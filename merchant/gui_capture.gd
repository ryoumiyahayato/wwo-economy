extends SceneTree
## Capture the existing native scenes after rendering. No replacement UI.
## --output ABS_DIR [--scene main|global] [--seconds 30] [--size 1280x800]
## --sequence requires a NEW user-data directory supplied by the launcher.
var scene: Node
var output: String=""
var scene_name: String="main"
var seconds: int=30
var window_size:=Vector2i(1280,800)
var sequence: bool=false
var failed: bool=false

func _initialize() -> void:
	_run.call_deferred()

func _fail(message: String) -> void:
	failed=true
	push_error("GUI_CAPTURE: "+message)
	if is_instance_valid(scene):scene.queue_free()
	quit(1)

func _run() -> void:
	var args:=OS.get_cmdline_user_args()
	var index: int=0
	while index<args.size():
		var key: String=args[index]
		if key=="--sequence":sequence=true;index+=1;continue
		if index+1>=args.size():_fail("Missing value for "+key);return
		var value: String=args[index+1]
		match key:
			"--output":output=value
			"--scene":scene_name=value
			"--seconds":seconds=clampi(int(value),1,600)
			"--size":
				var parts:=value.split("x")
				if parts.size()!=2:_fail("Expected WIDTHxHEIGHT");return
				window_size=Vector2i(int(parts[0]),int(parts[1]))
			_:_fail("Unknown option "+key);return
		index+=2
	if not output.is_absolute_path() or output.begins_with("res://") or output.begins_with("user://"):
		_fail("--output must be an explicit absolute filesystem directory");return
	if scene_name not in ["main","global"] or window_size.x<960 or window_size.y<600:
		_fail("Use main/global and a viewport of at least 960x600");return
	if DisplayServer.get_name()=="headless":_fail("A real rendering display is required; headless screenshots are not valid");return
	if DirAccess.make_dir_recursive_absolute(output)!=OK:_fail("Cannot create output directory");return
	# Never overwrite captures from another run.
	if not DirAccess.get_files_at(output).is_empty():_fail("Output directory must be empty");return
	root.size=window_size
	if sequence:
		await _sequence()
		return
	scene=load("res://merchant/"+("main" if scene_name=="main" else "global_market")+".tscn").instantiate()
	root.add_child(scene)
	var previous: String="";var count: int=0
	var deadline: int=Time.get_ticks_msec()+seconds*1000
	while Time.get_ticks_msec()<deadline:
		await create_timer(0.3).timeout
		var state: String
		if scene_name=="main":
			if scene.busy or scene.stepping:continue
			state=str(scene.city_home)+"|"+scene.message+"|"+str(scene.selected_tab)+"|"+scene.selected_place+"|"+str(scene.current_minute)+"|"+str(scene.dialog.visible)
		else:
			if not scene.pending.is_empty():continue
			state=scene.note.text+"|"+str(scene.map_view.global_mode)+"|"+scene.map_view.selected_place+"|"+scene.map_view.commodity+"|"+str(scene.map_view.side.visible)
		if state!=previous:
			previous=state
			await _capture("frame_%03d"%count);count+=1
	# Stop the worker without issuing a save, time or domain command.
	scene.queue_free();await process_frame;quit(1 if failed else 0)

func _capture(name: String) -> void:
	await process_frame
	RenderingServer.force_draw()
	var frame:=root.get_texture().get_image()
	if frame==null or frame.is_empty():_fail("Rendered viewport is empty");return
	var error: Error=frame.save_png(output.path_join(name+".png"))
	if error!=OK:_fail("PNG write failed: "+error_string(error));return
	print("GUI_CAPTURE ",name," ",frame.get_size()," display=",DisplayServer.get_name()," renderer=",RenderingServer.get_video_adapter_name())

func _wait_ready(global_scene: bool) -> bool:
	var deadline: int=Time.get_ticks_msec()+90000
	while Time.get_ticks_msec()<deadline:
		await create_timer(0.1).timeout
		if global_scene:
			if not scene.map_view.map_base.failure.is_empty():_fail(scene.map_view.map_base.failure);return false
			if scene.pending.is_empty() and scene.map_view.map_base.loaded and not scene.map_view.market.is_empty():
				if scene.map_view.map_base.renderer.current_view_map_status().get("state")=="installed":return true
		else:
			if scene.startup_failed:_fail(scene.message);return false
			if scene.world_ready and not scene.busy:return true
	_fail("Scene did not become ready before timeout");return false

func _sequence() -> void:
	# Only this explicit screenshot mode seeds a disposable Formal world. It
	# refuses existing user data, never reads an archived/player save, and uses
	# the original bootstrap, clock, persistence and Runtime handoff unchanged.
	const Save=preload("res://merchant/merchant_save.gd")
	const Consumer=preload("res://merchant/consumer_access_opening.gd")
	const Plans=preload("res://merchant/merchant_plans.gd")
	if OS.get_environment("WWO_GUI_CAPTURE_DISPOSABLE")!="1":_fail("Set WWO_GUI_CAPTURE_DISPOSABLE=1 with a new isolated user-data directory");return
	for slot: int in range(1,8):
		if Save.has_slot(slot):_fail("Sequence refuses an existing save directory");return
	if FileAccess.file_exists("user://merchant_host.cfg"):_fail("Sequence refuses existing preferences");return
	var built: WorldBuildResult=Consumer.build("consumer_combined")
	if not built.success:_fail(built.error);return
	if not Consumer.apply_condition(built.world,"consumer_combined").get("accepted",false):_fail("Existing development opening rejected");return
	built.world.economy_r1._dated_input_procurement_enabled=true
	if not built.world.economy_state.enable_reference_market("shocks"):_fail("Reference initialization rejected");return
	for day: int in 3:
		if not built.simulation_step.advance_minutes(1440).get("success",true):_fail("Formal day advancement failed");return
	var saved: Dictionary=Save.new().save(built,6,Plans.new().state)
	if not saved.get("success",false):_fail(str(saved));return
	print("GUI_CAPTURE_DISPOSABLE_WORLD minute=",built.world.game_clock.total_minutes()," userdata=",OS.get_user_data_dir()," basis=FRESH_CONSUMER_COMBINED_THREE_DAYS_NOT_PRIOR_EXPERIMENT")
	built=null
	scene=load("res://merchant/global_market.tscn").instantiate();root.add_child(scene)
	scene.actions[0].pressed.emit()
	if not await _wait_ready(true):return
	scene.map_view.side.hide()
	await _capture("01_global_default")
	scene.map_view.select_place("market:country_fra")
	await _capture("02_france_wheat")
	scene.map_view.mode_button.pressed.emit()
	var order_ids: Array=scene.map_view.network.get("edges",{}).keys()
	if not order_ids.is_empty():scene.map_view.select_order(str(order_ids[0]))
	print("GUI_CAPTURE_PHYSICAL_ORDERS ",JSON.stringify(scene.map_view.network.get("edges",{})))
	await _capture("03_physical_orders")
	# The original button relinquishes the same Runtime to merchant/main.tscn.
	scene.actions[6].pressed.emit()
	var deadline: int=Time.get_ticks_msec()+90000
	while is_instance_valid(scene) and Time.get_ticks_msec()<deadline:await process_frame
	if is_instance_valid(scene):_fail("Original business handoff timed out");return
	for child: Node in root.get_children():
		if child.get_script()==load("res://merchant/merchant_scene.gd"):scene=child;break
	if not is_instance_valid(scene):_fail("Original merchant scene missing after handoff");return
	if not await _wait_ready(false):return
	scene.guide.get_ok_button().pressed.emit()
	print("GUI_CAPTURE_BUSINESS minute=",scene.current_minute," order_ids=",scene.snapshot.firm.get("orders",[]).map(func(o: Dictionary):return o.id))
	await _capture("04_merchant_business")
	if scene.current_minute!=4320:_fail("Capture actions unexpectedly advanced the world");return
	scene.queue_free();await process_frame;quit(1 if failed else 0)
