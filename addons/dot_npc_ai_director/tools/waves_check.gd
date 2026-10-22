extends SceneTree

## Loads every wave set of a game in every tier and prints each one's problems, for server owners and CI.
##
## [codeblock]
## godot --headless --path . --script res://addons/dot_npc_ai_director/tools/waves_check.gd -- --game=<game> [--roots=a,b] [--check-npcs]
## [/codeblock]
##
## Each set is built once per difficulty it names (and `normal`). Exit 1 if any set fails; a
## warning alone does not fail. [code]--check-npcs[/code] asks the game's `npc` profiles
## whether every id a wave names exists. The output ends with [code]WAVES_CHECK sets=N failed=M[/code].


func _init() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	var game := ""
	var roots := PackedStringArray()
	var check_npcs := false

	for a in OS.get_cmdline_user_args():
		if a.begins_with("--game="):
			game = a.substr(7)
		elif a.begins_with("--roots="):
			roots = PackedStringArray(a.substr(8).split(",", false))
		elif a == "--check-npcs":
			check_npcs = true

	var profiles := DotWaveSet.make_set(game, roots)
	var npcs := DotNpcProfiles.make_set(game, roots) if check_npcs else null
	var exists := Callable()

	if npcs != null:
		exists = func(npc_id: String) -> bool: return npcs.has_id(npc_id)

	var failed := 0
	var ids := profiles.list_ids()

	for id in ids:
		var loaded := profiles.load_profile(id)
		var names: Array = ["normal"]

		if loaded.ok:
			for d in loaded.value.get_value("difficulty", {}):
				if not names.has(str(d)):
					names.append(str(d))

		var bad := {}
		var warned := PackedStringArray()
		var lines := PackedStringArray()

		if not loaded.ok:
			bad[loaded.error.message] = names
		else:
			for d in names:
				var res := DotWaveSet.from_profile(loaded.value, d, exists)

				if not res.ok:
					bad[res.error.message] = bad.get(res.error.message, []) + [d]
				elif d == "normal":
					warned.append_array(res.value.warnings)
					lines = res.value.describe_lines()

		if bad.is_empty():
			print("ok    %s" % id)
			for w in warned:
				print("  warn  %s" % w)
			for l in lines:
				print("  %s" % l)
		else:
			failed += 1
			print("FAIL  %s" % id)
			for b in bad:
				print("  %s%s" % [b, "" if bad[b].size() == names.size() else "  (difficulty %s)" % ", ".join(PackedStringArray(bad[b]))])

	print("WAVES_CHECK sets=%d failed=%d" % [ids.size(), failed])
	quit(1 if failed > 0 else 0)
