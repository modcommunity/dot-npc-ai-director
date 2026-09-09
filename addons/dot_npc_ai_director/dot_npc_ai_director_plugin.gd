@tool
extends EditorPlugin

## Editor entry point for dot-npc-ai-director. Registers the director node only.
##
## No autoloads. A server running two maps in one process — which is what a game change
## is for one tick — holds two directors, each with its own population.

const _ICON := "res://addons/dot_npc_ai_director/icon_placeholder.svg"

const _TYPES := [
	[
		"DotNpcDirector",
		"Node",
		"res://addons/dot_npc_ai_director/runtime/dot_npc_director.gd",
	],
]


func _enter_tree() -> void:
	var icon: Texture2D = null
	if ResourceLoader.exists(_ICON):
		icon = load(_ICON) as Texture2D

	for entry in _TYPES:
		add_custom_type(entry[0], entry[1], load(entry[2]), icon)


func _exit_tree() -> void:
	for i in range(_TYPES.size() - 1, -1, -1):
		remove_custom_type(_TYPES[i][0])
