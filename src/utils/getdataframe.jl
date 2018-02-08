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
