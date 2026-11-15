@tool
class_name DotNpcDirector
extends "dot_npc_director_inputs.gd"

## Population and pacing. The co-operative survival shooters' director, over a
## [DotNpcSpawner].
##
## [b]Four phases and one number.[/b] BUILD_UP raises the population until the players
## are having a hard time; SUSTAIN holds it there briefly; FADE lets it fall; RELAX
## leaves them alone until they have both breathed and moved. The number is
## [DotNpcDirectorStress], and it is what makes this a director rather than a spawn
## timer: a team that is struggling gets a moment to recover and a team that is coasting
## gets something to do, from the same rules, with no difficulty setting.
##
## [b]It owns no NPCs.[/b] Every spawn, cap, reclaim and budget is [DotNpcSpawner]'s;
## this decides how many and where, and the spawner is free to refuse. That division is
## why a game can run a director on some maps and not others without two population
## systems.
##
## [codeblock]
## var director := DotNpcDirector.new()
## director.spawner = npcs
## director.rules = DotNpcDirectorRules.new()
## director.flow = DotNpcDirectorFlow.new(map.critical_path)
## director.population = [&"zombie", &"zombie", &"brute"]   # weighted by repetition
## add_child(director)
##
## # Every simulated tick, after the spawner has been given its candidates:
## director.report_player(&"alice", position, health / max_health)
## director.tick(delta)
## [/codeblock]


## The pacing moved on.
signal phase_changed(from: Phase, to: Phase)

## A wave was placed. [param count] is how many actually spawned, not how many were
## asked for — the spawner refuses past its own budget and a listener wants the truth.
signal wave_spawned(at: Vector3, count: int)

enum Phase {
	## Population rising. Ends when the players are having a hard enough time.
	BUILD_UP,
	## Held at the peak, briefly.
	SUSTAIN,
	## Falling back toward the relax figure.
	FADE,
	## Quiet. Ends when the players have both waited and travelled.
	RELAX,
}

@export_group("Wiring")

## The spawner this director drives. Required.
@export var spawner_ref: DotNodeRef = null

@export_group("Rules")

@export var rules: DotNpcDirectorRules = null

## What may be spawned, by id. Repetition is the weighting.
##
## [b]A flat list rather than a table of weights, deliberately.[/b] `[&"zombie",
## &"zombie", &"zombie", &"brute"]` is one brute in four, is obvious at a glance, is a
## line an operator can edit in a JSON file, and cannot express a weight that does not
## add up. A table of floats can, and the first thing anybody does with one is get it
## wrong by 0.05 and never notice.
@export var population: Array[StringName] = []

## Set false to leave the population exactly where it is. For a scripted set piece.
@export var enabled: bool = true

## While this grace runs the director spawns and reclaims nothing; the game ticks it.
var grace: DotNpcDirectorGrace = null

## The spawner, resolved. Assignable directly for a host that has one to hand.
var spawner: DotNpcSpawner = null

## The map's critical path. Null or empty for an arena.
var flow: DotNpcDirectorFlow = null


var _phase: Phase = Phase.BUILD_UP

## Simulated seconds when the current phase began.
var _phase_started: float = 0.0

## Simulated seconds. Advanced by [method tick], never a wall clock.
var _now: float = 0.0

var _last_spawn_at: float = -1000.0
var _last_reclaim_at: float = -1000.0

## How many spawns have come from behind the party, and how many in total. What
## [member DotNpcDirectorRules.behind_fraction] is enforced against.
var _behind_spawns: int = 0
var _total_spawns: int = 0


var _specials := DotNpcDirectorSpecials.new()

var wave_count: int = 0
var spawn_count: int = 0
var refused_placements: int = 0


## Whether [param site] is allowed in the current phase and by its cap and filter.
## Distance and sight are the caller's, because sight costs a raycast.
func _site_allows(site: Variant) -> bool:
	if not bool(_site_get(site, "enabled", true)):
		return false

	if float(_site_get(site, "weight", 1.0)) <= 0.0:
		return false

	var phases: Variant = _site_get(site, "phases", [])

	if phases is Array and not (phases as Array).is_empty():
		var current := String(Phase.keys()[_phase]).to_lower()
		var listed := false

		for phase_name in phases:
			listed = listed or String(phase_name).to_lower() == current

		if not listed:
			return false

	var cap := int(_site_get(site, "max_alive", 0))

	if cap > 0 and site_alive_fn.is_valid() and int(site_alive_fn.call(site)) >= cap:
		return false

	if site_filter.is_valid():
		return bool(site_filter.call(site, _site_get(site, "position", Vector3.ZERO)))

	return true


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	if rules == null:
		rules = DotNpcDirectorRules.new()

	var valid := rules.validate()

	if not valid.ok:
		DotLog.warn(CHANNEL, "director rules are not usable", {
			"why": valid.error.message
		})

	if spawner == null and spawner_ref != null:
		var resolved := spawner_ref.resolve(self)

		if resolved.ok:
			spawner = resolved.value as DotNpcSpawner

	if spawner == null:
		DotLog.warn(CHANNEL, "the director has no spawner and will do nothing", {})

	_specials.reset(rules)

	if rules.skill_enabled or rules.difficulty_enabled or rules.specials_enabled:
		DotLog.info(CHANNEL, "director adaptation on", {
			"skill": rules.skill_enabled,
			"difficulty": rules.difficulty_enabled,
			"specials": rules.specials_enabled,
		})


# --- What the game tells it ---------------------------------------------------


## The multiplier on one player's share of the peak: 1.0 while skill is off or unknown.
func skill_multiplier(id: StringName) -> float:
	if rules == null or not rules.skill_enabled or not _skills.has(id):
		return 1.0

	return (_skills[id] as DotNpcDirectorSkill).multiplier(rules)


## Enemy accuracy multiplier for the host to apply; 1.0 while difficulty is off.
func enemy_accuracy_multiplier() -> float:
	return DotNpcDirectorDifficulty.accuracy(rules)


## Enemy damage multiplier for the host to apply; 1.0 while difficulty is off.
func enemy_damage_multiplier() -> float:
	return DotNpcDirectorDifficulty.damage(rules)


## Specials that may still be spawned right now by the budget alone.
func special_budget() -> float:
	return _specials.budget


# --- The tick -----------------------------------------------------------------

func tick(delta: float) -> void:
	if spawner == null or not enabled:
		return

	if grace != null and grace.is_active():
		return

	_now += delta

	_advance_stress(delta)
	_advance_skill(delta)
	_advance_phase()

	if rules.specials_enabled:
		_specials.advance(rules, delta)

	if _now - _last_spawn_at >= rules.spawn_interval:
		_last_spawn_at = _now
		_spawn_toward_target()

	# No `> 0.0` guard on the interval.
	#
	# Zero means "every tick" here, exactly as it does for `spawn_interval` and for
	# `DotNpcLimits.spawn_interval` — and the first version of this line read it as
	# "never", so a game that turned the wait off got a director that never reclaimed
	# anything. Two settings named the same way meaning opposite things at zero is the
	# kind of difference nobody reads twice.
	if _now - _last_reclaim_at >= rules.reclaim_interval:
		_last_reclaim_at = _now
		_reclaim_behind()


func _advance_stress(delta: float) -> void:
	for id in _players:
		var player: DotNpcDirectorStress = _players[id]
		var threats := 0

		if rules.stress_threat_radius > 0.0:
			threats = spawner.npcs_near(player.position, rules.stress_threat_radius).size()

		player.advance(rules, player.position, player.health_fraction, threats, delta)


func _advance_skill(delta: float) -> void:
	if not rules.skill_enabled:
		return

	for id in _players:
		var skill := _skill_of(id)
		skill.add_damage((_players[id] as DotNpcDirectorStress).last_loss)
		skill.advance(rules, delta)


## The party's stress: the worst player's, or the average.
func stress() -> float:
	if _players.is_empty():
		return 0.0

	var worst := 0.0
	var total := 0.0

	for id in _players:
		var value := (_players[id] as DotNpcDirectorStress).value
		worst = maxf(worst, value)
		total += value

	return worst if rules.stress_from_worst_player else total / float(_players.size())


func _advance_phase() -> void:
	var elapsed := _now - _phase_started

	match _phase:
		Phase.BUILD_UP:
			if stress() >= rules.peak_stress:
				_go_to(Phase.SUSTAIN)

		Phase.SUSTAIN:
			if elapsed >= rules.sustain_seconds:
				_go_to(Phase.FADE)

		Phase.FADE:
			if elapsed >= rules.fade_seconds:
				_go_to(Phase.RELAX)

		Phase.RELAX:
			# Both, and this is the pair that makes a relax work. Time alone lets a team
			# that has stopped to argue about a door be attacked on schedule; distance
			# alone lets a team that is sprinting be attacked every few seconds.
			var rested := elapsed >= rules.relax_seconds
			var moved := party_travel() >= rules.relax_distance

			if rested and moved:
				_go_to(Phase.BUILD_UP)
			elif rules.relax_break_stress > 0.0 and stress() >= rules.relax_break_stress:
				# Something has gone wrong that the director did not cause. Left alone
				# the pacing would keep spawning into a fight that is already happening.
				_go_to(Phase.SUSTAIN)


func _go_to(to: Phase) -> void:
	var from := _phase
	_phase = to
	_phase_started = _now

	if to == Phase.RELAX:
		# The travel counters start now, or the relax ends on distance the party covered
		# during the fight — which is most of it, and the relax would be over before it
		# began.
		for id in _players:
			(_players[id] as DotNpcDirectorStress).reset_travel()

	phase_changed.emit(from, to)

	DotLog.debug(CHANNEL, "pacing", {
		"from": Phase.keys()[from],
		"to": Phase.keys()[to],
		"stress": "%.2f" % stress(),
	})


func phase() -> Phase:
	return _phase


func phase_name() -> String:
	return Phase.keys()[_phase]


# --- How many ------------------------------------------------------------------

## How many enemies the director wants alive right now.
##
## FADE interpolates rather than dropping, which is the whole difference between a wave
## breaking and a wave being deleted: the population it produces is the population that
## is already alive, walking away or being killed, and the director simply stops
## replacing it.
func target_population() -> int:
	var players := maxf(float(_players.size()), 1.0)
	var per_player := rules.build_up_per_player

	match _phase:
		Phase.BUILD_UP:
			per_player = rules.build_up_per_player
		Phase.SUSTAIN:
			per_player = rules.peak_per_player
		Phase.FADE:
			var t := (
				clampf((_now - _phase_started) / rules.fade_seconds, 0.0, 1.0)
				if rules.fade_seconds > 0.0 else 1.0
			)
			per_player = lerpf(rules.peak_per_player, rules.relax_per_player, t)
		Phase.RELAX:
			per_player = rules.relax_per_player

	var wanted := int(round(per_player * players))

	if rules.skill_enabled and not _players.is_empty() and (
		_phase == Phase.SUSTAIN or _phase == Phase.FADE
	):
		wanted = int(round(_skilled_population()))

	return mini(wanted, rules.absolute_cap) if rules.absolute_cap > 0 else wanted


## The sustain or fade population with each player's share of the peak scaled by skill.
func _skilled_population() -> float:
	var relax := rules.relax_per_player
	var t := 0.0

	if _phase == Phase.FADE:
		t = (
			clampf((_now - _phase_started) / rules.fade_seconds, 0.0, 1.0)
			if rules.fade_seconds > 0.0 else 1.0
		)

	var total := 0.0

	for id in _players:
		var peak := rules.peak_per_player * skill_multiplier(id)
		total += lerpf(peak, relax, t)

	return total


func _spawn_toward_target() -> void:
	if population.is_empty() or _players.is_empty():
		return

	var wanted := target_population() - spawner.world_count()

	if wanted <= 0:
		return

	var burst := mini(wanted, rules.spawn_burst) if rules.spawn_burst > 0 else wanted
	var placed := 0
	var at := Vector3.ZERO

	for i in burst:
		var spot := choose_spawn_point()

		if not spot.ok:
			refused_placements += 1
			break

		at = spot.value

		# Round-robin through the population list rather than a random pick, so the
		# weighting is exact rather than approached. A random pick from a four-entry
		# list gives four brutes in a row often enough for a player to notice and
		# conclude the director is broken.
		var kind := population[(_total_spawns + i) % population.size()]

		if rules.specials_enabled and rules.special_kinds.has(kind):
			kind = _kind_within_budget(kind, (_total_spawns + i) % population.size())

			if kind == &"":
				continue

		# [b]The spawner says which dimension its world is, and this is the only place the
		# director cares.[/b] Everything above — the stress, the phase, the population
		# target, the scoring of a spawn point — is arithmetic on points in dot-npc's own
		# plane and is identical either way. A 2D game forking this file to change one
		# call would be forking the whole director to avoid a `Vector3`.
		var made: DotNpcInstance = (
			spawner.spawn_2d(kind, DotNpcInstance.from_plane(at), &"director")
			if spawner.two_dimensional
			else spawner.spawn(kind, at, &"director")
		)

		if made != null:
			placed += 1

			if rules.specials_enabled and rules.special_kinds.has(kind):
				_specials.spend()

	if placed <= 0:
		return

	_total_spawns += placed
	spawn_count += placed
	wave_count += 1

	wave_spawned.emit(at, placed)


## [param kind] if the specials budget allows it, else the next ordinary kind, else empty.
func _kind_within_budget(kind: StringName, start: int) -> StringName:
	var alive := 0

	for special in rules.special_kinds:
		alive += spawner.count_of(special)

	if _specials.allows(rules, alive):
		return kind

	_specials.denied += 1

	for offset in population.size():
		var other := population[(start + offset) % population.size()]

		if not rules.special_kinds.has(other):
			return other

	return &""


# --- Where ---------------------------------------------------------------------

## Picks somewhere to put one enemy, or a refusal saying why not.
##
## [b]Preference, not a search for the best.[/b] The candidates are scored and the best
## legal one wins, which sounds like the same thing and is not: an unscored search that
## takes the first legal point puts every wave in the same doorway, because the point
## list is in the order the map generated it.
func choose_spawn_point() -> DotResult:
	if spawn_points.is_empty():
		return DotResult.fail(
			DotError.CODE_STATE,
			"The director has no spawn points, so it has nowhere to put anything."
		)

	var ahead_of := _wanted_flow()
	var allow_behind := (
		rules.behind_fraction > 0.0
		and float(_behind_spawns) < float(maxi(_total_spawns, 1)) * rules.behind_fraction
	)

	var best := Vector3.ZERO
	var best_score := -INF
	var found := false
	var best_site: Variant = null
	var use_sites := not _sites.is_empty() and _sites.size() == spawn_points.size()

	for index in spawn_points.size():
		var point := spawn_points[index]
		var site: Variant = _sites[index] if use_sites else null
		var score := _spawn_score(point, site, use_sites, allow_behind, ahead_of)

		if score > best_score:
			best_score = score
			best = point
			best_site = site
			found = true

	if not found:
		return DotResult.fail(
			DotError.CODE_STATE,
			"No spawn point is far enough, near enough and out of sight.",
			"%d considered" % spawn_points.size()
		)

	# Asked again of the winner alone, exactly as [method _spawn_score] asked it.
	if flow != null and flow.has_route() and flow.flow_of(best) < _party_flow():
		_behind_spawns += 1

	last_site = best_site
	return DotResult.success(best)


## How much [method choose_spawn_point] wants [param point] (higher is better), or -INF where
## the rules or its [param site] forbid it.
func _spawn_score(point: Vector3, site: Variant, use_sites: bool, allow_behind: bool, ahead_of: float) -> float:
	var nearest := _distance_to_nearest_player(point)
	var min_distance := rules.spawn_min_distance
	var max_distance := rules.spawn_max_distance
	var sight := "any"

	if use_sites:
		if not _site_allows(site):
			return -INF

		var site_min := float(_site_get(site, "min_player_distance", 0.0))
		var site_max := float(_site_get(site, "max_player_distance", 0.0))
		min_distance = site_min if site_min > 0.0 else min_distance
		max_distance = site_max if site_max > 0.0 else max_distance
		sight = String(_site_get(site, "sight", "any"))

	if nearest < min_distance or nearest > max_distance:
		return -INF

	if sight == "any":
		if rules.spawn_out_of_sight and _is_visible_to_any_player(point):
			return -INF
	elif _is_visible_to_any_player(point) != (sight == "visible_to_players"):
		return -INF

	var score := 0.0

	if flow != null and flow.has_route():
		var point_flow := flow.flow_of(point)
		if point_flow < _party_flow() and not allow_behind:
			return -INF

		# Closest to the preferred flow position wins. A director that simply took
		# the furthest-ahead point spawns everything at the end of the map, where it
		# waits for the party for two minutes and then arrives as one enormous wave.
		score = -absf(point_flow - ahead_of)
	else:
		# No route: prefer the middle of the legal band. In an arena "ahead" has no
		# meaning and the useful preference is "not right on top of them, not so far
		# away it never arrives".
		var middle := (min_distance + max_distance) * 0.5
		score = -absf(nearest - middle)

	if use_sites:
		score += (float(_site_get(site, "weight", 1.0)) - 1.0) * SITE_WEIGHT_METRES

	return score


func _party_flow() -> float:
	if flow == null or not flow.has_route() or _players.is_empty():
		return 0.0

	var furthest := 0.0

	for id in _players:
		furthest = maxf(furthest, flow.flow_of((_players[id] as DotNpcDirectorStress).position))

	return furthest


func _wanted_flow() -> float:
	return _party_flow() + rules.spawn_ahead


## Whether any player has line of sight to [param point].
##
## Uses the spawner's world, and answers "no" when there is no physics world — for
## [DotNpcSenses]' reason: refusing every spawn in a scene that is not in a viewport
## would make a headless suite unable to place anything, and a suite that cannot place
## anything tests nothing.
func _is_visible_to_any_player(point: Vector3) -> bool:
	if spawner == null:
		return false

	# Asked of the viewport rather than of the spawner. A [DotNpcSpawner] is a plain
	# [Node] and has no `get_world_3d` — the obvious call does not exist, and written as
	# a duck-typed one it does not even compile, because GDScript cannot infer the type
	# of what a `has_method` branch returns.
	var viewport := spawner.get_viewport()

	if viewport == null:
		return false

	var world := viewport.world_3d

	if world == null:
		return false

	var space: PhysicsDirectSpaceState3D = world.direct_space_state

	if space == null:
		return false

	for id in _players:
		var player: DotNpcDirectorStress = _players[id]

		# Raised to about eye height at both ends. A ray between two points on the floor
		# is blocked by every kerb and doorstep, so a floor-to-floor test reports that
		# nothing is ever visible and the out-of-sight rule stops meaning anything.
		var from := player.position + Vector3.UP * 1.6
		var to := point + Vector3.UP * 1.6

		var query := PhysicsRayQueryParameters3D.create(from, to)

		if space.intersect_ray(query).is_empty():
			return true

	return false


# --- Reclaiming ------------------------------------------------------------------

## Removes what the party has left behind.
##
## [b]Behind along the ROUTE, not merely far away.[/b] Distance alone reclaims the wave
## waiting in the room the party is about to walk into, which is the wave that was the
## whole point. dot-npc's own reclaim is the distance-based safety net underneath this.
func _reclaim_behind() -> void:
	if flow == null or not flow.has_route() or _players.is_empty():
		return

	var behind_of := _party_flow() - rules.spawn_max_distance

	for npc in spawner.all_npcs():
		if npc.owner_id != &"director" or npc.has_target():
			continue

		if flow.flow_of(npc.position()) < behind_of:
			spawner.remove(npc.instance_id, DotNpcSpawner.REASON_RECLAIMED)


# --- Reporting -------------------------------------------------------------------

func now() -> float:
	return _now


func describe() -> Dictionary:
	return {
		"phase": phase_name(),
		"for": "%.1fs" % (_now - _phase_started),
		"stress": "%.2f" % stress(),
		"players": _players.size(),
		"alive": spawner.world_count() if spawner != null else 0,
		"target": target_population(),
		"waves": wave_count,
		"refused": refused_placements,
		"skill": rules.skill_enabled,
		"difficulty": "%.2f acc, %.2f dmg" % [enemy_accuracy_multiplier(), enemy_damage_multiplier()],
		"specials": "%.1f budget, %d spawned, %d denied" % [
			_specials.budget, _specials.spawned, _specials.denied
		],
	}


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()

	out.append("phase        %s for %.1fs" % [phase_name(), _now - _phase_started])
	out.append("stress       %.2f (%s), peak at %.2f" % [
		stress(),
		"worst player" if rules.stress_from_worst_player else "party average",
		rules.peak_stress,
	])
	out.append("population   %d alive, %d wanted" % [
		spawner.world_count() if spawner != null else 0, target_population()
	])
	out.append("travel       %.0f m of %.0f m" % [party_travel(), rules.relax_distance])
	out.append("waves        %d, %d spawned, %d placements refused" % [
		wave_count, spawn_count, refused_placements
	])

	if rules.difficulty_enabled:
		out.append("difficulty   dial %.2f, accuracy x%.2f, damage x%.2f" % [
			DotNpcDirectorDifficulty.dial_of(rules), enemy_accuracy_multiplier(), enemy_damage_multiplier()
		])

	if rules.specials_enabled:
		out.append("specials     %.1f budget, %d spawned, %d denied" % [
			_specials.budget, _specials.spawned, _specials.denied
		])

	for id in _players:
		var player: DotNpcDirectorStress = _players[id]
		out.append("  %-16s stress %.2f  health %.0f%%  travelled %.0f m%s" % [
			String(id), player.value, player.health_fraction * 100.0, player.travelled,
			"  skill x%.2f" % skill_multiplier(id) if rules.skill_enabled else ""
		])

	return out
