@tool
extends Node

## What the game tells a [DotNpcDirector]: where things may appear and who is playing.
##
## The part of the director that only records: spawn points and sites, the players'
## positions, health and skill records, and the plain questions about them. The pacing
## that reads these is [DotNpcDirector]'s own.

const CHANNEL := "npc.director"

## Candidate spawn positions, in world space. Usually a map's nav data points.
##
## [b]Given rather than derived, because "where may something appear" is a level design
## question.[/b] A navigable point is not automatically a legal spawn: a game wants its
## horde coming out of the dark corridor rather than out of the safe room, and only the
## map knows which is which. `DotNpcNavData.points` is a reasonable default and a game
## that wants better passes better.
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


## Takes authored spawn sites with per-site rules instead of bare points.
##
## [b]Duck-typed, so this addon does not depend on dot-spawn.[/b] A site is an object with
## properties, or a Dictionary with keys, named [code]position[/code] (Vector3, required),
## [code]enabled[/code], [code]weight[/code] (0 vetoes, above 1 is preferred),
## [code]max_alive[/code] (0 is no limit; needs [member site_alive_fn]), [code]phases[/code]
## (lower-case phase names such as [code]relax[/code]; empty is any),
## [code]sight[/code] ([code]hidden_from_players[/code], [code]visible_to_players[/code] or
## [code]any[/code]) and [code]min_player_distance[/code] / [code]max_player_distance[/code]
## (above 0 replace the rules' band for that site). A DotSpawnPointDef fits as it is.
## Returns how many sites were kept (those with a Vector3 position).
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


## Fills [member spawn_points] from a map's navigation, thinned.
##
## The convenience the field's own documentation has always pointed at: a navigable
## point is the reasonable default and every game was writing this loop. Still an
## explicit call rather than something the director does on its own, because which
## points are [i]legal[/i] spawns is a level design question and a game that wants
## better still passes better.
##
## [b][param minimum_spacing] is not a nicety.[/b] [method choose_spawn_point] walks
## every candidate and, for each one inside the distance band, asks whether a player
## can see it — which is a raycast. A two-metre grid over a modest map is a few
## thousand points, so an unthinned list is a few thousand raycasts per wave, several
## times a minute, on the server. Eight metres is about a room.
##
## [param filter] excludes what the map says an NPC should not be standing on:
## `DotNpcNavFilter.walking_only()` keeps a horde out of the crouch tunnels, and a
## filter with `exclude_flags` set to `AVOID` keeps it off the ledges.
##
## Returns how many points were kept.
func set_spawn_points_from_nav(
	nav: DotNpcNavData,
	minimum_spacing: float = 8.0,
	filter: DotNpcNavFilter = null


## One player's position and health this tick. Called before [method tick].
##
## [b]Health as a fraction, not as a number.[/b] See [DotNpcDirectorStress]: a game that
## had to report damage would have to remember to from every damage path it has, and the
## one it forgets is the one that matters.
func report_player(id: StringName, position: Vector3, health_fraction: float) -> void:
	if not _players.has(id):
		_players[id] = DotNpcDirectorStress.make(id)

	(_players[id] as DotNpcDirectorStress).position = position
	(_players[id] as DotNpcDirectorStress).health_fraction = health_fraction


## Forgets a player. Called when one disconnects or is spectating.
##
## Their stress goes with them, which is right: a director must not keep building toward
## a peak on behalf of somebody who has left, and it must not be stuck in a relax waiting
## for them to travel.
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


## How far the least-travelled player has come since the relax began.
##
## [b]The least, not the most.[/b] The relax ends when the PARTY has moved on; one
## player scouting ahead while the rest hold a door has not moved the party anywhere,
## and ending the relax on their travel drops a wave on three people who are standing
## still.
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
