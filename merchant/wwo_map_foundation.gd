extends Control
## Host for the synchronized main-game map. Owns presentation resources only.
signal map_ready
signal map_failed(message: String)
signal place_selected(place_id: String)
const MAP_SCENE = preload("res://shared/wwo_map/scenes/presentation/map/globe_renderer.tscn")
@export var preview_controls: bool = false
var controller: WWOMapGlobeController
var renderer: WWOMapGlobeRenderer
var loaded: bool = false
var failure: String = ""
var content: WWOMapHistoricalLoader
var politics: WWOMapRuntimePoliticalEntityView
var evidence: WWOMapHistoricalPoliticalEvidenceView
var catalog := WWOMapVNextSpatialCatalog.new()
var reference_date: Dictionary = {"year":1900,"month":1,"day":1}
var _worker: Thread
var _started: int
var _stage: Label
var _focus: String = "place:paris"

func _ready() -> void:
	_started = Time.get_ticks_msec()
	var background := TextureRect.new()
	background.texture = preload("res://assets/maps/background/galactic_chart.png")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	controller = WWOMapGlobeController.new(); add_child(controller)
	controller.set_map_mode("geographic")
	controller.selection_changed.connect(func(): place_selected.emit(controller.selected_place_id))
	_stage = Label.new(); _stage.text="正在读取 WWO 主地图组件与原地理资料…"
	_stage.position=Vector2(16,70); add_child(_stage)
	if preview_controls:
		var bar := HBoxContainer.new(); bar.position=Vector2(12,12); add_child(bar)
		for id: String in ["place:paris","place:lyon",""]:
			var button := Button.new(); button.text={"place:paris":"巴黎","place:lyon":"里昂","":"全球"}[id]
			bar.add_child(button); button.pressed.connect(focus_place.bind(id))
		var political := CheckButton.new(); political.text="历史政治参考"; bar.add_child(political)
		political.toggled.connect(func(on: bool): controller.set_map_mode("political" if on else "geographic"))
	_worker=Thread.new(); _worker.start(_prepare)

func _prepare() -> Dictionary:
	# Same admitted content path as FormalWorldMenu._read_preview. No world build.
	var provenance := WWOMapHistoricalProvenanceFoundation.new()
	if not provenance.load_current(): return {"error":provenance.initialization_error}
	var prepared := WWOMapHistoricalLoader.new()
	if not prepared.load_current(provenance.gate()): return {"error":"\n".join(prepared.errors)}
	prepared.provenance=provenance
	var historical := WWOMapHistoricalPoliticalEvidenceCatalog.new()
	var identities := WWOMapRuntimePoliticalEntityRegistry.new()
	if not historical.configure(WWOMapHistoricalPoliticalEvidenceCatalog.DEFAULT_PATH,provenance.gate()): return {"error":historical.initialization_error}
	if not identities.configure(historical): return {"error":identities.initialization_error}
	return {"content":prepared,"politics":WWOMapRuntimePoliticalEntityView.new(identities.snapshot()),
		"evidence":WWOMapHistoricalPoliticalEvidenceView.new(historical.read_only_snapshot()),
		"meshes":WWOMapGlobeRenderer.prepare_source_geometry(prepared.geometry_content)}

func _process(_delta: float) -> void:
	if _worker==null or _worker.is_alive(): return
	var result: Dictionary=_worker.wait_to_finish(); _worker=null
	if result.has("error"):
		failure=str(result.error); _stage.text="MAP_INTEGRATION_BLOCKED\n"+failure
		push_error(_stage.text); map_failed.emit(failure); set_process(false); return
	content=result.content; politics=result.politics; evidence=result.evidence
	if not catalog.load_legacy_world_map():
		failure=str(catalog.errors()); _stage.text=failure; map_failed.emit(failure); return
	# Match the main menu: create the renderer only after admitted content exists.
	# External resizing can otherwise enable its processing before configure().
	renderer = MAP_SCENE.instantiate(); add_child(renderer)
	move_child(renderer,1)
	renderer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	renderer.show_footer = true
	renderer.map_notice.connect(func(message: String): print("WWO_MAP_NOTICE ",message))
	renderer.relief.decode_asset=WWOMapGeographyLoader.decode_relief
	renderer.configure(content.geometry_content,controller)
	renderer.install_source_geometry(result.meshes)
	renderer.local_content=content.local_spatial
	renderer.strategic_content=content.strategic_spatial
	loaded=true; _refresh_geography(); focus_place(_focus)
	_stage.hide(); set_process(false)
	print("WWO_MAP_FOUNDATION_READY ",JSON.stringify({"prepare_ms":Time.get_ticks_msec()-_started,"renderer":renderer.get_script().resource_path,"controller":controller.get_script().resource_path,"world_created":false}))
	map_ready.emit()

func _refresh_geography() -> void:
	if not loaded:return
	var places: Array[Dictionary]=[]
	places.append_array(catalog.cities()); places.append_array(catalog.ports())
	var units := WWOMapCurrentWorldPoliticalProjection.map_units(politics,evidence)
	renderer.refresh(politics,evidence,null,places,reference_date,content.resolve_map(reference_date,units))

func set_reference_date(value: Dictionary) -> void:
	if value.is_empty():return
	var day := {"year":value.get("year"),"month":value.get("month"),"day":value.get("day")}
	if day==reference_date:return
	reference_date=day; _refresh_geography()

func focus_place(id: String) -> void:
	_focus=id
	if not loaded:return
	controller.suspend_motion()
	if id.is_empty():
		controller.region_camera.active=false; controller.region_camera.leave_local()
		controller.set_world_zoom(0.86)
	else:
		var place: Dictionary=catalog.get_place(id)
		if renderer.focus_place(place): controller.select("",id)

func visible_point(unit: Vector3) -> Vector2:
	if not loaded:return Vector2(INF,INF)
	if not controller.region_camera.active and (controller.orientation()*unit).z<=0.0:return Vector2(INF,INF)
	if controller.region_camera.active and unit.dot(controller.region_camera.tangent_frame.z)<=0.0:return Vector2(INF,INF)
	var point := renderer.screen_point(unit)
	if not Rect2(Vector2.ZERO,size).has_point(point):return Vector2(INF,INF)
	# Use the main map's inverse pick as the displayed-surface admission check.
	var picked := renderer.unit_at(point)
	if picked.is_zero_approx() or picked.dot(unit)<0.9999:return Vector2(INF,INF)
	return point

func focus_region(id: String) -> void:
	if not loaded:return
	var coordinates: Array=catalog.get_place(id).get("lon_lat",[])
	if coordinates.size()!=2:return
	var unit := WWOMapGlobeProjection.lon_lat_to_unit(Vector2(float(coordinates[0]),float(coordinates[1])))
	# The main controller owns REGION entry, tangent frame, bearing and scale.
	controller.focus_region(unit,size*0.5,3.0,0.0,size)

func _exit_tree() -> void:
	if _worker!=null:
		_worker.wait_to_finish(); _worker=null
