class_name DotNpcDirectorStress
extends RefCounted

## How hard one player is having it, 0 to 1. What the whole pacing cycle turns on.
##
## [b]This is the genre's actual insight and it is worth stating plainly.[/b] A director
## driven by a timer gives every player the same game whether they are winning or losing.
## A director driven by an estimate of what the players are *experiencing* gives a team
## that is struggling a moment to recover and a team that is coasting something to do —
## from the same rules, with no difficulty setting.
##
## [b]It rises on things that happen TO a player and decays with nothing happening.[/b]
## Damage is most of it, because damage is the only thing every game already measures the
## same way. Enemies nearby are the rest, because being surrounded is stressful before
## anything has hit you — and a director without that term waits for the first bite
## before it notices a player is in trouble.
##
## Never a wall clock: a player's stress must be the same on a server that stalls for a
## second as on one that does not.

## Who this is. A player id, matching what the game names its candidates with.
var id: StringName = &""

## Where they are. Pushed by the game every tick.
var position: Vector3 = Vector3.ZERO

## Health as a fraction of their own maximum, 0 to 1.
var health_fraction: float = 1.0

## The accumulated figure, 0 to 1.
var value: float = 0.0

## How far this player has travelled since the director last reset it, in metres.
##
## What [member DotNpcDirectorRules.relax_distance] is measured against, and it is
## measured per player rather than for the party: a team that split up has one person
## making progress and the director should notice.
var travelled: float = 0.0

## Health as a fraction, last tick. What damage is derived from.
##
## [b]Derived rather than reported, deliberately.[/b] A game reporting "this player took
## 12 damage" has to remember to, from every damage path it has — falling, fire,
## friendly fire, a scripted event — and the one it forgets is the one that matters. A
## health fraction is a single number a game already has and cannot forget to update.
var _last_health: float = 1.0

var _last_position: Vector3 = Vector3.ZERO

var _seeded: bool = false


static func make(p_id: StringName) -> DotNpcDirectorStress:
	var stress := DotNpcDirectorStress.new()
	stress.id = p_id
	return stress


## Feeds this tick's facts in and advances the estimate.
##
## [param threats] is how many enemies are within the rules' threat radius — counted by
## the director, because it is the thing that has the population.
func advance(
	rules: DotNpcDirectorRules,
	p_position: Vector3,
	p_health_fraction: float,
	threats: int,
	delta: float
) -> float:
	position = p_position
	health_fraction = clampf(p_health_fraction, 0.0, 1.0)

	if not _seeded:
		# Seeded on the first tick rather than at construction.
		#
		# Without this a player joining at half health registers half a health bar of
		# damage on their first tick and the director opens with a peak — which reads
		# as the game attacking somebody the instant they connect.
		_seeded = true
		_last_health = health_fraction
		_last_position = position

	var lost := maxf(_last_health - health_fraction, 0.0)
	_last_health = health_fraction

	# Only the horizontal. A player falling down a lift shaft covers a great deal of
	# distance and has made no progress at all, and the relax should not end because of
	# it.
	var moved := _last_position - position
	moved.y = 0.0
	travelled += moved.length()
	_last_position = position

	value += lost * rules.stress_per_damage
	value += float(threats) * rules.stress_per_threat * delta
	value -= rules.stress_decay * delta

	value = clampf(value, 0.0, 1.0)

	return value


## Puts the travel counter back to zero. Called when a relax begins.
func reset_travel() -> void:
	travelled = 0.0


func describe() -> Dictionary:
	return {
		"player": String(id),
		"stress": "%.2f" % value,
		"health": "%.0f%%" % (health_fraction * 100.0),
		"travelled": "%.0f m" % travelled,
	}
