# MultiVector for CliffordAlgebras.jl

import Base.zero, Base.one, Base.iszero, Base.isone
import Base.==, Base.show, Base.eltype, Base.convert
import Base.getproperty, Base.propertynames, Base.conj
import Base.reverse, Base.~

"""
    MultiVector{CA,T,BI}

Type for a multivector belonging to the algebra CA<:CliffordAlgbra with vector coefficients of type T.
Coefficients are stored using a sparse coding, and only the coefficients of the basis indices stored in the tuple BI are considered.
"""
struct MultiVector{CA,T,BI,K}
    c::NTuple{K,T}
    function MultiVector(
        CA::Type{<:CliffordAlgebra},
        BI::NTuple{K,Integer},
        c::NTuple{K,T},
    ) where {K,T<:Real}
        @assert length(BI) > 0 
        #@assert issorted(BI) && allunique(BI)
        new{CA,T,convert(NTuple{K,Int}, BI),K}(c)
    end
end

"""
    MultiVector(::CliffordAlgebra, a::Real)
    MultiVector(::Type{<:CliffordAlgebra}, a::Real)

Creates a MultiVector from the real number a with only a scalar component. The internal storage type of the MultiVector is the type of a.
"""
MultiVector(CA::Type{<:CliffordAlgebra}, a::T) where {T<:Real} = MultiVector(CA, (1,), (a,))
MultiVector(ca::CliffordAlgebra, a::T) where {T<:Real} = MultiVector(typeof(ca), a)

"""
    MultiVector(::CliffordAlgebra, v::NTuple{N,T}) where {N,T<:Real}
    MultiVector(::Type{<:CliffordAlgebra}, v::NTuple{N,T}) where {N,T<:Real}

Creates a MultiVector by converting the provided vector v to a 1-vector. The internal storage type of the MultiVector is T.
"""
function MultiVector(CA::Type{<:CliffordAlgebra}, v::NTuple{N,T}) where {N,T<:Real}
    @assert N == order(CA) "Dimension count mismatch."
    MultiVector(CA, Tuple(2:N+1), v)
end

MultiVector(ca::CliffordAlgebra, v::NTuple{N,T}) where {N,T<:Real} =
    MultiVector(typeof(ca), v)

zero(::Type{<:MultiVector{CA,T}}) where {CA,T} = MultiVector(CA, zero(T))
zero(mv::MultiVector) = zero(typeof(mv))

one(::Type{<:MultiVector{CA,T}}) where {CA,T} = MultiVector(CA, one(T))
one(mv::MultiVector) = one(typeof(mv))

iszero(mv::MultiVector) = all(iszero.(coefficients(mv)))
isone(mv::MultiVector) =
    baseindices(mv)[1] == 1 &&
    isone(coefficients(mv)[1]) &&
    all(iszero.(coefficients(mv)[2:end]))

    
(==)(a::MultiVector, b::MultiVector) = false

@generated function (==)(a::MultiVector{CA}, b::MultiVector{CA}) where {CA}
    bia = baseindices(a)
    bib = baseindices(b)
    bi = union(bia,bib)
    cond = foldr( (exl,exr) -> Expr(:&&, exl, exr), (
        begin
            ka = findfirst(isequal(i), bia)
            kb = findfirst(isequal(i), bib)
            if isnothing(ka)
                :(iszero(cb[$kb]))
            elseif isnothing(kb)
                :(iszero(ca[$ka]))
            else
                :(ca[$ka] == cb[$kb])
            end
        end
        for i in bi
    ))
    quote
        ca = coefficients(a)
        cb = coefficients(b)
        return $cond    
    end
end

(==)(a::MultiVector{CA,Ta,BI}, b::MultiVector{CA,Tb,BI}) where {CA,Ta,Tb,BI} = coefficients(a) == coefficients(b)

(==)(a::MultiVector{CA}, b::Real) where CA = a == MultiVector(CA, b)
(==)(a::Real, b::MultiVector) = b == a


"""
    coefficients(::MultiVector)

Returns the sparse coefficients of the MultiVector.
"""
coefficients(mv::MultiVector) = getfield(mv,:c)


"""
    algebra(::MultiVector)
    algebra(::Type{<:MultiVector})

Returns the CliffordAlgebra instance to which the MultiVector belongs.
"""
algebra(::Type{<:MultiVector{CA}}) where {CA} = CA.instance
algebra(mv::MultiVector) = algebra(typeof(mv))


"""
    Algebra(::MultiVector)
    Algebra(::Type{<:MultiVector})

Returns the CliffordAlgebra type to which the MultiVector belongs.
"""
Algebra(::Type{<:MultiVector{CA}}) where {CA} = CA
Algebra(mv::MultiVector) = Algebra(typeof(mv))


eltype(::Type{<:MultiVector{CA,T}}) where {CA,T} = T
eltype(mv::MultiVector) = eltype(typeof(mv))


"""
    baseindices(::MultiVector)
    baseindices(::Type{<:MultiVector})

Returns the indices for the sparse MultiVector basis.
"""
baseindices(::Type{<:MultiVector{CA,T,BI}}) where {CA,T,BI} = BI
baseindices(mv::MultiVector) = baseindices(typeof(mv))

convert(T::Type{<:Real}, mv::MultiVector{CA,Tmv,(1,),1}) where {CA,Tmv} =
    convert(T, coefficients(mv)[1])

function convert(T::Type{<:Real}, mv::MultiVector{CA,Tmv,BI}) where {CA,Tmv,BI}
    if BI[1] == 1
        if all(iszero.(coefficients(mv)[2:end]))
            convert(T, coefficients(mv)[1])
        else
            throw(InexactError(:convert, T, mv))
        end
    else
        if all(iszero.(coefficients(mv)))
            zero(T)
        else
            throw(InexactError(:convert, T, mv))
        end
    end
end

"""
    scalar(mv::MultiVector)

Returns the scalar component of the multivector. The result if of the internal storage type eltype(mv).
"""
function scalar(mv::MultiVector{CA,T,BI}) where {CA,T,BI}
    if BI[1] == 1
        coefficients(mv)[1]
    else
        zero(T)
    end
end


"""
    prune(::MultiVector ; rtol = 1e-8 )

Returns a new MultiVector with all basis vectors removed from the sparse basis whose coefficients fall below the relative magnitude threshold.
This function is not type stable, because the return type depends on the sparse basis.
"""
function prune(mv::MultiVector; rtol = 1e-8)
    threshold = rtol * abs(maximum(coefficients(mv)))
    selector = findall(c -> abs(c) > threshold, coefficients(mv))
    if isempty(selector)
        zero(mv)
    else
        MultiVector(Algebra(mv), baseindices(mv)[selector], coefficients(mv)[selector])
    end
end

"""
    extend(::MultiVector)

Returns a new MultiVector with a non-sparse coefficient coding. This can be useful to manage type stability.
"""
@generated function extend(mv::MultiVector{CA}) where CA
    bi = baseindices(mv)
    d = dimension(CA)
    T = eltype(mv)
    bexpr = Expr(:call,:tuple)
    cexpr = Expr(:call,:tuple)
    for k = 1:d
        push!(bexpr.args, k)
        n = findfirst(isequal(k), bi)
        if isnothing(n)
            push!(cexpr.args, :(zero($T)))
        else
            push!(cexpr.args, :(coefficients(mv)[$n]))
        end
    end
    :(@inbounds MultiVector(CA, $bexpr, $cexpr))
end


"""
    grade(::MultiVector, k::Integer)

Projects the MultiVector onto the k-vectors.
"""
function grade(mv::MultiVector, k::Integer)
    ca = algebra(mv)
    selector = findall(isequal(k), map(i -> basegrade(ca, i), baseindices(mv)))
    if isempty(selector)
        zero(mv)
    else
        MultiVector(Algebra(mv), baseindices(mv)[selector], coefficients(mv)[selector])
    end
end


"""
    isgrade(::MultiVector, k::Integer)

Returns true if the MultiVector is of grade k, false if not.
"""
function isgrade(mv::MultiVector, k::Integer)
    ca = algebra(mv)
    all(basegrade(ca,i) == k || iszero(coefficients(mv)[n]) for (n,i) in enumerate(baseindices(mv)))
end


"""
    even(::MultiVector)

Returns the even grade projection of the MultiVector.
"""
function even(mv::MultiVector)
    ca = algebra(mv)
    selector = findall(iseven, map(i -> basegrade(ca, i), baseindices(mv)))
    if isempty(selector)
        zero(mv)
    else
        MultiVector(Algebra(mv), baseindices(mv)[selector], coefficients(mv)[selector])
    end
end


"""
    odd(::MultiVector)

Returns the odd grade projection of the MultiVector.
"""
function odd(mv::MultiVector)
    ca = algebra(mv)
    selector = findall(isodd, map(i -> basegrade(ca, i), baseindices(mv)))
    if isempty(selector)
        zero(mv)
    else
        MultiVector(Algebra(mv), baseindices(mv)[selector], coefficients(mv)[selector])
    end
end

"""
    grin(mv::MultiVector)

Returns the grade involution of the MultiVector, i.e. even(mv) - odd(mv).
"""
grin(mv::MultiVector) = even(mv) - odd(mv)

"""
    dual(mv::MultiVector)

Returns the Poincaré dual of the MultiVector, such that for all basis MultiVectors mv * dual(mv) = pseudoscalar. Dual is a linear map and the images of other MultiVectors follow from the images of the basis MultiVectors.
"""
dual(mv::MultiVector{CA,T,BI,K}) where {CA,T,BI,K} =
    MultiVector(CA, dimension(CA) + 1 .- BI[end:-1:1], coefficients(mv)[end:-1:1])

"""
    reverse(::MultiVector)

Returns the MultiVector that has all the basis vector products reversed.
"""
function reverse(mv::MultiVector)
    # Reverses the order of the canonical basis products
    CA = Algebra(mv)
    BI = baseindices(mv)
    s = map(n -> basereverse(CA, n), BI)
    MultiVector(CA, BI, coefficients(mv) .* s)
end

"""
    ~a
    (~)(::MultiVector)

Returns the reversed MultiVector reverse(a).
"""
(~)(mv::MultiVector) = reverse(mv)


"""
    conj(mv::MultiVector)

Return the conjugate of the MultiVector, i.e. reverse(grin(mv)).
"""
conj(mv::MultiVector) = reverse(grin(mv))


function show_multivector(io::IO, m::MultiVector{CA,T,BI,K}) where {CA,T,BI,K}
    if all(iszero.(coefficients(m)))
        print(io, 0)
    else
        for k = 1:K
            if !iszero(coefficients(m)[k])
                bs = basesymbol(CA, BI[k])
                if bs == Symbol(:𝟏)
                    if coefficients(m)[k] < 0
                        print(io, "-", -coefficients(m)[k])
                    else
                        print(io, "+", coefficients(m)[k])
                    end
                else
                    if coefficients(m)[k] < 0
                        print(io, "-", -coefficients(m)[k], "×", bs)
                    else
                        print(io, "+", coefficients(m)[k], "×", bs)
                    end
                end
            end
        end
        print(io, " ∈ Cl", signature(CA))
    end
end


function show(io::IO, m::MultiVector)
    show_multivector(io, m)
end


"""
    basevector(::CliffordAlgebra, n::Integer)
    basevector(::Type{<:CliffordAlgebra}, n::Integer)

Returns the n-th basis MultiVector of the given CliffordAlgebra.
"""
basevector(CA::Type{<:CliffordAlgebra}, n::Integer) = MultiVector(CA, (n,), (1,))
basevector(ca::CliffordAlgebra, n::Integer) = basevector(typeof(ca), n)


"""
    basevector(::CliffordAlgebra, name::Symbol)
    basevector(::Type{<:CliffordAlgebra}, name::Symbol)

Returns the basis MultiVector with the specified name from the given Clifford Algebra.
"""
function basevector(CA::Type{<:CliffordAlgebra}, name::Symbol)
    baseindex = findfirst(isequal(name), ntuple(k -> basesymbol(CA, k), dimension(CA)))
    if isnothing(baseindex)
        error("Algebra does not have a basis element ", name)
    end
    basevector(CA, baseindex)
end

basevector(ca::CliffordAlgebra, name::Symbol) = basevector(typeof(ca), name)

propertynames(ca::CliffordAlgebra) = ntuple(i -> basesymbol(ca, i), dimension(ca))
propertynames(mv::MultiVector) = propertynames(algebra(mv))


function getproperty(ca::CliffordAlgebra, name::Symbol)
    basevector(ca, name)
end


function getproperty(mv::MultiVector, name::Symbol)
    ca = algebra(mv)
    baseindex = findfirst(isequal(name), ntuple(k -> basesymbol(ca, k), dimension(ca)))
    if isnothing(baseindex)
        error("Algebra does not have a basis element ", name)
    end
    storageindex = findfirst(isequal(baseindex), baseindices(mv))
    if isnothing(storageindex)
        return zero(eltype(mv))
    else
        return coefficients(mv)[storageindex]
    end
end


"""
    pseudoscalar(::CliffordAlgebra)
    pseudoscalar(::Type{<:CliffordAlgebra})

Returns the pseudoscalar of the given algebra.
"""
pseudoscalar(CA::Type{<:CliffordAlgebra}) = MultiVector(CA, (dimension(CA),), (1,))
pseudoscalar(ca::CliffordAlgebra) = pseudoscalar(typeof(ca))

"""
    vector(::MultiVector)

Returns the non-sparse vector representation of the MutliVector.
"""
function vector(mv::MultiVector)
    ca = algebra(mv)
    d = dimension(ca)
    T = eltype(mv)
    V = zeros(T, d)
    V[collect(baseindices(mv))] .= coefficients(mv)
    V
end


"""
    matrix(::MultiVector)

Returns the matrix algebra representation of the MultiVector.
"""
function matrix(mv::MultiVector)
    ca = algebra(mv)
    d = dimension(ca)
    T = eltype(mv)
    M = zeros(T, d, d)
    for (c, b) in zip(coefficients(mv), baseindices(mv))
        for bi = 1:d
            (bo, mc) = baseproduct(ca, b, bi)
            M[bo, bi] += c * mc
        end
    end
    M
end
