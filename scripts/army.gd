class_name Army
extends RefCounted
## A troop group marching between two nodes. Pure data.

var from_id: int
var to_id: int
var faction: int          # CityNode.OWNER_*
var troops: int
var depart_time: float    # game.time at launch
var travel_time: float    # seconds to reach destination

func arrival_time() -> float:
	return depart_time + travel_time

func progress(current_time: float) -> float:
	## 0.0 at launch, 1.0 on arrival.
	if travel_time <= 0.0:
		return 1.0
	return clampf((current_time - depart_time) / travel_time, 0.0, 1.0)
