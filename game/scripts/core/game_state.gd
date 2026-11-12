extends Node
## Autoload "GameState": what the main scene should load.

const LEVEL_PROTO := "proto"
const LEVEL_DISTRICT := "district"
const MODE_SANDBOX := "sandbox"
const MODE_TDM := "tdm"

var level := LEVEL_DISTRICT
## Sandbox (free destruction) or the 5 vs 5 team deathmatch with bots.
var mode := MODE_SANDBOX
## Empty for normal play, "all" or a shot name to run the cinematic fly-throughs.
var cinematic := ""
var quality := Quality.HIGH


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		match kv[0]:
			"level":
				level = kv[1] if kv.size() > 1 else LEVEL_DISTRICT
			"cinematic":
				cinematic = kv[1] if kv.size() > 1 else "all"
			"quality":
				quality = clampi(int(kv[1]), 0, 3)
			"tdm", "tdm_auto", "tdm_test":
				mode = MODE_TDM
				level = LEVEL_DISTRICT


func start(new_level: String, cine := "", new_mode := MODE_SANDBOX) -> void:
	level = new_level
	cinematic = cine
	mode = new_mode
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func to_menu() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/menu.tscn")
