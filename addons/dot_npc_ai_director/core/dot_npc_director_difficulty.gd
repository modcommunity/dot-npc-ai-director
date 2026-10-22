class_name DotNpcDirectorDifficulty
extends RefCounted

## Maps a difficulty name or dial to the multipliers a host applies to its enemies.
##
## The director knows no combat addon: it only publishes numbers, and the host feeds them
## to whatever decides accuracy and damage.

## Preset name -> dial value, 1.0 being normal.
const PRESETS := {
	"easy": 0.5,
	"normal": 1.0,
	"hard": 1.5,
	"nightmare": 2.0,
}

const FLOOR := 0.1


static func has_preset(name: String) -> bool:
	return PRESETS.has(name.to_lower())


## The dial a rules object selects: its numeric dial if set, else its preset, else 1.0.
static func dial_of(rules: DotNpcDirectorRules) -> float:
	if not rules.difficulty_enabled:
		return 1.0

	if rules.difficulty_dial >= 0.0:
		return rules.difficulty_dial

	return float(PRESETS.get(rules.difficulty_preset.to_lower(), 1.0))


## Enemy accuracy multiplier; 1.0 when difficulty is off.
static func accuracy(rules: DotNpcDirectorRules) -> float:
	if not rules.difficulty_enabled:
		return 1.0

	return maxf(1.0 + (dial_of(rules) - 1.0) * rules.difficulty_accuracy_per_dial, FLOOR)


## Enemy damage multiplier; 1.0 when difficulty is off.
static func damage(rules: DotNpcDirectorRules) -> float:
	if not rules.difficulty_enabled:
		return 1.0

	return maxf(1.0 + (dial_of(rules) - 1.0) * rules.difficulty_damage_per_dial, FLOOR)
