# dot-npc-ai-director

The co-operative survival shooters' director: population and pacing through a build-up / sustain / fade / relax cycle, driven by an estimate of how hard the players are having it rather than by a timer, spawning ahead of them along their route, out of sight, and reclaiming what is behind.

Read the family [CLAUDE.md](../../CLAUDE.md) first; this file is only what is specific to the director.

**The distributable is `addons/dot_npc_ai_director/`.** It depends on dot-core and dot-npc (both symlinked, `.gitignore`). Not on dot-npc-ai: a director decides *how many* and *where*, and what each NPC does when it gets there is a brain's business. A game can run this over dot-npc's own `DotNpcBrain` and never install a behaviour tree.

```bash
ln -s ../../dot-core/addons/dot_core addons/dot_core
ln -s ../../dot-npc/addons/dot_npc addons/dot_npc
```

## Read before

| Read | Before |
| --- | --- |
| [docs/design.md](docs/design.md) | anything: the phases, stress, the relax, flow, placement, spawn points, reclaiming, the spawner owning every NPC, 2D, where a game plugs in, what is not here |
| [docs/history.md](docs/history.md) | the bugs the suite found while it was written |

## Layout

| Path | What |
| --- | --- |
| `addons/dot_npc_ai_director/core/dot_npc_director_stress.gd` | `DotNpcDirectorStress`: the estimate of what the players are experiencing |
| `addons/dot_npc_ai_director/core/dot_npc_director_flow.gd` | `DotNpcDirectorFlow`: the map's critical path as a distance along a line |
| `addons/dot_npc_ai_director/core/dot_npc_director_rules.gd` | `DotNpcDirectorRules`: every number, a `DotConfig` |
| `addons/dot_npc_ai_director/runtime/dot_npc_director.gd` | `DotNpcDirector`: the phase cycle, placement, reclaiming, `set_spawn_points_from_nav` |
| `examples/director_selftest.tscn` | the suite; non-zero on failure |
| `fixtures/npc_body.tscn` | the NPC body the suite spawns |

## Running and testing

The family's two steps ([game-dev/CLAUDE.md](../../CLAUDE.md#validating-anything)), parsing only this repository's scripts, then `timeout 120 godot --headless --path . res://examples/director_selftest.tscn`.

The suite turns the out-of-sight rule off (`spawn_out_of_sight = false`), and says so: there is no level in it to hide behind, so every point is visible from everywhere and leaving it on would test the raycast rather than the pacing.

## Rules that bite

- Pacing is driven by `DotNpcDirectorStress`, never a timer. [design](docs/design.md#driven-by-stress-not-a-timer)
- Damage is derived from the reported health fraction; stress is seeded on the first tick; `stress_from_worst_player` is on by default on purpose. [design](docs/design.md#stress)
- The relax ends on time **and** the least-travelled player's horizontal distance. [design](docs/design.md#the-relax-needs-both-a-clock-and-a-distance)
- "Ahead" is a position along `DotNpcDirectorFlow`, projected onto the nearest segment; no route degrades, it does not refuse. [design](docs/design.md#flow-where-ahead-is)
- Spawn candidates are scored, never first-legal; `spawn_min_distance` is the number that decides the feel. [design](docs/design.md#placement-is-a-preference-not-the-first-legal-answer)
- Spawn points are given by the game; `set_spawn_points_from_nav` is explicit and thins, because every candidate costs a raycast. [design](docs/design.md#spawn-points-are-given-not-derived)
- Reclaim along the route, only `owner_id == &"director"`, never an NPC with a target; an interval of 0 means every tick. [design](docs/design.md#reclaiming-is-along-the-route-not-by-distance)
- The spawner owns every NPC and may refuse; `wave_spawned` reports what actually spawned. The world comes from the viewport, never `spawner.get_world_3d()`. [design](docs/design.md#it-owns-no-npcs)
- Population is a flat list walked round-robin; repetition is the weighting. [design](docs/design.md#it-owns-no-npcs)
- 2D is the spawner's question (`two_dimensional`), one branch at the spawn; never a flag here. [design](docs/design.md#a-2d-game-drives-this-unchanged)

Deliberately not here: special enemies, map events, item placement, a difficulty setting, a player-versus-player director. [design](docs/design.md#deliberately-not-here)
