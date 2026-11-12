class_name GunModels
## Voxel weapon models (1.9 cm voxels), shared by the first-person view and the
## bots' hands. Forward is -Z; the pivot is the grip, `muzzle` is in voxels.

const VS := 0.019

static var _cache := {}


## {mesh, muzzle (local meters)} for a Weapons id.
static func get_model(w: int) -> Dictionary:
	if _cache.has(w):
		return _cache[w]
	var vol: VoxelVolume
	var pivot := Vector3.ZERO
	var muzzle := Vector3.ZERO
	match w:
		Weapons.RIFLE:
			vol = _rifle()
			pivot = Vector3(2, 4, 31)
			muzzle = Vector3(2, 6, 0)
		Weapons.SHOTGUN:
			vol = _shotgun()
			pivot = Vector3(2, 3, 25)
			muzzle = Vector3(2, 5, 0)
		Weapons.SNIPER:
			vol = _sniper()
			pivot = Vector3(2, 4, 38)
			muzzle = Vector3(2, 6, 0)
		Weapons.RPG:
			vol = _launcher()
			pivot = Vector3(4, 4, 26)
			muzzle = Vector3(4, 8, 0)
		_:
			vol = _grenade()
			pivot = Vector3(3, 3, 3)
			muzzle = Vector3(3, 3, 3)
	var m := {"mesh": VoxModel.mesh(vol, VS, pivot), "muzzle": (muzzle - pivot) * VS}
	_cache[w] = m
	return m


static func instance(w: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = get_model(w).mesh
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return mi


static func _rifle() -> VoxelVolume:
	var v := VoxModel.volume(Vector3i(4, 11, 48))
	var dark := VoxMat.id("tank_black")
	var metal := VoxMat.id("metal_dark")
	v.fill_box(Vector3i(1, 5, 0), Vector3i(3, 7, 12), metal)             # barrel
	v.fill_box(Vector3i(1, 7, 3), Vector3i(3, 10, 5), metal)             # front sight
	v.fill_box(Vector3i(0, 4, 10), Vector3i(4, 8, 22), dark)             # handguard
	v.fill_box(Vector3i(0, 4, 22), Vector3i(4, 9, 34), metal)            # receiver
	v.fill_box(Vector3i(1, 9, 24), Vector3i(3, 11, 31), dark)            # optic
	v.fill_box(Vector3i(1, 10, 23), Vector3i(3, 11, 25), VoxMat.id("glass"))
	v.fill_box(Vector3i(1, 0, 24), Vector3i(3, 4, 27), dark)             # magazine
	v.fill_box(Vector3i(1, -1, 25), Vector3i(3, 1, 28), dark)
	v.fill_box(Vector3i(1, 0, 31), Vector3i(3, 4, 33), dark)             # grip
	v.fill_box(Vector3i(1, 4, 34), Vector3i(3, 8, 48), dark)             # stock
	v.fill_box(Vector3i(1, 3, 44), Vector3i(3, 8, 48), metal)
	return v


static func _shotgun() -> VoxelVolume:
	var v := VoxModel.volume(Vector3i(4, 8, 40))
	v.fill_box(Vector3i(1, 4, 0), Vector3i(3, 6, 22), VoxMat.id("metal_dark"))
	v.fill_box(Vector3i(1, 2, 4), Vector3i(3, 4, 16), VoxMat.id("wood_dark"))
	v.fill_box(Vector3i(0, 3, 18), Vector3i(4, 7, 27), VoxMat.id("metal"))
	v.fill_box(Vector3i(1, 0, 24), Vector3i(3, 3, 26), VoxMat.id("tank_black"))
	v.fill_planks(Vector3i(1, 1, 27), Vector3i(3, 6, 40), 2, 1, 2, VoxMat.ids("wood"), 9)
	return v


static func _sniper() -> VoxelVolume:
	var v := VoxModel.volume(Vector3i(5, 13, 60))
	var stock := VoxMat.id("metal_green")
	var metal := VoxMat.id("metal_dark")
	v.fill_box(Vector3i(1, 5, 0), Vector3i(3, 7, 26), metal)             # barrel
	v.fill_box(Vector3i(0, 3, 20), Vector3i(5, 8, 36), stock)            # fore stock
	v.fill_box(Vector3i(1, 6, 30), Vector3i(4, 9, 42), metal)            # action
	v.fill_cylinder(Vector3(2.5, 10.5, 24), 2.2, 18, 2, VoxMat.id("tank_black"))   # scope
	v.fill_box(Vector3i(1, 9, 23), Vector3i(4, 12, 24), VoxMat.id("glass"))
	v.fill_box(Vector3i(2, 8, 28), Vector3i(3, 9, 30), metal)
	v.fill_box(Vector3i(2, 8, 38), Vector3i(3, 9, 40), metal)
	v.fill_box(Vector3i(4, 7, 39), Vector3i(5, 8, 41), metal)            # bolt handle
	v.fill_box(Vector3i(1, 0, 36), Vector3i(4, 5, 39), stock)            # grip
	v.fill_box(Vector3i(1, 2, 39), Vector3i(4, 8, 60), stock)            # butt stock
	v.fill_box(Vector3i(1, 2, 58), Vector3i(4, 8, 60), VoxMat.id("rubber"))
	return v


static func _launcher() -> VoxelVolume:
	var v := VoxModel.volume(Vector3i(8, 13, 46))
	v.fill_cylinder(Vector3(4, 8, 0), 3.6, 46, 2, VoxMat.id("metal_green"))
	v.fill_cylinder(Vector3(4, 8, 0), 2.2, 46, 2, 0)
	v.fill_cylinder(Vector3(4, 8, 0), 3.9, 3, 2, VoxMat.id("metal_dark"))
	v.fill_cylinder(Vector3(4, 8, 43), 3.9, 3, 2, VoxMat.id("metal_dark"))
	v.fill_box(Vector3i(3, 0, 24), Vector3i(5, 5, 28), VoxMat.id("metal_dark"))
	v.fill_box(Vector3i(5, 10, 18), Vector3i(8, 13, 24), VoxMat.id("tank_black"))
	v.fill_cylinder(Vector3(4, 8, 0), 1.6, 2, 2, VoxMat.id("metal_red"))
	return v


static func _grenade() -> VoxelVolume:
	var v := VoxModel.volume(Vector3i(7, 9, 7))
	v.fill_sphere(Vector3(3.5, 3.5, 3.5), 3.3, VoxMat.id("metal_green"))
	v.fill_box(Vector3i(3, 6, 3), Vector3i(4, 9, 4), VoxMat.id("metal"))
	v.fill_box(Vector3i(4, 7, 3), Vector3i(6, 8, 4), VoxMat.id("metal_dark"))
	return v
