#  General TODO:  
#  1. Confirm that we can use the general case for setindex!, getindex,
# 	and has value instead of teh two specific cases for Variable and Fixed.  
#	Is there any reason to specify Start, Step or Year here in order to be
#	positive that they match?

#
#  1. TIMESTEP
#

function gettime(ts::Timestep{Start, Step, Stop}) where {Start, Step, Stop}
	return Start + (ts.t - 1) * Step
end

function gettime(ts::VariableTimestep)
	return ts.current
end

function is_start(ts::AbstractTimestep)
	return ts.t == 1
end

# LFR-TBD:  is_stop function is not used internally, so we may want to deprecate it ... 
# look into where it might be used within models?
function is_stop(ts::Timestep{Start, Step, Stop}) where {Start, Step, Stop}
	return gettime(ts) == Stop
end

function is_stop(ts::VariableTimestep{Years}) where {Years}
	return gettime(ts) == Years[end]
end

function finished(ts::Timestep{Start, Step, Stop}) where {Start, Step, Stop}
	return gettime(ts) > Stop
end

function finished(ts::VariableTimestep{Years}) where {Years}
	return gettime(ts) > Years[end]
end

function next_timestep(ts::Timestep{Start, Step, Stop}) where {Start, Step, Stop}
	if finished(ts)
			error("Cannot get next timestep, this is final timestep.")
	end
	return Timestep{Start, Step, Stop}(ts.t + 1)
end

function next_timestep(ts::VariableTimestep{Years}) where {Years}
	if finished(ts)
		error("Cannot get next timestep, this is final timestep.")
	end
	return VariableTimestep{Years}(ts.t + 1)		
end

# LFR-TBD:  This funcion is not used internally, and the arithmetic is possible wrong.  
# function new_timestep(ts::Timestep{Start, Step, Stop}, new_start::Int) where {Start, Step, Stop}
# 	return Timestep{new_start, Step, Stop}(Int(ts.t + (Start - new_start) / Step))
# end

#
#  2. CLOCK
#

function timestep(c::Clock)
	return c.ts
end

function timeindex(c::Clock)
	return c.ts.t
end

function gettime(c::Clock)
	return gettime(c.ts)
end

function advance(c::Clock)
	c.ts = next_timestep(c.ts)
	nothing
end

function finished(c::Clock)
	return finished(c.ts)
end

#
# 3.  TimestepVector and TimestepMatrix
#

#
# 3a.  General
#

function get_timestep_instance(T, years, num_dims, value)
	if !(num_dims in (1, 2))
		error("TimeStepVector or TimestepMatrix support only 1 or 2 dimensions, not $num_dims")
	end

	timestep_array_type = num_dims == 1 ? TimestepVector : TimestepMatrix
	stepsize = isuniform(collect(years))
	if stepsize == -1
		return timestep_array_type{VariableTimestep{years}, T}(value)
	else
		return timestep_array_type{Timestep{years[1], stepsize}, T}(value)
	end
end

const AnyIndex = Union{Int, Vector{Int}, Tuple, Colon, OrdinalRange}

# TBD: can it be reduced to this?
# const AnyIndex = Union{Int, Range}

#
# 3b. TimestepVector
#

function Base.getindex(v::TimestepVector, ts::T) where {T <: AbstractTimestep}
	return v.data[ts.t]
end

# function Base.getindex(v::TimestepVector{Timestep{Start, Step}, T}, ts::Timestep{Start, Step, Stop}) where {T, Start, Step, Stop} 
# 	return v.data[ts.t]
# end

# function Base.getindex(v::TimestepVector{VariableTimestep{Years}, T}, ts::VariableTimestep{Years}) where {T, Years}
# 	return v.data[ts.t]
# end

function Base.getindex(v::TimestepVector{Timestep{d_start, Step}, T}, ts::Timestep{t_start, Step, Stop}) where {T, d_start, t_start, Step, Stop} 
	t = Int(ts.t + (t_start - d_start) / Step)
	return v.data[t]
end

function Base.getindex(v::TimestepVector{VariableTimestep{d_years}, T}, ts::VariableTimestep{t_years}) where {T, d_years, t_years}
	t = ts.t + findfirst(d_years, t_years[1]) - 1
	return v.data[t]
end

# int indexing version supports old style components 
function Base.getindex(v::TimestepVector, i::AnyIndex)
	return v.data[i]
end

# function Base.getindex(v::TimestepVector{Timestep{Start, Step}, T}, i::AnyIndex) where {T, Start, Step}
# 	return v.data[i]
# end

# function Base.getindex(v::TimestepVector{VariableTimestep{Years}, T}, i::AnyIndex) where {T, Years}
# 	return v.data[i]
# end

function Base.setindex!(v::TimestepVector, val, ts::T) where {T <: AbstractTimestep}
	setindex!(v.data, val, ts.t)
end

# function Base.setindex!(v::TimestepVector{Timestep{Start, Step}, T}, val, ts::Timestep{Start, Step, Stop}) where {T, Start, Step, Stop} 
# 	setindex!(v.data, val, ts.t)
# end

# function Base.setindex!(v::TimestepVector{VariableTimestep{Years}, T}, val, ts::VariableTimestep{Years}) where {T, Years}
# 	setindex!(v.data, val, ts.t)	
# end

function Base.setindex!(v::TimestepVector{Timestep{d_start, Step}, T}, val, ts::Timestep{t_start, Step, Stop}) where {T, d_start, t_start, Step, Stop} 
	t = Int(ts.t + (t_start - d_start) / Step)
	setindex!(v.data, val, t)
end

function Base.setindex!(v::TimestepVector{VariableTimestep{d_years}, T}, val, ts::VariableTimestep{t_years}) where {T, d_years, t_years}
	t = ts.t + findfirst(d_years, t_years[1]) - 1
	setindex!(v.data, val, t)
end

# int indexing version supports old style components 
function Base.setindex!(v::TimestepVector, val, i::AnyIndex)
	setindex!(v.data, val, i)
end

# function Base.setindex!(v::TimestepVector{Timestep{Start, Step}, T}, val, i::AnyIndex) where {T, Start, Step}
# 	setindex!(v.data, val, i)
# end

# function Base.setindex!(v::TimestepVector{VariableTimestep{Years}, T}, val, i::AnyIndex) where {T, Years}
# 	setindex!(v.data, val, i)
# end

# LFR-TBD:  this function assumes fixed step size, need to parameterize properly 
# and then create a version for variable timestep.  It is also not used within
# the code and possibly incorrectly interprets the meaning of the Base.indices function.
# function Base.indices(x::TimestepVector{T, Start, Step}) where {T, Start, Step}
# 	return (Start:Step:(Start + (length(x.data) - 1) * Step), )
# end

function Base.length(v::TimestepVector)
	return length(v.data)
end

Base.endof(v::TimestepVector) = length(v)

#
# 3c. TimestepMatrix
#


function Base.getindex(mat::TimestepMatrix, ts::T, i::AnyIndex) where {T <: AbstractTimestep}
	return mat.data[ts.t, i]
end

# function Base.getindex(mat::TimestepMatrix{Timestep{Start, Step}, T}, ts::Timestep{Start, Step, Stop}, i::AnyIndex) where {T, Start, Step, Stop} 
# 	return mat.data[ts.t, i]
# end

# function Base.getindex(mat::TimestepMatrix{VariableTimestep{Years}, T}, ts::VariableTimestep{Years}, i::AnyIndex) where {T, Years}
# 	return mat.data[ts.t, i]
# end

function Base.getindex(mat::TimestepMatrix{Timestep{d_start, Step}, T}, ts::Timestep{t_start, Step, Stop}, i::AnyIndex) where {T, d_start, t_start, Step, Stop} 
	t = Int(ts.t + (t_start - d_start) / Step)
	return return mat.data[t, i]
end

function Base.getindex(mat::TimestepMatrix{VariableTimestep{d_years}, T}, ts::VariableTimestep{t_years}, i::AnyIndex) where {T, d_years, t_years}
	t = ts.t + findfirst(d_years, t_years[1]) - 1
	return return mat.data[t, i]
end

# int indexing version supports old style components
function Base.getindex(mat::TimestepMatrix, idx1::AnyIndex, idx2::AnyIndex)
	return mat.data[idx1, idx2]
end

# function Base.getindex(mat::TimestepMatrix{Timestep{Start, Step}, T}, idx1::AnyIndex, idx2::AnyIndex) where {T, Start, Step}
# 	return mat.data[idx1, idx2]
# end

# function Base.getindex(mat::TimestepMatrix{VariableTimestep{Years}, T}, idx1::AnyIndex, idx2::AnyIndex) where {T, Years}
# 	return mat.data[idx1, idx2]
# end


function Base.setindex(mat::TimestepMatrix, val, ts::T, idx::AnyIndex) where {T <: AbstractTimestep}
	setindex!(mat.data, val, ts.t, idx)
end

# function Base.setindex(mat::TimestepMatrix{Timestep{Start, Step}, T}, val, ts::Timestep{Start, Step, Stop}, idx::AnyIndex) where {T, Start, Step, Stop} 
# 	setindex!(mat.data, val, ts.t, idx)
# end

# function Base.setindex!(mat::TimestepMatrix{VariableTimestep{Years}, T}, val, ts::VariableTimestep{Years}, idx::AnyIndex) where {T, Years}
# 	setindex!(mat.data, val, ts.t, idx)
# end

function Base.setindex!(mat::TimestepMatrix{Timestep{d_start, Step}, T}, val, ts::Timestep{t_start, Step, Stop}, idx::AnyIndex) where {T, d_start, t_start, Step, Stop} 
	t = Int(ts.t + (t_start - d_start) / Step)
	setindex!(mat.data, val, t, idx)
end

function Base.setindex!(mat::TimestepMatrix{VariableTimestep{d_years}, T}, val, ts::VariableTimestep{t_years}, idx::AnyIndex) where {T, d_years, t_years}
	t = ts.t + findfirst(d_years, t_years[1]) - 1
	setindex!(mat.data, val, t, idx)
end

# int indexing version supports old style components
function Base.setindex!(mat::TimestepMatrix, val, idx1::AnyIndex, idx2::AnyIndex)
	setindex!(mat.data, val, idx1, idx2)
end

# function Base.setindex!(mat::TimestepMatrix{Timestep{Start, Step}, T}, val, idx1::AnyIndex, idx2::AnyIndex) where {T, Start, Step}
# 	setindex!(mat.data, val, idx1, idx2)
# end

# function Base.setindex!(mat::TimestepMatrix{VariableTimestep{Years}, T}, val, idx1::AnyIndex, idx2::AnyIndex) where {T, Years}
# 	setindex!(mat.data, val, idx1, idx2)
# end

#
# 4. TimestepArray methods
#

Base.fill!(obj::TimestepArray, value) = fill!(obj.data, value)

Base.size(obj::TimestepArray) = size(obj.data)

Base.size(obj::TimestepArray, i::Int) = size(obj.data, i)

Base.ndims(obj::TimestepArray{T_ts, T, N}) where {T_ts,T, N} = N

Base.eltype(obj::TimestepArray{T_ts, T, N}) where {T_ts,T, N} = T

start_period(obj::TimestepArray{Timestep{Start,Step}, T, N}) where {Start, Step, T, N} = Start
start_period(obj::TimestepArray{VariableTimestep{Years}, T, N}) where {Years, T, N} = Years[1]

end_period(obj::TimestepArray{Timestep{Start, Step}, T, N}) where {Start, Step,T, N} = (Start + (size(obj, 1) - 1) * Step)
end_period(obj::TimestepArray{VariableTimestep{Years}, T, N}) where {Years,T, N} = Years[end]

# LFR-TBD:  this function only works for a timestep array parameterized by fixed timesteps, 
# do we want to keep this?  As of now it is never used directly.  Recommend: delete
# step_size(obj::TimestepArray{Timestep{Start, Step}, T, N}) where {Start, Step, T, N} = Step

years_array(obj::TimestepArray{Timestep{Start, Step}, T, N}) where {Start, Step, T, N} = collect(Start:Step:(Start + (size(obj, 1) - 1) * Step))
years_array(obj::TimestepArray{VariableTimestep{Years}, T, N}) where {Years, T, N} = collect(Years)

function Base.getindex(arr::TimestepArray, ts::T, indxs::AnyIndex...) where {T <: AbstractTimestep}
	return arr.data[ts.t, idxs...]
end

# function Base.getindex(arr::TimestepArray{Timestep{Start, Step}, T, N}, ts::Timestep{Start, Step, Stop}, indxs::AnyIndex...) where {T, N, Start, Step, Stop}
# 	return arr.data[ts.t, idxs...]
# end

# function Base.getindex(arr::TimestepArray{VariableTimestep{Years}, T, N}, ts::VariableTimestep{Years}, indxs::AnyIndex...) where {T, N, Years}
# 	return arr.data[ts.t, idxs...]
# end

function Base.getindex(arr::TimestepArray{Timestep{d_start, Step}, T, N}, ts::Timestep{t_start, Step, Stop}, indxs::AnyIndex...) where {T, N, d_start, t_start, Step, Stop}
	t = Int(ts.t + (Start - Years[1]) / Step)					
	return arr.data[t, idxs...]
end

function Base.getindex(arr::TimestepArray{VariableTimestep{d_years}, T, N}, ts::VariableTimestep{t_years}, indxs::AnyIndex...) where {T, N, d_years, t_years}
	t = ts.t + findfirst(d_years, t_years[1]) - 1	
	return arr.data[t, idxs...]
end

# Old-style: first index is Int or Range, rather than a Timestep
function Base.getindex(arr::TimestepArray, idx1::AnyIndex, idx2::AnyIndex, idxs::AnyIndex...)
	return arr.data[idx1, idx2, idxs...]
end

# function Base.getindex(arr::TimestepArray{Timestep{Start, Step}, T, N}, idx1::AnyIndex, idx2::AnyIndex, idxs::AnyIndex...) where {T, N, Start, Step}
# 	return arr.data[idx1, idx2, idxs...]
# end

# function Base.getindex(arr::TimestepArray{VariableTimestep{Years}, T, N}, idx1::AnyIndex, idx2::AnyIndex, idxs::AnyIndex...) where {T, N, Years}
# 	return arr.data[idx1, idx2, idxs...]
# end

function Base.setindex!(arr::TimestepArray, val, ts::T, indxs::AnyIndex...) where {T <: AbstractTimestep}
	setindex!(arr.data, val, ts.t, idxs...)
end

# function Base.setindex!(arr::TimestepArray{Timestep{Start, Step}, T, N}, val, ts::Timestep{Start, Step, Stop}, indxs::AnyIndex...) where {T, N, Start, Step, Stop}
# 	setindex!(arr.data, val, ts.t, idxs...)
# end

# function Base.setindex!(arr::TimestepArray{VariableTimestep{Years}, T, N}, val, ts::VariableTimestep{Years}, indxs::AnyIndex...) where {T, N, Years}
# 	setindex!(arr.data, val, ts.t, idxs...)
# end

function Base.setindex!(arr::TimestepArray{Timestep{d_start, Step}, T, N}, val, ts::Timestep{t_start, Step, Stop}, indxs::AnyIndex...) where {T, N, d_start, t_start, Step, Stop}
	t = ts.t + findfirst(d_years, t_years[1]) - 1	
	setindex!(arr.data, val, t, idxs...)
end

function Base.setindex!(arr::TimestepArray{VariableTimestep{d_years}, T, N}, val, ts::VariableTimestep{t_years}, indxs::AnyIndex...) where {T, N, d_years, t_years}
	t = ts.t + findfirst(d_years, t_years[1]) - 1	
	setindex!(arr.data, val, t, idxs...)
end

# Old-style: first index is Int or Range, rather than a Timestep
function Base.setindex!(arr::TimestepArray, val, idx1::AnyIndex, idx2::AnyIndex, idxs::AnyIndex...)
	setindex!(arr.data, val, idx1, idx2, idxs...)
end

# function Base.setindex!(arr::TimestepArray{Timestep{Start, Step}, T, N}, val, idx1::AnyIndex, idx2::AnyIndex, idxs::AnyIndex...) where {T, N, Start, Step}
# 	setindex!(arr.data, val, idx1, idx2, idxs...)
# end

# function Base.setindex!(arr::TimestepArray{VariableTimestep{Years}, T, N}, val, idx1::AnyIndex, idx2::AnyIndex, idxs::AnyIndex...) where {T, N, Years}
# 	setindex!(arr.data, val, idx1, idx2, idxs...)
# end

function hasvalue(arr::TimestepArray, ts::T) where {T <: AbstractTimestep}
	return 1 <= ts.t <= size(arr, 1)	
end

# function hasvalue(arr::TimestepArray{Timestep{Start, Step}, T, N}, ts::Timestep{Start, Step, Stop}) where {T, N, Start, Step, Stop}
# 	return 1 <= ts.t <= size(arr, 1)	
# end

# function hasvalue(arr::TimestepArray{VariableTimestep{Years}, T, N}, ts::VariableTimestep{Years}) where {T, N, Years}
# 	return 1 <= ts.t <= size(arr, 1)	
# end

function hasvalue(arr::TimestepArray{Timestep{d_start, Step}, T, N}, ts::Timestep{t_start, Step, Stop}) where {T, N, d_start, t_start, Step, Stop}
	return d_start <= gettime(ts) <= end_period(arr)
end

function hasvalue(arr::TimestepArray{VariableTimestep{d_years}, T, N}, ts::VariableTimestep{t_years}) where {T, N, t_years, d_years}
	return d_years[1] <= gettime(ts) <= end_period(arr)	
end

# Legacy integer case
function hasvalue(arr::TimestepArray, t::Int) 
	return 1 <= t <= size(arr, 1)
end

# function hasvalue(arr::TimestepArray{Timestep{Start, Step}, T, N}, t::Int) where {T, N, Start, Step}
# 	return 1 <= t <= size(arr, 1)
# end

# function hasvalue(arr::TimestepArray{VariableTimestep{Years}, T, N}, t::Int) where {T, N, Years}
# 	return 1 <= t <= size(arr, 1)
# end

# Array and Timestep have different Start, validating all dimensions
function hasvalue(arr::TimestepArray{Timestep{d_start, Step}, T, N}, 
	ts::Timestep{t_start, Step, Stop}, 
	idxs::Int...) where {T, N, d_start, t_start, Step, Stop}
	return d_start <= gettime(ts) <= end_period(arr) && all([1 <= idx <= size(arr, i) for (i, idx) in enumerate(idxs)])
end

# Array and Timestep different years, validating all dimensions
function hasvalue(arr::TimestepArray{VariableTimestep{d_years}, T, N}, 
	ts::VariableTimestep{t_years}, 
	idxs::Int...) where {T, N, d_years, t_years}

	return d_years[1] <= gettime(ts) <= end_period(arr) && all([1 <= idx <= size(arr, i) for (i, idx) in enumerate(idxs)])
end

# LFR-TBD:  this function assumes fixed step size, need to parameterize properly 
# and then create a version for variable timestep; also this is never used so we 
# may just want to deprecate it
# function Base.indices(arr::TimestepArray{T, N, Start, Step}) where {T, N, Start, Step}
# 	idxs = [1:size(arr, i) for i in 2:ndims(arr)]
# 	stop = end_period(arr)
# 	return (Start:Step:stop, idxs...)
# end