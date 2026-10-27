extends Node

## Proves the skill estimate, difficulty multipliers and specials budget, and that all three are inert when off.
##
## [codeblock]
## godot --headless --path . res://examples/director_adapt_selftest.tscn
## [/codeblock]

const BODY := "res://fixtures/npc_body.tscn"

const CHECKS := 41
const SECTIONS := 7

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()
var _entered := 0
var _completed := 0

var _world: Node3D = null


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("dot-npc-ai-director adaptation self-test")
	_world = Node3D.new()
	add_child(_world)

	_test_skill()
	_test_team_pressure()
	_test_difficulty()
	_test_specials()
	_test_off_switch()
	_test_determinism()
	_test_stuck_rescue()

	print("")
	print("%d passed, %d failed" % [_passed, _failed])

	for line in _failures:
		print("  FAIL  %s" % line)

	print("%d of %d sections ran to their last line" % [_completed, _entered])
	if _entered != SECTIONS or _completed != _entered:
		print("ERROR: %d sections entered and %d completed, %d expected." % [_entered, _completed, SECTIONS])
		get_tree().quit(1)
		return
	if _passed + _failed != CHECKS:
		print("ERROR: %d checks ran, %d expected." % [_passed + _failed, CHECKS])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)


func _test_stuck_rescue() -> void:
	_section("stuck infected: repath, then relocate; progress and fights are not stuck")
	var r := DotNpcStuckRescue.new()
	_check(r.due(1, 0.0), "an unseen NPC is due at once")
	_check(r.observe(1, 40.0, 0.0) == DotNpcStuckRescue.NONE and not r.due(1, 0.5) and r.due(1, 1.0), "checks are spaced by the interval")
	var t := 0.0
	var seen := []
	while t < 14.0:
		t += 1.0
		var a := r.observe(1, 40.0, t)
		if a != DotNpcStuckRescue.NONE:
			seen.append([t, a])
	_check(seen.size() >= 2 and seen[0] == [6.0, DotNpcStuckRescue.REPATH], "no progress for 6 s: a repath first")
	_check(seen[1] == [14.0, DotNpcStuckRescue.RELOCATE], "then a relocation at 14 s")
	_check(r.repaths == 1 and r.relocations == 1, "the counts say so")
	var again := 0
	for i in 5:
		t += 1.0
		if r.observe(1, 40.0, t) != DotNpcStuckRescue.NONE:
			again += 1
	_check(again == 0, "relocating restarts the clock")
	var p := DotNpcStuckRescue.new()
	p.observe(2, 40.0, 0.0)
	var acted := false
	for i in 40:
		if p.observe(2, 40.0 - float(i) * 1.5, float(i + 1)) != DotNpcStuckRescue.NONE:
			acted = true
	_check(not acted, "closing in is progress")
	var f := DotNpcStuckRescue.new()
	f.observe(3, 2.0, 0.0)
	var fought := false
	for i in 30:
		if f.observe(3, 2.0, float(i + 1)) != DotNpcStuckRescue.NONE:
			fought = true
	_check(not fought, "within reach of a survivor is a fight, not a stall")
	var low := DotNpcStuckRescue.new()
	low.observe(4, 50.0, 0.0)
	var first := -1.0
	for i in 20:
		if low.observe(4, 50.0, float(i + 1), 3) == DotNpcStuckRescue.REPATH:
			first = float(i + 1)
			break
	_check(first > 0.0 and first <= 2.5, "with few left the waits shrink to a third (repath at %.0f s)" % first)
	var wander := DotNpcStuckRescue.new()
	wander.observe(5, 40.0, 0.0)
	var circled := false
	for i in 12:
		if wander.observe(5, 40.0 + float(i % 2) * 3.0, float(i + 1)) == DotNpcStuckRescue.REPATH:
			circled = true
	_check(circled, "moving without getting closer still counts as stuck")
	r.forget(1)
	_check(r.due(1, 99.0) and r.describe()["tracked"] == 0, "forgotten NPCs are gone")
	var gone := DotNpcStuckRescue.new()
	gone.observe(6, 30.0, 0.0)
	gone.clear()
	_check(gone.describe()["tracked"] == 0, "clear empties it")
	_check(r.describe()["relocations"] == 1, "describe reports the totals")
	_done()


func _section(title: String) -> void:
	_entered += 1
	print(title)


func _done() -> void:
	_completed += 1


func _check(ok: bool, what: String, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    %s" % what)
	else:
		_failed += 1
		_failures.append(what if detail == "" else "%s (%s)" % [what, detail])
		print("  FAIL  %s" % _failures[-1])


func _spawner() -> DotNpcSpawner:
	var cat := DotNpcCatalogue.new()
	for id in [&"zombie", &"brute"]:
		var def := DotNpcDef.make(id, BODY)
		def.require_line_of_sight = false
		cat.add(def)

	var spawner := DotNpcSpawner.new()
	spawner.catalogue = cat
	var limits := DotNpcLimits.new()
	limits.spawn_interval = 0.0
	limits.require_navigable_spawn = false
	limits.world_budget = 0
	limits.per_kind_cap = 0
	limits.reclaim_distance = 0.0
	spawner.limits = limits
	spawner.authoritative = true
	_world.add_child(spawner)
	return spawner


func _rules() -> DotNpcDirectorRules:
	var rules := DotNpcDirectorRules.new()
	rules.spawn_out_of_sight = false
	rules.spawn_interval = 0.0
	rules.peak_stress = 0.3
	rules.sustain_seconds = 100000.0
	rules.skill_warmup_seconds = 60.0
	rules.skill_smoothing = 0.3
	return rules


func _director(rules: DotNpcDirectorRules, population: Array[StringName] = [&"zombie"]) -> DotNpcDirector:
	var director := DotNpcDirector.new()
	director.spawner = _spawner()
	director.rules = rules
	director.population = population
	var points := PackedVector3Array()
	for i in 41:
		points.append(Vector3(0, 0, -5.0 * float(i)))
	director.spawn_points = points
	_world.add_child(director)
	return director


func _drop(director: DotNpcDirector) -> void:
	director.spawner.queue_free()
	director.queue_free()


## One player for [param seconds]; every 6 s they lose [param loss] of their health and recover.
func _play(director: DotNpcDirector, seconds: float, loss: float, deaths_per_minute: float = 0.0) -> Array[float]:
	var seen: Array[float] = []
	var t := 0.0
	var next_death := 0.0
	while t < seconds:
		var phase := fmod(t, 6.0)
		var health := 1.0 - loss if phase < 0.1 + 0.0001 and t >= 6.0 else 1.0
		if loss > 0.0 and t < 0.1:
			health = 1.0 - 0.5
		director.report_player(&"p", Vector3.ZERO, health)
		if deaths_per_minute > 0.0 and t >= next_death:
			director.report_death(&"p")
			next_death += 60.0 / deaths_per_minute
		director.tick(0.1)
		seen.append(director.skill_multiplier(&"p"))
		t += 0.1
	return seen


func _test_skill() -> void:
	_section("skill estimate")

	var rules := _rules()
	rules.skill_enabled = true
	var weak := _director(rules)
	var seen := _play(weak, 5.0, 0.4)
	_check(seen[0] == 1.0 and seen[seen.size() - 1] == 1.0,
		"a new player reads 1.0 before the first sample", "%.3f after 5 s" % seen[seen.size() - 1])
	seen = _play(weak, 20.0, 0.4)
	_check(seen[seen.size() - 1] > 0.9, "and the estimate moves slowly", "%.3f after 25 s" % seen[seen.size() - 1])
	seen = _play(weak, 600.0, 0.4)
	var low := seen[seen.size() - 1]
	_check(low < 0.75 and low >= rules.skill_min, "a struggling player converges to the lower bound", "%.3f" % low)
	_check(seen.min() >= rules.skill_min and seen.max() <= rules.skill_max, "and never leaves the bounds")

	var strong := _director(rules)
	seen = _play(strong, 600.0, 0.0)
	var high := seen[seen.size() - 1]
	_check(high > 1.25 and high <= rules.skill_max, "a player who is never hurt converges to the upper bound", "%.3f" % high)

	var dying := _director(rules)
	seen = _play(dying, 600.0, 0.0, 6.0)
	_check(seen[seen.size() - 1] < 1.0, "deaths alone pull the estimate down", "%.3f" % seen[seen.size() - 1])
	_check(strong.skill_multiplier(&"nobody") == 1.0, "an unknown player reads 1.0")
	for d in [weak, strong, dying]:
		_drop(d)
	_done()


func _test_team_pressure() -> void:
	_section("team pressure")

	var rules := _rules()
	rules.skill_enabled = true
	var struggling := _director(rules)
	var dominating := _director(rules)
	_play(struggling, 600.0, 0.4)
	_play(dominating, 600.0, 0.0)
	struggling.report_player(&"p", Vector3.ZERO, 1.0)
	dominating.report_player(&"p", Vector3.ZERO, 1.0)
	var base := int(round(rules.peak_per_player))
	var s := _peak_population(struggling)
	var d := _peak_population(dominating)
	_check(s < base, "a struggling team gets a smaller peak than the rules say", "%d against %d" % [s, base])
	_check(d > base, "a dominating team gets a larger one", "%d against %d" % [d, base])
	_check(s < d, "and the two are ordered")
	for x in [struggling, dominating]:
		_drop(x)
	_done()


## The population the director would want at a sustained peak.
func _peak_population(director: DotNpcDirector) -> int:
	director._phase = DotNpcDirector.Phase.SUSTAIN
	return director.target_population()


func _test_difficulty() -> void:
	_section("difficulty")

	var rules := DotNpcDirectorRules.new()
	_check(DotNpcDirectorDifficulty.accuracy(rules) == 1.0 and DotNpcDirectorDifficulty.damage(rules) == 1.0,
		"off by default, both multipliers read 1.0")
	rules.difficulty_enabled = true
	var seen: Array[float] = []
	for name in ["easy", "normal", "hard", "nightmare"]:
		rules.difficulty_preset = name
		seen.append(DotNpcDirectorDifficulty.accuracy(rules))
	_check(seen[1] == 1.0 and seen[0] < seen[1] and seen[1] < seen[2] and seen[2] < seen[3],
		"presets rise easy, normal, hard, nightmare, and normal is 1.0", str(seen))
	rules.difficulty_preset = "hard"
	_check(is_equal_approx(DotNpcDirectorDifficulty.accuracy(rules), 1.125)
		and is_equal_approx(DotNpcDirectorDifficulty.damage(rules), 1.15), "hard maps to 1.125 accuracy and 1.15 damage")
	rules.difficulty_dial = 2.0
	_check(is_equal_approx(DotNpcDirectorDifficulty.accuracy(rules), 1.25), "a numeric dial overrides the preset")
	rules.difficulty_dial = 0.0
	_check(DotNpcDirectorDifficulty.accuracy(rules) < 1.0 and DotNpcDirectorDifficulty.accuracy(rules) >= 0.1,
		"a dial of zero is a floor, not zero")
	rules.difficulty_dial = -1.0
	rules.difficulty_preset = "bogus"
	_check(not rules.validate().ok, "an unknown preset is refused")
	var configured := DotNpcDirectorRules.new()
	configured.apply_dictionary({"difficulty_enabled": true, "difficulty_preset": "easy"})
	_check(DotNpcDirectorDifficulty.accuracy(configured) < 1.0, "and it is set from a config dictionary")
	_done()


func _test_specials() -> void:
	_section("specials budget")

	var population: Array[StringName] = [&"zombie", &"brute", &"brute", &"brute"]
	var rules := _rules()
	rules.peak_stress = 100.0
	rules.build_up_per_player = 40.0
	rules.absolute_cap = 60
	rules.spawn_burst = 10
	rules.specials_enabled = true
	rules.special_kinds = [&"brute"]
	rules.special_cooldown_seconds = 30.0
	rules.special_budget_cap = 2
	rules.special_max_alive = 0
	var limited := _director(rules, population)
	_ready_director(limited)
	_play(limited, 10.0, 0.0)
	var brutes := limited.spawner.count_of(&"brute")
	_check(brutes == 2, "the first two specials come at once, then the budget is empty", "%d" % brutes)
	_check(limited.spawner.count_of(&"zombie") > 5, "ordinary kinds fill the rest")
	_play(limited, 25.0, 0.0)
	for npc in limited.spawner.all_npcs():
		if npc.def.id == &"zombie":
			limited.spawner.remove(npc.instance_id, DotNpcSpawner.REASON_RECLAIMED)
	_play(limited, 1.0, 0.0)
	brutes = limited.spawner.count_of(&"brute")
	_check(brutes == 3, "one more is earned per cooldown", "%d after 36 s" % brutes)

	var capped_rules := rules.clone() as DotNpcDirectorRules
	capped_rules.special_budget_cap = 20
	capped_rules.special_max_alive = 1
	var capped := _director(capped_rules, population)
	_ready_director(capped)
	_play(capped, 10.0, 0.0)
	_check(capped.spawner.count_of(&"brute") == 1, "special_max_alive limits specials standing at once")

	var free_rules := rules.clone() as DotNpcDirectorRules
	free_rules.specials_enabled = false
	var free := _director(free_rules, population)
	_ready_director(free)
	_play(free, 10.0, 0.0)
	_check(free.spawner.count_of(&"brute") > 10, "with the budget off the population is unlimited",
		"%d" % free.spawner.count_of(&"brute"))
	for x in [limited, capped, free]:
		_drop(x)
	_done()


func _ready_director(director: DotNpcDirector) -> void:
	director._specials.reset(director.rules)


## Everything the director produces over a fixed history, as one string.
func _trace(rules: DotNpcDirectorRules) -> String:
	var population: Array[StringName] = [&"zombie", &"brute"]
	var director := _director(rules, population)
	_ready_director(director)
	var out := ""
	var seen := _play(director, 120.0, 0.3, 1.0)
	out += "%.6f %.6f " % [seen[seen.size() - 1], director.stress()]
	out += "%d %d %d %.3f %.3f" % [
		director.target_population(), director.spawn_count, director.spawner.world_count(),
		director.enemy_accuracy_multiplier(), director.enemy_damage_multiplier()
	]
	_drop(director)
	return out


func _test_off_switch() -> void:
	_section("off switch")

	var plain := _rules()
	var tweaked := _rules()
	tweaked.skill_min = 0.5
	tweaked.skill_max = 2.0
	tweaked.difficulty_preset = "nightmare"
	tweaked.difficulty_dial = 3.0
	tweaked.special_kinds = [&"brute"]
	tweaked.special_budget_cap = 1
	_check(not tweaked.skill_enabled and not tweaked.difficulty_enabled and not tweaked.specials_enabled,
		"all three are off by default")
	var a := _trace(plain)
	var b := _trace(tweaked)
	_check(a == b, "their settings change nothing while off", "%s | %s" % [a, b])
	var on := _rules()
	on.skill_enabled = true
	_check(_trace(on) != a, "and turning one on does change the outcome")
	_done()


func _test_determinism() -> void:
	_section("determinism")

	var rules := _rules()
	rules.skill_enabled = true
	rules.difficulty_enabled = true
	rules.difficulty_preset = "hard"
	rules.specials_enabled = true
	rules.special_kinds = [&"brute"]
	var first := _trace(rules)
	var second := _trace(rules.clone() as DotNpcDirectorRules)
	_check(first == second, "the same history gives the same result twice", "%s | %s" % [first, second])

	var director := _director(rules)
	_play(director, 5.0, 0.0)
	var d := director.describe()
	_check(d.has("skill") and d.has("difficulty") and d.has("specials"), "describe reports all three")
	_check("\n".join(director.describe_lines()).contains("difficulty"), "describe_lines reports the difficulty")
	_drop(director)
	_done()
