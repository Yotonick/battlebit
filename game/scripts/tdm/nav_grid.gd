class_name NavGrid
extends Node
## Ground-level walkability grid (1 m cells) over the district for the bots.
## Every cell is probed with a downward ray (floor height) and a body-sized box
## (obstacles). Destruction re-probes the touched cells, so holes blown in walls
## and fences become paths. Pathfinding is AStarGrid2D; the same grid is drawn
## as the minimap.

const CELL := 1.0
const FREE := 0
const BLOCKED := 1
const SOFT := 2        # a hedge, picket fence, bench...: bots push or break through
const VOID := 3        # water, deep crater, raised floor
const SOFT_WEIGHT := 9.0
const WALL_WEIGHT := 1.7
const RESCAN_BUDGET_USEC := 1800
## Labels of objects that are never worth breaking through.
const HARD_LABELS := ["ground", "railway", "pier", "bus_stop", "kiosk", "storage", "shed", "foodmart",
	"pharmacy", "autoshop", "wagon", "lamp_post", "pole", "flag", "hoop", "slide", "carousel", "climber", "bars"]

var n := 0
var origin := Vector2.ZERO
var ground_y := 2.0
var state := PackedByteArray()
var floor_y := PackedFloat32Array()
var astar := AStarGrid2D.new()
var image: Image
var texture: ImageTexture
## Bumped whenever cells change; bots repath when it moves on.
var version := 0

var _queue := {}
var _tex_dirty := false
var _tex_t := 0.0
var _awake := {}            # VoxelObject -> footprint center when it woke up
var _awake_t := 0.0
var _box: BoxShape3D
var _q: PhysicsShapeQueryParameters3D
var _space: PhysicsDirectSpaceState3D
var _temp_blocks := {}      # cell index -> seconds left


func setup(half: float, gy: float) -> void:
	ground_y = gy
	n = int(ceil(half * 2.0 / CELL))
	origin = Vector2(-half, -half)
	state.resize(n * n)
	floor_y.resize(n * n)
	astar.region = Rect2i(0, 0, n, n)
	astar.cell_size = Vector2(CELL, CELL)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	_box = BoxShape3D.new()
	_box.size = Vector3(CELL * 0.62, 1.3, CELL * 0.62)
	_q = PhysicsShapeQueryParameters3D.new()
	_q.shape = _box
	_q.collision_mask = Layers.STATIC | Layers.DYNAMIC
	image = Image.create(n, n, false, Image.FORMAT_RGBA8)
	texture = ImageTexture.create_from_image(image)


## Full scan; call once the level is built and the physics space is populated.
func scan_all() -> void:
	_space = get_viewport().world_3d.direct_space_state
	var t0 := Time.get_ticks_msec()
	for i in n * n:
		_scan(i)
	for i in n * n:
		_apply(i)
	texture.update(image)
	print("[nav] %dx%d cells scanned in %d ms, %d free" % [n, n, Time.get_ticks_msec() - t0, state.count(FREE)])
	VoxelWorld.instance.geometry_changed.connect(_on_changed)


func _on_changed(pos: Vector3, radius: float) -> void:
	queue_area(pos, radius)


func queue_area(pos: Vector3, radius: float) -> void:
	var a := world_to_cell(pos - Vector3(radius, 0, radius))
	var b := world_to_cell(pos + Vector3(radius, 0, radius))
	for z in range(maxi(a.y, 0), mini(b.y, n - 1) + 1):
		for x in range(maxi(a.x, 0), mini(b.x, n - 1) + 1):
			_queue[x + z * n] = true


## A bot got stuck on this cell: avoid it for a while.
func block_temporarily(c: Vector2i, seconds: float) -> void:
	if not _in(c):
		return
	var i := c.x + c.y * n
	_temp_blocks[i] = seconds
	astar.set_point_solid(c, true)
	version += 1


func _process(delta: float) -> void:
	if _space == null:
		return
	_awake_t -= delta
	if _awake_t <= 0.0:
		_awake_t = 0.5
		_track_dynamic()
	if not _temp_blocks.is_empty():
		for i: int in _temp_blocks.keys():
			_temp_blocks[i] -= delta
			if _temp_blocks[i] <= 0.0:
				_temp_blocks.erase(i)
				_queue[i] = true
	if not _queue.is_empty():
		var t0 := Time.get_ticks_usec()
		var done: Array[int] = []
		for i: int in _queue.keys():
			_queue.erase(i)
			_scan(i)
			done.append(i)
			if Time.get_ticks_usec() - t0 > RESCAN_BUDGET_USEC:
				break
		for i in done:
			_apply(i)
			# Neighbour weights depend on this cell.
			var c := Vector2i(i % n, i / n)
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if _in(c + d):
					_apply((c + d).x + (c + d).y * n)
		version += 1
		_tex_dirty = true
	_tex_t -= delta
	if _tex_dirty and _tex_t <= 0.0:
		_tex_t = 0.4
		_tex_dirty = false
		texture.update(image)


## Moving bodies (falling wall pieces, pushed cars) change the map where they
## come to rest; re-probe their area when they fall asleep.
func _track_dynamic() -> void:
	for o in VoxelWorld.instance.objects:
		if o.static_mode or not is_instance_valid(o):
			continue
		var moving := not o.sleeping and o.linear_velocity.length_squared() > 0.04
		if moving and not _awake.has(o):
			_awake[o] = o.world_center()
		elif not moving and _awake.has(o):
			var r := Vector3(o.volume.get_size()).length() * VoxelObject.VS * 0.5 + 0.5
			queue_area(_awake[o], r)
			queue_area(o.world_center(), r)
			_awake.erase(o)
	for o in _awake.keys():
		if not is_instance_valid(o):
			queue_area(_awake[o], 3.0)
			_awake.erase(o)


func _scan(i: int) -> void:
	var c := Vector2i(i % n, i / n)
	var p := cell_center_xz(c)
	var top := Vector3(p.x, ground_y + 1.5, p.y)
	var rq := PhysicsRayQueryParameters3D.create(top, Vector3(p.x, ground_y - 2.0, p.y), Layers.STATIC)
	var hit := _space.intersect_ray(rq)
	if hit.is_empty():
		state[i] = VOID
		floor_y[i] = ground_y
		return
	var fy: float = hit.position.y
	floor_y[i] = fy
	if fy < ground_y - 1.3 or fy > ground_y + 0.55:
		state[i] = VOID
		return
	_q.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, fy + 0.4 + 0.65, p.y))
	var res := _space.intersect_shape(_q, 6)
	if res.is_empty():
		state[i] = FREE
		return
	var soft := true
	for r in res:
		var o := r.collider as VoxelObject
		if o == null or not _soft_object(o, Vector3(p.x, fy, p.y)):
			soft = false
			break
	state[i] = SOFT if soft else BLOCKED


func _soft_object(o: VoxelObject, at: Vector3) -> bool:
	if not o.static_mode:
		# Light props get pushed aside; cars and wagons do not.
		return o.mass < 260.0
	if o.label in HARD_LABELS or o.label.begins_with("block"):
		return false
	# Sample the obstacle: only weak materials (wood, glass, plaster, foliage,
	# plastic) can be broken with a rifle butt.
	var strongest := 0.0
	for h: float in [0.6, 1.0, 1.4]:
		for off: Vector3 in [Vector3.ZERO, Vector3(0.25, 0, 0), Vector3(-0.25, 0, 0), Vector3(0, 0, 0.25), Vector3(0, 0, -0.25)]:
			var v := o.to_voxel(at + off + Vector3(0, h, 0))
			var vox := o.volume.get_voxel(Vector3i(floori(v.x), floori(v.y), floori(v.z)))
			if vox != 0:
				strongest = maxf(strongest, VoxMat.PROPS[VoxMat.material_of(vox)][0])
	return strongest <= 1.0


func _apply(i: int) -> void:
	var c := Vector2i(i % n, i / n)
	var s := state[i]
	var solid := s == BLOCKED or s == VOID or _temp_blocks.has(i)
	astar.set_point_solid(c, solid)
	if not solid:
		var w := 1.0
		if s == SOFT:
			w = SOFT_WEIGHT
		else:
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = c + d
				if _in(q) and state[q.x + q.y * n] == BLOCKED:
					w = WALL_WEIGHT
					break
		astar.set_point_weight_scale(c, w)
	var col := Color(0.34, 0.37, 0.35, 0.92)
	match s:
		BLOCKED: col = Color(0.11, 0.12, 0.13, 0.96)
		SOFT: col = Color(0.24, 0.29, 0.23, 0.94)
		VOID: col = Color(0.14, 0.22, 0.28, 0.92) if floor_y[i] < ground_y - 0.3 else Color(0.2, 0.2, 0.21, 0.94)
	image.set_pixel(c.x, c.y, col)


# ------------------------------------------------------------------ queries

func _in(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < n and c.y < n


func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(floori((p.x - origin.x) / CELL), floori((p.z - origin.y) / CELL))


func cell_center_xz(c: Vector2i) -> Vector2:
	return origin + (Vector2(c) + Vector2(0.5, 0.5)) * CELL


func cell_point(c: Vector2i) -> Vector3:
	var xz := cell_center_xz(c)
	var y := floor_y[c.x + c.y * n] if _in(c) else ground_y
	return Vector3(xz.x, y, xz.y)


func cell_state(c: Vector2i) -> int:
	return state[c.x + c.y * n] if _in(c) else VOID


func walkable(c: Vector2i) -> bool:
	return _in(c) and not astar.is_point_solid(c)


func is_free(c: Vector2i) -> bool:
	return _in(c) and state[c.x + c.y * n] == FREE and not _temp_blocks.has(c.x + c.y * n)


func walkable_at(p: Vector3) -> bool:
	return walkable(world_to_cell(p))


func nearest_walkable(c: Vector2i, max_r := 8) -> Vector2i:
	if is_free(c):
		return c
	for r in range(1, max_r + 1):
		for k in range(-r, r + 1):
			for q: Vector2i in [Vector2i(c.x + k, c.y - r), Vector2i(c.x + k, c.y + r), Vector2i(c.x - r, c.y + k), Vector2i(c.x + r, c.y + k)]:
				if is_free(q):
					return q
	return Vector2i(-1, -1)


## Random free point within `radius` of `center` (falls back to the center).
func random_point_near(center: Vector3, radius: float, rng: RandomNumberGenerator) -> Vector3:
	for k in 12:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * radius
		var c := world_to_cell(center + Vector3(cos(a) * r, 0, sin(a) * r))
		if is_free(c):
			return cell_point(c)
	var q := nearest_walkable(world_to_cell(center), 10)
	return cell_point(q) if q.x >= 0 else center


## Smoothed world-space path (waypoints at floor height). Empty if no route.
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	var a := nearest_walkable(world_to_cell(from), 3)
	var b := nearest_walkable(world_to_cell(to), 8)
	if a.x < 0 or b.x < 0:
		return out
	var ids: Array[Vector2i] = astar.get_id_path(a, b, true)
	if ids.is_empty():
		return out
	# String pulling: skip every waypoint that has a straight free line.
	var i := 0
	while i < ids.size() - 1:
		var j := mini(i + 24, ids.size() - 1)
		while j > i + 1 and not line_free(ids[i], ids[j]):
			j -= 1
		out.append(cell_point(ids[j]))
		i = j
	if out.is_empty():
		out.append(cell_point(b))
	return out


## True when every cell along the segment is plain free ground.
func line_free(a: Vector2i, b: Vector2i) -> bool:
	var d := Vector2(b - a)
	var steps := int(ceil(d.length() / 0.35))
	for s in range(1, steps + 1):
		var p := Vector2(a) + d * (float(s) / steps)
		if not is_free(Vector2i(roundi(p.x), roundi(p.y))):
			return false
	return true
