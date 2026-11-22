extends RefCounted

const ACTIONS := {
	"move_forward": KEY_W,
	"move_backward": KEY_S,
	"move_left": KEY_A,
	"move_right": KEY_D,
	"jump": KEY_SPACE,
	"run": KEY_SHIFT,
	"crouch": KEY_X,
	"ragdoll": KEY_E,
	"first_person": KEY_V,
	"third_person": KEY_N,
	"third_aim_left": KEY_M,
	"third_aim_right": KEY_B,
	"zoom_in": KEY_O,
	"zoom_out": KEY_L,
	"fov_decrease": KEY_I,
	"fov_increase": KEY_K,
	"toggle_mouse_mode": KEY_Y,
	"options_menu": KEY_ESCAPE,
}


static func missing_actions(existing: PackedStringArray) -> PackedStringArray:
	var missing := PackedStringArray()
	for action: String in ACTIONS:
		if existing.has(action):
			continue
		missing.append(action)
	return missing
