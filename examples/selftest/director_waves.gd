extends "res://examples/director_selftest_base.gd"

## The director self-test's hold-out sections: waves by rounds, by days and nights and by
## the clock, and authored spawn sites. Run from [code]director_selftest.gd[/code].


## Ten waves, each bigger than the last, a breather between, cleared by killing them.
func _test_waves_rounds() -> void:
	_section("waves: rounds")

	var w := DotNpcDirectorWaves.new()
	w.count = 3
	w.first_quiet_seconds = 5.0
	w.quiet_seconds = 10.0
	w.wave_base = 10
	w.wave_per_player = 2
	_check(w.validate().ok, "a schedule of three waves is usable")

	var stages: Array = []
	w.stage_changed.connect(func(stage: int, index: int) -> void: stages.append([stage, index]))
	var done := [false]
	w.finished.connect(func() -> void: done[0] = true)

	w.begin(4)
	_check(w.stage == DotNpcDirectorWaves.Stage.QUIET and w.index == 1 and absf(w.seconds_left() - 5.0) < 0.01,
		"it opens with the first quiet, for the wave that follows it", "%s %d %.1f" % [w.stage_name(), w.index, w.seconds_left()])

	_run_waves(w, 5.1, 0)
	_check(w.stage == DotNpcDirectorWaves.Stage.HORDE and w.budget == 16,
		"then wave 1, sized for the team", "%s budget %d" % [w.stage_name(), w.budget])

	# Released over time, never all at once, and never more than the game has room for.
	var first := w.take(100)
	_run_waves(w, 1.0, first)
	var second := w.take(3)
	_check(first == 0 and second > 0 and second <= 3, "a wave is released over time and within the room given",
		"%d then %d" % [first, second])

	# Release the rest, kill all but one: the wave is not over while one is alive.
	var out := second
	for i in 200:
		var _n := w.take(100)
		out += _n
		w.tick(0.1, out, 4)
	_check(w.sent == w.budget and w.stage == DotNpcDirectorWaves.Stage.HORDE, "a released wave with the living is still on",
		"%d of %d sent" % [w.sent, w.budget])
	w.tick(0.1, 1, 4)
	_check(w.stage == DotNpcDirectorWaves.Stage.HORDE and w.remaining() == 1, "and one left alive holds it open", str(w.remaining()))
	w.tick(0.1, 0, 4)
	_check(w.stage == DotNpcDirectorWaves.Stage.QUIET and w.index == 2 and absf(w.seconds_left() - 10.0) < 0.2,
		"killing the last one starts the breather before wave 2", "%s %d %.1f" % [w.stage_name(), w.index, w.seconds_left()])

	var sizes: Array = []
	for k in range(1, 11):
		sizes.append(w.wave_size(k, 4))
	var rising := true
	for k in range(1, sizes.size()):
		rising = rising and int(sizes[k]) > int(sizes[k - 1])
	_check(rising and int(sizes[9]) >= int(sizes[0]) * 3, "each wave is bigger than the last, and the tenth a wall", str(sizes))
	_check(w.wave_size(1, 12) > w.wave_size(1, 4), "and a bigger team gets a bigger wave")

	# A straggler nobody can reach does not hold the breather off for ever.
	_run_waves(w, 10.1, 0)
	w.straggler_seconds = 5.0
	var released_at := -1.0
	var t := 0.0
	for i in 200:
		var _n := w.take(100)
		w.tick(0.1, 1, 4)
		t += 0.1
		if released_at < 0.0 and w.sent >= w.budget:
			released_at = t
		if w.stage != DotNpcDirectorWaves.Stage.HORDE:
			break
	_check(w.stage == DotNpcDirectorWaves.Stage.QUIET and w.overtime and t - released_at < 6.0,
		"a wave down to a straggler or two ends soon after its last release, and says so", "%.1f s after" % (t - released_at))

	# Wave 3, the last: clearing it finishes the hold.
	_run_waves(w, 10.1, 0)
	for i in 200:
		var _n := w.take(100)
		w.tick(0.1, 0, 4)
	_check(w.stage == DotNpcDirectorWaves.Stage.DONE and done[0], "clearing the last wave finishes the hold", w.stage_name())
	_check(stages.size() == 7, "and every stage was announced: three quiets, three waves, done", str(stages))
	_done()


## Days and nights: a night is survived, not cleared, and the light follows.
func _test_waves_cycle() -> void:
	_section("waves: days and nights")

	var w := DotNpcDirectorWaves.new()
	w.style = DotNpcDirectorWaves.Style.CYCLE
	w.count = 2
	w.first_quiet_seconds = 20.0
	w.quiet_seconds = 20.0
	w.horde_seconds = 30.0
	w.twilight_seconds = 5.0
	_check(w.validate().ok, "two nights are a usable schedule")
	w.begin(2)
	_check(w.daylight() == 0.0, "it is dark at the first moment of the first day")
	_run_waves(w, 10.0, 0)
	_check(is_equal_approx(w.daylight(), 1.0), "full day in its middle", "%.2f" % w.daylight())
	_run_waves(w, 10.1, 0)
	_check(w.stage == DotNpcDirectorWaves.Stage.HORDE and w.daylight() == 0.0 and absf(w.seconds_left() - 29.9) < 0.3,
		"then night 1, dark, with its clock", "%.1f left" % w.seconds_left())
	_check(w.take(50) == 0 and w.remaining() == -1, "a night is not a count to release")
	_run_waves(w, 30.1, 99)
	_check(w.stage == DotNpcDirectorWaves.Stage.QUIET and w.index == 2, "a night ends at dawn however many are left")
	_run_waves(w, 20.1, 0)
	_check(w.strength() > 1.0, "and the second night is harder than the first", "%.2f" % w.strength())
	_run_waves(w, 30.1, 0)
	_check(w.stage == DotNpcDirectorWaves.Stage.DONE and w.daylight() == 1.0, "surviving the last night is the end, and it is morning")
	_done()


## One clock, harder as it runs; 0 seconds runs for ever.
func _test_waves_clock() -> void:
	_section("waves: the clock")

	var w := DotNpcDirectorWaves.new()
	w.style = DotNpcDirectorWaves.Style.CLOCK
	w.first_quiet_seconds = 0.0
	w.horde_seconds = 60.0
	w.begin(1)
	_check(w.stage == DotNpcDirectorWaves.Stage.HORDE and w.daylight() == -1.0,
		"no opening quiet starts the clock at once, in the map's own light")
	var early := w.strength()
	_run_waves(w, 50.0, 0)
	_check(w.strength() > early and absf(w.seconds_left() - 10.0) < 0.2, "it grows harder as it runs",
		"%.2f then %.2f" % [early, w.strength()])
	_run_waves(w, 10.1, 0)
	_check(w.stage == DotNpcDirectorWaves.Stage.DONE, "and is held when it runs out")

	var endless := DotNpcDirectorWaves.new()
	endless.style = DotNpcDirectorWaves.Style.CLOCK
	endless.first_quiet_seconds = 0.0
	endless.horde_seconds = 0.0
	endless.begin(1)
	_run_waves(endless, 3600.0, 0)
	_check(endless.stage == DotNpcDirectorWaves.Stage.HORDE and endless.seconds_left() == -1.0,
		"a clock of 0 never ends: it is held as long as somebody lasts")
	_check(DotNpcDirectorWaves.style_from("nights") == DotNpcDirectorWaves.Style.CYCLE
		and DotNpcDirectorWaves.style_from("waves") == DotNpcDirectorWaves.Style.ROUNDS
		and DotNpcDirectorWaves.style_from("nonsense") == -1, "a style is read from its name")
	_done()


func _run_waves(w: DotNpcDirectorWaves, seconds: float, alive: int) -> void:
	var t := 0.0
	while t < seconds - 0.0001:
		w.tick(0.1, alive, w.players)
		t += 0.1


func _test_authored_sites() -> void:
	_section("authored sites")

	var spawner := _spawner()
	var rules := _rules()
	rules.spawn_min_distance = 10.0
	rules.spawn_max_distance = 60.0

	var director := _director(spawner, rules)
	director.flow = null
	director.report_player(&"alice", Vector3.ZERO, 1.0)

	var mid := {"id": "mid", "position": Vector3(0, 0, -35)}
	var near := {"id": "near", "position": Vector3(0, 0, -20)}
	var far := {"id": "far", "position": Vector3(0, 0, -55)}

	_check(director.set_sites([mid, near, far, {"id": "no position"}]) == 3,
		"a site without a position is dropped")
	_check(director.choose_spawn_point().value == Vector3(0, 0, -35) and director.last_site == mid,
		"with no rules the middle of the band wins and last_site names it")

	mid["enabled"] = false
	_check(director.choose_spawn_point().value != Vector3(0, 0, -35), "a disabled site is never used")
	mid["enabled"] = true

	mid["weight"] = 0.0
	_check(director.choose_spawn_point().value != Vector3(0, 0, -35), "weight 0 vetoes")
	mid["weight"] = 1.0

	near["weight"] = 3.0
	_check(director.choose_spawn_point().value == Vector3(0, 0, -20), "a heavier site is preferred")
	near["weight"] = 1.0

	mid["phases"] = ["relax"]
	var vetoed: bool = director.choose_spawn_point().value != Vector3(0, 0, -35)
	mid["phases"] = ["build_up"]
	_check(vetoed and director.choose_spawn_point().value == Vector3(0, 0, -35),
		"a site listing other phases is vetoed, and used in its own phase")
	mid["phases"] = []

	mid["max_alive"] = 2
	director.site_alive_fn = func(_site: Variant) -> int: return 2
	_check(director.choose_spawn_point().value != Vector3(0, 0, -35), "a site at max_alive is vetoed")
	director.site_alive_fn = func(_site: Variant) -> int: return 1
	_check(director.choose_spawn_point().value == Vector3(0, 0, -35), "and used below it")
	mid["max_alive"] = 0

	mid["min_player_distance"] = 50.0
	_check(director.choose_spawn_point().value != Vector3(0, 0, -35),
		"a site's own distance band replaces the rules'")
	mid["min_player_distance"] = 0.0

	director.site_filter = func(site: Variant, _point: Vector3) -> bool: return site != mid
	_check(director.choose_spawn_point().value != Vector3(0, 0, -35), "the game's site_filter vetoes")

	director.queue_free()
	spawner.queue_free()
	_done()
