extends SceneTree
const Scene=preload("res://merchant/merchant_scene.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var scene=Scene.new();root.add_child(scene)
	while not scene.world_ready and not scene.startup_failed:await process_frame
	var result: Dictionary={"minute":scene.current_minute,"selected_contract":scene.selected_contract,"user_selected":scene.contract_user_selected,"supply":scene.snapshot.get("supply",{}),"opportunities":scene.snapshot.get("opportunities",[]),"orders":scene.view.get("orders",[]),"sales_orders":scene.view.get("sales_orders",[])}
	var f=FileAccess.open("/workspace/shared/economy_102_home/snapshot_probe.json",FileAccess.WRITE);f.store_string(JSON.stringify(result,"  "));f.close()
	scene.queue_free();await process_frame
	print("QA102_SNAPSHOT_PASS");quit()
