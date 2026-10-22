class_name DotWaveSet
extends RefCounted

## A hold-out's waves as config: one `waves` profile resolved to a [DotWaveSpec] per wave.
##
## A wave with no entry is generated from the formula in [DotNpcDirectorWaves]; the entries
## only say where a wave differs. The set spawns nothing and loads no NPC: the game gets a
## spec at wave start and does the rest. Design: docs/waves.md.

const ADDON := "dot_npc_ai_director"
const KIND := "waves"
const CHANNEL := "waves"

## Per-wave keys an entry may hold.
const ENTRY_KEYS := ["pool", "size", "size_mult", "release", "quiet", "specials", "boss", "reward", "announce", "health_mult", "speed_mult", "extra"]
const STYLES := ["rounds", "cycle", "clock"]
const DIFFICULTY_KEYS := ["size", "health", "speed", "reward"]
const DIRECTOR_KEYS := ["skill", "specials_budget"]

## Sub-keys of the dictionary fields: name -> key -> [type, min, max, default].
const SUB := {
	"size": {"base": ["int", 0, 10000, 16], "per_player": ["int", 0, 10000, 4]},
	"growth": {"linear": ["float", 0.0, 100.0, 0.25], "accel": ["float", 0.0, 100.0, 0.02]},
	"release": {"base": ["float", 0.01, 1000.0, 1.5], "growth": ["float", 0.0, 100.0, 0.12]},
	"overtime": {"seconds": ["float", 0.0, 86400.0, 150.0], "stragglers": ["int", 0, 1000, 3], "straggler_seconds": ["float", 0.0, 86400.0, 30.0]},
	"alive_cap": {"base": ["int", 0, 10000, 24], "per_player": ["int", 0, 10000, 6]},
}

## Wave `wave` of `count` was reached on the map named [member map_key], or the set finished.
## A game wires this to whatever tracks progress per map, without the director knowing maps.
signal progress(map_key: String, wave: int, count: int, done: bool)

var id := ""
var style: int = DotNpcDirectorWaves.Style.ROUNDS
var count: int = 10
var first_quiet: float = 30.0
var quiet: float = 30.0
var seconds: float = 150.0
var twilight: float = 10.0
var size_base: int = 16
var size_per_player: int = 4
var growth_linear: float = 0.25
var growth_accel: float = 0.02
var release_base: float = 1.5
var release_growth: float = 0.12
var overtime_seconds: float = 150.0
var stragglers: int = 3
var straggler_seconds: float = 30.0
var cap_base: int = 24
var cap_per_player: int = 6

## NPC id -> weight for waves with no entry.
var pool: Dictionary = {}

## `skill` / `specials_budget`; empty means the set is a pure schedule.
var director: Dictionary = {}

## Preset name -> {size, health, speed, reward} multipliers.
var difficulties: Dictionary = {}

## The preset in play and its multipliers.
var difficulty := "normal"
var mult := {"size": 1.0, "health": 1.0, "speed": 1.0, "reward": 1.0}

## The set's `extra:` block, untouched.
var extra: Dictionary = {}

## Non-fatal findings from the load (an entry past the count).
var warnings := PackedStringArray()

## `tier: path` of every file that built this set, weakest first.
var sources := PackedStringArray()
var chain := PackedStringArray()
var overrides := PackedStringArray()

## The game's adjustment of a wave after resolution: `func(spec: DotWaveSpec) -> DotWaveSpec`.
var wave_resolved: Callable = Callable()

## The game's check of an `extra:` block: `func(extra: Dictionary) -> DotResult`.
var validate_extra: Callable = Callable()

## Names the map in play for [signal progress]; the game sets it at map start.
var map_key := ""

## Map key -> highest wave reached on it.
var reached: Dictionary = {}

var _exact: Dictionary = {}
var _ranges: Array = []
var _last: Dictionary = {}
var _has_last := false


## The fields of a `waves` profile.
static func schema() -> Array:
	var f := DotProfileSet.field
	return [
		f.call("style", "string", "rounds", {"enum": STYLES}),
		f.call("count", "int", 10, {"min": 1, "max": 1000}),
		f.call("first_quiet", "float", 30.0, {"min": 0.0, "max": 86400.0}),
		f.call("quiet", "float", 30.0, {"min": 0.0, "max": 86400.0}),
		f.call("seconds", "float", 150.0, {"min": 0.0, "max": 86400.0}),
		f.call("twilight", "float", 10.0, {"min": 0.0, "max": 3600.0}),
		f.call("size", "dict", {}), f.call("growth", "dict", {}), f.call("release", "dict", {}),
		f.call("overtime", "dict", {}), f.call("alive_cap", "dict", {}),
		f.call("pool", "dict", {}), f.call("director", "dict", {}), f.call("difficulty", "dict", {}),
		f.call("waves", "dict", {}), f.call("nights", "dict", {}),
	]


## The profile set for a game's wave sets (`cfg/game/<game>/waves/<id>.yml` over the addon's).
static func make_set(game: String, roots: PackedStringArray = PackedStringArray(), cmdline: PackedStringArray = PackedStringArray()) -> DotProfileSet:
	var s := DotProfileSet.create(ADDON, game, KIND, schema())
	s.roots = roots
	s.cmdline = cmdline
	return s


## Loads wave set [param set_id] and builds it. Value: a [DotWaveSet]. See [method from_profile].
static func load_set(profiles: DotProfileSet, set_id: String, p_difficulty: String = "normal", npc_exists: Callable = Callable(), p_validate_extra: Callable = Callable()) -> DotResult:
	var res := profiles.load_profile(set_id)
	if not res.ok:
		return res
	return from_profile(res.value, p_difficulty, npc_exists, p_validate_extra)


## Builds and validates a set from a loaded profile. Every problem is reported together as one
## [code]CODE_INVALID[/code]; [param npc_exists] is `func(id: String) -> bool` and is only asked when valid.
static func from_profile(profile: DotProfile, p_difficulty: String = "normal", npc_exists: Callable = Callable(), p_validate_extra: Callable = Callable()) -> DotResult:
	var s := DotWaveSet.new()
	s.id = profile.id
	s.sources = profile.sources
	s.chain = profile.chain
	s.overrides = profile.overrides
	s.validate_extra = p_validate_extra
	var errs := s._load(profile, p_difficulty, npc_exists)
	if not errs.is_empty():
		return DotResult.fail(DotError.CODE_INVALID, "waves/%s: %s" % [profile.id, "; ".join(errs)])
	for w in s.warnings:
		DotLog.warn(CHANNEL, w, {"set": s.id})
	return DotResult.success(s)


## The first wave number that is the set's last.
func last_index() -> int:
	return 1 if style == DotNpcDirectorWaves.Style.CLOCK else count


## Enemies alive at once the set allows for [param players].
func alive_cap(players: int) -> int:
	return cap_base + cap_per_player * maxi(players - 1, 0)


## Wave [param k] for [param players] players, after the game's [member wave_resolved] hook.
func resolve(k: int, players: int) -> DotWaveSpec:
	var spec := resolve_raw(k, players)
	if wave_resolved.is_valid():
		var out: Variant = wave_resolved.call(spec)
		if out is DotWaveSpec:
			return out
		DotLog.warn(CHANNEL, "wave_resolved returned no spec; keeping the resolved one", {"set": id, "wave": k})
	return spec


## Wave [param k] as the file says it, no hook. Deterministic in (k, players).
func resolve_raw(k: int, players: int) -> DotWaveSpec:
	var e := _entry(k)
	var spec := DotWaveSpec.new()
	spec.index = k
	spec.is_last = k >= last_index()
	spec.pool = e["pool"]
	spec.extra = e["extra"]
	spec.specials = e.get("specials", {}).duplicate()
	spec.boss = e.get("boss", {}).duplicate()
	spec.reward = e.get("reward")
	spec.announce = e.get("announce", "")
	spec.release = e.get("release", -1.0)
	spec.quiet = e.get("quiet", -1.0)
	spec.reward_mult = mult["reward"]
	spec.health_mult = e.get("health_mult", 1.0) * mult["health"]
	spec.speed_mult = e.get("speed_mult", 1.0) * mult["speed"]
	if style == DotNpcDirectorWaves.Style.ROUNDS:
		var n: int
		if e.has("size"):
			n = e["size"]
		else:
			var team := size_base + size_per_player * maxi(players - 1, 0)
			var step := float(maxi(k - 1, 0))
			n = maxi(int(round(float(team) * (1.0 + growth_linear * step + growth_accel * step * step))), 1)
		spec.size = maxi(int(round(float(n) * e.get("size_mult", 1.0) * mult["size"])), 1)
	return spec


## The quiet before wave [param k] from its entry, or -1 for the set's.
func quiet_of(k: int) -> float:
	return _entry(k).get("quiet", -1.0)


## Sets [param rules] from the set's `director:` block and difficulty. False (nothing touched) for a pure schedule.
func apply_to_rules(rules: DotNpcDirectorRules) -> bool:
	if director.is_empty():
		return false
	rules.skill_enabled = bool(director.get("skill", false))
	if director.has("specials_budget"):
		var b: int = director["specials_budget"]
		rules.specials_enabled = b > 0
		rules.special_budget_cap = maxi(b, 1)
	if DotNpcDirectorDifficulty.has_preset(difficulty):
		rules.difficulty_enabled = true
		rules.difficulty_preset = difficulty
	return true


## A wave's size after the director's skill, clamped to the rules' skill range; unchanged when the set's skill is off.
func skilled_size(size: int, skill: float, rules: DotNpcDirectorRules) -> int:
	if not director.get("skill", false) or rules == null:
		return size
	return maxi(int(round(float(size) * clampf(skill, rules.skill_min, rules.skill_max))), 1)


## The part of a wave's specials the budget may spend now: whole units, in id order. The budget refuses; this does not go round it.
static func specials_within_budget(spec: DotWaveSpec, budget: float) -> Dictionary:
	var left := int(floor(budget))
	var out := {}
	var ids := spec.specials.keys()
	ids.sort()
	for sid in ids:
		var n := mini(int(spec.specials[sid]), left)
		if n > 0:
			out[sid] = n
			left -= n
	return out


## Records and signals that wave [param wave] was reached on [member map_key].
func report_progress(wave: int, done: bool) -> void:
	reached[map_key] = maxi(int(reached.get(map_key, 0)), wave)
	progress.emit(map_key, wave, last_index(), done)


## How far through the set [param key] got, 0 to 1.
func progress_of(key: String) -> float:
	return clampf(float(reached.get(key, 0)) / float(maxi(last_index(), 1)), 0.0, 1.0)


func describe() -> Dictionary:
	return {
		"id": id, "style": DotNpcDirectorWaves.STYLE_NAMES[style], "count": count, "difficulty": difficulty,
		"entries": _exact.size() + _ranges.size() + (1 if _has_last else 0), "pool": pool.duplicate(),
		"director": director.duplicate(), "extends": chain, "warnings": warnings.size(),
	}


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("wave set   %s, %s x%d, difficulty %s, %d entries, %d warnings" % [id, DotNpcDirectorWaves.STYLE_NAMES[style], count, difficulty, _exact.size() + _ranges.size() + (1 if _has_last else 0), warnings.size()])
	out.append("  extends  %s" % " -> ".join(chain))
	for src in sources:
		out.append("  layer    %s" % src)
	for o in overrides:
		out.append("  override %s" % o)
	for w in warnings:
		out.append("  warn     %s" % w)
	return out


func _load(profile: DotProfile, p_difficulty: String, npc_exists: Callable) -> PackedStringArray:
	var errs := PackedStringArray()
	var v := profile.values
	style = DotNpcDirectorWaves.style_from(v["style"])
	count = v["count"]
	first_quiet = v["first_quiet"]
	quiet = v["quiet"]
	seconds = v["seconds"]
	twilight = v["twilight"]
	var sz := _sub("size", v["size"], errs)
	size_base = sz["base"]
	size_per_player = sz["per_player"]
	var gr := _sub("growth", v["growth"], errs)
	growth_linear = gr["linear"]
	growth_accel = gr["accel"]
	var rl := _sub("release", v["release"], errs)
	release_base = rl["base"]
	release_growth = rl["growth"]
	var ot := _sub("overtime", v["overtime"], errs)
	overtime_seconds = ot["seconds"]
	stragglers = ot["stragglers"]
	straggler_seconds = ot["straggler_seconds"]
	var ac := _sub("alive_cap", v["alive_cap"], errs)
	cap_base = ac["base"]
	cap_per_player = ac["per_player"]
	extra = profile.extra.duplicate(true)
	pool = _check_pool(v["pool"], "pool", errs, false)
	_load_director(v["director"], errs)
	_load_difficulties(v["difficulty"], p_difficulty, errs)

	var cycle: bool = style == DotNpcDirectorWaves.Style.CYCLE
	var key := "nights" if cycle else "waves"
	var other := "waves" if cycle else "nights"
	if not (v[other] as Dictionary).is_empty():
		errs.append("%s: a %s set takes '%s:' entries" % [other, DotNpcDirectorWaves.STYLE_NAMES[style], key])
	if cycle and seconds <= 0.0:
		errs.append("seconds: a night needs a length")
	_load_entries(v[key], key, errs)
	_call_validate_extra(extra, "extra", errs)

	if errs.is_empty():
		var missing := {}
		for k in range(1, last_index() + 1):
			var e := _entry(k)
			_sum_check(e["pool"], "wave %d pool" % k, errs)
			var named: Array = e["pool"].keys() + e.get("specials", {}).keys()
			if e.has("boss"):
				named.append(e["boss"]["npc"])
			for n in named:
				if npc_exists.is_valid() and not npc_exists.call(str(n)):
					missing[n] = missing.get(n, "") + (", " if missing.has(n) else "") + str(k)
		for n in missing:
			errs.append("no NPC '%s' (wave %s)" % [n, missing[n]])
	if errs.is_empty():
		var sched := DotNpcDirectorWaves.new()
		fill_schedule(sched, 1)
		var res := sched.validate()
		if not res.ok:
			errs.append(res.error.message)
	return errs


## Copies the set's numbers onto [param sched] and binds it so each wave resolves through the set.
func fill_schedule(sched: DotNpcDirectorWaves, players: int) -> void:
	sched.style = style
	sched.count = count
	sched.first_quiet_seconds = first_quiet
	sched.quiet_seconds = quiet
	sched.horde_seconds = seconds
	sched.twilight_seconds = twilight
	sched.wave_base = size_base
	sched.wave_per_player = size_per_player
	sched.growth = growth_linear
	sched.growth_accel = growth_accel
	sched.release_base = release_base
	sched.release_growth = release_growth
	sched.overtime_seconds = overtime_seconds
	sched.straggler_count = stragglers
	sched.straggler_seconds = straggler_seconds
	sched.players = players
	sched.wave_set = self


## A dictionary field filled from its defaults, with unknown keys, types and ranges reported.
func _sub(name: String, given: Variant, errs: PackedStringArray) -> Dictionary:
	var out := {}
	var spec: Dictionary = SUB[name]
	for k in spec:
		out[k] = spec[k][3]
	if not (given is Dictionary):
		errs.append("%s: must be a mapping" % name)
		return out
	for k in given:
		if not spec.has(k):
			errs.append("%s: unknown key '%s' (use %s)" % [name, k, ", ".join(PackedStringArray(spec.keys()))])
			continue
		var s: Array = spec[k]
		var n: Variant = _number(given[k], s[0] == "int")
		if n == null:
			errs.append("%s.%s: expected %s, got %s" % [name, k, s[0], str(given[k])])
		elif n < s[1] or n > s[2]:
			errs.append("%s.%s: %s is outside %s..%s" % [name, k, str(n), str(s[1]), str(s[2])])
		else:
			out[k] = n
	return out


static func _number(v: Variant, want_int: bool) -> Variant:
	if v is int:
		return v if want_int else float(v)
	if v is float and is_finite(v):
		if want_int:
			return int(v) if v == floorf(v) else null
		return v
	return null


func _load_director(given: Variant, errs: PackedStringArray) -> void:
	director = {}
	if not (given is Dictionary):
		errs.append("director: must be a mapping")
		return
	for k in given:
		if not DIRECTOR_KEYS.has(k):
			errs.append("director: unknown key '%s' (use %s)" % [k, ", ".join(DIRECTOR_KEYS)])
		elif k == "skill":
			if given[k] is bool:
				director[k] = given[k]
			else:
				errs.append("director.skill: expected bool, got %s" % str(given[k]))
		else:
			var n: Variant = _number(given[k], true)
			if n == null or n < 0 or n > 20:
				errs.append("director.specials_budget: expected an int 0..20, got %s" % str(given[k]))
			else:
				director[k] = n


func _load_difficulties(given: Variant, wanted: String, errs: PackedStringArray) -> void:
	difficulties = {}
	if not (given is Dictionary):
		errs.append("difficulty: must be a mapping")
		return
	for name in given:
		var row: Variant = given[name]
		if row == null or (row is String and row == ""):
			row = {}
		if not (row is Dictionary):
			errs.append("difficulty.%s: must be a mapping" % name)
			continue
		var m := {"size": 1.0, "health": 1.0, "speed": 1.0, "reward": 1.0}
		for k in row:
			var n: Variant = _number(row[k], false)
			if not DIFFICULTY_KEYS.has(k):
				errs.append("difficulty.%s: unknown key '%s' (use %s)" % [name, k, ", ".join(DIFFICULTY_KEYS)])
			elif n == null or n <= 0.0 or n > 100.0:
				errs.append("difficulty.%s.%s: expected a number above 0, got %s" % [name, k, str(row[k])])
			else:
				m[k] = n
		difficulties[str(name)] = m
	difficulty = wanted
	if difficulties.has(wanted):
		mult = difficulties[wanted]
	elif wanted != "normal":
		errs.append("difficulty: no preset '%s' (have %s)" % [wanted, ", ".join(PackedStringArray(difficulties.keys()))])


## A pool as {id: weight}. [param allow_add] lets keys start with '+' (kept in the result).
func _check_pool(given: Variant, ctx: String, errs: PackedStringArray, allow_add: bool) -> Dictionary:
	var out := {}
	if not (given is Dictionary):
		errs.append("%s: must be a mapping of NPC id to weight" % ctx)
		return out
	for k in given:
		var name := str(k)
		var n: Variant = _number(given[k], false)
		if name.strip_edges() == "" or (name.begins_with("+") and (not allow_add or name.length() == 1)):
			errs.append("%s: bad id '%s'" % [ctx, name])
		elif n == null or n < 0.0:
			errs.append("%s.%s: a weight is a number of 0 or more, got %s" % [ctx, name, str(given[k])])
		else:
			out[name] = n
	return out


func _sum_check(p: Dictionary, ctx: String, errs: PackedStringArray) -> void:
	var total := 0.0
	for k in p:
		total += float(p[k])
	if p.is_empty() or total <= 0.0:
		errs.append("%s: empty, or its weights sum to 0" % ctx)


func _call_validate_extra(e: Dictionary, ctx: String, errs: PackedStringArray) -> void:
	if e.is_empty() or not validate_extra.is_valid():
		return
	var res: Variant = validate_extra.call(e)
	if res is DotResult and not res.ok:
		errs.append("%s: %s" % [ctx, res.error.message])


## Parses a key of the entries map: {lo, hi} or {last: true}; empty when unreadable.
static func _entry_key(k: Variant) -> Dictionary:
	if k is int:
		return {"lo": k, "hi": k}
	if k is float and k == floorf(k):
		return {"lo": int(k), "hi": int(k)}
	var s := str(k).strip_edges()
	if s == "last":
		return {"last": true}
	if s.is_valid_int():
		return {"lo": s.to_int(), "hi": s.to_int()}
	var parts := s.split("-")
	if parts.size() == 2 and parts[0].strip_edges().is_valid_int() and parts[1].strip_edges().is_valid_int():
		return {"lo": parts[0].strip_edges().to_int(), "hi": parts[1].strip_edges().to_int()}
	return {}


func _load_entries(given: Variant, label: String, errs: PackedStringArray) -> void:
	_exact = {}
	_ranges = []
	_last = {}
	_has_last = false
	if not (given is Dictionary):
		errs.append("%s: must be a mapping keyed by wave number" % label)
		return
	var limit := last_index()
	for k in given:
		var key := _entry_key(k)
		var ctx := "%s.%s" % [label, str(k)]
		if key.is_empty():
			errs.append("%s: a key is a number, a range like 6-9, or 'last'" % ctx)
			continue
		var e := _check_entry(given[k], ctx, errs)
		if key.has("last"):
			_last = e
			_has_last = true
			continue
		if key["lo"] < 1 or key["hi"] < key["lo"]:
			errs.append("%s: waves start at 1 and a range runs upward" % ctx)
			continue
		if key["hi"] > limit:
			warnings.append("%s: past the last wave (%d); the part beyond is ignored" % [ctx, limit])
		if key["lo"] == key["hi"]:
			if _exact.has(key["lo"]):
				errs.append("%s: wave %d is written twice" % [ctx, key["lo"]])
			_exact[key["lo"]] = e
		else:
			_ranges.append({"lo": key["lo"], "hi": key["hi"], "entry": e})
	_ranges.sort_custom(_range_before)


## Wider ranges first so a narrower one applies later and wins; ties by start.
static func _range_before(a: Dictionary, b: Dictionary) -> bool:
	var wa: int = a["hi"] - a["lo"]
	var wb: int = b["hi"] - b["lo"]
	if wa != wb:
		return wa > wb
	return a["lo"] < b["lo"]


func _check_entry(raw: Variant, ctx: String, errs: PackedStringArray) -> Dictionary:
	var e := {}
	if raw == null or (raw is String and raw == ""):
		return e
	if not (raw is Dictionary):
		errs.append("%s: must be a mapping" % ctx)
		return e
	for k in raw:
		var v: Variant = raw[k]
		var c := "%s.%s" % [ctx, k]
		match str(k):
			"pool":
				e["pool"] = _check_pool(v, c, errs, true)
			"size":
				var n: Variant = _number(v, true)
				if n == null or n < 1:
					errs.append("%s: expected a count of 1 or more, got %s" % [c, str(v)])
				else:
					e["size"] = n
			"size_mult", "health_mult", "speed_mult":
				var n: Variant = _number(v, false)
				if n == null or n <= 0.0 or n > 100.0:
					errs.append("%s: expected a number above 0, got %s" % [c, str(v)])
				else:
					e[str(k)] = n
			"release":
				var n: Variant = _number(v, false)
				if n == null or n <= 0.0:
					errs.append("%s: expected enemies a second above 0, got %s" % [c, str(v)])
				else:
					e["release"] = n
			"quiet":
				var n: Variant = _number(v, false)
				if n == null or n < 0.0:
					errs.append("%s: expected seconds of 0 or more, got %s" % [c, str(v)])
				else:
					e["quiet"] = n
			"specials":
				e["specials"] = _check_specials(v, c, errs)
			"boss":
				e["boss"] = _check_boss(v, c, errs)
			"reward":
				e["reward"] = v
			"announce":
				if v is String:
					e["announce"] = v
				else:
					errs.append("%s: expected text, got %s" % [c, str(v)])
			"extra":
				if v is Dictionary:
					e["extra"] = v.duplicate(true)
					_call_validate_extra(v, c, errs)
				else:
					errs.append("%s: must be a mapping" % c)
			_:
				errs.append("%s: unknown key (use %s, or put it under extra:)" % [c, ", ".join(ENTRY_KEYS)])
	return e


func _check_specials(v: Variant, c: String, errs: PackedStringArray) -> Dictionary:
	var out := {}
	if not (v is Dictionary):
		errs.append("%s: must be a mapping of NPC id to count" % c)
		return out
	for k in v:
		var n: Variant = _number(v[k], true)
		if n == null or n < 1:
			errs.append("%s.%s: expected a count of 1 or more, got %s" % [c, k, str(v[k])])
		else:
			out[str(k)] = n
	return out


func _check_boss(v: Variant, c: String, errs: PackedStringArray) -> Dictionary:
	var out := {"count": 1, "at": 0.0}
	if not (v is Dictionary):
		errs.append("%s: must be a mapping" % c)
		return out
	for k in v:
		match str(k):
			"npc":
				if v[k] is String and v[k] != "":
					out["npc"] = v[k]
				else:
					errs.append("%s.npc: expected an NPC id, got %s" % [c, str(v[k])])
			"count":
				var n: Variant = _number(v[k], true)
				if n == null or n < 1:
					errs.append("%s.count: expected 1 or more, got %s" % [c, str(v[k])])
				else:
					out["count"] = n
			"at":
				var f: Variant = _number(v[k], false)
				if f == null or f < 0.0 or f > 1.0:
					errs.append("%s.at: expected 0..1, got %s" % [c, str(v[k])])
				else:
					out["at"] = f
			_:
				errs.append("%s: unknown key '%s' (use npc, count, at)" % [c, k])
	if not out.has("npc"):
		errs.append("%s: a boss needs an npc" % c)
		out["npc"] = ""
	return out


## The merged entry for wave [param k]: set pool, then ranges (wide to narrow), the number, `last`.
func _entry(k: int) -> Dictionary:
	var acc := {"pool": pool.duplicate(), "extra": extra.duplicate(true)}
	var layers: Array = []
	for r in _ranges:
		if k >= r["lo"] and k <= r["hi"]:
			layers.append(r["entry"])
	if _exact.has(k):
		layers.append(_exact[k])
	if _has_last and k == last_index():
		layers.append(_last)
	for layer in layers:
		for key in layer:
			if key == "pool":
				acc["pool"] = _merge_pool(acc["pool"], layer["pool"])
			elif key == "extra":
				DotAddonConfig.merge(acc["extra"], layer["extra"].duplicate(true))
			else:
				acc[key] = layer[key]
	return acc


## Plain keys replace the pool, '+id' keys add to whatever it is by then.
static func _merge_pool(base: Dictionary, given: Dictionary) -> Dictionary:
	var out := {}
	var plain := false
	for k in given:
		if not String(k).begins_with("+"):
			out[k] = given[k]
			plain = true
	if not plain:
		out = base.duplicate()
	for k in given:
		if String(k).begins_with("+"):
			out[String(k).substr(1)] = given[k]
	return out
