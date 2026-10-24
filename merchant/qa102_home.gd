extends SceneTree
const Scene=preload("res://merchant/merchant_scene.gd")
class QuietScene:
	extends "res://merchant/merchant_scene.gd"
	func _start() -> void:pass
	func _process(_delta: float) -> void:pass
	func _observe() -> void:pass
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var scene=QuietScene.new();root.add_child(scene)
	await process_frame
	assert(scene.header.text.contains("读取"))
	assert(scene._home_contract_text().contains("读取"))
	scene.world_ready=true;scene.busy=false;scene.pending_requests.clear()
	scene.view={"cash":300,"reserved":20,"operations":[{"site_id":"site:test","stock_place_id":"place:paris","inventory":{"grain":5},"free_inventory":{"grain":3}}]}
	scene.snapshot={"personal_available":2498,"business":{"offers":[]},"player_place":"place:paris"}
	scene.selected_place="place:marseille";scene._refresh()
	assert(scene.facilities[1].disabled and scene.facilities[1].text.contains("无自有仓"))
	scene.selected_place="place:paris";scene._refresh();assert(not scene.facilities[1].disabled)
	scene._open_supply();assert(scene.selected_tab==0 and not scene.city_home)
	for tab: int in range(7):
		scene._set_tab(tab)
		assert(not scene.city_home and scene.section_select.visible and scene.detail.visible)
		assert(not scene.home_delegate.visible)
		scene._return_city();assert(scene.city_home and scene.home_delegate.visible)
	for size: Vector2 in [Vector2(960,600),Vector2(1066,600),Vector2(1280,720)]:
		scene.layout_size=size;scene._layout_controls()
		assert(scene.home_goal.get_rect().end.y<=scene.facilities[0].position.y)
		assert(scene.home_next.get_rect().end.y<=scene.notice.position.y)
		for b: Button in scene.facilities:assert(b.size.y>=48 and b.get_rect().end.x<=size.x)
		assert(scene.home_delegate.get_rect().end.x<=size.x)
		assert(scene.buttons[4].get_rect().end.x<=size.x)
	scene.snapshot["opportunities"]=[{"id":"old","status":"OVERDUE","quantity":80,"good":"grain","deadline":1000},{"id":"active","status":"ACCEPTED","accept_action":"a","quantity":1,"good":"soap","deadline":18000,"ontime":0,"late":0,"paid":0}]
	scene.snapshot.make_read_only()
	scene._focus_contract();assert(scene.selected_contract=="active" and scene.snapshot["supply"]["id"]=="active")
	scene.contract_user_selected=true;scene.selected_contract="old";scene.snapshot["supply"]=scene.snapshot["opportunities"][0]
	scene._focus_contract();assert(scene.snapshot["supply"]["id"]=="old")
	assert(scene._home_contract_text().contains("无本商号履约记录") and not scene._home_contract_text().contains("到账0"))
	scene.contract_user_selected=false
	scene.snapshot["opportunities"]=[{"id":"old_done","status":"COMPLETED","accept_action":"a","ended_minute":3000,"accepted_minute":1000,"deadline":4000},{"id":"new_done","status":"COMPLETED","accept_action":"b","ended_minute":18000,"accepted_minute":12000,"deadline":19000}]
	scene._focus_contract();assert(scene.selected_contract=="new_done","Recently completed contract must remain understandable")
	scene.snapshot["supply"]={}
	scene.selected_tab=0;scene.world_ready=false;scene.startup_failed=true;scene._refresh();assert(scene.header.text.contains("失败"))
	scene.queue_free();await process_frame
	var feedback=Scene.new();feedback.observed_supply={"id":"a","paid":0,"ontime":0,"status":"ACCEPTED"}
	feedback._receive({"id":1,"kind":"advance","ok":true,"result":{},"view":{"firm":{},"minute":100,"site":"site:test","supply":{"id":"b","status":"COMPLETED","paid":50,"ontime":1}}})
	assert(not feedback.message.contains("本次到账"),"Changing focus must not invent a new payment")
	feedback.free()
	print("QA102_HOME_PASS loading unknown local_inventory_guard all_seven_routes responsive_960_1066_1280")
	quit()
