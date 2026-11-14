Decides how many enemies are alive and where new ones appear, based on how hard the players are having it. It also has a wave, night and clock scheduler for games where the players hold a place.

Part of TMC's **Dot** collection: modular, MIT-licensed building blocks for games on the TMC platform (only the TMC website back end is closed). It was built with Claude Code and its headless suites pass, but little of it has met real players yet, so expect rough edges and please report what you find.

## How it works

The director loops through four phases:

1. **Build up.** Enemies come in until the players are under enough pressure.
2. **Sustain.** The peak is held for a few seconds.
3. **Fade.** The number of enemies falls back.
4. **Relax.** A quiet stretch that ends only when enough time has passed and the players have moved on far enough.

Pressure is **stress**. It rises when a player loses health or has enemies close by, and drains when nothing happens. A struggling team gets a break sooner, and a team doing well gets more. There is no difficulty setting unless you turn on the optional skill, difficulty and specials rules (off by default, see docs/design.md).

The director only decides how many and where. What an enemy does is up to its brain ([dot-npc-ai](https://github.com/modcommunity/dot-npc-ai) or your own).

## Install

You need [Godot 4.7](https://godotengine.org/download). [dot-bootstrap](https://github.com/modcommunity/dot-bootstrap) clones every project and links the addons for you.

By hand: copy `addons/dot_npc_ai_director/`, [dot-npc](https://github.com/modcommunity/dot-npc)'s `addons/dot_npc/` and [dot-core](https://github.com/modcommunity/dot-core)'s `addons/dot_core/` into your project and enable them in **Project > Project Settings > Plugins**.

## Use

```gdscript
npcs.authoritative = true                     # the DotNpcSpawner. A client's spawner refuses every spawn

var director := DotNpcDirector.new()
director.spawner = npcs
director.population = [&"zombie", &"zombie", &"zombie", &"brute"]   # taken in turn: 1 brute in 4
director.set_spawn_points_from_nav(nav)       # a DotNpcNavData, thinned to one point every 8 m
director.flow = DotNpcDirectorFlow.new(map.route)   # the path through the level, start to finish
add_child(director)

# Every server tick:
for player in players:
    director.report_player(player.id, player.position, player.health / player.max_health)
director.tick(delta)                          # in seconds

# When a player leaves or starts spectating:
director.forget_player(player.id)
```

Report health as a fraction, not as damage. The director works out the damage from the change.

`flow` is the route through the level. With one, the director spawns ahead of the players (40 m by default, `behind_fraction` of spawns from behind) and cleans up enemies they have left behind. Without one it spawns in the middle of its distance band. You can set `spawn_points` yourself instead of using the navigation data.

Spawn points must be inside the min and max distance from every player and, by default, out of sight. The sight check raycasts in the spawner's physics world, so it needs collision. With no physics world every point counts as hidden.

Signals: `phase_changed(from, to)` and `wave_spawned(at, count)`. `describe_lines()` prints phase, stress, population and travel for a console.

## Waves, nights and clocks

`DotNpcDirectorWaves` is a schedule for a team holding a place.

| Style | A horde stretch is | It ends | The quiet between |
| --- | --- | --- | --- |
| `ROUNDS` | a wave: a count of enemies, bigger every wave | when all have come and none are alive | a breather |
| `CYCLE` | a night: a length of time, harder every night | at dawn, whatever is left | a day, with `daylight()` going 0 to 1 and back |
| `CLOCK` | one stretch, harder as it runs (0 seconds is forever) | when the clock runs out | none |

```gdscript
var waves := DotNpcDirectorWaves.new()
waves.style = DotNpcDirectorWaves.Style.ROUNDS
waves.count = 10                 # waves, or nights
waves.quiet_seconds = 30.0       # the breather, or a day
waves.wave_base = 16             # wave 1 for one player; wave_per_player more for each other
waves.stage_changed.connect(func(stage, index): print(waves.stage_name(), " ", index))
waves.finished.connect(func(): print("held"))
waves.begin(players.size())

# Every server tick:
waves.tick(delta, enemies_of_this_wave_alive, players.size())
var n := waves.take(room_for)    # ROUNDS: how many of the wave to spawn now
# ...spawn n; give_back(k) any you could not
```

It spawns nothing itself. It says what is owed and how hard this stretch is (`strength()`, 1 for the first), and your game decides what that means. A wave also ends `overtime_seconds` after its last enemy was released, so an enemy stuck behind a crate cannot hold the breather off forever.

## Settings

Rules live in a `DotNpcDirectorRules` resource on the director's `rules` (a default is made if unset). Settings are layered: inspector defaults, a JSON file, the environment, then the command line. Call `load_layered()` before adding the director:

```gdscript
var rules := DotNpcDirectorRules.new()
rules.load_layered("user://director.json")
director.rules = rules
```

```bash
DOT_DIRECTOR_PEAK_PER_PLAYER=8 godot --headless -- --director-relax-seconds=45
```

Populations are per player, so the same rules suit one player or many.

| Setting | Default | What it does |
| --- | --- | --- |
| `peak_per_player` | 12 | Enemies alive at the peak, per player |
| `build_up_per_player` | 5 | Enemies alive while building up, per player |
| `relax_per_player` | 1.5 | Enemies alive while relaxing, per player |
| `absolute_cap` | 60 | Most enemies alive whatever the player count. Default 60, 0 = unlimited (left to the spawner) |
| `peak_stress` | 0.75 | Stress (0 to 1) that ends the build-up |
| `sustain_seconds` | 4 | How long the peak is held |
| `fade_seconds` | 8 | How long the population takes to fall back |
| `relax_seconds` | 30 | Shortest relax |
| `relax_distance` | 60 | Metres every player must travel before the relax can end |
| `relax_break_stress` | 0.9 | Stress that ends a relax early. 0 turns it off |
| `spawn_min_distance` | 18 | Nearest a spawn may be to a player (m) |
| `spawn_max_distance` | 70 | Furthest a spawn may be (m) |
| `spawn_out_of_sight` | true | Only spawn where no player can see |
| `spawn_ahead` | 40 | How far ahead along the route to prefer (m) |
| `behind_fraction` | 0.2 | Share of spawns allowed behind the players |
| `spawn_burst` | 3 | Most enemies spawned in one go. Default 3, 0 = unlimited |
| `spawn_interval` | 0.5 | Seconds between spawn attempts |
| `reclaim_interval` | 2.0 | Seconds between clean-ups of enemies left behind. 0 is every tick |
| `stress_decay` | 0.08 | Stress drained per second |
| `stress_per_damage` | 1.4 | Stress added per whole health bar lost |
| `stress_per_threat` | 0.05 | Stress added per second for each enemy nearby |
| `stress_threat_radius` | 8 | What counts as nearby (m) |
| `stress_from_worst_player` | true | Use the most stressed player. Off uses the average |

## Test

```bash
godot --headless --path . --import
godot --headless --path . res://examples/director_selftest.tscn
godot --headless --path . res://examples/director_adapt_selftest.tscn
godot --headless --path . res://examples/waves_selftest.tscn
```

## Licence

MIT. See [LICENSE](LICENSE).
