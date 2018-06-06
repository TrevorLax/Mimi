connector_comp_name(i::Int) = Symbol("ConnectorComp$i")

# Return the datatype to use for instance variables/parameters
function _instance_datatype(md::ModelDef, def::DatumDef, start::Int)
    dtype = def.datatype == Number ? number_type(md) : def.datatype
    dims = dimensions(def)
    num_dims = dim_count(def)

    if num_dims == 0
        T = Scalar{dtype}

    elseif dims[1] != :time
        T = Array{dtype, num_dims}
    
    else   

        #T = TimestepArray{AbstractTimestep, dtype, num_dims}

        # LFR-TBD:  There may be a more elegant way to carry out the logic below.  
        # We need to access years and stepsize, so this might have to do with
        # how the isuniform function is used etc.
        years = years_array(md)
        stepsize = isuniform(years)
        if stepsize == -1
            T = TimestepArray{VariableTimestep{years}, dtype, num_dims}
        else
            T = TimestepArray{Timestep{start, stepsize}, dtype, num_dims}
        end
    end

    # println("_instance_datatype($def) returning $T")
    return T
end

function _vars_type(md::ModelDef, comp_def::ComponentDef)
    var_defs = variables(comp_def)    
    vnames = Tuple([name(vdef) for vdef in var_defs])
    
    start = comp_def.start
    vtypes = Tuple{[_instance_datatype(md, vdef, start) for vdef in var_defs]...}

    return ComponentInstanceVariables{vnames, vtypes}
end

# Create the Ref or Array that will hold the value(s) for a Parameter or Variable
function _instantiate_datum(md::ModelDef, def::DatumDef, start::Int)
    dtype = _instance_datatype(md, def, start)
    dims = dimensions(def)
    num_dims = length(dims)
    
    if num_dims == 0
        value = dtype(0)
      
    # TBD: This is necessary only if dims[1] == :time, otherwise "else" handles it, too
    elseif num_dims == 1 && dims[1] == :time
        # t = dimension(md, :time)
        # value = dtype(length(t[start:end]))
        value = dtype(dim_count(md, :time))

    else # if dims[1] != :time
        # TBD: Handle unnamed indices properly
        counts = dim_counts(md, Vector{Symbol}(dims))
        value = dtype(counts...)
    end

    return value
end

"""
_instantiate_component_vars(md::ModelDef, comp_def::ComponentDef)

Instantiate a component and its variables (but not its parameters). Return 
the resulting ComponentInstance.
"""
function _instantiate_component_vars(md::ModelDef, comp_def::ComponentDef)
    comp_name = name(comp_def)
    start = comp_def.start
    vtype = _vars_type(md, comp_def)
    
    vals = [_instantiate_datum(md, def, start) for def in variables(comp_def)]
    return vtype(vals)
end

# Save a reference to the model's dimension dictionary to make it 
# available in calls to run_timestep.
function save_dim_dict_reference(mi::ModelInstance)
    dim_dict = dim_value_dict(mi.md)

    for ci in values(mi.components)
        ci.dim_dict = dim_dict
    end

    return nothing
end

function build(m::Model)
    # Reference a copy in the ModelInstance to avoid changes underfoot
    m.mi = build(copy(m.md))
    return nothing
end

function build(md::ModelDef)
    # check if all parameters are set
    not_set = unconnected_params(md)
    if ! isempty(not_set)
        params = join(not_set, " ")
        msg = "Cannot build model; the following parameters are not set: $params"
        error(msg)
    end

    var_dict = Dict{Symbol, Any}()                 # collect all var defs and
    par_dict = Dict{Symbol, Dict{Symbol, Any}}()   # store par values as we go
  
    comp_defs = compdefs(md)
    for comp_def in comp_defs
        comp_name = name(comp_def)
        var_dict[comp_name] = _instantiate_component_vars(md, comp_def)
        par_dict[comp_name] = Dict()  # param value keyed by param name
    end

    # Iterate over connections to create parameters, referencing storage in vars   
    for ipc in internal_param_conns(md)
        comp_name = ipc.src_comp_name      

        vars = var_dict[comp_name]
        var_value_obj = get_property_obj(vars, ipc.src_var_name)
        
        par_values = par_dict[ipc.dst_comp_name]
        par_values[ipc.dst_par_name] = var_value_obj
    end
    
    for ext in external_param_conns(md)
        comp_name = ext.comp_name
        param = external_param(md, ext.external_param)
        par_values = par_dict[comp_name]
        val = value(param)
        par_values[ext.param_name] = val isa Number ? Scalar(val) : val
    end

    # Make the external parameter connections for the hidden ConnectorComps.
    # Connect each :input2 to its associated backup value.
    for (i, backup) in enumerate(md.backups)
        comp_name = connector_comp_name(i)
        param = external_param(md, backups)

        par_values = par_dict[comp_name]
        par_values[:input2] = value(param)
    end

    mi = ModelInstance(md)

    # instantiate parameters
    for comp_def in comp_defs
        comp_name = name(comp_def)

        vars = var_dict[comp_name]
        
        par_values = par_dict[comp_name]
        pnames = Tuple(parameter_names(comp_def))
        pvals  = [par_values[pname] for pname in pnames]
        ptypes = Tuple{map(typeof, pvals)...}
        pars = ComponentInstanceParameters{pnames, ptypes}(pvals)

        ci = ComponentInstance{typeof(vars), typeof(pars)}(comp_def, vars, pars, comp_name)
        addcomponent(mi, ci)
    end

    save_dim_dict_reference(mi)
    return mi
end

function create_marginal_model(base::Model, delta::Float64=1.0)
    # Make sure the base has a ModelInstance before we copy since this
    # copies the ModelDef to avoid being affected by later changes.
    if base.mi == nothing
        build(base)
    end

    # Create a marginal model, which shares the internal ModelDef between base and marginal
    mm = MarginalModel(base, delta)
end

function Base.run(mm::MarginalModel, ntimesteps::Int=typemax(Int))
    run(mm.base, ntimesteps=ntimesteps)
    run(mm.marginal, ntimesteps=ntimesteps)
end
