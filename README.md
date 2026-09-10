This is the **AI director** asset for TMC's **Dot** collection. It is what you add when the game should decide for itself how hard the next two minutes are.

This collection of assets provides modular building blocks for creating games and applications within the TMC ecosystem, ensuring consistency and interoperability across all `dot-*` assets. This includes core functionality, networking, authentication, cloud integration, and more.

**These assets are COMPLETELY OPEN SOURCE**. You are free to use, modify, and distribute them under the terms of the MIT license. The only thing not open source is the back-end web infrastructure. So if you opt into using your own authentication backend instead of integrating with TMC, you will need to build and integrate your own back-end infrastructure.

## From Maintainer & WARNING
This asset, along with all the others, was built initially with **Claude Code** and will continue to be maintained and extended using it. This is because I (`gamemann`) cannot build the entire TMC platform alone (I wish I could lol).

**Please treat this as partially tested.** Every asset has its own headless test suite and those suites pass, but very little of this has been in front of real players yet. Expect rough edges, and please report anything you run into.

I intend on reviewing code, testing, and editing documentation regularly. If you're interested in helping out, please let me know!

## An AI Director
**The Left 4 Dead director for Godot 4.** Population, pacing and the build-up / sustain
/ fade / relax cycle, driven by an estimate of how hard the players are having it rather
than by a timer.

Depends on **dot-core** and **[dot-npc](https://github.com/modcommunity/dot-npc)**. Not
on `dot-npc-ai`: this decides how many and where, and what each one does when it gets
there is a brain's business.

## Why it is not a spawn timer

A timer gives every player the same game whether they are winning or losing. This is
driven by what the players are actually experiencing — damage taken, enemies close, time
without a break — so a team that is struggling gets a moment to recover and a team that
is coasting gets something to do. Same rules, no difficulty setting.

## Installing

Copy `addons/dot_npc_ai_director/`, `addons/dot_npc/` and
[`dot-core`](https://github.com/modcommunity/dot-core)'s `addons/dot_core/` into your
project, and enable them in *Project → Project Settings → Plugins*.

## Five minutes

```gdscript
var director := DotNpcDirector.new()
director.spawner = npcs                               # a DotNpcSpawner
director.rules = DotNpcDirectorRules.new()
director.population = [&"zombie", &"zombie", &"zombie", &"brute"]   # 1 brute in 4
director.spawn_points = nav.points                    # or the map's own list
director.flow = DotNpcDirectorFlow.new(map.critical_path)
add_child(director)

# Every simulated tick:
for player in players:
    director.report_player(player.id, player.position, player.health / player.max_health)

director.tick(delta)
```

Health as a **fraction**, not a damage number: a game that had to report damage would
have to remember to from every damage path it has, and the one it forgets is the one
that matters.

## The relax needs both a clock and a distance

Time alone lets a team that has stopped to argue about a door be attacked on schedule.
Distance alone lets a team that is sprinting be attacked every few seconds. And the
distance is the **least-travelled** player's, because one person scouting ahead has not
moved the party anywhere.

## Validating

```bash
godot --headless --path . --import
timeout 120 godot --headless --path . res://examples/director_selftest.tscn
```

52 checks, exits non-zero on failure.

## Licence

MIT.
