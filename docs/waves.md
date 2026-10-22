# Waves as config (design, not built)

A survival server owner should be able to change what comes, how many, how fast, and what the team is paid, by editing a yml file, and add a new mutant without a code change. Today the numbers live in `ZzConfig` cvars and `ZzSurvival.TWISTS`, and the one NPC mix is hardcoded in the horde. This is the shape that replaces that; it is built on `DotProfile` (dot-core, in progress) and on the schedule that already exists, `DotNpcDirectorWaves`.

## Who owns what

| Piece | Owner | Why |
| --- | --- | --- |
| Tiers, `extends:`, `extra:`, env/cli override, validation of types | dot-core `DotProfileSet` | one layering for the whole family |
| `DotWaveSet` (schema, id lookup, per-wave resolution, validation across files) and `DotNpcDirectorWaves.from_profile()` | **dot-npc-ai-director** (recommended) | it already owns the schedule and the budget/skill/special rules; a new addon would only wrap its one class |
| NPC profile ids (`cfg/game/<game>/npc/<id>.yml`) | dot-npc (`npc` kind) | the director holds ids, never builds an NPC |
| Which wave set a map plays, difficulty, rotation | dot-map `maps.yml` | rotation is already there; the director must not know about maps |
| Match end, then vote | the game, via dot-map's `map_over` and dot-vote | `DotMapSession` emits and does not decide (dot-map `docs/rotation.md`) |
| The kinds, specials, twists, rewards (restock), boss brains | the game | meaning is the game's |

The director takes no dependency on dot-map or dot-match: the game passes a set id and a difficulty in, and the director says `finished`.

## Layers

Same tiers as `DotProfile`, weakest first: schema defaults < `cfg/addons/dot_npc_ai_director/waves/<set>.yml` < `cfg/game/<game>/waves/<set>.yml` < `cfg/server/waves/<set>.yml` < environment < command line. A server owner copies nothing: a file in `cfg/server/waves/` with a few keys overrides those keys of the game's set (`extends:` is implied for the same id). Dictionaries merge by key and lists replace, so waves are a map keyed by number, never a list; otherwise changing wave 5 would mean restating all ten.

Environment and command line use the profile prefix: `PROFILE_WAVES_SCHOOL_HOLD_COUNT=12`, `--profile.waves/school_hold.count=12`. Only scalars in the schema can be overridden that way; wave entries are file-only.

## The schema

Two levels. The set holds the schedule and defaults; `waves:` holds per-wave deviations. A wave with no entry is generated from the formula in `DotNpcDirectorWaves` (`wave_base`, `wave_per_player`, `growth`, `growth_accel`), so a ten-wave hold is five lines and a hand-made campaign is as long as its author likes.

```yaml
# cfg/addons/dot_npc_ai_director/waves/hold.yml  (the addon's neutral default)
style: rounds            # rounds | cycle | clock (DotNpcDirectorWaves.Style)
count: 10
first_quiet: 30          # seconds
quiet: 30                # the break between waves
size: {base: 16, per_player: 4}
growth: {linear: 0.25, accel: 0.02}
release: {base: 1.5, growth: 0.12}        # enemies a second, rising
overtime: {seconds: 150, stragglers: 3, straggler_seconds: 30}
alive_cap: {base: 24, per_player: 6}
pool:                    # the default mix, weights not percentages
  common: 10
director:                # optional; absent means the set is a pure schedule
  skill: true            # use DotNpcDirectorRules skill (scales size within skill_min..max)
  specials_budget: 2
difficulty:              # presets a map or server names; multiply the generated numbers
  easy:   {size: 0.7, health: 0.8, speed: 0.95, reward: 1.2}
  normal: {}
  hard:   {size: 1.3, health: 1.2, speed: 1.1, reward: 0.9}
waves: {}
extra: {}                # untouched; the game reads its own keys here
```

```yaml
# cfg/game/zombie-zone/waves/school_hold.yml  (game tier: extends the addon's hold)
extends: hold
count: 10
size: {base: 16, per_player: 4}
pool: {zz_common: 10, zz_crawler: 2}
director: {skill: true, specials_budget: 2}
waves:
  1:  {pool: {zz_common: 1}, release: 1.0, announce: "They are coming through the gym."}
  3:  {pool: {zz_common: 8, zz_crawler: 3, zz_sprinter: 2}}
  "5": {boss: {npc: zz_brute, count: 1, at: 0.33}, reward: {restock: tier2, cash: 0}}
  "6-9": {specials: {zz_spitter: 1, zz_strangler: 1}}      # a range applies to each wave in it
  last: {boss: {npc: zz_brute, count: 2, at: 0.33}, pool: {zz_common: 6, zz_rider: 2}}
extra:
  zz: {twists: true, breather: patch_up}
```

Per-wave keys (all optional, all inherit the set's value): `pool` (NPC profile id -> weight; replaces the set pool for that wave, `+id` prefix adds instead of replacing), `size` (absolute count for that wave, overrides the formula), `size_mult`, `release` (per second), `quiet` (the break before it), `specials` (id -> count, spread over the wave), `boss` (`npc`, `count`, `at`: the fraction of the wave released before it arrives; the wave is not over while a boss stands), `reward` (opaque to the director, passed to the game in `wave_started`), `announce`, `health_mult`, `speed_mult`, `extra`. Ranges (`"6-9"`) and `last` expand before validation; a number beats a range beats `last`'s default only where they name the same wave: `last` always wins for the final wave.

A cycle set uses `nights:` the same way, and a clock set has one entry, `1`.

## Difficulty, skill and the director's budget

Difficulty is a named preset in the set, picked by the map entry; it multiplies the generated count, health, speed and reward and never rewrites `pool`. It feeds the director's existing `difficulty_preset` rule so the one dial moves both the schedule and the stress cycle's accuracy and damage. `director.skill` turns on `DotNpcDirectorRules.skill_enabled` for this set only; skill still clamps to `skill_min..skill_max`, so a hand-written wave of 20 stays between 14 and 26 at defaults. `specials_budget` is the cooldown budget (`special_budget_cap`); a wave's `specials:` is what the budget may spend on that wave and is refused by it, not around it. Fixed sizes are therefore a ceiling for the author and a dial for the director, and a set that wants them exact sets `director: {skill: false}`.

## Maps and rotation

dot-map's rotation file says which maps rotate. Add one optional field to a rotation entry, resolved by the same `defaults:` / `games:` layers:

```yaml
# cfg/addons/dot_map/maps.yml (rotation.md names it cfg/maps.yml; confirm which is current)
games:
  game-zombie-zone:
    rotation: survival
    rotations:
      survival:
        mode: cycle
        cooldown: 2
        maps:
          - zz_school: {waves: school_hold, difficulty: normal}
          - zz_mall:   {waves: mall_siege,  difficulty: hard}
          - "zz_camp_*": {waves: camp_nights}    # a glob entry carries its settings to every match
```

A bare string stays valid. `DotMapDef` gains a free `play: Dictionary` (the entry's settings, opaque to dot-map); the game reads `play.waves` and `play.difficulty` at map start. Precedence for the wave set: server command (`sv_waves <set>`, admin) > the rotation entry > the map document's `survival.waves` (the map author's suggestion, replacing today's `wave_scale_by_map`) > the game's default set. A missing set id is a WARN and the next candidate, never a crash and never zero waves.

## The match

Round start: game resolves the set, calls `DotNpcDirectorWaves.from_profile(profile, difficulty, players)` and `begin`. Each stage change emits the resolved wave (`WaveSpec`: index, size, pool, specials, boss, reward, announce) so the game never reads yml mid-match. When the last wave is cleared the schedule emits `finished`; the game ends the match as a win (dot-match `match_ended`), shows the scoreboard, and lets dot-map's session run the vote or take the next rotation entry. All players dead ends it as a loss through the same path. Nothing in the set can extend or loop a match; "endless" is `style: clock` with `0` seconds.

## Extension points for Zombie Zone

1. `pool`, `boss.npc`, `specials` hold NPC ids from `cfg/game/zombie-zone/npc/`; ZZ registers its brains by profile (`brain: zz_spitter` in the NPC file), not by wave code.
2. `extra.zz` carries what only ZZ understands (twists on or off, breather style, cache tier). The game subclasses `DotWaveSet` (or just reads `extra`) and may assign `wave_resolved(spec) -> spec` to adjust a wave after resolution; today's twists become that hook plus `extra.zz.twists`, with `TWISTS` moved to `cfg/game/zombie-zone/twists.yml` in a later step.
3. `reward` is opaque: ZZ reads `restock: tier2` and calls its `restock()`; another game could read `cash`.
4. `validate_extra` callable on the set so ZZ rejects `extra.zz` typos at load, with the same `DotResult` code.

## A new mutant with no code change

1. Add `cfg/game/zombie-zone/npc/zz_bloat_king.yml` (health, speed, damage, `brain:` an existing brain, `model:` an existing scene, `extends: zz_brute` for a quick variant).
2. Name it in `pool`, `specials` or `boss` of a wave, in the game's set or in `cfg/server/waves/`.
3. Start the map. A brain or a model that does not exist yet needs code or an asset; a variant of what exists never does. The existing brains take their tuning from the NPC profile (this is the dot-npc profile work, a prerequisite).

## Validation

At load and again at match start, returned as a `DotResult` with one aggregated message listing every problem (not just the first): unknown keys (use `extra`), types and ranges, `count` against the numbered entries (an entry past `count` is a WARN, not an error), a pool that is empty or sums to 0, weights negative, every NPC id resolvable through an injected `npc_exists(id)` (the director does not load NPCs), `boss.at` in 0..1, difficulty preset exists, a `style` that has the fields it needs (`nights` with `cycle`), and `DotNpcDirectorWaves.validate()` on the built schedule. A set that fails falls back to the next candidate (above) and logs ERROR once; the match is never started on a half-valid set. A headless tool, `waves_check`, loads every set in every tier of a game and prints the same aggregate (for server owners and CI). `describe_lines()` on the set prints each layer's source so "why is wave 5 a brute" is answerable.

## Test plan

- Director suite (numbers only, no engine NPCs): tier merge order, range expansion and `last` precedence, formula against explicit waves, difficulty multipliers, every validation failure above gets one case, `from_profile` reproduces today's `DotNpcDirectorWaves` defaults exactly (regression guard for the 10-wave school numbers), `+id` pool add, env override of a scalar, wave entries refusing env.
- dot-map suite: rotation entry with a mapping parses, a bare string still does, glob entry carries settings, precedence of `sv_waves` > entry > map doc, missing set falls through.
- ZZ: `headless_survival` plays a three-wave set from yml and a server-tier override of wave 2, asserts the spawned ids and counts equal the yml, and that a mutant added only as an npc yml spawns. A render of the HUD wave title for an announce line. Existing ZZ suites stay green with the default set equal to today's numbers.
- Final wave cleared then rotation: a session test that `finished` leads to `map_over` and the next entry.

## Tasks, in order

1. dot-core: `DotProfile` lands (in progress), including dictionary merge and range-safe keys; no work here beyond confirming a `waves` kind needs nothing special.
2. dot-npc: `npc` profile kind with `brain:` and `model:` fields, if not already there (blocks "no code change").
3. dot-npc-ai-director: `DotWaveSet`, `from_profile`, `WaveSpec`, validation, `waves_check`, suite, API level bump, default `hold.yml`.
4. dot-map: rotation entry mapping form, `DotMapDef.play`, `sv_waves`, rotation docs and suite.
5. game-zombie-zone: `cfg/game/zombie-zone/waves/*.yml` carrying today's numbers, `ZzSurvival` reads the set, `wave_scale_by_map` and the survival cvars become server-tier defaults, `extra.zz`, mutant demo, survival suite.
6. Other hold-out games adopt it; twists to yml; an in-game editor is out of scope (files only).

Order is 1-2 (parallel), 3, 4, 5. Steps 3 and 4 can run together once 1 exists.
