#
#  TIMESTEP
#

# General TODO:  
# 1. We may want to type specialize the functions in the TIMESTEP
# section below for performance reasons.

function gettime(ts::Timestep{Start, Step, Stop}) where {Start, Step, Stop}
	return Start + (ts.t - 1) * Step
end

function gettime(ts::VariableTimestep)
	return ts.current
end

function is_start(ts::AbstractTimestep)
	return ts.t == 1
end

# NOTE:  is_stop function is not used internally, so we may want to deprecate it ... 
# look into where it might be used within models?
function is_stop(ts::Timestep{Start, Step, Stop}) where {Start, Step, Stop}
	return gettime(ts) == Stop
end

function is_stop(ts::VariableTimestep{Years}) where {Years}
	return gettime(ts) == Years[end-1]
end

function finished(ts::Timestep{Start, Step, Stop}) where {Start, Step, Stop}
	return gettime(ts) > Stop
end

function finished(ts::VariableTimestep{Years}) where {Years}
	return gettime(ts) > Years[end-1]
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

# NOTE:  This funcion is not used internally, and the arithmetic is possible wrong.  
# function new_timestep(ts::Timestep{Start, Step, Stop}, new_start::Int) where {Start, Step, Stop}
# 	return Timestep{new_start, Step, Stop}(Int(ts.t + (Start - new_start) / Step))
# end

#
#  CLOCK
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
# TimestepMatrix and TimestepVector
#

function get_timestep_instance(T, years, num_dims, value)
	if !(num_dims in (1, 2))
			error("TimeStepVector or TimestepMatrix support only 1 or 2 dimensions, not $num_dims")
	end

	timestep_type = num_dims == 1 ? TimestepVector : TimestepMatrix
	return timestep_type{T, years}(value)
end

const AnyIndex = Union{Int, Vector{Int}, Tuple, Colon, OrdinalRange}

# TBD: can it be reduced to this?
# const AnyIndex = Union{Int, Range}

#
# TimestepVector
#

# TODO:  this function would be better handled by dispatch as opposed to
# conditional statements; also the first case tests if the full range of years
# is equal, which isn't really necessary ... but checking narrower case is messy
function Base.getindex(x::TimestepVector{T, Years}, ts::Timestep{Start, Step, Stop}) where {T, Start, Step, Stop, Years}
	if tuple(Start:Step:Stop..., Stop + Step) == Years
		t = ts.t
	else
		t = Int(ts.t + (Start - Years[1]) / Step)
	end
	return x.data[t]
end

function Base.getindex(x::TimestepVector{T, Years}, ts::VariableTimestep{Years}) where {T, Years}
	return x.data[ts.t]
end

function Base.getindex(x::TimestepVector{T, d_years}, ts::VariableTimestep{t_years}) where {T, d_years, t_years}
	t = ts.t + find(d_years .== t_years[1])[1] - 1
	return x.data[t]
end

# int indexing version supports old style components
function Base.getindex(x::TimestepVector{T, Years}, i::AnyIndex) where {T, Years}
   	return x.data[i]
end

# TODO:  this function assumes fixed step size, need to parameterize properly 
# and then create a version for variable timestep.  It is also not used within
# the code and possibly incorrectly interprets the meaning of the Base.indices function.
# function Base.indices(x::TimestepVector{T, Start, Step}) where {T, Start, Step}
# 	return (Start:Step:(Start + (length(x.data) - 1) * Step), )
# end

# TODO:  this function would be better handled by dispatch as opposed to
# conditional statements; also the first case tests if the full range of years
# is equal, which isn't really necessary ... but checking narrower case is messy
function Base.setindex!(v::TimestepVector{T, Years}, val, ts::Timestep{Start, Step, Stop}) where {T, Start, Step, Stop, Years}
	if tuple(Start:Step:Stop..., Stop + Step) == Years
		t = ts.t
	else
		t = Int(ts.t + (Start - Years[1]) / Step)
	end
	setindex!(v.data, val, t)
end

function Base.setindex!(v::TimestepVector{T, Years}, val, ts::VariableTimestep{Years}) where {T, Years}
	setindex!(v.data, val, ts.t)
end

function Base.setindex!(v::TimestepVector{T, d_years}, val, ts::VariableTimestep{t_years}) where {T, d_years, t_years}
	t = ts.t + find(d_years .== t_years[1])[1] - 1
	setindex!(v.data, val, t)
end

function Base.setindex!(v::TimestepVector{T, Years}, val, i::AnyIndex) where {T, Years}
	setindex!(v.data, val, i)
end

function Base.length(v::TimestepVector)
	return length(v.data)
end

Base.endof(v::TimestepVector) = length(v)

#
# TimestepMatrix
#

# TODO:  this function would be better handled by dispatch as opposed to
# conditional statements; also the first case tests if the full range of years
# is equal, which isn't really necessary ... but checking narrower case is messy
function Base.getindex(mat::TimestepMatrix{T, Years}, ts::Timestep{Start, Step, Stop}, i::AnyIndex) where {T, Start, Step, Stop, Years}
	if tuple(Start:Step:Stop..., Stop + Step) == Years
		t = ts.t
	else
		t = Int(ts.t + (Start - Years[1]) / Step)	
	end
	return mat.data[t, i]
end

function Base.getindex(mat::TimestepMatrix{T, Years}, ts::VariableTimestep{Years}, i::AnyIndex) where {T, Years}
	return mat.data[ts.t, i]
end

function Base.getindex(mat::TimestepMatrix{T, d_years}, ts::VariableTimestep{t_years}, i::AnyIndex) where {T, d_years, t_years}
	t = ts.t + find(d_years .== t_years[1])[1] - 1
	return mat.data[t, i]
end

# int indexing version supports old style components
function Base.getindex(mat::TimestepMatrix{T, Years}, idx1::AnyIndex, idx2::AnyIndex) where {T, Years}
	return mat.data[idx1, idx2]
end

# TODO:  this function would be better handled by dispatch as opposed to
# conditional statements; also the first case tests if the full range of years
# is equal, which isn't really necessary ... but checking narrower case is messy
function Base.setindex!(mat::TimestepMatrix{T, Years}, val, ts::Timestep{Start, Step, Stop}, idx::AnyIndex) where {T, Start, Step, Stop, Years}
	if tuple(Start:Step:Stop..., Stop + Step) == Years
		t = ts.t
	else
		t = Int(ts.t + (Start - Years[1]) / Step)		
	end
	setindex!(mat.data, val, t, idx)
end

function Base.setindex!(mat::TimestepMatrix{T, Years}, val, ts::VariableTimestep{Years}, idx::AnyIndex) where {T, Years}
	setindex!(mat.data, val, ts.t, idx)	
end

function Base.setindex!(mat::TimestepMatrix{T, d_years}, val, ts::VariableTimestep{t_years}, idx::AnyIndex) where {T, d_years, t_years}
	t = ts.t + find(d_years .== t_years[1])[1] - 1
	setindex!(mat.data, val, t, idx)	
end

function Base.setindex!(mat::TimestepMatrix{T, Years}, val, idx1::AnyIndex, idx2::AnyIndex) where {T, Years}
	setindex!(mat.data, val, idx1, idx2)
end

#
# TimestepArray methods
#

Base.fill!(obj::TimestepArray, value) = fill!(obj.data, value)

Base.size(obj::TimestepArray) = size(obj.data)

Base.size(obj::TimestepArray, i::Int) = size(obj.data, i)

Base.ndims(obj::TimestepArray{T, N, Years}) where {T, N, Years} = N

Base.eltype(obj::TimestepArray{T, N, Years}) where {T, N, Years} = T

start_period(obj::TimestepArray{T, N, Years}) where {T, N, Years} = Years[1]

end_period(obj::TimestepArray{T, N, Years}) where {T, N, Years} = Years[end-1]

# ------------------------------------------------------------------------------
# TODO:  All functions below this point must be reevaluated in light of changes
# to TimestepArray and inclusion of VariableTimestep
# ------------------------------------------------------------------------------

# needs to be rethought for variable timestep length
step_size(obj::TimestepArray{T, N, Years}) where {T, N, Start, Step} = Step

# TimestepArray and Timestep have the same Start and Step
function Base.getindex(arr::TimestepArray{T, N, Start, Step}, ts::AbstractTimestep{Start, Step, Stop}, idxs::AnyIndex...) where {T, N, Start, Step, Stop}
	return arr.data[ts.t, idxs...]
end

# TimestepArray and Timestep have different Start dates
function Base.getindex(arr::TimestepArray{T, N, d_start, Step}, ts::Timestep{t_start, Step, Stop}, idxs::AnyIndex...) where {T, N, d_start, Step, t_start, Stop}
	t = Int(ts.t + (t_start - d_start) / Step)
	return arr.data[t, idxs...]
end

function Base.getindex(arr::TimestepArray{T, N, d_start, Steps}, ts::VariableTimestep{t_start, Steps, Stop}, idxs::AnyIndex...) where {T, N, d_start, Steps, t_start, Stop}
	# TODO:  write this function
	return arr.data[t, idxs...]
end 

# TimestepArray and Timestep have the same Start and Step
function Base.setindex!(arr::TimestepArray{T, N, Start, Step}, val, ts::AbstractTimestep{Start, Step, Stop}, idxs::AnyIndex...) where {T, N, Start, Step, Stop}
	setindex!(arr.data, val, ts.t, idxs...)
end

# TimestepArray and Timestep have different Start dates
function Base.setindex!(arr::TimestepArray{T, N, d_start, Step}, val, ts::Timestep{t_start, Step, Stop}, idxs::AnyIndex...) where {T, N, d_start, Step, t_start, Stop}
	t = Int(ts.t + (t_start - d_start) / Step)
	setindex!(arr.data, val, t, idxs...)
end

function Base.setindex!(arr::TimestepArray{T, N, d_start, Steps}, val, ts::VariableTimestep{t_start, Steps, Stop}, idxs::AnyIndex...) where {T, N, d_start, Steps, t_start, Stop}
	# TODO:  write this function
	setindex!(arr.data, val, t, idxs...)
end

# Old-style: first index is Int or Range, rather than a Timestep
function Base.getindex(arr::TimestepArray{T, N, Start, Step}, idx1::AnyIndex, idx2::AnyIndex, idxs::AnyIndex...) where {T, N, Start, Step}
	return arr.data[idx1, idx2, idxs...]
end

# Old-style: first index is Int or Range, rather than a Timestep
function Base.setindex!(arr::TimestepArray{T, N, Start, Step}, val, idx1::AnyIndex, idx2::AnyIndex, idxs::AnyIndex...) where {T, N, Start, Step}
	setindex!(arr.data, val, idx1, idx2, idxs...)
end

# TODO:  this function assumes fixed step size, need to parameterize properly 
# and then create a version for variable timestep
function Base.indices(arr::TimestepArray{T, N, Start, Step}) where {T, N, Start, Step}
	idxs = [1:size(arr, i) for i in 2:ndims(arr)]
	stop = end_period(arr)
	return (Start:Step:stop, idxs...)
end

# Legacy integer case
function hasvalue(arr::TimestepArray{T, N, Start, Step}, t::Int) where {T, N, Start, Step}
	return 1 <= t <= size(arr, 1)
end

# Array and timestep have the same start period and step
function hasvalue(arr::TimestepArray{T, N, Start, Step}, ts::AbstractTimestep{Start, Step, Stop}) where {T, N, Start, Step, Stop}
	return 1 <= ts.t <= size(arr, 1)
end

# Array and Timestep have different start periods but same step
function hasvalue(arr::TimestepArray{T, N, Start1, Step}, ts::AbstractTimestep{Start2, Step, Stop}) where {T, N, Start1, Start2, Step, Stop}
	return Start1 <= gettime(ts) <= end_period(arr)
end

# Array and Timestep different start periods, validating all dimensions
function hasvalue(arr::TimestepArray{T, N, Start1, Step}, 
				  ts::AbstractTimestep{Start2, Step, Stop}, 
				  idxs::Int...) where {T, N, Start1, Start2, Step, Stop}
	return Start1 <= gettime(ts) <= end_period(arr) && all([1 <= idx <= size(arr, i) for (i, idx) in enumerate(idxs)])
end
