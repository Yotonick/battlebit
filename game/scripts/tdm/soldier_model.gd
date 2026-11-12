class_name SoldierModel
extends Node3D
## Voxel soldier (4.5 cm voxels) for the bots: team-colored uniform, vest and
## helmet with a glowing team stripe, procedural walk / crouch / aim / recoil /
## reload / throw / death animation. Meshes are built once per team and shared.

const VS := 0.045
const HIP := 0.86

static var _meshes := {}    # team -> {part: Mesh}

var team := 0
var pelvis: Node3D
var spine: Node3D
var head: Node3D
var arms: Node3D
var hand: Node3D
var leg_l: Node3D
var leg_r: Node3D
var knee_l: Node3D
var knee_r: Node3D
var arm_l: Node3D
var arm_r: Node3D
var guns: Array[MeshInstance3D] = []
var weapon := 0

var _phase := 0.0
var _crouch := 0.0
var _recoil := 0.0
var _reload := 0.0
var _throw := 0.0
var _dead := 0.0
var _dead_dir := 1.0
var _dead_yaw := 0.0


static func _part(size: Vector3i, pivot: Vector3, fill: Callable) -> ArrayMesh:
	var v := VoxModel.volume(size)
	fill.call(v)
	return VoxModel.mesh(v, VS, pivot)


static func _build(t: int) -> Dictionary:
	var uni := VoxMat.id("uni_blue" if t == 0 else "uni_red")
	var vest := VoxMat.id("vest_tan" if t == 0 else "vest_dark")
	var helmet := VoxMat.id("helmet_blue" if t == 0 else "helmet_red")
	var band := VoxMat.id("band_blue" if t == 0 else "band_red")
	var skin := VoxMat.id("skin" if t == 0 else "skin_dark")
	var boot := VoxMat.id("boot")
	var dark := VoxMat.id("tank_black")
	var m := {}
	# Torso: uniform, plate carrier with pouches, team stripe on the shoulders.
	m.torso = _part(Vector3i(12, 13, 8), Vector3(6, 0, 4), func(v: VoxelVolume):
		v.fill_box(Vector3i(1, 0, 1), Vector3i(11, 12, 7), uni)
		v.fill_box(Vector3i(0, 2, 0), Vector3i(12, 10, 8), vest)
		v.fill_box(Vector3i(2, 3, 0), Vector3i(5, 6, 1), dark)
		v.fill_box(Vector3i(7, 3, 0), Vector3i(10, 6, 1), dark)
		v.fill_box(Vector3i(0, 10, 2), Vector3i(12, 12, 6), uni)
		v.fill_box(Vector3i(0, 9, 3), Vector3i(1, 11, 5), band)
		v.fill_box(Vector3i(11, 9, 3), Vector3i(12, 11, 5), band)
		v.fill_box(Vector3i(2, 4, 7), Vector3i(10, 11, 8), dark))
	m.pelvis = _part(Vector3i(10, 4, 7), Vector3(5, 2, 3.5), func(v: VoxelVolume):
		v.fill_box(Vector3i(0, 0, 0), Vector3i(10, 4, 7), uni)
		v.fill_box(Vector3i(0, 3, 0), Vector3i(10, 4, 7), dark))
	m.head = _part(Vector3i(9, 10, 9), Vector3(4.5, 0, 4.5), func(v: VoxelVolume):
		v.fill_box(Vector3i(2, 0, 2), Vector3i(7, 7, 7), skin)
		v.fill_box(Vector3i(3, 3, 2), Vector3i(4, 4, 3), dark)
		v.fill_box(Vector3i(5, 3, 2), Vector3i(6, 4, 3), dark)
		v.fill_box(Vector3i(1, 5, 1), Vector3i(8, 9, 8), helmet)
		v.fill_box(Vector3i(2, 9, 2), Vector3i(7, 10, 7), helmet)
		v.fill_box(Vector3i(1, 5, 1), Vector3i(8, 6, 2), helmet)
		v.fill_box(Vector3i(1, 7, 7), Vector3i(8, 8, 8), band)
		v.fill_box(Vector3i(2, 7, 0), Vector3i(7, 9, 1), dark))
	m.thigh = _part(Vector3i(5, 9, 5), Vector3(2.5, 9, 2.5), func(v: VoxelVolume):
		v.fill_box(Vector3i(0, 0, 0), Vector3i(5, 9, 5), uni)
		v.fill_box(Vector3i(4, 3, 1), Vector3i(5, 6, 4), dark))
	m.shin = _part(Vector3i(5, 10, 7), Vector3(2.5, 10, 4.5), func(v: VoxelVolume):
		v.fill_box(Vector3i(0, 2, 2), Vector3i(5, 10, 7), uni)
		v.fill_box(Vector3i(0, 6, 1), Vector3i(5, 8, 2), dark)
		v.fill_box(Vector3i(0, 0, 0), Vector3i(5, 3, 7), boot))
	m.upper_arm = _part(Vector3i(4, 7, 4), Vector3(2, 7, 2), func(v: VoxelVolume):
		v.fill_box(Vector3i(0, 0, 0), Vector3i(4, 7, 4), uni))
	m.forearm = _part(Vector3i(4, 8, 4), Vector3(2, 8, 2), func(v: VoxelVolume):
		v.fill_box(Vector3i(0, 2, 0), Vector3i(4, 8, 4), uni)
		v.fill_box(Vector3i(0, 0, 0), Vector3i(4, 2, 4), dark))
	return m


static func meshes(t: int) -> Dictionary:
	if not _meshes.has(t):
		_meshes[t] = _build(t)
	return _meshes[t]


func _mi(parent: Node3D, mesh: Mesh, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	parent.add_child(mi)
	return mi


func _node(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _ready() -> void:
	var m := meshes(team)
	pelvis = _node(self, Vector3(0, HIP, 0))
	_mi(pelvis, m.pelvis)
	leg_l = _node(pelvis, Vector3(-0.11, -0.02, 0))
	leg_r = _node(pelvis, Vector3(0.11, -0.02, 0))
	for leg in [leg_l, leg_r]:
		_mi(leg, m.thigh)
		var knee := _node(leg, Vector3(0, -9 * VS, 0))
		_mi(knee, m.shin)
		if leg == leg_l:
			knee_l = knee
		else:
			knee_r = knee
	spine = _node(pelvis, Vector3(0, 0.08, 0))
	_mi(spine, m.torso)
	head = _node(spine, Vector3(0, 11 * VS, 0))
	_mi(head, m.head)
	# Arms and the gun pitch together around the shoulders.
	arms = _node(spine, Vector3(0, 10 * VS, -0.02))
	arm_r = _node(arms, Vector3(0.2, 0, 0))
	_mi(arm_r, m.upper_arm)
	var fr := _node(arm_r, Vector3(0, -7 * VS, 0))
	_mi(fr, m.forearm)
	arm_r.rotation = Vector3(1.15, 0, -0.2)
	fr.rotation = Vector3(0.5, 0, 0)
	arm_l = _node(arms, Vector3(-0.2, 0, 0))
	_mi(arm_l, m.upper_arm)
	var fl := _node(arm_l, Vector3(0, -7 * VS, 0))
	_mi(fl, m.forearm)
	arm_l.rotation = Vector3(1.4, 0, 0.6)
	fl.rotation = Vector3(0.3, 0, 0)
	hand = _node(arms, Vector3(0.09, -0.16, -0.3))
	for w in Weapons.COUNT:
		var g := GunModels.instance(w)
		g.visible = w == weapon
		hand.add_child(g)
		guns.append(g)


func set_weapon(w: int) -> void:
	weapon = w
	for i in guns.size():
		guns[i].visible = i == w


## Muzzle in world space for tracers and flashes.
func muzzle_position() -> Vector3:
	return hand.global_transform * (GunModels.get_model(weapon).muzzle as Vector3)


func kick() -> void:
	_recoil = 1.0


func throw_anim() -> void:
	_throw = 1.0


func reload_anim(on: bool) -> void:
	_reload = 1.0 if on else 0.0


func die(from_dir: Vector3) -> void:
	_dead = 0.001
	# Fall away from the shot.
	var local := global_basis.inverse() * from_dir
	_dead_dir = 1.0 if local.z >= 0.0 else -1.0
	_dead_yaw = randf_range(-0.4, 0.4)


func revive() -> void:
	_dead = 0.0
	rotation = Vector3.ZERO
	position = Vector3.ZERO
	visible = true


## speed: horizontal m/s, pitch: aim pitch (radians, + up), crouch 0..1.
func animate(delta: float, speed: float, pitch: float, crouch: bool) -> void:
	if _dead > 0.0:
		_dead = minf(_dead + delta * 2.2, 1.0)
		var k := 1.0 - pow(1.0 - _dead, 3.0)
		rotation = Vector3(_dead_dir * k * PI * 0.5, _dead_yaw * k, 0)
		position = Vector3(0, -k * 0.1, 0)
		leg_l.rotation.x = lerpf(leg_l.rotation.x, 0.2, k)
		leg_r.rotation.x = lerpf(leg_r.rotation.x, -0.15, k)
		arms.rotation.x = lerpf(arms.rotation.x, 0.9, k)
		return
	_crouch = move_toward(_crouch, 1.0 if crouch else 0.0, delta * 5.0)
	var amp := clampf(speed / 4.0, 0.0, 1.4)
	_phase += delta * (4.0 + speed * 1.5) * (1.0 if speed > 0.3 else 0.0)
	var s := sin(_phase)
	var swing := 0.55 * amp
	var kneel := _crouch
	leg_l.rotation.x = s * swing * (1.0 - kneel) + kneel * 1.3
	leg_r.rotation.x = -s * swing * (1.0 - kneel) + kneel * 0.2
	knee_l.rotation.x = -maxf(0.0, -s) * 0.9 * amp * (1.0 - kneel) - kneel * 1.35
	knee_r.rotation.x = -maxf(0.0, s) * 0.9 * amp * (1.0 - kneel) - kneel * 1.6
	pelvis.position.y = HIP - kneel * 0.36 + absf(cos(_phase)) * 0.025 * amp
	spine.rotation.x = -0.12 * amp - kneel * 0.12
	_recoil = maxf(_recoil - delta * 8.0, 0.0)
	_throw = maxf(_throw - delta * 2.5, 0.0)
	var throw_k := sin(_throw * PI)
	arms.rotation.x = clampf(pitch, -1.2, 1.2) - spine.rotation.x + _recoil * 0.12 - _reload * 0.6 + throw_k * 1.6
	arms.rotation.z = -_reload * 0.3
	hand.position.z = -0.3 + _recoil * 0.05
	head.rotation.x = clampf(pitch * 0.5, -0.5, 0.5)
