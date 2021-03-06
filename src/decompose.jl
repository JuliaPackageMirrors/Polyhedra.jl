using FixedSizeArrays
# I only import it and do not use "using" so that Datastructures.status does not conflict with MathProgBase.status
import DataStructures
import GeometryTypes.decompose, GeometryTypes.isdecomposable

function fulldecompose{T}(poly::Polyhedron{3,T})
  ine = SimpleHRepresentation(getinequalities(poly))
  ext = SimpleVRepresentation(getgenerators(poly))

  # I need to do division so if T is e.g. Integer, I need to use another type
  RT = typeof(one(T)/2)

  A = ine.A
  #rayinface{T<:Real}(r::Vector{T}, i::Integer) = myeqzero(dot(r, A[i,:])) && !myeqzero(r)
  #vertinface{T<:Real}(r::Vector{T}, i::Integer) = myeqzero(dot(r, A[i,:])) && !myeqzero(r)
  R = ext.R
  V = isempty(ext.V) ? [0 0 0] : ext.V

  # Intersection of rays with the limits of the scene
  (xmin, xmax) = extrema(map((j)->V[j,1], 1:size(V,1)))
  (ymin, ymax) = extrema(map((j)->V[j,2], 1:size(V,1)))
  (zmin, zmax) = extrema(map((j)->V[j,3], 1:size(V,1)))
  width = max(xmax-xmin, ymax-ymin, zmax-zmin)
  if width == zero(T)
    width = 2
  end
  scene = HyperRectangle{3,RT}([(xmin+xmax)/2-width, (ymin+ymax)/2-width, (zmin+zmax)/2-width], 2*width*ones(RT,3))
  function exit_point(start, ray)
    times = max((Vector(minimum(scene))-start) ./ ray, (Vector(maximum(scene))-start) ./ ray)
    times[ray .== 0] = Inf # To avoid -Inf with .../(-0)
    time = minimum(times)
    start + time * ray
  end

  triangles = DataStructures.Stack(Tuple{Tuple{Vector{Float64},Vector{Float64},Vector{Float64}},Int64})
  for i in 1:size(A, 1)
    xray = nothing
    yray = nothing
    zray = A[i,:]
    if myeqzero(zray)
      continue
    end
    newface = true
    for j in 1:i-1
      if myeqzero(cross(zray, A[j,:])) && (i in ine.linset || dot(zray, A[j,:]) > 0) # If A[j,:] is almost 0, it is always true...
        # parallel and equality or inequality and same sense
        # TODO is it possible that A[i,:] is stronger than A[j,:] ?
        newface = false
      end
    end
    if !newface
      continue
    end
    if i > 1 && A[i,:] == A[i-1,:] # Same row, only need to check i-1 since the rows are sorted
      continue
    end

    # Checking rays
    counterclockwise(a, b) = dot(cross(a, b), zray)
    line = nothing
    lineleft = false
    lineright = false
    function checkleftright(r::Vector, lin::Bool)
      cc = counterclockwise(r, line)
      if !myeqzero(cc)
        if cc < 0 || lin
          lineleft = true
        end
        if cc > 0 || lin
          lineright = true
        end
      end
    end
    for j in 1:size(R, 1)
      if myeqzero(dot(R[j,:], zray)) && !myeqzero(R[j,:])
        if line != nothing
          checkleftright(R[j,:], j in ext.Rlinset)
        else
          if j in ext.Rlinset
            line = vec(R[j,:])
            if xray != nothing
              checkleftright(xray, false) # false otherwise line wouldn't be nothing
            end
            if yray != nothing
              checkleftright(yray, false)
            end
          end
          if xray == nothing || counterclockwise(R[j,:], xray) > 0
            xray = vec(R[j,:])
          end
          if yray == nothing || counterclockwise(R[j,:], yray)  < 0
            yray = vec(R[j,:])
          end
        end
      end
    end

    # Checking vertices
    face_vert = IntSet([])
    for j in 1:size(V, 1)
      if myeq(dot(V[j,:], zray), ine.b[i])
        push!(face_vert, j)
      end
    end

    if line != nothing
      if isempty(face_vert)
        center = zeros(typeof(V), size(V, 2))
      else
        center = vec(V[first(face_vert), :])
      end
      hull = DataStructures.Stack(Any)
      push!(hull, exit_point(center, line))
      if lineleft
        push!(hull, exit_point(center, cross(zray, line)))
      end
      push!(hull, exit_point(center, -line))
      if lineright
        push!(hull, exit_point(center, cross(line, zray)))
      end
      hulls = (hull,)
    else
      #if length(face_vert) < 3 # Wrong, they are also the rays
      #  error("Not enough vertices and rays to form a face, it may be because of numerical rounding. Otherwise, please report this bug.")
      #end
      if length(face_vert) < 3 && (xray == nothing || (length(face_vert) < 2 && (yray == xray || length(face_vert) < 1)))
        continue
      end
      face_verts = Vector{Int}(length(face_vert))
      idx = 1
      for v in face_vert
        face_verts[idx] = v
        idx += 1
      end
      if xray == nothing
        sweep_norm = cross(zray, [1,0,0])
        if sum(abs(sweep_norm)) == 0
          sweep_norm = cross(zray, [0,1,0])
        end
      else
        sweep_norm = cross(zray, xray)
      end
      sort!(face_verts, by = j -> dot(V[j,:], sweep_norm))
      function getsemihull(sign_sense)
        hull = DataStructures.Stack(Int)
        prev = sign_sense == 1 ? face_verts[1] : face_verts[length(face_verts)]
        cur = prev
        for j in (sign_sense == 1 ? (2:length(face_verts)) : ((length(face_verts)-1):-1:1))
          while prev != cur && counterclockwise(V[cur,:] - V[prev,:], V[face_verts[j],:] - V[prev,:]) >= 0
            cur = prev
            pop!(hull)
            if !isempty(hull)
              prev = DataStructures.top(hull)
            end
          end
          if yray != nothing && counterclockwise(V[face_verts[j],:] - V[cur,:], yray) >= 0
            break
          else
            push!(hull, cur)
            prev = cur
            cur = face_verts[j]
          end
        end
        push!(hull, cur)
        hull
      end
      xtoy_hull = getsemihull(1)
      if yray == nothing
        ytox_hull = getsemihull(-1)
      else
        ytox_hull = DataStructures.Stack(Any)
        push!(ytox_hull, face_verts[1])
        if DataStructures.top(xtoy_hull) != face_verts[1]
          push!(ytox_hull, DataStructures.top(xtoy_hull))
        end
        push!(ytox_hull, exit_point(V[DataStructures.top(xtoy_hull),:], yray))
        push!(ytox_hull, exit_point(V[face_verts[1],:], xray))
      end
      hulls = (xtoy_hull, ytox_hull)
    end
    for hull in hulls
      if length(hull) >= 3
        a = pop!(hull)
        if isa(a, Int)
          a = V[a,:]
        end
        b = pop!(hull)
        if isa(b, Int)
          b = V[b,:]
        end
        while !isempty(hull)
          c = pop!(hull)
          if isa(c, Int)
            c = V[c,:]
          end
          push!(triangles, ((a,b,c), i))
          b = c
        end
      end
    end

  end
  ntri = length(triangles)
  points  = Vector{FixedSizeArrays.Point{3,RT}}(3*ntri)
  faces   = Vector{GeometryTypes.Face{3,Int,0}}(ntri)
  ns = Vector{GeometryTypes.Normal{3,RT}}(3*ntri)
  for i in 1:ntri
    tri = pop!(triangles)
    normal = vec(A[tri[2],:])
    for j = 1:3
      idx = 3*(i-1)+j
      #ns[idx] = -normal
      ns[idx] = normal
    end
    faces[i] = Array(3*(i-1)+(1:3))
    k = 1
    for k = 1:3
      # reverse order of the 3 vertices so that if I compute the
      # normals with the `normals` function, they are in the good
      # sense.
      # I know I don't use the `normals` function but I don't know
      # what is the OpenGL convention so I don't know if it cares
      # about the order of the vertices.
      points[3*i-k+1] = tri[1][k]
    end
  end
  # If the type of ns is Rational, it also works.
  # The normalized array in in float but then it it recast into Rational
  map!(normalize, ns)
  (points, faces, ns)
end


isdecomposable{T<:Point, S<:Polyhedron}(::Type{T}, ::Type{S}) = true
isdecomposable{T<:Face, S<:Polyhedron}(::Type{T}, ::Type{S}) = true
isdecomposable{T<:Normal, S<:Polyhedron}(::Type{T}, ::Type{S}) = true
function decompose{N, T1, T2}(PT::Type{Point{N, T1}}, poly::Polyhedron{N, T2})
  points = fulldecompose(poly)[1]
  map(PT, points)
end
function decompose{N, T, O, T2}(FT::Type{Face{N, T, O}}, poly::Polyhedron{3, T2})
  faces = fulldecompose(poly)[2]
  decompose(FT, faces)
end
function decompose{NT<:Normal, T}(::Type{NT}, poly::Polyhedron{3,T})
  ns = fulldecompose(poly)[3]
  map(NT, ns)
end
