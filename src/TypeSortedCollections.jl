__precompile__()

module TypeSortedCollections

export
    TypeSortedCollection,
    num_types

using Compat

const TupleOfVectors = Tuple{Vararg{Vector{T} where T}}

struct TypeSortedCollection{D<:TupleOfVectors, N}
    data::D
    indices::NTuple{N, Vector{Int}}

    function TypeSortedCollection{D, N}() where {D<:TupleOfVectors, N}
        fieldcount(D) == N || error()
        data = tuple((T[] for T in D.parameters)...)
        indices = tuple((Int[] for i in eachindex(data))...)
        new{D, N}(data, indices)
    end

    TypeSortedCollection{D}() where {D<:TupleOfVectors} = TypeSortedCollection{D, length(D.parameters)}()
    TypeSortedCollection{D, N}(A) where {D<:TupleOfVectors, N} = append!(TypeSortedCollection{D, N}(), A)
    TypeSortedCollection{D}(A) where {D<:TupleOfVectors} = append!(TypeSortedCollection{D}(), A)

    function TypeSortedCollection(data::D, indices::NTuple{N, Vector{Int}}) where {D<:TupleOfVectors, N}
        fieldcount(D) == N || error()
        l = mapreduce(length, +, 0, data)
        l == mapreduce(length, +, 0, indices) || error()
        allindices = Base.Iterators.flatten(indices)
        allunique(allindices) || error()
        extrema(allindices) == (1, l) || error()
        new{D, N}(data, indices)
    end
end

function TypeSortedCollection(A, preserve_order::Bool = false)
    if preserve_order
        data = Vector[]
        indices = Vector{Vector{Int}}()
        for (i, x) in enumerate(A)
            T = typeof(x)
            if isempty(data) || T != eltype(last(data))
                push!(data, T[])
                push!(indices, Int[])
            end
            push!(last(data), x)
            push!(last(indices), i)
        end
        TypeSortedCollection(tuple(data...), tuple(indices...))
    else
        types = unique(typeof.(A))
        D = Tuple{[Vector{T} for T in types]...}
        TypeSortedCollection{D}(A)
    end
end

function TypeSortedCollection(A, indices::NTuple{N, Vector{Int}} where {N})
    @assert length(A) == sum(length, indices)
    data = []
    for indicesvec in indices
        @assert length(indicesvec) > 0
        T = typeof(A[indicesvec[1]])
        Tdata = Vector{T}()
        sizehint!(Tdata, length(indicesvec))
        push!(data, Tdata)
        for i in indicesvec
            A[i]::T
            push!(Tdata, A[i])
        end
    end
    TypeSortedCollection(tuple(data...), indices)
end

function Base.append!(dest::TypeSortedCollection, A)
    eltypes = map(eltype, dest.data)
    type_to_tuple_index = Dict(T => i for (i, T) in enumerate(eltypes))
    index = length(dest)
    for x in A
        T = typeof(x)
        haskey(type_to_tuple_index, T) || throw(ArgumentError("Cannot store elements of type $T; must be one of $eltypes."))
        i = type_to_tuple_index[T]
        push!(dest.data[i], x)
        push!(dest.indices[i], (index += 1))
    end
    dest
end

Base.@pure num_types(::Type{<:TypeSortedCollection{<:Any, N}}) where {N} = N
num_types(x::TypeSortedCollection) = num_types(typeof(x))

Base.isempty(x::TypeSortedCollection) = all(isempty, x.data)
Base.empty!(x::TypeSortedCollection) = foreach(empty!, x.data)
Base.length(x::TypeSortedCollection) = mapreduce(length, +, 0, x.data)
Base.indices(x::TypeSortedCollection) = x.indices # semantics are a little different from Array, but OK

# Trick from StaticArrays:
@inline first_tsc(a1::TypeSortedCollection, as::Union{<:TypeSortedCollection, AbstractVector}...) = a1
@inline first_tsc(a1, as::Union{<:TypeSortedCollection, AbstractVector}...) = first_tsc(as...)

# inspired by Base.ith_all
@inline _getindex_all(::Val, j, vecindex) = ()
Base.@propagate_inbounds _getindex_all(vali::Val{i}, j, vecindex, a1, as...) where {i} = (_getindex(vali, j, vecindex, a1), _getindex_all(vali, j, vecindex, as...)...)
@inline _getindex(::Val, j, vecindex, a::AbstractVector) = a[vecindex]
@inline _getindex(::Val{i}, j, vecindex, a::TypeSortedCollection) where {i} = a.data[i][j]
@inline _setindex!(::Val, j, vecindex, a::AbstractVector, val) = a[vecindex] = val
@inline _setindex!(::Val{i}, j, vecindex, a::TypeSortedCollection, val) where {i} = a.data[i][j] = val

@inline lengths_match(l::Int) = true
@inline lengths_match(l::Int, a1, as...) = length(a1) == l && lengths_match(l, as...)
@noinline lengths_match_fail() = throw(DimensionMismatch("Lengths of input collections do not match."))

@inline indices_match(::Val, indices::Vector{Int}, ::AbstractVector) = true
@inline function indices_match(::Val{i}, indices::Vector{Int}, tsc::TypeSortedCollection) where {i}
    tsc_indices = tsc.indices[i]
    length(indices) == length(tsc_indices) || return false
    @inbounds for j in eachindex(indices, tsc_indices)
        indices[j] == tsc_indices[j] || return false
    end
    true
end
@inline indices_match(vali::Val, indices::Vector{Int}, a1, as...) = indices_match(vali, indices, a1) && indices_match(vali, indices, as...)
@noinline indices_match_fail() = throw(ArgumentError("Indices of TypeSortedCollections do not match."))

@generated function Base.map!(f, dest::Union{TypeSortedCollection{<:Any, N}, AbstractArray}, args::Union{TypeSortedCollection{<:Any, N}, AbstractArray}...) where {N}
    expr = Expr(:block)
    push!(expr.args, :(Base.@_inline_meta))
    push!(expr.args, :(leading_tsc = first_tsc(dest, args...)))
    push!(expr.args, :(@boundscheck lengths_match(length(leading_tsc), dest, args...) || lengths_match_fail()))
    for i = 1 : N
        vali = Val(i)
        push!(expr.args, quote
            let inds = leading_tsc.indices[$i]
                @boundscheck indices_match($vali, inds, dest, args...) || indices_match_fail()
                for j in linearindices(inds)
                    vecindex = inds[j]
                    _setindex!($vali, j, vecindex, dest, f(_getindex_all($vali, j, vecindex, args...)...))
                end
            end
        end)
    end
    quote
        $expr
        dest
    end
end

@generated function Base.foreach(f, As::Union{<:TypeSortedCollection{<:Any, N}, AbstractVector}...) where {N}
    expr = Expr(:block)
    push!(expr.args, :(Base.@_inline_meta))
    push!(expr.args, :(leading_tsc = first_tsc(As...)))
    push!(expr.args, :(@boundscheck lengths_match(length(leading_tsc), As...) || lengths_match_fail()))
    for i = 1 : N
        vali = Val(i)
        push!(expr.args, quote
            let inds = leading_tsc.indices[$i]
                @boundscheck indices_match($vali, inds, As...) || indices_match_fail()
                @inbounds for j in linearindices(inds)
                    vecindex = inds[j]
                    f(_getindex_all($vali, j, vecindex, As...)...)
                end
            end
        end)
    end
    quote
        $expr
        nothing
    end
end

@generated function Base.mapreduce(f, op, v0, tsc::TypeSortedCollection{<:Any, N}) where {N}
    expr = Expr(:block)
    push!(expr.args, :(Base.@_inline_meta))
    push!(expr.args, :(ret = Base.r_promote(op, v0)))
    for i = 1 : N
        push!(expr.args, quote
            let vec = tsc.data[$i]
                ret = mapreduce(f, op, ret, vec)
            end
        end)
    end
    quote
        $expr
        return ret
    end
end

end # module
