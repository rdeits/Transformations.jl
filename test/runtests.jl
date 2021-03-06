using Transformations
using Base.Test

using LearnBase
import LossFunctions: L2DistLoss
using Transformations.TestTransforms
import Transformations.Testing: check_gradient
using Distributions
using StochasticOptimization.Iteration
import MultivariateStats

# for reproducibility
srand(1)

function verify_gradient(err)
    isempty(err) && return
    if maximum(abs(err)) > 1e-3
        @show err extrema(err)
        @test false
    end
end

function test_gradient(t::Transformation, ϵ=1e-5)
    perr, xerr = check_gradient(t, ϵ=ϵ)
    verify_gradient(perr)
    verify_gradient(xerr)
end

@testset "Concat" begin
    n1, n2 = 2, 3
    n = n1 + n2
    cc = Concat(n)

    node1 = Transformations.OutputNode(n1)
    node1.val[:] = rand(n1)
    link_nodes!(node1, input_node(cc))
    node2 = Transformations.OutputNode(n2)
    node2.val[:] = rand(n2)
    link_nodes!(node2, input_node(cc))
    transform!(cc.input)

    @test transform!(cc) == vcat(node1.val, node2.val)

    ∇y = ones(n)
    grad!(cc, ∇y)
    @test input_grad(cc) == ∇y

    test_gradient(cc)
end


@testset "Gate" begin
    n = 3
    g = Gate(n)

    node1 = Transformations.OutputNode(n)
    node1.val[:] = rand(n)
    link_nodes!(node1, input_node(g))
    node2 = Transformations.OutputNode(n)
    node2.val[:] = rand(n)
    link_nodes!(node2, input_node(g))
    transform!(g.input)

    @test transform!(g) ≈ node1.val .* node2.val

    ∇y = ones(n)
    grad!(g, ∇y)
    @test input_grad(g) == ∇y

    # test_gradient(g)
end


@testset "PCA" begin
    nin, nout = 4, 2
    n = 50
    μ = zeros(nin)
    Λ = UpperTriangular(rand(nin,nin))
    Σ = Λ'*Λ
    mv = MultivariateNormal(μ, Σ)
    x = rand(mv, n)

    # learn the whitening by passing over the data a few times
    # note: since we do this online, it should approach the "true"
    # value in the limit
    totn = 1000n
    w = Whiten(nin, nout, lookback=100n, method=:pca)
    for i=1:totn
        learn!(w, x[:,mod1(i,n)])
    end

    # compute the projected output
    y = zeros(nout,n)
    for (xi,yi) in each_obs(x,y)
        yi[:] = transform!(w,xi)
    end

    # do it using MultivariateStats (the reference)
    wref = MultivariateStats.fit(MultivariateStats.PCA, x, maxoutdim=nout)
    yref = MultivariateStats.transform(wref, x)

    # check that we're close enough to the "true" projection
    @test norm(abs(y./yref)-1) < 1

    # check that the covariance matrices are close
    @test maximum(abs(cov(y') - cov(yref'))) < 1e-2

    # check that the means are close
    @test maximum(abs(mean(y,2) - mean(yref,2))) < 1e-2
end

@testset "Whitened PCA" begin
    nin, nout = 4, 2
    n = 50
    μ = zeros(nin)
    Λ = UpperTriangular(rand(nin,nin))
    Σ = Λ'*Λ
    mv = MultivariateNormal(μ, Σ)
    x = rand(mv, n)

    # learn the whitening by passing over the data a few times
    # note: since we do this online, it should approach the "true"
    # value in the limit
    totn = 50n
    w = Whiten(nin, nout, lookback=totn, method=:whitened_pca)
    for i=1:totn
        learn!(w, x[:,mod1(i,n)])
    end

    # compute the projected output
    y = zeros(nout,n)
    for (xi,yi) in each_obs(x,y)
        yi[:] = transform!(w,xi)
    end

    # check that the covariance is close to the identity
    # @show cov(y')
    @test maximum(abs(cov(y')-I)) < 1e-1

    # check that the mean is close to zero
    # @show mean(y,2)
    @test maximum(abs(mean(y,2))) < 1e-1
end


@testset "Whitened ZCA" begin
    nin, nout = 4, 4
    n = 50
    μ = zeros(nin)
    Λ = UpperTriangular(rand(nin,nin))
    Σ = Λ'*Λ
    mv = MultivariateNormal(μ, Σ)
    x = rand(mv, n)

    # learn the whitening by passing over the data a few times
    # note: since we do this online, it should approach the "true"
    # value in the limit
    totn = 100n
    w = Whiten(nin, nout, lookback=10n, method=:zca)
    for i=1:totn
        learn!(w, x[:,mod1(i,n)])
    end

    # compute the projected output
    y = zeros(nout,n)
    for (xi,yi) in each_obs(x,y)
        yi[:] = transform!(w,xi)
    end

    # check that the mean is close to zero
    # @show mean(y,2)
    @test maximum(abs(mean(y,2))) < 1e-1
end


@testset "Distributions" begin
    n = 4
    μ = rand(n)
    σ = rand(n)
    t = MvNormalTransformation(μ, σ)
    @test typeof(t.dist.Σ) <: Distributions.PDiagMat
    @test t.n == n
    @test t.nμ == n
    @test t.nU == n
    @test input_length(t) == 2n
    @test output_length(t) == n
    newx = rand(2n)
    transform!(t, newx)
    grad!(t)
    @test t.dist.Σ.diag ≈ newx[n+1:end] .^ 2
    @test t.dist.Σ.inv_diag ≈ 1 ./ (newx[n+1:end] .^ 2)

    U = rand(n,n)
    t = MvNormalTransformation(μ, U*U')
    @test typeof(t.dist.μ) <: Vector{Float64}
    @test typeof(t.dist.Σ) <: Distributions.PDMat
    @test t.n == n
    @test t.nμ == n
    @test t.nU == div(n*(n+1), 2)
    @test input_length(t) == n + div(n*(n+1), 2)
    @test output_length(t) == n
    newx = rand(input_length(t))
    transform!(t, newx)
    grad!(t)
    @test t.dist.μ == newx[1:n]
    cf = t.dist.Σ.chol[:UL]
    @test cf[1,2] == newx[n+2]
    @test cf[end] == newx[end]

    # test_gradient(t)
end

@testset "Affine" begin
    nin, nout = 2, 3
    input = rand(nin)
    target = rand(nout)
    a = Affine(nin, nout)
    loss = L2DistLoss()
    w, b = a.params.views
    x, y = input_value(a), output_value(a)
    ∇w, ∇b = a.params.∇_views
    ∇x, ∇y = input_grad(a), output_grad(a)
    nparams = nout*(nin+1)

    for i=1:2
        output = transform!(a, input)

        @test y == w * x + b
        @test size(x) == (nin,)
        @test size(w) == (nout,nin)
        @test size(b) == (nout,)
        @test size(y) == (nout,)
        @test size(∇x) == (nin,)
        @test size(∇w) == (nout,nin)
        @test size(∇b) == (nout,)
        @test size(∇y) == (nout,)
        @test size(output) == (nout,)
        @test size(params(a)) == (nparams,)
        @test size(grad(a)) == (nparams,)

        l = value(loss, target, output)
        dl = deriv(loss, target, output)
        grad!(a, dl)

        @test grad(a.output) == dl
        @test ∇w ≈ repmat(input', nout, 1) .* repmat(dl, 1, nin)
        @test ∇b == dl
        @test ∇x ≈ w' * dl
    end

    test_gradient(a)
end

@testset "Linear" begin
    nin, nout = 2, 3
    input = rand(nin)
    target = rand(nout)
    t = Linear(nin, nout)
    loss = L2DistLoss()
    w = t.params.views[1]
    x, y = input_value(t), output_value(t)
    ∇w = t.params.∇_views[1]
    ∇x, ∇y = input_grad(t), output_grad(t)
    nparams = nout*nin

    for i=1:2
        output = transform!(t, input)

        wx = w * x
        @test y ≈ wx
        @test size(x) == (nin,)
        @test size(w) == (nout,nin)
        @test size(y) == (nout,)
        @test size(∇x) == (nin,)
        @test size(∇w) == (nout,nin)
        @test size(∇y) == (nout,)
        @test size(output) == (nout,)
        @test size(params(t)) == (nparams,)
        @test size(grad(t)) == (nparams,)

        l = value(loss, target, output)
        dl = deriv(loss, target, output)
        grad!(t, dl)

        @test grad(t.output) == dl
        @test ∇w ≈ repmat(input', nout, 1) .* repmat(dl, 1, nin)
        @test ∇x ≈ w' * dl
    end

    test_gradient(t, 1e-5)
end

@testset "LayerNorm" begin
    n = 3
    input = rand(n)
    t = LayerNorm(n, α=1.0)
    g, b = t.params.views
    a, y = input_value(t), output_value(t)
    ∇g, ∇b = t.params.∇_views
    ∇a, ∇y = input_grad(t), output_grad(t)
    nparams = 2n

    for i=1:2
        output = transform!(t, input)

        @test y ≈ g .* (a .- mean(a)) ./ std(a) .+ b
        @test size(a) == (n,)
        @test size(g) == (n,)
        @test size(b) == (n,)
        @test size(y) == (n,)
        @test size(∇a) == (n,)
        @test size(∇g) == (n,)
        @test size(∇b) == (n,)
        @test size(∇y) == (n,)
        @test size(output) == (n,)
        @test size(params(t)) == (nparams,)
        @test size(grad(t)) == (nparams,)
    end

    # first test with g=ones, b=zeros, then test with random number
    test_gradient(t, 1e-5)
    g[:] = rand(n)
    b[:] = rand(n)
    test_gradient(t, 1e-5)
end

@testset "Activations" begin
    n = 2
    input = rand(n)
    for s in Transformations.activations
        f = Activation{s,Float64}(n)
        output = transform!(f, input)
        @test output == map(@eval($s), input)

        grad!(f, ones(2))
        @test f.input.∇ == map(@eval($(Symbol(s,"′"))), input)

        test_gradient(f)
    end
end


@testset "Chain" begin
    n1, n2, n3 = 4,5,2
    input = rand(n1)

    T = Float64
    chain = Chain(T,
        Affine(T, n1, n2),
        Activation{:relu,T}(n2),
        Affine(T, n2, n3),
        Activation{:logistic,T}(n3)
    )

    @test length(chain.ts) == 4
    @test chain.ts[1].input.val === chain.input.val
    @test chain.ts[end].output.val === chain.output.val

    x = input
    for t in chain.ts
        x = transform!(t, x)
        @test x ≈ output_value(t)
    end
    y = transform!(chain, input)
    @test y ≈ output_value(chain.ts[end])
    @test y ≈ x

    # first compute the chain of transformations manually,
    manual_output = input
    for t in chain.ts
        manual_output = transform!(t, manual_output)
    end

    # now do it using the chain, and make sure it matches
    output = transform!(chain, input)
    @test manual_output == output

    test_gradient(chain)
end

@testset "ResidualLayer" begin
    n = 3
    f = nnet(3, 3, [4], layernorm=false)
    t = ResidualLayer(n, f)
    @test f === t.f

    x = rand(n)
    x2 = copy(x)
    y = copy(transform!(t, x))
    @test x == x2
    y2 = transform!(t, x)
    @test y == y2
    @test y ≈ transform!(f, x) + x2

    ∇y = rand(n)
    grad!(t, ∇y)
    @test output_grad(f) == ∇y

    test_gradient(t, 1e-8)
end


@testset "resnet" begin
    nin, nout = 3, 2
    nblocks = 2
    t = resnet(nin, nout, nblocks, nh=[2], layernorm=false)
    # @show t

    @test length(t.ts) == nblocks+1
    @test isa(t.ts[end], Affine)
    for i=1:nblocks
        @test isa(t.ts[i], ResidualLayer)
    end

    x = rand(nin)
    y = copy(transform!(t, x))

    x̂ = copy(transform!(t.ts[1], x))
    for i=2:nblocks+1
        x̂ = transform!(t.ts[i])
    end
    @test y ≈ x̂

    ∇y = rand(nout)
    grad!(t, ∇y)
    @test output_grad(t) == ∇y

    test_gradient(t)
end

@testset "ConvFilter" begin
    nin = (3,3)
    nfilter = (2,2)
    stride = (1,1)
    nrf, ncf = nfilter
    x = reshape(linspace(1,9,9), nin...)
    f = ConvFilter(nin, nfilter, stride)

    @test f.sizein == nin
    @test f.sizefilter == nfilter
    @test f.sizeout == (2,2)

    w, b = f.params.views
    b[1] = 0.5
    @test size(w) == nfilter
    @test size(b) == (1,)

    y = transform!(f, x)
    nr,nc = f.sizeout
    for r=1:nr, c=1:nc
        @test y[r,c] ≈ sum(w .* view(x, r:r+nrf-1, c:c+ncf-1)) + b[1]
    end

    ∇y = rand(f.sizeout...)
    grad!(f, ∇y)

    ∇x = input_grad(f)
    ∇w, ∇b = f.params.∇_views
    for i=1:nrf, j=1:ncf
        @test ∇w[i,j] ≈ sum(view(x, i:nr+i-1, j:nc+j-1) .* ∇y)
    end
    @test ∇b[1] == sum(∇y)
    for r=1:nin[1], c=1:nin[2]
        @test ∇x[r,c] ≈ sum(view(w, nrf:-1:1, ncf:-1:1) .*
            Transformations.TileView{Float64,2,typeof(∇y)}(∇y, (r-nrf+1,c-ncf+1), (nrf,ncf)))
    end

    # TODO: once stride is implemented, test that
end

@testset "Differentiable" begin
    f(θ) = sum(100θ.^2)
    df(θ) = map(θi -> 200θi, θ)
    t = tfunc(f, 2, df)
    θ = params(t)
    θ[:] = [1.,2.]
    @test transform!(t) == f(θ)
    grad!(t)
    @test grad(t) == df(θ)

    t = tfunc(rosenbrock, 4, rosenbrock_gradient)
    @test typeof(t) <: OnceDifferentiable{Float64}
    θ = params(t)
    @test size(θ) == (4,)
    θ[:] = linspace(0,3,4)
    @test transform!(t) == rosenbrock(θ)
    grad!(t)
    @test grad(t) == rosenbrock_gradient(θ)

    test_gradient(t)
end
