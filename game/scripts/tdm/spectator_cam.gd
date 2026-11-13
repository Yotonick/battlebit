class_name SpectatorCam
extends Camera3D
## Spectator camera for bot-only matches (--tdm_auto): follows one bot over
## the shoulder, switching to whoever is fighting every few seconds.

var game: TdmMatch
var hud: TdmHud
var target: Bot
var _switch_t := 0.0


func _ready() -> void:
	fov = 70.0
	far = Quality.view_distance(GameState.quality)
	make_current()


func _process(delta: float) -> void:
	_switch_t -= delta
	if target == null or target.dead or _switch_t <= 0.0:
		_pick()
	if target == null:
		return
	hud.subject = target
	var yaw := target.global_rotation.y
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var want_pos := target.global_position + Vector3(0, 2.3, 0) - fwd * 3.6 + right * 0.9
	var hit := VoxelWorld.instance.raycast(target.global_position + Vector3(0, 1.8, 0), want_pos, Layers.STATIC)
	if not hit.is_empty():
		want_pos = hit.position + (target.global_position + Vector3(0, 1.8, 0) - want_pos).normalized() * 0.3
	var look := target.global_position + Vector3(0, 1.4, 0) + target.aim_dir() * 8.0
	var want := Transform3D(Basis.looking_at((look - want_pos).normalized(), Vector3.UP), want_pos)
	global_transform = global_transform.interpolate_with(want, 1.0 - exp(-5.0 * delta))


func _pick() -> void:
	_switch_t = 9.0
	var best: Bot = null
	var bs := -INF
	for b in game.bots:
		if b.dead:
			continue
		var s := randf() * 2.0
		if b.state == Bot.COMBAT:
			s += 5.0
		if b == target:
			s += 1.0
		if s > bs:
			bs = s
			best = b
	if best != target and best != null:
		target = best
		global_transform = Transform3D(Basis.IDENTITY, target.global_position + Vector3(0, 2.5, 3.0))
