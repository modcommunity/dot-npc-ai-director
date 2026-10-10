# History

Bugs the suite found while the director was being written. The lessons that still apply are rules in [CLAUDE.md](../CLAUDE.md) and [design.md](design.md).

- **`reclaim_interval` of 0 meant "never".** `spawn_interval` of 0 means "every tick" in `DotNpcLimits` and everywhere else in this family, so a game that turned the wait off got a director that never reclaimed anything. Two settings named the same way meaning opposite things at zero is the kind of difference nobody reads twice.
- **`spawner.get_world_3d()` does not exist.** A `DotNpcSpawner` is a plain `Node`, and written as a duck-typed `has_method` branch it does not even compile: GDScript cannot infer the type of what such a branch returns. The world comes from the viewport.
- **In the suite: a phase test asserted where the cycle happened to be at the end of its loop.** Left-over stress from a peak can break a relax early (documented behaviour with its own test), so the party goes round more than once and the final phase depends on the loop length. It asserts that BUILD_UP was *re-entered* now, which is what "it begins again" actually means.
