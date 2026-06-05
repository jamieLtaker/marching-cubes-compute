extends Node3D

var chunkTemplate = preload("res://scene/chunk.tscn")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var dist = 3
	for x in range(-dist, dist):
		for y in range(-dist, dist):
			for z in range(-dist, dist):
				var chunk = chunkTemplate.instantiate()
				chunk.chunkCoord = Vector3i(x, y, z)
				
				add_child(chunk)
	pass # Replace with function body.
