class_name DotNpcDirectorSkill
extends RefCounted

## A slow estimate of how well one player is doing, as a multiplier on their share of the peak.
## Events fold into an exponential average each sample window, so one bad fight barely moves it.

## The smoothed multiplier, before warm-up.
var estimate: float = 1.0

## Seconds this player has been observed.
var observed: float = 0.0

var _since_sample: float = 0.0
var _damage: float = 0.0
var _deaths: int = 0
var _revives: int = 0
var _kills: int = 0


## Health bars lost since the last call.
func add_damage(fraction: float) -> void:
	_damage += maxf(fraction, 0.0)


func add_death() -> void:
	_deaths += 1


## This player revived a teammate.
func add_revive() -> void:
	_revives += 1


func add_kill() -> void:
	_kills += 1


func advance(rules: DotNpcDirectorRules, delta: float) -> void:
	observed += delta
	_since_sample += delta

	if _since_sample < rules.skill_sample_seconds:
		return

	var per_minute := 60.0 / _since_sample
	var load_pm := (
		_damage * per_minute
		+ float(_deaths) * per_minute * rules.skill_death_weight
		- float(_revives) * per_minute * rules.skill_revive_weight
		- float(_kills) * per_minute * rules.skill_kill_weight
	)
	load_pm = maxf(load_pm, 0.0)

	var raw := clampf(
		2.0 - load_pm / rules.skill_reference_load, rules.skill_min, rules.skill_max
	)
	estimate = lerpf(estimate, raw, rules.skill_smoothing)

	_since_sample = 0.0
	_damage = 0.0
	_deaths = 0
	_revives = 0
	_kills = 0


## The multiplier to apply: 1.0 for a new player, the estimate once warmed up, always in bounds.
func multiplier(rules: DotNpcDirectorRules) -> float:
	var weight := 1.0

	if rules.skill_warmup_seconds > 0.0:
		weight = clampf(observed / rules.skill_warmup_seconds, 0.0, 1.0)

	return clampf(lerpf(1.0, estimate, weight), rules.skill_min, rules.skill_max)
