class_name TdmHud
extends CanvasLayer
## Battlefield-style HUD for the team deathmatch: compass, team score bars and
## clock, kill feed, rotating minimap (drawn from the bots' nav grid, so it
## shows destruction), health, weapon panel with ammo pips, dynamic crosshair,
## hit markers, damage direction arcs, score ribbons, radio callouts, markers
## over team mates and spotted enemies, death screen, Tab scoreboard, end of
## round screen, suppression / low health screen effect and the sniper scope.
## In spectator mode (--tdm_auto) it follows the bot the camera watches.

const FRIEND := Color(0.36, 0.74, 1.0)
const FOE := Color(1.0, 0.33, 0.2)
const ACCENT := Color(1.0, 0.62, 0.18)
const PANEL := Color(0.02, 0.03, 0.04, 0.55)
const WHITE := Color(0.96, 0.97, 0.98)

var game: TdmMatch
var player: Player
## Spectator mode: the bot being watched (else the player).
var subject: Node3D
var camera: Camera3D

static var font: Font
static var font_bold: Font

var _canvas: Canvas
var _map: Minimap
var _fx: ColorRect
var _scope: ColorRect
var _end_box: VBoxContainer
var _ribbons: Array = []       # [text, points, t]
var _radio: Array = []         # [text, t]
var _hit_t := 0.0
var _hit_kill := false
var _hit_head := false
var _banner := ""
var _banner_t := 0.0
var _show_help := false


func _ready() -> void:
	layer = 9
	add_to_group("tdm_hud")
	if font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial"])
		f.font_weight = 500
		font = f
		var b := SystemFont.new()
		b.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial"])
		b.font_weight = 700
		font_bold = b
	_fx = ColorRect.new()
	_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/hud_fx.gdshader")
	_fx.material = sm
	add_child(_fx)
	_scope = ColorRect.new()
	_scope.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sc := ShaderMaterial.new()
	sc.shader = load("res://shaders/scope.gdshader")
	_scope.material = sc
	_scope.visible = false
	add_child(_scope)
	_canvas = Canvas.new()
	_canvas.hud = self
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	_map = Minimap.new()
	_map.hud = self
	_map.clip_contents = true
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_map)
	game.kill_feed.connect(func(_e): pass)
	game.player_event.connect(_on_event)
	game.radio.connect(func(text: String, team: int):
		if team == player.team or game.auto:
			_radio.append([text, _now()])
			if _radio.size() > 4:
				_radio.pop_front())
	game.round_over.connect(_on_round_over)


func _now() -> float:
	return Time.get_ticks_msec() * 0.001


func hitmarker(kill: bool, head: bool) -> void:
	_hit_t = 0.28 if kill else 0.18
	_hit_kill = kill
	_hit_head = head
	VoxelWorld.instance.sfx.play_ui("hitmark", -8.0 if not kill else -4.0, 1.25 if head else 1.0)


func _on_event(kind: String, text: String, points: int) -> void:
	if kind == "start":
		_banner = text
		_banner_t = 5.0
		return
	_ribbons.append([text, points, _now(), kind])
	if _ribbons.size() > 5:
		_ribbons.pop_front()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("toggle_help"):
		_show_help = not _show_help


func _process(_delta: float) -> void:
	camera = get_viewport().get_camera_3d()
	if subject == null:
		subject = player
	var vs := get_viewport().get_visible_rect().size
	var s := vs.y / 1080.0
	var mm := 270.0 * s
	_map.position = Vector2(26 * s, vs.y - 26 * s - mm - 40 * s)
	_map.size = Vector2(mm, mm)
	_map.queue_redraw()
	_canvas.queue_redraw()
	var sup := 0.0
	var low := 0.0
	var dead := false
	if subject == player and not game.auto:
		sup = player.suppression
		low = clampf(1.0 - player.health / 45.0, 0.0, 1.0) if not player.dead else 0.0
		dead = player.dead
	var mat := _fx.material as ShaderMaterial
	mat.set_shader_parameter("suppression", sup)
	mat.set_shader_parameter("low_health", low)
	mat.set_shader_parameter("hurt", player.hurt if subject == player else 0.0)
	mat.set_shader_parameter("dead", 1.0 if dead or game.over else 0.0)
	# The effect reads the screen; skip it entirely when idle.
	_fx.visible = sup + low + (player.hurt if subject == player else 0.0) > 0.01 or dead or game.over
	_scope.visible = subject == player and player.guns != null and player.guns.scoped and not player.dead
	_hit_t = maxf(_hit_t - _delta, 0.0)
	_banner_t -= _delta


func _on_round_over(w: int) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_end_box = VBoxContainer.new()
	_end_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_end_box.offset_top = -190
	_end_box.offset_bottom = -60
	_end_box.offset_left = -220
	_end_box.offset_right = 220
	_end_box.add_theme_constant_override("separation", 10)
	add_child(_end_box)
	for b in [["Ещё один бой", func(): GameState.start(GameState.LEVEL_DISTRICT, "", GameState.MODE_TDM)],
			["Главное меню", func(): GameState.to_menu()]]:
		var btn := Button.new()
		btn.text = b[0]
		btn.custom_minimum_size = Vector2(440, 54)
		btn.add_theme_font_override("font", font_bold)
		btn.add_theme_font_size_override("font_size", 24)
		btn.pressed.connect(b[1])
		_end_box.add_child(btn)
	_end_box.visible = not game.auto
	if game.auto:
		get_tree().create_timer(6.0).timeout.connect(func(): GameState.to_menu())
	var _unused := w


# ================================================================== drawing helpers

static func text(ci: CanvasItem, pos: Vector2, t: String, size: float, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, bold := false, outline := 0.0) -> void:
	var f := font_bold if bold else font
	if outline > 0.0:
		ci.draw_string_outline(f, pos, t, align, width, int(size), int(outline), Color(0, 0, 0, color.a * 0.6))
	ci.draw_string(f, pos, t, align, width, int(size), color)


static func text_w(t: String, size: float, bold := false) -> float:
	return (font_bold if bold else font).get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(size)).x


## Slanted panel (Battlefield-style parallelogram).
static func slant(ci: CanvasItem, r: Rect2, color: Color, skew := 10.0) -> void:
	if r.size.x <= skew * 2.0 + 1.0 or r.size.y <= 1.0:
		ci.draw_rect(r, color)
		return
	ci.draw_colored_polygon(PackedVector2Array([
		r.position + Vector2(skew, 0), Vector2(r.end.x, r.position.y),
		r.end - Vector2(skew, 0), Vector2(r.position.x, r.end.y)]), color)


func subject_arsenal() -> Weapons.Arsenal:
	if subject is Bot:
		return (subject as Bot).arsenal
	if player.guns:
		return player.guns.arsenal
	return null


func subject_health() -> float:
	return float(subject.get("health"))


func subject_yaw() -> float:
	if subject == player and player.dead and camera:
		return camera.global_rotation.y
	return subject.global_rotation.y


# ================================================================== main canvas

class Canvas:
	extends Control
	var hud: TdmHud

	func _draw() -> void:
		if hud.subject == null or not is_instance_valid(hud.subject):
			return
		var vs := get_viewport_rect().size
		var s := vs.y / 1080.0
		var g := hud.game
		_draw_markers(s)
		_draw_compass(vs, s)
		_draw_scores(vs, s, g)
		_draw_feed(vs, s, g)
		if not g.auto and hud.player.dead and not g.over:
			_draw_death(vs, s, g)
		else:
			_draw_crosshair(vs, s)
			_draw_damage_arcs(vs, s)
		_draw_health(vs, s)
		_draw_weapon(vs, s)
		_draw_ribbons(vs, s)
		_draw_radio(vs, s)
		if hud._banner_t > 0.0:
			_draw_banner(vs, s)
		if g.auto:
			_draw_spectator(vs, s)
		if hud._show_help:
			_draw_help(vs, s)
		if g.over:
			_draw_end(vs, s, g)
		elif Input.is_action_pressed("scoreboard"):
			_draw_scoreboard(vs, s, g)

	# ---------------------------------------------------------- compass
	func _draw_compass(vs: Vector2, s: float) -> void:
		var w := 620.0 * s
		var cx := vs.x * 0.5
		var y := 16.0 * s
		var h := 26.0 * s
		draw_rect(Rect2(cx - w * 0.5, y, w, h), Color(0, 0, 0, 0.28))
		var yaw := rad_to_deg(-hud.subject_yaw())
		var span := 100.0
		var labels := {0: "С", 45: "СВ", 90: "В", 135: "ЮВ", 180: "Ю", 225: "ЮЗ", 270: "З", 315: "СЗ"}
		for deg in range(0, 360, 5):
			var rel := wrapf(float(deg) - yaw, -180.0, 180.0)
			if absf(rel) > span * 0.5:
				continue
			var x := cx + rel / span * w
			var a := 1.0 - absf(rel) / (span * 0.5)
			if labels.has(deg):
				TdmHud.text(self, Vector2(x - 30 * s, y + 19 * s), labels[deg], 17 * s, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, 60 * s, true)
			elif deg % 15 == 0:
				draw_line(Vector2(x, y + 4 * s), Vector2(x, y + 12 * s), Color(1, 1, 1, a * 0.8), 1.5 * s)
				TdmHud.text(self, Vector2(x - 20 * s, y + 24 * s), str(deg), 10 * s, Color(1, 1, 1, a * 0.6), HORIZONTAL_ALIGNMENT_CENTER, 40 * s)
			else:
				draw_line(Vector2(x, y + 4 * s), Vector2(x, y + 8 * s), Color(1, 1, 1, a * 0.4), 1.0 * s)
		# Spotted enemies on the compass.
		var me: Node3D = hud.subject
		for e in hud.game.enemies_of(me.get("team")):
			if not hud.game.is_spotted(e, me.get("team")):
				continue
			var d: Vector3 = e.global_position - me.global_position
			var b := rad_to_deg(atan2(d.x, -d.z))
			var rel := wrapf(b - yaw, -180.0, 180.0)
			if absf(rel) < span * 0.5:
				var x := cx + rel / span * w
				_diamond(Vector2(x, y + h + 6 * s), 5 * s, TdmHud.FOE)
		draw_colored_polygon(PackedVector2Array([Vector2(cx - 6 * s, y + h + 1), Vector2(cx + 6 * s, y + h + 1), Vector2(cx, y + h - 7 * s)]), TdmHud.ACCENT)

	func _diamond(c: Vector2, r: float, col: Color) -> void:
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), col)

	# ---------------------------------------------------------- scores
	func _draw_scores(vs: Vector2, s: float, g: TdmMatch) -> void:
		var cx := vs.x * 0.5
		var y := 54.0 * s
		var my_team: int = hud.subject.get("team")
		var tbox := Rect2(cx - 58 * s, y, 116 * s, 42 * s)
		TdmHud.slant(self, tbox, Color(0.02, 0.03, 0.04, 0.75), 8 * s)
		var tl := int(ceil(g.time_left))
		TdmHud.text(self, Vector2(tbox.position.x, y + 31 * s), "%02d:%02d" % [tl / 60, tl % 60], 28 * s, TdmHud.WHITE, HORIZONTAL_ALIGNMENT_CENTER, tbox.size.x, true)
		for side in 2:
			var t := my_team if side == 0 else 1 - my_team
			var col: Color = TdmHud.FRIEND if t == my_team else TdmHud.FOE
			var dir := -1.0 if side == 0 else 1.0
			var bw := 300.0 * s
			var x0 := cx + dir * 66 * s
			var box := Rect2(x0 - (78 * s if side == 0 else 0.0), y, 78 * s, 42 * s)
			TdmHud.slant(self, box, Color(col.r * 0.35, col.g * 0.35, col.b * 0.35, 0.8), 8 * s)
			TdmHud.text(self, Vector2(box.position.x, y + 33 * s), str(g.team_score[t]), 32 * s, col.lightened(0.2), HORIZONTAL_ALIGNMENT_CENTER, box.size.x, true)
			var bar := Rect2(x0 + (dir * 86 * s) - (bw if side == 0 else 0.0), y + 8 * s, bw, 10 * s)
			draw_rect(bar, Color(0, 0, 0, 0.45))
			var k := clampf(float(g.team_score[t]) / g.score_limit, 0.0, 1.0)
			var fill := Rect2(bar.position.x + (bar.size.x * (1.0 - k) if side == 0 else 0.0), bar.position.y, bar.size.x * k, bar.size.y)
			draw_rect(fill, col)
			for tick in range(1, 10):
				var tx := bar.position.x + bar.size.x * tick / 10.0
				draw_line(Vector2(tx, bar.position.y), Vector2(tx, bar.end.y), Color(0, 0, 0, 0.35), 1.0)
			var label: String = TdmMatch.TEAM_NAMES[t] + ("  (ВЫ)" if t == my_team and not g.auto else "")
			TdmHud.text(self, Vector2(bar.position.x, bar.end.y + 18 * s), label, 14 * s, col, HORIZONTAL_ALIGNMENT_RIGHT if side == 0 else HORIZONTAL_ALIGNMENT_LEFT, bar.size.x, true, 3 * s)

	# ---------------------------------------------------------- kill feed
	func _draw_feed(vs: Vector2, s: float, g: TdmMatch) -> void:
		var y := 22.0 * s
		var now := hud._now()
		var my_team: int = hud.subject.get("team")
		for e: Dictionary in g.feed:
			var age := now - float(e.t)
			if age > 8.0:
				continue
			var a := clampf((8.0 - age) / 1.0, 0.0, 1.0) * clampf(age / 0.15, 0.0, 1.0)
			var fs := 17.0 * s
			var parts: Array = []
			if e.killer != "":
				parts.append([e.killer, _team_col(int(e.killer_team), my_team), true])
			parts.append(["[%s]" % e.weapon if e.weapon != "" else "[—]", Color(0.85, 0.87, 0.9), false])
			if e.headshot:
				parts.append(["◎", TdmHud.ACCENT, true])
			parts.append([e.victim, _team_col(int(e.victim_team), my_team), true])
			var total := 0.0
			for p in parts:
				total += TdmHud.text_w(p[0], fs, p[2]) + 10 * s
			var x := vs.x - 26 * s - total
			var row := Rect2(x - 12 * s, y, total + 18 * s, 28 * s)
			TdmHud.slant(self, row, Color(0.02, 0.03, 0.04, 0.55 * a), 6 * s)
			if e.player:
				draw_rect(Rect2(row.position.x - 4 * s, y, 3 * s, row.size.y), Color(TdmHud.ACCENT, a))
			for p in parts:
				var c: Color = p[1]
				c.a = a
				TdmHud.text(self, Vector2(x, y + 20 * s), p[0], fs, c, HORIZONTAL_ALIGNMENT_LEFT, -1, p[2])
				x += TdmHud.text_w(p[0], fs, p[2]) + 10 * s
			y += 32 * s

	func _team_col(t: int, mine: int) -> Color:
		if t < 0:
			return Color(0.8, 0.8, 0.8)
		return TdmHud.FRIEND if t == mine else TdmHud.FOE

	# ---------------------------------------------------------- world markers
	func _draw_markers(s: float) -> void:
		var cam := hud.camera
		if cam == null:
			return
		var me: Node3D = hud.subject
		var team: int = me.get("team")
		for o in hud.game.soldiers:
			if o == me or o.dead:
				continue
			var head: Vector3 = o.global_position + Vector3(0, 2.15, 0)
			if cam.is_position_behind(head):
				continue
			var p := cam.unproject_position(head)
			if not p.is_finite() or p.x < -100 or p.y < -100 or p.x > size.x + 100 or p.y > size.y + 100:
				continue
			var d := cam.global_position.distance_to(head)
			if o.team == team:
				var a := clampf(1.0 - (d - 60.0) / 80.0, 0.35, 1.0)
				var r := 7.0 * s
				draw_colored_polygon(PackedVector2Array([p + Vector2(-r, -r * 0.6), p + Vector2(r, -r * 0.6), p + Vector2(0, r * 0.7)]), Color(TdmHud.FRIEND, a))
				if d < 45.0:
					TdmHud.text(self, p + Vector2(-80 * s, -12 * s), o.display_name, 14 * s, Color(TdmHud.FRIEND, a), HORIZONTAL_ALIGNMENT_CENTER, 160 * s, true, 3 * s)
			elif hud.game.is_spotted(o, team):
				var r2 := 8.0 * s
				_diamond(p, r2, Color(TdmHud.FOE, 0.95))
				_diamond(p, r2 * 0.45, Color(0.1, 0.02, 0.0, 0.9))
				if d < 35.0:
					TdmHud.text(self, p + Vector2(-80 * s, -14 * s), o.display_name, 13 * s, TdmHud.FOE, HORIZONTAL_ALIGNMENT_CENTER, 160 * s, true, 3 * s)

	# ---------------------------------------------------------- crosshair
	func _draw_crosshair(vs: Vector2, s: float) -> void:
		var c := vs * 0.5
		var p := hud.player
		if hud.subject == p and p.guns and not p.dead and p.vehicle == null:
			var guns := p.guns
			if guns.scoped:
				return
			var w := guns.arsenal.current
			var focal := vs.y * 0.5 / tan(deg_to_rad(p.camera.fov * 0.5))
			var gap := clampf(guns.current_spread() * focal, 3.0 * s, 120.0 * s)
			var col := Color(1, 1, 1, 0.9)
			if guns.ads > 0.6 and w == Weapons.RIFLE:
				draw_circle(c, 2.6 * s, Color(1.0, 0.15, 0.1, 0.95))
				draw_arc(c, 7 * s, 0, TAU, 24, Color(1.0, 0.15, 0.1, 0.35), 1.0 * s)
			elif w == Weapons.SHOTGUN:
				draw_arc(c, gap + 4 * s, 0, TAU, 40, Color(1, 1, 1, 0.7), 1.6 * s)
				draw_circle(c, 1.8 * s, col)
			elif w == Weapons.GRENADE:
				draw_arc(c, 10 * s, PI * 0.15, PI * 0.85, 16, col, 2.0 * s)
				draw_circle(c, 2.0 * s, col)
			elif w == Weapons.RPG:
				draw_line(c + Vector2(-14 * s, 0), c + Vector2(-5 * s, 0), col, 2.0 * s)
				draw_line(c + Vector2(14 * s, 0), c + Vector2(5 * s, 0), col, 2.0 * s)
				for k in 3:
					var yy := (8 + k * 9) * s
					draw_line(c + Vector2(-(6 - k) * s, yy), c + Vector2((6 - k) * s, yy), Color(1, 1, 1, 0.7), 1.5 * s)
			else:
				var l := 9.0 * s
				for dvec in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
					draw_line(c + dvec * gap, c + dvec * (gap + l), Color(0, 0, 0, 0.5), 3.4 * s)
					draw_line(c + dvec * gap, c + dvec * (gap + l), col, 1.8 * s)
				draw_circle(c, 1.4 * s, col)
			if guns.arsenal.reloading():
				var k2 := guns.arsenal.reload_progress()
				draw_arc(c, 24 * s, -PI * 0.5, -PI * 0.5 + TAU * k2, 40, Color(TdmHud.ACCENT, 0.9), 3 * s)
			elif guns.arsenal.mags[w] <= int(Weapons.DEFS[w].mag * 0.25) and Weapons.DEFS[w].mag > 2:
				var blink := 0.5 + 0.5 * sin(hud._now() * 8.0)
				TdmHud.text(self, c + Vector2(-120 * s, 64 * s), "[R]  ПЕРЕЗАРЯДКА" if guns.arsenal.reserves[w] > 0 else "НЕТ ПАТРОНОВ", 16 * s, Color(TdmHud.ACCENT, 0.5 + blink * 0.5), HORIZONTAL_ALIGNMENT_CENTER, 240 * s, true, 3 * s)
		# Hit marker.
		if hud._hit_t > 0.0:
			var k3 := hud._hit_t / (0.28 if hud._hit_kill else 0.18)
			var hc := Color(1.0, 0.2, 0.15, k3) if hud._hit_kill else (Color(TdmHud.ACCENT, k3) if hud._hit_head else Color(1, 1, 1, k3))
			var r0 := (7.0 if hud._hit_kill else 6.0) * s
			var r1 := (17.0 if hud._hit_kill else 13.0) * s
			for dvec in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				var dn: Vector2 = dvec.normalized()
				draw_line(c + dn * r0, c + dn * r1, hc, (3.0 if hud._hit_kill else 2.2) * s)

	func _draw_damage_arcs(vs: Vector2, s: float) -> void:
		var p := hud.player
		if hud.subject != p:
			return
		var c := vs * 0.5
		var now := Time.get_ticks_msec()
		var yaw := p.global_rotation.y
		var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
		var right := Vector3(cos(yaw), 0, -sin(yaw))
		for h: Array in p.hit_dirs:
			var age := (now - int(h[1])) / 1000.0
			if age > 1.8:
				continue
			var d: Vector3 = h[0]
			var ang := atan2(d.dot(right), d.dot(fwd))
			var a := clampf(1.0 - age / 1.8, 0.0, 1.0)
			var mid := ang - PI * 0.5
			draw_arc(c, 150 * s, mid - 0.35, mid + 0.35, 24, Color(1.0, 0.12, 0.08, 0.85 * a), 9 * s)

	# ---------------------------------------------------------- health, weapon
	func _draw_health(vs: Vector2, s: float) -> void:
		var x := 26.0 * s
		var y := vs.y - 26.0 * s - 30.0 * s
		var w := 270.0 * s
		var hp := hud.subject_health()
		TdmHud.slant(self, Rect2(x, y, w, 30 * s), TdmHud.PANEL, 6 * s)
		var k := clampf(hp / 100.0, 0.0, 1.0)
		var col := Color(0.95, 0.95, 0.95) if k > 0.35 else Color(1.0, 0.25, 0.18)
		var bar := Rect2(x + 58 * s, y + 10 * s, w - 72 * s, 10 * s)
		draw_rect(bar, Color(0, 0, 0, 0.5))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * k, bar.size.y)), col)
		for t in range(1, 10):
			var tx := bar.position.x + bar.size.x * t / 10.0
			draw_line(Vector2(tx, bar.position.y), Vector2(tx, bar.end.y), Color(0, 0, 0, 0.4), 1.0)
		TdmHud.text(self, Vector2(x + 8 * s, y + 23 * s), str(ceili(hp)), 22 * s, col, HORIZONTAL_ALIGNMENT_LEFT, 48 * s, true)

	func _draw_weapon(vs: Vector2, s: float) -> void:
		var ars := hud.subject_arsenal()
		if ars == null:
			return
		var w := ars.current
		var d: Dictionary = Weapons.DEFS[w]
		var right := vs.x - 26.0 * s
		var bottom := vs.y - 26.0 * s
		var pw := 400.0 * s
		var panel := Rect2(right - pw, bottom - 112 * s, pw, 112 * s)
		TdmHud.slant(self, panel, TdmHud.PANEL, 10 * s)
		draw_rect(Rect2(panel.position.x + 10 * s, panel.position.y, pw - 10 * s, 2 * s), Color(TdmHud.ACCENT, 0.8))
		TdmHud.text(self, Vector2(panel.position.x + 22 * s, panel.position.y + 26 * s), "%s  ·  %s" % [d.short, String(d.name).to_upper()], 15 * s, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_LEFT, -1, true)
		var mag := str(ars.mags[w])
		var big := 62.0 * s
		var mx := panel.position.x + 22 * s
		var low: bool = ars.mags[w] <= int(d.mag * 0.25) and d.mag > 2
		TdmHud.text(self, Vector2(mx, panel.end.y - 18 * s), mag, big, Color(1.0, 0.35, 0.25) if low else TdmHud.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
		var mw := TdmHud.text_w(mag, big, true)
		TdmHud.text(self, Vector2(mx + mw + 10 * s, panel.end.y - 22 * s), "/ %d" % ars.reserves[w], 26 * s, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_LEFT, -1, true)
		TdmHud.text(self, Vector2(mx + mw + 10 * s, panel.end.y - 56 * s), d.mode, 13 * s, TdmHud.ACCENT, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
		# Ammo pips.
		var pips := int(d.mag)
		var px := panel.end.x - 26 * s
		var py := panel.end.y - 52 * s
		var pip_w := clampf(150.0 * s / pips, 3 * s, 14 * s)
		for i in pips:
			var on := i < ars.mags[w]
			var r := Rect2(px - (i + 1) * pip_w, py, pip_w - 1.5 * s, 16 * s)
			draw_rect(r, Color(1, 1, 1, 0.9) if on else Color(1, 1, 1, 0.15))
		# Equipment counters.
		var gx := panel.end.x - 26 * s
		var gy := panel.end.y - 16 * s
		var gren := ars.mags[Weapons.GRENADE] + ars.reserves[Weapons.GRENADE]
		var rock := ars.mags[Weapons.RPG] + ars.reserves[Weapons.RPG]
		var eq := "ГРАНАТЫ ×%d    РАКЕТЫ ×%d" % [gren, rock]
		TdmHud.text(self, Vector2(gx - 300 * s, gy), eq, 14 * s, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_RIGHT, 300 * s, true)
		# Slots above the panel.
		var sx := right - pw + 10 * s
		var sy := panel.position.y - 30 * s
		for i in Weapons.COUNT:
			var label := "%d %s" % [i + 1, Weapons.DEFS[i].short]
			var tw := TdmHud.text_w(label, 14 * s, true) + 16 * s
			var r2 := Rect2(sx, sy, tw, 24 * s)
			var cur := i == w
			TdmHud.slant(self, r2, Color(TdmHud.ACCENT, 0.85) if cur else Color(0, 0, 0, 0.4), 5 * s)
			var c: Color = Color(0.05, 0.05, 0.05) if cur else (Color(1, 1, 1, 0.75) if ars.has_ammo(i) else Color(1, 1, 1, 0.3))
			TdmHud.text(self, Vector2(sx + 8 * s, sy + 17 * s), label, 14 * s, c, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
			sx += tw + 4 * s

	# ---------------------------------------------------------- ribbons, radio, banner
	func _draw_ribbons(vs: Vector2, s: float) -> void:
		var now := hud._now()
		var y := vs.y * 0.62
		var total := 0
		for r: Array in hud._ribbons:
			if now - float(r[2]) < 3.5:
				total += int(r[1])
		var i := 0
		for r: Array in hud._ribbons:
			var age := now - float(r[2])
			if age > 3.5:
				continue
			var a := clampf((3.5 - age) / 0.6, 0.0, 1.0)
			var slide := (1.0 - clampf(age / 0.12, 0.0, 1.0)) * 40.0 * s
			var t: String = r[0]
			var big: bool = r[3] == "kill"
			var fs := (24.0 if big else 18.0) * s
			var yy := y + i * 30 * s
			var tw := TdmHud.text_w(t, fs, true)
			var pts := "+%d" % r[1] if int(r[1]) > 0 else ""
			var pwid := TdmHud.text_w(pts, fs, true)
			var x := vs.x * 0.5 - (tw + pwid + 16 * s) * 0.5 + slide
			TdmHud.text(self, Vector2(x, yy), t, fs, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_LEFT, -1, true, 4 * s)
			if pts != "":
				TdmHud.text(self, Vector2(x + tw + 16 * s, yy), pts, fs, Color(TdmHud.ACCENT, a), HORIZONTAL_ALIGNMENT_LEFT, -1, true, 4 * s)
			i += 1
		if total > 100:
			TdmHud.text(self, Vector2(vs.x * 0.5 - 100 * s, y - 34 * s), "+%d" % total, 30 * s, TdmHud.ACCENT, HORIZONTAL_ALIGNMENT_CENTER, 200 * s, true, 4 * s)

	func _draw_radio(vs: Vector2, s: float) -> void:
		var now := hud._now()
		var y := vs.y - 26 * s - 270 * s - 40 * s - 16 * s
		var lines: Array = []
		for r: Array in hud._radio:
			if now - float(r[1]) < 6.0:
				lines.append(r)
		for k in lines.size():
			var r: Array = lines[lines.size() - 1 - k]
			var a := clampf((6.0 - (now - float(r[1]))) / 0.8, 0.0, 1.0)
			TdmHud.text(self, Vector2(28 * s, y - k * 24 * s), r[0], 16 * s, Color(TdmHud.FRIEND.lightened(0.25), a), HORIZONTAL_ALIGNMENT_LEFT, -1, true, 4 * s)

	func _draw_banner(vs: Vector2, s: float) -> void:
		var a := clampf(hud._banner_t / 0.8, 0.0, 1.0)
		var y := vs.y * 0.3
		draw_rect(Rect2(0, y - 54 * s, vs.x, 92 * s), Color(0, 0, 0, 0.45 * a))
		draw_rect(Rect2(vs.x * 0.5 - 220 * s, y - 54 * s, 440 * s, 3 * s), Color(TdmHud.ACCENT, a))
		TdmHud.text(self, Vector2(0, y), "КОМАНДНЫЙ БОЙ", 44 * s, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, vs.x, true)
		TdmHud.text(self, Vector2(0, y + 28 * s), hud._banner, 18 * s, Color(TdmHud.ACCENT, a), HORIZONTAL_ALIGNMENT_CENTER, vs.x, true)

	func _draw_spectator(vs: Vector2, s: float) -> void:
		var b := hud.subject as Bot
		if b == null:
			return
		var t := "НАБЛЮДЕНИЕ:  %s  ·  %s  ·  %s" % [b.display_name, TdmMatch.TEAM_NAMES[b.team], b.state_name()]
		TdmHud.text(self, Vector2(0, vs.y - 160 * s), t, 18 * s, TdmHud.FRIEND if b.team == 0 else TdmHud.FOE, HORIZONTAL_ALIGNMENT_CENTER, vs.x, true, 4 * s)

	func _draw_help(vs: Vector2, s: float) -> void:
		var lines := ["WASD — движение, Shift — бег, Ctrl — присесть, Space — прыжок",
			"ЛКМ — огонь, ПКМ — прицел, R — перезарядка, G — быстрая граната",
			"1–5 / колесо — оружие, Q — пометить врага, Tab — таблица счёта",
			"E — сесть в машину, F3 — производительность, Esc — пауза"]
		var r := Rect2(vs.x - 26 * s - 560 * s, 250 * s, 560 * s, 30 * s + lines.size() * 24 * s)
		draw_rect(r, TdmHud.PANEL)
		for i in lines.size():
			TdmHud.text(self, r.position + Vector2(16 * s, 30 * s + i * 24 * s), lines[i], 15 * s, Color(1, 1, 1, 0.9))

	# ---------------------------------------------------------- death screen
	func _draw_death(vs: Vector2, s: float, g: TdmMatch) -> void:
		var p := hud.player
		var k: Node3D = p.killer
		var y := vs.y * 0.66
		draw_rect(Rect2(0, y - 70 * s, vs.x, 150 * s), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(vs.x * 0.5 - 260 * s, y - 70 * s, 520 * s, 3 * s), TdmHud.FOE)
		if k != null and is_instance_valid(k):
			var entry: Dictionary = g.feed.back() if not g.feed.is_empty() else {}
			TdmHud.text(self, Vector2(0, y - 34 * s), "ВАС УБИЛ", 16 * s, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER, vs.x, true)
			TdmHud.text(self, Vector2(0, y + 6 * s), k.display_name, 38 * s, TdmHud.FOE, HORIZONTAL_ALIGNMENT_CENTER, vs.x, true)
			var dist := roundi(k.global_position.distance_to(p.global_position))
			var info := "%s  ·  %d м  ·  у врага %d HP" % [entry.get("weapon", ""), dist, ceili(float(k.get("health")))]
			if entry.get("headshot", false):
				info += "  ·  В ГОЛОВУ"
			TdmHud.text(self, Vector2(0, y + 34 * s), info, 17 * s, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_CENTER, vs.x, true)
		else:
			TdmHud.text(self, Vector2(0, y), "ВЫ ПОГИБЛИ", 38 * s, TdmHud.FOE, HORIZONTAL_ALIGNMENT_CENTER, vs.x, true)
		var left := g.respawn_left(p)
		TdmHud.text(self, Vector2(0, y + 66 * s), "ВОЗРОЖДЕНИЕ ЧЕРЕЗ %d" % ceili(left), 18 * s, TdmHud.ACCENT, HORIZONTAL_ALIGNMENT_CENTER, vs.x, true)

	# ---------------------------------------------------------- scoreboard
	func _draw_scoreboard(vs: Vector2, s: float, g: TdmMatch) -> void:
		var w := 1240.0 * s
		var h := 470.0 * s
		var r := Rect2((vs.x - w) * 0.5, vs.y * 0.5 - h * 0.5 - 20 * s, w, h)
		draw_rect(r, Color(0.02, 0.03, 0.04, 0.82))
		var my_team: int = hud.subject.get("team")
		for side in 2:
			var t := my_team if side == 0 else 1 - my_team
			var col: Color = TdmHud.FRIEND if side == 0 else TdmHud.FOE
			var x := r.position.x + 20 * s + side * (w * 0.5)
			var cw := w * 0.5 - 40 * s
			var y := r.position.y + 44 * s
			draw_rect(Rect2(x, y - 34 * s, cw, 3 * s), col)
			TdmHud.text(self, Vector2(x, y), TdmMatch.TEAM_NAMES[t], 26 * s, col, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
			TdmHud.text(self, Vector2(x, y), str(g.team_score[t]), 30 * s, col, HORIZONTAL_ALIGNMENT_RIGHT, cw, true)
			y += 38 * s
			var cols := [["ИМЯ", 0.0], ["У", 0.52], ["С", 0.62], ["П", 0.72], ["ОЧКИ", 0.84]]
			for c in cols:
				TdmHud.text(self, Vector2(x + cw * float(c[1]), y), c[0], 13 * s, Color(1, 1, 1, 0.55), HORIZONTAL_ALIGNMENT_LEFT, -1, true)
			y += 12 * s
			var rank := 1
			for o in g.sorted_team(t):
				var st: Dictionary = g.stats[o]
				var me: bool = o == hud.player and not g.auto
				var row := Rect2(x, y, cw, 34 * s)
				draw_rect(row, Color(col.r, col.g, col.b, 0.28 if me else 0.1))
				if me:
					draw_rect(Rect2(x, y, 3 * s, row.size.y), TdmHud.ACCENT)
				var a := 0.45 if o.dead else 1.0
				var name: String = "%d  %s" % [rank, o.display_name]
				TdmHud.text(self, Vector2(x + 10 * s, y + 24 * s), name, 17 * s, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_LEFT, -1, true)
				var vals := [st.kills, st.deaths, st.assists, st.score]
				for i in 4:
					TdmHud.text(self, Vector2(x + cw * float(cols[i + 1][1]), y + 24 * s), str(vals[i]), 17 * s, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_LEFT, -1, i == 3)
				y += 38 * s
				rank += 1

	# ---------------------------------------------------------- end of round
	func _draw_end(vs: Vector2, s: float, g: TdmMatch) -> void:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.55))
		var my_team: int = 0 if g.auto else hud.player.team
		var title := "НИЧЬЯ"
		var col := Color(0.9, 0.9, 0.9)
		if g.winner >= 0:
			var won: bool = g.winner == my_team
			title = ("ПОБЕДА" if won else "ПОРАЖЕНИЕ") if not g.auto else "ПОБЕДИЛИ " + TdmMatch.TEAM_NAMES[g.winner]
			col = TdmHud.FRIEND if won or (g.auto and g.winner == 0) else TdmHud.FOE
		var y := vs.y * 0.2
		draw_rect(Rect2(vs.x * 0.5 - 300 * s, y - 70 * s, 600 * s, 4 * s), col)
		TdmHud.text(self, Vector2(0, y), title, 72 * s, col, HORIZONTAL_ALIGNMENT_CENTER, vs.x, true)
		TdmHud.text(self, Vector2(0, y + 50 * s), "%s  %d  :  %d  %s" % [TdmMatch.TEAM_NAMES[0], g.team_score[0], g.team_score[1], TdmMatch.TEAM_NAMES[1]], 26 * s, TdmHud.WHITE, HORIZONTAL_ALIGNMENT_CENTER, vs.x, true)
		var m := g.mvp()
		if m:
			var st: Dictionary = g.stats[m]
			var box := Rect2(vs.x * 0.5 - 260 * s, y + 90 * s, 520 * s, 96 * s)
			TdmHud.slant(self, box, Color(0.02, 0.03, 0.04, 0.8), 12 * s)
			TdmHud.text(self, Vector2(box.position.x, box.position.y + 30 * s), "ЛУЧШИЙ ИГРОК МАТЧА", 15 * s, TdmHud.ACCENT, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, true)
			TdmHud.text(self, Vector2(box.position.x, box.position.y + 64 * s), m.display_name, 30 * s, TdmHud.FRIEND if m.team == 0 else TdmHud.FOE, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, true)
			TdmHud.text(self, Vector2(box.position.x, box.position.y + 88 * s), "%d очков · %d убийств · %d в голову" % [st.score, st.kills, st.headshots], 15 * s, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER, box.size.x)
		_draw_scoreboard(vs + Vector2(0, 260 * s), s * 0.82, g)


# ================================================================== minimap

class Minimap:
	extends Control
	var hud: TdmHud
	const RANGE := 130.0

	func _draw() -> void:
		if hud.subject == null or not is_instance_valid(hud.subject):
			return
		var g := hud.game
		var nav := g.nav
		var sz := size
		var s := sz.x / 270.0
		draw_rect(Rect2(Vector2.ZERO, sz), Color(0.03, 0.04, 0.05, 0.62))
		var me: Node3D = hud.subject
		var center := sz * 0.5
		var scale := sz.x / RANGE
		var yaw := hud.subject_yaw()
		var mp := me.global_position
		if nav.texture:
			# World x,z -> map pixels, rotated so that the view points up.
			var off := Vector2(mp.x - nav.origin.x, mp.z - nav.origin.y) / NavGrid.CELL
			draw_set_transform(center, yaw, Vector2.ONE * scale * NavGrid.CELL)
			draw_texture(nav.texture, -off, Color(1, 1, 1, 0.92))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var team: int = me.get("team")
		var now := Time.get_ticks_msec() * 0.001
		for b in g.bags:
			_blip(b.global_position, mp, yaw, center, scale, Color(0.4, 0.9, 0.4, 0.9), 3.0 * s, "square")
		for o in g.soldiers:
			if o == me or o.dead:
				continue
			if o.team == team:
				_blip(o.global_position, mp, yaw, center, scale, TdmHud.FRIEND, 6.0 * s, "arrow", o.global_rotation.y)
			elif g.is_spotted(o, team):
				_blip(o.global_position, mp, yaw, center, scale, TdmHud.FOE, 6.0 * s, "diamond")
			elif now - float(o.fired_t) < 1.2 and o.global_position.distance_to(mp) < 60.0:
				# Unsuppressed fire shows up on the map, like in Battlefield.
				_blip(o.global_position, mp, yaw, center, scale, Color(TdmHud.FOE, 0.7), 4.0 * s, "dot")
		# Self.
		var r := 8.0 * s
		draw_colored_polygon(PackedVector2Array([center + Vector2(0, -r), center + Vector2(r * 0.7, r * 0.7), center + Vector2(0, r * 0.3), center + Vector2(-r * 0.7, r * 0.7)]), Color(1, 1, 1))
		# View cone.
		var fov := deg_to_rad(39.0)
		draw_line(center, center + Vector2(sin(-fov), -cos(fov)) * sz.x * 0.35, Color(1, 1, 1, 0.18), 1.0)
		draw_line(center, center + Vector2(sin(fov), -cos(fov)) * sz.x * 0.35, Color(1, 1, 1, 0.18), 1.0)
		# North marker on the rim.
		var n := Vector2(sin(yaw), -cos(yaw)) * (sz.x * 0.5 - 12 * s)
		TdmHud.text(self, center + n + Vector2(-10 * s, 6 * s), "С", 14 * s, TdmHud.ACCENT, HORIZONTAL_ALIGNMENT_CENTER, 20 * s, true, 3 * s)
		draw_rect(Rect2(Vector2.ZERO, sz), Color(1, 1, 1, 0.25), false, 1.5)
		draw_rect(Rect2(0, 0, sz.x, 3 * s), Color(TdmHud.ACCENT, 0.8))
		var zone := g.zone_name_at(mp)
		if zone != "":
			TdmHud.text(self, Vector2(8 * s, sz.y - 8 * s), zone.to_upper(), 12 * s, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_LEFT, -1, true, 3 * s)

	func _blip(p: Vector3, me: Vector3, yaw: float, center: Vector2, scale: float, col: Color, r: float, kind: String, dir_yaw := 0.0) -> void:
		var d := Vector2(p.x - me.x, p.z - me.z).rotated(yaw) * scale
		var lim := size.x * 0.5 - r
		d = d.clamp(Vector2(-lim, -lim), Vector2(lim, lim))
		var c := center + d
		match kind:
			"arrow":
				var a := yaw - dir_yaw
				var pts := PackedVector2Array()
				for v in [Vector2(0, -r), Vector2(r * 0.7, r * 0.7), Vector2(-r * 0.7, r * 0.7)]:
					pts.append(c + (v as Vector2).rotated(-a))
				draw_colored_polygon(pts, col)
			"diamond":
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), col)
			"square":
				draw_rect(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), col)
			_:
				draw_circle(c, r, col)
