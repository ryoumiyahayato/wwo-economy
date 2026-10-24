extends SceneTree
## Scripted desktop UI interaction, not Android-device evidence.
var scene: Node
var capture_dir: String=""
func _initialize() -> void:call_deferred("run")
func idle() -> void:
	while scene.busy or scene.stepping or not scene.world_ready:await process_frame
	await process_frame
func capture(name: String) -> void:
	await process_frame;await process_frame
	var image: Image=root.get_texture().get_image()
	assert(image.save_png(capture_dir+"/"+name+".png")==OK)
	print("GUI08_CAPTURE ",name," minute=",scene.current_minute," supply=",scene.snapshot.get("supply",{}).get("id"))
func advance_days(days: int) -> void:
	for hour: int in days*24:
		scene._send("advance",{"minutes":60});await idle()
func run() -> void:
	capture_dir=OS.get_cmdline_user_args()[0]
	scene=load("res://merchant/main.tscn").instantiate();root.add_child(scene)
	await idle()
	assert(scene.snapshot["slot"]==4)
	await capture("01_city_new")
	scene._set_tab(0);scene.selected_place="place:lyon";scene.selected_good="grain";scene.quantity.value=8;scene._observe();await idle()
	for q: Dictionary in scene.display_offers:
		if q.get("seller")=="firm:regional_upstream":scene.offer_key=scene._offer_key(q);break
	scene._refresh();scene._primary();await idle();assert(scene.dialog.visible)
	await capture("02_real_purchase_preview")
	scene.dialog.hide();scene._confirm();await idle();assert(scene.message.begins_with("受理"))
	await advance_days(3)
	scene._set_tab(6);await idle()
	await capture("03_arrived_opportunities")
	var chosen: int=-1
	for i: int in scene.snapshot["opportunities"].size():
		var c: Dictionary=scene.snapshot["opportunities"][i]
		if c["id"].begins_with("procurement:grain") and c["status"]=="RECRUITING":chosen=i;break
	assert(chosen>=0)
	scene._row_changed(chosen);await idle()
	scene._primary();assert(scene.dialog.visible)
	await capture("04_small_contract_confirmation")
	scene.dialog.hide();scene._cancel_preview();await idle()
	assert(not scene.snapshot["supply"].has("accept_action"))
	scene._primary();scene.dialog.hide();scene._confirm();await idle()
	assert(scene.snapshot["supply"]["status"]=="ACCEPTED")
	await capture("05_contract_accepted")
	scene.quantity.value=1;scene._primary();assert(scene.dialog.visible)
	await capture("06_real_batch_preview")
	scene.dialog.hide();scene._confirm();await idle()
	await advance_days(2)
	scene._set_tab(6);await idle()
	assert(scene.snapshot["supply"]["paid"]==5 and scene.snapshot["supply"]["ontime"]==1)
	await capture("07_real_payment")
	scene._set_tab(7);await capture("08_business_review")
	scene._return_city();await capture("09_city_completed")
	print("GUI08_UI_PASS cancel_without_contract accepted_real_notice original_purchase_transport_batch_payment")
	scene._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
