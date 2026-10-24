extends SceneTree
## Real external owner -> value handoff -> existing runtime -> export -> reentry.
const Runtime=preload("res://merchant/merchant_runtime.gd")
const Opening=preload("res://merchant/merchant_opening.gd")
var failures: int=0
var scene_export: Dictionary={}
var owned_runtimes: Array[RefCounted]=[]
var owned_scene: Node
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> bool:
	if not ok:
		failures+=1;push_error("QA10_HOST_FAIL "+label)
		for worker: RefCounted in owned_runtimes:worker.shutdown_and_join()
		if is_instance_valid(owned_scene):
			if owned_scene.runtime!=null:owned_scene.runtime.shutdown_and_join()
			owned_scene.queue_free()
		quit(1)
	return ok
func response(runtime: RefCounted,id: int) -> Dictionary:
	var until: int=Time.get_ticks_msec()+120000
	while Time.get_ticks_msec()<until:
		for row: Dictionary in runtime.poll():
			if row.get("id")==id:return row
		await create_timer(0.01).timeout
	check(false,"worker response timeout");return {}
func slot_fingerprints() -> Dictionary:
	var values: Dictionary={}
	for slot: int in range(1,5):
		for suffix: String in ["",".bak"]:
			var path: String="user://merchant_host_slot_%d.json"%slot+suffix
			values[path]=FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "ABSENT"
	values["preference"]=FileAccess.get_sha256("user://merchant_host.cfg") if FileAccess.file_exists("user://merchant_host.cfg") else "ABSENT"
	return values
func run() -> void:
	var slots_before: Dictionary=slot_fingerprints()
	# This setup is the external host, not the scene/runtime's opening path.
	var original: WorldBuildResult=WorldBootstrap.new().build(null,[],[],FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT,false,{"format":"HOST_REGION_SELECTION","person_ids":[],"select_people_at_sites":true,"configuration":Opening.opportunities_configuration()})
	if not check(original.success,"external world build"):return
	if not check(Opening.grant_regional_authority(original.world),"preexisting authority"):return
	if not check(original.simulation_step.advance_minutes(1).get("success",true),"host initial step"):return
	var person: String=original.world.player_state.player_id()
	# Explicit legal host fixture: an existing named resident with no player or
	# enterprise role. Materialization consumes a real population claim.
	var player_record: Dictionary=original.world.person_overlay.person(person)
	if not check(original.world.person_overlay.materialize("person:qa10_external_resident","claim:qa10_external_resident",player_record["population_territory_id"],player_record["basic_demographic_identity"],player_record["current_place_id"],{"kind":"generated","basis":"explicit_host_integration_test_resident"}),"materialize existing unauthorized resident"):return
	var initial: Dictionary=original.persistence.snapshot()
	var context: Dictionary=Runtime.host_context(initial,person,Opening.FIRM,Opening.SITE,{},Opening.REGIONAL_AUTHORITY)
	if not check(Runtime._plain(context),"encoded context is pure primitive values"):return
	var encoded_roundtrip: Dictionary=FormalWorldPersistenceDocument.decode(context["snapshot_document"])
	if not check(encoded_roundtrip.get("success",false) and encoded_roundtrip["snapshot"]==initial,"exact payload preserves all legal Variant values losslessly"):return
	# Relinquish mutable ownership. The host keeps only a pure-value checkpoint.
	original=null
	var runtime: RefCounted=Runtime.new();owned_runtimes.append(runtime)
	if not check(runtime.start_external(context)==OK,"start external"):return
	# Input is copied: subsequent caller edits cannot corrupt worker restoration.
	context["person_id"]="tampered-after-start"
	var init: Dictionary=await response(runtime,0)
	if not check(init.get("ok",false),"restore external continuation"):return
	var view: Dictionary=init["view"]
	if not check(view["minute"]==initial["total_minutes"] and view["slot"]==0,"no opening minute or slot"):return
	if not check(view["identity"]["person_id"]==person and view["identity"]["can_manage"],"legal player identity and authority"):return
	if not check(runtime.submit("advance",{"minutes":60})==-1 and runtime.submit("host_advance",{"minutes":60})==-1,"scene cannot own external clock"):return
	if not check(runtime.submit("switch",{"slot":4})==-1,"external context cannot switch to development bootstrap"):return
	var place: String=view["player_place"]
	var observed: Dictionary=await response(runtime,runtime.submit("observe",{"site":Opening.LYON_SITE}))
	if not check(observed["view"]["player_place"]==place and observed["view"]["minute"]==view["minute"],"remote browsing never travels or advances"):return
	if not check(observed["view"]["identity"]["can_manage"],"remote browsing preserves authority"):return
	observed=await response(runtime,runtime.submit("observe",{"site":Opening.SITE,"quantity":2}))
	var request: Dictionary={}
	for offer: Dictionary in observed["view"]["business"].get("offers",[]):
		if offer.get("good")=="grain" and offer.get("seller")=="firm:regional_upstream" and offer.get("can_order",false):request=offer["request"].duplicate(true);break
	if not check(not request.is_empty(),"real executable quote"):return
	var bought: Dictionary=await response(runtime,runtime.submit("buy",request))
	if not check(bought.get("ok",false),"legal action accepted in restored host world"):return
	var obligations: Array=bought["view"]["firm"]["orders"]
	var reserved: Variant=bought["view"]["firm"]["reserved"]
	if not check(not obligations.is_empty() and int(reserved)>0,"unresolved order and real funds reservation exist"):return
	if not check(bought["view"]["minute"]==view["minute"],"purchase does not advance time"):return
	var closed: Dictionary=await response(runtime,runtime.submit("close"))
	if not check(closed.get("ok",false),"leave acknowledged"):return
	while not runtime.finished():await create_timer(0.01).timeout
	runtime.join_finished()
	var exported: Dictionary=closed["result"]["host_context"]
	var decoded: Dictionary=FormalWorldPersistenceDocument.decode(exported["snapshot_document"])
	if not check(decoded.get("success",false),"exported exact-Variant document decodes"):return
	if not check(decoded["snapshot"]["economy_native"]!=initial["economy_native"],"action changes authoritative continuation"):return
	# Original host can legally restore the returned world, with the same orders.
	var restored: WorldBuildResult=FormalPersistence.new().restore_candidate(decoded["snapshot"])
	if not check(restored.success,"host receives legal Formal snapshot"):return
	var firm: Dictionary=LivelihoodAction.query_firm(restored.world,person,Opening.FIRM)
	if not check(firm["orders"]==obligations and firm["reserved"]==reserved,"host retains unresolved order IDs and reservations"):return
	restored=null;runtime=null
	# Re-enter through the exact standalone play scene, using its external adapter.
	var scene: Node=load("res://merchant/main.tscn").instantiate();owned_scene=scene
	if not check(scene.enter_host_context(exported)==OK,"same scene accepts pure context"):return
	scene.host_continuation_ready.connect(func(value: Dictionary)->void:scene_export=value)
	root.add_child(scene)
	var until: int=Time.get_ticks_msec()+120000
	while not scene.world_ready and Time.get_ticks_msec()<until:await create_timer(0.01).timeout
	if not check(scene.world_ready,"same scene reentry restores"):return
	if not check(scene.view["orders"]==obligations and scene.view["reserved"]==reserved,"scene reentry retains orders and reservations"):return
	if not check(scene.current_minute==view["minute"],"no time during leave or scene reentry"):return
	if not check(scene.runtime.advance_from_host(1)>0,"host step accepted"):return
	until=Time.get_ticks_msec()+120000
	while scene.current_minute==int(view["minute"]) and Time.get_ticks_msec()<until:await create_timer(0.01).timeout
	if not check(scene.current_minute==int(view["minute"])+1,"only host advances original clock once"):return
	scene.leave_host_context()
	until=Time.get_ticks_msec()+120000
	while scene_export.is_empty() and Time.get_ticks_msec()<until:await create_timer(0.01).timeout
	if not check(not scene_export.is_empty(),"same scene returns continuation instead of quitting host"):return
	await process_frame
	var invalid_contexts: Dictionary={}
	for bad_field: String in ["person_id","firm_id","site_id","quote_authority_id"]:
		var invalid: Dictionary=exported.duplicate(true);invalid[bad_field]="not-existing"
		invalid_contexts[bad_field]=invalid
	var wrong_schema: Dictionary=exported.duplicate(true);wrong_schema["schema"]="unsupported_external_host_v0"
	invalid_contexts["schema"]=wrong_schema
	var corrupt: Dictionary=exported.duplicate(true)
	corrupt["snapshot_document"][FormalWorldPersistenceDocument.PAYLOAD_FIELD]=""
	invalid_contexts["corrupt_exact_payload"]=corrupt
	var wrong_document: Dictionary=exported.duplicate(true)
	wrong_document["snapshot_document"][FormalWorldPersistenceDocument.SNAPSHOT_SCHEMA_FIELD]="formal_world_v0"
	invalid_contexts["document_schema"]=wrong_document
	var other_person: String=""
	for record: Dictionary in initial.get("persons",{}).get("persons",[]):
		if record.get("person_id","")!=person:other_person=str(record.get("person_id",""));break
	if not check(not other_person.is_empty(),"existing unauthorized person fixture"):return
	var unauthorized: Dictionary=exported.duplicate(true);unauthorized["person_id"]=other_person
	invalid_contexts["existing_unauthorized_person"]=unauthorized
	for bad_field: String in invalid_contexts:
		var invalid: Dictionary=invalid_contexts[bad_field]
		var bad: RefCounted=Runtime.new();owned_runtimes.append(bad)
		if not check(bad.start_external(invalid)==OK,"invalid queued for worker validation"):return
		var rejected: Dictionary=await response(bad,0)
		if not check(not rejected.get("ok",true) and rejected.get("view",{}).is_empty(),"fail closed "+bad_field):return
		bad.shutdown_and_join();bad=null
	var nonvalue: RefCounted=Runtime.new()
	if not check(nonvalue.start_external({"object":RefCounted.new()})==ERR_INVALID_DATA,"object cannot cross thread"):return
	var node:=Node.new()
	if not check(nonvalue.start_external({"node":node})==ERR_INVALID_DATA,"Node cannot cross thread"):return
	node.free()
	if not check(nonvalue.start_external({"resource":Resource.new()})==ERR_INVALID_DATA,"Resource cannot cross thread"):return
	if not check(nonvalue.start_external({})==ERR_INVALID_DATA,"empty external context cannot bootstrap"):return
	if not check(slots_before==slot_fingerprints(),"standalone slots and preference never changed"):return
	print("QA10_HOST_PASS ownership clock legal_action export reentry unresolved_orders reservations invalid_context")
	quit(0 if failures==0 else 1)
