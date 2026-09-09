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
## [b]The shape is Left 4 Dead's and the numbers are ours.[/b] Build up until the
## players are having a hard time, hold it there briefly, let it fall, then leave them
## alone for long enough to breathe and move — and then do it again. Valve's insight was
## that the cycle should be driven by an estimate of what the players are *experiencing*
## rather than by a timer, because a timer gives every player the same game whether they
## are winning or losing.

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

	return DotResult.success(null)


func describe_summary() -> String:
	return "peak %.0f/player at %.0f%% stress, %.0fs sustain, %.0fs fade, %.0fs relax" % [
		peak_per_player, peak_stress * 100.0, sustain_seconds, fade_seconds, relax_seconds
	]
