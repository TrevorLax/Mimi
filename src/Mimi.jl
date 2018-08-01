__precompile__()

module Mimi

using DataFrames
using DataStructures
using Distributions
using Electron
using JSON 
using LightGraphs
using MetaGraphs
using NamedArrays
using StringBuilders

export
    @defcomp,
    MarginalModel,
    Model,
    add_comp!,  
    components, #TODO components -> comps?
    connect_param!,
    create_marginal_model,
    disconnect_param!,
    explore,
    getdataframe,
    getproperty,
    gettime,
    get_param_value,
    get_var_value,
    hasvalue,
    is_first,
    is_last,
    load_comps,
    modeldef,
    name,
    new_comp,
    parameters, #TODO:  parameters -> params?
    replace_comp!, 
    set_dimension!, # TODO:  Think hard about the terminology of axis-dimension-index-blabla
    set_leftover_params!, #TODO:  Rething this function in general
    setproperty!,
    set_param!, 
    variables  #TODO:  variables -> vars?

include("core/types.jl")

# After loading types, the rest can just be alphabetical
include("core/build.jl")
include("core/connections.jl")
include("core/defs.jl")
include("core/defcomp.jl")
include("core/deprecated.jl")
include("core/dimensions.jl")
include("core/instances.jl")
include("core/references.jl")
include("core/time.jl")
include("core/model.jl")
include("explorer/explore.jl")
include("mcs/mcs.jl")
include("utils/graph.jl")
# include("utils/plotting.jl")
include("utils/getdataframe.jl")
include("utils/lint_helper.jl")
include("utils/misc.jl")

"""
    load_comps(dirname::String="./components")

Call include() on all the files in the indicated directory.
This avoids having modelers create a long list of include()
statements. Just put all the components in a directory.
"""
function load_comps(dirname::String="./components")
    files = readdir(dirname)
    for file in files
        if endswith(file, ".jl")
            pathname = joinpath(dirname, file)
            include(pathname)
        end
    end
end

# Components are defined here to allow pre-compilation to work
function __init__()
    compdir = joinpath(dirname(@__FILE__), "components")
    load_comps(compdir)
end

end # module
