include(joinpath(pwd(), "src/models/biped.jl"))
include(joinpath(pwd(), "src/objectives/velocity.jl"))
include(joinpath(pwd(), "src/constraints/contact.jl"))

# Visualize
include(joinpath(pwd(), "src/models/visualize.jl"))
vis = Visualizer()
open(vis)

θ = pi / 20.0
q1 = initial_configuration(model, θ)
qT = copy(q1)
qT[1] += 1.0
q1[3] -= pi / 30.0
q1[4] += pi / 20.0
# q1[5] -= pi / 10.0
# q1, qT = loop_configurations(model, θ)
visualize!(vis, model, [q1])

# Horizon
T = 21

# Time step
tf = 2.0
h = tf / (T-1)

# Bounds

# ul <= u <= uu
_uu = Inf * ones(model.m)
_uu[model.idx_u] .= 100.0

_ul = zeros(model.m)
_ul[model.idx_u] .= -100.0
ul, uu = control_bounds(model, T, _ul, _uu)

xl, xu = state_bounds(model, T, x1 = [q1; q1])

# Objective
q_ref = linear_interp(q1, qT, T)
X0 = configuration_to_state(q_ref)

obj_penalty = PenaltyObjective(1.0e3, model.m)

Qq = 10.0 * Diagonal(ones(model.nq))
Q = cat(0.5 * Qq, 0.5 * Qq, dims = (1, 2))
QT = cat(0.5 * Qq, 100.0 * Diagonal(ones(model.nq)), dims = (1, 2))
R = Diagonal([1.0e-1 * ones(model.nu)..., zeros(model.m - model.nu)...])

obj_tracking = quadratic_tracking_objective(
    [t < T ? Q : QT for t = 1:T],
    [R for t = 1:T-1],
    [X0[t] for t = 1:T],
    [zeros(model.m) for t = 1:T]
    )
obj_velocity = velocity_objective(
    [Diagonal(1.0e-1 * ones(model.nq)) for t = 1:T-1],
    model.nq,
    h = h)
obj_acceleration = acceleration_objective(
    [Diagonal(1.0e-1 * ones(model.nq)) for t = 1:T-1],
    model.nq,
    h = h)
obj = MultiObjective([obj_tracking,
                      obj_penalty,
                      obj_velocity,
                      obj_acceleration])

# Constraints
con_contact = contact_constraints(model, T)
# con_pinned = pinned_foot_constraint(model, q1, T)
con = multiple_constraints([con_contact])#, con_pinned])

# Problem
prob = trajectory_optimization_problem(model,
               obj,
               T,
               h = h,
               xl = xl,
               xu = xu,
               ul = ul,
               uu = uu,
               con = con
               )

# trajectory initialization
U0 = [1.0e-5 * rand(model.m) for t = 1:T-1] # random controls

# Pack trajectories into vector
Z0 = pack(X0, U0, prob)

#NOTE: may need to run examples multiple times to get good trajectories
# Solve nominal problem
@time Z̄ = solve(prob, copy(Z0),
    nlp = :ipopt,
    tol = 1.0e-3, c_tol = 1.0e-3, mapl = 5)

check_slack(Z̄, prob)
X̄, Ū = unpack(Z̄, prob)
using Plots
plot(hcat(Ū...)[1:model.nu,:]', linetype = :steppost)

# Visualize
visualize!(vis, model, state_to_configuration(X̄), Δt = h)
