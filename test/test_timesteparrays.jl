using Mimi
using Base.Test

import Mimi:
    Timestep, TimestepVector, TimestepMatrix, next_timestep, hasvalue, 
    get_timestep_instance

a = collect(reshape(1:16,4,4))

## quick check of isuniform
@test isuniform([]) == -1
@test isuniform([1]) == 1
@test isuniform([1,2,3]) == 1
@test isuniform([1,2,3,5]) == -1

###########################################
# 1. Test TimestepVector - Fixed Timestep #
###########################################
years = (collect(2000:1:2003)...)

#1a.  test get_timestep_instance, constructor, endof, step_size, and length (with both 
# matching years and mismatched years)

i = get_timestep_instance(Int, years, 1, a[:,3])
x = TimestepVector{Timestep{2000, 1}, Int}(a[:,3])
@test typeof(i) == typeof(x)
@test length(x) == 4
@test endof(x) == 4
@test step_size(x) == 1

#1b.  test hasvalue, getindex, and setindex (with both matching years and
# mismatched years)

t = Timestep{2001, 1, 3000}(1)

@test hasvalue(x, t)
@test !hasvalue(x, Timestep{2000, 1, 2012}(10)) 
@test x[t] == 10

t2 = next_timestep(t)

@test x[t2] == 11
#@test indices(x) == (2000:2003,) #may remove this function

x[t2] = 99
@test x[t2] == 99

t3 = Timestep{2000, 1, 2003}(1)
@test x[t3] == 9

x[t3] = 100
@test x[t3] == 100

##############################################
# 2. Test TimestepVector - Variable Timestep #
##############################################

years = ([2000:5:2005; 2015:10:2025]...)
x = TimestepVector{VariableTimestep{years}, Int}(a[:,3])

#2a.  test hasvalue, getindex, years_array, and setindex (with both matching years and
# mismatched years)

@test years_array(x) == years
t = VariableTimestep{([2005:5:2010; 2015:10:3000]...)}()

@test hasvalue(x, t) 
@test !hasvalue(x, Timestep{2000, 1, 2012}(10)) 
@test x[t] == 10

t2 =  next_timestep(t)

@test x[t2] == 11
#@test indices(x) == (2000:2003,) #may remove this function

x[t2] = 99
@test x[t2] == 99

t3 = VariableTimestep{years}()
@test x[t3] == 9

x[t3] = 100
@test x[t3] == 100

###########################################
# 3. Test TimestepMatrix - Fixed Timestep #
###########################################
years = (collect(2000:1:2003)...)

#3a.  test get_timestep_instance and constructor (with both matching years 
# and mismatched years)

i = get_timestep_instance(Int, years, 2, a[:,1:2])
y = TimestepMatrix{Timestep{2000, 1}, Int}(a[:,1:2])
@test typeof(i) == typeof(y)

#3b.  test hasvalue, getindex, and setindex (with both matching years and
# mismatched years)

t = Timestep{2001, 1, 3000}(1)

@test hasvalue(y, t, 1) 
@test !hasvalue(y, Timestep{2000, 1, 3000}(10), 1)
@test y[t,1] == 2
@test y[t,2] == 6

t2 = next_timestep(t)

@test y[t2,1] == 3
@test y[t2,2] == 7
 
y[t2, 1] = 5
@test y[t2, 1] == 5

t3 = Timestep{2000, 1, 2005}(1)

@test y[t3, 1] == 1
@test y[t3, 2] == 5

y[t3, 1] = 10
@test y[t3,1] == 10

#3c.  interval wider than 1
z = TimestepMatrix{Timestep{2000, 2}, Int}(a[:,3:4])
t = Timestep{1980, 2, 3000}(11)

@test z[t,1] == 9
@test z[t,2] == 13

t2 = next_timestep(t)
@test z[t2,1] == 10
@test z[t2,2] == 14

##############################################
# 4. Test TimestepMatrix - Variable Timestep #
##############################################

years = ([2000:5:2005; 2015:10:2025]...)
y = TimestepMatrix{VariableTimestep{years}, Int}(a[:,1:2])

#4a.  test hasvalue, getindex, setindex, and endof (with both matching years and
# mismatched years)

t = VariableTimestep{([2005:5:2010; 2015:10:3000]...)}()

@test hasvalue(y, t, 1) 
@test !hasvalue(y, Timestep{2000, 4, 3000}(10), 1) 
@test y[t,1] == 2
@test y[t,2] == 6

t2 = next_timestep(t)

@test y[t2,1] == 3
@test y[t2,2] == 7
 
y[t2, 1] = 5
@test y[t2, 1] == 5

t3 = VariableTimestep{years}()

@test y[t3, 1] == 1
@test y[t3, 2] == 5

y[t3, 1] = 10
@test y[t3,1] == 10

##################################
# 5. Test TimeStepAarray methods #
##################################

x_years = ([2000:5:2005; 2015:10:2025]...)
y_years = ([2000:5:2005; 2015:10:2025]...)

x = TimestepVector{Int, x_years}(a[:,3]) #vector
y = TimestepMatrix{Int, y_years}(a[:,1:2]) #matrix

x_fill = fill!(x, 2)
y_fill = fill!(y, 2)
@test x.data == fill(2, (4))
@test y.data == fill(2, (4, 2))

@test size(x) == size(a[:,3])
@test size(y) == size(a[:,1:2])
@test size(y,2) == size(a[:,1:2],2)

@test ndims(x) == 1
@test ndims(y) == 2

@test eltype(x) == eltype(a) 
@test eltype(y) == eltype(a) 

@test start_period(x) == x_years[1]
@test start_period(y) == y_years[1]
@test end_period(x) == x_years[end]
@test end_period(y) == y_years[end]
