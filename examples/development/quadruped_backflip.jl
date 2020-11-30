# Model
include_model("quadruped")

θ = -pi / 3.25
q1 = initial_configuration(model, θ)

# Horizon
T = 26

# Time step
tf = 2.5
h = tf / (T - 1)

u1 = initial_torque(model, q1, h)[model.idx_u]

# Free-time model_ft
model_ft = free_time_model(model)

function fd(model::Quadruped, x⁺, x, u, w, h, t)
	q3 = view(x⁺, model.nq .+ (1:model.nq))
	q2⁺ = view(x⁺, 1:model.nq)
	q2⁻ = view(x, model.nq .+ (1:model.nq))
	q1 = view(x, 1:model.nq)
	u_ctrl = view(u, model.idx_u)
	λ = view(u, model.idx_λ)
	b = view(u, model.idx_b)
	h = u[end]

    [q2⁺ - q2⁻;
    ((1.0 / h) * (M_func(model, q1) * (SVector{11}(q2⁺) - SVector{11}(q1))
    - M_func(model, q2⁺) * (SVector{11}(q3) - SVector{11}(q2⁺)))
    + transpose(B_func(model, q3)) * SVector{8}(u_ctrl)
    + transpose(N_func(model, q3)) * SVector{4}(λ)
    + transpose(P_func(model, q3)) * SVector{8}(b)
    - h * C_func(model, q3, (q3 - q2⁺) / h))]
end

function maximum_dissipation(model::Quadruped, x⁺, u, h)
	q3 = view(x⁺, model.nq .+ (1:model.nq))
	q2 = view(x⁺, 1:model.nq)
	ψ = view(u, model.idx_ψ)
	ψ_stack = [ψ[1] * ones(2); ψ[2] * ones(2); ψ[3] * ones(2); ψ[4] * ones(2)]
	η = view(u, model.idx_η)
	h = u[end]
	return P_func(model, q3) * (q3 - q2) / h + ψ_stack - η
end

include(joinpath(pwd(), "src/objectives/velocity.jl"))
include(joinpath(pwd(), "src/objectives/nonlinear_stage.jl"))
include(joinpath(pwd(), "src/constraints/contact.jl"))
include(joinpath(pwd(), "src/constraints/free_time.jl"))

# Visualize
# - Pkg.add any external deps from visualize.jl
include(joinpath(pwd(), "models/visualize.jl"))
vis = Visualizer()
open(vis)

# Configurations
# 1: x pos
# 2: z pos
# 3: torso angle (rel. to downward vertical)
# 4: thigh 1 angle (rel. to downward vertical)
# 5: calf 1 (rel. to thigh 1)
# 6: thigh 2 (rel. to downward vertical)
# 7: calf 2 (rel. to thigh 2)
# θ = pi / 12.5
# q1 = initial_configuration(model_ft, θ) # generate initial config from θ
# qT = copy(q1)
# qT[1] += 1.0
# q1[3] -= pi / 30.0
# q1[4] += pi / 20.0
# q1[5] -= pi / 10.0
# q1, qT = loop_configurations(model_ft, θ)
# qT[1] += 1.0

q1 = initial_configuration(model_ft,  θ)
qM = initial_configuration(model_ft,  -pi / 2.5)

# qM[1] += model_ft.l1
qM[2] += 1.5
qM[3] += pi
qM[4] += pi
qM[6] += pi
qT = copy(q1)
qT[1] -= model_ft.l1
qT[3] += 2.0 * pi
qT[4] += 2.0 * pi
qT[6] += 2.0 * pi

visualize!(vis, model_ft, [q1])
visualize!(vis, model_ft, [qM])
visualize!(vis, model_ft, [qT])

q_ref = [linear_interp(q1, qM, 14)[1:end-1]...,
    linear_interp(qM, qT, 13)...]

# q_ref = linear_interp(q1, qM, T)
visualize!(vis, model_ft, q_ref)

# Bounds

# control
# u = (τ1..4, λ1..2, β1..4, ψ1..2, η1...4, s1)
# ul <= u <= uu
_uu = Inf * ones(model_ft.m)
_uu[model_ft.idx_u] .= Inf
_uu[end] = 2.0 * h

_ul = zeros(model_ft.m)
_ul[model_ft.idx_u] .= -Inf
_ul[end] = 0.5 * h
ul, uu = control_bounds(model_ft, T, _ul, _uu)

xl, xu = state_bounds(model_ft, T,
    x1 = [q1; q1],
    xT = [Inf * ones(model.nq); qT])

# Objective
x0 = configuration_to_state(q_ref)

# penalty on slack variable
obj_penalty = PenaltyObjective(1.0e5, model_ft.m - 1)

# quadratic tracking objective
# Σ (x - xref)' Q (x - x_ref) + (u - u_ref)' R (u - u_ref)
obj_control = quadratic_time_tracking_objective(
    [zeros(model_ft.n, model_ft.n) for t = 1:T],
    [Diagonal([1.0e-1 * ones(model_ft.nu)..., zeros(model_ft.m - model_ft.nu)...]) for t = 1:T-1],
    [zeros(model_ft.n) for t = 1:T],
    [[copy(u1); zeros(model_ft.m - model_ft.nu)] for t = 1:T],
    1.0)

# quadratic velocity penalty
# Σ v' Q v
obj_velocity = velocity_objective(
    [Diagonal(1.0 * ones(model_ft.nq)) for t = 1:T-1],
    model_ft.nq,
    h = h,
    idx_angle = collect([3, 4, 5, 6, 7, 8, 9, 10, 11]))

# torso height
q2_idx = (12:22)
t_h = kinematics_1(model_ft, qM, body = :torso, mode = :com)[2]
l_stage_torso_h(x, u, t) = 100.0 * (kinematics_1(model_ft, view(x, q2_idx), body = :torso, mode = :com)[2] - t_h)^2.0
l_terminal_torso_h(x) = 0.0 * (kinematics_1(model_ft, view(x, q2_idx), body = :torso, mode = :com)[2] - t_h)^2.0
obj_torso_h = nonlinear_stage_objective(l_stage_torso_h, l_terminal_torso_h)
#
# # torso lateral
# l_stage_torso_lat(x, u, t) = (1.0 * (kinematics_1(model_ft, view(x, q2_idx), body = :torso, mode = :com)[1] - kinematics_1(model_ft, view(x0[t], q2_idx), body = :torso, mode = :com)[1])^2.0)
# l_terminal_torso_lat(x) = (0.0 * (kinematics_1(model_ft, view(x, q2_idx), body = :torso, mode = :com)[1] - kinematics_1(model_ft, view(x0[T], q2_idx), body = :torso, mode = :com)[1])^2.0)
# obj_torso_lat = nonlinear_stage_objective(l_stage_torso_lat, l_terminal_torso_lat)
#
# foot 1 height
l_stage_fh1(x, u, t) = 10.0 * (kinematics_2(model_ft, view(x, q2_idx), body = :leg_1, mode = :ee)[2] - 0.5)^2.0
l_terminal_fh1(x) = 0.0 * (kinematics_2(model_ft, view(x, q2_idx), body = :leg_1, mode = :ee)[2])^2.0
obj_fh1 = nonlinear_stage_objective(l_stage_fh1, l_terminal_fh1)

# foot 2 height
l_stage_fh2(x, u, t) = 10.0 * (kinematics_2(model_ft, view(x, q2_idx), body = :leg_2, mode = :ee)[2] - 0.5)^2.0
l_terminal_fh2(x) = 0.0 * (kinematics_2(model_ft, view(x, q2_idx), body = :leg_2, mode = :ee)[2])^2.0
obj_fh2 = nonlinear_stage_objective(l_stage_fh2, l_terminal_fh2)

# foot 3 height
l_stage_fh3(x, u, t) = 1.0 * (kinematics_3(model_ft, view(x, q2_idx), body = :leg_3, mode = :ee)[2] - 0.5)^2.0
l_terminal_fh3(x) = 0.0 * (kinematics_3(model_ft, view(x, q2_idx), body = :leg_3, mode = :ee)[2])^2.0
obj_fh3 = nonlinear_stage_objective(l_stage_fh3, l_terminal_fh3)

# foot 4 height
l_stage_fh4(x, u, t) = 1.0 * (kinematics_3(model_ft, view(x, q2_idx), body = :leg_4, mode = :ee)[2] - 0.5)^2.0
l_terminal_fh4(x) = 0.0 * (kinematics_3(model_ft, view(x, q2_idx), body = :leg_4, mode = :ee)[2])^2.0
obj_fh4 = nonlinear_stage_objective(l_stage_fh4, l_terminal_fh4)

obj = MultiObjective([obj_penalty,
                      obj_control,
                      obj_velocity,
                      obj_torso_h,
                      # obj_torso_lat,
                      obj_fh1,
                      obj_fh2,
                      obj_fh3,
                      obj_fh4])

# Constraints
con_contact = contact_constraints(model_ft, T)
con_free_time = free_time_constraints(T)
con = multiple_constraints([con_contact, con_free_time])

# Problem
prob = trajectory_optimization_problem(model_ft,
               obj,
               T,
               h = h,
               xl = xl,
               xu = xu,
               ul = ul,
               uu = uu,
               con = con)

# trajectory initialization
u0 = [[copy(u1); 1.0e-5 * rand(model_ft.m - model_ft.nu - 1); h] for t = 1:T-1] # random controls

# Pack trajectories into vector
z0 = pack(x0, u0, prob)
z0 .+= 1.0e-5 * randn(prob.num_var)

# Solve
include_snopt()

@time z̄ = solve(prob, copy(z0),
    nlp = :SNOPT7,
    tol = 1.0e-3, c_tol = 1.0e-3,
    time_limit = 60 * 3, mapl = 5)

# @time z̄ = solve(prob, copy(z̄ .+ 1.0e-3 * rand(prob.num_var)),
#     nlp = :SNOPT7,
#     tol = 1.0e-3, c_tol = 1.0e-3,
#     time_limit = 60 * 30, mapl = 5)

check_slack(z̄, prob)
x̄, ū = unpack(z̄, prob)
tf, t, hc = get_time(ū)
ū
# Visualize
visualize!(vis, model_ft, state_to_configuration(x̄), Δt = ū[1][end])

visualize!(vis, model_ft, [[state_to_configuration(x̄)[1] for i = 1:5]..., state_to_configuration(x̄)..., [state_to_configuration(x̄)[end] for i = 1:5]...], Δt = ū[1][end])

# setobject!(vis["box"], HyperRectangle(Vec(0.0, 0.0, 0.0), Vec(0.5, 1.0, 0.25)))
# settransform!(vis["box"], Translation(1.0, -0.5, 0))
# # open(vis)
using Plots
plot(t[1:end-1], hcat(ū...)[model_ft.idx_u, :]', linetype = :steppost,
	width = 2.0, label = "", xlabel= "time (s)", ylabel = "control")
