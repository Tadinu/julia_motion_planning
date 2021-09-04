include_ddp()
Random.seed!(0)

# Model
include_model("acrobot")
n, m, d = 4, 1, 4
model = Acrobot{Euler, FixedTime}(4, 1, 4, 1.0, 0.33, 1.0, 0.5, 1.0, 0.33, 1.0, 0.5, 9.81, 0.1, 0.1)

function fd(model::Acrobot{Euler, FixedTime}, x, u, w, h, t)
    x + h * f(model, x + 0.5 * h * f(model, x, u, w), u, w)
end

# function fd(model::Acrobot{Euler, FixedTime}, x⁺, x, u, w, h, t)
#     # x⁺ - (x + h * f(model, x⁺, u, w))
#     x⁺ - (x + h * f(model, x, u, w))
# end

function fd(model::Acrobot{Euler, FixedTime}, x, u, w, h, t)
    rz(z) = fd(model, z, x, u, w, h, t) # implicit Euler integration
	x⁺ = newton(rz, copy(x), tol_r = 1.0e-12)
    # x⁺ = levenberg_marquardt(rz, copy(x))
	return x⁺
end

fd(model, zeros(model.n), 0.001 * ones(model.m), zeros(model.d), 0.1, 1)

function fdx(model::Acrobot{Euler, FixedTime}, x, u, w, h, t)
	rz(z) = fd(model, z, x, u, w, h, t) # implicit Euler integration
    x⁺ = newton(rz, copy(x), tol_r = 1.0e-12)
    # x⁺ = levenberg_marquardt(rz, copy(x))
	∇rz = ForwardDiff.jacobian(rz, x⁺)
	rx(z) = fd(model, x⁺, z, u, w, h, t) # implicit Euler integration
	∇rx = ForwardDiff.jacobian(rx, x)
	return -1.0 * ∇rz \ ∇rx
end

fdx(model, ones(model.n), 0.01 * ones(model.m), zeros(model.d), 0.1, 1)

function fdu(model::Acrobot{Euler, FixedTime}, x, u, w, h, t)
	rz(z) = fd(model, z, x, u, w, h, t) # implicit Euler integration
    x⁺ = newton(rz, copy(x), tol_r = 1.0e-12)
    # x⁺ = levenberg_marquardt(rz, copy(x))
	∇rz = ForwardDiff.jacobian(rz, x⁺)
	ru(z) = fd(model, x⁺, x, z, w, h, t) # implicit Euler integration
	∇ru = ForwardDiff.jacobian(ru, u)
	return -1.0 * ∇rz \ ∇ru
end

fdu(model, zeros(model.n), zeros(model.m), zeros(model.d), 0.1, 1)

# Model
n = model.n
m = model.m

# Time
T = 101
tf = 5.0
h = tf / (T - 1)

# Initial conditions, controls, disturbances
x1 = [0.0, 0.0, 0.0, 0.0]
xT = [π, 0.0, 0.0, 0.0] # goal state
ū = [1.0e-3 * rand(model.m) for t = 1:T-1]
w = [zeros(model.d) for t = 1:T-1]

# Rollout
x̄ = rollout(model, x1, ū, w, h, T)
# x̄ = linear_interpolation(x1, xT, T)
plot(hcat(x̄...)')

# Objective
Q = [(t < T ? Diagonal(1.0e-3 * ones(model.n))
        : Diagonal(100.0 * ones(model.n))) for t = 1:T]
q = [-2.0 * Q[t] * xT for t = 1:T]

R = [Diagonal(1.0e-3 * ones(model.m)) for t = 1:T-1]
r = [zeros(model.m) for t = 1:T-1]

obj = StageCosts([QuadraticCost(Q[t], q[t],
	t < T ? R[t] : nothing, t < T ? r[t] : nothing) for t = 1:T], T)

function g(obj::StageCosts, x, u, t)
	T = obj.T
    if t < T
		Q = obj.cost[t].Q
		q = obj.cost[t].q
	    R = obj.cost[t].R
		r = obj.cost[t].r
        return x' * Q * x + q' * x + u' * R * u + r' * u
    elseif t == T
		Q = obj.cost[T].Q
		q = obj.cost[T].q
        return x' * Q * x + q' * x
    else
        return 0.0
    end
end

# Problem
prob = problem_data(model, obj, copy(x̄), copy(ū), w, h, T)
    # analytical_dynamics_derivatives = true)

# Solve
@time ddp_solve!(prob,
    max_iter = 1000, verbose = true,
    grad_tol = 1.0e-3,
    linesearch = :armijo)

x, u = current_trajectory(prob)
x̄, ū = nominal_trajectory(prob)

# Visualize
# using Plots
# plot(π * ones(T),
#     width = 2.0, color = :black, linestyle = :dash)
# plot!(hcat(x...)', width = 2.0, label = "")
# plot(hcat(u..., u[end])',
#     width = 2.0, linetype = :steppost)
#
# include(joinpath(pwd(), "models/visualize.jl"))
# vis = Visualizer()
# render(vis)
# # open(vis)
# visualize!(vis, model, x, Δt = h)

@show norm(x[end] - xT)
