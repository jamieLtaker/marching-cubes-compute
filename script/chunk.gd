extends StaticBody3D

@export var chunkCoord := Vector3i.ZERO;

var vertices := PackedVector3Array()
var triangles := PackedInt32Array()
var densities := PackedFloat32Array()
var normals := PackedVector3Array()
var trimesh:ConcavePolygonShape3D
@onready var rd := ComputeHelper.rd
@onready var marching_shader := ComputeHelper.get_shader("res://script/shader/marching.glsl")
@onready var density_shader := ComputeHelper.get_shader("res://script/shader/density.glsl")

const CHUNK_WIDTH := 32
const MAX_VERTS := CHUNK_WIDTH * CHUNK_WIDTH * CHUNK_WIDTH * 3

func uniformFromRid(rid:RID, binding:int, uniformType) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.uniform_type = uniformType# RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = binding
	uniform.add_id(rid)
	return uniform

func PrepareArrays() -> void:
	vertices.resize(MAX_VERTS)
	triangles.resize(MAX_VERTS)
	normals.resize(MAX_VERTS)
	
func ComputeDensities() -> void:
	densities.resize((CHUNK_WIDTH + 1) * (CHUNK_WIDTH + 1) * (CHUNK_WIDTH + 1))
	var densitiesBytes = densities.to_byte_array()
	var densitiesBuffer := rd.storage_buffer_create(densitiesBytes.size(), densitiesBytes)
	var densitiesUniform = uniformFromRid(densitiesBuffer, 0, RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER)
	
	var params = PackedInt32Array()
	params.push_back(chunkCoord.x)
	params.push_back(chunkCoord.y)
	params.push_back(chunkCoord.z)
	var paramsBytes = params.to_byte_array()
	var paramsBuffer = rd.storage_buffer_create(paramsBytes.size(), paramsBytes)
	var paramsUniform = uniformFromRid(paramsBuffer, 1, RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER)
	
	var uniform_set := rd.uniform_set_create([densitiesUniform, paramsUniform], density_shader, 0)
	
	var pipeline := rd.compute_pipeline_create(density_shader)
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_dispatch(compute_list, 5, 5, 5)
	rd.compute_list_end()
	
	rd.submit()
	rd.sync()
	
	densitiesBytes = rd.buffer_get_data(densitiesBuffer)
	densities = densitiesBytes.to_float32_array()
	
	rd.free_rid(paramsBuffer)
	rd.free_rid(densitiesBuffer)
	
	

func ComputeMarchingCubes() -> void:
	var verticesBytes = vertices.to_byte_array()
	var verticesBuffer := rd.storage_buffer_create(verticesBytes.size(), verticesBytes)
	var verticesUniform = uniformFromRid(verticesBuffer, 0, RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER)
	
	var trianglesBytes = triangles.to_byte_array()
	var trianglesBuffer := rd.storage_buffer_create(trianglesBytes.size(), trianglesBytes)
	var trianglesUniform = uniformFromRid(trianglesBuffer, 1, RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER)
	
	var densitiesBytes = densities.to_byte_array()
	var densitiesBuffer := rd.storage_buffer_create(densitiesBytes.size(), densitiesBytes)
	var densitiesUniform = uniformFromRid(densitiesBuffer, 3, RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER)
	
	var normalsBytes = normals.to_byte_array()
	var normalsBuffer := rd.storage_buffer_create(normalsBytes.size(), normalsBytes)
	var normalsUniform = uniformFromRid(normalsBuffer, 4, RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER)
	
	# you need to pass these because storing it as a constant array in the shader makes
	# it take a long time to sample
	var triangleTableBytes = ComputeHelper.TriangleTable.to_byte_array()
	var triangleTableBuffer = rd.storage_buffer_create(triangleTableBytes.size(), triangleTableBytes)
	var triangleTableUniform = uniformFromRid(triangleTableBuffer, 5, RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER)
	
	var params = PackedInt32Array()
	params.push_back(0)
	params.push_back(0)
	var paramsBytes = params.to_byte_array()
	var paramsBuffer = rd.storage_buffer_create(paramsBytes.size(), paramsBytes)
	var paramsUniform = uniformFromRid(paramsBuffer, 2, RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER)
	
	var uniform_set := rd.uniform_set_create([verticesUniform, trianglesUniform, paramsUniform, densitiesUniform, normalsUniform, triangleTableUniform], marching_shader, 0)
	
	# setting up pipeline takes negligible amount of time so don't worry about optimizing this
	var pipeline := rd.compute_pipeline_create(marching_shader)
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_dispatch(compute_list, 4, 4, 4)
	rd.compute_list_end()
	
	#begin GPU portion
	# these two should take 1.5msec (if flat shaded)
	rd.submit()
	rd.sync()
	#end gpu portion
	
	# 2ms
	verticesBytes = rd.buffer_get_data(verticesBuffer)
	trianglesBytes = rd.buffer_get_data(trianglesBuffer)
	normalsBytes = rd.buffer_get_data(normalsBuffer)
	paramsBytes = rd.buffer_get_data(paramsBuffer)
		
	params = paramsBytes.to_int32_array()
	var numVertices = params[0]
	var numTriangles = params[1]

	# remove the space we didn't need
	verticesBytes = verticesBytes.slice(0, numVertices * 4 * 4) # 4 floats (4 bytes each)
	trianglesBytes = trianglesBytes.slice(0, numTriangles * 4 * 4)
	normalsBytes = normalsBytes.slice(0, numVertices * 4 * 4)
	
	# This is formatted specifically to make a quick conversion from vector4 array to vector3 array
	# This is because for complicated reasons the shader will only output vector3s with the size
	# of a vector4, so this is my fix for that
	vertices = PackedVector3Array(Array(verticesBytes.to_vector4_array()))
	triangles = trianglesBytes.to_int32_array()
	normals = PackedVector3Array(Array(normalsBytes.to_vector4_array()))
	
	# hopefully I didn't miss any
	rd.free_rid(verticesBuffer)
	rd.free_rid(trianglesBuffer)
	rd.free_rid(normalsBuffer)
	rd.free_rid(paramsBuffer)
	rd.free_rid(densitiesBuffer)
	
func BuildMesh()->void:
	
	if (vertices.size() == 0):
		return
	
	var _mesh:= ArrayMesh.new()
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = triangles
	arrays[Mesh.ARRAY_NORMAL] = normals
	
	#significant overhead
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays) 
	
	$MeshInstance3D.mesh = _mesh
	$CollisionShape3D.shape = trimesh

func buildCollisionMesh() -> void:
	# this only works if its flat shaded, in which case the vertex array will be in the 
	# trimesh format used for the concave polygon.
	trimesh = ConcavePolygonShape3D.new()
	trimesh.set_faces(vertices)

func updateChunk() -> void:
	PrepareArrays()
	ComputeMarchingCubes()
	BuildMesh()

func _ready() -> void:
	
	position = chunkCoord * CHUNK_WIDTH;
	
	var beginTime = Time.get_ticks_usec()
	
	ComputeDensities()
	updateChunk()
	
	var endTime = Time.get_ticks_usec()
	print("Compute chunk time: " + str((endTime - beginTime) / 1000.0) + "ms")
