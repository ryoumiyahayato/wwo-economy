extends SceneTree
var scene: Node
var previous: String=""
var count: int=0
func _initialize() -> void:_run.call_deferred()
func _run() -> void:
	root.size=Vector2i(1280,720)
	scene=load("res://merchant/main.tscn").instantiate();root.add_child(scene)
	var deadline: int=Time.get_ticks_msec()+540000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if FileAccess.file_exists("/workspace/shared/economy_07_playability/stop_gui.request"):
			scene._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
			return
		var state: String=str(scene.city_home)+"|"+str(scene.message)+"|"+str(scene.selected_tab)+"|"+str(scene.selected_place)+"|"+str(scene.current_minute)+"|"+str(scene.snapshot.get("slot",0))+"|"+str(scene.dialog.visible)
		if state!=previous and not scene.busy and not scene.stepping:
			previous=state
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/workspace/shared/economy_07_playability/gui_frames/frame_%03d.png"%count)
			print("GUI_STATE ",count," ",state," site=",scene.selected_site," city=",JSON.stringify(scene.city_state)," supply=",JSON.stringify(scene.snapshot.get("supply",{})))
			count+=1
		await create_timer(0.3).timeout
	scene._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
