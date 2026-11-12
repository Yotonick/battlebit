class_name PlayerGuns
extends Node3D
## The player's five team deathmatch weapons: first-person voxel models, aiming
## down sights (RMB, sniper scope), recoil and spread, reloading (R), quick
## grenade (G) and spotting enemies (Q). Shares the bots' Arsenal and Combat.

const BASE_POS := Vector3(0.24, -0.26, -0.46)
## Sight height above the grip (meters) per weapon, to line it up when aiming.
const SIGHT := [0.124, 0.076, 0.124, 0.17, 0.0]
const ADS_Z := [-0.3, -0.34, -0.3, -0.36, -0.4]

var player: Player
var input_enabled := true
var arsenal := Weapons.Arsenal.new()
var aiming := false
## 0..1 progress into the sights.
var ads := 0.0
var scoped := false
## Scripted trigger for automated tests.
var sim_fire := false
var _models: Array[Node3D] = []
var _recoil := 0.0
var _switch := 0.0
var _sway := Vector2.ZERO
var _prev := Weapons.RIFLE
var _throw_anim := 0.0
var _spot_cd := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_setup_input()
	for w in Weapons.COUNT:
		var n := Node3D.new()
		var mi := GunModels.instance(w)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(mi)
		n.visible = w == arsenal.current
		add_child(n)
		_models.append(n)


func _setup_input() -> void:
	for a in [["aim", -1, MOUSE_BUTTON_RIGHT], ["reload", KEY_R, 0], ["spot", KEY_Q, 0], ["quick_grenade", KEY_G, 0], ["scoreboard", KEY_TAB, 0]]:
		if InputMap.has_action(a[0]):
			continue
		InputMap.add_action(a[0])
		if a[1] == -1:
			var mb := InputEventMouseButton.new()
			mb.button_index = a[2]
			InputMap.action_add_event(a[0], mb)
		else:
			var k := InputEventKey.new()
			k.physical_keycode = a[1]
			InputMap.action_add_event(a[0], k)


func on_respawn() -> void:
	arsenal.refill_all()
	_select(Weapons.RIFLE, true)
	aiming = false
	ads = 0.0
	scoped = false


func current_def() -> Dictionary:
	return Weapons.DEFS[arsenal.current]


func _select(w: int, force := false) -> void:
	if force:
		arsenal.current = w
		arsenal.equip_t = 0.3
	elif not arsenal.select(w):
		return
	for i in _models.size():
		_models[i].visible = i == w
	_switch = 1.0


func _unhandled_input(e: InputEvent) -> void:
	if not input_enabled or player.dead:
		return
	for k in Weapons.COUNT:
		if e.is_action_pressed("tool_%d" % (k + 1)):
			if k != arsenal.current:
				_prev = arsenal.current
			_select(k)
	if e is InputEventMouseButton and e.pressed and not aiming:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var step := -1 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1
			var w := arsenal.current
			for i in Weapons.COUNT:
				w = wrapi(w + step, 0, Weapons.COUNT)
				if arsenal.has_ammo(w):
					break
			_prev = arsenal.current
			_select(w)
	if e.is_action_pressed("reload"):
		if arsenal.start_reload():
			VoxelWorld.instance.sfx.play("reload", global_position, -6.0)
	if e.is_action_pressed("quick_grenade"):
		_quick_throw()
	if e.is_action_pressed("spot"):
		_spot()
	if e is InputEventMouseMotion:
		_sway += e.relative * 0.0003


func _process(delta: float) -> void:
	if player == null:
		return
	arsenal.tick(delta)
	_spot_cd -= delta
	_switch = maxf(_switch - delta * 4.0, 0.0)
	var d := current_def()
	var captured := input_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not player.dead and player.vehicle == null
	var fire_pressed := captured and Input.is_action_just_pressed("fire")
	var fire_held := captured and Input.is_action_pressed("fire")
	if sim_fire:
		fire_pressed = true
		fire_held = true
	var sprint := player.is_sprinting() and player.is_on_floor()
	aiming = captured and Input.is_action_pressed("aim") and not arsenal.reloading() and arsenal.current != Weapons.GRENADE and not sprint
	ads = move_toward(ads, 1.0 if aiming else 0.0, delta * 5.5)
	scoped = d.get("scope", false) and ads > 0.92
	player.speed_mult = lerpf(1.0, 0.55, ads) * (0.9 if arsenal.current == Weapons.RPG else 1.0)
	var fov_target: float = lerpf(78.0, float(d.ads_fov), ads)
	if not player.dead and player.vehicle == null:
		player.camera.fov = lerpf(player.camera.fov, fov_target, 1.0 - exp(-18.0 * delta))
		player.mouse_sensitivity = 0.0022 * lerpf(1.0, float(d.ads_fov) / 78.0, ads)

	if not sprint:
		var want := fire_held if d.auto else fire_pressed
		if want and arsenal.ready():
			_fire()
		elif fire_pressed and arsenal.mags[arsenal.current] == 0 and not arsenal.busy():
			if not arsenal.start_reload():
				VoxelWorld.instance.sfx.play_ui("dry", -6.0)
			else:
				VoxelWorld.instance.sfx.play("reload", global_position, -6.0)
	# Out of grenades or rockets: back to the rifle.
	if not arsenal.has_ammo(arsenal.current) and not arsenal.busy() and arsenal.current != Weapons.RIFLE:
		_select(Weapons.RIFLE if arsenal.has_ammo(Weapons.RIFLE) else Weapons.SHOTGUN)
	_animate(delta, sprint)


## Spread cone (radians) for the current state, also drawn by the crosshair.
func current_spread() -> float:
	var d := current_def()
	var hv := Vector2(player.velocity.x, player.velocity.z).length()
	var hip: float = d.spread * (1.0 + clampf(hv / 4.0, 0.0, 1.2) * 0.8) * (0.7 if player.crouching else 1.0)
	if not player.is_on_floor():
		hip *= 2.5
	var s := lerpf(hip, float(d.ads_spread) * (1.0 + clampf(hv / 4.0, 0.0, 1.0)), ads)
	return s * (1.0 + arsenal.burst * (0.1 if arsenal.current == Weapons.RIFLE else 0.0))


func muzzle_pos() -> Vector3:
	var m := _models[arsenal.current]
	return m.global_transform * (GunModels.get_model(arsenal.current).muzzle as Vector3)


func _fire() -> void:
	var w := arsenal.current
	var d := current_def()
	var spread := current_spread()
	arsenal.consume()
	player.fired_t = Time.get_ticks_msec() * 0.001
	_recoil = 1.0
	var kick: float = d.recoil * (0.55 if ads > 0.5 else 1.0)
	match d.kind:
		"hitscan":
			var res := Combat.fire_hitscan(player, player.camera.global_position, muzzle_pos(), player.aim_dir(), w, spread)
			player.add_recoil(kick * _rng.randf_range(0.7, 1.0), _rng.randf_range(-0.35, 0.35) * kick)
			player.shake(0.06 if w == Weapons.RIFLE else 0.2)
			if res.hit:
				var hud := get_tree().get_first_node_in_group("tdm_hud")
				if hud:
					hud.hitmarker(res.kill, res.head)
		"rocket":
			_fire_rocket(spread)
			player.add_recoil(kick, 0.0)
			player.shake(0.3)
		"grenade":
			_spawn_grenade()
			arsenal.start_reload()
	if arsenal.mags[w] == 0 and arsenal.reserves[w] > 0 and d.kind != "grenade":
		# Auto reload after the last round, like the bots.
		get_tree().create_timer(0.25).timeout.connect(func():
			if arsenal.current == w and arsenal.start_reload():
				VoxelWorld.instance.sfx.play("reload", global_position, -6.0))


func _fire_rocket(spread: float) -> void:
	var d: Dictionary = Weapons.DEFS[Weapons.RPG]
	var r := Projectiles.Rocket.new()
	r.shooter_rid = player.get_rid()
	r.source = player
	r.weapon = Weapons.RPG
	r.blast_radius = d.blast_radius
	r.blast_power = d.blast_power
	VoxelWorld.instance.add_child(r)
	var from := muzzle_pos()
	var dir := player.aim_dir()
	var hit := player.aim_ray(300.0)
	if not hit.is_empty() and from.distance_to(hit.position) > 2.0:
		dir = (hit.position - from).normalized()
	dir = (dir + Vector3(_rng.randfn(), _rng.randfn(), _rng.randfn()) * spread).normalized()
	r.global_position = from
	r.velocity = dir * float(d.speed)
	r.look_at(from + dir, Vector3.UP)
	VoxelWorld.instance.sfx.play("rocket", from, 2.0)
	Combat.noise(from, d.noise, player)


func _quick_throw() -> void:
	var g := Weapons.GRENADE
	if _throw_anim > 0.0 or arsenal.busy() or arsenal.current == g:
		return
	if arsenal.mags[g] <= 0:
		if arsenal.reserves[g] <= 0:
			return
		arsenal.reserves[g] -= 1
		arsenal.mags[g] = 1
	arsenal.mags[g] -= 1
	if arsenal.reserves[g] > 0:
		arsenal.reserves[g] -= 1
		arsenal.mags[g] = 1
	_spawn_grenade()
	arsenal.equip_t = 0.55


func _spawn_grenade() -> void:
	var d: Dictionary = Weapons.DEFS[Weapons.GRENADE]
	var g := Projectiles.PipeBomb.new()
	g.grenade = true
	g.fuse = d.fuse
	g.source = player
	g.weapon = Weapons.GRENADE
	g.blast_radius = d.blast_radius
	g.blast_power = d.blast_power
	VoxelWorld.instance.add_child(g)
	g.global_position = player.camera.global_position + player.aim_dir() * 0.5 + Vector3.DOWN * 0.1
	g.linear_velocity = player.aim_dir() * float(d.speed) + Vector3.UP * 2.0 + player.velocity * 0.5
	g.angular_velocity = Vector3(_rng.randf_range(-8, 8), _rng.randf_range(-8, 8), _rng.randf_range(-8, 8))
	VoxelWorld.instance.sfx.play("pin", g.global_position, -6.0)
	VoxelWorld.instance.sfx.play("throw", g.global_position, -4.0)
	Combat.noise(g.global_position, 25.0, player)
	_throw_anim = 1.0


## Q: mark the enemies under the crosshair for the whole team.
func _spot() -> void:
	if _spot_cd > 0.0:
		return
	_spot_cd = 0.6
	var game := get_tree().get_first_node_in_group("tdm_match")
	if game == null:
		return
	var eye := player.camera.global_position
	var dir := player.aim_dir()
	var n := 0
	for s: Node3D in game.enemies_of(player.team):
		var to: Vector3 = s.aim_point() - eye
		if to.length() > 180.0 or dir.angle_to(to) > deg_to_rad(7.0):
			continue
		if VoxelWorld.instance.raycast(eye, s.aim_point(), Layers.STATIC).is_empty():
			game.spot(s, player.team, 7.0)
			n += 1
	if n > 0:
		VoxelWorld.instance.sfx.play_ui("click", -4.0, 1.4)
		game.player_event("spot", n)


func _animate(delta: float, sprint: bool) -> void:
	var w := arsenal.current
	var m := _models[w]
	m.visible = not scoped
	_sway = _sway.lerp(Vector2.ZERO, 1.0 - exp(-8.0 * delta))
	var hv := Vector2(player.velocity.x, player.velocity.z).length()
	var t := Time.get_ticks_msec() * 0.001
	var bob_k := clampf(hv / 5.0, 0.0, 1.5) * (1.0 - ads * 0.85) if player.is_on_floor() else 0.0
	var bob := Vector3(sin(t * 7.5) * 0.01, absf(cos(t * 7.5)) * 0.012, 0) * bob_k
	var hip := BASE_POS
	var aim := Vector3(0.0, -SIGHT[w], ADS_Z[w])
	var pos := hip.lerp(aim, ads) + bob + Vector3(-_sway.x, _sway.y, 0) * (1.0 - ads * 0.8)
	pos.y -= _switch * 0.3
	var rot := Vector3.ZERO
	if sprint:
		rot += Vector3(-0.35, 0.6, 0.15)
		pos += Vector3(-0.05, -0.05, 0.05)
	_recoil = maxf(_recoil - delta * 7.0, 0.0)
	rot.x += _recoil * (0.08 if ads > 0.5 else 0.2)
	pos.z += _recoil * (0.03 if ads > 0.5 else 0.07)
	if arsenal.reloading():
		var k := sin(arsenal.reload_progress() * PI)
		rot += Vector3(-0.5, 0.0, 0.6) * k
		pos += Vector3(0.0, -0.12, 0.0) * k
	_throw_anim = maxf(_throw_anim - delta * 2.5, 0.0)
	var tk := sin(_throw_anim * PI)
	if w == Weapons.GRENADE:
		pos += Vector3(0.05, 0.05, 0.05)
		rot.x += tk * -1.4
	else:
		# Quick throw: the gun dips while the other hand throws.
		pos.y -= tk * 0.15
		rot.z += tk * 0.4
	m.position = pos
	m.rotation = rot
