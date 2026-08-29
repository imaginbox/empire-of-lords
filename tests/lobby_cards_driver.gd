extends SceneTree
## Lobby cards driver: verifies the 3-card menu switches to the VS and
## Conquest sub-screens and back to the menu.

var t := 0.0
var step := 0
var lobby: Node = null


func _process(delta: float) -> bool:
	t += delta
	if step == 0 and t >= 1.5:
		step = 1
		change_scene_to_file("res://scenes/Lobby.tscn")
		return false
	if step == 1 and current_scene != null and current_scene.name == "Lobby":
		step = 2
		lobby = current_scene
		print("LOBBY loaded")
	if step == 2 and lobby != null and t >= 3.0:
		# verifier le menu par defaut
		print("menu visible: ", lobby.get("_menu_screen").visible)
		print("vs visible au depart: ", lobby.get("_vs_screen").visible)
		# ouvrir VS
		lobby.call("_on_open_vs")
		step = 3
		return false
	if step == 3 and t >= 3.6:
		print("apres _on_open_vs -> menu: ", lobby.get("_menu_screen").visible, ", vs: ", lobby.get("_vs_screen").visible)
		# retour
		lobby.call("_back_to_menu")
		step = 4
		return false
	if step == 4 and t >= 4.2:
		print("apres retour -> menu: ", lobby.get("_menu_screen").visible, ", vs: ", lobby.get("_vs_screen").visible)
		# ouvrir Conquest
		lobby.call("_on_open_conquest")
		step = 5
		return false
	if step == 5 and t >= 4.8:
		print("apres _on_open_conquest -> menu: ", lobby.get("_menu_screen").visible, ", conquest: ", lobby.get("_conquest_screen").visible)
		print("DRIVER END")
		quit(0)
		return true
	if t > 8.0:
		print("DRIVER TIMEOUT")
		quit(1)
		return true
	return false
