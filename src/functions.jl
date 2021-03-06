
"""
A wrapper around a parameterized function of the form f(θ, x...)
    - θ are parameters to be learned
    - x is per-iteration inputs... there may not be any (for
        example the Rosenbrock function is only f(θ))

The type parameter DIFFNUM is the number of times it can be differentiated.
"""
type Differentiable{T,DIFFNUM,P<:Params} <: Minimizable
    f::Function
    df::NTuple{DIFFNUM,Function}
    input::SumNode{T,1}
    output::OutputNode{T,1}
    params::P
end
Differentiable(args...) = Differentiable(Float64, args...)
function Differentiable{T}(::Type{T}, f::Function, nθ::Int, nx::Int, df::Function...)
    input = InputNode(T, nx)
    output = OutputNode(T, 1)
    params = Params(T, nθ)
    Differentiable(f, df, input, output, params)
end

# a convenience constructor for Differentiable types
function tfunc(f::Function, nΘ::Int, nx::Int, df::Function...; T = Float64)
    Differentiable(T, f, nΘ, nx, df...)
end
tfunc(f::Function, nΘ::Int, df::Function...; kw...) = tfunc(f, nΘ, 0, df...; kw...)

typealias NonDifferentiable{T,P} Differentiable{T,0,P}
typealias OnceDifferentiable{T,P} Differentiable{T,1,P}
typealias TwiceDifferentiable{T,P} Differentiable{T,2,P}

function apply_function(t::Differentiable, f::Function)
    if input_length(t) == 0
        # not a function of x
        f(params(t))
    else
        f(params(t), input_value(t))
    end
end

function transform!(t::Differentiable)
    t.output.val[1] = apply_function(t, t.f)
end

totalcost(t::Differentiable) = t.output.val[1]

grad!(t::NonDifferentiable) = error()

function grad!(t::Differentiable)
    grad(t)[:] = apply_function(t, t.df[1])
    return
end

# -----------------------------------------------------------------------
# some common test functions

module TestTransforms

using ..Transformations

export
    rosenbrock,
    rosenbrock_gradient
    # rosenbrock_transform

function rosenbrock(θ::AbstractVector)
    sum(100(θ[i+1] - θ[i]^2)^2 + (θ[i] - 1)^2 for i=1:length(θ)-1)
end

function rosenbrock(θs::Number...)
    rosenbrock(collect(θs))
end

function rosenbrock_gradient(θ::AbstractVector)
    ∇ = zeros(θ)
    n = length(θ)
    for i=1:n
        if i > 1
            ∇[i] += 200*(θ[i] - θ[i-1]^2)
        end
        if i < n
            ∇[i] += 2*(θ[i]-1) - 400θ[i] * (θ[i+1] - θ[i]^2)
        end
    end
    ∇
end

function rosenbrock_gradient(θs::Number...)
    rosenbrock_gradient(collect(θs))
end

# function rosenbrock_transform(nθ::Int = 2)
#     @assert nθ > 1
#     Differentiable(rosenbrock, 0, nθ, rosenbrock_gradient)
# end

end #TestTransforms
