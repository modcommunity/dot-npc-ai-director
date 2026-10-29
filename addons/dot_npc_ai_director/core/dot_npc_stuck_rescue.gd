class_name DotNpcStuckRescue
extends RefCounted

## Notices an NPC that makes no progress toward the survivors: repath, then relocate, then remove so the caller can re-spawn it.
## Pure bookkeeping on the caller's think tick: ask [method due] first, measure distance only then. Progress is the best distance reached, not movement.
## When few are left ([member low_count]) the waits shrink to a third.

const NONE := 0
const REPATH := 1
const RELOCATE := 2
const REMOVE := 3

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
## Relocations without progress in between after which it is removed instead. 0 never removes.
var remove_after_relocations: int = 2

var repaths: int = 0
var relocations: int = 0
var removals: int = 0

var _seen: Dictionary = {}
## id -> relocations since it last made progress.
var _moved: Dictionary = {}


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
		_moved.erase(id)
		return NONE
	var entry: Array = e
	entry[2] = now
	var scale := 0.33 if low_count > 0 and live_count <= low_count else 1.0
	var stalled := now - float(entry[1])
	if stalled >= relocate_after * scale:
		_seen[id] = [distance, now, now, false]
		var moved := int(_moved.get(id, 0)) + 1
		_moved[id] = moved
		if remove_after_relocations > 0 and moved > remove_after_relocations:
			_moved.erase(id)
			removals += 1
			return REMOVE
		relocations += 1
		return RELOCATE
	if stalled >= repath_after * scale and not bool(entry[3]):
		entry[3] = true
		repaths += 1
		return REPATH
	return NONE


func forget(id: int) -> void:
	_seen.erase(id)
	_moved.erase(id)


func clear() -> void:
	_seen.clear()
	_moved.clear()


func describe() -> Dictionary:
	return {"tracked": _seen.size(), "repaths": repaths, "relocations": relocations, "removals": removals}
