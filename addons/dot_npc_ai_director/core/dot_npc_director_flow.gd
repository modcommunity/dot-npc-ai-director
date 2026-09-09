class_name DotNpcDirectorFlow
extends RefCounted

## Where "ahead" is. The map's critical path, as a distance along a line.
##
## [b]Without this a director cannot spawn ahead of anybody[/b], and spawning ahead is
## most of what makes a director feel like a director rather than like a random spawner.
## "Ahead" is not a direction — a party walking a horseshoe corridor is facing away from
## where it is going for half the map — so it has to be a position along the route the
## level was built around.
##
## [b]The route is the game's, and it is cheap to give.[/b] A campaign map already knows
## its own critical path: it is the line the level designer built the fight along, and in
## this family's code-built maps it is a handful of constants. dot-map's catalogue is
## where a game would keep it.
##
## A flat route — no route at all — degrades to "distance from the party", which is what
## a director in an arena should do anyway. The class answers that honestly rather than
## refusing.

## The route, in order, in world space. Empty for a map with no critical path.
var points: PackedVector3Array = PackedVector3Array()

## Cumulative distance along [member points]. Built with the route, never recomputed.
var _distance: PackedFloat32Array = PackedFloat32Array()


func _init(p_points: PackedVector3Array = PackedVector3Array()) -> void:
	set_route(p_points)


func set_route(p_points: PackedVector3Array) -> void:
	points = p_points
	_distance = PackedFloat32Array()

	if points.is_empty():
		return

	var total := 0.0
	_distance.append(0.0)

	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
		_distance.append(total)


func has_route() -> bool:
	return points.size() >= 2


## The total length of the route, in metres.
func length() -> float:
	return _distance[_distance.size() - 1] if _distance.size() > 0 else 0.0


## How far along the route [param p] is, in metres. 0 when there is no route.
##
## Projected onto the nearest segment rather than snapped to the nearest point, because
## a route of six points across a hundred metres would otherwise quantise every player's
## progress to twenty-metre steps — and the relax distance is measured in tens of metres.
func flow_of(p: Vector3) -> float:
	if not has_route():
		return 0.0

	var best := 0.0
	var best_sq := INF

	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var segment := b - a
		var length_sq := segment.length_squared()

		if length_sq < 0.0001:
			continue

		var t := clampf((p - a).dot(segment) / length_sq, 0.0, 1.0)
		var closest := a + segment * t
		var d_sq := p.distance_squared_to(closest)

		if d_sq < best_sq:
			best_sq = d_sq
			best = _distance[i] + sqrt(length_sq) * t

	return best


## The world position at [param flow] metres along the route.
##
## Clamped to the ends rather than extrapolated: a director asked for a point forty
## metres past the end of a map should spawn at the end of the map, not in the void
## beyond it.
func position_at(flow: float) -> Vector3:
	if points.is_empty():
		return Vector3.ZERO

	if not has_route():
		return points[0]

	var wanted := clampf(flow, 0.0, length())

	for i in range(points.size() - 1):
		if wanted <= _distance[i + 1]:
			var span := _distance[i + 1] - _distance[i]

			if span < 0.0001:
				return points[i]

			return points[i].lerp(points[i + 1], (wanted - _distance[i]) / span)

	return points[points.size() - 1]


func describe() -> Dictionary:
	return {
		"points": points.size(),
		"length": "%.0f m" % length(),
	}
