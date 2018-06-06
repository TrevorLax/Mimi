# Global component registry: @defcomp stores component definitions here
global const _compdefs = Dict{ComponentId, ComponentDef}()

compdefs() = collect(values(_compdefs))

compdef(comp_id::ComponentId) = _compdefs[comp_id]

function compdef(comp_name::Symbol)
    matches = collect(Iterators.filter(obj -> name(obj) == comp_name, values(_compdefs)))
    count = length(matches)

    if count == 1
        return matches[1]
    elseif count == 0
        error("Component $comp_name was not found in the global registry")
    else
        error("Multiple components named $comp_name were found in the global registry")
    end
end

compdefs(md::ModelDef) = values(md.comp_defs)

compkeys(md::ModelDef) = keys(md.comp_defs)

hascomp(md::ModelDef, comp_name::Symbol) = haskey(md.comp_defs, comp_name)

compdef(md::ModelDef, comp_name::Symbol) = md.comp_defs[comp_name]

function reset_compdefs(reload_builtins=true)
    empty!(_compdefs)

    if reload_builtins
        compdir = joinpath(dirname(@__FILE__), "..", "components")
        load_comps(compdir)
    end
end

start_period(comp_def::ComponentDef) = comp_def.start

stop_period(comp_def::ComponentDef) = comp_def.stop

# Return the module object for the component was defined in
compmodule(comp_id::ComponentId) = comp_id.module_name

compname(comp_id::ComponentId) = comp_id.comp_name

function Base.show(io::IO, comp_id::ComponentId)
    print(io, "$(comp_id.module_name).$(comp_id.comp_name)")
end

# Gets the name of all NamedDefs: DatumDef, ComponentDef, DimensionDef
name(def::NamedDef) = def.name

number_type(md::ModelDef) = md.number_type

numcomponents(md::ModelDef) = length(md.comp_defs)


function dump_components()
    for comp in compdefs()
        println("\n$(name(comp))")
        for (tag, objs) in ((:Variables, variables(comp)), (:Parameters, parameters(comp)), (:Dimensions, dimensions(comp)))
            println("  $tag")
            for obj in objs
                println("    $(obj.name) = $obj")
            end
        end
    end
end

"""
    new_component(comp_id::ComponentId)

Create an empty `ComponentDef`` to the global component registry with the given
`comp_id`. The empty `ComponentDef` must be populated with calls to `addvariable`,
`addparameter`, etc.
"""
function new_component(comp_id::ComponentId, verbose::Bool=true)
    if verbose
        if haskey(_compdefs, comp_id)
            warn("Redefining component $comp_id")
        else
            println("new component $comp_id")
        end
    end

    comp_def = ComponentDef(comp_id)
    _compdefs[comp_id] = comp_def
    return comp_def
end

"""
    delete!(m::ModelDef, component::Symbol

Delete a component by name from a model definition.
"""
function Base.delete!(md::ModelDef, comp_name::Symbol)
    if ! haskey(md.comp_defs, comp_name)
        error("Cannot delete '$comp_name' from model; component does not exist.")
    end

    delete!(md.comp_defs, comp_name)

    ipc_filter = x -> x.src_comp_name != comp_name && x.dst_comp_name != comp_name
    filter!(ipc_filter, md.internal_param_conns)

    epc_filter = x -> x.comp_name != comp_name
    filter!(epc_filter, md.external_param_conns)  
end

#
# Dimensions
#
function add_dimension(comp::ComponentDef, name)
    comp.dimensions[name] = dim_def = DimensionDef(name)
    return dim_def
end

add_dimension(comp_id::ComponentId, name) = add_dimension(compdef(comp_id), name)

dimensions(comp_def::ComponentDef) = values(comp_def.dimensions)

dimensions(def::DatumDef) = def.dimensions

dimensions(comp_def::ComponentDef, datum_name::Symbol) = dimensions(datumdef(comp_def, datum_name))

dim_count(def::DatumDef) = length(def.dimensions)

datatype(def::DatumDef) = def.datatype

description(def::DatumDef) = def.description

unit(def::DatumDef) = def.unit

# LFR-TBD:  Since not all models have a step_size, we have removed this function
# and replaced it with a complementary one, yeras_array

# step_size(md::ModelDef) = step_size(indexvalues(md))

# function step_size(md::ModelDef)
#     # N.B. assumes that all timesteps of the model are the same length
#     keys::Vector{Int} = dim_keys(md, :time) # keys are, e.g., the years the model runs
#     return length(keys) > 1 ? keys[2] - keys[1] : 1
# end

# function step_size(values::Vector{Int})
#     # N.B. assumes that all timesteps of the model are the same length
#      return length(values) > 1 ? values[2] - values[1] : 1
# end

function years_array(md::ModelDef)
    keys::Vector{Int} = dim_keys(md, :time)
    return keys
end

function years_array(values::Vector{Int})
    return values
end

function check_parameter_dimensions(md::ModelDef, value::AbstractArray, dims::Vector, name::Symbol)
    for dim in dims
        if haskey(md, dim)
            if isa(value, NamedArray)
                labels = names(value, findnext(dims, dim, 1))
                dim_vals = dim_keys(md, dim)
                for i in 1:length(labels)
                    if labels[i] != dim_vals[i]
                        error("Labels for dimension $dim in parameter $name do not match model's index values")
                    end
                end
            end
        else
            error("Dimension $dim in parameter $name not found in model's dimensions")
        end
    end
end

dimensions(md::ModelDef) = md.dimensions
dimensions(md::ModelDef, dims::Vector{Symbol}) = [dimension(md, dim) for dim in dims]
dimension(md::ModelDef, name::Symbol) = md.dimensions[name]

dim_count_dict(md::ModelDef) = Dict([name => length(value) for (name, value) in dimensions(md)])
dim_counts(md::ModelDef, dims::Vector{Symbol}) = [length(dim) for dim in dimensions(md, dims)]
dim_count(md::ModelDef, name::Symbol) = length(dimension(md, name))

dim_key_dict(md::ModelDef) = Dict([name => collect(keys(dim)) for (name, dim) in dimensions(md)])
dim_keys(md::ModelDef, name::Symbol) = collect(keys(dimension(md, name)))

dim_values(md::ModelDef, name::Symbol) = collect(values(dimension(md, name)))
dim_value_dict(md::ModelDef) = Dict([name => collect(values(dim)) for (name, dim) in dimensions(md)])

timelabels(md::ModelDef) = collect(keys(dimension(md, :time)))

Base.haskey(md::ModelDef, name::Symbol) = haskey(md.dimensions, name)

function set_dimension!(md::ModelDef, name::Symbol, keys::Union{Int, Vector, Tuple, Range})    
    if haskey(md, name)
        warn("Redefining dimension :$name")
    end

    dim = Dimension(keys)
    md.dimensions[name] = dim
    return dim
end

# LFR-TBD:  We might be able to simplify this function, and we should think through
# it's return carefully as it is at the root of several functions.  Also, do we
# want to be able to call this on a model too (like years_array?) ... otherwise
# we often call years_array and then isuniform.
#
# helper function for setindex; used to determine if the provided time values are 
# a uniform range. The function returns -1 if the vector is not uniform, 
#otherwise it returns the timestep length aka stepsize
function isuniform(values::Vector)
    num_values = length(values)

    if num_values == 0
        return -1
    end

    if num_values == 1
        return 1
    end

    stepsize = values[2] - values[1]
    
    if num_values == 2
        return stepsize
    end

    for i in 3:length(values)
        if (values[i] - values[i - 1]) != stepsize
            return -1
        end
    end

    return stepsize
end

#
# Parameters
#

external_params(md::ModelDef) = md.external_params

function addparameter(comp_def::ComponentDef, name, datatype, dimensions, description, unit)
    p = DatumDef(name, datatype, dimensions, description, unit, :parameter)
    comp_def.parameters[name] = p
    return p
end

function addparameter(comp_id::ComponentId, name, datatype, dimensions, description, unit)
    addparameter(compdef(comp_id), name, datatype, dimensions, description, unit)
end

parameters(comp_def::ComponentDef) = values(comp_def.parameters)

parameters(comp_id::ComponentId) = parameters(compdef(comp_id))

"""
    parameter_names(md::ModelDef, comp_name::Symbol)

Return a list of all parameter names for a given component in a model def.
"""
parameter_names(md::ModelDef, comp_name::Symbol) = parameter_names(compdef(md, comp_name))

parameter_names(comp_def::ComponentDef) = [name(param) for param in parameters(comp_def)]

parameter(md::ModelDef, comp_name::Symbol, param_name::Symbol) = parameter(compdef(md, comp_name), param_name)

function parameter(comp_def::ComponentDef, name::Symbol) 
    try
        return comp_def.parameters[name]
    catch
        error("Parameter $name was not found in component $(comp_def.name)")
    end
end

function parameter_unit(md::ModelDef, comp_name::Symbol, param_name::Symbol)
    param = parameter(md, comp_name, param_name)
    return param.unit
end

function parameter_dimensions(md::ModelDef, comp_name::Symbol, param_name::Symbol)
    param = parameter(md, comp_name, param_name)
    return param.dimensions
end

"""
    set_parameter!(m::ModelDef, comp_name::Symbol, name::Symbol, value, dims=nothing)

Set the parameter of a component in a model to a given value. Value can by a scalar,
an array, or a NamedAray. Optional argument 'dims' is a list of the dimension names of
the provided data, and will be used to check that they match the model's index labels.
"""
function set_parameter!(md::ModelDef, comp_name::Symbol, param_name::Symbol, value, dims=nothing)
    comp_def = compdef(md, comp_name)

    # perform possible dimension and labels checks
    if isa(value, NamedArray)
        dims = dimnames(value)
    end

    if dims != nothing
        check_parameter_dimensions(md, value, dims, param_name)
    end

    comp_param_dims = parameter_dimensions(md, comp_name, param_name)
    num_dims = length(comp_param_dims)
    
    if length(comp_param_dims) > 0
        comp_def = compdef(md, comp_name)
        data_type = datatype(parameter(comp_def, param_name))
        dtype = data_type == Number ? number_type(md) : data_type

        # convert the number type and, if NamedArray, convert to Array
        value = convert(Array{dtype, num_dims}, value)
        
        if comp_param_dims[1] == :time
            T = eltype(value)
            # start = start_period(comp_def)
            # dur = step_size(md)

            #values = num_dims == 0 ? value : TimestepArray{AbstractTimestep, T, num_dims}(value)

            # LFR-TBD:  There may be a more elegant way to carry out the logic below.  
            # We need to access years and stepsize, so this might have to do with
            # how the isuniform function is used etc.
            if num_dims == 0
                values = value
            else
                years = years_array(md)
                stepsize = isuniform(years)
                if stepsize == -1
                    values = TimestepArray{VariableTimestep{years}, T, num_dims}(value)
                else
                    values = TimestepArray{Timestep{years[1], stepsize}, T, num_dims}(value)
                end
                
            end

        else
            values = value
        end

        set_external_array_param!(md, param_name, values, comp_param_dims)

    else # scalar parameter case
        set_external_scalar_param!(md, param_name, value)
    end

    connect_parameter(md, comp_name, param_name, param_name)
    nothing
end

#
# Variables
#
variables(comp_def::ComponentDef) = values(comp_def.variables)

variables(comp_id::ComponentId) = variables(compdef(comp_id))

function variable(comp_def::ComponentDef, var_name::Symbol)
    try
        return comp_def.variables[var_name]
    catch
        error("Variable $var_name was not found in component $(comp_def.comp_id)")
    end
end

variable(comp_id::ComponentId, var_name::Symbol) = variable(compdef(comp_id), var_name)

variable(md::ModelDef, comp_name::Symbol, var_name::Symbol) = variable(compdef(md, comp_name), var_name)

"""
    variable_names(md::ModelDef, comp_name::Symbol)

Return a list of all variable names for a given component in a model def.
"""
variable_names(md::ModelDef, comp_name::Symbol) = variable_names(compdef(md, comp_name))

variable_names(comp_def::ComponentDef) = [name(var) for var in variables(comp_def)]


function variable_unit(md::ModelDef, comp_name::Symbol, var_name::Symbol)
    var = variable(md, comp_name, var_name)
    return var.unit
end

function variable_dimensions(md::ModelDef, comp_name::Symbol, var_name::Symbol)
    var = variable(md, comp_name, var_name)
    return var.dimensions
end

# Add a variable to a ComponentDef
function addvariable(comp_def::ComponentDef, name, datatype, dimensions, description, unit)
    v = DatumDef(name, datatype, dimensions, description, unit, :variable)
    comp_def.variables[name] = v
    return v
end

# Add a variable to a ComponentDef referenced by ComponentId
function addvariable(comp_id::ComponentId, name, datatype, dimensions, description, unit)
    addvariable(compdef(comp_id), name, datatype, dimensions, description, unit)
end

#
# Other
#

# Return the number of timesteps a given component in a model will run for.
# function getspan(md::ModelDef, comp_name::Symbol)
#     comp_def = compdef(md, comp_name)
#     start = start_period(comp_def)
#     stop  = stop_period(comp_def)
#     step  = step_size(md)
#     return Int((stop - start) / step + 1)
# end
function getspan(md::ModelDef, comp_name::Symbol)
    comp_def = compdef(md, comp_name)
    start = start_period(comp_def)
    stop  = stop_period(comp_def)
    years = years_array(md)
    start_index = findfirst(years, start)
    stop_index = findfirst(years, stop)
    return Int(size(years[start:stop]))
end

function set_run_period!(comp_def::ComponentDef, start, stop)
    comp_def.start = start
    comp_def.stop = stop
    return nothing
end

#
# Model
#
const VoidInt    = Union{Void, Int}
const VoidSymbol = Union{Void, Symbol}

"""
    addcomponent(md::ModelDef, comp_def::ComponentDef; start=nothing, stop=nothing, before=nothing, after=nothing)

Add the component indicated by `comp_def` to the model. The component is added at the end of 
the list unless one of the keywords, `start`, `stop`, `before`, `after`. If the `comp_name`
differs from that in the `comp_def`, a copy of `comp_def` is made and assigned the new name.
"""
function addcomponent(md::ModelDef, comp_def::ComponentDef, comp_name::Symbol;
                      start::VoidInt=nothing, stop::VoidInt=nothing, 
                      before::VoidSymbol=nothing, after::VoidSymbol=nothing)
    # check that start and stop are within the model's time index range
    time_index = dim_keys(md, :time)

    if start == nothing
        start = time_index[1]
    elseif start < time_index[1]
        error("Cannot add component $name with start time before start of model's time index range.")
    end

    if stop == nothing
        stop = time_index[end]
    elseif stop > time_index[end]
        error("Cannot add component $name with stop time after end of model's time index range.")
    end

    if before != nothing && after != nothing
        error("Cannot specify both 'before' and 'after' parameters")
    end

    # Check if component being added already exists
    if hascomp(md, comp_name)
        error("Cannot add two components of the same name ($comp_name)")
    end

    # Create a shallow copy of the original but with the new name
    # TBD: Why do we need to make a copy here? Sort this out.
    if compname(comp_def.comp_id) != comp_name
        comp_def = copy_comp_def(comp_def, comp_name)
    end        

    set_run_period!(comp_def, start, stop)

    if before == nothing && after == nothing
        md.comp_defs[comp_name] = comp_def   # just add it to the end
        return nothing
    end

    new_comps = OrderedDict{Symbol, ComponentDef}()

    if before != nothing
        if ! hascomp(md, before)
            error("Component to add before ($before) does not exist")
        end

        for i in compkeys(md)
            if i == before
                new_comps[comp_name] = comp_def
            end
            new_comps[i] = md.comp_defs[i]
        end

    else    # after != nothing, since we've handled all other possibilities above
        if ! hascomp(md, after)
            error("Component to add before ($before) does not exist")
        end

        for i in compkeys(md)
            new_comps[i] = md.comp_defs[i]
            if i == after
                new_comps[comp_name] = comp_def
            end
        end
    end

    md.comp_defs = new_comps
    # println("md.comp_defs: $(md.comp_defs)")
    return nothing
end

function addcomponent(md::ModelDef, comp_id::ComponentId, comp_name::Symbol=comp_id.comp_name;
                      start::VoidInt=nothing, stop::VoidInt=nothing, 
                      before::VoidSymbol=nothing, after::VoidSymbol=nothing)
    # println("Adding component $comp_id as :$comp_name")
    addcomponent(md, compdef(comp_id), comp_name, start=start, stop=stop, before=before, after=after)
end

function replace_component(md::ModelDef, comp_id::ComponentId, comp_name::Symbol=comp_id.comp_name;
                           start::VoidInt=nothing, stop::VoidInt=nothing,
                           before::VoidSymbol=nothing, after::VoidSymbol=nothing)
    delete!(md, comp_name)
    addcomponent(md, comp_id, comp_name; start=start, stop=stop, before=before, after=after)
end

"""
Create a mostly-shallow copy of `comp_def`, but make a deep copy of its
ComponentId so we can rename the copy without affecting the original.
"""
function copy_comp_def(comp_def::ComponentDef, comp_name::Symbol)
    comp_id = comp_def.comp_id
    obj     = ComponentDef(comp_id)

    # Use the comp_id as is, since this identifies the run_timestep function, but
    # use an alternate name to reference it in the model's component list.
    obj.name = comp_name

    obj.variables  = comp_def.variables
    obj.parameters = comp_def.parameters
    obj.dimensions = comp_def.dimensions
    obj.start      = comp_def.start
    obj.stop       = comp_def.stop

    return obj
end

"""
    copy_external_params(md::ModelDef)

Make copies of ModelParameter subtypes representing external parameters. 
This is used both in the copy() function below, and in the MCS subsystem 
to restore values between trials.

"""
function copy_external_params(md::ModelDef)
    external_params = Dict{Symbol, ModelParameter}()

    for (key, obj) in md.external_params
        external_params[key] = obj isa ScalarModelParameter ? ScalarModelParameter(obj.value) : ArrayModelParameter(copy(obj.values), obj.dimensions)
    end

    return external_params
end

function Base.copy(obj::TimestepVector{T_ts, T}) where {T_ts, T}
    return TimestepVector{T_ts, T}(copy(obj.data))
end

function Base.copy(obj::TimestepMatrix{T_ts, T}) where {T_ts, T}
    return TimestepMatrix{T_ts, T}(copy(obj.data))
end

"""
    copy(md::ModelDef)

Create a copy of a ModelDef object that is not entirely shallow, nor completely deep.
The aim is to copy the full structure, reusing references to immutable elements.
"""
function Base.copy(md::ModelDef)
    mdcopy = ModelDef(md.number_type)
    mdcopy.module_name = md.module_name
    
    merge!(mdcopy.comp_defs, md.comp_defs)
    
    mdcopy.dimensions = deepcopy(md.dimensions)

    # These are vectors of immutable structs, so we can (shallow) copy them safely
    mdcopy.internal_param_conns = copy(md.internal_param_conns)
    mdcopy.external_param_conns = copy(md.external_param_conns)

    # Names of external params that the ConnectorComps will use as their :input2 parameters.
    mdcopy.backups = copy(md.backups)
    mdcopy.external_params = copy_external_params(md)

    mdcopy.sorted_comps = md.sorted_comps == nothing ? nothing : copy(md.sorted_comps)    
    
    return mdcopy
end
