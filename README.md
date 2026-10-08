This is the **AI director** asset for TMC's **Dot** collection. It is what you add when the game should decide for itself how hard the next two minutes are.

This collection of assets provides modular building blocks for creating games and applications within the TMC ecosystem, ensuring consistency and interoperability across all `dot-*` assets. This includes core functionality, networking, authentication, cloud integration, and more.

**These assets are COMPLETELY OPEN SOURCE**. You are free to use, modify, and distribute them under the terms of the MIT license. The only thing not open source is the back-end web infrastructure. So if you opt into using your own authentication backend instead of integrating with TMC, you will need to build and integrate your own back-end infrastructure.

## From Maintainer & WARNING
This asset, along with all the others, was built initially with **Claude Code** and will continue to be maintained and extended using it. This is because I (`gamemann`) cannot build the entire TMC platform alone (I wish I could lol).

**Please treat this as partially tested.** Every asset has its own headless test suite and those suites pass, but very little of this has been in front of real players yet. Expect rough edges, and please report anything you run into.

I intend on reviewing code, testing, and editing documentation regularly. If you're interested in helping out, please let me know!

## What it does
The director decides how many enemies are alive and where new ones appear, based on how hard the players are having it. It runs in a loop of four phases:

1. **Build up.** Enemies come in until the players are under enough pressure.
2. **Sustain.** The peak is held for a few seconds.
3. **Fade.** The number of enemies falls back.
4. **Relax.** A quiet stretch, which only ends when enough time has passed **and** the players have moved on far enough.

Pressure is measured as **stress**: it goes up when a player loses health or has enemies close by, and drains when nothing is happening. A team that is struggling gets a break sooner, and a team that is doing well gets more to deal with. There is no difficulty setting.

The director picks how many and where. What an enemy does once it is there is up to its brain ([dot-npc-ai](https://github.com/modcommunity/dot-npc-ai), or your own).

## Getting started
You need [Godot 4.7](https://godotengine.org/download). The easiest way to get this addon and the ones it needs is [dot-bootstrap](https://github.com/modcommunity/dot-bootstrap), which clones every project and links the addons into each one.

To add it to your own project by hand, copy `addons/dot_npc_ai_director/`, [dot-npc](https://github.com/modcommunity/dot-npc)'s `addons/dot_npc/` and [dot-core](https://github.com/modcommunity/dot-core)'s `addons/dot_core/` into it, and enable them in **Project → Project Settings → Plugins**.

## Using it

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

Health is reported as a **fraction**, not as damage. The director works out the damage from the change, so your game does not have to report it from every place that deals damage.

`flow` is the route through the level. With one, the director spawns ahead of the players (40 m by default, and only 1 spawn in 5 from behind) and cleans up enemies the players have left behind. Without one, as in an arena, it spawns in the middle of its distance band. You can also set `spawn_points` yourself instead of reading them from the navigation.

A spawn point must be between 18 m and 70 m from every player and, by default, out of their sight. The sight check uses raycasts in the spawner's physics world, so it needs a level with collision. With no physics world every point counts as hidden.

Signals: `phase_changed(from, to)` and `wave_spawned(at, count)`. `describe_lines()` prints the phase, stress, population and travel for a console.

## Settings
The rules live in a `DotNpcDirectorRules` resource, set on the director's `rules` (it makes a default one if you do not). Like every Dot config it is layered: inspector defaults, then a JSON file, then the environment, then the command line. Call `load_layered()` on it before adding the director:

```gdscript
var rules := DotNpcDirectorRules.new()
rules.load_layered("user://director.json")
director.rules = rules
```

```bash
DOT_DIRECTOR_PEAK_PER_PLAYER=8 godot --headless -- --director-relax-seconds=45
```

Populations are **per player**, so the same rules work for one player or eight.

| Setting | Default | What it does |
| --- | --- | --- |
| `peak_per_player` | 12 | Enemies alive at the peak, per player |
| `build_up_per_player` | 5 | Enemies alive while building up, per player |
| `relax_per_player` | 1.5 | Enemies alive while relaxing, per player. A few keep it tense |
| `absolute_cap` | 60 | Most enemies alive whatever the player count. 0 leaves it to the spawner |
| `peak_stress` | 0.75 | Stress (0 to 1) that ends the build-up |
| `sustain_seconds` | 4 | How long the peak is held |
| `fade_seconds` | 8 | How long the population takes to fall back |
| `relax_seconds` | 30 | Shortest relax |
| `relax_distance` | 60 | How far (in metres) every player must travel before the relax can end |
| `relax_break_stress` | 0.9 | Stress that ends a relax early, because a fight has started anyway. 0 turns it off |
| `spawn_min_distance` | 18 | Nearest a spawn may be to a player |
| `spawn_max_distance` | 70 | Furthest a spawn may be |
| `spawn_out_of_sight` | true | Only spawn where no player can see |
| `spawn_ahead` | 40 | How far ahead along the route to prefer spawning |
| `behind_fraction` | 0.2 | Share of spawns allowed behind the players |
| `spawn_burst` | 3 | Most enemies spawned in one go, so a wave does not cause a hitch |
| `spawn_interval` | 0.5 | Seconds between spawn attempts |
| `reclaim_interval` | 2.0 | Seconds between clean-ups of enemies left behind. 0 is every tick |
| `stress_decay` | 0.08 | How much stress drains per second |
| `stress_per_damage` | 1.4 | Stress added per whole health bar lost |
| `stress_per_threat` | 0.05 | Stress added per second for each enemy nearby |
| `stress_threat_radius` | 8 | What counts as nearby, in metres |
| `stress_from_worst_player` | true | Use the most stressed player. Off uses the average |

## Testing

```bash
godot --headless --path . --import
godot --headless --path . res://examples/director_selftest.tscn
```

## License
MIT. See [LICENSE](LICENSE).
