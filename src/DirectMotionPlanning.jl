module DirectMotionPlanning

using LinearAlgebra, ForwardDiff, FiniteDiff, StaticArrays, SparseArrays
using MathOptInterface, Ipopt
using Distributions, Interpolations
using JLD2

using Colors
using CoordinateTransformations
using FileIO
using GeometryBasics
using MeshCat, MeshIO
using Rotations
# using RigidBodyDynamics, MeshCatMechanisms

include("indices.jl")
include("utils.jl")

include("time.jl")
include("model.jl")
include("integration.jl")

include("problem.jl")

include("objective.jl")
include("objectives/quadratic.jl")
include("objectives/penalty.jl")

include("constraints.jl")
include("constraints/dynamics.jl")

include("moi.jl")
include("solvers/snopt.jl")

include("lqr.jl")
include("unscented.jl")

# direct policy optimization
function include_dpo()
    include(joinpath(pwd(), "src/direct_policy_optimization/dpo.jl"))
end

end # module
