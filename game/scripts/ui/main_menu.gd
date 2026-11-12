extends Control
## Title screen: pick the district map, the prototype range or the fly-throughs.
## Any scripted command line run (--bench, --level, --cinematic, ...) skips it.

const AUTOSTART := ["bench", "tour", "drive", "tools", "crater", "dtour", "audit", "glass", "level", "cinematic", "tdm", "tdm_auto", "tdm_test"]


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.trim_prefix("--").split("=")[0] in AUTOSTART:
			GameState.start.call_deferred(GameState.level, GameState.cinematic, GameState.mode)
			return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := TextureRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	if ResourceLoader.exists("res://ui/menu_bg.png"):
		bg.texture = load("res://ui/menu_bg.png")
	add_child(bg)
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.05, 0.04, 0.03, 0.55)
	add_child(shade)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	box.offset_left = 110
	box.offset_top = -230
	box.offset_right = 760
	box.offset_bottom = 230
	box.add_theme_constant_override("separation", 14)
	add_child(box)
	var title := Label.new()
	title.text = "ВОКСЕЛЬНЫЙ СНОС"
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.55))
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Полностью разрушаемый воксельный мир"
	sub.add_theme_font_size_override("font_size", 22)
	sub.modulate = Color(1, 1, 1, 0.8)
	box.add_child(sub)
	box.add_child(_spacer(26))
	_button(box, "Американский пригород — карта", func(): GameState.start(GameState.LEVEL_DISTRICT))
	_button(box, "Командный бой 5×5 — TDM с ботами", func(): GameState.start(GameState.LEVEL_DISTRICT, "", GameState.MODE_TDM))
	_button(box, "Полигон — прототип механик", func(): GameState.start(GameState.LEVEL_PROTO))
	_button(box, "Кинопролёты по пригороду", func(): GameState.start(GameState.LEVEL_DISTRICT, "all"))
	var q := OptionButton.new()
	for n in Quality.NAMES:
		q.add_item("Графика: " + n)
	q.selected = GameState.quality
	q.item_selected.connect(func(i: int): GameState.quality = i)
	q.add_theme_font_size_override("font_size", 24)
	q.custom_minimum_size = Vector2(520, 54)
	box.add_child(q)
	_button(box, "Выход", func(): get_tree().quit())
	var hint := Label.new()
	hint.text = "Esc в игре — пауза и возврат в меню"
	hint.modulate = Color(1, 1, 1, 0.6)
	box.add_child(hint)


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _button(parent: Control, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(520, 58)
	b.add_theme_font_size_override("font_size", 28)
	b.pressed.connect(cb)
	parent.add_child(b)
