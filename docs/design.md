# Design

Why the director is shaped the way it is, and why the obvious alternative is wrong in each case.

## Driven by stress, not a timer

**A director driven by a timer gives every player the same game whether they are winning or losing.** The co-operative survival shooters' insight was to drive it from an estimate of what the players are *experiencing* instead: a team that is struggling gets a moment to recover and a team that is coasting gets something to do, from the same rules, with no difficulty setting.

That estimate is `DotNpcDirectorStress`, and the four phases are what it moves between:

| Phase | |
| --- | --- |
| **BUILD_UP** | Population rising. Ends when stress reaches `peak_stress`. |
| **SUSTAIN** | Held at the peak, briefly. Holding it is how a director turns a fight into a grind; three to five seconds is a wave breaking. |
| **FADE** | Population target interpolates down. It does not *delete* anything: the wave that is alive walks away or is killed, and the director simply stops replacing it. |
| **RELAX** | Quiet. Ends when the party has both waited **and** travelled. |

## Stress

It rises on things that happen *to* a player and decays with nothing happening.

- **Damage is derived from a health fraction, not reported.** A game reporting "this player took 12 damage" has to remember to from every damage path it has (falling, fire, friendly fire, a scripted event) and the one it forgets is the one that matters. A health fraction is a single number a game already has and cannot forget to update.
- **Enemies nearby are a term of their own**, because being surrounded is stressful before anything has hit you. A director without it waits for the first bite before it notices a player is in trouble.
- **It is seeded on the first tick, not at construction.** Without that, a player who joins at half health registers half a health bar of damage on their first tick and the director opens with a peak: the game attacking somebody the instant they connect.
- **`stress_from_worst_player` defaults to on, and it is a design position.** A director on the party average keeps piling on while one player is being torn apart, because three healthy players hide them. In a co-op game the person having the worst time is the one whose experience decides whether the game was any good.

## The relax needs both a clock and a distance

Time alone lets a team that has stopped to argue about a door be attacked on schedule. Distance alone lets a team that is sprinting be attacked every few seconds.

The distance is the **least-travelled** player's, not the most: one player scouting ahead while the rest hold a door has not moved the party anywhere, and ending the relax on their travel drops a wave on three people who are standing still. A player who disconnects is forgotten so they cannot hold a relax open for ever, and vertical travel does not count: a player falling down a lift shaft has made no progress.

`relax_break_stress` is the escape hatch: something has gone wrong the director did not cause, and left alone the pacing would keep spawning into a fight that is already happening. Left-over stress from a peak can therefore break a relax early, so the cycle can go round more than once in a short run.

## Flow: where "ahead" is

`DotNpcDirectorFlow` is the map's critical path as a distance along a line. Without it a director cannot spawn ahead of anybody, and **spawning ahead is most of what makes a director feel like a director**: a director that spawned evenly around the party makes retreating impossible, which removes the only decision the players had.

"Ahead" cannot be a direction (a party walking a horseshoe corridor is facing away from where it is going for half the map), so it has to be a position along the route the level was built around. In this family's code-built maps that route is a handful of constants, and dot-map's catalogue is where a game would keep it.

- **A position is projected onto the nearest segment, not snapped to the nearest point.** A route of six points across a hundred metres would otherwise quantise every player's progress to twenty-metre steps, and the relax distance is measured in tens of metres.
- **A map with no route answers honestly rather than refusing.** Placement degrades to "prefer the middle of the legal distance band", which is what a director in an arena should do anyway.

## Placement is a preference, not the first legal answer

Every candidate is scored and the best wins. An unscored search that takes the first legal point puts every wave in the same doorway, because the point list is in the order the map generated it. The score is "closest to the preferred flow position". A director that simply took the furthest-ahead legal point spawns everything at the end of the map, where it waits for the party for two minutes and then arrives as one enormous wave.

`spawn_min_distance` is **the single most important number for how a director feels**: too near and things appear in front of people, which reads as cheating; too far and the pressure arrives a minute after it was decided on.

## Spawn points are given, not derived

A navigable point is not automatically a legal spawn: a game wants its horde coming out of the dark corridor rather than out of the safe room, and only the map knows which is which. `DotNpcNavData.points` is a reasonable default, and `DotNpcDirector.set_spawn_points_from_nav` fills `spawn_points` from it, as an explicit call, because which points are *legal* is a level design question and a game that wants better passes better.

**The thinning is not a nicety.** `choose_spawn_point` walks every candidate and, for each one inside the distance band, asks whether a player can see it, which is a raycast. A two-metre grid over a modest map is a few thousand points, so an unthinned list is a few thousand raycasts per wave, several times a minute, on the server. `minimum_spacing` defaults to eight metres, about a room.

It takes a `DotNpcNavFilter` for the same reason a path does: `DotNpcNavFilter.walking_only()` keeps a horde out of the crouch tunnels it cannot use, and one excluding `AVOID` keeps it off the ledges.

## Reclaiming is along the route, not by distance

Distance alone reclaims the wave waiting in the room the party is about to walk into, which is the wave that was the whole point. dot-npc's own `reclaim_distance` (in `DotNpcLimits`) is the safety net underneath this, and it stays on.

The director only reclaims what it spawned (`owner_id == &"director"`), because a scripted set piece is not its to tidy away, and it never takes an NPC that has a target. `reclaim_interval` of 0 means every tick, as `spawn_interval` does in `DotNpcLimits`.

## It owns no NPCs

Every spawn, cap, reclaim and budget is `DotNpcSpawner`'s. This decides how many and where, and the spawner is free to refuse. That division is why a game can run a director on some maps and not on others without having two population systems, and it is why `wave_spawned` reports how many actually spawned rather than how many were asked for. The world for the visibility raycast comes from the viewport, because a spawner is a plain `Node`.

The population list is flat and repetition is the weighting: `[&"zombie", &"zombie", &"zombie", &"brute"]` is one brute in four, is obvious at a glance, is a line an operator can edit, and cannot express a weight that does not add up. A table of floats can, and the first thing anybody does with one is get it wrong by 0.05 and never notice. It is walked round-robin rather than sampled, because a random pick from a four-entry list gives four brutes in a row often enough for a player to notice and conclude the director is broken.

## A 2D game drives this unchanged

Everything here (the stress, the phase, the population target, the travel estimate, the scoring of a spawn point) is arithmetic on points in dot-npc's own plane, and dot-npc's plane is XZ with a vertical that a 2D world never moves. So the only line that has to know which dimension it is in is the one that spawns something, and it asks the spawner: `DotNpcSpawner.two_dimensional` routes it through `spawn_2d`.

That is deliberately one branch in one function rather than a flag on this class. A director serves a spawner and a spawner serves a world; asking the thing that knows is cheaper than keeping a second copy of the answer, and this family's most repeated bug is two copies of one list.

## Where a game plugs in

| To change | Where |
| --- | --- |
| Where a wave may appear | `DotNpcDirector.spawn_points`, or `set_spawn_points_from_nav` |
| Every number the director has an opinion about | `DotNpcDirectorRules`, layered like every `DotConfig` |
| What may be spawned, and in what proportion | `DotNpcDirector.population` |
| Where "ahead" is | `DotNpcDirectorFlow`, from the map's critical path |
| What the players are experiencing | `report_player(id, position, health_fraction)` |
| Whether pacing runs at all | `DotNpcDirector.enabled`, for a scripted set piece |
| What a spawned NPC then does | its brain: dot-npc's, or dot-npc-ai's |

## A hold-out is a schedule, not a cycle

The stress cycle paces a team that is moving: its relax ends on distance travelled. A team holding a place does not travel, so its relax never ends, and the cycle has nothing to say about when a hold is won. `DotNpcDirectorWaves` is the other half: a fixed schedule of quiet and horde stretches in one of three styles.

| Style | Horde stretch | Ends | Quiet stretch |
| --- | --- | --- | --- |
| **ROUNDS** | a wave: a count of enemies, `wave_size(k)` | when all of it is released and none is alive, or `overtime_seconds` after the last release | the breather |
| **CYCLE** | a night: a length of time | at dawn, however many are left | the day; `daylight()` ramps through dawn and dusk |
| **CLOCK** | one stretch, harder as it runs; 0 seconds is endless | when the clock runs out | none after the opening one |

- **It spawns nothing.** It says what is owed (`take`, `give_back`) and how hard the stretch is (`strength`); the game spawns, and reports how many of the wave are alive. So a suite runs it with numbers, and a game drives commons, drones or a 2D swarm with it unchanged.
- **A wave is released, never dropped.** `take` hands out what `release_rate()` has accrued, within the room the game says it has. A hundred bodies on one frame is a hitch and a crowd at one door.
- **What could not be spawned is owed again** (`give_back`): a wave that silently shrank is a wave that cleared early.
- **Cleared means dead, with a backstop.** One body stuck behind a crate would otherwise hold the breather off for ever: a wave ends `overtime_seconds` after its last release, or `straggler_seconds` after it once only `straggler_count` are left (two bashing at a door nobody could see through held a school's breather off for minutes). `overtime` says the wave ended on time, and what happens to the stragglers is the game's call.
- **Growth is linear plus a small square** (`growth`, `growth_accel`): linear alone makes the last waves feel like the middle ones.

## Deliberately not here

- **No special enemies.** A boss and the specialist enemies with their own abilities are a game's content. The director only rations which population ids count as special (`DotNpcDirectorSpecials`, off by default).
- **No map events.** Scripted climaxes, safe rooms and finales are level scripting.
- **No item or ammo placement.** Directors in the genre often do that too; here it is dot-loadout's world pickups and a game's decision, and joining them would make this addon depend on one more thing.
- **No difficulty setting by default.** `difficulty_enabled` is off; when on, it only publishes accuracy and damage multipliers (`DotNpcDirectorDifficulty`) for the host to apply, because the director knows no combat addon.
- **No player-versus-player director.** Deciding where a human-controlled special enemy may spawn is a different problem with a fairness constraint this has nothing to say about.

## Optional adaptation (all off by default)

Three groups in `DotNpcDirectorRules`, each with an `_enabled` switch that leaves behaviour untouched while false. **Skill** (`DotNpcDirectorSkill`): per player, events (health lost, `report_death`, `report_revive`, `report_kill`) fold every `skill_sample_seconds` into a smoothed multiplier within `skill_min`..`skill_max`, blended in over `skill_warmup_seconds` from 1.0, and applied to that player's share of `peak_per_player` in SUSTAIN and FADE. **Difficulty**: a preset name or numeric dial becomes `enemy_accuracy_multiplier()` and `enemy_damage_multiplier()`. **Specials**: `special_kinds` spend a budget that refills one per `special_cooldown_seconds` up to `special_budget_cap`, with `special_max_alive` as a second limit; a denied special becomes the next ordinary kind in the population list.
