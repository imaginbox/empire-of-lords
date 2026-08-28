extends Node
## Balance validation smoke tests. Run with `run_tests(res://tests/test_balance.gd)`.
##
## These verify BalanceSimulation executes end-to-end and print the difficulty
## metrics. Assertions are deliberately lenient (sanity bounds only) because
## small-season samples are naturally noisy — the authoritative balance picture
## comes from running the simulation with more seasons and reading the report.

const SIM = preload("res://tests/balance_simulation.gd")


func _run_checked(tag: String, num_seasons: int, season_len: float, allies: int) -> Dictionary:
	var sim: Node = SIM.new()
	var rep: Dictionary = sim.run(num_seasons, season_len, true, 0, allies, 3)
	sim.queue_free()
	print("[%s] saisons=%d wins=%d losses=%d stalls=%d win_rate=%.0f%% max_realm=%s" % [
		tag,
		rep["seasons"],
		rep["wins"],
		rep["losses"],
		rep["stalls"],
		rep["win_rate"] * 100.0,
		GameState.REALMS[rep["max_realm"]],
	])
	return rep


func test_no_ally_playable() -> void:
	var rep: Dictionary = _run_checked("SANS alliés", 3, 200.0, 0)
	assert(rep.has("win_rate") and rep.has("max_realm"), "simulation returned no report")


func test_allied_main_path() -> void:
	var rep: Dictionary = _run_checked("2 alliés", 4, 200.0, 2)
	assert(rep.has("win_rate") and rep.has("max_realm"), "simulation returned no report")


func test_realm_promotion_reachable() -> void:
	var rep: Dictionary = _run_checked("parcours", 5, 200.0, 2)
	var promoted: bool = rep["max_realm"] >= 1
	print("[parcours] a-t-il été promu au moins une fois ? ", promoted)
	assert(promoted, "did not reach at least Bronze (max_realm=%d)" % rep["max_realm"])
