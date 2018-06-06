"""
A RandomVariable can be "assigned" to different model parameters. Its
value can be used directly or applied by adding to, or multiplying by, 
reference values for the indicated parameter. Note that the distribution
must be instantiated, e.g., call as RandomVariable(:foo, Normal()), not
RandomVariable(:foo, Normal).
"""
struct RandomVariable
    name::Symbol
    dist::Distribution   

    function RandomVariable(name::Symbol, dist::Distribution)
        self = new(name, dist)
        _rvDict[name] = self
        return self
    end
end

struct TransformSpec
    paramname::Symbol
    op::Symbol
    rvname::Symbol
    dims::Vector{Any}

    function TransformSpec(paramname::Symbol, op::Symbol, rvname::Symbol, dims::Vector{Any}=[])
        if ! (op in (:(=), :(+=), :(*=)))
            error("Valid operators are =, +=, and *= (got $op)")
        end
   
        return new(paramname, op, rvname, dims)
    end 
end

const CorrelationSpec = Tuple{Symbol, Symbol, Float64}

"""
Holds all the data that defines a Monte Carlo simulation.
"""
mutable struct MonteCarloSimulation
    trials::Int
    rvlist::Vector{RandomVariable}
    translist::Vector{TransformSpec}
    corrlist::Union{Vector{CorrelationSpec}, Void}
    savelist::Vector{Tuple}
    data::DataFrame
    results::Union{Dict{Tuple, DataFrame}, Void}
    output_dir::Union{String, Void}

    function MonteCarloSimulation(rvlist::Vector{RandomVariable}, 
                                  translist::Vector{TransformSpec}, 
                                  corrlist::Union{Vector{CorrelationSpec}, Void},
                                  savelist::Vector{Tuple})
        return new(0, rvlist, translist, corrlist, savelist, DataFrame(), nothing, nothing)
    end
end