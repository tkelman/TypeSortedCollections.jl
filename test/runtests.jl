using Base.Test
using TypeSortedCollections

module M
f(x::Int64) = 3 * x
f(x::Float64) = round(Int64, x / 2)

g(x::Int64, y1::Float64, y2::Int64) = x * y1 * y2
g(x::Float64, y1::Float64, y2::Int64) = x + y1 + y2
g(x::Int64, y1::Float64, y2::Float64) = x * y1 - y2
g(x::Float64, y1::Float64, y2::Float64) = x + y1 - y2
end

@testset "ambiguities" begin
    base_ambiguities = detect_ambiguities(Base, Core)
    tsc_ambiguities = setdiff(detect_ambiguities(TypeSortedCollections, Base, Core), base_ambiguities)
    @test isempty(tsc_ambiguities)
end

@testset "general collection interface" begin
    x = Number[3.; 4; 5]
    sortedx = TypeSortedCollection(x)
    @test length(sortedx) == length(x)
    @test !isempty(sortedx)
    @test @allocated(length(sortedx)) == 0

    empty!(sortedx)
    @test length(sortedx) == 0
    @test isempty(sortedx)
end

@testset "empty input" begin
    x = Number[]
    sortedx = TypeSortedCollection(x)
    @test isempty(sortedx)
end

@testset "map! no args" begin
    x = Number[3.; 4; 5]
    sortedx = TypeSortedCollection(x)
    @test length(sortedx.data) == 2

    results = similar(x, Int64)
    map!(M.f, results, sortedx)
    allocations = @allocated map!(M.f, results, sortedx)
    @test allocations == 0
    for (index, element) in enumerate(x)
        @test results[index] == M.f(element)
    end
end

@testset "map! with args" begin
    x = Number[3.; 4; 5]
    sortedx = TypeSortedCollection(x)
    y1 = rand(length(x))
    y2 = rand(Int, length(x))
    results = similar(x, Float64)
    map!(M.g, results, sortedx, y1, y2)
    for (index, element) in enumerate(x)
        @test results[index] == M.g(element, y1[index], y2[index])
    end
    allocations = @allocated map!(M.g, results, sortedx, y1, y2)
    @test allocations == 0

    y2 = Number[7.; 8; 9]
    sortedy2 = TypeSortedCollection(y2)
    map!(M.g, results, sortedx, y1, sortedy2)
    for (index, element) in enumerate(x)
        @test results[index] == M.g(element, y1[index], y2[index])
    end
    allocations = @allocated map!(M.g, results, sortedx, y1, sortedy2)
    @test allocations == 0
end

@testset "map! indices mismatch" begin
    x = Number[3.; 4; 5]
    sortedx = TypeSortedCollection(x)
    y1 = rand(length(x))
    y2 = Number[8; 9; Float32(7)]
    sortedy2 = TypeSortedCollection(y2)
    results = similar(x, Float64)
    @test_throws ArgumentError map!(M.g, results, sortedx, y1, sortedy2)
end

@testset "map! length mismatch" begin
    x = Number[3.; 4; 5]
    sortedx = TypeSortedCollection(x)
    y1 = rand(length(x) + 1)
    y2 = rand(length(x))
    results = similar(x, Float64)
    @test_throws DimensionMismatch map!(M.g, results, sortedx, y1, y2)
end

@testset "foreach" begin
    x = Number[4.; 5; 3.]
    sortedx = TypeSortedCollection(x)
    @test length(sortedx.data) == 2
    results = []
    foreach(sortedx) do x
        push!(results, x * 4.)
    end
    for (index, element) in enumerate(x)
        @test element * 4. in results
    end

    y1 = rand(length(x))
    y2 = Number[7.; 8; 9.]
    sortedy2 = TypeSortedCollection(y2)
    foreach(M.g, sortedx, y1, sortedy2)
    allocations = @allocated foreach(M.g, sortedx, y1, sortedy2)
    @test allocations == 0
end

@testset "append!" begin
    x = Number[4.; 5; 3.]
    sortedx = TypeSortedCollection(x)
    @test_throws ArgumentError append!(sortedx, [Float32(6)])
    append!(sortedx, x)
    @test length(sortedx) == 2 * length(x)
end

@testset "mapreduce" begin
    x = Number[4.; 5; 3.]
    let sortedx = TypeSortedCollection(x), v0 = 2. # required to achieve zero allocations.
        result = mapreduce(M.f, +, v0, sortedx)
        @test isapprox(result, mapreduce(M.f, +, v0, sortedx); atol = 1e-18)
        @test (@allocated mapreduce(M.f, +, v0, sortedx)) == 0
    end
end

@testset "matching indices" begin
    x = Number[3.; 4; 5]
    sortedx = TypeSortedCollection(x)
    y1 = [7.; 8.; 9.]
    sortedy1 = TypeSortedCollection(y1, indices(sortedx))
    @test length(sortedy1.data) == length(sortedx.data)
    y2 = rand(Int, length(x))
    foreach(M.g, sortedx, sortedy1, y2)
end

@testset "preserve order" begin
    x = Number[3.; 4; 5; 6.]
    sortedx1 = TypeSortedCollection(x)
    sortedx2 = TypeSortedCollection(x, true)
    @test num_types(sortedx1) == 2
    @test num_types(sortedx2) == 3
    results = Number[]
    foreach(x -> push!(results, x), sortedx2)
    @test all(x .== results)
end
