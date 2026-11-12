class_name TdmMatch
extends Node
## 5 vs 5 team deathmatch on the district: the player and four bots (blue)
## against five bots (red). First team to SCORE_LIMIT kills, or the higher score
## when the clock runs out, wins. Owns teams, spawns, scoring (kill 100,
## headshot +25, assist 50, spot 10), the kill feed, the bots' director (which
## zone each bot pushes to), shared spotting, radio callouts and ammo bags.

signal kill_feed(entry: Dictionary)
signal player_event(kind: String, text: String, points: int)
signal radio(text: String, team: int)
signal round_over(winner: int)

const SCORE_LIMIT := 50
const TIME_LIMIT := 600.0
const RESPAWN_TIME := 5.0
const TEAM_NAMES := ["СИНИЕ", "КРАСНЫЕ"]
const TEAM_COLORS := [Color(0.35, 0.72, 1.0), Color(1.0, 0.34, 0.22)]
const BOT_NAMES := ["Ghost", "Viper", "Hawk", "Reaper", "Maverick", "Bishop", "Cobra", "Raven", "Saber",
	"Nomad", "Havoc", "Jester", "Rook", "Falcon", "Wolf", "Diesel", "Kodiak", "Spectre"]
const ROLES := ["assault", "marksman", "assault", "breacher", "assault"]

## Team spawn areas (x, z).
const SPAWNS := [
	[Vector2(30, -53.5), Vector2(46, -53.5), Vector2(62, -53.5), Vector2(77, -53.5), Vector2(-25, -83),
		Vector2(-2, -83), Vector2(-43.5, -58), Vector2(-43.5, -72), Vector2(16, -53.5)],
	[Vector2(-70, 51.8), Vector2(-46, 51.8), Vector2(40, 51.8), Vector2(62, 51.8), Vector2(78, 51.8),
		Vector2(-74, 38), Vector2(-60, 38), Vector2(55, 44), Vector2(87, 30)],
]
## Zones the director sends bots to: [center, weight, radius, name].
const ZONES := [
	[Vector2(-17, -15), 3.0, 10.0, "детская площадка"],
	[Vector2(44, -33), 2.0, 7.0, "баскетбольная площадка"],
	[Vector2(62, -19), 2.0, 8.0, "восточная парковка"],
	[Vector2(-20, -40), 2.0, 9.0, "двор у первого дома"],
	[Vector2(-44, -12), 2.0, 7.0, "западный проезд"],
	[Vector2(-5, 11), 2.0, 9.0, "южный проезд"],
	[Vector2(45, -5), 2.0, 8.0, "сараи"],
	[Vector2(-20, -83), 1.0, 8.0, "склады"],
	[Vector2(50, -61), 1.2, 10.0, "парковка FOOD MART"],
	[Vector2(-68, 40), 1.2, 9.0, "парковка аптеки"],
	[Vector2(56, 44), 1.2, 7.0, "автосервис"],
	[Vector2(12, 45), 1.0, 7.0, "остановка"],
	[Vector2(-78, -30), 1.0, 8.0, "берег реки"],
	[Vector2(75, 38), 1.0, 6.0, "мусорные баки"],
]

var main: Node3D
var world: VoxelWorld
var nav: NavGrid
var player: Player
var soldiers: Array[Node3D] = []
var bots: Array[Bot] = []
var team_score := [0, 0]
## soldier -> {kills, deaths, assists, score, headshots}
var stats := {}
var time_left := TIME_LIMIT
var score_limit := SCORE_LIMIT
var over := false
var winner := -1
var started := false
## Spectator test mode: the player is out, ten bots fight.
var auto := false
var feed: Array[Dictionary] = []
var bags: Array[Node3D] = []

var _spotted := [{}, {}]          # team -> {soldier: {pos, t, until}}
var _damage := {}                 # victim -> {attacker: damage}
var _respawn := {}                # soldier -> seconds left
var _path_budget := 2
var _rng := RandomNumberGenerator.new()
var _combat_marks: Array = []     # [pos, time] of recent kills for the director
var _radio_t := 0.0
var _bag_t := 0.0
var _last_callout := {}
var _log_t := 0.0
var weapon_kills := [0, 0, 0, 0, 0, 0]
## Test statistics: grenades thrown, rockets fired, bot CPU time.
var dbg := {"grenades": 0, "rockets": 0, "bot_usec": 0, "bot_max_usec": 0, "frames": 0}
var kill_dist_sum := 0.0


func _ready() -> void:
	add_to_group("tdm_match")
	_rng.randomize()


func setup(m: Node3D, w: VoxelWorld, p: Player, spectate: bool) -> void:
	main = m
	world = w
	player = p
	auto = spectate
	Combat.tracers = Combat.Tracers.new()
	world.add_child(Combat.tracers)
	nav = NavGrid.new()
	nav.name = "NavGrid"
	add_child(nav)
	nav.setup(DistrictLevel.HALF, DistrictLevel.GY)
	player.team = 0
	player.display_name = "Вы"
	if auto:
		player.remove_from_group("soldiers")
		player.process_mode = Node.PROCESS_MODE_DISABLED
		player.visible = false
		player.collision_layer = 0
		player.collision_mask = 0
		player.dead = true
	else:
		soldiers.append(player)
		stats[player] = _new_stats()
		player.died.connect(func(k: Node, wpn: int, hs: bool): on_death(player, k, wpn, hs))
	var names := BOT_NAMES.duplicate()
	names.shuffle()
	var ni := 0
	for t in 2:
		var count := 5 if (t == 1 or auto) else 4
		var roles := ROLES.duplicate()
		roles.shuffle()
		for k in count:
			var b := Bot.new()
			b.game = self
			b.team = t
			b.display_name = names[ni]
			ni += 1
			b.role = roles[k % roles.size()]
			b.skill = _rng.randf_range(0.55, 0.92)
			b.name = "Bot_%s" % b.display_name
			b.process_mode = Node.PROCESS_MODE_DISABLED
			main.add_child(b)
			b.nav = nav
			b.global_position = Vector3(0, -50, 0)
			bots.append(b)
			soldiers.append(b)
			stats[b] = _new_stats()


## Called once the level is in the physics space: scan the grid, deploy.
func start() -> void:
	nav.scan_all()
	for s in soldiers:
		_spawn(s)
	for b in bots:
		b.process_mode = Node.PROCESS_MODE_INHERIT
	started = true
	player_event.emit("start", "%d УБИЙСТВ ДО ПОБЕДЫ  ·  10 МИНУТ" % score_limit, 0)


func _new_stats() -> Dictionary:
	return {"kills": 0, "deaths": 0, "assists": 0, "score": 0, "headshots": 0}


# ================================================================== queries

func enemies_of(team: int) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for s in soldiers:
		if s.team != team and not s.dead:
			out.append(s)
	return out


func allies_of(team: int) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for s in soldiers:
		if s.team == team and not s.dead:
			out.append(s)
	return out


func take_path_budget() -> bool:
	if _path_budget <= 0:
		return false
	_path_budget -= 1
	return true


func spot(s: Node3D, by_team: int, seconds := 4.0) -> void:
	var now := Time.get_ticks_msec() * 0.001
	var d: Dictionary = _spotted[by_team]
	var fresh := not d.has(s) or float(d[s].until) < now - 3.0
	d[s] = {"pos": s.global_position, "t": now, "until": now + seconds}
	if fresh and not auto and by_team == player.team and _radio_t <= 0.0:
		_radio_t = 3.0
		var spotter := _closest_ally_to(s.global_position, by_team)
		if spotter and spotter != player:
			var dist := roundi(spotter.global_position.distance_to(s.global_position))
			radio.emit("%s: Противник замечен — %d м, %s" % [spotter.display_name, dist, _bearing(spotter.global_position, s.global_position)], by_team)


func spotted_by(team: int) -> Dictionary:
	return _spotted[team]


func is_spotted(s: Node3D, by_team: int) -> bool:
	var d: Dictionary = _spotted[by_team]
	return d.has(s) and float(d[s].until) > Time.get_ticks_msec() * 0.001


func _closest_ally_to(p: Vector3, team: int) -> Node3D:
	var best: Node3D = null
	var bd := INF
	for a in allies_of(team):
		var d := a.global_position.distance_to(p)
		if d < bd:
			bd = d
			best = a
	return best


func _bearing(from: Vector3, to: Vector3) -> String:
	var d := to - from
	var ang := fposmod(rad_to_deg(atan2(d.x, -d.z)), 360.0)
	var names := ["север", "северо-восток", "восток", "юго-восток", "юг", "юго-запад", "запад", "северо-запад"]
	return names[int(round(ang / 45.0)) % 8]


func callout(b: Bot, kind: String) -> void:
	if auto or b.team != player.team:
		return
	var now := Time.get_ticks_msec() * 0.001
	if now - float(_last_callout.get(b, -100.0)) < 7.0:
		return
	_last_callout[b] = now
	var text: String = {"reload": "Перезаряжаюсь, прикройте!", "grenade": "Граната!", "rpg": "Ракета пошла!"}.get(kind, "")
	if text != "" and b.global_position.distance_to(player.global_position) < 60.0:
		radio.emit("%s: %s" % [b.display_name, text], b.team)


func nearest_bag(p: Vector3, radius: float) -> Node3D:
	var best: Node3D = null
	var bd := radius
	for g in bags:
		var d := g.global_position.distance_to(p)
		if d < bd:
			bd = d
			best = g
	return best


## Where this team's enemies are thought to be: spotted ones, else their spawn.
func front_point(team: int, from: Vector3) -> Vector3:
	var acc := Vector3.ZERO
	var n := 0
	var now := Time.get_ticks_msec() * 0.001
	var d: Dictionary = _spotted[team]
	for s in d:
		if is_instance_valid(s) and float(d[s].t) > now - 20.0:
			acc += d[s].pos
			n += 1
	if n > 0:
		return acc / n
	var c := Vector2.ZERO
	for sp: Vector2 in SPAWNS[1 - team]:
		c += sp
	c /= SPAWNS[1 - team].size()
	return Vector3(c.x, DistrictLevel.GY, c.y) if from == Vector3.INF else Vector3(c.x, DistrictLevel.GY, c.y)


## Director: the zone a bot should push to next.
func request_zone(b: Bot) -> Vector3:
	var now := Time.get_ticks_msec() * 0.001
	var own := _centroid(b.team)
	var foe := _centroid(1 - b.team)
	var mid := (own + foe) * 0.5
	var best := -1
	var best_s := -INF
	for i in ZONES.size():
		var z: Array = ZONES[i]
		var c := Vector3(z[0].x, DistrictLevel.GY, z[0].y)
		var heat := 0.0
		for m in _combat_marks:
			if now - float(m[1]) < 40.0 and (m[0] as Vector3).distance_to(c) < 25.0:
				heat += 1.0
		var crowd := 0
		for o in bots:
			if o != b and o.team == b.team and o._zone != Vector3.INF and o._zone.distance_to(c) < float(z[2]) + 4.0:
				crowd += 1
		var s: float = float(z[1]) * (1.0 + minf(heat, 4.0) * 0.5) - b.global_position.distance_to(c) / 55.0 \
			- c.distance_to(mid) / 70.0 - crowd * 1.3 + _rng.randf() * 1.5
		if s > best_s:
			best_s = s
			best = i
	var zz: Array = ZONES[best]
	return nav.random_point_near(Vector3(zz[0].x, DistrictLevel.GY, zz[0].y), zz[2], _rng)


func _centroid(team: int) -> Vector3:
	var acc := Vector3.ZERO
	var n := 0
	for s in allies_of(team):
		acc += s.global_position
		n += 1
	if n == 0:
		var c := Vector2.ZERO
		for sp: Vector2 in SPAWNS[team]:
			c += sp
		c /= SPAWNS[team].size()
		return Vector3(c.x, DistrictLevel.GY, c.y)
	return acc / n


func zone_name_at(p: Vector3) -> String:
	var best := ""
	var bd := 22.0
	for z: Array in ZONES:
		var d := Vector2(p.x, p.z).distance_to(z[0])
		if d < bd:
			bd = d
			best = z[3]
	return best


# ================================================================== damage, kills

func register_damage(victim: Node, source: Node, amount: float) -> void:
	if source == null or source == victim:
		return
	if not _damage.has(victim):
		_damage[victim] = {}
	_damage[victim][source] = float(_damage[victim].get(source, 0.0)) + amount


func on_death(victim: Node3D, killer: Node, weapon: int, headshot: bool) -> void:
	if not stats.has(victim):
		return
	stats[victim].deaths += 1
	var k := killer as Node3D
	var enemy_kill: bool = k != null and k != victim and stats.has(k) and k.team != victim.team
	var dist := 0.0
	if enemy_kill:
		dist = k.global_position.distance_to(victim.global_position)
		stats[k].kills += 1
		stats[k].score += 100 + (25 if headshot else 0)
		if headshot:
			stats[k].headshots += 1
		team_score[k.team] += 1
		if weapon >= 0 and weapon < Weapons.COUNT:
			weapon_kills[weapon] += 1
		kill_dist_sum += dist
	# Assists for everyone else who did real damage.
	var dmg: Dictionary = _damage.get(victim, {})
	for a in dmg:
		if a != k and is_instance_valid(a) and stats.has(a) and float(dmg[a]) >= 25.0 and a.team != victim.team:
			stats[a].assists += 1
			stats[a].score += 50
			if a == player:
				player_event.emit("assist", "ПОМОЩЬ В УБИЙСТВЕ  " + victim.display_name, 50)
	_damage.erase(victim)
	var entry := {
		"killer": k.display_name if k != null and stats.has(k) else "",
		"killer_team": k.team if k != null and stats.has(k) else -1,
		"victim": victim.display_name, "victim_team": victim.team,
		"weapon": Weapons.DEFS[weapon].short if weapon >= 0 and weapon < Weapons.COUNT else "",
		"headshot": headshot, "t": Time.get_ticks_msec() * 0.001,
		"player": k == player or victim == player,
	}
	feed.append(entry)
	if feed.size() > 6:
		feed.pop_front()
	kill_feed.emit(entry)
	if k == player and enemy_kill:
		player_event.emit("kill", "ВРАГ УБИТ  " + victim.display_name, 100)
		if headshot:
			player_event.emit("headshot", "В ГОЛОВУ", 25)
		world.sfx.play_ui("kill", -4.0)
	_combat_marks.append([victim.global_position, Time.get_ticks_msec() * 0.001])
	if _combat_marks.size() > 40:
		_combat_marks.pop_front()
	_drop_bag(victim.global_position)
	_respawn[victim] = RESPAWN_TIME
	if victim != player and k == player:
		pass
	if team_score[0] >= score_limit or team_score[1] >= score_limit:
		_end(0 if team_score[0] >= score_limit else 1)


func respawn_left(s: Node) -> float:
	return float(_respawn.get(s, 0.0))


func _drop_bag(p: Vector3) -> void:
	var bag := Node3D.new()
	var v := VoxModel.volume(Vector3i(8, 6, 5))
	v.fill_box(Vector3i(0, 0, 0), Vector3i(8, 5, 5), VoxMat.id("metal_green"))
	v.fill_box(Vector3i(0, 5, 1), Vector3i(8, 6, 4), VoxMat.id("tank_black"))
	v.fill_box(Vector3i(3, 1, 0), Vector3i(5, 4, 1), VoxMat.id("plastic_yellow"))
	bag.add_child(VoxModel.instance(v, 0.05, Vector3(4, 0, 2.5)))
	world.add_child(bag)
	var hit := world.raycast(p + Vector3(0, 1.0, 0), p + Vector3(0, -3.0, 0), Layers.STATIC)
	bag.global_position = hit.position if not hit.is_empty() else p
	bag.set_meta("life", 25.0)
	bags.append(bag)


func _spawn(s: Node3D) -> void:
	var pts: Array = SPAWNS[s.team]
	var best := Vector3.ZERO
	var best_s := -INF
	for sp: Vector2 in pts:
		var c := Vector3(sp.x, DistrictLevel.GY, sp.y)
		var near_enemy := INF
		var seen := false
		for e in enemies_of(s.team):
			var d := e.global_position.distance_to(c)
			near_enemy = minf(near_enemy, d)
			if d < 70.0 and not seen:
				seen = world.raycast(e.global_position + Vector3(0, 1.6, 0), c + Vector3(0, 1.5, 0), Layers.STATIC).is_empty()
		var mates := 0
		for a in allies_of(s.team):
			if a != s and a.global_position.distance_to(c) < 35.0:
				mates += 1
		var score := minf(near_enemy, 60.0) * 0.1 - (6.0 if seen else 0.0) + mates * 0.6 + _rng.randf() * 2.0
		if near_enemy < 18.0:
			score -= 20.0
		if score > best_s:
			best_s = score
			best = c
	var p := nav.random_point_near(best, 3.5, _rng) + Vector3(0, 0.05, 0)
	var f := front_point(s.team, Vector3.INF) - p
	var yaw := atan2(-f.x, -f.z)
	s.respawn_at(p, yaw)
	_respawn.erase(s)


func _end(w: int) -> void:
	if over:
		return
	over = true
	winner = w
	round_over.emit(w)


func mvp() -> Node3D:
	var best: Node3D = null
	var bs := -1
	for s in soldiers:
		if int(stats[s].score) > bs:
			bs = stats[s].score
			best = s
	return best


func sorted_team(t: int) -> Array:
	var out: Array = []
	for s in soldiers:
		if s.team == t:
			out.append(s)
	out.sort_custom(func(a, b): return int(stats[a].score) > int(stats[b].score))
	return out


# ================================================================== loop

func _physics_process(_delta: float) -> void:
	_path_budget = 2
	dbg.frames += 1


func _process(delta: float) -> void:
	if not started:
		return
	_radio_t -= delta
	if not over:
		time_left -= delta
		if time_left <= 0.0:
			time_left = 0.0
			_end(-1 if team_score[0] == team_score[1] else (0 if team_score[0] > team_score[1] else 1))
	for s in _respawn.keys():
		_respawn[s] -= delta
		if _respawn[s] <= 0.0 and not over:
			_spawn(s)
	# Spotting expires.
	var now := Time.get_ticks_msec() * 0.001
	for t in 2:
		var d: Dictionary = _spotted[t]
		for s in d.keys():
			if not is_instance_valid(s) or s.dead or float(d[s].until) < now - 6.0:
				d.erase(s)
	_bag_t -= delta
	if _bag_t <= 0.0:
		_bag_t = 0.25
		_update_bags(0.25)
	if auto:
		_log_t -= delta
		if _log_t <= 0.0:
			_log_t = 30.0
			print_status()


func _update_bags(dt: float) -> void:
	var i := 0
	while i < bags.size():
		var g := bags[i]
		var life: float = g.get_meta("life") - dt
		g.set_meta("life", life)
		var taken := false
		for s in soldiers:
			if s.dead or s.global_position.distance_to(g.global_position) > 1.4:
				continue
			if s == player:
				player.guns.arsenal.resupply()
				player_event.emit("ammo", "ПАТРОНЫ ПОПОЛНЕНЫ", 0)
			else:
				(s as Bot).arsenal.resupply()
			world.sfx.play("click", g.global_position, -6.0, 0.8)
			taken = true
			break
		if taken or life <= 0.0:
			g.queue_free()
			bags.remove_at(i)
		else:
			i += 1


func print_status() -> void:
	var states := {}
	var stuck := 0.0
	for b in bots:
		states[b.state_name()] = int(states.get(b.state_name(), 0)) + 1
		stuck += b.dbg_stuck
	var kills: int = team_score[0] + team_score[1]
	print("[tdm] %.0f s left | score %d:%d | kills by weapon %s | avg kill dist %.1f m | stuck total %.0f s | states %s | fps %d | grenades %d rockets %d | bots %.2f ms/frame (max %.1f)" % [
		time_left, team_score[0], team_score[1], weapon_kills, kill_dist_sum / maxf(kills, 1), stuck, states, Engine.get_frames_per_second(),
		dbg.grenades, dbg.rockets, dbg.bot_usec / 1000.0 / maxf(dbg.frames, 1), dbg.bot_max_usec / 1000.0])
	print("[tdm]   cpu: process %.1f ms, physics %.1f ms | objects %d (dyn %d), debris %d, pending rebuilds %d, rebuild max %.1f ms, explosions %d, nav queue %d" % [
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		world.objects.size(), world.dynamic_count(), world.debris.active_count, world.pending_rebuilds(), world.stats.rebuild_max_usec / 1000.0,
		world.stats.explosions, nav._queue.size()])
	world.stats.rebuild_max_usec = 0
	dbg.bot_usec = 0
	dbg.bot_max_usec = 0
	dbg.frames = 0
