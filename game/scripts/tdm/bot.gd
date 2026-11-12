class_name Bot
extends CharacterBody3D
## Team deathmatch bot.
##
## Senses: a 130 degree field of view with line-of-sight rays (seeing through
## glass), spotting that takes time (distance, crouching, muzzle flashes),
## hearing gunfire and explosions, bullets whizzing past, and the team's shared
## spotting. Memory keeps the last known position of every enemy.
## Decisions (every ~0.25 s) pick a state: advance to a zone the team director
## assigns, hold it from cover, fight, take cover (hide, reload, peek, shoot),
## hunt the last known position over a flank, investigate noise, dodge
## grenades, pick up ammo. Weapons are chosen by range; grenades are thrown on a
## ballistic arc at enemies behind cover, rockets go at groups, at enemies
## indoors and at the cover someone hides behind. Bots melee through hedges and
## fences when stuck and mark impassable spots on the shared nav grid.
## Aim turns at a limited rate, has reaction time and an error that settles
## while tracking and grows when moving or under fire.

enum { ADVANCE, HOLD, COMBAT, COVER, HUNT, INVESTIGATE, EVADE, RESUPPLY }
const STATE_NAMES := ["наступление", "удержание", "бой", "укрытие", "охота", "проверка шума", "уклонение", "пополнение"]

const WALK := 3.3
const RUN := 5.9
const CROUCH_SPEED := 1.9
const GRAVITY := 13.0
const STEP_HEIGHT := 0.38
const MAX_HEALTH := 100.0
const VIEW_DIST := 160.0
const FOV_COS := 0.42
const STAND_EYE := 1.6
const CROUCH_EYE := 1.05

var game: TdmMatch
var nav: NavGrid
var team := 0
var display_name := ""
var skill := 0.7
## "assault" (rifle), "breacher" (shotgun rush), "marksman" (sniper)
var role := "assault"
var health := MAX_HEALTH
var dead := false
var arsenal := Weapons.Arsenal.new()
var model: SoldierModel
var state := ADVANCE
var target: Node3D = null
var fired_t := -10.0
var crouching := false
var spawn_protect := 0.0
var cover_pos := Vector3.INF

## soldier -> {pos, t, aw, vis, vel}
var memory := {}
var _rng := RandomNumberGenerator.new()
var _yaw := 0.0
var _pitch := 0.0
var _think_t := 0.0
var _perceive_t := 0.0
var _now := 0.0
var _since_hurt := 10.0
var _damage_recent := 0.0
var _suppression := 0.0
var _reaction := 0.0
var _settle := 3.0
var _aim_err := Vector3.ZERO
var _err_t := 0.0
var _burst_left := 0
var _burst_pause := 0.0
var _primary := Weapons.RIFLE
var _want_weapon := Weapons.RIFLE
var _grenade_cd := 6.0
var _rpg_cd := 4.0
var _rpg_point := Vector3.INF
var _throw_t := -1.0
var _throw_at := Vector3.ZERO
var _throw_high := false
var _cover_cd := 0.0
var _cover_peek := false
var _cover_t := 0.0
var _peek_t := 0.0
var _peeking := false
var _strafe := 1.0
var _strafe_t := 0.0
var _posture_crouch := false
var _hunt_pos := Vector3.INF
var _hunt_flank := Vector3.INF
var _flank_set := false
var _hear_pos := Vector3.INF
var _hear_t := -100.0
var _zone := Vector3.INF
var _hold_t := 0.0
var _scan_t := 0.0
var _scan_dir := Vector3.FORWARD
var _evade_from := Vector3.INF
var _evade_t := 0.0
var _lost_t := 0.0
var _path := PackedVector3Array()
var _path_i := 0
var _path_goal := Vector3.INF
var _path_t := 0.0
var _path_version := -1
var _want_goal := Vector3.INF
var _move_speed := 0.0
var _stuck_t := 0.0
var _stuck_ref := Vector3.ZERO
var _stuck_check := 0.0
var _jump_cd := 0.0
var _melee_cd := 0.0
var _step_acc := 0.0
var _col: CollisionShape3D
var _capsule: CapsuleShape3D
var _bag: Node3D = null
## Seconds spent stuck (test statistics).
var dbg_stuck := 0.0


func _ready() -> void:
	_rng.seed = hash(display_name) + Time.get_ticks_usec()
	add_to_group("soldiers")
	add_to_group("bots")
	collision_layer = Layers.PLAYER
	collision_mask = Layers.STATIC | Layers.DYNAMIC | Layers.PLAYER
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(52.0)
	safe_margin = 0.02
	_capsule = CapsuleShape3D.new()
	_capsule.radius = 0.32
	_capsule.height = 1.8
	_col = CollisionShape3D.new()
	_col.shape = _capsule
	_col.position.y = 0.9
	add_child(_col)
	model = SoldierModel.new()
	model.team = team
	add_child(model)
	_primary = Weapons.SHOTGUN if role == "breacher" else (Weapons.SNIPER if role == "marksman" else Weapons.RIFLE)
	arsenal.current = _primary
	_want_weapon = _primary
	model.set_weapon(_primary)
	_think_t = _rng.randf() * 0.3
	_perceive_t = _rng.randf() * 0.2


# ================================================================== soldier API

func eye_pos() -> Vector3:
	return global_position + Vector3(0, CROUCH_EYE if crouching else STAND_EYE, 0)


func aim_point() -> Vector3:
	return global_position + Vector3(0, 0.75 if crouching else 1.15, 0)


func head_point() -> Vector3:
	return global_position + Vector3(0, 1.05 if crouching else 1.62, 0)


func head_y() -> float:
	return global_position.y + (0.92 if crouching else 1.45)


func state_name() -> String:
	return STATE_NAMES[state]


func take_hit(amount: float, source: Node, weapon: int, headshot: bool, from: Vector3) -> bool:
	if dead or spawn_protect > 0.0:
		return false
	if source != null and source != self and source.get("team") == team:
		return false
	health -= amount
	_damage_recent += amount
	_since_hurt = 0.0
	_suppression = minf(_suppression + 0.5, 1.0)
	if game:
		game.register_damage(self, source, amount)
	if source is Node3D and source != self and not source.dead:
		var m := _mem(source)
		m.aw = maxf(m.aw, 1.0)
		m.pos = (source as Node3D).global_position
		m.t = _now
		# Turn towards the shooter right away.
		if target == null:
			_scan_dir = (from - global_position).normalized()
	if health <= 0.0:
		_die(source, weapon, headshot, from)
		return true
	return false


func apply_blast(pos: Vector3, reach: float, power: float, source: Node = null, weapon := -1) -> void:
	if dead:
		return
	var c := aim_point()
	var d := c.distance_to(pos)
	if d >= reach:
		return
	var k := 1.0 - d / reach
	var dir := ((c - pos).normalized() + Vector3.UP * 0.4).normalized()
	velocity += dir * power * 1.4 * k
	if source != null and source != self and source.get("team") == team:
		return
	var dmg := power * 24.0 * k * k
	# Walls between the blast and the body soak most of it.
	var hit := VoxelWorld.instance.raycast(pos, c, Layers.STATIC)
	if not hit.is_empty() and hit.position.distance_to(c) > 0.4:
		dmg *= 0.35
	take_hit(dmg, source, weapon, false, pos)


func suppress(amount: float, source: Node) -> void:
	if dead:
		return
	_suppression = minf(_suppression + amount * 0.35, 1.0)
	if source is Node3D and not source.dead:
		var m := _mem(source)
		if m.t < _now - 1.0:
			m.pos = (source as Node3D).global_position + Vector3(_rng.randf_range(-3, 3), 0, _rng.randf_range(-3, 3))
			m.t = _now
		if target == null:
			_scan_dir = ((source as Node3D).global_position - global_position).normalized()


func hear(pos: Vector3, radius: float, source: Node) -> void:
	if dead or source == self:
		return
	if source != null and source.get("team") == team:
		return
	var d := global_position.distance_to(pos)
	if d > radius:
		return
	var err := d * 0.12
	_hear_pos = pos + Vector3(_rng.randf_range(-err, err), 0, _rng.randf_range(-err, err))
	_hear_t = _now
	if source is Node3D and not source.dead and d < radius * 0.6:
		var m := _mem(source)
		if m.t < _now - 2.0:
			m.pos = _hear_pos
			m.t = _now - 1.0


func respawn_at(pos: Vector3, yaw: float) -> void:
	dead = false
	health = MAX_HEALTH
	global_position = pos
	velocity = Vector3.ZERO
	_yaw = yaw
	_pitch = 0.0
	rotation.y = yaw
	arsenal.refill_all()
	arsenal.current = _primary
	_want_weapon = _primary
	model.set_weapon(_primary)
	model.revive()
	collision_layer = Layers.PLAYER
	collision_mask = Layers.STATIC | Layers.DYNAMIC | Layers.PLAYER
	memory.clear()
	target = null
	_zone = Vector3.INF
	_path = PackedVector3Array()
	_path_goal = Vector3.INF
	_set_crouch(false)
	cover_pos = Vector3.INF
	_suppression = 0.0
	_damage_recent = 0.0
	_throw_t = -1.0
	_rpg_point = Vector3.INF
	spawn_protect = 2.0
	_set_state(ADVANCE)


func _die(source: Node, weapon: int, headshot: bool, from: Vector3) -> void:
	dead = true
	health = 0.0
	collision_layer = 0
	collision_mask = Layers.STATIC
	velocity = Vector3(0, velocity.y, 0)
	model.die((global_position - from).normalized())
	target = null
	if game:
		game.on_death(self, source, weapon, headshot)


# ================================================================== main loop

func _physics_process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_tick(delta)
	var dt := Time.get_ticks_usec() - t0
	if game:
		game.dbg.bot_usec += dt
		game.dbg.bot_max_usec = maxi(game.dbg.bot_max_usec, dt)


func _tick(delta: float) -> void:
	_now = Time.get_ticks_msec() * 0.001
	if dead:
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
			move_and_slide()
		model.animate(delta, 0.0, 0.0, false)
		return
	if game and game.over:
		velocity = Vector3(0, velocity.y - GRAVITY * delta, 0)
		move_and_slide()
		model.animate(delta, 0.0, _pitch, crouching)
		return
	spawn_protect = maxf(spawn_protect - delta, 0.0)
	arsenal.tick(delta)
	_since_hurt += delta
	_damage_recent = maxf(_damage_recent - delta * 12.0, 0.0)
	_suppression = maxf(_suppression - delta * 0.35, 0.0)
	_grenade_cd -= delta
	_rpg_cd -= delta
	_cover_cd -= delta
	_melee_cd -= delta
	_jump_cd -= delta
	if _since_hurt > 5.0 and health < MAX_HEALTH:
		health = minf(health + 12.0 * delta, MAX_HEALTH)

	_perceive_t -= delta
	if _perceive_t <= 0.0:
		_perceive_t = 0.18
		_perceive(0.18)
	_think_t -= delta
	if _think_t <= 0.0:
		_think_t = _rng.randf_range(0.2, 0.3)
		_think()
	_run_state(delta)
	_weapon_logic(delta)
	_update_aim(delta)
	_move(delta)
	model.animate(delta, Vector2(velocity.x, velocity.z).length(), _pitch, crouching)
	model.reload_anim(arsenal.reloading())


# ================================================================== perception

func _mem(s: Node) -> Dictionary:
	if not memory.has(s):
		memory[s] = {"pos": (s as Node3D).global_position, "t": -100.0, "aw": 0.0, "vis": false, "vel": Vector3.ZERO}
	return memory[s]


## Line of sight that ignores glass panes (up to three of them).
func los(from: Vector3, to: Vector3) -> bool:
	var a := from
	for k in 4:
		var hit := VoxelWorld.instance.raycast(a, to, Layers.SOLID)
		if hit.is_empty():
			return true
		var o := hit.collider as VoxelObject
		if o == null:
			return false
		var vox := o.voxel_at_hit(hit.position, hit.normal)
		if vox == 0 or VoxMat.material_of(vox) != VoxMat.GLASS:
			return false
		a = hit.position + (to - a).normalized() * 0.16
	return false


func _perceive(dt: float) -> void:
	var eye := eye_pos()
	var fwd := Vector2(-sin(_yaw), -cos(_yaw))
	for e: Node3D in game.enemies_of(team):
		var m := _mem(e)
		var chest: Vector3 = e.aim_point()
		var to := chest - eye
		var d := to.length()
		var vis := false
		if d < VIEW_DIST:
			var flat := Vector2(to.x, to.z).normalized()
			var in_fov := d < 5.0 or flat.dot(fwd) > FOV_COS
			if in_fov and (los(eye, chest) or los(eye, e.head_point())):
				vis = true
		if vis:
			var rate := 0.9 + 2.8 * (1.0 - d / VIEW_DIST)
			if _now - float(e.fired_t) < 0.6:
				rate *= 2.2
			if e.crouching and Vector2(e.velocity.x, e.velocity.z).length() < 0.5:
				rate *= 0.55
			if Vector2(to.x, to.z).normalized().dot(fwd) > 0.93:
				rate *= 1.5
			if d < 12.0:
				rate *= 2.0
			rate *= 0.6 + skill * 0.6
			m.aw = minf(float(m.aw) + dt * rate, 2.0)
			if m.aw >= 1.0:
				m.pos = e.global_position
				m.vel = e.velocity
				m.t = _now
				game.spot(e, team)
		else:
			m.aw = maxf(float(m.aw) - dt * 0.35, 0.0)
		m.vis = vis and m.aw >= 1.0
	# Team spotting fills in positions this bot cannot see itself.
	var shared: Dictionary = game.spotted_by(team)
	for e: Node3D in shared:
		if e.dead:
			continue
		var m := _mem(e)
		if not m.vis and float(m.t) < float(shared[e].t):
			m.pos = shared[e].pos
			m.t = shared[e].t
	for e in memory.keys():
		if not is_instance_valid(e) or e.dead or _now - float(memory[e].t) > 25.0 and not memory[e].vis:
			memory.erase(e)


func _visible(e: Node) -> bool:
	return e != null and memory.has(e) and memory[e].vis and not e.dead


func _select_target() -> void:
	var best: Node3D = null
	var best_s := -INF
	for e: Node3D in memory:
		var m: Dictionary = memory[e]
		if not m.vis or e.dead:
			continue
		var d := global_position.distance_to(e.global_position)
		var s := 100.0 / (d + 5.0)
		if e.get("target") == self:
			s *= 1.7
		if e == target:
			s *= 1.4
		if e is Player:
			s *= 1.1
		if s > best_s:
			best_s = s
			best = e
	if best != target and best != null:
		_reaction = lerpf(0.65, 0.22, skill) + _rng.randf() * 0.15
		if target != null and _visible(target):
			_reaction *= 0.5
		_settle = 3.0
	if best != null:
		target = best
		_lost_t = 0.0
	elif target != null:
		_lost_t += 0.25
		if _lost_t > 1.6 or target.dead:
			target = null


func _freshest_memory() -> Dictionary:
	var best := {}
	var best_t := -INF
	for e: Node3D in memory:
		var m: Dictionary = memory[e]
		if e.dead:
			continue
		if float(m.t) > best_t:
			best_t = m.t
			best = {"who": e, "pos": m.pos, "t": m.t}
	return best


func _grenade_danger() -> Vector3:
	for g: Node3D in get_tree().get_nodes_in_group("grenades"):
		if g.fuse > 0.25 and g.global_position.distance_to(global_position) < 6.5:
			return g.global_position
	return Vector3.INF


# ================================================================== decisions

func _set_state(s: int) -> void:
	if s == state:
		return
	state = s
	_path = PackedVector3Array()
	_path_goal = Vector3.INF
	match s:
		HOLD:
			_hold_t = _rng.randf_range(6.0, 14.0)
		COVER:
			_cover_t = 0.0
			_peek_t = _rng.randf_range(1.0, 2.2)
			_peeking = false
		HUNT, INVESTIGATE:
			_hunt_flank = Vector3.INF
			_flank_set = false
		COMBAT:
			_posture_crouch = role == "marksman" or _rng.randf() < 0.35
	if s != COVER and s != HOLD:
		cover_pos = Vector3.INF


func _think() -> void:
	_select_target()
	_choose_weapon()
	var danger := _grenade_danger()
	if danger != Vector3.INF:
		_evade_from = danger
		_evade_t = 1.6
		_set_state(EVADE)
		return
	if state == EVADE and _evade_t > 0.0:
		return
	if target != null:
		var tp := target.global_position
		var hurt := _damage_recent > 30.0 or health < 45.0
		var empty := arsenal.mags[arsenal.current] == 0 and arsenal.reserves[arsenal.current] > 0
		if state != COVER and (hurt or empty or _suppression > 0.75) and _cover_cd <= 0.0 and role != "breacher":
			_cover_cd = 2.0
			if _find_cover(tp):
				_set_state(COVER)
				return
		if state != COVER:
			_set_state(COMBAT)
		return
	if state == COVER and (health < 75.0 or arsenal.reloading()) and _cover_t < 9.0:
		return
	var mem := _freshest_memory()
	if not mem.is_empty() and _now - float(mem.t) < 14.0:
		var mp: Vector3 = mem.pos
		if _try_grenade(mem):
			return
		if _try_rpg_cover(mem):
			return
		if state != HUNT or _hunt_pos.distance_to(mp) > 4.0:
			_hunt_pos = mp
			_set_state(HUNT)
		return
	if _hear_pos != Vector3.INF and _now - _hear_t < 9.0:
		if state != INVESTIGATE or _hunt_pos.distance_to(_hear_pos) > 6.0:
			_hunt_pos = _hear_pos
			_set_state(INVESTIGATE)
		return
	if _low_ammo():
		_bag = game.nearest_bag(global_position, 45.0)
		if _bag != null:
			_set_state(RESUPPLY)
			return
	if state != ADVANCE and state != HOLD:
		_set_state(ADVANCE)


func _low_ammo() -> bool:
	return arsenal.mags[_primary] + arsenal.reserves[_primary] < Weapons.DEFS[_primary].mag * 2


func _choose_weapon() -> void:
	if _throw_t >= 0.0:
		return
	var w := _primary
	if not arsenal.has_ammo(w):
		w = Weapons.RIFLE if arsenal.has_ammo(Weapons.RIFLE) else Weapons.SHOTGUN
	if target != null:
		var d := global_position.distance_to(target.global_position)
		if d < 9.0 and arsenal.has_ammo(Weapons.SHOTGUN) and (role == "breacher" or d < 5.0):
			w = Weapons.SHOTGUN
		elif d > 55.0 and arsenal.has_ammo(Weapons.SNIPER) and role == "marksman":
			w = Weapons.SNIPER
		elif d > 70.0 and arsenal.has_ammo(Weapons.SNIPER) and skill > 0.7:
			w = Weapons.SNIPER
		elif d > 9.0 and d < 25.0 and role != "breacher" and arsenal.has_ammo(Weapons.RIFLE):
			w = Weapons.RIFLE
		if _want_rpg_on(target, d):
			w = Weapons.RPG
	elif _rpg_point != Vector3.INF and arsenal.has_ammo(Weapons.RPG):
		w = Weapons.RPG
	_want_weapon = w
	if arsenal.current != w and arsenal.select(w):
		model.set_weapon(w)
		_burst_left = 0


## Rockets: at groups, at enemies indoors or in vehicles, never point blank.
func _want_rpg_on(e: Node3D, d: float) -> bool:
	if _rpg_cd > 0.0 or not arsenal.has_ammo(Weapons.RPG) or d < 12.0 or d > 95.0:
		return false
	if arsenal.current == Weapons.RPG and arsenal.mags[Weapons.RPG] > 0:
		return true
	if e is Player and (e as Player).vehicle != null:
		return true
	var group := 0
	for o: Node3D in game.enemies_of(team):
		if o != e and o.global_position.distance_to(e.global_position) < 5.0:
			group += 1
	if group >= 1:
		return true
	# Indoors: a ceiling right above the target.
	var up := VoxelWorld.instance.raycast(e.global_position + Vector3(0, 1.9, 0), e.global_position + Vector3(0, 4.5, 0), Layers.STATIC)
	return not up.is_empty() and _rng.randf() < 0.5


func _try_grenade(mem: Dictionary) -> bool:
	if _grenade_cd > 0.0 or _throw_t >= 0.0 or arsenal.mags[Weapons.GRENADE] + arsenal.reserves[Weapons.GRENADE] <= 0:
		return false
	var who: Node3D = mem.who
	if _visible(who) or _now - float(mem.t) > 4.0:
		return false
	var p: Vector3 = mem.pos
	var d := global_position.distance_to(p)
	if d < 9.0 or d > 30.0:
		return false
	var from := eye_pos()
	for high in [false, true]:
		if _arc_clear(from, p, high):
			_throw_at = p
			_throw_high = high
			_throw_t = 0.45
			_grenade_cd = _rng.randf_range(9.0, 15.0)
			arsenal.select(Weapons.GRENADE)
			model.set_weapon(Weapons.GRENADE)
			model.throw_anim()
			return true
	_grenade_cd = 2.0
	return false


func _arc_clear(from: Vector3, to: Vector3, high: bool) -> bool:
	var speed: float = Weapons.DEFS[Weapons.GRENADE].speed
	var dir := Combat.throw_dir(from, to, speed, high)
	var v := dir * speed
	var flat := Vector2(to.x - from.x, to.z - from.z).length()
	var hv := maxf(Vector2(v.x, v.z).length(), 0.1)
	var t_end := flat / hv
	var prev := from
	for k in range(1, 9):
		var t := t_end * k / 8.0
		var p := from + v * t + Vector3.DOWN * 4.9 * t * t
		var hit := VoxelWorld.instance.raycast(prev, p, Layers.SOLID)
		if not hit.is_empty():
			# Fine if it lands close to the target anyway.
			return hit.position.distance_to(to) < 3.5
		prev = p
	return true


## An enemy hides behind something we can blow away.
func _try_rpg_cover(mem: Dictionary) -> bool:
	if _rpg_cd > 0.0 or not arsenal.has_ammo(Weapons.RPG) or _now - float(mem.t) > 6.0:
		return false
	var p: Vector3 = mem.pos + Vector3(0, 1.0, 0)
	var eye := eye_pos()
	var d := eye.distance_to(p)
	if d < 14.0 or d > 80.0:
		return false
	var hit := VoxelWorld.instance.raycast(eye, p, Layers.SOLID)
	if hit.is_empty():
		return false
	var hp: Vector3 = hit.position
	if hp.distance_to(eye) < 10.0 or hp.distance_to(p) > 5.0:
		return false
	_rpg_point = hp
	if state != COMBAT:
		_set_state(COMBAT)
	return true


# ================================================================== cover

func _find_cover(threat: Vector3) -> bool:
	var teye := threat + Vector3(0, 1.5, 0)
	var me := global_position
	var best := Vector3.INF
	var best_s := -INF
	var best_peek := false
	var base := _rng.randf() * TAU
	for ring: float in [2.5, 5.0, 8.0, 12.0]:
		for k in 8:
			var a := base + k * TAU / 8.0
			var c := nav.world_to_cell(me + Vector3(cos(a), 0, sin(a)) * ring)
			if not nav.is_free(c):
				continue
			var q := nav.cell_point(c)
			if los(teye, q + Vector3(0, 0.9, 0)):
				continue
			var peek := los(teye, q + Vector3(0, 1.55, 0))
			var dt := q.distance_to(threat)
			var s := -ring * 0.6 + (4.0 if peek else 0.0)
			if dt < 7.0:
				s -= 8.0
			elif dt > 12.0 and dt < 50.0:
				s += 2.0
			if (q - me).dot(threat - me) > 0.0:
				s -= ring * 0.3
			for ally: Node3D in game.allies_of(team):
				if ally != self and ally.get("cover_pos") is Vector3 and (ally.cover_pos as Vector3).distance_to(q) < 2.5:
					s -= 5.0
			if s > best_s:
				best_s = s
				best = q
				best_peek = peek
	if best == Vector3.INF:
		return false
	cover_pos = best
	_cover_peek = best_peek
	return true


# ================================================================== states

func _run_state(delta: float) -> void:
	_move_speed = 0.0
	_want_goal = Vector3.INF
	var want_crouch := false
	match state:
		ADVANCE:
			if _zone == Vector3.INF:
				_zone = game.request_zone(self)
			_want_goal = _zone
			_move_speed = RUN if _rng.randf() < 0.98 else WALK
			if global_position.distance_to(_zone) < 3.0:
				var front: Vector3 = game.front_point(team, _zone)
				if _find_cover(front):
					_zone = cover_pos
				_set_state(HOLD)
		HOLD:
			_hold_t -= delta
			if cover_pos != Vector3.INF and global_position.distance_to(cover_pos) > 0.8:
				_want_goal = cover_pos
				_move_speed = WALK
			else:
				want_crouch = true
			_scan_t -= delta
			if _scan_t <= 0.0:
				_scan_t = _rng.randf_range(1.2, 2.8)
				var f: Vector3 = (game.front_point(team, global_position) - global_position)
				f.y = 0.0
				_scan_dir = f.normalized().rotated(Vector3.UP, _rng.randf_range(-1.1, 1.1))
			if _hold_t <= 0.0:
				_zone = Vector3.INF
				_set_state(ADVANCE)
		COMBAT:
			_combat_move(delta)
			want_crouch = _posture_crouch and _move_speed < 0.5
		COVER:
			if cover_pos == Vector3.INF:
				_set_state(COMBAT)
			elif global_position.distance_to(cover_pos) > 0.7 and _cover_t < 0.01:
				_want_goal = cover_pos
				_move_speed = RUN
			else:
				_cover_t += delta
				_peek_t -= delta
				if _peek_t <= 0.0:
					_peeking = not _peeking and _cover_peek and not arsenal.reloading()
					_peek_t = _rng.randf_range(1.4, 2.8) if _peeking else _rng.randf_range(1.0, 2.2)
				want_crouch = not _peeking
				if arsenal.mags[arsenal.current] < int(Weapons.DEFS[arsenal.current].mag * 0.6):
					arsenal.start_reload()
				# Cover that does not hide us any more is no cover.
				if target != null and not _peeking and _visible(target) and _cover_t > 1.0 and _cover_cd <= 0.0:
					_cover_cd = 1.5
					if not _find_cover(target.global_position):
						_set_state(COMBAT)
				if _cover_t > 10.0 or (_cover_t > 3.0 and health > 80.0 and not arsenal.reloading()):
					_set_state(COMBAT if target != null else HUNT)
		HUNT, INVESTIGATE:
			if not _flank_set:
				_flank_set = true
				_hunt_flank = _flank_point(_hunt_pos) if state == HUNT else Vector3.INF
			var goal := _hunt_pos
			if _hunt_flank != Vector3.INF:
				if global_position.distance_to(_hunt_flank) > 3.0:
					goal = _hunt_flank
				else:
					_hunt_flank = Vector3.INF
			var d := global_position.distance_to(_hunt_pos)
			if d > (10.0 if state == INVESTIGATE else 2.5):
				_want_goal = goal
				_move_speed = RUN if d > 30.0 else WALK
			else:
				_scan_dir = Vector3(cos(_now), 0, sin(_now))
				if state == INVESTIGATE:
					_hear_pos = Vector3.INF
				else:
					for e in memory.keys():
						if not memory[e].vis and memory[e].pos.distance_to(_hunt_pos) < 6.0:
							memory.erase(e)
				_set_state(ADVANCE)
		EVADE:
			_evade_t -= delta
			var away := global_position - _evade_from
			away.y = 0.0
			_want_goal = global_position + away.normalized() * 6.0
			_move_speed = RUN
			if _evade_t <= 0.0:
				_set_state(COMBAT if target != null else ADVANCE)
		RESUPPLY:
			if _bag == null or not is_instance_valid(_bag):
				_set_state(ADVANCE)
			else:
				_want_goal = _bag.global_position
				_move_speed = RUN
	if crouching != want_crouch:
		_set_crouch(want_crouch)


## Approach point off to the side of `p` so hunting bots come from a flank.
func _flank_point(p: Vector3) -> Vector3:
	var to := p - global_position
	to.y = 0.0
	var d := to.length()
	if d < 18.0:
		return Vector3.INF
	var side := to.normalized().cross(Vector3.UP) * (1.0 if hash(display_name) % 2 == 0 else -1.0)
	var c := nav.world_to_cell(p - to.normalized() * 12.0 + side * minf(d * 0.4, 16.0))
	c = nav.nearest_walkable(c, 6)
	return nav.cell_point(c) if c.x >= 0 else Vector3.INF


func _combat_move(delta: float) -> void:
	var tp := target.global_position if target != null else (_rpg_point if _rpg_point != Vector3.INF else global_position)
	var d := global_position.distance_to(tp)
	var w := arsenal.current
	var max_d := 160.0 if w == Weapons.SNIPER else (14.0 if w == Weapons.SHOTGUN else 55.0)
	if target != null and not _visible(target):
		# Lost sight: close in on where it was.
		_want_goal = tp
		_move_speed = WALK
		return
	if role == "breacher" and d > 7.0 or d > max_d:
		_want_goal = tp
		_move_speed = RUN if role == "breacher" and d > 15.0 else WALK
		return
	if role == "marksman" and w == Weapons.SNIPER:
		return
	if d < 5.0 and w != Weapons.SHOTGUN:
		var away := global_position - tp
		away.y = 0.0
		_want_goal = global_position + away.normalized() * 4.0
		_move_speed = WALK
		return
	_strafe_t -= delta
	if _strafe_t <= 0.0:
		_strafe_t = _rng.randf_range(0.6, 1.7)
		_strafe = -_strafe if _rng.randf() < 0.65 else _strafe
		if _rng.randf() < 0.25:
			_strafe = 0.0
	if _strafe != 0.0:
		var to := tp - global_position
		to.y = 0.0
		var side := to.normalized().cross(Vector3.UP) * _strafe
		if not nav.walkable_at(global_position + side * 1.2):
			_strafe = -_strafe
			side = -side
		_want_goal = global_position + side * 2.0
		_move_speed = WALK * 0.8


# ================================================================== weapons and aim

func _aim_target_point() -> Vector3:
	if _throw_t >= 0.0:
		return _throw_at + Vector3(0, 2.0, 0)
	if target != null and _visible(target):
		var p: Vector3 = target.aim_point()
		if arsenal.current == Weapons.SNIPER and skill > 0.75:
			p = target.head_point() - Vector3(0, 0.08, 0)
		if arsenal.current == Weapons.RPG:
			var d := eye_pos().distance_to(p)
			p = target.global_position + Vector3(0, 0.35, 0) + target.velocity * (d / 55.0)
		return p
	if _rpg_point != Vector3.INF and arsenal.current == Weapons.RPG:
		return _rpg_point
	if target != null and memory.has(target):
		return memory[target].pos + Vector3(0, 1.2, 0)
	if _path_i < _path.size() and _move_speed > 0.0:
		var wp := _path[mini(_path_i + 1, _path.size() - 1)]
		var dir := wp - global_position
		dir.y = 0.0
		if dir.length_squared() > 0.25:
			return eye_pos() + dir.normalized() * 10.0
	return eye_pos() + _scan_dir * 10.0


func _update_aim(delta: float) -> void:
	var eye := eye_pos()
	var p := _aim_target_point()
	_err_t -= delta
	if _err_t <= 0.0:
		_err_t = _rng.randf_range(0.3, 0.7)
		_aim_err = Vector3(_rng.randfn(), _rng.randfn() * 0.6, _rng.randfn()).normalized()
	_settle = maxf(_settle - delta * (1.2 + skill * 1.6), 1.0)
	var to := p - eye
	var d := maxf(to.length(), 0.5)
	if target != null and _visible(target):
		var moving := clampf(Vector2(velocity.x, velocity.z).length() / RUN, 0.0, 1.0)
		var tv: Vector3 = target.velocity
		var ang := (0.010 + 0.03 * (1.0 - skill)) * _settle * (1.0 + 0.9 * moving) * (1.0 + 0.8 * _suppression) * (1.0 + tv.length() * 0.06)
		p += _aim_err * d * tan(ang)
		to = p - eye
	var want_yaw := atan2(-to.x, -to.z)
	var want_pitch := atan2(to.y, Vector2(to.x, to.z).length())
	var rate := lerpf(3.2, 8.0, skill) * (1.6 if absf(angle_difference(_yaw, want_yaw)) > 1.2 else 1.0)
	_yaw = _yaw + clampf(angle_difference(_yaw, want_yaw), -rate * delta, rate * delta)
	_pitch = move_toward(_pitch, want_pitch, rate * 0.7 * delta)
	rotation.y = _yaw


func aim_dir() -> Vector3:
	return Vector3(-sin(_yaw) * cos(_pitch), sin(_pitch), -cos(_yaw) * cos(_pitch))


func _weapon_logic(delta: float) -> void:
	if _throw_t >= 0.0:
		_throw_t -= delta
		if _throw_t < 0.0:
			_throw_grenade()
		return
	if arsenal.busy():
		return
	var w := arsenal.current
	if arsenal.mags[w] == 0:
		if arsenal.start_reload():
			game.callout(self, "reload")
		elif w != _primary and arsenal.has_ammo(_primary):
			arsenal.select(_primary)
			model.set_weapon(_primary)
		return
	var shoot_at := Vector3.INF
	if target != null and _visible(target) and (state != COVER or _peeking):
		shoot_at = target.aim_point()
	elif _rpg_point != Vector3.INF and w == Weapons.RPG:
		shoot_at = _rpg_point
	if shoot_at == Vector3.INF:
		# Top up the magazine between fights.
		if target == null and arsenal.mags[w] < int(Weapons.DEFS[w].mag * 0.5):
			arsenal.start_reload()
		return
	if _reaction > 0.0 and w != Weapons.RPG:
		_reaction -= delta
		return
	var eye := eye_pos()
	var dist := eye.distance_to(shoot_at)
	var want := (_aim_target_point() - eye).normalized()
	var dir := aim_dir()
	if dir.angle_to(want) > 0.05 + 0.5 / maxf(dist, 1.0):
		return
	if _friendly_in_line(eye, shoot_at):
		return
	if not arsenal.ready():
		return
	match w:
		Weapons.RIFLE:
			if _burst_pause > 0.0:
				_burst_pause -= delta
				return
			if _burst_left <= 0:
				_burst_left = _rng.randi_range(6, 10) if dist < 15.0 else (_rng.randi_range(3, 6) if dist < 45.0 else _rng.randi_range(2, 4))
			_fire_hitscan(w, dir)
			_burst_left -= 1
			if _burst_left <= 0:
				_burst_pause = _rng.randf_range(0.18, 0.45) + dist * 0.006
		Weapons.SHOTGUN:
			if dist < 30.0:
				_fire_hitscan(w, dir)
		Weapons.SNIPER:
			if _settle < 1.35:
				_fire_hitscan(w, dir)
		Weapons.RPG:
			if dist > 9.0 and not _blocked_close(eye, dir, 7.0):
				_fire_rocket(dir)
		Weapons.GRENADE:
			arsenal.select(_primary)
			model.set_weapon(_primary)


func _blocked_close(eye: Vector3, dir: Vector3, dist: float) -> bool:
	return not VoxelWorld.instance.raycast(eye, eye + dir * dist, Layers.SOLID).is_empty()


func _friendly_in_line(from: Vector3, to: Vector3) -> bool:
	var seg := to - from
	var len2 := seg.length_squared()
	for a: Node3D in game.allies_of(team):
		if a == self:
			continue
		var p: Vector3 = a.aim_point()
		var t := clampf((p - from).dot(seg) / maxf(len2, 0.01), 0.0, 1.0)
		if t > 0.02 and t < 0.98 and p.distance_to(from + seg * t) < 0.8:
			return true
	return false


func _fire_hitscan(w: int, dir: Vector3) -> void:
	var d: Dictionary = Weapons.DEFS[w]
	var moving := Vector2(velocity.x, velocity.z).length() > 1.0
	var spread: float = float(d.ads_spread) * (1.0 + arsenal.burst * 0.18) * (1.7 if moving else 1.0) * (0.8 if crouching else 1.0)
	if w == Weapons.SHOTGUN:
		spread = d.spread
	arsenal.consume()
	fired_t = _now
	model.kick()
	Combat.fire_hitscan(self, eye_pos(), model.muzzle_position(), dir, w, spread)


func _fire_rocket(dir: Vector3) -> void:
	arsenal.consume()
	fired_t = _now
	model.kick()
	var d: Dictionary = Weapons.DEFS[Weapons.RPG]
	var r := Projectiles.Rocket.new()
	r.shooter_rid = get_rid()
	r.source = self
	r.weapon = Weapons.RPG
	r.blast_radius = d.blast_radius
	r.blast_power = d.blast_power
	VoxelWorld.instance.add_child(r)
	var sd := (dir + Vector3(_rng.randfn(), _rng.randfn(), _rng.randfn()) * float(d.spread) * (1.6 - skill)).normalized()
	r.global_position = model.muzzle_position()
	r.velocity = sd * float(d.speed)
	r.look_at(r.global_position + sd, Vector3.UP)
	VoxelWorld.instance.sfx.play("rocket", r.global_position, 2.0)
	Combat.noise(r.global_position, d.noise, self)
	_rpg_cd = _rng.randf_range(10.0, 18.0)
	game.dbg.rockets += 1
	_rpg_point = Vector3.INF
	game.callout(self, "rpg")


func _throw_grenade() -> void:
	var d: Dictionary = Weapons.DEFS[Weapons.GRENADE]
	if arsenal.mags[Weapons.GRENADE] <= 0:
		arsenal.mags[Weapons.GRENADE] = 1
		arsenal.reserves[Weapons.GRENADE] = maxi(arsenal.reserves[Weapons.GRENADE] - 1, 0)
	arsenal.consume()
	if arsenal.reserves[Weapons.GRENADE] > 0:
		arsenal.reserves[Weapons.GRENADE] -= 1
		arsenal.mags[Weapons.GRENADE] = 1
	var from := eye_pos() + aim_dir() * 0.4
	var dir := Combat.throw_dir(from, _throw_at, d.speed, _throw_high)
	var g := Projectiles.PipeBomb.new()
	g.grenade = true
	g.fuse = d.fuse
	g.source = self
	g.weapon = Weapons.GRENADE
	g.blast_radius = d.blast_radius
	g.blast_power = d.blast_power
	VoxelWorld.instance.add_child(g)
	g.global_position = from
	g.linear_velocity = dir * float(d.speed) * _rng.randf_range(0.94, 1.03)
	g.angular_velocity = Vector3(_rng.randf_range(-8, 8), _rng.randf_range(-8, 8), _rng.randf_range(-8, 8))
	VoxelWorld.instance.sfx.play("pin", from, -6.0)
	VoxelWorld.instance.sfx.play("throw", from, -4.0)
	game.callout(self, "grenade")
	game.dbg.grenades += 1
	arsenal.equip_t = 0.0
	arsenal.current = _primary
	model.set_weapon(_primary)
	_throw_t = -1.0


# ================================================================== movement

func _set_crouch(on: bool) -> void:
	if not on and crouching:
		var q := PhysicsShapeQueryParameters3D.new()
		var s := CapsuleShape3D.new()
		s.radius = 0.3
		s.height = 1.8
		q.shape = s
		q.transform = Transform3D(Basis.IDENTITY, global_position + Vector3(0, 0.95, 0))
		q.collision_mask = Layers.STATIC
		q.exclude = [get_rid()]
		if not get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty():
			return
	crouching = on
	_capsule.height = 1.2 if on else 1.8
	_col.position.y = _capsule.height * 0.5


func _update_path() -> void:
	if _want_goal == Vector3.INF:
		_path = PackedVector3Array()
		_path_goal = Vector3.INF
		return
	_path_t -= get_physics_process_delta_time()
	var need := _path_goal == Vector3.INF or _path_goal.distance_to(_want_goal) > 2.0 or _path_t <= 0.0 \
		or (_path_version != nav.version and _path_t < 2.0) or _path_i >= _path.size()
	if not need:
		return
	# Short straight hops (strafing, backing off) need no search.
	if global_position.distance_to(_want_goal) < 4.5 and nav.line_free(nav.world_to_cell(global_position), nav.world_to_cell(_want_goal)):
		_path = PackedVector3Array([_want_goal])
		_path_i = 0
		_path_goal = _want_goal
		_path_t = 0.6
		return
	if not game.take_path_budget():
		return
	_path = nav.find_path(global_position, _want_goal)
	_path_i = 0
	_path_goal = _want_goal
	_path_t = 3.0
	_path_version = nav.version


func _move(delta: float) -> void:
	_update_path()
	var wish := Vector3.ZERO
	if _move_speed > 0.0 and _path_i < _path.size():
		var wp := _path[_path_i]
		var to := wp - global_position
		to.y = 0.0
		if to.length() < 0.55:
			_path_i += 1
			if _path_i < _path.size():
				wp = _path[_path_i]
				to = wp - global_position
				to.y = 0.0
		if to.length() > 0.05:
			var speed := CROUCH_SPEED if crouching else _move_speed
			wish = to.normalized() * speed
	# Keep apart from team mates.
	for a: Node3D in game.allies_of(team):
		if a == self:
			continue
		var off := global_position - a.global_position
		off.y = 0.0
		var dd := off.length()
		if dd < 1.3 and dd > 0.01:
			wish += off / dd * (1.3 - dd) * 3.0
	if is_on_floor():
		var k := 1.0 - exp(-10.0 * delta)
		velocity.x = lerpf(velocity.x, wish.x, k)
		velocity.z = lerpf(velocity.z, wish.z, k)
	else:
		var k := 1.0 - exp(-2.0 * delta)
		velocity.x = lerpf(velocity.x, wish.x, k)
		velocity.z = lerpf(velocity.z, wish.z, k)
		velocity.y -= GRAVITY * delta
	_try_step_up(delta)
	move_and_slide()
	_push_bodies()
	_footsteps(delta)
	_check_stuck(delta, wish)
	var b := DistrictLevel.HALF - 0.6
	global_position.x = clampf(global_position.x, -b, b)
	global_position.z = clampf(global_position.z, -b, b)
	if global_position.y < -20.0:
		take_hit(1000.0, null, -1, false, global_position)


func _try_step_up(delta: float) -> void:
	if not is_on_floor() and velocity.y > 0.5:
		return
	var horiz := Vector3(velocity.x, 0, velocity.z)
	if horiz.length_squared() < 0.04:
		return
	var motion := horiz * delta + horiz.normalized() * 0.05
	var xf := global_transform
	if not test_move(xf, motion):
		return
	var up := Vector3.UP * STEP_HEIGHT
	if test_move(xf, up):
		return
	var raised := xf.translated(up)
	if test_move(raised, motion):
		return
	var col := KinematicCollision3D.new()
	if test_move(raised.translated(motion), -up, col):
		var rise := STEP_HEIGHT - col.get_travel().length()
		if rise > 0.02:
			global_position.y += rise + 0.01
			velocity.y = maxf(velocity.y, 0.0)


func _push_bodies() -> void:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var body := c.get_collider() as RigidBody3D
		if body == null or body.freeze:
			continue
		var push := -c.get_normal()
		push.y = maxf(push.y, 0.0)
		body.apply_impulse(push * clampf(velocity.length() * 9.0, 0.0, 50.0) * minf(body.mass, 80.0) / 80.0, c.get_position() - body.global_position)


func _check_stuck(delta: float, wish: Vector3) -> void:
	_stuck_check -= delta
	if _stuck_check <= 0.0:
		_stuck_check = 0.5
		var moved := Vector2(global_position.x - _stuck_ref.x, global_position.z - _stuck_ref.z).length()
		_stuck_ref = global_position
		if wish.length() > 1.0 and moved < 0.35:
			_stuck_t += 0.5
		else:
			_stuck_t = maxf(_stuck_t - 0.5, 0.0)
	if _stuck_t < 0.5:
		return
	dbg_stuck += delta
	var fwd := Vector3(wish.x, 0, wish.z).normalized()
	if _stuck_t >= 0.5 and _jump_cd <= 0.0 and is_on_floor():
		_jump_cd = 1.6
		velocity.y = 4.8
	if _stuck_t >= 1.0 and _melee_cd <= 0.0:
		_melee_cd = 0.55
		_breach(fwd)
	if _stuck_t >= 3.0:
		if OS.is_debug_build() and game.auto:
			print("[stuck] %s %s %s goal %s path %d/%d" % [display_name, global_position.snapped(Vector3.ONE * 0.1), state_name(), _want_goal.snapped(Vector3.ONE * 0.1), _path_i, _path.size()])
		nav.block_temporarily(nav.world_to_cell(global_position + fwd * 1.0), 20.0)
		_path_goal = Vector3.INF
		_stuck_t = 0.0


## Rifle-butt the soft obstacle in front (hedge, picket fence, door, glass).
func _breach(fwd: Vector3) -> void:
	for h: float in [1.1, 0.5]:
		var from := global_position + Vector3(0, h, 0)
		var hit := VoxelWorld.instance.raycast(from, from + fwd * 1.3, Layers.SOLID)
		if hit.is_empty():
			continue
		var o := hit.collider as VoxelObject
		if o == null:
			return
		if not o.static_mode:
			o.apply_impulse(fwd * minf(o.mass, 300.0) * 2.0, hit.position - o.global_position)
			return
		var vox := o.voxel_at_hit(hit.position, hit.normal)
		if vox != 0 and VoxMat.PROPS[VoxMat.material_of(vox)][0] <= 1.0:
			model.kick()
			VoxelWorld.instance.damage_at(o, hit.position - hit.normal * 0.1, 0.5, 1.3, fwd * 60.0, 0.3, 6)
			VoxelWorld.instance.sfx.play("hammer", hit.position, -4.0, _rng.randf_range(0.85, 1.1))
		return


func _footsteps(delta: float) -> void:
	if not is_on_floor():
		return
	var hs := Vector2(velocity.x, velocity.z).length()
	_step_acc += hs * delta
	if _step_acc > (0.95 if hs > 4.5 else 0.75):
		_step_acc = 0.0
		VoxelWorld.instance.sfx.play("step", global_position, -15.0 + (3.0 if hs > 4.5 else 0.0), _rng.randf_range(0.85, 1.15))
