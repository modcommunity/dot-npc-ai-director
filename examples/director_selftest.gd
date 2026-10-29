extends "director_selftest_base.gd"

## Proves the pacing cycles, the placement refuses, and the stress is the players'.
##
## [codeblock]
## godot --headless --path . res://examples/director_selftest.tscn
## [/codeblock]
##
## [b]The tests that matter are the ones about the CYCLE.[/b] Population arithmetic is
## easy to assert and easy to get right. What breaks a director in front of players is a
## relax that never ends, a peak that never comes, a wave placed in front of somebody's
## face, and a reclaim that deletes the ambush the party is walking into. All four are
## here, driven by a stress figure fed the way a real game would feed it.

const CHECKS := 82

## Sections entered against sections that ran to their last line, and against this. A
## runtime error inside a section aborts that function and nothing says so; a section that
## bailed out early after a failed guard is counted as not finished on purpose. The CHECKS
## total is the other half — see docs/testing.md.
const SECTIONS := 19

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()
var _entered := 0
var _completed := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("dot-npc-ai-director self-test")
	print("")

	_world = Node3D.new()
	add_child(_world)

	_test_rules()
	_test_stress()
	_test_stress_seeding()
	_test_flow()
	_test_population()
	_test_cycle()
	_test_relax_needs_both()
	_test_relax_breaks_on_disaster()
	_test_spawn_points_from_nav()
	_test_placement_distance()
	_test_placement_ahead()
	_test_placement_refuses()
	_test_weighting()
	_test_reclaim_behind()
	_test_players_leaving()
	_test_grace()
	_test_waves_rounds()
	_test_waves_cycle()
	_test_waves_clock()

	print("")
	print("%d passed, %d failed" % [_passed, _failed])

	for line in _failures:
		print("  FAIL  %s" % line)

	print("%d of %d sections ran to their last line" % [_completed, _entered])
	if _entered != SECTIONS or _completed != _entered:
		print("ERROR: %d sections entered and %d completed, %d expected. One aborted or was skipped." % [
			_entered, _completed, SECTIONS
		])
		get_tree().quit(1)
		return
	# The total the section counter cannot be. A runtime error inside a section aborts
	# that function, and the counter is satisfied because the section had already
	# announced itself. See docs/testing.md.
	if _passed + _failed != CHECKS:
		print("ERROR: %d checks ran, %d expected. A section aborted part-way." % [
			_passed + _failed, CHECKS
		])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)


func _section(title: String) -> void:
	_entered += 1
	print(title)


## A section reached its last line. See [constant SECTIONS].
func _done() -> void:
	_completed += 1


func _check(ok: bool, what: String, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    %s" % what)
	else:
		_failed += 1
		var line := what if detail == "" else "%s (%s)" % [what, detail]
		_failures.append(line)
		print("  FAIL  %s" % line)


# --- Rules and stress ---------------------------------------------------------

func _test_rules() -> void:
	_section("rules")

	var rules := DotNpcDirectorRules.new()
	_check(rules.validate().ok, "the defaults are usable")

	rules.spawn_min_distance = 100.0
	rules.spawn_max_distance = 50.0
	_check(
		not rules.validate().ok,
		"a minimum above the maximum is refused",
		"no spawn point could ever be legal"
	)

	var inverted := DotNpcDirectorRules.new()
	inverted.relax_per_player = 40.0
	inverted.peak_per_player = 10.0
	_check(
		not inverted.validate().ok,
		"and a relax busier than a peak inverts the whole cycle"
	)

	var configured := DotNpcDirectorRules.new()
	configured.apply_dictionary({"peak_per_player": 30.0})
	_check(
		configured.peak_per_player == 30.0,
		"and it is a DotConfig, so a campaign is retuned in a file"
	)
	_done()


func _test_stress() -> void:
	_section("stress")

	var rules := _rules()
	var player := DotNpcDirectorStress.make(&"alice")

	player.advance(rules, Vector3.ZERO, 1.0, 0, 0.1)
	_check(player.value == 0.0, "a player nothing is happening to has none")

	player.advance(rules, Vector3.ZERO, 0.6, 0, 0.1)
	_check(player.value > 0.4, "losing health raises it", "%.2f" % player.value)

	var after_damage := player.value

	for i in 60:
		player.advance(rules, Vector3.ZERO, 0.6, 0, 0.1)

	_check(player.value < after_damage, "and it decays with nothing happening",
		"%.2f from %.2f" % [player.value, after_damage])

	var surrounded := DotNpcDirectorStress.make(&"bob")
	surrounded.advance(rules, Vector3.ZERO, 1.0, 0, 0.1)

	for i in 100:
		surrounded.advance(rules, Vector3.ZERO, 1.0, 8, 0.1)

	_check(
		surrounded.value > 0.1,
		"and being surrounded raises it before anything has hit you",
		"%.2f; without this a director waits for the first bite" % surrounded.value
	)

	var falling := DotNpcDirectorStress.make(&"carol")
	falling.advance(rules, Vector3.ZERO, 1.0, 0, 0.1)
	falling.advance(rules, Vector3(0, -80, 0), 1.0, 0, 0.1)
	_check(
		falling.travelled < 1.0,
		"and falling down a shaft is not progress",
		"%.1f m; the relax must not end because somebody fell" % falling.travelled
	)
	_done()


func _test_stress_seeding() -> void:
	_section("stress: joining late")

	var rules := _rules()
	var joiner := DotNpcDirectorStress.make(&"late")

	# First tick at half health: a player who joined hurt, or one the director had not
	# been told about. Without seeding on the first tick this registers half a health
	# bar of damage and the director opens with a peak.
	joiner.advance(rules, Vector3.ZERO, 0.5, 0, 0.1)

	_check(
		joiner.value == 0.0,
		"a player who arrives already hurt is not counted as having just been hurt",
		"%.2f; the game would attack them the instant they connect" % joiner.value
	)

	joiner.advance(rules, Vector3.ZERO, 0.3, 0, 0.1)
	_check(joiner.value > 0.0, "but damage after that counts normally")
	_done()


func _test_flow() -> void:
	_section("flow")

	var flow := DotNpcDirectorFlow.new(PackedVector3Array([
		Vector3(0, 0, 0), Vector3(0, 0, -100), Vector3(50, 0, -100)
	]))

	_check(flow.has_route(), "a route is a route")
	_check(absf(flow.length() - 150.0) < 0.01, "and knows its length", "%.1f" % flow.length())

	_check(
		absf(flow.flow_of(Vector3(0, 0, -50)) - 50.0) < 0.01,
		"a position halfway along the first leg is 50 m in"
	)
	_check(
		absf(flow.flow_of(Vector3(25, 0, -100)) - 125.0) < 0.01,
		"and one on the second leg counts the first"
	)
	_check(
		absf(flow.flow_of(Vector3(3, 0, -50)) - 50.0) < 0.5,
		"and a position beside the route is projected onto it",
		"snapping to the nearest point would quantise progress to the leg length"
	)

	_check(
		flow.position_at(75.0).is_equal_approx(Vector3(0, 0, -75)),
		"and a flow distance turns back into a position"
	)
	_check(
		flow.position_at(9999.0).is_equal_approx(Vector3(50, 0, -100)),
		"clamped to the end rather than extrapolated into the void"
	)

	var arena := DotNpcDirectorFlow.new()
	_check(not arena.has_route(), "and a map with no critical path says so honestly")
	_check(arena.flow_of(Vector3(9, 9, 9)) == 0.0, "rather than refusing")
	_done()


# --- Pacing -------------------------------------------------------------------

func _test_population() -> void:
	_section("population")

	var spawner := _spawner()
	var director := _director(spawner)

	director.report_player(&"a", Vector3.ZERO, 1.0)
	director.report_player(&"b", Vector3.ZERO, 1.0)

	var two := director.target_population()

	director.report_player(&"c", Vector3.ZERO, 1.0)
	director.report_player(&"d", Vector3.ZERO, 1.0)

	_check(
		director.target_population() > two,
		"the population is per player",
		"a horde sized for four is a massacre for one and a walk for eight"
	)

	director.rules.absolute_cap = 3
	_check(director.target_population() == 3, "and the absolute cap wins")

	director.queue_free()
	spawner.queue_free()
	_done()


func _test_cycle() -> void:
	_section("the cycle")

	var spawner := _spawner()
	var rules := _rules()
	rules.sustain_seconds = 1.0
	rules.fade_seconds = 2.0
	rules.relax_seconds = 3.0
	rules.relax_distance = 10.0
	rules.peak_stress = 0.5

	var director := _director(spawner, rules)
	var phases: Array[String] = []

	# An Array rather than a counter: a GDScript lambda captures locals BY VALUE.
	director.phase_changed.connect(func(_f: DotNpcDirector.Phase, t: DotNpcDirector.Phase) -> void:
		phases.append(DotNpcDirector.Phase.keys()[t]))

	director.report_player(&"alice", Vector3.ZERO, 1.0)

	_check(director.phase() == DotNpcDirector.Phase.BUILD_UP, "it starts building up")

	for i in 20:
		director.report_player(&"alice", Vector3.ZERO, 1.0)
		director.tick(0.1)

	_check(
		director.phase() == DotNpcDirector.Phase.BUILD_UP,
		"and stays there while the players are fine",
		"now %s" % director.phase_name()
	)

	# Hurt, badly. The director should notice without being told about damage.
	var health := 1.0

	for i in 20:
		health = maxf(health - 0.05, 0.1)
		director.report_player(&"alice", Vector3.ZERO, health)
		director.tick(0.1)

	_check(
		director.phase() == DotNpcDirector.Phase.SUSTAIN
			or phases.has("SUSTAIN"),
		"a player having a hard time peaks it",
		"now %s after %s" % [director.phase_name(), str(phases)]
	)

	var walked := 0.0

	for i in 200:
		walked += 0.5
		director.report_player(&"alice", Vector3(0, 0, -walked), 1.0)
		director.tick(0.1)

	_check(phases.has("FADE"), "the peak fades")
	_check(phases.has("RELAX"), "and then it is quiet")

	# That the cycle CAME BACK, not where it happens to be at the end of the loop.
	#
	# Stress left over from the peak can break a relax early — which is the documented
	# behaviour and is tested on its own — so the party goes round more than once in
	# twenty seconds and the final phase is whichever one the last tick landed in.
	# Asserting the final phase would make this test pass or fail on the loop length.
	_check(
		phases.has("BUILD_UP"),
		"and once they have breathed and moved, it begins again",
		"phases seen: %s" % str(phases)
	)

	director.queue_free()
	spawner.queue_free()
	_done()


func _test_relax_needs_both() -> void:
	_section("a relax needs both")

	var spawner := _spawner()
	var rules := _rules()
	rules.relax_seconds = 2.0
	rules.relax_distance = 40.0
	rules.relax_break_stress = 0.0

	var director := _director(spawner, rules)
	director.report_player(&"alice", Vector3.ZERO, 1.0)
	director._go_to(DotNpcDirector.Phase.RELAX)

	# Plenty of time, standing still. A team arguing about a door.
	for i in 200:
		director.report_player(&"alice", Vector3.ZERO, 1.0)
		director.tick(0.1)

	_check(
		director.phase() == DotNpcDirector.Phase.RELAX,
		"waiting alone does not end it",
		"or a team that stopped is attacked on schedule"
	)

	var walked := 0.0

	for i in 200:
		walked += 0.5
		director.report_player(&"alice", Vector3(0, 0, -walked), 1.0)
		director.tick(0.1)

	_check(
		director.phase() == DotNpcDirector.Phase.BUILD_UP,
		"and moving as well does",
		"now %s after %.0f m" % [director.phase_name(), walked]
	)

	director.queue_free()
	spawner.queue_free()
	_done()


func _test_relax_breaks_on_disaster() -> void:
	_section("a relax that has to end")

	var spawner := _spawner()
	var rules := _rules()
	rules.relax_seconds = 600.0
	rules.relax_distance = 10000.0
	rules.relax_break_stress = 0.6

	var director := _director(spawner, rules)
	director.report_player(&"alice", Vector3.ZERO, 1.0)
	director._go_to(DotNpcDirector.Phase.RELAX)

	var health := 1.0

	for i in 30:
		health = maxf(health - 0.05, 0.05)
		director.report_player(&"alice", Vector3.ZERO, health)
		director.tick(0.1)

	_check(
		director.phase() != DotNpcDirector.Phase.RELAX,
		"a player being killed during the quiet ends the quiet",
		"or the pacing keeps spawning into a fight that is already happening"
	)

	director.queue_free()
	spawner.queue_free()
	_done()


# --- Placement ----------------------------------------------------------------

func _test_spawn_points_from_nav() -> void:
	_section("spawn points from navigation")

	var builder := DotNpcNavBuilder.new()
	builder.spacing = 2.0
	builder.generate_cover = false
	builder.add_floor(AABB(Vector3(-20, 0, -20), Vector3(40, 0, 40)), 0.0)
	builder.add_floor(
		AABB(Vector3(-20, 0, 20), Vector3(40, 0, 10)), 0.0,
		DotNpcNavData.AREA_GROUND, DotNpcNavData.Flag.CROUCH
	)

	var nav := builder.build(&"arena", "digest")
	var director := _director(_spawner())

	var kept := director.set_spawn_points_from_nav(nav, 8.0)

	_check(kept > 0, "navigation becomes spawn points", "%d of %d" % [
		kept, nav.point_count()
	])

	# Not a nicety. choose_spawn_point walks every candidate and raycasts the ones
	# inside the distance band, so an unthinned two-metre grid is a few thousand
	# raycasts per wave on the server.
	_check(
		kept < nav.point_count() / 4,
		"thinned rather than copied, because every candidate costs a raycast per wave",
		"%d of %d" % [kept, nav.point_count()]
	)

	var closest := INF
	for i in director.spawn_points.size():
		for j in range(i + 1, director.spawn_points.size()):
			closest = minf(
				closest, director.spawn_points[i].distance_to(director.spawn_points[j])
			)

	_check(
		closest >= 8.0 - 0.001,
		"and no two kept points are closer than the spacing asked for",
		"%.2f m" % closest
	)

	var crouch_free := director.set_spawn_points_from_nav(
		nav, 4.0, DotNpcNavFilter.walking_only()
	)
	var in_the_tunnel := 0
	for point in director.spawn_points:
		if point.z > 20.0:
			in_the_tunnel += 1

	_check(crouch_free > 0, "a filter still keeps most of the map")
	_check(
		in_the_tunnel == 0,
		"and keeps the horde out of the crouch tunnel it cannot use"
	)

	_check(
		director.set_spawn_points_from_nav(null) == 0,
		"no navigation is no spawn points rather than an error"
	)
	_check(
		director.spawn_points.is_empty(),
		"and clears whatever was there, so a map change does not leave the last map's"
	)

	director.queue_free()
	_done()


func _test_placement_distance() -> void:
	_section("placement: how far")

	var spawner := _spawner()
	var rules := _rules()
	rules.spawn_min_distance = 20.0
	rules.spawn_max_distance = 60.0

	var director := _director(spawner, rules)
	director.report_player(&"alice", Vector3.ZERO, 1.0)

	for i in 20:
		var spot := director.choose_spawn_point()

		if not spot.ok:
			_check(false, "a spawn point is found", spot.error.message)
			break

		var distance := (spot.value as Vector3).distance_to(Vector3.ZERO)

		if distance < 20.0 or distance > 60.0:
			_check(false, "every spawn is inside the band", "%.1f m" % distance)
			break

	_check(true, "every spawn is inside the band",
		"too near reads as cheating; too far arrives a minute late")

	director.queue_free()
	spawner.queue_free()
	_done()


func _test_placement_ahead() -> void:
	_section("placement: ahead")

	var spawner := _spawner()
	var rules := _rules()
	rules.spawn_min_distance = 10.0
	rules.spawn_max_distance = 90.0
	rules.spawn_ahead = 40.0
	rules.behind_fraction = 0.0

	var director := _director(spawner, rules)
	director.report_player(&"alice", Vector3(0, 0, -50), 1.0)

	var spot := director.choose_spawn_point()

	_check(spot.ok, "a spawn point is found")
	_check(
		(spot.value as Vector3).z < -50.0,
		"and it is AHEAD of the party along the route",
		"at z=%.0f; a director that surrounds people removes the only decision they had"
			% (spot.value as Vector3).z
	)

	var wanted := -50.0 - 40.0
	_check(
		absf((spot.value as Vector3).z - wanted) < 10.0,
		"and near the preferred distance ahead rather than at the end of the map",
		"z=%.0f, wanted about %.0f" % [(spot.value as Vector3).z, wanted]
	)

	director.queue_free()
	spawner.queue_free()
	_done()


func _test_placement_refuses() -> void:
	_section("placement: refusing")

	var spawner := _spawner()
	var rules := _rules()
	rules.spawn_min_distance = 500.0
	rules.spawn_max_distance = 900.0

	var director := _director(spawner, rules)
	director.report_player(&"alice", Vector3.ZERO, 1.0)

	_check(
		not director.choose_spawn_point().ok,
		"with nowhere legal, it refuses rather than picking anyway"
	)

	var empty := _director(spawner, _rules())
	empty.spawn_points = PackedVector3Array()
	empty.report_player(&"alice", Vector3.ZERO, 1.0)

	_check(
		not empty.choose_spawn_point().ok,
		"and a director with no spawn points says so"
	)

	director.queue_free()
	empty.queue_free()
	spawner.queue_free()
	_done()


func _test_weighting() -> void:
	_section("weighting")

	var spawner := _spawner()
	var rules := _rules()
	rules.spawn_min_distance = 5.0
	rules.spawn_max_distance = 200.0
	rules.spawn_burst = 40
	rules.behind_fraction = 1.0

	var director := _director(spawner, rules)
	director.report_player(&"alice", Vector3(0, 0, -100), 1.0)

	for i in 20:
		director.tick(0.1)

	var zombies := spawner.count_of(&"zombie")
	var brutes := spawner.count_of(&"brute")

	_check(zombies + brutes > 0, "the director spawns", "%d + %d" % [zombies, brutes])
	_check(
		brutes > 0 and zombies > brutes,
		"and a list of three zombies to one brute gives about that",
		"%d zombies, %d brutes; a random pick gives four brutes in a row often enough to notice"
			% [zombies, brutes]
	)

	director.queue_free()
	spawner.queue_free()
	_done()


func _test_reclaim_behind() -> void:
	_section("reclaim")

	var spawner := _spawner()
	var rules := _rules()
	rules.spawn_max_distance = 50.0
	rules.reclaim_interval = 0.0

	var director := _director(spawner, rules)
	director.report_player(&"alice", Vector3(0, 0, -150), 1.0)

	var behind := spawner.spawn(&"zombie", Vector3(0, 0, -10), &"director")
	var ahead := spawner.spawn(&"zombie", Vector3(0, 0, -180), &"director")
	var scripted := spawner.spawn(&"zombie", Vector3(0, 0, -5), &"map")

	director.tick(0.1)

	_check(not behind.is_alive(), "what the party has walked past is reclaimed")
	_check(
		ahead.is_alive(),
		"and the ambush they are walking INTO is not",
		"distance alone would reclaim the wave that was the whole point"
	)
	_check(
		scripted.is_alive(),
		"and nothing the director did not spawn is touched",
		"a scripted set piece is not the director's to tidy away"
	)

	director.queue_free()
	spawner.queue_free()
	_done()


func _test_players_leaving() -> void:
	_section("players leaving")

	var spawner := _spawner()
	var rules := _rules()
	rules.relax_seconds = 1.0
	rules.relax_distance = 10.0

	var director := _director(spawner, rules)
	director.report_player(&"alice", Vector3.ZERO, 1.0)
	director.report_player(&"bob", Vector3.ZERO, 1.0)
	director._go_to(DotNpcDirector.Phase.RELAX)

	# Alice walks; bob disconnects without moving. The relax must not be held open for
	# ever by somebody who is not there.
	var walked := 0.0

	for i in 100:
		walked += 0.5
		director.report_player(&"alice", Vector3(0, 0, -walked), 1.0)
		director.tick(0.1)

	_check(
		director.phase() == DotNpcDirector.Phase.RELAX,
		"a party is as far along as its least-travelled member",
		"one player scouting ahead has not moved the party anywhere"
	)

	director.forget_player(&"bob")
	director.tick(0.1)

	_check(director.player_count() == 1, "a player can be forgotten")
	_check(
		director.phase() == DotNpcDirector.Phase.BUILD_UP,
		"and the relax is no longer held open by somebody who has left",
		"now %s" % director.phase_name()
	)

	director.queue_free()
	spawner.queue_free()
	_done()


func _test_grace() -> void:
	_section("grace")
	var spawner := _spawner()
	var director := _director(spawner, _rules())
	director.report_player(&"alice", Vector3.ZERO, 1.0)
	var grace := DotNpcDirectorGrace.new()
	director.grace = grace
	var ended := [0]
	grace.ended.connect(func(_skipped: bool) -> void: ended[0] += 1)
	_check(not grace.begin(0.0) and not grace.is_active(), "a grace of zero seconds does not run")
	_check(grace.begin(2.0) and grace.is_active(), "a grace runs")
	for i in 15:
		director.tick(0.1)
	_check(grace.is_active() and spawner.all_npcs().is_empty(), "the director spawns nothing while it runs")
	grace.tick(2.0)
	_check(not grace.is_active() and ended[0] == 1, "it ends once, when it runs out")
	var spawned := 0
	for i in 400:
		director.tick(0.1)
	spawned = spawner.all_npcs().size()
	_check(spawned > 0, "and the director spawns after it", "%d spawned" % spawned)
	director.queue_free()
	spawner.queue_free()
	_done()


# --- A hold-out's schedule ---------------------------------------------------------------------

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
