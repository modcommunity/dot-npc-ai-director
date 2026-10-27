class_name DotNpcStuckRescue
extends RefCounted

## Notices an infected that has made no progress toward the survivors, and says what to do next: first
## repath, then relocate it near them, out of sight.
##
## [b]Pure bookkeeping on the caller's think tick.[/b] The caller asks [method due] (one dictionary
## read) and only then measures the distance to its nearest survivor for [method observe], so a
## hundred zombies cost a hundred reads a tick and a handful of measurements. The caller does the
## repath and the move, and logs it ([method describe] counts them): this class holds no NPC.
##
## [b]Progress is the best distance reached[/b], not movement: a zombie circling a wall moves and
## gets nowhere. When few are left ([member low_count]) the waits shrink to a third, because the
## last five are the ones the team is waiting for.

const NONE := 0
const REPATH := 1
const RELOCATE := 2

## Seconds without progress before a repath, and before a relocation.
var repath_after: float = 6.0
var relocate_after: float = 14.0
## Metres closer than its best that counts as progress.
var min_progress: float = 1.0
## Within this of a survivor it is fighting, not stuck.
var engaged_range: float = 3.0
## Seconds between checks of one NPC.
var interval: float = 1.0
## At or under this many left, the waits shrink to a third. 0 off.
var low_count: int = 8

var repaths: int = 0
var relocations: int = 0

var _seen: Dictionary = {}


## Whether [param id] is worth measuring at [param now].
func due(id: int, now: float) -> bool:
	var e: Variant = _seen.get(id)
	return e == null or now - float((e as Array)[2]) >= interval


## Records [param distance] (metres to the nearest survivor) and returns [constant NONE], [constant REPATH] or
## [constant RELOCATE]. A repath is offered once per stall, a relocation after it; relocating resets the clock.
func observe(id: int, distance: float, now: float, live_count: int = 99) -> int:
	var e: Variant = _seen.get(id)
	if e == null or distance < float((e as Array)[0]) - min_progress or distance <= engaged_range:
		# [best distance, last progress at, last check at, repathed]
		_seen[id] = [distance, now, now, false]
		return NONE
	var entry: Array = e
	entry[2] = now
	var scale := 0.33 if low_count > 0 and live_count <= low_count else 1.0
	var stalled := now - float(entry[1])
	if stalled >= relocate_after * scale:
		_seen[id] = [distance, now, now, false]
		relocations += 1
		return RELOCATE
	if stalled >= repath_after * scale and not bool(entry[3]):
		entry[3] = true
		repaths += 1
		return REPATH
	return NONE


func forget(id: int) -> void:
	_seen.erase(id)


func clear() -> void:
	_seen.clear()


func describe() -> Dictionary:
	return {"tracked": _seen.size(), "repaths": repaths, "relocations": relocations}
