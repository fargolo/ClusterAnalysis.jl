using Statistics
using Tables

"""
    euclidian(a::AbstractArray, b::AbstractArray)

Calculate euclidian distance from two arrays.
"""
function euclidian(a::AbstractArray, b::AbstractArray)
    @assert length(a) == length(b)
    dist = √(sum((a - b).^2))
    return dist
end

"""
    Kmeans(df::Matrix{T}, K::Int) where {T<:AbstractFloat}

Create the K-means cluster model and also initialize calculating the first centroids, estimating clusters and total variance.

# Constructors
```julia
Kmeans(df::Matrix{T}, K::Int) where {T<:AbstractFloat} : default constructor. 
Kmeans(df::Matrix{T}, K::Int) where {T} = Kmeans(Matrix{Float64}(df), K) : where df is an Matrix{T} where T is not a subtype of AbstractFloat.
Kmeans(df, K::Int) : where df implements the Tables.jl interface, e.g.: DataFrame type from DataFrames.jl package.   
```

# Fields
- df::Matrix{T}: return the dataset in a Matrix form.
- K::Int: return the number of cluster of the model.
- centroids::Vector{Vector{T}}: returns the values of each variable for each centroid 
- cluster::Vector{T}: return the cluster output for each observation in the dataset.
- variance::T: return the total variance of model, summing the variance of each cluster.
Where T is a subtype of AbstractFloat.
"""
mutable struct Kmeans{T<:AbstractFloat}
    df::Matrix{T}
    K::Int
    centroids::Vector{Vector{T}}
    cluster::Vector{T}
    variance::T

    # Internal Constructor
    function Kmeans(df::Matrix{T}, K::Int) where {T<:AbstractFloat}
        
        # generate random centroids
        nl = size(df, 1)
        indexes = rand(1:nl, K)
        centroids = Vector{T}[df[i,:] for i in indexes]

        # estimate clusters
        cluster = T[]
        for obs in eachrow(df)
            dist = [euclidian(obs, c) for c in centroids]
            cl = argmin(dist)
            push!(cluster, cl)
        end

        # evaluate total variance
        cl = sort(unique(cluster))
        variance = zero(T)
        for k in cl
            df_filter = df[cluster .== k, :]
            variance += sum( var.( eachcol(df_filter) ) )
        end

        return new{T}(df, K, centroids, cluster, variance)
    end
end

# External Constructors
Kmeans(df::Matrix{T}, K::Int) where {T} = Kmeans(Matrix{Float64}(df), K)

function Kmeans(df, K::Int)
    Tables.istable(df) ? (df = Tables.matrix(df)) : throw(ArgumentError("The df argument passed does not implement the Tables.jl interface.")) 
    return Kmeans(df, K)
end

"""
    iteration!(model::Kmeans{T}, niter::Int) where {T<:AbstractFloat}

Random initialize K cluster centroids, then estimate cluster and update centroid `niter` times,
calculate the total variance and evaluate if it's the optimum result.
"""
function iteration!(model::Kmeans{T}, niter::Int) where {T<:AbstractFloat}
    
    # Randomly initialize K cluster centroids
    nl = size(model.df, 1)
    indexes = rand(1:nl, model.K)
    centroids = Vector{T}[model.df[i,:] for i in indexes]
    cluster = T[]

    # estimate cluster and update centroids
    for _ in 1:niter

        # estimate cluster to all observations 
        cls = T[]
        for obs in eachrow(model.df)
            dist = [euclidian(obs, c) for c in centroids]
            cl = argmin(dist)
            push!(cls, cl)
        end
    
        # update centroids using the mean
        cl = sort(unique(cls))
        ctr = Vector{Float64}[]
        for k in cl
            df_filter = model.df[cls .== k, :]
            push!( ctr, mean.(eachcol(df_filter)) )
        end
    
        # update the variables
        cluster = cls
        centroids = ctr
    end

    # evaluate total variance of all cluster
    cl = sort(unique(cluster))
    variance = zero(T)
    for k in cl
        df_filter = model.df[cluster .== k, :]
        variance += sum( var.(eachcol(df_filter)) )
    end

    # evaluate if update or not the kmeans model (minimizing the total variance) 
    if variance < model.variance
        model.centroids = centroids
        model.cluster = cluster
        model.variance = variance
    end
end

"""
    fit!(model::Kmeans, nstart::Int=50, niter::Int=10)

execute `nstart` times the iteration! function to try obtain the global optimum.
"""
function fit!(model::Kmeans, nstart::Int=50, niter::Int=10)
    for _ in 1:nstart
        iteration!(model, niter)
    end  
end
