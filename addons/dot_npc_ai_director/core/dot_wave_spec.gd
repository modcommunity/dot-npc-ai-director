class_name DotWaveSpec
extends RefCounted

## One wave as resolved for a match: what a game reads at wave start so it never reads yml mid-match.

## The wave or night number, 1-based.
var index: int = 1

## Whether this is the set's final wave.
var is_last: bool = false

## Enemies in the wave (ROUNDS), already scaled by players and difficulty.
var size: int = 0

## NPC profile id -> weight, never empty and never summing to 0.
var pool: Dictionary = {}

## NPC profile id -> count, spread over the wave.
var specials: Dictionary = {}

## `{npc, count, at}` or empty; `at` is the fraction of the wave released before it arrives.
var boss: Dictionary = {}

## Opaque to the director: the game reads what it understands (a restock tier, cash).
var reward: Variant = null

## Multiplier the chosen difficulty puts on the reward.
var reward_mult: float = 1.0

## A line for the HUD, or empty.
var announce: String = ""

## Enemies a second for this wave, or -1 for the schedule's own rising rate.
var release: float = -1.0

## Seconds of quiet before this wave, or -1 for the set's.
var quiet: float = -1.0

var health_mult: float = 1.0
var speed_mult: float = 1.0

## The wave's `extra:` block, merged over the set's, untouched.
var extra: Dictionary = {}


func to_dictionary() -> Dictionary:
	return {
		"index": index, "is_last": is_last, "size": size, "pool": pool.duplicate(true),
		"specials": specials.duplicate(true), "boss": boss.duplicate(true), "reward": reward,
		"reward_mult": reward_mult, "announce": announce, "release": release, "quiet": quiet,
		"health_mult": health_mult, "speed_mult": speed_mult, "extra": extra.duplicate(true),
	}


func describe() -> String:
	return "wave %d%s: %d from %s%s%s" % [
		index, " (last)" if is_last else "", size, str(pool),
		", specials %s" % str(specials) if not specials.is_empty() else "",
		", boss %s" % str(boss) if not boss.is_empty() else "",
	]
