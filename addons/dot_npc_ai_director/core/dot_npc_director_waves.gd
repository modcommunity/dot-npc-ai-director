class_name DotNpcDirectorWaves
extends RefCounted

## A hold-out's schedule: quiet stretches and horde stretches, in order, until it is over.
##
## [DotNpcDirector] paces a team that is MOVING: it builds up ahead of them and lets them
## breathe once they have gone far enough. A team that is holding a place does not move, so a
## relax that waits for distance never ends and the director has nothing to say about when the
## hold is won. This is the other half: a fixed schedule a game runs a hold-out on, in one of
## three styles a server owner picks.
##
## [codeblock]
## ROUNDS   quiet, wave 1, quiet, wave 2 ... wave N: each wave a COUNT of enemies, cleared
##          by killing them, each bigger than the last; the quiet between is the breather
## CYCLE    day, night 1, day, night 2 ... night N: each night a length of TIME, survived
##          rather than cleared, each harder than the last; the day is the breather
## CLOCK    one stretch of time, harder as it goes (0 seconds: as long as anybody lasts)
## [/codeblock]
##
## [b]It spawns nothing and owns nothing.[/b] It says what stage the hold is in, how much of
## a wave is still owed ([method take]), and how hard this stretch is ([method strength]);
## the game spawns, and tells it how many of the wave are still alive. So the same schedule
## drives a horde of commons, a wave of drones or a 2D swarm, and a suite can run it with
## numbers alone.
##
## [b]A wave is released, not dropped.[/b] [method take] hands out the wave a few at a time
## at [method release_rate], which rises with the wave: wave 1 trickles in and lets a team
## learn the doors, wave 10 arrives as a flood. A game that spawned a whole wave on its first
## tick would be spawning a hundred bodies in one frame, and every one of them at the same
## door.
##
## [b]Cleared means dead, with a backstop.[/b] A ROUNDS wave ends when all of it has been
## released and none of it is left alive. One body stuck behind a crate would then hold the
## breather off for ever, so a wave also ends [member overtime_seconds] after its last
## release, and the stage change says so ([member overtime]); what to do with the stragglers
## is the game's call.

enum Style { ROUNDS, CYCLE, CLOCK }

enum Stage {
	## Not started, or stopped.
	IDLE,
	## A breather between waves, or a day.
	QUIET,
	## A wave, a night, or the clock running.
	HORDE,
	## The last wave cleared, the last night survived, the clock run out.
	DONE,
}

const STYLE_NAMES := ["rounds", "cycle", "clock"]
const STAGE_NAMES := ["idle", "quiet", "horde", "done"]

## The stage changed. [param index] is the wave or night it belongs to (1-based): a QUIET
## stage carries the number of the wave that follows it.
signal stage_changed(stage: int, index: int)

## The hold is over and held. Emitted once, with the change to DONE.
signal finished()

# --- The schedule ---------------------------------------------------------------------------

var style: int = Style.ROUNDS

## Waves (ROUNDS) or nights (CYCLE). CLOCK has one stretch whatever this says.
var count: int = 10

## Seconds of quiet before the first wave, night or clock: time to find the doors.
var first_quiet_seconds: float = 30.0

## Seconds of quiet between waves (the breather), or of day between nights.
var quiet_seconds: float = 30.0

## Seconds a night lasts (CYCLE), or the whole hold (CLOCK; 0 for as long as anybody lasts).
## ROUNDS waves have no length: they last until they are cleared.
var horde_seconds: float = 150.0

# --- How big, how fast, how much harder -----------------------------------------------------

## ROUNDS: the first wave's size for one player, and how many more for each further player.
var wave_base: int = 16
var wave_per_player: int = 4

## How much harder each wave or night is than the first, as a fraction of it: wave k is
## `1 + growth * (k - 1) + growth_accel * (k - 1)^2` times wave 1. Linear alone makes the
## last waves feel like the middle ones; the small square term is what makes wave 10 a wall.
var growth: float = 0.25
var growth_accel: float = 0.02

## ROUNDS: enemies released a second in wave 1, and how much faster each later wave is (a
## fraction of the first).
var release_base: float = 1.5
var release_growth: float = 0.12

## ROUNDS: seconds after a wave's last release that it counts as cleared whatever is alive.
var overtime_seconds: float = 150.0

## CYCLE: seconds of a day that are dawn and dusk, over which [method daylight] ramps.
var twilight_seconds: float = 10.0

# --- Where it is ----------------------------------------------------------------------------

var stage: int = Stage.IDLE

## The wave or night in play or coming next, 1-based. 0 before the first.
var index: int = 0

## Seconds in the current stage, and since the hold began.
var stage_elapsed: float = 0.0
var elapsed: float = 0.0

## ROUNDS: this wave's size, how many of it have been handed out, and seconds since the last.
var budget: int = 0
var sent: int = 0
var since_last_sent: float = 0.0

## Whether the last wave ended on [member overtime_seconds] rather than by being cleared.
var overtime: bool = false

## How many were alive at the last [method tick]: what [method remaining] counts.
var alive: int = 0

## Players at the last [method begin] or wave start, which sizes the waves.
var players: int = 1

var _owed: float = 0.0

## Whether the quiet in play is the opening one, which has its own length.
var _first_quiet_pending: bool = false


## Checks the schedule. A game calls this before [method begin], with the numbers its
## operator set.
func validate() -> DotResult:
	if style < Style.ROUNDS or style > Style.CLOCK:
		return DotResult.fail(DotError.CODE_INVALID, "style is %d; it is 0 rounds, 1 cycle or 2 clock" % style)

	if style != Style.CLOCK and count < 1:
		return DotResult.fail(DotError.CODE_INVALID, "a hold of %s needs at least one" % ("waves" if style == Style.ROUNDS else "nights"))

	if style == Style.CYCLE and horde_seconds <= 0.0:
		return DotResult.fail(DotError.CODE_INVALID, "a night needs a length")

	if style == Style.ROUNDS and wave_base + wave_per_player <= 0:
		return DotResult.fail(DotError.CODE_INVALID, "a wave of nobody is not a wave")

	if quiet_seconds < 0.0 or first_quiet_seconds < 0.0 or release_base <= 0.0:
		return DotResult.fail(DotError.CODE_INVALID, "negative quiet, or a release rate of nothing")

	return DotResult.success(self)


## Starts the hold for [param p_players]. The first stage is the opening quiet, or the first
## horde when there is none.
func begin(p_players: int) -> void:
	players = maxi(p_players, 1)
	index = 0
	elapsed = 0.0
	alive = 0
	overtime = false

	if first_quiet_seconds > 0.0:
		_first_quiet_pending = true
		_enter(Stage.QUIET, 1)
	else:
		_start_horde(1)


## Stops it where it is. Nothing more is owed.
func stop() -> void:
	budget = 0
	sent = 0
	_owed = 0.0
	stage = Stage.IDLE


## One step. [param p_alive] is how many of the current wave are still alive (ROUNDS; the
## other styles may pass anything), [param p_players] how many players there are now: a wave
## is sized when it starts, so somebody joining mid-wave makes the next one bigger, not this.
func tick(delta: float, p_alive: int, p_players: int) -> void:
	if stage == Stage.IDLE or stage == Stage.DONE:
		return

	alive = maxi(p_alive, 0)
	players = maxi(p_players, 1)
	elapsed += delta
	stage_elapsed += delta

	match stage:
		Stage.QUIET:
			if stage_elapsed >= _quiet_length():
				_start_horde(index)
		Stage.HORDE:
			match style:
				Style.ROUNDS:
					_owed = minf(_owed + release_rate() * delta, float(budget - sent))
					if sent >= budget:
						since_last_sent += delta
						if alive <= 0:
							_end_horde(false)
						elif since_last_sent >= overtime_seconds:
							_end_horde(true)
				Style.CYCLE:
					if stage_elapsed >= horde_seconds:
						_end_horde(false)
				Style.CLOCK:
					if horde_seconds > 0.0 and stage_elapsed >= horde_seconds:
						_end_horde(false)


## ROUNDS: up to [param most] of the wave to release now, taken off what is owed. The game
## passes how many it has room for (its own cap on the living minus those alive), and spawns
## what this returns. 0 outside a ROUNDS wave.
func take(most: int) -> int:
	if stage != Stage.HORDE or style != Style.ROUNDS or most <= 0:
		return 0

	var n := mini(mini(int(floor(_owed)), budget - sent), most)

	if n <= 0:
		return 0

	sent += n
	_owed -= float(n)
	since_last_sent = 0.0
	return n


## Gives back [param n] that were taken and could not be spawned (no room, nowhere to put
## them), so they are owed again rather than lost: a wave that silently shrank is a wave
## that cleared early.
func give_back(n: int) -> void:
	if n <= 0:
		return

	sent = maxi(sent - n, 0)
	_owed += float(n)


## The size of wave [param k] for [param p_players] players.
func wave_size(k: int, p_players: int) -> int:
	var team := wave_base + wave_per_player * maxi(p_players - 1, 0)
	return maxi(int(round(float(team) * strength_of(k))), 1)


## How hard wave or night [param k] is against the first: 1 for the first.
func strength_of(k: int) -> float:
	var step := float(maxi(k - 1, 0))
	return 1.0 + growth * step + growth_accel * step * step


## How hard the stretch in play is. CLOCK grows with the clock instead: one step for every
## [member quiet_seconds] + 60 seconds held, so a ten-minute hold climbs like ten waves.
func strength() -> float:
	if style == Style.CLOCK:
		var step := maxf(stage_elapsed if stage == Stage.HORDE else 0.0, 0.0) / maxf(quiet_seconds + 60.0, 1.0)
		return 1.0 + growth * step + growth_accel * step * step

	return strength_of(maxi(index, 1))


## ROUNDS: enemies a second this wave is released at.
func release_rate() -> float:
	return release_base * (1.0 + release_growth * float(maxi(index - 1, 0)))


## Seconds until this stage ends, or -1 when it ends on something other than time (a ROUNDS
## wave, an endless clock).
func seconds_left() -> float:
	match stage:
		Stage.QUIET:
			return maxf(_quiet_length() - stage_elapsed, 0.0)
		Stage.HORDE:
			if style == Style.ROUNDS or (style == Style.CLOCK and horde_seconds <= 0.0):
				return -1.0
			return maxf(horde_seconds - stage_elapsed, 0.0)

	return -1.0


## ROUNDS: what is left of the wave in play: owed, and alive. -1 in the other styles.
func remaining() -> int:
	if style != Style.ROUNDS:
		return -1

	if stage != Stage.HORDE:
		return 0

	return maxi(budget - sent, 0) + alive


## How much of the light is day, 0 (night) to 1, for a CYCLE: the days ramp up through dawn
## and down through dusk over [member twilight_seconds]. -1 for the other styles, which
## keep whatever light the map has.
func daylight() -> float:
	if style != Style.CYCLE:
		return -1.0

	if stage != Stage.QUIET:
		return 0.0 if stage == Stage.HORDE else 1.0 if stage == Stage.DONE else 0.0

	var length := _quiet_length()
	var ramp := minf(twilight_seconds, length * 0.5)

	if ramp <= 0.0:
		return 1.0

	return clampf(minf(stage_elapsed / ramp, (length - stage_elapsed) / ramp), 0.0, 1.0)


## Whether the wave or night in play is the last.
func is_last() -> bool:
	return style == Style.CLOCK or index >= count


func stage_name() -> String:
	return STAGE_NAMES[clampi(stage, 0, STAGE_NAMES.size() - 1)]


func style_name() -> String:
	return STYLE_NAMES[clampi(style, 0, STYLE_NAMES.size() - 1)]


## A style from its name (`rounds`, `cycle`, `clock`, or the game's own words `waves`,
## `nights`, `days`, `timer`), or -1.
static func style_from(text: String) -> int:
	match text.strip_edges().to_lower():
		"rounds", "waves", "0":
			return Style.ROUNDS
		"cycle", "nights", "days", "day_night", "1":
			return Style.CYCLE
		"clock", "timer", "2":
			return Style.CLOCK

	return -1


func _quiet_length() -> float:
	return first_quiet_seconds if _first_quiet_pending else quiet_seconds


func _enter(to: int, k: int) -> void:
	stage = to
	index = k
	stage_elapsed = 0.0
	stage_changed.emit(stage, index)


func _start_horde(k: int) -> void:
	_first_quiet_pending = false
	budget = wave_size(k, players) if style == Style.ROUNDS else 0
	sent = 0
	_owed = 0.0
	since_last_sent = 0.0
	overtime = false
	_enter(Stage.HORDE, k)


func _end_horde(over_time: bool) -> void:
	overtime = over_time
	budget = 0
	sent = 0
	_owed = 0.0

	if is_last():
		_enter(Stage.DONE, index)
		finished.emit()
	else:
		_enter(Stage.QUIET, index + 1)


func describe() -> Dictionary:
	var out := {
		"style": style_name(), "stage": stage_name(), "index": index, "count": count,
		"stage_elapsed": snappedf(stage_elapsed, 0.1), "strength": snappedf(strength(), 0.01),
	}

	if style == Style.ROUNDS:
		out["wave"] = "%d sent of %d, %d alive" % [sent, budget, alive]

	return out


func describe_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("waves      %s, %s %d of %d, %.0f s in" % [style_name(), stage_name(), index, count, stage_elapsed])

	if style == Style.ROUNDS and stage == Stage.HORDE:
		lines.append("           %d of %d released, %d alive, %.2f a second" % [sent, budget, alive, release_rate()])

	return lines
