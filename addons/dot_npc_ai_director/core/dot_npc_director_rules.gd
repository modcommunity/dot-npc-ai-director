@tool
class_name DotNpcDirectorRules
extends DotConfig

## Every number the director is allowed to have an opinion about.
##
## A [DotConfig], so an operator retunes the pacing of a campaign in a file rather than
## in a build — which matters more here than anywhere else in this family, because
## "is it too hard" is a question that is only ever answered by playing it and then
## changing a number.
##
## [b]The shape is the co-operative survival shooters' and the numbers are ours.[/b]
## Build up until the players are having a hard time, hold it there briefly, let it
## fall, then leave them alone for long enough to breathe and move — and then do it
## again. The insight that genre contributed was that the cycle should be driven by an
## estimate of what the players are [i]experiencing[/i] rather than by a timer, because
## a timer gives every player the same game whether they are winning or losing.

@export_group("Population")

## Enemies alive at once during a peak, per player.
##
## [b]Per player, and that is not a detail.[/b] A horde sized for four is a massacre for
## one and a walk for eight, and a director whose population was absolute would need
## retuning for every server size.
@export_range(0.0, 100.0, 0.5) var peak_per_player: float = 12.0

## Enemies alive at once while building up, per player.
@export_range(0.0, 100.0, 0.5) var build_up_per_player: float = 5.0

## Enemies alive at once while relaxing, per player.
##
## [b]Not zero.[/b] A completely empty lull tells the players the game has stopped, and
## they stop moving carefully — so the next peak lands on people who were not playing.
## A handful of wanderers is what keeps a corridor tense.
@export_range(0.0, 100.0, 0.5) var relax_per_player: float = 1.5

## Ceiling on the population whatever the player count says. 0 = the spawner's own.
##
## Belt and braces over [DotNpcLimits]: the spawner refuses past its budget anyway, but
## a director that keeps asking is a director burning a spawn attempt per tick.
@export_range(0, 500, 1) var absolute_cap: int = 60

@export_group("Pacing")

## How much stress ends the build-up, 0 to 1. See [DotNpcDirectorStress].
@export_range(0.0, 1.0, 0.01) var peak_stress: float = 0.75

## Seconds the peak is held once it is reached.
##
## [b]Short.[/b] The peak is the moment the game is hardest and holding it is how a
## director turns a fight into a grind; three to five seconds is a wave breaking.
@export_range(0.0, 60.0, 0.5) var sustain_seconds: float = 4.0

## Seconds the population takes to fall from the peak back to the relax figure.
@export_range(0.0, 120.0, 0.5) var fade_seconds: float = 8.0

## Least seconds of quiet before the build-up may start again.
@export_range(0.0, 300.0, 1.0) var relax_seconds: float = 30.0

## How far the players must travel during the relax before it may end, in metres.
##
## [b]Distance as well as time, and the pair is the point.[/b] Time alone lets a team
## that has stopped to argue about a door be attacked on schedule; distance alone lets a
## team that is sprinting be attacked every few seconds. Both must be satisfied.
@export_range(0.0, 2000.0, 5.0) var relax_distance: float = 60.0

## How much stress ends a relax early, 0 to 1. 0 disables it.
##
## Something has gone wrong that the director did not cause — a player fell, or walked
## into what was left of the last wave. Left alone, the pacing would keep spawning into
## a fight that is already happening.
@export_range(0.0, 1.0, 0.01) var relax_break_stress: float = 0.9

@export_group("Where")

## Nearest a spawn may be to any player, in metres.
##
## [b]The single most important number for how a director FEELS.[/b] Too near and things
## appear in front of people, which reads as cheating; too far and the pressure arrives
## a minute after it was decided on.
@export_range(0.0, 500.0, 1.0) var spawn_min_distance: float = 18.0

@export_range(0.0, 2000.0, 1.0) var spawn_max_distance: float = 70.0

## Whether a spawn point must be out of every player's sight.
@export var spawn_out_of_sight: bool = true

## How far ahead along the players' route the director prefers to spawn, in metres.
##
## Ahead rather than behind, because being surrounded is a thing a game should do
## deliberately and rarely. A director that spawned evenly around the party makes
## retreating impossible, which removes the only decision the players had.
@export_range(0.0, 1000.0, 1.0) var spawn_ahead: float = 40.0

## Fraction of spawns allowed to come from behind, 0 to 1.
@export_range(0.0, 1.0, 0.01) var behind_fraction: float = 0.2

@export_group("Rate")

## Most enemies the director will spawn in one tick.
##
## [b]A wave arrives over a second or two, not in one frame.[/b] Twelve bodies
## instantiated in one tick is a visible hitch on any machine, and it is the frame the
## player is about to need.
@export_range(1, 50, 1) var spawn_burst: int = 3

## Seconds between the director's spawn attempts.
@export_range(0.0, 10.0, 0.05) var spawn_interval: float = 0.5

## Seconds between the director's reclaim passes. 0 = every tick.
##
## Far rarer than spawning: reclaiming walks the population and asks where everybody is,
## and nothing about that answer changes in a tenth of a second.
@export_range(0.0, 60.0, 0.1) var reclaim_interval: float = 2.0

@export_group("Stress")

## How fast stress decays with nothing happening, per second.
@export_range(0.0, 1.0, 0.01) var stress_decay: float = 0.08

## Stress added per point of health lost, as a fraction of a player's maximum.
@export_range(0.0, 10.0, 0.05) var stress_per_damage: float = 1.4

## Stress added per second per enemy within [member stress_threat_radius].
@export_range(0.0, 1.0, 0.005) var stress_per_threat: float = 0.05

@export_range(0.0, 100.0, 0.5) var stress_threat_radius: float = 8.0

## How a party's stress is combined: the worst player's, or the average.
##
## [b]The worst, by default, and it is a real design position.[/b] A director on the
## average keeps piling on while one player is being torn apart, because three healthy
## players hide them. In a co-op game the person having the worst time is the one whose
## experience decides whether the game was any good.
@export var stress_from_worst_player: bool = true

@export_group("Skill")

## Whether each player's recent record scales their share of the peak. Off = no change.
@export var skill_enabled: bool = false

## Lowest and highest multiplier the skill estimate may put on a player's peak.
@export_range(0.1, 1.0, 0.01) var skill_min: float = 0.7
@export_range(1.0, 3.0, 0.01) var skill_max: float = 1.3

## Share of each new sample folded into the estimate, 0 to 1. Small moves slowly.
@export_range(0.01, 1.0, 0.01) var skill_smoothing: float = 0.1

## Seconds between samples; each folds the events since the last one into the estimate.
@export_range(1.0, 120.0, 1.0) var skill_sample_seconds: float = 10.0

## Seconds a player is observed before the estimate counts in full; a new player is 1.0.
@export_range(0.0, 1800.0, 5.0) var skill_warmup_seconds: float = 120.0

## Health bars lost per minute that count as an average player, so the estimate is 1.0.
@export_range(0.05, 20.0, 0.05) var skill_reference_load: float = 1.0

## Load added per death per minute, in the same unit as damage taken per minute.
@export_range(0.0, 20.0, 0.1) var skill_death_weight: float = 2.0

## Load removed per revive performed per minute.
@export_range(0.0, 20.0, 0.1) var skill_revive_weight: float = 0.5

## Load removed per kill per minute. 0 ignores kills, which is the default on purpose.
@export_range(0.0, 5.0, 0.01) var skill_kill_weight: float = 0.0

@export_group("Difficulty")

## Whether the difficulty multipliers are published. Off = both read 1.0.
@export var difficulty_enabled: bool = false

## Named preset: easy, normal, hard or nightmare. See [DotNpcDirectorDifficulty].
@export var difficulty_preset: String = "normal"

## Numeric dial, 1.0 being normal. Negative = use the preset instead.
@export_range(-1.0, 4.0, 0.05) var difficulty_dial: float = -1.0

## Change in enemy accuracy per unit of dial away from 1.0.
@export_range(0.0, 1.0, 0.01) var difficulty_accuracy_per_dial: float = 0.25

## Change in enemy damage per unit of dial away from 1.0.
@export_range(0.0, 1.0, 0.01) var difficulty_damage_per_dial: float = 0.3

@export_group("Specials")

## Whether the kinds in [member special_kinds] are limited by a cooldown budget.
@export var specials_enabled: bool = false

## Population ids that count as special or elite. The rest are never limited.
@export var special_kinds: Array[StringName] = []

## Seconds to earn one special spawn.
@export_range(1.0, 600.0, 1.0) var special_cooldown_seconds: float = 45.0

## Most special spawns that can be banked while none are wanted.
@export_range(1, 20, 1) var special_budget_cap: int = 2

## Most specials alive at once. 0 = no limit beyond the budget.
@export_range(0, 50, 1) var special_max_alive: int = 2


func env_prefix() -> String:
	return "DOT_DIRECTOR_"


func cli_prefix() -> String:
	return "--director-"


func validate() -> DotResult:
	if spawn_min_distance >= spawn_max_distance:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"spawn_min_distance is not below spawn_max_distance, so no spawn point can ever be legal.",
			"%.0f m and %.0f m" % [spawn_min_distance, spawn_max_distance]
		)

	if relax_per_player > peak_per_player:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"A relax with more enemies than a peak inverts the whole cycle.",
			"%.1f against %.1f" % [relax_per_player, peak_per_player]
		)

	if peak_stress <= 0.0:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"A peak stress of zero peaks immediately and for ever.",
			"%.2f" % peak_stress
		)

	if skill_min > 1.0 or skill_max < 1.0:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"The skill bounds must straddle 1.0, or a new player is already scaled.",
			"%.2f to %.2f" % [skill_min, skill_max]
		)

	if difficulty_enabled and difficulty_dial < 0.0 and not DotNpcDirectorDifficulty.has_preset(difficulty_preset):
		return DotResult.fail(
			DotError.CODE_INVALID,
			"The difficulty preset is not one of the known names.",
			difficulty_preset
		)

	return DotResult.success(null)


func describe_summary() -> String:
	return "peak %.0f/player at %.0f%% stress, %.0fs sustain, %.0fs fade, %.0fs relax" % [
		peak_per_player, peak_stress * 100.0, sustain_seconds, fade_seconds, relax_seconds
	]
