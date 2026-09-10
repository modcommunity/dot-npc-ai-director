extends Node

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

const BODY := "res://fixtures/npc_body.tscn"

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()

var _world: Node3D = null


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

	print("")
	print("%d passed, %d failed" % [_passed, _failed])

	for line in _failures:
		print("  FAIL  %s" % line)

	get_tree().quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    %s" % what)
	else:
		_failed += 1
		var line := what if detail == "" else "%s (%s)" % [what, detail]
		_failures.append(line)
		print("  FAIL  %s" % line)


# --- Builders -----------------------------------------------------------------

func _catalogue() -> DotNpcCatalogue:
	var cat := DotNpcCatalogue.new()

	var zombie := DotNpcDef.make(&"zombie", BODY)
	zombie.require_line_of_sight = false
	cat.add(zombie)

	var brute := DotNpcDef.make(&"brute", BODY)
	brute.require_line_of_sight = false
	brute.cost = 4
	cat.add(brute)

	return cat


func _spawner() -> DotNpcSpawner:
	var spawner := DotNpcSpawner.new()
	spawner.catalogue = _catalogue()

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


## A straight corridor of spawn points, 200 m long.
func _corridor() -> PackedVector3Array:
	var points := PackedVector3Array()

	for i in 41:
		points.append(Vector3(0, 0, -5.0 * float(i)))

	return points


func _director(spawner: DotNpcSpawner, rules: DotNpcDirectorRules = null) -> DotNpcDirector:
	var director := DotNpcDirector.new()
	director.spawner = spawner
	director.rules = rules if rules != null else _rules()
	director.population = [&"zombie", &"zombie", &"zombie", &"brute"]
	director.spawn_points = _corridor()
	director.flow = DotNpcDirectorFlow.new(PackedVector3Array([
		Vector3(0, 0, 0), Vector3(0, 0, -200)
	]))
	_world.add_child(director)
	return director


## Rules with the sight test off, because there is no level in this suite to be hidden
## behind and every point would otherwise be visible from everywhere.
func _rules() -> DotNpcDirectorRules:
	var rules := DotNpcDirectorRules.new()
	rules.spawn_out_of_sight = false
	rules.spawn_interval = 0.0
	return rules


# --- Rules and stress ---------------------------------------------------------

func _test_rules() -> void:
	print("rules")

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


func _test_stress() -> void:
	print("stress")

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


func _test_stress_seeding() -> void:
	print("stress: joining late")

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


func _test_flow() -> void:
	print("flow")

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


# --- Pacing -------------------------------------------------------------------

func _test_population() -> void:
	print("population")

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


func _test_cycle() -> void:
	print("the cycle")

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


func _test_relax_needs_both() -> void:
	print("a relax needs both")

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


func _test_relax_breaks_on_disaster() -> void:
	print("a relax that has to end")

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


# --- Placement ----------------------------------------------------------------

func _test_spawn_points_from_nav() -> void:
	print("spawn points from navigation")

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


func _test_placement_distance() -> void:
	print("placement: how far")

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


func _test_placement_ahead() -> void:
	print("placement: ahead")

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


func _test_placement_refuses() -> void:
	print("placement: refusing")

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


func _test_weighting() -> void:
	print("weighting")

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


func _test_reclaim_behind() -> void:
	print("reclaim")

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


func _test_players_leaving() -> void:
	print("players leaving")

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
