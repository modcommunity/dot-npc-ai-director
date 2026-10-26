class_name DotNpcDirectorGrace
extends RefCounted

## A countdown at the start of a round during which nothing spawns, so players can prepare.

## The grace began, with its length in seconds.
signal started(seconds: float)
## The grace ran out (or was cancelled with [code]skipped[/code] true).
signal ended(skipped: bool)

## Seconds left; 0 when none is running.
var left: float = 0.0
## Seconds it was begun with.
var total: float = 0.0

var _active := false


## Starts a grace of [param seconds]; 0 or less does nothing. Returns whether one is running.
func begin(seconds: float) -> bool:
	if seconds <= 0.0:
		return false
	total = seconds
	left = seconds
	_active = true
	started.emit(seconds)
	return true


func is_active() -> bool:
	return _active


## Counts down; emits [signal ended] on the tick it reaches zero.
func tick(delta: float) -> void:
	if not _active:
		return
	left = maxf(left - delta, 0.0)
	if left <= 0.0:
		_end(false)


## Ends it now.
func skip() -> void:
	if _active:
		_end(true)


## Forgets a running grace without announcing it (a map ended).
func clear() -> void:
	_active = false
	left = 0.0
	total = 0.0


func _end(skipped: bool) -> void:
	_active = false
	left = 0.0
	ended.emit(skipped)


func describe() -> Dictionary:
	return {"active": _active, "left": snappedf(left, 0.1), "total": total}
