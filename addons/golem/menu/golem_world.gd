extends Node3D

const OPTIONS_MENU := preload("res://addons/golem/menu/options_menu.gd")


func _enter_tree() -> void:
	if get_node_or_null("OptionsMenu") != null:
		return
	var menu: CanvasLayer = OPTIONS_MENU.new()
	menu.name = "OptionsMenu"
	menu.layer = 20
	add_child(menu)
