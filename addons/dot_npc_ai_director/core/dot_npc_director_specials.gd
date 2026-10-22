class_name DotNpcDirectorSpecials
extends RefCounted

## A cooldown budget for special and elite spawns: one is earned per cooldown, up to a cap.

## Spawns currently available.
var budget: float = 0.0

var spawned: int = 0
var denied: int = 0


## Starts with a full budget so the first special is not delayed.
func reset(rules: DotNpcDirectorRules) -> void:
	budget = float(rules.special_budget_cap)
	spawned = 0
	denied = 0


func advance(rules: DotNpcDirectorRules, delta: float) -> void:
	budget = minf(budget + delta / rules.special_cooldown_seconds, float(rules.special_budget_cap))


## Whether one more special may spawn given [param alive] already out.
func allows(rules: DotNpcDirectorRules, alive: int) -> bool:
	if budget < 1.0:
		return false

	return rules.special_max_alive <= 0 or alive < rules.special_max_alive


func spend() -> void:
	budget = maxf(budget - 1.0, 0.0)
	spawned += 1
