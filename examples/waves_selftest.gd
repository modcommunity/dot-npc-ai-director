extends Node

## Proves wave sets: parse, ranges, `last`, tiers and extends, extra passthrough, refused input, determinism, the map-progress signal and the hookup to the director's rules.
##
## [codeblock]
## godot --headless --path . res://examples/waves_selftest.tscn
## [/codeblock]

const CHECKS := 60
const SECTIONS := 9
const GOOD := ["res://cfg", "res://fixtures/cfg"]
const SERVER := ["res://cfg", "res://fixtures/cfg", "res://fixtures/cfg_server"]
const BAD := ["res://cfg", "res://fixtures/cfg_bad"]

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()
var _entered := 0
var _completed := 0



func _ready() -> void:
	DotLog.set_level(DotLog.Level.FATAL)
	_run.call_deferred()


func _run() -> void:
	print("dot-npc-ai-director waves self-test")
	_test_parse()
	_test_ranges()
	_test_last()
	_test_tiers()
	_test_extra()
	_test_refused()
	_test_determinism()
	_test_map_progress()
	_test_director_hookup()

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


func _load(id: String, roots: Array = GOOD, difficulty := "normal", cmdline: Array = [], npc_exists := Callable(), validate_extra := Callable()) -> DotResult:
	var profiles := DotWaveSet.make_set("testgame", PackedStringArray(roots), PackedStringArray(cmdline))
	return DotWaveSet.load_set(profiles, id, difficulty, npc_exists, validate_extra)


func _wset(id: String, roots: Array = GOOD, difficulty := "normal", cmdline: Array = []) -> DotWaveSet:
	var res := _load(id, roots, difficulty, cmdline)
	if not res.ok:
		print("  load of %s failed: %s" % [id, res.error.message])
		return DotWaveSet.new()
	return res.value


func _test_parse() -> void:
	_section("parse")
	var s := _wset("school_hold")
	_check(s.id == "school_hold" and s.count == 10 and s.style == DotNpcDirectorWaves.Style.ROUNDS, "the game's set loads with its count and style")
	_check(s.pool == {"common": 10.0, "tg_common": 10.0, "tg_crawler": 2.0}, "the pool merges over the hold set it extends", str(s.pool))
	_check(s.chain == PackedStringArray(["school_hold", "hold"]), "the extends chain is kept", str(s.chain))
	_check(s.sources.size() == 2, "each layer's source is listed", str(s.sources))

	var hold := _wset("hold")
	var plain := DotNpcDirectorWaves.new()
	var same := true
	for players in [1, 2, 4]:
		for k in range(1, 11):
			same = same and hold.resolve(k, players).size == plain.wave_size(k, players)
	_check(same, "the neutral hold reproduces the schedule's own sizes for 1, 2 and 4 players, waves 1 to 10")
	_check(hold.release_base == plain.release_base and hold.overtime_seconds == plain.overtime_seconds and hold.first_quiet == plain.first_quiet_seconds and hold.growth_accel == plain.growth_accel, "and its release, overtime, quiet and growth numbers")
	_check(hold.alive_cap(3) == 36, "alive cap is base plus per player", str(hold.alive_cap(3)))

	var res := DotNpcDirectorWaves.from_profile(DotWaveSet.make_set("testgame", PackedStringArray(GOOD)).load_profile("school_hold").value, "normal", 3)
	_check(res.ok and res.value.wave_set != null and res.value.players == 3, "from_profile returns a schedule bound to its set")
	_done()


func _test_ranges() -> void:
	_section("ranges")
	var s := _wset("school_hold")
	_check(s.resolve(5, 1).specials.is_empty(), "wave 5 is outside the range 6-9 and gets no specials")
	var hit := true
	for k in [6, 7, 8, 9]:
		hit = hit and s.resolve(k, 1).specials == {"tg_spitter": 1, "tg_strangler": 1}
	_check(hit, "every wave from 6 to 9 gets the range's specials")
	_check(s.resolve(10, 1).specials.is_empty(), "wave 10 does not")
	_check(s.resolve(7, 1).extra == {"tg": {"twists": true, "breather": "patch_up", "fog": true}}, "a range's extra deep-merges over the set's", str(s.resolve(7, 1).extra))
	var w8 := s.resolve(8, 1)
	_check(w8.size == 40 and w8.specials.has("tg_spitter"), "a number applies over the range that covers it and keeps the range's other keys", str(w8.to_dictionary()))
	_check(w8.pool.get("tg_rider") == 2.0 and w8.pool.get("tg_common") == 10.0, "'+id' adds to the pool instead of replacing it", str(w8.pool))
	_check(s.resolve(3, 1).pool == {"tg_common": 8.0, "tg_crawler": 3.0, "tg_sprinter": 2.0}, "a plain pool replaces the set's", str(s.resolve(3, 1).pool))
	_check(s.resolve(2, 1).size == DotNpcDirectorWaves.new().wave_size(2, 1) and s.resolve(2, 4).size > s.resolve(2, 1).size, "a wave with no entry comes from the formula and grows with players")
	_check(s.resolve(1, 1).release == 1.0 and s.quiet_of(1) == 5.0 and s.quiet_of(2) == -1.0, "per-wave release and quiet are carried; others inherit")
	_done()


func _test_last() -> void:
	_section("last")
	var s := _wset("school_hold")
	var l := s.resolve(10, 2)
	_check(l.is_last and l.boss == {"npc": "tg_brute", "count": 2, "at": 0.33}, "'last' is the final wave and carries its boss", str(l.boss))
	_check(l.pool == {"tg_common": 6.0, "tg_rider": 2.0}, "and replaces the pool", str(l.pool))
	_check(l.specials.is_empty(), "and a range that stops at wave 9 does not reach it")
	_check(not s.resolve(9, 1).is_last and s.resolve(9, 1).boss.is_empty(), "wave 9 is not last and has no boss")
	_check(s.resolve(5, 1).boss.get("count") == 1 and s.resolve(5, 1).reward == {"restock": "tier2", "cash": 0}, "a numbered boss and its opaque reward pass through", str(s.resolve(5, 1).reward))
	var longer := _wset("school_hold", GOOD, "normal", ["--profile.waves/school_hold.count=12"])
	_check(longer.resolve(12, 1).boss.get("count") == 2 and longer.resolve(10, 1).boss.is_empty(), "'last' follows the count when the count is overridden")
	var clock := _wset("endless")
	_check(clock.last_index() == 1 and clock.resolve(1, 1).is_last and clock.resolve(1, 1).announce != "", "a clock set has one wave, which is the last")
	var nights := _wset("nights")
	_check(nights.resolve(2, 1).health_mult == 1.5 and nights.resolve(3, 1).announce == "The last night." and nights.resolve(1, 1).size == 0, "a cycle set reads 'nights:' the same way and has no head count")
	_done()


func _test_tiers() -> void:
	_section("extends and tiers")
	var s := _wset("school_hold", SERVER)
	_check(s.count == 12 and s.quiet == 20.0, "the server tier overrides a few keys of the game's set", "%d %f" % [s.count, s.quiet])
	_check(s.resolve(2, 1).size == 99 and s.resolve(2, 1).pool == {"tg_common": 5.0}, "and wave 2 only, by number, without restating the others")
	_check(s.resolve(7, 1).specials == {"tg_spitter": 3, "tg_strangler": 1}, "a server range changes one of the game's specials for those waves and keeps the other", str(s.resolve(7, 1).specials))
	_check(s.resolve(3, 1).pool.has("tg_sprinter") and s.resolve(12, 1).is_last, "untouched entries survive and 'last' moved to the new count")
	_check(s.sources.size() == 3 and s.describe_lines().size() >= 4, "describe_lines lists each layer", str(s.sources))
	var o := _wset("school_hold", GOOD, "normal", ["--profile.waves/school_hold.quiet=7", "--profile.waves/school_hold.waves=oops"])
	_check(o.quiet == 7.0 and o.overrides.size() == 1, "a command-line scalar overrides, and entries cannot be overridden that way", str(o.overrides))
	_done()


func _test_extra() -> void:
	_section("extra passthrough and hooks")
	var s := _wset("school_hold")
	_check(s.extra == {"tg": {"twists": true, "breather": "patch_up"}}, "extra reaches the set untouched", str(s.extra))
	s.wave_resolved = func(spec: DotWaveSpec) -> DotWaveSpec:
		if spec.extra.get("tg", {}).get("twists", false):
			spec.announce = "twist %d" % spec.index
			spec.size += 1
		return spec
	var plain := _wset("school_hold").resolve(4, 1)
	var hooked := s.resolve(4, 1)
	_check(hooked.announce == "twist 4" and hooked.size == plain.size + 1, "wave_resolved can adjust a wave from extra")
	s.wave_resolved = func(_spec: DotWaveSpec): return null
	_check(s.resolve(4, 1).size == plain.size, "a hook that returns nothing keeps the resolved wave")

	var check := func(e: Dictionary) -> DotResult:
		for k in e.get("tg", {}):
			if not ["twists", "breather", "fog"].has(k):
				return DotResult.fail(DotError.CODE_INVALID, "extra.tg: unknown key '%s'" % k)
		return DotResult.success(null)
	_check(_load("school_hold", GOOD, "normal", [], Callable(), check).ok, "validate_extra accepts the game's own keys, in the set and in an entry")
	var bad := _load("extra_typo", BAD, "normal", [], Callable(), check)
	_check(not bad.ok and bad.error.code == DotError.CODE_INVALID and "twistz" in bad.error.message, "and refuses a typo with CODE_INVALID", bad.error.message if not bad.ok else "")
	_done()


func _test_refused() -> void:
	_section("bad input refused")
	var expect := {
		"unknown_key": "unknown key 'bogus'", "bad_style": "not one of", "count_zero": "below min",
		"sub_unknown": "unknown key 'color'", "sub_range": "outside", "empty_pool": "wave 1 pool",
		"neg_weight": "weight", "boss_at": "expected 0..1", "boss_npc": "needs an npc",
		"entry_key": "a key is a number", "entry_unknown": "sizee", "range_back": "range runs upward",
		"nights_on_rounds": "takes 'waves:'", "waves_on_cycle": "takes 'nights:'",
		"bad_difficulty_mult": "difficulty.hard.size", "director_key": "skil", "cycle_no_length": "night needs a length",
		"wave_pool_zero": "wave 4 pool", "bad_parent": "nowhere",
	}
	var exists := func(id: String) -> bool: return id != "ghost"
	var all_ok := true
	for id in expect:
		var res := _load(id, BAD)
		var good: bool = not res.ok and expect[id] in res.error.message
		if not good:
			print("    %s -> %s" % [id, res.error.message if not res.ok else "loaded"])
		all_ok = all_ok and good
	_check(all_ok, "each of %d malformed sets is refused with its reason" % expect.size())
	var missing := _load("npc_missing", BAD, "normal", [], exists)
	_check(not missing.ok and "no NPC 'ghost' (wave 2)" in missing.error.message, "an NPC id the injected check does not know is refused", missing.error.message if not missing.ok else "")
	var multi := _load("multi", BAD)
	_check(not multi.ok and "skil" in multi.error.message and "sizee" in multi.error.message and "expected 0..1" in multi.error.message, "every problem is reported together, not the first", multi.error.message if not multi.ok else "")
	_check(not _load("school_hold", GOOD, "brutal").ok, "a difficulty the set does not name is refused")
	var past := _load("past_count", BAD)
	_check(past.ok and past.value.warnings.size() == 2, "an entry past the count is a warning, not an error", str(past.value.warnings) if past.ok else past.error.message)
	_check(_load("past_count", BAD, "normal", [], Callable(), Callable()).ok and not _load("nope", GOOD).ok, "and a missing set is a refusal, not a crash")
	_done()


func _drive(id: String, count: int) -> Array:
	var profiles := DotWaveSet.make_set("testgame", PackedStringArray(GOOD), PackedStringArray(["--profile.waves/%s.count=%d" % [id, count]]))
	var res := DotNpcDirectorWaves.from_profile(profiles.load_profile(id).value, "normal", 2, {"map_key": "m1"})
	var sched: DotNpcDirectorWaves = res.value
	var log: Array = []
	sched.wave_started.connect(func(spec: DotWaveSpec): log.append("%d:%d:%s" % [spec.index, spec.size, ",".join(PackedStringArray(spec.pool.keys()))]))
	sched.finished.connect(func(): log.append("finished"))
	sched.begin(2)
	var alive := 0
	for i in 4000:
		alive += sched.take(100)
		if sched.stage == DotNpcDirectorWaves.Stage.HORDE and sched.sent >= sched.budget:
			alive = 0
		sched.tick(0.5, alive, 2)
		if sched.stage == DotNpcDirectorWaves.Stage.DONE:
			break
	log.append(sched.wave_set.reached.duplicate())
	return log


func _test_determinism() -> void:
	_section("deterministic resolution")
	var a := _wset("school_hold")
	var b := _wset("school_hold")
	var same := true
	for k in range(1, 11):
		same = same and a.resolve(k, 3).to_dictionary() == b.resolve(k, 3).to_dictionary() and a.resolve(k, 3).to_dictionary() == a.resolve(k, 3).to_dictionary()
	_check(same, "the same files and the same (wave, players) give the same spec every time")
	var run1 := _drive("school_hold", 3)
	var run2 := _drive("school_hold", 3)
	_check(run1 == run2, "a whole run of the schedule is reproducible", str(run1))
	_check(run1.size() == 5 and run1[0].begins_with("1:") and run1[3] == "finished", "three waves start in order and then it finishes", str(run1))
	_check(run1[1].begins_with("2:") and int(run1[1].split(":")[1]) == DotNpcDirectorWaves.new().wave_size(2, 2), "the schedule sizes a wave from the set", run1[1])
	_check(run1[0].ends_with("tg_common") and not run1[2].ends_with("tg_common"), "wave 1 uses its own pool and the last wave its own", str(run1))
	var hard := _wset("school_hold", GOOD, "hard")
	var easy := _wset("school_hold", GOOD, "easy")
	var n := _wset("school_hold")
	_check(easy.resolve(2, 2).size < n.resolve(2, 2).size and n.resolve(2, 2).size < hard.resolve(2, 2).size, "difficulty scales the head count", "%d %d %d" % [easy.resolve(2, 2).size, n.resolve(2, 2).size, hard.resolve(2, 2).size])
	_check(hard.resolve(2, 2).health_mult == 1.2 and hard.resolve(2, 2).speed_mult == 1.1 and hard.resolve(2, 2).reward_mult == 0.9 and hard.resolve(2, 2).pool == n.resolve(2, 2).pool, "and health, speed and reward but never the pool")
	_done()


func _test_map_progress() -> void:
	_section("map-cycle progress signal")
	var profiles := DotWaveSet.make_set("testgame", PackedStringArray(GOOD), PackedStringArray(["--profile.waves/school_hold.count=2"]))
	var seen: Array = []
	var res := DotNpcDirectorWaves.from_profile(profiles.load_profile("school_hold").value, "normal", 1, {"map_key": "school"})
	var sched: DotNpcDirectorWaves = res.value
	sched.wave_set.progress.connect(func(key: String, wave: int, count: int, done: bool): seen.append([key, wave, count, done]))
	sched.begin(1)
	for i in 4000:
		var got := sched.take(100)
		sched.tick(0.5, 0 if sched.sent >= sched.budget else got, 1)
		if sched.stage == DotNpcDirectorWaves.Stage.DONE:
			break
	_check(seen == [["school", 1, 2, false], ["school", 2, 2, false], ["school", 2, 2, true]], "wave starts and the finish are signalled with the map key", str(seen))
	_check(sched.wave_set.progress_of("school") == 1.0 and sched.wave_set.progress_of("mall") == 0.0, "progress is kept per map key")
	sched.wave_set.map_key = "mall"
	sched.wave_set.report_progress(1, false)
	_check(sched.wave_set.progress_of("mall") == 0.5 and seen.back()[0] == "mall", "a game moving to the next map names it and keeps the old map's progress")
	_check(sched.wave_set.map_key == "mall" and sched.wave_set.progress_of("school") == 1.0, "without the set knowing what a map is")
	_done()


func _test_director_hookup() -> void:
	_section("hookup to the director's rules")
	var s := _wset("school_hold", GOOD, "hard")
	var rules := DotNpcDirectorRules.new()
	_check(not _wset("hold").apply_to_rules(rules) and not rules.skill_enabled and not rules.specials_enabled, "a pure schedule leaves the rules alone")
	_check(s.apply_to_rules(rules) and rules.skill_enabled and rules.specials_enabled and rules.special_budget_cap == 2, "director: switches on skill and sets the specials budget")
	_check(rules.difficulty_enabled and rules.difficulty_preset == "hard" and DotNpcDirectorDifficulty.dial_of(rules) == 1.5, "the difficulty name feeds the existing preset")
	_check(s.skilled_size(20, 5.0, rules) == 26 and s.skilled_size(20, 0.1, rules) == 14 and s.skilled_size(20, 1.0, rules) == 20, "skill moves a fixed wave only within skill_min..skill_max (20 stays 14 to 26)")
	var spec := s.resolve(7, 1)
	_check(DotWaveSet.specials_within_budget(spec, 1.4) == {"tg_spitter": 1} and DotWaveSet.specials_within_budget(spec, 0.9).is_empty() and DotWaveSet.specials_within_budget(spec, 5.0).size() == 2, "a wave's specials are what the budget allows, not more", str(DotWaveSet.specials_within_budget(spec, 1.4)))
	var off := _wset("school_hold")
	off.director = {"skill": false}
	_check(off.skilled_size(20, 1.3, rules) == 20, "'skill: false' makes fixed sizes exact")
	_check(s.describe().get("difficulty") == "hard" and s.describe_lines()[0].begins_with("wave set"), "describe and describe_lines say what is loaded")
	_done()
