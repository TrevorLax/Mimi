#
# Functions pertaining to instantiated models and their components
#

modeldef(mi::ModelInstance) = mi.md

compinstance(mi::ModelInstance, name::Symbol) = mi.components[name]

compdef(ci::ComponentInstance) = compdef(ci.comp_id)

name(ci::ComponentInstance) = ci.comp_name

"""
    components(mi::ModelInstance)

Return an iterator on the components in model instance `mi`.
"""
components(mi::ModelInstance) = values(mi.components)

function addcomponent(mi::ModelInstance, ci::ComponentInstance) 
    mi.components[name(ci)] = ci

    push!(mi.starts, ci.start)
    push!(mi.stops, ci.stop)
end

#
# Support for dot-overloading in run_timestep functions
#
function _index_pos(names, propname, var_or_par)
    index_pos = findfirst(names, propname)
    # println("findfirst($names, $propname) returned $index_pos")

    index_pos == 0 && error("Unknown $var_or_par name $propname.")
    return index_pos
end

# TBD: Allow assignment only to array slices, not entire arrays
function _property_expr(obj, types, index_pos)
    T = types.parameters[index_pos]
    # println("_property_expr() index_pos: $index_pos, T: $T")
   
    if T <: Scalar
        value_type = T.parameters[1]
        ex = :(obj.values[$index_pos].value::$(value_type)) # dereference Scalar instance
    else
        ex = :(obj.values[$index_pos])
    end

    # println("_property_expr returning $ex")
    return ex
end

# Fallback get & set property funcs that revert to dot notation
@generated function getproperty(obj, ::Val{PROPERTY}) where {PROPERTY}
    return :(obj.$PROPERTY)
end

@generated function setproperty!(obj, ::Val{PROPERTY}, value) where {PROPERTY}
    return :(obj.$PROPERTY = value)
end

# Special case support for Dicts so we can use dot notation on dimension.
# The run() func passes a Dict of dimensions by name as the "d" parameter.
# Here we return a range representing the indices into that list of values.
# TBD: Need to revise this in v0.7 so we don't affect all Dicts.
@generated function getproperty(obj::Dict, ::Val{PROPERTY}) where {PROPERTY}
    return :(obj[PROPERTY])
end

# Setting/getting parameter and variable values
@generated function getproperty(obj::ComponentInstanceParameters{NAMES, TYPES}, 
                                ::Val{PROPERTY}) where {NAMES, TYPES, PROPERTY}
    index_pos = _index_pos(NAMES, PROPERTY, "parameter")
    return _property_expr(obj, TYPES, index_pos)
end

@generated function getproperty(obj::ComponentInstanceVariables{NAMES, TYPES}, 
                                ::Val{PROPERTY}) where {NAMES, TYPES, PROPERTY}
    index_pos = _index_pos(NAMES, PROPERTY, "variable")
    return _property_expr(obj, TYPES, index_pos)
end

# Shouldn't set the parameter itself, just the value (for Scalar objs) or array slice

@generated function setproperty!(obj::ComponentInstanceParameters{NAMES, TYPES}, 
                                 ::Val{PROPERTY}, value) where {NAMES, TYPES, PROPERTY}
    index_pos = _index_pos(NAMES, PROPERTY, "parameter")
    T = TYPES.parameters[index_pos]

    if T <: Scalar
        return :(obj.values[$index_pos].value = value)
    else
        error("You cannot override indexed parameter $PROPERTY::$T.")
        # return :(obj.values[$index_pos] = value)
    end
end

@generated function setproperty!(obj::ComponentInstanceVariables{NAMES, TYPES}, 
                                 ::Val{PROPERTY}, value) where {NAMES, TYPES, PROPERTY}
    index_pos = _index_pos(NAMES, PROPERTY, "variable")
    T = TYPES.parameters[index_pos]

    if T <: Scalar
        return :(obj.values[$index_pos].value = value)
    else
        error("You cannot override indexed variable $PROPERTY::$T.")
        # return :(obj.values[$index_pos] = value)
    end
end

# Get the object stored for the given variable, not the value of the variable.
# This is used in the model building process to connect internal parameters.
function get_property_obj(obj::ComponentInstanceVariables{NAMES, TYPES}, 
                          name::Symbol) where {NAMES, TYPES}
    index_pos = _index_pos(NAMES, name, "variable")
    return obj.values[index_pos]
end

# Convenience functions that can be called with a name symbol rather than Val(name)
function get_parameter_value(ci::ComponentInstance, name::Symbol)
    try 
        return getproperty(ci.parameters, Val(name))
    catch err
        if isa(err, KeyError)
            error("Component $(ci.comp_id) has no parameter named $name")
        else
            rethrow(err)
        end
    end
end

function get_variable_value(ci::ComponentInstance, name::Symbol)
    try
        # println("Getting $name from $(ci.variables)")
        return getproperty(ci.variables, Val(name))
    catch err
        if isa(err, KeyError)
            error("Component $(ci.comp_id) has no variable named $name")
        else
            rethrow(err)
        end
    end
end

set_parameter_value(ci::ComponentInstance, name::Symbol, value) = setproperty!(ci.parameters, Val(name), value)

set_variable_value(ci::ComponentInstance, name::Symbol, value)  = setproperty!(ci.variables, Val(name), value)

# Allow values to be obtained from either parameter type using one method name.
value(param::ScalarModelParameter) = param.value

value(param::ArrayModelParameter)  = param.values

dimensions(obj::ArrayModelParameter) = obj.dimensions

dimensions(obj::ScalarModelParameter) = []

"""
    variables(mi::ModelInstance, comp_name::Symbol)

Return the `ComponentInstanceVariables` for `comp_name` in ModelInstance 'mi'.
"""
variables(mi::ModelInstance, comp_name::Symbol) = variables(compinstance(mi, comp_name))

variables(ci::ComponentInstance) = ci.variables

"""
    parameters(mi::ModelInstance, comp_name::Symbol)

Return the `ComponentInstanceParameters` for `comp_name` in ModelInstance 'mi'.
"""
parameters(mi::ModelInstance, comp_name::Symbol) = parameters(compinstance(mi, comp_name))

parameters(ci::ComponentInstance) = ci.parameters


function Base.getindex(mi::ModelInstance, comp_name::Symbol, datum_name::Symbol)
    if !(comp_name in keys(mi.components))
        error("Component :$comp_name does not exist in current model")
    end
    
    comp_inst = compinstance(mi, comp_name)
    vars = comp_inst.variables
    pars = comp_inst.parameters

    if datum_name in vars.names
        which = vars
    elseif datum_name in pars.names
        which = pars
    else
        error("$datum_name is not a parameter or a variable in component $comp_name.")
    end

    value = getproperty(which, Val(datum_name))
    # return isa(value, PklVector) || isa(value, TimestepMatrix) ? value.data : value
    return value isa TimestepArray ? value.data : value
end

"""
    dim_count(mi::ModelInstance, dim_name::Symbol)

Returns the size of index `dim_name`` in model instance `mi`.
"""
dim_count(mi::ModelInstance, dim_name::Symbol) = dim_count(mi.md, dim_name)

dim_key_dict(mi::ModelInstance) = dim_key_dict(mi.md)

dim_value_dict(mi::ModelInstance) = dim_value_dict(mi.md)

function make_clock(mi::ModelInstance, ntimesteps, time_keys::Vector{Int})
    start = time_keys[1]
    stop  = time_keys[min(length(time_keys), ntimesteps)]
    step = isuniform(time_keys)
    if step != -1
        return Clock{Timestep}(start, step, stop)

    else
        stop_index = findfirst(time_keys, stop)
        years = (time_keys[1:stop_index]...)
        return Clock{VariableTimestep}(years)

    end
end

function reset_variables(ci::ComponentInstance)
    # println("reset_variables($(ci.comp_id))")
    vars = ci.variables

    for (name, T) in zip(vars.names, vars.types.parameters)
        value = getproperty(vars, Val(name))

        if (T <: AbstractArray || T <: TimestepArray) && eltype(value) <: AbstractFloat
            fill!(value, NaN)

        elseif T <: AbstractFloat || (T <: Scalar && T.parameters[1] <: AbstractFloat)            
            setproperty!(vars, Val(name), NaN)

        elseif (T <: Scalar)    # integer or bool
            setproperty!(vars, Val(name), 0)
        end
    end
end

# Fall-back for components without init methods
function init(module_name, comp_name, p::ComponentInstanceParameters, v::Mimi.ComponentInstanceVariables, d::Union{Void, Dict})
    nothing
end

function init(mi::ModelInstance)
    for ci in components(mi)
        init(mi, ci)
    end
end

function init(mi::ModelInstance, ci::ComponentInstance)
    reset_variables(ci)
    module_name = compmodule(ci.comp_id)

    init(Val(module_name), Val(ci.comp_name), ci.parameters, ci.variables, ci.dim_dict)
end

function run_timestep(ci::ComponentInstance, clock::Clock)
    if ci.run_timestep == nothing
        return
    end

    pars = ci.parameters
    vars = ci.variables
    dims = ci.dim_dict
    t = ci.useIntegerTime ? timeindex(clock) : clock.ts

    ci.run_timestep(pars, vars, dims, t)
    advance(clock)
    nothing
end

function _run_components(mi::ModelInstance, clock::Clock,
                         starts::Vector{Int}, stops::Vector{Int}, comp_clocks::Vector{Clock})
    comp_instances = components(mi)
    
    while ! finished(clock)
        for (ci, start, stop, comp_clock) in zip(comp_instances, starts, stops, comp_clocks)
            if start <= gettime(clock) <= stop
                run_timestep(ci, comp_clock)
            end
        end
        advance(clock)
    end
    nothing
end

function Base.run(mi::ModelInstance, ntimesteps::Int=typemax(Int), 
                  dimkeys::Union{Void, Dict{Symbol, Vector{T} where T <: DimensionKeyTypes}}=nothing)
    if length(mi.components) == 0
        error("Cannot run the model: no components have been created.")
    end

    t::Vector{Int} = dimkeys == nothing ? dim_keys(mi.md, :time) : dimkeys[:time]

    starts = mi.starts
    stops = mi.stops
    step  = isuniform(t)

    if step != -1
        comp_clocks = [Clock{Timestep}(start, step, stop) for (start, stop) in zip(starts, stops)]
    else
        comp_clocks = Array{Clock{VariableTimestep}}(length(starts))
        for i = 1:length(starts)
            start_index = findfirst(t, starts[i])
            stop_index = findfirst(t, stops[i])
            years = t[start_index:stop+index]
            comp_clocks[i] = Clock{VariableTimestep}(years)
        end
    end

    clock = make_clock(mi, ntimesteps, t)

    init(mi)    # call module's (or fallback) init function

    _run_components(mi, clock, starts, stops, comp_clocks)
    nothing
end
