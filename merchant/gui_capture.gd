extends SceneTree
var scene: Node
var previous: String=""
var count: int=0
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	root.size=Vector2i(960,600)
	scene=load("res://merchant/main.tscn").instantiate();root.add_child(scene)
	var deadline: int=Time.get_ticks_msec()+165000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		var state: String=str(scene.city_home)+"|"+str(scene.message)+"|"+str(scene.selected_tab)+"|"+str(scene.selected_place)+"|"+str(scene.current_minute)+"|"+str(scene.snapshot.get("slot",0))
		if state!=previous and not scene.busy:
			previous=state
			root.get_texture().get_image().save_png("/workspace/scratch/0174c283a033/economy_prototype_06_review/gui_frames/frame_%03d.png"%count)
			print("GUI_STATE ",count," ",state," running=",scene.running," selected_site=",scene.selected_site)
			count+=1
		await create_timer(0.3).timeout
	scene._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
