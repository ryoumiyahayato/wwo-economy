extends SceneTree
const Runtime=preload("res://merchant/merchant_runtime.gd")
const Save=preload("res://merchant/merchant_save.gd")
const MapScene=preload("res://merchant/economy_map_view.tscn")
var runtime: RefCounted
func _initialize() -> void:run.call_deferred()

func response(id: int) -> Dictionary:
	var start: int=Time.get_ticks_msec()
	while Time.get_ticks_msec()-start<60000:
		for row: Dictionary in runtime.poll():
			if int(row.id)==id:return row
		await process_frame
	assert(false,"Timed out waiting for worker response "+str(id));return {}

func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	var before: PackedByteArray=FileAccess.get_file_as_bytes(Save.path(5))
	assert(not before.is_empty())
	runtime=Runtime.new()
	assert(runtime.start_observer(99)==ERR_FILE_NOT_FOUND)
	assert(runtime.start_observer(5)==OK)
	var first: Dictionary=await response(0);assert(first.ok,str(first))
	var view: Dictionary=first.view
	assert(view.slot==5 and view.observer_only and not view.save_pending)
	for kind: String in ["advance","buy","save","switch","plan","export","stop"]:assert(runtime.submit(kind)==-1)
	var map_view: Control=MapScene.instantiate();root.add_child(map_view)
	map_view.update_snapshot(view)
	assert(map_view.contacts.get("schema")=="merchant_observed_contacts_v2","Map discarded current contacts schema")
	assert(map_view.contacts==view.market_contacts)
	var started: int=Time.get_ticks_msec()
	while not map_view.map_base.loaded:
		assert(map_view.map_base.failure.is_empty(),map_view.map_base.failure)
		assert(Time.get_ticks_msec()-started<30000,"Shared map preparation timeout")
		await process_frame
	assert(map_view.map_base.renderer.get_script().resource_path=="res://shared/wwo_map/scripts/presentation/map/globe_renderer.gd")
	for id: String in ["place:paris","place:lyon","place:marseille"]:
		map_view.focus_place(id)
		assert(id in map_view.details.text)
	map_view.map_base.controller.focus(-map_view._unit("place:paris"))
	assert(not map_view.map_base.visible_point(map_view._unit("place:paris")).is_finite())
	for iteration: int in range(3):
		var id: int=runtime.submit("observe");assert(id>0)
		var row: Dictionary=await response(id)
		assert(row.ok and row.generation==first.generation and row.view==view,"Observe changed confirmed values")
		map_view.update_snapshot(row.view)
	# Missing-coordinate presentation keeps the original economic identity and facts.
	var detached: Dictionary=view.duplicate(true)
	detached.market_network.nodes["place:missing_coordinate_fixture"]={"known_own_sites":[],"known_own_stock_by_good":{},"known_own_free_by_good":{},"known_own_reserved_by_good":{}}
	map_view.update_snapshot(detached)
	detached.market_network.nodes.clear()
	assert(map_view.network.nodes.has("place:missing_coordinate_fixture"),"View did not detach caller values")
	assert("place:missing_coordinate_fixture" in map_view.unlocated)
	map_view.select_place("place:missing_coordinate_fixture");assert("未定位" in map_view.details.text)
	var close_id: int=runtime.submit("close");var closed: Dictionary=await response(close_id)
	assert(closed.ok and closed.result.persistence=="READ_ONLY_NO_WRITE")
	while not runtime.finished():await process_frame
	runtime.join_finished();runtime=null
	assert(before==FileAccess.get_file_as_bytes(Save.path(5)),"Observer changed save bytes")
	map_view.queue_free()
	var output: Dictionary={"status":"PASS","slot":5,"minute":view.minute,"generation":first.generation,"refresh_count":3,"save_bytes_unchanged":true,"same_confirmed_values":true,"observer_rejected_mutations":true,"source_ledger_and_lots_preserved_by_exact_file_equality":true,"missing_coordinate_fixture_retained":true,"native_scope":"OBSERVER_AND_DETACHED_VIEW_NOT_HUMAN_GUI"}
	var file:=FileAccess.open(args[0],FileAccess.WRITE);file.store_string(JSON.stringify(output,"\t"));file.close()
	print("QA_ECONOMY_MAP_OBSERVER_PASS ",JSON.stringify(output));quit()
