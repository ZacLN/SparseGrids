module RadialSqrtCC
@windows ? (begin
const libwget 	= :w_get_l
const libwgetinv= :w_get_inv_l
const libinterp = :sparse_interp_l
end
:begin
const libwget 	= :_Z7w_get_lPdiiPiS0_S_iS_S_S_
const libwgetinv=:_Z11w_get_inv_lPdiiPiS0_S_iS_S_S_
const libinterp = :_Z15sparse_interp_lPdiS_iiPiS0_S_iS_S_S_
end)

Mi(i::Int) = (i==1) ? 1 : 2^(i-1)+1

function dMi(i::Int64)
	if (i==1)
		return 1
	elseif (i==2)
		return 2
	else
		return 2^(i-2)
	end
end

xi(i::Int,j::Int) = (i==1) ? 0.5 : (j-1)/(Mi(i)-1.0)


function dxi(i::Int64,j::Int64)
	if (i==1)
		return 0.5
	elseif (i==2)
		if (j==1)
			return 0.0;
		else
			return 1.0;
		end
	else
		return ((j)*2.0-1.0)/(Mi(i)-1.0)
	end
end

Xi(i::Int) = (i==1) ? [0.5] : collect(linspace(0,1,Mi(i)))


function dXi(i::Int64)
	dM 	= dMi(i)
	M  	= Mi(i)
	X  	= Array(Float64,dM)
	if (i==1)
		X = 0.5
	elseif (i==2)
		X = [0.0,1.0]
	else
		for ii = 1:dM
			X[ii] = ((ii)*2.0-1.0)/(M-1.0)
		end
	end
	return X
end

function getind(grid::Array{Float64},q::Int)
	dim = size(grid,2)
	nG = size(grid,1)
	ind = fill!(Array(Int64,nG,dim),0)#zeros(nG,dim)
	for i = 1:nG*dim
		ind[i]=q
		for ddi=q+dim:-1:2
			if mod(grid[i],1/(Mi(ddi)-1))==0.0
				ind[i] = ddi
			end
		end
		if grid[i]==0.5
			ind[i] = 1
		end
	end
	return ind
end


function basis_func(x::Float64,xij::Float64,mi::Int32)
	if (mi==1)
		return 1.0
	elseif (abs(x-xij)<(1.0/(mi-1.0)))
		return (1.0-(mi-1.0)*abs(x-xij))
	else
		return 0.0
	end
end

include("combinatorics.jl")
include("conversion.jl")
const libsparse = @windows ? "libsparse" : "libsparse.so"
import Base.-
immutable Index
	x::Vector{Int}
end

type Node
	x::Vector{Float64}
	level::Int
	index::Index
end



type Grid
	d::Int64
	q::Int64
	n::Int64
	grid::Array{Float64,2}
	index::Array{Int64,2}
	level::Vector{Int64}
	lvl_l::Vector{Int32}
	lvl_s::Array{Int32,2}
	bounds::Array{Float64,2}
	active::Vector{Bool}
end


Node(G::Grid)= Node[Node(vec(G.grid[i,:]),G.level[i],Index(vec(G.index[i,:]))) for i = 1:G.n]

Base.length(I::Index) = length(I.x)
Base.maximum(I::Index) = maximum(I.x)
Base.size(x::Node) = length(x.x)
-(I::Index,i::Int) = Index(I.x-i)

function Base.size(I::Index)
	out = 1
	for i = 1:length(I)
		out *= dMi(I.x[i])
	end
	return out
end

function Nodes(I::Index)
	dim = length(I)
	vs = [dXi(I.x[i]) for i = 1:dim]
    sz = map(dMi,I.x)
    out = Array(Node,prod(sz))
    for i in eachindex(out)
    	@inbounds out[i] = Node(zeros(dim),sum(I.x)-dim,I)
    end

    s = 1
    for d=1:dim
        snext = s*sz[d]
        for j = 1:prod(sz)
            out[j].x[d] = vs[d][div(rem(j-1, snext), s)+1]
        end
        s = snext
    end
    return out
end

function grid_size(Q::Index)
	q=maximum(Q)+length(Q)
	cnt = 0
	for q1=length(Q):q
		inds = comb(length(Q),q1)
		bQ = Array(Bool,length(inds))
		for i = 1:length(inds)
			bQ[i]=all(inds[i].x.<=Q.x+1)
		end
		inds = inds[bQ]
		Ninds = length(inds)
		for j = 1:Ninds
			tseq=inds[j]
			cnt = cnt+size(tseq)
		end
	end
	return cnt
end

function nodes(Q::Index)
	D = length(Q)
	q = maximum(Q)+length(Q)
	nG = grid_size(Q)
	GRID = Array(Node,nG)

	next_ind = 0
	for q1 = D:q
		inds = comb(D,q1)
		bQ = Array(Bool,length(inds))
		for i = 1:length(inds)
			bQ[i]=all(inds[i].x.<=Q.x+1)
		end
		inds = inds[bQ]
		Ninds = length(inds)
		for j = 1:Ninds
			tseq = inds[j]
			new_grid_size = size(tseq)
			GRID[next_ind+1:next_ind+new_grid_size] = Nodes(tseq)
			next_ind += new_grid_size
		end
	end
	return GRID[1:next_ind]
end

function nodes(Q::Index,q::Int)
	D = length(Q)
	q = q+length(Q)
	nG = grid_size(Q)
	GRID = Array(Node,0)

	next_ind = 0

	inds = comb(D,q)
	bQ = Array(Bool,length(inds))
	for i = 1:length(inds)
		bQ[i]=all(inds[i].x.<=Q.x+1)
	end
	inds = inds[bQ]
	Ninds = length(inds)
	for j = 1:Ninds
		tseq = inds[j]
		new_grid_size = size(tseq)
		# GRID[next_ind+1:next_ind+new_grid_size] = Nodes(tseq)
		GRID = [GRID;Nodes(tseq)]
		next_ind += new_grid_size
	end

	return GRID[1:next_ind]
end



Grid(D::Int,Q::Int,bounds = [zeros(1,D);ones(1,D)]) =	Grid(ones(Int,D)*Q,bounds)
Grid(D::Int,Q::Vector{Int},bounds = [zeros(1,D);ones(1,D)]) = Grid(Q,bounds)

function Grid(Q::Vector{Int},bounds::Array{Float64,2})
	if all(bounds.==0.0)
		bounds = [zeros(1,d);ones(1,d)]
	end
	x=nodes(Index(Q))
	D = size(x[1])
	N = length(x)
	grid = zeros(length(x),D)
	index = zeros(Int,length(x),D)
	level = zeros(Int,length(x))
	for i = 1:length(x)
		grid[i,:]= x[i].x
		index[i,:]= x[i].index.x
		level[i]= x[i].level
	end
	q = maximum(level)
	return Grid(D,
				q,
				N,
				grid,
				index,
				level,
				[[findfirst(level.==i) for i = 1:q];length(x)+1],
				map(Mi,index),
				bounds,
				ones(Bool,N))

end

Base.values(G::Grid)= nUtoX(G.grid,G.bounds)
Base.values(G::Grid,i::Int)= UtoX(G.grid[:,i],G.bounds[:,i])

function interp(x1::Array{Float64},G::Grid,A::Vector{Float64})
	ϵ = 1.0
	x = nXtoU(x1,G.bounds)
	Gm = eye(G.n)
    for i = 2:G.n
        for j = 1:i-1
            Gm[i,j]=exp(-(ϵ*norm(G.grid[i,:]-G.grid[j,:]))^2)
            Gm[j,i]=Gm[i,j]
        end
    end
	w =  Gm\A
    g = Array(Float64,size(x,1),G.n)
    for i = 1:size(x,1)
        for j = 1:G.n
            g[i,j]=exp(-(ϵ*norm(x[i,:]-G.grid[j,:]))^2)
        end
    end
    return g*w
end


# function getW(G::Grid,A)
# 	Aold = zeros(G.n)
# 	dA = zeros(G.n)
# 	w = zeros(G.n)
# 	ccall((libwget, libsparse),
# 		Void,
# 		(Ptr{Float64},Int32,Int32,Ptr{Float64},Ptr{Float64},Ptr{Float64},Int32,Ptr{Float64},Ptr{Float64},Ptr{Float64}),
# 		pointer(G.grid),G.n,G.d,pointer(G.lvl_s),pointer(G.lvl_l),pointer(A),G.q,pointer(Aold),pointer(dA),pointer(w))
# 	return w
# end

# function getWinv(G::Grid)
# 	drange=collect(1:G.d)
# 	qA= eye(G.n)
# 	qAold = zeros(G.n,G.n)
# 	qw= zeros(G.n,G.n)
# 	qtemp = zeros(G.n)
#
# 	for i = 1:G.lvl_l[1]-1
# 		@simd for j = 1:G.n
# 		    @inbounds qw[i,j] = qA[i,j] - qAold[i,j]
# 		end
#     end
#     for i in 1:G.n
#     	fill!(qtemp,0)
#         for ii in 1:G.lvl_l[1]-1
#             temp2=1.0
#             for d in drange
#                 @inbounds temp2 *= basis_func(G.grid[i,d],G.grid[ii,d],G.lvl_s[ii,d])
#             end
#             @simd for j = 1:G.n
# 	            @inbounds qtemp[j] += temp2*qw[ii,j]
# 	        end
#         end
#
# 	    @simd for j = 1:G.n
# 		    @inbounds qAold[i,j] += qtemp[j]
# 		end
#     end
#
# 	for q in 1:G.q
# 	    for i = G.lvl_l[q]:G.lvl_l[q+1]-1
# 	    	@simd for j = 1:G.n
# 		        @inbounds qw[i,j] = qA[i,j] - qAold[i,j]
# 		    end
# 	    end
# 	    for i in G.lvl_l[q]:G.n
# 	        fill!(qtemp,0)
# 	        for ii in G.lvl_l[q]:G.lvl_l[q+1]-1
# 	            temp2=1.0
# 	            for d in drange
# 	                @inbounds temp2 *= basis_func(G.grid[i,d],G.grid[ii,d],G.lvl_s[ii,d])
# 	            end
# 	            @simd for j = 1:G.n
# 		            @inbounds qtemp[j] += temp2*qw[ii,j]
# 		        end
# 	        end
# 	        @simd for j = 1:G.n
# 			    @inbounds qAold[i,j] += qtemp[j]
# 			end
# 	    end
# 	end
#    return sparse(qw)
# end

# function getWinvC(G::Grid)
# 	Aold = zeros(G.n,G.n)
# 	dA = zeros(G.n,G.n)
# 	w = zeros(G.n,G.n)
# 	A = eye(G.n,G.n)
# 	grid = deepcopy(G.grid)
# 	ccall((libwgetinv, libsparse),
# 		Void,
# 		(Ptr{Float64},Int32,Int32,Ptr{Float64},Ptr{Float64},Ptr{Float64},Int32,Ptr{Float64},Ptr{Float64},Ptr{Float64}),
# 		pointer(grid),G.n,G.d,pointer(G.lvl_s),pointer(G.lvl_l),pointer(A),G.q,pointer(Aold),pointer(dA),pointer(w))
# 	return sparse(w)
# end

# function getQ(xi1::Array{Float64},G::Grid)
#     xi = nXtoU(xi1,G.bounds)
#     xi[xi.>1]=1.0
#     xi[xi.<0]=0.0
#     nx = size(xi,1)
#
#     lvl_l = [1;G.lvl_l]
#
#     Q = spzeros(nx,G.n)
#     drange=collect(1:G.d)
#     for i in 1:nx
#         for q in 0:G.q
#             for ii in lvl_l[q+1]:lvl_l[q+2]-1
#                 temp2=1.0
#                 for d in drange
#                     @inbounds temp2 *= basis_func(xi[i,d],G.grid[ii,d],G.lvl_s[ii,d])
#
#                 end
#                 Q[i,ii]+=temp2
#             end
#         end
#     end
#    return Q
# end

function grow!(G::Grid,ids::Vector{Int},bounds::Vector{Int})
	locs = G.grid[ids,:]
	for i = 1:size(locs,1)
		id = findfirst(prod(G.grid.==locs[i,:],2))
		grow!(G,id,bounds)
	end
end




function grow!(G::Grid,id::Int,bounds::Vector{Int})
	@assert id≤G.n
    G.active[id]=false
    targ = G.grid[id,:]

    newX = nodes(Index(min(ones(Int,G.d)*(G.level[id]+1),bounds)),G.level[id]+1)

    if length(newX)==0
    	return
    end

    n = G.d*2
    for d=1:G.d
        if targ[d]==0.0 || targ[d]==1.0
            n-=1
        end
    end

    dst = Float64[norm(newX[i].x-vec(targ)) for i = 1:length(newX)]
    newX = newX[sortperm(dst)[1:n],:]

    id1 = ones(Bool,size(newX,1))
    for i = 1:size(newX,1)
        for j = 1:G.n
            if newX[i].x==vec(G.grid[j,:])
                id1[i] = false
            end
        end
    end
    if sum(id1)==0
    	return
    end
    newX = newX[id1]


    G.grid = [G.grid;hcat(Array{Float64}[x.x for x in newX]...)']
    G.index = [G.index;hcat(Array{Int}[x.index.x for x in newX]...)']
    G.level = [G.level;Int[x.level for x in newX]]
    G.active = [G.active;ones(Bool,length(newX))]
    sid = sortperm(G.level)
    G.grid = G.grid[sid,:]
    G.index = G.index[sid,:]
    G.level = G.level[sid]
	G.active = G.active[sid]

	G.n = size(G.grid,1)
	G.q = maximum(G.level)
    G.lvl_l=[[findfirst(G.level.==i) for i = 1:maximum(G.level)];G.n+1]
    G.lvl_s = convert(Array{Float64},map(Mi,G.index))

    return nothing
end

function shrink!(G::Grid,id::Vector{Bool})

	G.grid=G.grid[id,:]
	G.active=G.active[id]
	G.index=G.index[id,:]
	G.level=G.level[id]
	G.n = length(G.level)
	G.lvl_l=[[findfirst(G.level.==i) for i = 1:maximum(G.level)];G.n+1]
    G.lvl_s = convert(Array{Int32},map(Mi,G.index))
    G.q = maximum(G.level)
    return nothing
end



end