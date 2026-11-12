class_name Combat
## Gunfire shared by the player and the bots: hitscan bullets that hurt soldiers
## and chip voxels, tracers, gunshot noise for the bots' hearing and near-miss
## suppression for the player.
##
## Soldiers (Player, Bot) are in the "soldiers" group and provide: team,
## display_name, dead, take_hit(amount, source, weapon, headshot, from) -> bool,
## apply_blast(pos, reach, power, source, weapon), head_y() -> float,
## aim_point() -> Vector3.

const HIT_MASK := Layers.SOLID | Layers.PLAYER

static var tracers: Tracers
static var _last_whiz_ms := 0


static func soldiers() -> Array[Node]:
	return VoxelWorld.instance.get_tree().get_nodes_in_group("soldiers")


static func is_enemy(a: Node, b: Node) -> bool:
	return a != null and b != null and a != b and a.team >= 0 and b.team >= 0 and a.team != b.team


## One trigger pull of a hitscan weapon. `origin` is where the bullet ray starts
## (eye), `muzzle` where the tracer starts. Returns {hit, kill, head}.
static func fire_hitscan(shooter: Node3D, origin: Vector3, muzzle: Vector3, dir: Vector3, w: int, spread: float, tracer := true) -> Dictionary:
	var world := VoxelWorld.instance
	var d := Weapons.def(w)
	var result := {"hit": false, "kill": false, "head": false}
	var side := dir.cross(Vector3.UP)
	side = side.normalized() if side.length_squared() > 0.0001 else Vector3.RIGHT
	var up := side.cross(dir).normalized()
	var ex: Array[RID] = [shooter.get_rid()]
	world.sfx.play(d.sound, muzzle, d.volume, randf_range(0.94, 1.06))
	world.fx.muzzle(muzzle, dir)
	noise(muzzle, d.noise, shooter)
	for i in int(d.pellets):
		var sd := dir
		if spread > 0.0:
			sd = (dir + side * randfn(0.0, spread) + up * randfn(0.0, spread)).normalized()
		var to := origin + sd * float(d.range)
		var hit := world.raycast(origin, to, HIT_MASK, ex)
		var end: Vector3 = to if hit.is_empty() else hit.position
		if tracer and i < 2 and tracers:
			tracers.spawn(muzzle, end)
		_near_miss(shooter, origin, end)
		if hit.is_empty():
			continue
		var col: Object = hit.collider
		if col is Node and (col as Node).is_in_group("soldiers"):
			if col.dead:
				continue
			var dist := origin.distance_to(hit.position)
			var head: bool = hit.position.y > col.head_y()
			var dmg := Weapons.damage_at_range(w, dist) * (float(d.head) if head else 1.0)
			var killed: bool = col.take_hit(dmg, shooter, w, head, origin)
			world.fx.dust(hit.position, Color(0.42, 0.03, 0.02), 0.3)
			result.hit = true
			result.kill = result.kill or killed
			result.head = result.head or head
		elif col is VoxelObject:
			var obj: VoxelObject = col
			var vox := obj.voxel_at_hit(hit.position, hit.normal)
			var mat := VoxMat.material_of(vox) if vox > 0 else 0
			var n := world.damage_at(obj, hit.position - hit.normal * 0.03, d.radius, d.power, sd * 10.0 * float(d.power), 0.4, 2)
			if mat == VoxMat.METAL or mat == VoxMat.HARDMETAL:
				world.fx.sparks(hit.position, hit.normal)
				if randf() < 0.3:
					world.sfx.play("metal", hit.position, -14.0, randf_range(1.2, 1.6))
			elif n == 0:
				world.fx.dust(hit.position, VoxMat.color_of(vox) if vox > 0 else Color(0.6, 0.58, 0.55), 0.25)
	return result


## Bots hear gunfire and explosions within `radius`.
static func noise(pos: Vector3, radius: float, source: Node) -> void:
	var tree := VoxelWorld.instance.get_tree()
	for b in tree.get_nodes_in_group("bots"):
		b.hear(pos, radius, source)


## Bullets passing close to an enemy's head suppress (and whiz for the player).
static func _near_miss(shooter: Node, from: Vector3, to: Vector3) -> void:
	var seg := to - from
	var len2 := seg.length_squared()
	if len2 < 1.0:
		return
	for s in soldiers():
		if s.dead or not is_enemy(shooter, s):
			continue
		var head: Vector3 = s.head_point()
		var t := clampf((head - from).dot(seg) / len2, 0.0, 1.0)
		if t >= 0.995:
			continue
		var dist := head.distance_to(from + seg * t)
		if dist > 2.4:
			continue
		s.suppress(1.0 - dist / 2.4, shooter)
		if s is Player:
			var now := Time.get_ticks_msec()
			if now - _last_whiz_ms > 90:
				_last_whiz_ms = now
				VoxelWorld.instance.sfx.play_ui("whiz", -10.0 + (2.4 - dist) * 3.0, randf_range(0.85, 1.2))


## Ballistic launch direction for a thrown grenade (low arc when possible).
static func throw_dir(from: Vector3, to: Vector3, speed: float, high := false) -> Vector3:
	var g := 9.8
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var x := flat.length()
	var y := to.y - from.y
	if x < 0.5:
		return Vector3.UP
	var v2 := speed * speed
	var disc := v2 * v2 - g * (g * x * x + 2.0 * y * v2)
	var ang := 0.7
	if disc >= 0.0:
		var r := sqrt(disc)
		ang = atan((v2 + r) / (g * x)) if high else atan((v2 - r) / (g * x))
	var h := flat / x
	return (h * cos(ang) + Vector3.UP * sin(ang)).normalized()


## Glowing bullet streaks drawn with one MultiMesh.
class Tracers:
	extends MultiMeshInstance3D
	const N := 128
	const SPEED := 330.0
	const LENGTH := 7.0
	var _from: Array[Vector3] = []
	var _dir: Array[Vector3] = []
	var _dist: Array[float] = []
	var _t: Array[float] = []

	func _ready() -> void:
		var box := BoxMesh.new()
		box.size = Vector3(0.022, 0.022, 1.0)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.8, 0.45)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.7, 0.35)
		mat.emission_energy_multiplier = 6.0
		box.material = mat
		multimesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = box
		multimesh.instance_count = N
		multimesh.visible_instance_count = 0
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		custom_aabb = AABB(Vector3(-400, -100, -400), Vector3(800, 300, 800))

	func spawn(from: Vector3, to: Vector3) -> void:
		var d := from.distance_to(to)
		if d < 1.5:
			return
		if _from.size() >= N:
			_from.pop_front()
			_dir.pop_front()
			_dist.pop_front()
			_t.pop_front()
		_from.append(from)
		_dir.append((to - from) / d)
		_dist.append(d)
		_t.append(0.0)

	func _process(delta: float) -> void:
		var i := 0
		while i < _from.size():
			_t[i] += delta
			if _t[i] * SPEED - LENGTH > _dist[i]:
				_from.remove_at(i)
				_dir.remove_at(i)
				_dist.remove_at(i)
				_t.remove_at(i)
			else:
				i += 1
		var n := _from.size()
		multimesh.visible_instance_count = n
		for k in n:
			var head := minf(_t[k] * SPEED, _dist[k])
			var tail := maxf(head - LENGTH, 0.0)
			var len := maxf(head - tail, 0.05)
			var mid := _from[k] + _dir[k] * (head + tail) * 0.5
			var b := Basis.looking_at(_dir[k], Vector3.UP if absf(_dir[k].y) < 0.99 else Vector3.FORWARD)
			multimesh.set_instance_transform(k, Transform3D(b * Basis.from_scale(Vector3(1, 1, len)), mid))
