extends SceneTree
class QuietScene:
	extends "res://merchant/merchant_scene.gd"
	func _start() -> void:pass
	func _process(_delta: float) -> void:pass
	func _observe() -> void:pass
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var scene=QuietScene.new();root.add_child(scene);await process_frame
	scene.world_ready=true;scene.busy=false;scene.pending_requests.clear()
	scene.snapshot={"slot":4,"business":{"offers":[]},"player_place":"place:paris"}
	scene.view={"cash":320,"reserved":0,"operations":[]}
	scene._show_guide();assert(not scene.feedback_entry.disabled)
	scene._guide_action("feedback")
	assert(scene.confirm_kind=="switch" and scene.confirm_payload=={"slot":5,"feedback_opt_in":true})
	assert(scene.confirm_detail.text.contains("旧1.0.1/1.0.2不能读取") and scene.confirm_detail.text.contains("数秒"))
	assert(scene.confirm_detail.text.contains("可能被NPC") and scene.confirm_detail.text.contains("不表示停止挂牌"))
	assert(scene.snapshot["slot"]==4,"Preview must not enter or create a world")
	scene._cancel_preview();scene.dialog.hide();assert(scene.confirm_kind.is_empty())
	for slot: int in [1,2,3,4]:
		scene.snapshot["slot"]=slot;scene._time_button(4)
		assert(scene.confirm_detail.text.contains("普通槽1–4与实验槽5分别保存"))
		assert(scene.confirm_payload["slot"]==slot%4+1,"Ordinary rotation must never include experiment")
		scene._cancel_preview();scene.dialog.hide()
	scene.snapshot["slot"]=5;scene._time_button(4);assert(scene.confirm_payload["slot"]==4)
	scene._cancel_preview();scene.dialog.hide();scene._show_guide();assert(scene.feedback_entry.disabled)
	scene._refresh();assert(scene.header.text.contains("反馈实验"))
	scene.snapshot["slot"]=4;scene.snapshot["external_host"]=true;scene._show_guide();assert(not scene.feedback_entry.visible)
	scene._guide_action("feedback");assert(scene.confirm_kind.is_empty())
	scene.snapshot["external_host"]=false
	scene._show_guide();assert(scene.guide_text.text.contains("不表示停止挂牌"));scene.guide.hide()
	for canvas: Vector2 in [Vector2(960,600),Vector2(1180,812),Vector2(1280,720)]:
		for slot: int in [4,5]:
			scene.snapshot["slot"]=slot;scene.snapshot["personal_available"]=2500
			scene.layout_size=canvas;scene._set_tab(0);scene._refresh()
			assert(scene.header.text.count("\n")==1,"Detailed header must have two explicit lines")
			assert(scene.header.get_minimum_size().y<=scene.header.size.y,"Header text must fit its reserved area")
			assert(scene.header.get_rect().end.y+8<=scene.map_buttons[0].position.y,"Header cannot overlap cities")
			assert(scene.header.get_minimum_size().x<=scene.header.size.x,"Header must fit before identity button")
	scene.busy=true;scene._guide_action("feedback");assert(scene.confirm_kind.is_empty())
	scene.queue_free();await process_frame
	print("QA_FLOW_PLAYER_UI_PASS preview_cancel ordinary_rotation explicit_entry experiment_badge external_host_block")
	quit()
