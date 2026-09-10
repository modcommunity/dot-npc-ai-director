# dot-npc-ai-director

**The Left 4 Dead director.** Population, pacing, and the build-up / sustain / fade /
relax cycle, driven by an estimate of how hard the players are having it rather than by
a timer — spawning ahead of them along their route, out of sight, and reclaiming what is
behind.

Depends on **dot-core and dot-npc**. Not on `dot-npc-ai`: a director decides *how many*
and *where*, and what each NPC does when it gets there is a brain's business. A game can
run this over dot-npc's own `DotNpcBrain` and never install a behaviour tree.

## The one idea

**A director driven by a timer gives every player the same game whether they are winning
or losing.** Valve's insight was to drive it from an estimate of what the players are
*experiencing* instead: a team that is struggling gets a moment to recover and a team
that is coasting gets something to do, from the same rules, with no difficulty setting.

That estimate is `DotNpcDirectorStress`, and the four phases are what it moves between:

| | |
| --- | --- |
| **BUILD_UP** | Population rising. Ends when stress reaches `peak_stress`. |
| **SUSTAIN** | Held at the peak, briefly. Holding it is how a director turns a fight into a grind; three to five seconds is a wave breaking. |
| **FADE** | Population target interpolates down. It does not *delete* anything — the wave that is alive walks away or is killed, and the director simply stops replacing it. |
| **RELAX** | Quiet. Ends when the party has both waited **and** travelled. |

## Stress

It rises on things that happen *to* a player and decays with nothing happening.

- **Damage is derived from a health fraction, not reported.** A game reporting "this
  player took 12 damage" has to remember to from every damage path it has — falling,
  fire, friendly fire, a scripted event — and the one it forgets is the one that matters.
  A health fraction is a single number a game already has and cannot forget to update.
- **Enemies nearby are a term of their own**, because being surrounded is stressful
  before anything has hit you. A director without it waits for the first bite before it
  notices a player is in trouble.
- **It is seeded on the first tick, not at construction.** Without that, a player who
  joins at half health registers half a health bar of damage on their first tick and the
  director opens with a peak — the game attacking somebody the instant they connect.
- **`stress_from_worst_player` defaults to on, and it is a design position.** A director
  on the party average keeps piling on while one player is being torn apart, because
  three healthy players hide them. In a co-op game the person having the worst time is
  the one whose experience decides whether the game was any good.

## The relax needs both a clock and a distance

Time alone lets a team that has stopped to argue about a door be attacked on schedule.
Distance alone lets a team that is sprinting be attacked every few seconds.

And the distance is the **least-travelled** player's, not the most: one player scouting
ahead while the rest hold a door has not moved the party anywhere, and ending the relax
on their travel drops a wave on three people who are standing still. A player who
disconnects is forgotten so they cannot hold a relax open for ever, and vertical travel
does not count — a player falling down a lift shaft has made no progress.

`relax_break_stress` is the escape hatch: something has gone wrong the director did not
cause, and left alone the pacing would keep spawning into a fight that is already
happening.

## Flow: where "ahead" is

`DotNpcDirectorFlow` is the map's critical path as a distance along a line. Without it a
director cannot spawn ahead of anybody, and **spawning ahead is most of what makes a
director feel like a director**: a director that spawned evenly around the party makes
retreating impossible, which removes the only decision the players had.

"Ahead" cannot be a direction — a party walking a horseshoe corridor is facing away from
where it is going for half the map — so it has to be a position along the route the level
was built around. In this family's code-built maps that route is a handful of constants,
and dot-map's catalogue is where a game would keep it.

Two details that matter:

- **A position is projected onto the nearest segment, not snapped to the nearest point.**
  A route of six points across a hundred metres would otherwise quantise every player's
  progress to twenty-metre steps, and the relax distance is measured in tens of metres.
- **A map with no route answers honestly rather than refusing.** Placement degrades to
  "prefer the middle of the legal distance band", which is what a director in an arena
  should do anyway.

## Placement is a preference, not the first legal answer

Every candidate is scored and the best wins. That sounds like the same thing and is not:
an unscored search that takes the first legal point puts every wave in the same doorway,
because the point list is in the order the map generated it.

The score is "closest to the preferred flow position". A director that simply took the
furthest-ahead legal point spawns everything at the end of the map, where it waits for
the party for two minutes and then arrives as one enormous wave.

`spawn_min_distance` is **the single most important number for how a director feels**:
too near and things appear in front of people, which reads as cheating; too far and the
pressure arrives a minute after it was decided on.

**Spawn points are given, not derived.** A navigable point is not automatically a legal
spawn: a game wants its horde coming out of the dark corridor rather than out of the
safe room, and only the map knows which is which. `DotNpcNavData.points` is a reasonable
default and a game that wants better passes better.

### Spawn points can now come from the navigation

The field's own documentation has always said `DotNpcNavData.points` is the reasonable
default, and every game was writing the loop.
`DotNpcDirector.set_spawn_points_from_nav` is that loop, still as an explicit call —
which points are *legal* spawns is a level design question, and a game that wants
better still passes better.

**The thinning is not a nicety.** `choose_spawn_point` walks every candidate and, for
each one inside the distance band, asks whether a player can see it — which is a
raycast. A two-metre grid over a modest map is a few thousand points, so an unthinned
list is a few thousand raycasts per wave, several times a minute, on the server. Eight
metres between kept points is about a room.

It takes a `DotNpcNavFilter` for the same reason a path does:
`DotNpcNavFilter.walking_only()` keeps a horde out of the crouch tunnels it cannot use,
and one excluding `AVOID` keeps it off the ledges.

## Reclaiming is along the route, not by distance

Distance alone reclaims the wave waiting in the room the party is about to walk into,
which is the wave that was the whole point. dot-npc's own `reclaim_distance` is the
safety net underneath this, and it stays on.

The director only reclaims what it spawned — `owner_id == &"director"` — because a
scripted set piece is not its to tidy away, and it never takes an NPC that has a target.

## It owns no NPCs

Every spawn, cap, reclaim and budget is `DotNpcSpawner`'s. This decides how many and
where, and the spawner is free to refuse. That division is why a game can run a director
on some maps and not on others without having two population systems, and it is why
`wave_spawned` reports how many actually spawned rather than how many were asked for.

The population list is flat and repetition is the weighting:
`[&"zombie", &"zombie", &"zombie", &"brute"]` is one brute in four, is obvious at a
glance, is a line an operator can edit, and cannot express a weight that does not add up.
A table of floats can, and the first thing anybody does with one is get it wrong by 0.05
and never notice. It is walked round-robin rather than sampled, because a random pick
from a four-entry list gives four brutes in a row often enough for a player to notice and
conclude the director is broken.

## Two bugs the suite found while this was being written

- **`reclaim_interval` of 0 meant "never".** `spawn_interval` of 0 means "every tick"
  here, in `DotNpcLimits`, and everywhere else in this family — so a game that turned the
  wait off got a director that never reclaimed anything. Two settings named the same way
  meaning opposite things at zero is the kind of difference nobody reads twice.
- **`spawner.get_world_3d()` does not exist.** A `DotNpcSpawner` is a plain `Node`, and
  written as a duck-typed `has_method` branch it does not even compile: GDScript cannot
  infer the type of what such a branch returns. The world comes from the viewport.

And one in the suite, worth as much: **a phase test asserted where the cycle happened to
be at the end of its loop.** Left-over stress from a peak can break a relax early — which
is documented behaviour with its own test — so the party goes round more than once and
the final phase depends on the loop length. It asserts that BUILD_UP was *re-entered*
now, which is what "it begins again" actually means.

## Validating

```bash
cd godot/dot-npc-ai-director
ln -s ../../dot-core/addons/dot_core addons/dot_core   # once
ln -s ../../dot-npc/addons/dot_npc addons/dot_npc      # once

godot --headless --path . --import
find . -name '*.gd' -not -path './.godot/*' -not -path './addons/dot_core/*' \
  -not -path './addons/dot_npc/*' | \
  while read f; do godot --headless --path . --check-only --script "res://${f#./}"; done

timeout 120 godot --headless --path . res://examples/director_selftest.tscn
```

52 checks. Exits non-zero on failure.

The suite turns the out-of-sight rule off, and says so: there is no level in it to be
hidden behind, so every point is visible from everywhere and leaving it on would test
the raycast rather than the pacing.

## Where a game plugs in

| To change | Where |
| --- | --- |
| Where a wave may appear | `DotNpcDirector.spawn_points`, or `set_spawn_points_from_nav` |
| Every number the director has an opinion about | `DotNpcDirectorRules`, layered like every `DotConfig` |
| What may be spawned, and in what proportion | `DotNpcDirector.population` |
| Where things may appear | `DotNpcDirector.spawn_points` |
| Where "ahead" is | `DotNpcDirectorFlow`, from the map's critical path |
| What the players are experiencing | `report_player(id, position, health_fraction)` |
| Whether pacing runs at all | `DotNpcDirector.enabled`, for a scripted set piece |
| What a spawned NPC then does | its brain — dot-npc's, or dot-npc-ai's |

## Things deliberately not here

- **No special infected.** A tank, a smoker and a boomer are a game's content and their
  cooldowns are a game's rules. A director that shipped them would be a game.
- **No map events.** Crescendo events, saferooms and finales are level scripting.
- **No item or ammo placement.** Valve's director does that too; here it is dot-loadout's
  world pickups and a game's decision, and joining them would make this addon depend on
  one more thing.
- **No difficulty setting.** The whole point is that there is not one. A game that wants
  one scales `peak_per_player` and `peak_stress`, which is two numbers in a config file.
- **No player-versus-player director.** Deciding where a human special infected may spawn
  is a different problem with a fairness constraint this has nothing to say about.
- **No 2D.** Everything here is `Vector3`.
