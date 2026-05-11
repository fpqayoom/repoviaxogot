@tool
extends EditorPlugin

const PANEL_SCENE := "res://addons/qugit/scenes/main.tscn"

var _panel: Control = null

func _enter_tree() -> void:
	if not ResourceLoader.exists(PANEL_SCENE):
		push_warning("qugit: main.tscn missing")
		return
	var scene: PackedScene = load(PANEL_SCENE)
	if not scene:
		return
	_panel = scene.instantiate()
	if _panel:
		add_control_to_bottom_panel(_panel, "qugit")

func _exit_tree() -> void:
	if _panel:
		remove_control_from_bottom_panel(_panel)
		_panel.queue_free()
		_panel = null
