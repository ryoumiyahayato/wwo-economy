extends SceneTree
const Opening=preload("res://merchant/merchant_opening.gd")
class QuietScene:
	extends "res://merchant/merchant_scene.gd"
	func _start() -> void:pass
	func _process(_delta: float) -> void:pass
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var scene=QuietScene.new();root.add_child(scene);await process_frame
	scene.world_ready=true;scene.busy=false;scene.pending_requests.clear()
	scene.news.assign(["真实采购已受理", "到仓 bread 2"])
	scene.observed_orders={"order:test":{"pending":0,"transit":2,"delivered":0,"cancelled":0}}
	scene.selected_contract="chosen";scene.contract_user_selected=true
	var saved_news: Array=scene.news.duplicate(true)
	var saved_orders: Dictionary=scene.observed_orders.duplicate(true)
	var view: Dictionary={"firm":{"cash":302,"reserved":0,"operations":[],"orders":[],"sales_orders":[]},"minute":4321,"site":Opening.SITE,"slot":5,"opportunities":[],"business":{}}
	scene._receive({"id":1,"kind":"switch","ok":false,"result":{"success":false,"message":"Injected save failure"},"view":view})
	var kept: bool=scene.news==saved_news and scene.observed_orders==saved_orders and scene.selected_contract=="chosen" and scene.contract_user_selected
	print("PASS " if kept else "FAIL ","failed switch retains player news, order observations and manual selection")
	scene._receive({"id":2,"kind":"switch","ok":true,"result":{"success":true},"view":view})
	var cleared: bool=scene.news.is_empty() and scene.observed_orders.is_empty() and not scene.contract_user_selected
	print("PASS " if cleared else "FAIL ","successful switch resets observations")
	scene.queue_free();await process_frame
	quit(0 if kept and cleared else 1)
