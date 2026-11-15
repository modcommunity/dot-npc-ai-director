@tool
extends Node

## What the game tells a [DotNpcDirector]: spawn points and sites, the players' positions, health and
## skill records, and the plain questions about them. The pacing that reads these is [DotNpcDirector]'s own.

const CHANNEL := "npc.director"

## Candidate spawn positions, in world space; usually a map's nav data points. Given, not derived: which
## navigable point is a legal spawn (the dark corridor, not the safe room) is a level design question only the
## map can answer, so `DotNpcNavData.points` is a default and a game that wants better passes better.
var spawn_points: PackedVector3Array = PackedVector3Array()

## Optional per-point rules, parallel to [member spawn_points]; see [method set_sites].
var _sites: Array = []

## Called as [code]site_alive_fn.call(site) -> int[/code]: how many of this site's NPCs are
## alive, for a site's [code]max_alive[/code]. Unset means max_alive is not enforced.
var site_alive_fn: Callable = Callable()

## Called as [code]site_filter.call(site, point) -> bool[/code] after the built-in rules;
## false vetoes the site. For a game's own rule (a team, a class, a door state).
var site_filter: Callable = Callable()

## The site the last successful [method choose_spawn_point] used, or null.
var last_site: Variant = null

## Score, in metres of preference, that one unit of a site's [code]weight[/code] above 1 is worth.
const SITE_WEIGHT_METRES := 10.0

## Player id -> DotNpcDirectorStress.
var _players: Dictionary = {}

## Player id -> DotNpcDirectorSkill. Empty while skill is off.
var _skills: Dictionary = {}


## Takes authored sites (duck-typed objects or Dictionaries, so no dot-spawn dependency; a DotSpawnPointDef fits) with
## [code]position[/code] (Vector3, required), [code]enabled[/code], [code]weight[/code] (0 vetoes, above 1 preferred), [code]max_alive[/code] (0 none; needs [member site_alive_fn]), [code]phases[/code] (lower-case, empty is any),
## [code]sight[/code] (hidden_from_players / visible_to_players / any), [code]min_player_distance[/code] / [code]max_player_distance[/code] (above 0 replace the band). Returns how many had a Vector3 position.
func set_sites(sites: Array) -> int:
	var kept: Array = []
	var points := PackedVector3Array()

	for site in sites:
		var position: Variant = _site_get(site, "position", null)

		if position is Vector3:
			kept.append(site)
			points.append(position)

	_sites = kept
	spawn_points = points
	return kept.size()


static func _site_get(site: Variant, key: String, fallback: Variant) -> Variant:
	if site is Dictionary:
		return (site as Dictionary).get(key, fallback)

	if site is Object:
		var value: Variant = (site as Object).get(key)
		return fallback if value == null else value

	return fallback


## Fills [member spawn_points] from a map's navigation, thinned to [param minimum_spacing] (not a nicety: each candidate in
## band costs [method choose_spawn_point] a raycast, so a few thousand unthinned points is a few thousand per wave; 8 m is a room).
## [param filter] drops what an NPC should not stand on (`DotNpcNavFilter.walking_only()`, `exclude_flags = AVOID`). Returns how many were kept.
func set_spawn_points_from_nav(
	nav: DotNpcNavData,
	minimum_spacing: float = 8.0,
	filter: DotNpcNavFilter = null
) -> int:
	spawn_points = PackedVector3Array()

	if nav == null or nav.points.is_empty():
		return 0

	var spacing_sq := minimum_spacing * minimum_spacing

	for i in nav.points.size():
		if filter != null and not filter.passes(nav.area_of(i), nav.flags_of(i)):
			continue

		var point := nav.points[i]
		var too_close := false

		for kept in spawn_points:
			if kept.distance_squared_to(point) < spacing_sq:
				too_close = true
				break

		if too_close:
			continue

		spawn_points.append(point)

	DotLog.info(CHANNEL, "spawn points taken from navigation", {
		"map": String(nav.map_id),
		"points": nav.points.size(),
		"kept": spawn_points.size(),
		"spacing": minimum_spacing,
	})

	return spawn_points.size()


## One player's position and health this tick, called before [method tick]. Health as a fraction, not damage
## reports: see [DotNpcDirectorStress]; the damage path a game forgets to report from is the one that matters.
func report_player(id: StringName, position: Vector3, health_fraction: float) -> void:
	if not _players.has(id):
		_players[id] = DotNpcDirectorStress.make(id)

	(_players[id] as DotNpcDirectorStress).position = position
	(_players[id] as DotNpcDirectorStress).health_fraction = health_fraction


## Forgets a player who disconnected or is spectating, stress and all: a director must not build a peak for
## somebody who left, nor sit in a relax waiting for them to travel.
func forget_player(id: StringName) -> bool:
	_skills.erase(id)
	return _players.erase(id)


## A player died. Feeds the skill estimate; no effect while skill is off.
func report_death(id: StringName) -> void:
	_skill_of(id).add_death()


## A player revived a teammate. Feeds the skill estimate.
func report_revive(id: StringName) -> void:
	_skill_of(id).add_revive()


## A player killed an enemy. Feeds the skill estimate (weighted 0 by default).
func report_kill(id: StringName) -> void:
	_skill_of(id).add_kill()


## The skill record of a player, made on first use.
func _skill_of(id: StringName) -> DotNpcDirectorSkill:
	if not _skills.has(id):
		_skills[id] = DotNpcDirectorSkill.new()

	return _skills[id]


func player_count() -> int:
	return _players.size()


## How far the least-travelled player has come since the relax began. The least, not the most: one player
## scouting ahead while the rest hold a door has not moved the party, and ending the relax then drops a wave on three
## people standing still.
func party_travel() -> float:
	if _players.is_empty():
		return 0.0

	var least := INF

	for id in _players:
		least = minf(least, (_players[id] as DotNpcDirectorStress).travelled)

	return least


func _distance_to_nearest_player(point: Vector3) -> float:
	var nearest := INF

	for id in _players:
		nearest = minf(nearest, point.distance_to((_players[id] as DotNpcDirectorStress).position))

	return nearest
