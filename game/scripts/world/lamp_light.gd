class_name LampLight
extends OmniLight3D
## Light bound to an emissive voxel: goes out when that voxel is destroyed or
## its piece breaks off.

var obj: VoxelObject
var voxel := Vector3i.ZERO
var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	if _t < 0.3:
		return
	_t = 0.0
	if not is_instance_valid(obj) or obj.volume.get_voxel(voxel) == 0:
		queue_free()
