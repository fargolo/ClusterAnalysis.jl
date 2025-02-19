"""
    struct KmeansResult{T<:AbstractFloat}
        K::Int
        centroids::Vector{Vector{T}}
        cluster::Vector{Int}
        withinss::T
        iter::Int
    end

Object resulting from kmeans algorithm that contains the number of clusters, centroids, clusters prediction, 
total-variance-within-cluster and number of iterations until convergence.
"""
struct KmeansResult{T<:AbstractFloat}
    K::Int
    centroids::Vector{Vector{T}}
    cluster::Vector{Int}
    withinss::T
    iter::Int
end

function Base.print(io::IO, model::KmeansResult{T}) where {T<:AbstractFloat}
    p = ["     $(v)\n" for v in model.centroids]

    print(IOContext(io, :limit => true), "KmeansResult{$T}:
 K = $(model.K)
 centroids = [\n", p..., " ]
 cluster = ", model.cluster, "
 within-cluster sum of squares = $(model.withinss)
 iterations = $(model.iter)")
end

Base.show(io::IO, model::KmeansResult) = print(io, model)

"""
    ClusterAnalysis.euclidean(a::AbstractVector, b::AbstractVector)

Calculate euclidean distance from two vectors. √∑(aᵢ - bᵢ)².

# Arguments (positional)
- `a`: First vector.
- `b`: Second vector.

# Example
```julia
julia> using ClusterAnalysis

julia> a = rand(100); b = rand(100);

julia> ClusterAnalysis.euclidean(a, b)
3.8625780213774954
```
"""
function euclidean(a::AbstractVector{T}, 
                   b::AbstractVector{T}) where {T<:AbstractFloat}
    @assert length(a) == length(b)

    # euclidean(a, b) = √∑(aᵢ- bᵢ)²
    s = zero(T)
    @simd for i in eachindex(a)
        @inbounds s += (a[i] - b[i])^2
    end
    return √s
end

"""
    ClusterAnalysis.squared_error(data::AbstractMatrix)
    ClusterAnalysis.squared_error(col::AbstractVector)

Function that evaluate the kmeans, using the Sum of Squared Error (SSE).

# Arguments (positional)
- `data` or `col`: Matrix of data observations or a Vector which represents one column of data.

# Example
```julia
julia> using ClusterAnalysis

julia> a = rand(100, 4);

julia> ClusterAnalysis.squared_error(a)
34.71086095943974

julia> ClusterAnalysis.squared_error(a[:, 1])
10.06029322934825
```
"""
function squared_error(data::AbstractMatrix{T}) where {T<:AbstractFloat}
    error = zero(T)
    @simd for i in axes(data, 2)
        error += squared_error(view(data, :, i))
    end
    return error
end

function squared_error(col::AbstractVector{T}) where {T<:AbstractFloat}
    μ = mean(col)
    error = zero(T)
    @simd for i in eachindex(col)
        @inbounds error += (col[i] - μ)^2
    end
    return error
end


"""
    ClusterAnalysis.totalwithinss(data::AbstractMatrix, K::Int, cluster::Vector)

Calculate the total-variance-within-cluster using the `squared_error()` function.

# Arguments (positional)
- `data`: Matrix of data observations.
- `K`: number of clusters.
- `cluster`: Vector of cluster for each data observation.

# Example
```julia
julia> using ClusterAnalysis
julia> using CSV, DataFrames

julia> iris = CSV.read(joinpath(pwd(), "path/to/iris.csv"), DataFrame);
julia> df = iris[:, 1:end-1];
julia> model = kmeans(df, 3);

julia> ClusterAnalysis.totalwithinss(Matrix(df), model.K, model.cluster)
78.85144142614601
```
"""
function totalwithinss(data::AbstractMatrix{T}, K::Int, cluster::AbstractVector{Int}) where {T<:AbstractFloat}
    # evaluate total-variance-within-clusters
    error = zero(T)
    @simd for k in 1:K
        error += squared_error(data[cluster .== k, :])
    end
    return error
end

"""
    kmeans(table, K::Int; nstart::Int = 1, maxiter::Int = 10, init::Symbol = :kmpp)
    kmeans(data::AbstractMatrix, K::Int; nstart::Int = 1, maxiter::Int = 10, init::Symbol = :kmpp)

Classify all data observations in k clusters by minimizing the total-variance-within each cluster.

# Arguments (positional)
- `table` or `data`: table or Matrix of data observations.
- `K`: number of clusters.

## Keyword 
- `nstart`: number of starts.
- `maxiter`: number of maximum iterations.
- `init`: centroids inicialization algorithm - `:kmpp` (default) or `:random`.

# Example
```julia
julia> using ClusterAnalysis
julia> using CSV, DataFrames

julia> iris = CSV.read(joinpath(pwd(), "path/to/iris.csv"), DataFrame);
julia> df = iris[:, 1:end-1];

julia> model = kmeans(df, 3)
KmeansResult{Float64}:
 K = 3
 centroids = [
     [5.932307692307693, 2.755384615384615, 4.42923076923077, 1.4384615384615382]
     [5.006, 3.4279999999999995, 1.462, 0.24599999999999997]
     [6.874285714285714, 3.088571428571429, 5.791428571428571, 2.117142857142857]
 ]
 cluster = [2, 2, 2, 2, 2, 2, 2, 2, 2, 2  …  3, 3, 1, 3, 3, 3, 1, 3, 3, 1]
 within-cluster sum of squares = 78.85144142614601
 iterations = 7
```

# Pseudo-code of the algorithm: 
* Repeat `nstart` times:  
    1. Initialize `K` clusters centroids using KMeans++ algorithm or random init.  
    2. Estimate clusters.  
    3. Repeat `maxiter` times:  
        * Update centroids using the mean().  
        * Reestimates the clusters.  
        * Calculate the total-variance-within-cluster.  
        * Evaluate the stop rule.  
* Keep the best result (minimum total-variance-within-cluster) of all `nstart` executions.

For more detailed explanation of the algorithm, check the 
[`Algorithm's Overview of KMeans`](https://github.com/AugustoCL/ClusterAnalysis.jl/blob/main/algo_overview/kmeans_overview.md).
""" 
function kmeans(table, K::Int; kwargs...)
    Tables.istable(table) ? (data = Tables.matrix(table)) : throw(ArgumentError("The table argument passed does not implement the Tables.jl interface."))
    return kmeans(data, K; kwargs...)
end

kmeans(data::AbstractMatrix{T}, K::Int; kwargs...) where {T} = kmeans(convert(Matrix{Float64}, data), K; kwargs...)

function kmeans(data::AbstractMatrix{T}, K::Int;
                nstart::Int = 1,
                maxiter::Int = 10,
                init::Symbol = :kmpp) where {T<:AbstractFloat}

    nl = size(data, 1)

    centroids = Vector{Vector{T}}(undef, K)
    cluster = Vector{Int}(undef, nl)
    withinss = Inf
    iter = 0

    # run multiple kmeans to get the best result
    for _ in 1:nstart

        new_centroids, new_cluster, new_withinss, new_iter = _kmeans(data, K, maxiter, init)

        if new_withinss > withinss
            centroids .= new_centroids
            cluster .= new_cluster
            withinss = new_withinss
            iter = new_iter
        end
    end

    return KmeansResult(K, centroids, cluster, withinss, iter)
end

function _kmeans(data::AbstractMatrix{T}, K::Int, maxiter::Int, init::Symbol) where {T<:AbstractFloat}

    nl = size(data, 1)

    # generate random centroids
    centroids = _initialize_centroids(data, K, init)

    # first clusters estimate
    cluster = Vector{Int}(undef, nl)
    for (i, obs) in enumerate(eachrow(data))
        dist = [euclidean(obs, c) for c in centroids]
        @inbounds cluster[i] = argmin(dist)
    end

    # first evaluation of total-variance-within-cluster
    withinss = totalwithinss(data, K, cluster)

    # variables to update during the iterations
    new_centroids = copy(centroids)
    new_cluster = copy(cluster)
    iter = 1
    norms = norm.(centroids)

    # start kmeans iterations until maxiter or convergence
    for _ in 2:maxiter

        # update new_centroids using the mean
        @simd for k in 1:K             # mean.(eachcol(data[new_cluster .== k, :]))
            @inbounds new_centroids[k] = vec(mean(view(data, new_cluster .== k, :), dims = 1))
        end

        # estimate cluster to all observations
        for (i, obs) in enumerate(eachrow(data))
            dist = [euclidean(obs, c) for c in new_centroids]
            @inbounds new_cluster[i] = argmin(dist)
        end

        # update iter, withinss-variance and calculate centroid norms
        new_withinss = totalwithinss(data, K, new_cluster)
        new_norms = norm.(new_centroids)
        iter += 1

        # convergence rule
        norm(norms - new_norms) ≈ 0 && break

        # update centroid norms
        norms .= new_norms

        # update centroids, cluster and whithinss
        if new_withinss > withinss
            centroids .= new_centroids
            cluster .= new_cluster
            withinss = new_withinss
        end

    end

    return centroids, cluster, withinss, iter
end

function _initialize_centroids(data::AbstractMatrix{T}, K::Int, init::Symbol) where {T<:AbstractFloat}
    nl = size(data, 1)

    if init == :random
        indexes = rand(1:nl, K)
        centroids = Vector{T}[data[i, :] for i in indexes]
    elseif init == :kmpp
        centroids = Vector{Vector{T}}(undef, K)
        centroids[1] = data[rand(1:nl), :]

        # distance vector for each observation
        dists = Vector{T}(undef, nl)

        # get each new centroid by the furthest observation (maximum distance)
        for k in 2:K

            # for each observation get the nearest centroid by the minimum distance
            for (i, row) in enumerate(eachrow(data))
                dist_c = [euclidean(row, c) for c in @view centroids[1:(k-1)]]
                @inbounds dists[i] = minimum(dist_c)
            end

            # new centroid by the furthest observation
            @inbounds centroids[k] = data[argmax(dists), :]
        end
    else
        throw(ArgumentError("The symbol :$init is not a valid argument. Use :random or :kmpp."))
    end

    return centroids
end
