extends RefCounted

## dot-npc-ai-director's API level. The rule for bumping it is on [DotAddonApi].
##
## LEVEL rises by one for anything a game could call that did not exist before. OLDEST is
## raised to LEVEL when something a game could have called is removed or changes meaning,
## because every pack built before that no longer compiles against this addon.

# 1: everything before this file existed (an absent file reads as 1).
# 2: DotNpcDirectorWaves, a hold-out's schedule: ROUNDS (waves cleared by killing them),
#    CYCLE (days and nights) and CLOCK; begin, tick, take, give_back, strength, daylight.
# 3: skill estimate, difficulty multipliers and the specials budget (all off by default).
const LEVEL := 3
const OLDEST := 1
