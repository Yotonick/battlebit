class_name TdmTest
extends Node
## Scripted team deathmatch check (--tdm_test --shots=<dir>): screenshots of the
## HUD at spawn, in a firefight, through the scope, of the scoreboard, the
## death screen and the end of the round (use --tdm_limit=N for a short one).

var game: TdmMatch
var player: Player
var shot_dir := "user://shots"
var quit_after := 240.0
var _t := 0.0
var _step := 0
var _end_t := -1.0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(shot_dir)


func _shot(name: String) -> void:
	var path := shot_dir.path_join(name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("[tdm_test] screenshot ", path, " | score %d:%d" % [game.team_score[0], game.team_score[1]])


func _process(delta: float) -> void:
	if not game.started:
		return
	_t += delta
	match _step:
		0:
			if _t > 6.0:
				_shot("t_spawn")
				_step += 1
		1:
			if _t > 24.0 and _go_fight():
				_step += 1
				_t = 24.0
		2:
			if _t > 25.4:
				_shot("t_fight")
				_step += 1
		3:
			if _t > 26.0:
				player.guns.sim_fire = false
				player.guns._select(Weapons.SNIPER, true)
				Input.action_press("aim")
				_step += 1
		4:
			if _t > 27.6:
				_shot("t_scope")
				Input.action_release("aim")
				player.guns._select(Weapons.RIFLE, true)
				Input.action_press("scoreboard")
				_step += 1
		5:
			if _t > 28.2:
				_shot("t_scoreboard")
				Input.action_release("scoreboard")
				_step += 1
		6:
			if _t > 29.0:
				player.god_mode = false
				var e := _nearest_enemy()
				if e:
					player.take_hit(500.0, e, Weapons.RIFLE, true, e.global_position)
				_step += 1
		7:
			if _t > 31.0:
				_shot("t_death")
				_step += 1
		8:
			if _t > 60.0:
				_shot("t_later")
				_step += 1
		9:
			if game.over and _end_t < 0.0:
				_end_t = _t
			if _end_t >= 0.0 and _t > _end_t + 2.5:
				_shot("t_end")
				get_tree().quit()
	if _t > quit_after:
		get_tree().quit()


func _nearest_enemy() -> Node3D:
	var best: Node3D = null
	var bd := INF
	for e in game.enemies_of(player.team):
		var d := e.global_position.distance_to(player.global_position)
		if d < bd:
			bd = d
			best = e
	return best


## Put the player behind a team mate who is in a firefight and open fire.
func _go_fight() -> bool:
	for b in game.bots:
		if b.team != player.team or b.dead or b.state != Bot.COMBAT or b.target == null or not b._visible(b.target):
			continue
		var tgt := b.target
		var yaw := b.global_rotation.y
		var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
		var right := Vector3(cos(yaw), 0, -sin(yaw))
		player.god_mode = true
		player.global_position = b.global_position - fwd * 2.2 + right * 0.9
		var d: Vector3 = tgt.aim_point() - player.camera.global_position
		player.look_at_dir(atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))
		player.guns.sim_fire = true
		return true
	return false
