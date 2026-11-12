class_name PauseMenu
extends CanvasLayer
## Esc: pause with Resume / Main menu / Quit.

var _panel: Control


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = ColorRect.new()
	(_panel as ColorRect).color = Color(0, 0, 0, 0.55)
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.visible = false
	add_child(_panel)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.offset_left = -220
	box.offset_right = 220
	box.offset_top = -150
	box.offset_bottom = 150
	box.add_theme_constant_override("separation", 12)
	_panel.add_child(box)
	var t := Label.new()
	t.text = "Пауза"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 40)
	box.add_child(t)
	_btn(box, "Продолжить", toggle)
	_btn(box, "Главное меню", func(): GameState.to_menu())
	_btn(box, "Выход", func(): get_tree().quit())


func _btn(parent: Control, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(440, 56)
	b.add_theme_font_size_override("font_size", 26)
	b.pressed.connect(cb)
	parent.add_child(b)


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	var on := not get_tree().paused
	get_tree().paused = on
	_panel.visible = on
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED
