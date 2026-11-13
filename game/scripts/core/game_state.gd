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
const SETTINGS_PATH := "user://settings.cfg"
## Graphics preset; saved to user://settings.cfg whenever it changes.
var quality := Quality.HIGH:
	set(v):
		quality = clampi(v, 0, Quality.COUNT - 1)
		var cfg := ConfigFile.new()
		cfg.load(SETTINGS_PATH)
		cfg.set_value("graphics", "quality", quality)
		cfg.save(SETTINGS_PATH)


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK and cfg.has_section_key("graphics", "quality"):
		quality = int(cfg.get_value("graphics", "quality"))
	else:
		quality = Quality.detect_default()
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		match kv[0]:
			"level":
				level = kv[1] if kv.size() > 1 else LEVEL_DISTRICT
			"cinematic":
				cinematic = kv[1] if kv.size() > 1 else "all"
			"quality":
				quality = int(kv[1])
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
