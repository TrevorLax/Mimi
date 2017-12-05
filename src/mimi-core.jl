abstract ComponentState

type ComponentInstanceInfo
    name::Symbol
    component_type::DataType
    offset::Int
    final::Int
end

abstract Parameter

type ScalarModelParameter <: Parameter
    value
end

type InternalParameterConnection
    source_variable_name::Symbol
    source_component_name::Symbol
    target_parameter_name::Symbol
    target_component_name::Symbol
    ignoreunits::Bool
    backup # either nothing, or a Symbol matching the name of the external parameter to be used as backup data
    function InternalParameterConnection(src_var::Symbol, src_comp::Symbol, target_par::Symbol, target_comp::Symbol, ignoreunits::Bool, backup::Union{Symbol, Void}=nothing)
        ipc = new(src_var, src_comp, target_par, target_comp, ignoreunits, backup)
        return ipc
    end
end

type ExternalParameterConnection
    component_name::Symbol
    param_name::Symbol #name of the parameter in the component
    external_parameter::Symbol #name of the parameter stored in m.external_parameters
end

type ModelInstance
    components::OrderedDict{Symbol, ComponentState}
    internal_parameter_connections::Array{InternalParameterConnection, 1}
    offsets::Array{Int, 1} # in order corresponding with components
    final_times::Array{Int, 1}
end

type ArrayModelParameter <: Parameter
    values
    dims::Vector{Symbol} #if empty, we don't have the dimensions' name information

    function ArrayModelParameter(values, dims::Vector{Symbol})
        amp = new()
        amp.values = values
        amp.dims = dims
        return amp
    end
end

type Model
    indices_counts::Dict{Symbol,Int}
    indices_values::Dict{Symbol,Vector{Any}}
    time_labels::Vector
    external_parameters::Dict{Symbol,Parameter}
    numberType::DataType
    internal_parameter_connections::Array{InternalParameterConnection, 1}
    external_parameter_connections::Array{ExternalParameterConnection, 1}
    components2::OrderedDict{Symbol, ComponentInstanceInfo}
    mi::Nullable{ModelInstance}

    function Model(numberType::DataType=Float64)
        m = new()
        m.indices_counts = Dict{Symbol,Int}()
        m.indices_values = Dict{Symbol, Vector{Any}}()
        # m.time_labels = Vector{Any}()
        m.external_parameters = Dict{Symbol, Parameter}()
        m.numberType = numberType
        m.internal_parameter_connections = Array{InternalParameterConnection,1}()
        m.external_parameter_connections = Array{ExternalParameterConnection, 1}()
        m.components2 = OrderedDict{Symbol, ComponentInstanceInfo}()
        m.mi = Nullable{ModelInstance}()
        return m
    end
end

"""
    components(m::Model)

List all the components in model `m`.
"""
function components(m::Model)
    collect(keys(m.components2))
end

# Return the MetaComponent for a given component
function getmetainfo(m::Model, componentname::Symbol)
    meta = metainfo.getallcomps()
    meta_module_name = Symbol(m.components2[componentname].component_type.name.module)
    meta_component_name = m.components2[componentname].component_type.name.name
    return meta[(meta_module_name, meta_component_name)]
end

"""
    variables(m::Model, componentname::Symbol)

List all the variables of `componentname` in model `m`.
"""
function variables(m::Model, componentname::Symbol)
    c = getmetainfo(m, componentname)
    collect(keys(c.variables))
end

"""
    variables(mi::ModelInstance, componentname::Symbol)

List all the variables of `componentname` in the ModelInstance 'mi'.
NOTE: this variables function does NOT take in Nullable instances
"""
function variables(mi::ModelInstance, componentname::Symbol)
    return fieldnames(mi.components[componentname].Variables)
end

# helper function for setindix; used to determine if the provided time values are a uniform range.
function isuniform(values::Vector)
    if length(values)==1 || length(values)==2
        return true
    end

    stepsize = values[2]-values[1]
    for i in 3:length(values)
        if (values[i]-values[i-1]) != stepsize
            return false
        end
    end

    return true
end
"""
    setindex(m::Model, name::Symbol, count::Int)

Set the values of `Model`'s' index `name` to integers 1 through `count`.
"""
function setindex(m::Model, name::Symbol, count::Int)
    m.indices_counts[name] = count
    m.indices_values[name] = collect(1:count)
    m.time_labels = Vector()
    nothing
end

"""
    setindex{T}(m::Model, name::Symbol, values::Vector{T})

Set the values of `Model`'s index `name` to `values`.
"""
function setindex{T}(m::Model, name::Symbol, values::Vector{T})
    m.indices_counts[name] = length(values)
    if name==:time && !isuniform(values)
        m.time_labels = values
        m.indices_values[name] = collect(1:length(values))
    else
        m.indices_values[name] = copy(values)
        m.time_labels = Vector()
    end
    nothing
end

"""
    setindex{T}(m::Model, name::Symbol, valuerange::Range{T})

Set the values of `Model`'s index `name` to the values in the given range `valuerange`.
"""
function setindex{T}(m::Model, name::Symbol, valuerange::Range{T})
    m.indices_counts[name] = length(valuerange)
    m.indices_values[name] = Vector{T}(valuerange)
    m.time_labels = Vector()
    nothing
end

"""
    addcomponent(m::Model, t, name::Symbol=t.name.name; before=nothing,after=nothing)

Add a component of type t to a model.
"""
function addcomponent(m::Model, t, name::Symbol=t.name.name; start=nothing, final=nothing, before=nothing,after=nothing)
    # check that start and final are within the model's time index range
    time_index = m.indices_values[:time]

    if start == nothing
        start = time_index[1]
    elseif start < time_index[1]
        error("Cannot add component ", name, " with start time before start of model's time index range.")
    end

    if final == nothing
        final = time_index[end]
    elseif final > time_index[end]
        error("Cannot add component ", name, " with final time after end of model's time index range.")
    end


    if before!=nothing && after!=nothing
        error("Can only specify before or after parameter")
    end

    #checking if component being added already exists
    for i in keys(m.components2)
        if i==name
            error("You cannot add two components of the same name: ", i)
        end
    end

    if before!=nothing
        newcomponents2 = OrderedDict{Symbol, ComponentInstanceInfo}()
        before_exists = false
        for i in keys(m.components2)
            if i==before
                before_exists = true
                newcomponents2[name] = ComponentInstanceInfo(name, t, start, final)
            end
            newcomponents2[i] = m.components2[i]
        end
        if !before_exists
            error("Component to add before does not exist: ", before)
        end
        m.components2 = newcomponents2
    elseif after!=nothing
        newcomponents2 = OrderedDict{Symbol, ComponentInstanceInfo}()
        after_exists = false
        for i in keys(m.components2)
            newcomponents2[i] = m.components2[i]
            if i==after
                after_exists = true
                newcomponents2[name] = ComponentInstanceInfo(name, t, start, final)
            end
        end
        if !after_exists
            error("Component to add after does not exist: ", after)
        end
        m.components2 = newcomponents2

    else
        m.components2[name] = ComponentInstanceInfo(name, t, start, final)
    end
    m.mi = Nullable{ModelInstance}()
    ComponentReference(m, name)
end

import Base.delete!

"""
    delete!(m::Model, component::Symbol

Delete a component from a model, by name.
"""
function delete!(m::Model, component::Symbol)
    if !(component in keys(m.components2))
        error("Cannot delete '$component' from model; component does not exist.")
    end

    delete!(m.components2, component)

    ipc_filter = x -> x.source_component_name!=component && x.target_component_name!=component
    filter!(ipc_filter, m.internal_parameter_connections)

    epc_filter = x -> x.component_name!=component
    filter!(epc_filter, m.external_parameter_connections)

    m.mi = Nullable{ModelInstance}()
end

"""
    setparameter(m::Model, component::Symbol, name::Symbol, value, dims)

Set the parameter of a component in a model to a given value. Value can by a scalar,
an array, or a NamedAray. Optional argument 'dims' is a list of the dimension names of
the provided data, and will be used to check that they match the model's index labels.
"""
function setparameter(m::Model, component::Symbol, name::Symbol, value, dims=nothing)
    # perform possible dimension and labels checks
    if isa(value, NamedArray)
        dims = dimnames(value)
    end
    if dims!=nothing
        check_parameter_dimensions(m, value, dims, name)
    end
    # now set the parameter
    comp_param_dims = getmetainfo(m, component).parameters[name].dimensions
    if length(comp_param_dims) > 0 # array parameter case
        value = convert(Array{m.numberType}, value) # converts the number type and also if it's a NamedArray it gets converted to Array
        if comp_param_dims[1] == :time
            offset = m.components2[component].offset
            duration = getduration(m.indices_values)
            T = eltype(value)
            if length(comp_param_dims)==1
                values = TimestepVector{T, offset, duration}(value)
            elseif length(comp_param_dims)==2
                values = TimestepMatrix{T, offset, duration}(value)
            else
                values = value
            end
        else
            values = value
        end
        set_external_array_parameter(m, name, values, dims)
    else # scalar parameter case
        set_external_scalar_parameter(m, name, value)
    end

    connectparameter(m, component, name, name)
    m.mi = Nullable{ModelInstance}()
    nothing
end

function check_parameter_dimensions(m::Model, value::AbstractArray, dims::Vector, name::Symbol)
    for dim in dims
        if dim in keys(m.indices_values)
            if isa(value, NamedArray)
                labels = names(value, findnext(dims, dim, 1))
                for i in collect(1:1:length(labels))
                    if !(labels[i] == m.indices_values[dim][i])
                        error(string("Parameter labels for ", dim, " dimension in ", name," parameter do not match model's indices values"))
                    end
                end
            end
        else
            error(string("Dimension ", dim, " in parameter ", name, " not found in model's dimensions"))
        end
    end
end

"""
Removes any parameter connections for a given parameter in a given component.
"""
function disconnect(m::Model, component::Symbol, parameter::Symbol)
    filter!(x->!(x.target_component_name==component && x.target_parameter_name==parameter), m.internal_parameter_connections)
    filter!(x->!(x.component_name==component && x.param_name==parameter), m.external_parameter_connections)
end

"""
    connectparameter(m::Model, component::Symbol, name::Symbol, parametername::Symbol)

Connect a parameter in a component to an external parameter.
"""
function connectparameter(m::Model, component::Symbol, name::Symbol, parametername::Symbol)
    p = m.external_parameters[parametername]

    if isa(p, ArrayModelParameter)
        checklabels(m, component, name, p)
    end

    disconnect(m, component, name)

    x = ExternalParameterConnection(component, name, parametername)
    push!(m.external_parameter_connections, x)

    nothing
end

function checklabels(m::Model, component::Symbol, name::Symbol, p::ArrayModelParameter)
    metacomp = getmetainfo(m, component)
    if !(eltype(p.values) <: metacomp.parameters[name].datatype)
        error(string("Mismatched datatype of parameter connection. Component: ", component, ", Parameter: ", name))
    elseif !(isempty(p.dims))
        if !(size(p.dims) == size(metacomp.parameters[name].dimensions))
            error(string("Mismatched dimensions of parameter connection. Component: ", component, ", Parameter: ", name))
        end
    end

    # Return early if it's a ConnectorComp so that we don't check the sizes, because they will not match.
    if metacomp.component_name == :ConnectorCompVector || metacomp.component_name == :ConnectorCompMatrix
        return nothing
    end

    comp_dims = metacomp.parameters[name].dimensions
    for (i, dim) in enumerate(comp_dims)
        if isa(dim, Symbol)
            if !(length(m.indices_values[dim])==size(p.values)[i])
                error(string("Mismatched data size for a parameter connection. Component: ", component, ", Parameter: ", name))
            end
        end
    end
end

"""
    set_external_array_parameter(m::Model, name::Symbol, value::TimestepVector, dims)

Adds a one dimensional time-indexed array parameter to the model.
"""
function set_external_array_parameter(m::Model, name::Symbol, value::TimestepVector, dims)
    p = ArrayModelParameter(value, [:time])
    m.external_parameters[name] = p
end

"""
    set_external_array_parameter(m::Model, name::Symbol, value::TimestepMatrix, dims)

Adds a two dimensional time-indexed array parameter to the model.
"""
function set_external_array_parameter(m::Model, name::Symbol, value::TimestepMatrix, dims)
    p = ArrayModelParameter(value, (dims!=nothing)?(dims):(Vector{Symbol}()))
    m.external_parameters[name] = p
end

"""
    set_external_array_parameter(m::Model, name::Symbol, value::AbstractArray, dims)

Add an array type parameter to the model.
"""
function set_external_array_parameter(m::Model, name::Symbol, value::AbstractArray, dims)
    if !(typeof(value) <: Array{m.numberType})
        # Need to force a conversion (simple convert may alias in v0.6)
        value = Array{m.numberType}(value)
    end
    p = ArrayModelParameter(value, (dims!=nothing)?(dims):(Vector{Symbol}()))
    m.external_parameters[name] = p
end

"""
    set_external_scalar_parameter(m::Model, name::Symbol, value::Any)

Add a scalar type parameter to the model.
"""
function set_external_scalar_parameter(m::Model, name::Symbol, value::Any)
    if typeof(value) <: AbstractArray
        value = convert(Array{m.numberType}, value)
    end
    p = ScalarModelParameter(value)
    m.external_parameters[name] = p
end

"""
    connectparameter(m::Model, target_component::Symbol, target_name::Symbol, source_component::Symbol, source_name::Symbol; ignoreunits::Bool=false)

Bind the parameter of one component to a variable in another component.
"""
function connectparameter(m::Model, target_component::Symbol, target_param::Symbol, source_component::Symbol, source_var::Symbol; ignoreunits::Bool=false)

    # Check the units, if provided
    if !ignoreunits &&
        !unitcheck(getmetainfo(m, target_component).parameters[target_param].unit,
                   getmetainfo(m, source_component).variables[source_var].unit)
        error("Units of $source_component.$source_var do not match $target_component.$target_param.")
    end

    # remove any existing connections for this target component and parameter
    disconnect(m, target_component, target_param)

    curr = InternalParameterConnection(source_var, source_component, target_param, target_component, ignoreunits)
    push!(m.internal_parameter_connections, curr)

    nothing
end

"""
    connectparameter(m::Model, target::Pair{Symbol, Symbol}, source::Pair{Symbol, Symbol}; ignoreunits::Bool=false)

Bind the parameter of one component to a variable in another component.
"""
function connectparameter(m::Model, target::Pair{Symbol, Symbol}, source::Pair{Symbol, Symbol}; ignoreunits::Bool=false)
    connectparameter(m, target[1], target[2], source[1], source[2]; ignoreunits=ignoreunits)
end

function connectparameter(m::Model, target::Pair{Symbol, Symbol}, source::Pair{Symbol, Symbol}, backup::Array; ignoreunits::Bool=false)
    connectparameter(m, target[1], target[2], source[1], source[2], backup; ignoreunits=ignoreunits)
end

function connectparameter(m::Model, target_component::Symbol, target_param::Symbol, source_component::Symbol, source_var::Symbol, backup::Array; ignoreunits::Bool=false)
    # If value is a NamedArray, we can check if the labels match
    if isa(backup, NamedArray)
        dims = dimnames(backup)
        check_parameter_dimensions(m, backup, dims, name)
    else
        dims = nothing
    end

    # Check that the backup value is the right size
    if getspan(m, target_component) != size(backup)[1]
        error("Backup data must span the whole length of the component.")
    end

    # some other check for second dimension??

    comp_param_dims = getmetainfo(m, target_component).parameters[target_param].dimensions
    backup = convert(Array{m.numberType}, backup) # converts the number type, and also if it's a NamedArray it gets converted to Array
    offset = m.components2[target_component].offset
    duration = getduration(m.indices_values)
    T = eltype(backup)
    if length(comp_param_dims)==1
        values = TimestepVector{T, offset, duration}(backup)
    elseif length(comp_param_dims)==2
        values = TimestepMatrix{T, offset, duration}(backup)
    else
        values = backup
    end
    set_external_array_parameter(m, target_param, values, dims)

    if !ignoreunits &&
        !unitcheck(getmetainfo(m, target_component).parameters[target_param].unit,
                   getmetainfo(m, source_component).variables[source_var].unit)
        error("Units of $source_component.$source_name do not match $target_component.$target_name.")
    end

    # remove any existing connections for this target component and parameter
    disconnect(m, target_component, target_param)

    curr = InternalParameterConnection(source_var, source_component, target_param, target_component, ignoreunits, target_param)
    push!(m.internal_parameter_connections, curr)

    nothing
end

# Default string, string unit check function
function unitcheck(one::AbstractString, two::AbstractString)
    # True if and only if they match
    return one == two
end

# Return the number of timesteps a given component in a model will run for.
function getspan(m::Model, comp::Symbol)
    duration = getduration(m.indices_values)
    start = m.components2[comp].offset
    final = m.components2[comp].final
    return Int((final - start) / duration + 1)
end

"""
    update_external_parameter(m::Model, name::Symbol, value)

Update the value of an external model parameter, referenced by name.
"""
function update_external_parameter(m::Model, name::Symbol, value)
    if !(name in keys(m.external_parameters))
        error("Cannot update parameter; $name not found in model's external parameters.")
    end

    param = m.external_parameters[name]

    if isa(param, ScalarModelParameter)
        if !(typeof(value) <: typeof(param.value))
            try
                value = convert(typeof(param.value), value)
            catch e
                error("Cannot update parameter $name; expected type $(typeof(param.value)) but got $(typeof(value)).")
            end
        elseif size(value) != size(param.value)
            error("Cannot update parameter $name; expected array of size $(size(param.value)) but got array of size $(size(value)).")
        else
            param.value = value
        end
    else # ArrayModelParameter
        if !(typeof(value) <: AbstractArray)
            error("Cannot update an array parameter $name with a scalar value.")
        elseif size(value) != size(param.values)
            error("Cannot update parameter $name; expected array of size $(size(param.values)) but got array of size $(size(value)).")
        elseif !(eltype(value) <: eltype(param.values))
            try
                value = convert(Array{eltype(param.values)}, value)
            catch e
                error("Cannot update parameter $name; expected array of type $(eltype(param.values)) but got $(eltype(value)).")
            end
        else # perform the update
            if isa(param.values, TimestepVector) || isa(param.values, TimestepMatrix)
                param.values.data = value
            else
                param.values = value
            end
        end
    end
    m.mi = Nullable{ModelInstance}()
end

"""
    setleftoverparameters(m::Model, parameters::Dict{Any,Any})

Set all the parameters in a model that don't have a value and are not connected
to some other component to a value from a dictionary. This method assumes the dictionary
keys are strings that match the names of unset parameters in the model.
"""
function setleftoverparameters(m::Model, parameters::Dict{Any,Any})
    parameters = Dict(lowercase(k)=>v for (k, v) in parameters)
    leftovers = get_unconnected_parameters(m)
    for (comp, p) in leftovers
        if !(p in keys(m.external_parameters)) # then we need to set the external parameter
            value = parameters[lowercase(string(p))]
            comp_param_dims = getmetainfo(m, comp).parameters[p].dimensions
            if length(comp_param_dims)==0 #scalar case
                set_external_scalar_parameter(m, p, value)
            else #array case
                value = convert(Array{m.numberType}, value)
                offset = m.indices_values[:time][1]
                duration = getduration(m.indices_values)
                T = eltype(value)
                if length(comp_param_dims)==1 && comp_param_dims[1]==:time
                    values = TimestepVector{T, offset, duration}(value)
                elseif length(comp_param_dims)==2 && comp_param_dims[1]==:time
                    values = TimestepMatrix{T, offset, duration}(value)
                else
                    values = value
                end
                set_external_array_parameter(m, p, values, nothing)
            end
        end
        connectparameter(m, comp, p, p)
    end
    nothing
end

"""
Return list of parameters that have been set for component c in model m.
"""
function get_set_parameters(m::Model, c::ComponentInstanceInfo)
    ext_connections = filter(x->x.component_name==c.name, m.external_parameter_connections)
    ext_set_params = map(x->x.param_name, ext_connections)

    int_connections = filter(x->x.target_component_name==c.name, m.internal_parameter_connections)
    int_set_params = map(x->x.target_parameter_name, int_connections)

    return union(ext_set_params, int_set_params)
end

"""
Return a list of all parameter names for a given component in a model m.
"""
function get_parameter_names(m::Model, component::ComponentInstanceInfo)
    _dict = Mimi.metainfo.getallcomps()
    _module = module_name(component.component_type.name.module)
    _metacomponent = _dict[(_module, component.component_type.name.name)]
    return keys(_metacomponent.parameters)
end

# returns the {name:parameter} dictionary
function get_parameters(m::Model, component::ComponentInstanceInfo)
    _dict = Mimi.metainfo.getallcomps()
    _module = module_name(component.component_type.name.module)
    _metacomponent = _dict[(_module, component.component_type.name.name)]
    return _metacomponent.parameters
end

function getindex(m::Model, component::Symbol, name::Symbol)
    return getindex(get(m.mi), component, name)
end

function getindex(mi::ModelInstance, component::Symbol, name::Symbol)
    if !(component in keys(mi.components))
        error("Component does not exist in current model")
    end
    if name in fieldnames(mi.components[component].Variables)
        v = getfield(mi.components[component].Variables, name)
        if isa(v, TimestepVector) || isa(v, TimestepMatrix)
            return v.data
        else
            return v
        end
    elseif name in fieldnames(mi.components[component].Parameters)
        p = getfield(mi.components[component].Parameters, name)
        if isa(p, TimestepVector) || isa(p, TimestepMatrix)
            return p.data
        else
            return p
        end
    else
        error(string(name, " is not a parameter or a variable in component ", component, "."))
    end
end

"""
    getindexcount(m::Model, i::Symbol)

Returns the size of index i in model m.
"""
function getindexcount(m::Model, i::Symbol)
    return m.indices_counts[i]
end

"""
    getindexvalues(m::Model, i::Symbol)

Return the values of index i in model m.
"""
function getindexvalues(m::Model, i::Symbol)
    return m.indices_values[i]
end

"""
    getindexlabels(m::Model, component::Symbol, x::Symbol)

Return the index labels of the variable or parameter in the given component.
"""
function getindexlabels(m::Model, component::Symbol, x::Symbol)
    metacomp = getmetainfo(m,component)
    if x in keys(metacomp.variables)
        return metacomp.variables[x].dimensions
    elseif x in keys(metacomp.parameters)
        return metacomp.parameters[x].dimensions
    else
        error(string("Cannot access dimensions; ", x, " is not a variable or a parameter in component ", component, "."))
    end
end

"""
    getdataframe(m::Model, componentname::Symbol, name::Symbol)

Return the values for variable `name` in `componentname` of model `m` as a DataFrame.
"""
function getdataframe(m::Model, componentname::Symbol, name::Symbol)
    if isnull(m.mi)
        error("Cannot get dataframe, model has not been built yet")
    elseif !(name in variables(m, componentname))
        error("Cannot get dataframe; variable $name not in component $componentname")
    else
        return getdataframe(m, get(m.mi), componentname, name)
    end
end


function getdataframe(m::Model, mi::ModelInstance, componentname::Symbol, name::Symbol)
    comp_type = typeof(mi.components[componentname])

    meta_module_name = Symbol(supertype(comp_type).name.module)
    meta_component_name = Symbol(supertype(comp_type).name.name)

    vardiminfo = getdiminfoforvar((meta_module_name,meta_component_name), name)

    if length(vardiminfo)==0
        return mi[componentname, name]
    end

    df = DataFrame()

    values = ((isempty(m.time_labels) || vardiminfo[1]!=:time) ? m.indices_values[vardiminfo[1]] : m.time_labels)
    if vardiminfo[1]==:time
        comp_start = m.components2[componentname].offset
        comp_final = m.components2[componentname].final
        start = findfirst(values, comp_start)
        final = findfirst(values, comp_final)
        num = getspan(m, componentname)
    end

    if length(vardiminfo)==1
        df[vardiminfo[1]] = values
        if vardiminfo[1]==:time
            df[name] = vcat(repeat([NaN], inner=start-1), mi[componentname, name], repeat([NaN], inner=length(values)-final))
        else
            df[name] = mi[componentname, name]
        end
        return df
    elseif length(vardiminfo)==2
        dim2 = length(m.indices_values[vardiminfo[2]])
        dim1 = length(m.indices_values[vardiminfo[1]])
        df[vardiminfo[1]] = repeat(values, inner=[dim2])
        df[vardiminfo[2]] = repeat(m.indices_values[vardiminfo[2]], outer=[dim1])

        data = m[componentname, name]
        if vardiminfo[1]==:time
            top = fill(NaN, (start-1, dim2))
            bottom = fill(NaN, (dim1-final, dim2))
            data = vcat(top, data, bottom)
        end
        df[name] = cat(1,[vec(data[i,:]) for i=1:dim1]...)

        return df
    else
        error("Not yet implemented")
    end
end

"""
    getdataframe(m::Model, comp_name_pairs::Pair(componentname::Symbol => name::Symbol)...)
    getdataframe(m::Model, comp_name_pairs::Pair(componentname::Symbol => (name::Symbol, name::Symbol...)...)

Return the values for each variable `name` in each corresponding `componentname` of model `m` as a DataFrame.
"""
function getdataframe(m::Model, comp_name_pairs::Pair...)
    if isnull(m.mi)
        error("Cannot get dataframe, model has not been built yet")
    else
        return getdataframe(m, get(m.mi), comp_name_pairs)
    end
end


function getdataframe(m::Model, mi::ModelInstance, comp_name_pairs::Tuple)
    #Make sure tuple passed in is not empty
    if length(comp_name_pairs) == 0
        error("Cannot get data frame, did not specify any componentname(s) and variable(s)")
    end

    # Get the base value of the number of dimensions from the first componentname and name pair association
    firstpair = comp_name_pairs[1]
    componentname = firstpair[1]
    name = firstpair[2]
    if isa(name, Tuple)
        name = name[1]
    end

    if !(name in variables(m, componentname))
        error("Cannot get dataframe; variable $name not in component $componentname")
    end

    vardiminfo = getvardiminfo(mi, componentname, name)
    num_dim = length(vardiminfo)

    #Initialize dataframe depending on num dimensions
    df = DataFrame()
    values = ((isempty(m.time_labels) || vardiminfo[1]!=:time) ? m.indices_values[vardiminfo[1]] : m.time_labels)
    if num_dim == 1
        df[vardiminfo[1]] = values
    elseif num_dim == 2
        dim1 = length(m.indices_values[vardiminfo[1]])
        dim2 = length(m.indices_values[vardiminfo[2]])
        df[vardiminfo[1]] = repeat(values, inner=[dim2])
        df[vardiminfo[2]] = repeat(m.indices_values[vardiminfo[2]],outer=[dim1])
    end

    # Iterate through all the pairs; always check for each variable that the number of dimensions matches that of the first
    for pair in comp_name_pairs
        componentname = pair[1]
        name = pair[2]

        if isa(name, Tuple)
            for comp_var in name
                if !(comp_var in variables(m, componentname))
                    error("Cannot get dataframe; variable $comp_var not in component $componentname")
                end

                vardiminfo = getvardiminfo(mi, componentname, comp_var)
                if vardiminfo[1]==:time
                    comp_start = m.components2[componentname].offset
                    comp_final = m.components2[componentname].final
                    start = findfirst(values, comp_start)
                    final = findfirst(values, comp_final)
                    num = getspan(m, componentname)
                end

                if !(length(vardiminfo) == num_dim)
                    error(string("Not all components have the same number of dimensions"))
                end

                if (num_dim==1)
                    if vardiminfo[1]==:time
                        df[comp_var] = vcat(repeat([NaN], inner=start-1), mi[componentname, comp_var], repeat([NaN], inner=length(values)-final))
                    else
                        df[comp_var] = mi[componentname, comp_var]
                    end
                elseif (num_dim == 2)
                    data = m[componentname, comp_var]
                    if vardiminfo[1]==:time
                        top = fill(NaN, (start-1, dim2))
                        bottom = fill(NaN, (dim1-final, dim2))
                        data = vcat(top, data, bottom)
                    end
                    df[comp_var] = cat(1,[vec(data[i,:]) for i=1:dim1]...)
                end
            end

        elseif (isa(name, Symbol))
            if !(name in variables(m, componentname))
                error("Cannot get dataframe; variable $name not in component $componentname")
            end

            vardiminfo = getvardiminfo(mi, componentname, name)
            if vardiminfo[1]==:time
                comp_start = m.components2[componentname].offset
                comp_final = m.components2[componentname].final
                start = findfirst(values, comp_start)
                final = findfirst(values, comp_final)
                num = getspan(m, componentname)
            end

            if !(length(vardiminfo) == num_dim)
                error(string("Not all components have the same number of dimensions"))
            end
            if (num_dim==1)
                if vardiminfo[1]==:time
                    df[name] = vcat(repeat([NaN], inner=start-1), mi[componentname, name], repeat([NaN], inner=length(values)-final))
                else
                    df[name] = mi[componentname, name]
                end
            elseif (num_dim == 2)
                data = m[componentname, name]
                if vardiminfo[1]==:time
                    top = fill(NaN, (start-1, dim2))
                    bottom = fill(NaN, (dim1-final, dim2))
                    data = vcat(top, data, bottom)
                end
                df[name] = cat(1,[vec(data[i,:]) for i=1:dim1]...)
            end
        else
            error(string("Name value for variable(s) in a component, ", componentname, " was neither a tuple nor a Symbol."))
        end
    end

    return df
end


function getvardiminfo(mi::ModelInstance, componentname::Symbol, name::Symbol)
    if !(componentname in keys(mi.components))
        error("Component not found model components")
    end
    comp_type = typeof(mi.components[componentname])

    meta_module_name = Symbol(supertype(comp_type).name.module)
    meta_component_name = Symbol(supertype(comp_type).name.name)

    vardiminfo = getdiminfoforvar((meta_module_name,meta_component_name), name)
    return vardiminfo
end

import Base.show
show(io::IO, a::ComponentState) = print(io, "ComponentState")

"""
    get_unconnected_parameters(m::Model)

Return a list of tuples (componentname, parametername) of parameters
that have not been connected to a value in the model.
"""
function get_unconnected_parameters(m::Model)
    unset_params = Array{Tuple{Symbol,Symbol}, 1}()
    for (name, c) in m.components2
        params = get_parameter_names(m, c)
        set_params = get_set_parameters(m, c)
        append!(unset_params, map(x->(name, x), setdiff(params, set_params)))
    end
    return unset_params
end

function build(m::Model)
    #check if all parameters are set
    unset = get_unconnected_parameters(m)
    if !isempty(unset)
        msg = "Cannot build model; the following parameters are unset: "
        for p in unset
            msg = string(msg, p, " ")
        end
        error(msg)
    end

    mi_connections = Array{InternalParameterConnection, 1}() # This is the list of internal connections that the ModelInstance will know about.
    mi_components = OrderedDict{Symbol, ComponentInstanceInfo}() # This is the ordered list of components (including hidden ConnectorComps) that the ModelInstance will use.
    backups = Array{Symbol, 1}() # This is the list of names of external parameters that the ConnectorComps will use as their :input2 parameters.
    num_connector_comps = 0
    duration = getduration(m.indices_values) # for now, all components have the same duration
    # Loop through the components and add necessary ConnectorComps.
    for c in values(m.components2)
        # first need to see if we need to add any connector components for this component
        int_connections = filter(x->x.target_component_name==c.name, m.internal_parameter_connections)
        need_connector_comps = filter(x->(x.backup != nothing), int_connections)
        for ipc in need_connector_comps
            num_connector_comps += 1
            push!(backups, ipc.backup)
            curr_name = Symbol("ConnectorComp$num_connector_comps")
            num_dims = length(size(m.external_parameters[ipc.backup].values))
            if num_dims == 1
                curr = ComponentInstanceInfo(curr_name, ConnectorCompVector, c.offset, c.final)
            elseif num_dims ==2
                curr = ComponentInstanceInfo(curr_name, ConnectorCompMatrix, c.offset, c.final)
            else
                error("Connector components for parameters with more than two dimensions not implemented.")
            end
            mi_components[curr_name] = curr # add the ConnectorComp to the ordered list of components
            push!(mi_connections, InternalParameterConnection(ipc.source_variable_name, ipc.source_component_name, :input1, curr_name, ipc.ignoreunits)) # add a new connection between source_component and the ConnectorComp
            push!(mi_connections, InternalParameterConnection(:output, curr_name, ipc.target_parameter_name, ipc.target_component_name, ipc.ignoreunits)) # add a new connection between ConnectorComp and target_component
        end

        # Now add the other InternalParameterConnections to the list of connections.
        for ipc in setdiff(int_connections, need_connector_comps)
            push!(mi_connections, ipc)
        end

        mi_components[c.name] = c # Order is imperitive: this component is added after any ConnectorComps were added.
    end

    # Now loop through and instantiate each component.
    builtComponents = OrderedDict{Symbol, ComponentState}()
    offsets = Array{Int, 1}()
    final_times = Array{Int, 1}()
    for c in values(mi_components) # loops through all ComponentInstanceInfos, including new ConnectorComps, in order.
        ext_connections = filter(x->x.component_name==c.name, m.external_parameter_connections)
        ext_params = map(x->x.param_name, ext_connections)
        # ext_params = Dict(x.param_name => x.external_parameter for x in ext_connections)

        int_connections = filter(x->x.target_component_name==c.name, mi_connections)
        int_params = Dict(x.target_parameter_name => x for x in int_connections)

        constructor = Expr(:call, c.component_type, m.numberType, :(Val{$(c.offset)}), :(Val{$duration}), :(Val{$(c.final)}))
        # for each parameter of component c, add the offset and duration as a parametric type to the constructor call for the component.
        for (pname, p) in get_parameters(m, c)
            if length(p.dimensions) > 0 && length(p.dimensions)<=2 && p.dimensions[1]==:time
                if pname==:input2 && (c.component_type == ConnectorCompVector || c.component_type == ConnectorCompMatrix)
                    offset = c.offset
                elseif pname in ext_params
                    offset = getoffset(m.external_parameters[pname].values)
                elseif pname in keys(int_params)
                    offset = mi_components[int_params[pname].source_component_name].offset
                else
                    error("unset paramter $pname; should be caught earlier")
                end
                push!(constructor.args, :(Val{$offset}))
                push!(constructor.args, :(Val{$duration}))
            end
        end

        push!(constructor.args, m.indices_counts)
        # println(constructor)

        comp = eval(eval(constructor))
        builtComponents[c.name] = comp

        push!(offsets, c.offset)
        push!(final_times, c.final)
    end

    # Make the internal parameter connections, including new hidden connections between ConnectorComps.
    for ipc in mi_connections
        c_target = builtComponents[ipc.target_component_name]
        c_source = builtComponents[ipc.source_component_name]
        setfield!(c_target.Parameters, ipc.target_parameter_name, getfield(c_source.Variables, ipc.source_variable_name))
    end

    # Make the external parameter connections.
    for x in m.external_parameter_connections
        param = m.external_parameters[x.external_parameter]
        if isa(param, ScalarModelParameter)
            setfield!(builtComponents[x.component_name].Parameters, x.param_name, param.value)
        else
            setfield!(builtComponents[x.component_name].Parameters, x.param_name, param.values)
        end
    end

    # Make the external parameter connections for the hidden ConnectorComps: connect each :input2 to its associated backup value.
    for i in 1:num_connector_comps
        setfield!(builtComponents[Symbol("ConnectorComp$i")].Parameters, :input2, m.external_parameters[backups[i]].values)
    end

    mi = ModelInstance(builtComponents, mi_connections, offsets, final_times)

    return mi
end

function getduration(indices_values)
    if length(indices_values[:time])>1
        return indices_values[:time][2]-indices_values[:time][1] #assumes that all timesteps of the model are the same length
    else
        return 1
    end
end

function makeclock(mi::ModelInstance, ntimesteps, indices_values)
    start = indices_values[:time][1]
    stop = indices_values[:time][min(length(indices_values[:time]),ntimesteps)]
    duration = getduration(indices_values)
    return Clock(start, stop, duration)
end

"""
    run(m::Model)

Run model `m` once.
"""
function run(m::Model;ntimesteps=typemax(Int))
    if length(m.components2) == 0
        error("Cannot run a model with no components.")
    end

    if isnull(m.mi)
        m.mi = Nullable{ModelInstance}(build(m))
    end
    run(get(m.mi), ntimesteps, m.indices_values)
end

function run(mi::ModelInstance, ntimesteps, indices_values)
    if length(mi.components) == 0
        error("Cannot run a model with no components.")
    end

    for (name,c) in mi.components
        resetvariables(c)
        update_scalar_parameters(mi, name)
        init(c)
    end

    components = [x for x in mi.components]
    newstyle = Array{Bool, 1}(length(components))
    offsets = mi.offsets
    final_times = mi.final_times

    for i in collect(1:length(components))
        c = components[i][2]
        newstyle[i] = method_exists(run_timestep, (typeof(c), Timestep))
    end

    clock = makeclock(mi, ntimesteps, indices_values)
    duration = getduration(indices_values)
    comp_clocks = [Clock(offsets[i], final_times[i], duration) for i in collect(1:length(components))]

    while !finished(clock)
        for (i, (name, c)) in enumerate(components)
            if gettime(clock) >= offsets[i] && gettime(clock) <= final_times[i]
                update_scalar_parameters(mi, name)
                if newstyle[i]
                    run_timestep(c, gettimestep(comp_clocks[i]))
                    move_forward(comp_clocks[i])
                else
                    run_timestep(c, gettimeindex(clock)) #int version (old way)
                end
            end
        end
        move_forward(clock)
    end
end

function update_scalar_parameters(mi::ModelInstance, c::Symbol)
    for x in get_connections(mi, c, :incoming)
        c_target = mi.components[x.target_component_name]
        c_source = mi.components[x.source_component_name]
        setfield!(c_target.Parameters, x.target_parameter_name, getfield(c_source.Variables, x.source_variable_name))
    end
end


# function update_scalar_parameters(mi::ModelInstance)
#     #this function is bad!! doesn't necessarilly update scalars in the correct order
#     for x in mi.internal_parameter_connections
#         c_target = mi.components[x.target_component_name]
#         c_source = mi.components[x.source_component_name]
#         setfield!(c_target.Parameters, x.target_parameter_name, getfield(c_source.Variables, x.source_variable_name))
#     end
# end


# function run_timestep(s, t)
#     typeofs = typeof(s)
#     println("Generic run_timestep called for $typeofs.")
# end

function init(s)
end

function resetvariables(s)
    typeofs = typeof(s)
    println("Generic resetvariables called for $typeofs.")
end

function getdiminfoforvar(s, name)
    meta = metainfo.getallcomps()
    meta[s].variables[name].dimensions
end

function getvpd(s)
    return s.Variables, s.Parameters, s.Dimensions
end

# Helper function for macro: collects all the keyword arguments in a function call to a dictionary.
function collectkw(args::Vector{Any})
    kws = Dict{Symbol, Any}()
    for arg in args
        if isa(arg, Expr) && arg.head == :kw
            kws[arg.args[1]] = arg.args[2]
        end
    end

    kws
end

"""
    @defcomp name begin

Define a new component.
"""
macro defcomp(name, ex)
    resetvarsdef = Expr(:block)

    metavardef = Expr(:block)
    metapardef = Expr(:block)
    metadimdef = Expr(:block)

    numarrayparams = 0

    for line in ex.args
        if line.head==:(=) && line.args[2].head==:call && line.args[2].args[1]==:Index
            dimensionName = line.args[1]

            push!(metadimdef.args, :(metainfo.adddimension(module_name(current_module()), $(Expr(:quote,name)), $(QuoteNode(dimensionName)) )))
        elseif line.head==:(=) && line.args[2].head==:call && line.args[2].args[1]==:Parameter
            if isa(line.args[1], Symbol)
                parameterName = line.args[1]
                parameterType = :Number
            elseif line.args[1].head==:(::)
                parameterName = line.args[1].args[1]
                parameterType = line.args[1].args[2]
            else
                error()
            end

            kws = collectkw(line.args[2].args)

            # Get description and unit, if provided
            description = get(kws, :description, "")
            unit = get(kws, :unit, "")

            if haskey(kws, :index)
                parameterIndex = kws[:index].args

                if length(parameterIndex)<=2 && parameterIndex[1]==:time
                    numarrayparams += 1
                end

                pardims = Array(Any, 0)
                for l in parameterIndex
                    push!(pardims, l)
                end

                push!(metapardef.args, :(metainfo.set_external_parameter(module_name(current_module()), $(Expr(:quote,name)), $(QuoteNode(parameterName)), $(esc(parameterType)), $(pardims), $(description), $(unit))))
            else
                push!(metapardef.args, :(metainfo.set_external_parameter(module_name(current_module()), $(Expr(:quote,name)), $(QuoteNode(parameterName)), $(esc(parameterType)), [], $(description), $(unit))))
            end
        elseif line.head==:(=) && line.args[2].head==:call && line.args[2].args[1]==:Variable
            if isa(line.args[1], Symbol)
                variableName = line.args[1]
                variableType = :Number
            elseif line.args[1].head==:(::)
                variableName = line.args[1].args[1]
                variableType = line.args[1].args[2]
            else
                error()
            end

            kws = collectkw(line.args[2].args)

            # Get description and unit, if provided
            description = get(kws, :description, "")
            unit = get(kws, :unit, "")

            if haskey(kws, :index)
                variableIndex = kws[:index].args

                vardims = Array(Any, 0)
                for l in variableIndex
                    push!(vardims, l)
                end

                push!(metavardef.args, :(metainfo.addvariable(module_name(current_module()), $(Expr(:quote,name)), $(QuoteNode(variableName)), $(esc(variableType)), $(vardims), $(description), $(unit))))

                if variableType==:Number
                    push!(resetvarsdef.args,:($(esc(Symbol("fill!")))(s.Variables.$(variableName),$(esc(Symbol("NaN"))))))
                end
            else
                push!(metavardef.args, :(metainfo.addvariable(module_name(current_module()), $(Expr(:quote,name)), $(QuoteNode(variableName)), $(esc(variableType)), [], $(description), $(unit))))

                if variableType==:Number
                    push!(resetvarsdef.args,:(s.Variables.$(variableName) = $(esc(Symbol("NaN")))))
                end
            end
        elseif line.head==:line
        else
            error("Unknown expression.")
        end
    end

    module_def = :(eval(current_module(), :(module temporary_name end)))
    module_def.args[3].args[1].args[2] = Symbol(string("_mimi_implementation_", name))

    call_expr = Expr(:call,
        Expr(:curly,
            Expr(:., Expr(:., Expr(:., :Main, QuoteNode(Symbol(current_module()))), QuoteNode(Symbol(string("_mimi_implementation_", name)))), QuoteNode(Symbol(string(name,"Impl")))),
            :T, :OFFSET, :DURATION, :FINAL
            ),
        :indices
        )

    callsignature = Expr(:call, Expr(:curly, Symbol(name), :T, :OFFSET, :DURATION, :FINAL), :(::Type{T}), :(::Type{Val{OFFSET}}),:(::Type{Val{DURATION}}),:(::Type{Val{FINAL}}))
    for i in 1:numarrayparams
        push!(call_expr.args[1].args, Symbol("OFFSET$i"))
        push!(call_expr.args[1].args, Symbol("DURATION$i"))

        push!(callsignature.args[1].args, Symbol("OFFSET$i"))
        push!(callsignature.args[1].args, Symbol("DURATION$i"))
        push!(callsignature.args, :(::Type{Val{$(Symbol("OFFSET$i"))}}))
        push!(callsignature.args, :(::Type{Val{$(Symbol("DURATION$i"))}}))

    end
    push!(callsignature.args, :indices)
    # println(call_expr)
    # println(callsignature)
    # println(Expr(:function, callsignature, call_expr))

    x = quote

        abstract $(esc(Symbol(name))) <: Mimi.ComponentState

        import Mimi.run_timestep
        import Mimi.init
        import Mimi.resetvariables

        function $(esc(Symbol("resetvariables")))(s::$(esc(Symbol(name))))
            $(resetvarsdef)
        end

        metainfo.addcomponent(module_name(current_module()), $(Expr(:quote,name)))
        $(metavardef)
        $(metapardef)
        $(metadimdef)

        $(module_def)
        eval($(esc(Symbol(string("_mimi_implementation_", name)))), metainfo.generate_comp_expressions(module_name(current_module()), $(Expr(:quote,name))))

        # callsignature.args[1].args[1] = $esc(Symbol(name)) # how to do this?
        $(Expr(:function, Expr(:call, Expr(:curly, esc(Symbol(name)), callsignature.args[1].args[2:end]...), callsignature.args[2:end]...), call_expr))

    end

    x
end

#Begin Graph Functionality section

function show(io::IO, m::Model)
    println(io, "showing model component connections:")
    for item in enumerate(keys(m.components2))
        c = item[2]
        i_connections = get_connections(m,c,:incoming)
        o_connections = get_connections(m,c,:outgoing)
        println(io, item[1], ". ", c, " component")
        println(io, "    incoming parameters:")
        if length(i_connections)==0
            println(io, "      none")
        else
            [println(io, "      - ",e.target_parameter_name," from ",e.source_component_name," component") for e in i_connections]
        end
        println(io, "    outgoing variables:")
        if length(o_connections)==0
            println(io, "      none")
        else
            [println(io, "      - ",e.source_variable_name," in ",e.target_component_name, " component") for e in o_connections]
        end
    end
end

function get_connections(m::Model, c::ComponentInstanceInfo, which::Symbol)
    return get_connections(m, c.name, which)
end

function get_connections(m::Model, component_name::Symbol, which::Symbol)
    if which==:all
        f = e -> e.source_component_name==component_name || e.target_component_name==component_name
    elseif which==:incoming
        f = e -> e.target_component_name==component_name
    elseif which==:outgoing
        f = e -> e.source_component_name==component_name
    else
        error("Invalid parameter for the 'which' argument; must be 'all' or 'incoming' or 'outgoing'.")
    end
    return filter(f, m.internal_parameter_connections)
end

function get_connections(mi::ModelInstance, component_name::Symbol, which::Symbol)
    if which==:all
        f = e -> e.source_component_name==component_name || e.target_component_name==component_name
    elseif which==:incoming
        f = e -> e.target_component_name==component_name
    elseif which==:outgoing
        f = e -> e.source_component_name==component_name
    else
        error("Invalid parameter for the 'which' argument; must be 'all' or 'incoming' or 'outgoing'.")
    end
    return filter(f, mi.internal_parameter_connections)
end

#End of graph section
