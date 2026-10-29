extends Node

## Fixtures the director self-test builds its world from: catalogue, spawner, corridor, director, rules.

const BODY := "res://fixtures/npc_body.tscn"

var _world: Node3D = null


func _catalogue() -> DotNpcCatalogue:
	var cat := DotNpcCatalogue.new()

	var zombie := DotNpcDef.make(&"zombie", BODY)
	zombie.require_line_of_sight = false
	cat.add(zombie)

	var brute := DotNpcDef.make(&"brute", BODY)
	brute.require_line_of_sight = false
	brute.cost = 4
	cat.add(brute)

	return cat


func _spawner() -> DotNpcSpawner:
	var spawner := DotNpcSpawner.new()
	spawner.catalogue = _catalogue()

	var limits := DotNpcLimits.new()
	limits.spawn_interval = 0.0
	limits.require_navigable_spawn = false
	limits.world_budget = 0
	limits.per_kind_cap = 0
	limits.reclaim_distance = 0.0
	spawner.limits = limits
	spawner.authoritative = true

	_world.add_child(spawner)

	return spawner


## A straight corridor of spawn points, 200 m long.
func _corridor() -> PackedVector3Array:
	var points := PackedVector3Array()

	for i in 41:
		points.append(Vector3(0, 0, -5.0 * float(i)))

	return points


func _director(spawner: DotNpcSpawner, rules: DotNpcDirectorRules = null) -> DotNpcDirector:
	var director := DotNpcDirector.new()
	director.spawner = spawner
	director.rules = rules if rules != null else _rules()
	director.population = [&"zombie", &"zombie", &"zombie", &"brute"]
	director.spawn_points = _corridor()
	director.flow = DotNpcDirectorFlow.new(PackedVector3Array([
		Vector3(0, 0, 0), Vector3(0, 0, -200)
	]))
	_world.add_child(director)
	return director


## Rules with the sight test off, because there is no level in this suite to be hidden
## behind and every point would otherwise be visible from everywhere.
func _rules() -> DotNpcDirectorRules:
	var rules := DotNpcDirectorRules.new()
	rules.spawn_out_of_sight = false
	rules.spawn_interval = 0.0
	return rules
