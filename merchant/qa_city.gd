extends SceneTree
var scene: Node
func _initialize() -> void:_run.call_deferred()
func _wait_idle() -> void:
	while scene.busy or scene.stepping:await process_frame
func _run() -> void:
	scene=load("res://merchant/main.tscn").instantiate();root.add_child(scene)
	await process_frame;await _wait_idle()
	assert(scene.world_ready and scene.city_home and scene.home_goal.visible)
	assert(not scene.primary.visible and not scene.section_select.visible)
	var minute: int=scene.current_minute
	for i: int in range(5):
		scene._enter_facility(i);await _wait_idle()
		assert(not scene.city_home and scene.detail.visible and scene.primary.visible)
		scene._return_city();assert(scene.city_home and not scene.primary.visible)
	for tab: int in range(7):
		scene._set_tab(tab);assert(scene.section_select.selected==tab)
		scene._show_confirm("取消检查");scene.dialog.hide();scene._cancel_preview()
		assert(scene.confirm_kind.is_empty())
	scene._select_place("place:marseille");assert(scene.city_home and scene.facilities[1].disabled and scene.facilities[4].disabled)
	scene._select_place("place:paris")
	assert(scene.current_minute==minute)
	print("CITY_HEADLESS_PASS real_05_restore facility_navigation seven_actions_retained cancel no_time_mutation")
	print("GOAL ",scene.home_goal.text)
	scene._time_button(3);await _wait_idle();assert(not scene.snapshot.get("save_pending",true))
	print("CITY_SAVE_PASS ",scene.current_minute)
	scene._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
