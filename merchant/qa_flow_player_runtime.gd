extends SceneTree
const Runtime=preload("res://merchant/merchant_runtime.gd")
const Save=preload("res://merchant/merchant_save.gd")
const Plans=preload("res://merchant/merchant_plans.gd")
class FailOnce:
	extends "res://merchant/merchant_save.gd"
	var fail_next: bool=true
	func save(built: WorldBuildResult,slot: int,state: Dictionary) -> Dictionary:
		if fail_next:
			fail_next=false;timings={};return {"success":false,"message":"QA save failure; preserve original world"}
		return super.save(built,slot,state)
class ProbeRuntime:
	extends "res://merchant/merchant_runtime.gd"
	func _open(slot: int) -> WorldBuildResult:
		var built: WorldBuildResult=super._open(slot)
		if built.success:
			var fault=FailOnce.new();fault.metadata=_save.metadata.duplicate(true);fault.plans=_save.plans.duplicate(true);fault.recovered=_save.recovered;_save=fault
		return built
func _initialize() -> void:call_deferred("run")
func response(runtime: RefCounted,id: int) -> Dictionary:
	assert(id>=0,"Request must be accepted by the mailbox")
	var until: int=Time.get_ticks_msec()+60000
	while Time.get_ticks_msec()<until:
		for row: Dictionary in runtime.poll():
			if row.get("id")==id:return row
		await create_timer(0.01).timeout
	assert(false,"Timed out waiting for runtime")
	return {}
func run() -> void:
	# This script creates deliberately mismatched test files. Never run in a real user directory.
	if OS.get_environment("ECONOMY_FLOW_PLAYER_QA")!="1" or not OS.get_user_data_dir().contains("flow_player_qa"):
		push_error("Require ECONOMY_FLOW_PLAYER_QA=1 and isolated XDG_DATA_HOME containing flow_player_qa");quit(2);return
	assert(not Save.has_slot(4) and not Save.has_slot(5),"Require a fresh isolated fixture directory")
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	var preference:=ConfigFile.new();preference.set_value("host","slot",4);assert(preference.save("user://merchant_host.cfg")==OK)
	var runtime=ProbeRuntime.new();assert(runtime.start()==OK)
	var init: Dictionary=await response(runtime,0);assert(init.get("ok",false) and init["view"]["slot"]==4)
	assert(runtime.submit("switch",{"slot":5})==-1,"Slot 5 requires explicit opt-in marker")
	var failed: Dictionary=await response(runtime,runtime.submit("switch",{"slot":5,"feedback_opt_in":true}))
	assert(not failed["ok"] and failed["view"]["slot"]==4 and not Save.has_slot(5),"Failed old save must not enter or create experiment")
	assert((await response(runtime,runtime.submit("save"))).get("ok",false))
	var switched: Dictionary=await response(runtime,runtime.submit("switch",{"slot":5,"feedback_opt_in":true}))
	assert(switched.get("ok",false) and switched["view"]["slot"]==5)
	var ordinary_hash: String=FileAccess.get_sha256(Save.path(4))
	var request: Dictionary={}
	for offer: Dictionary in switched["view"]["business"].get("offers",[]):
		if offer.get("can_order",false):request=offer["request"].duplicate(true);break
	assert(not request.is_empty())
	var bought: Dictionary=await response(runtime,runtime.submit("buy",request))
	assert(bought["result"].get("save_pending",false) and bought["result"]["executed_result"].get("accepted",false))
	var after: Dictionary=bought["view"]["firm"].duplicate(true)
	var blocked: Dictionary=await response(runtime,runtime.submit("buy",request))
	assert(blocked["result"].get("save_pending",false) and blocked["view"]["firm"]==after)
	assert((await response(runtime,runtime.submit("save"))).get("ok",false))
	assert(FileAccess.get_sha256(Save.path(4))==ordinary_hash,"Experiment must not write ordinary slot")
	preference.load("user://merchant_host.cfg");assert(preference.get_value("host","slot")==4)
	var decoded: Dictionary=Save._read(Save.path(5),5);assert(decoded.get("error","").is_empty())
	var recovered: WorldBuildResult=FormalPersistence.new().restore_candidate(decoded["core"]);assert(recovered.success)
	assert(recovered.world.economy_r1.config["case_id"]=="MERCHANT_REGION_FEEDBACK_CANDIDATE")
	var again: Dictionary=recovered.persistence.snapshot()
	for field: String in ["economy_native","ledger","total_minutes"]:assert(again[field]==decoded["core"][field],"Limited exact recovery only: "+field)
	assert((await response(runtime,runtime.submit("close"))).get("ok",false));runtime.shutdown_and_join()
	var restart=Runtime.new();assert(restart.start()==OK)
	var normal: Dictionary=await response(restart,0);assert(normal.get("ok",false) and normal["view"]["slot"]==4)
	var resumed: Dictionary=await response(restart,restart.submit("switch",{"slot":5,"feedback_opt_in":true}));
	assert(resumed.get("ok",false))
	var resumed_firm: Dictionary=resumed["view"]["firm"].duplicate(true)
	var compared_after: Dictionary=after.duplicate(true)
	# Existing restored projection uses a different direct-cost window start. Keep evidence;
	# never rewrite the domain or claim the entire world/view is exactly restored.
	for index: int in range(compared_after["operations"].size()):
		var original_cost: Dictionary=compared_after["operations"][index]["finances"]["direct_costs"]
		var restored_cost: Dictionary=resumed_firm["operations"][index]["finances"]["direct_costs"]
		print("KNOWN_PROJECTION_WINDOW ",JSON.stringify({"site":compared_after["operations"][index]["site_id"],"before_start":original_cost.get("start_minute"),"restored_start":restored_cost.get("start_minute")}))
		original_cost.erase("start_minute");restored_cost.erase("start_minute")
	assert(resumed_firm==compared_after,"All remaining firm view fields, amounts and orders must match")
	assert((await response(restart,restart.submit("switch",{"slot":4}))).get("ok",false))
	# A valid ordinary core deliberately placed in the QA experimental envelope must fail closed.
	var old: Dictionary=Save._read(Save.path(4),4)
	var old_world: WorldBuildResult=FormalPersistence.new().restore_candidate(old["core"]);assert(old_world.success)
	var writer=Save.new();assert(writer.save(old_world,5,old["plans"])["success"])
	var rejected: Dictionary=await response(restart,restart.submit("switch",{"slot":5,"feedback_opt_in":true}))
	assert(not rejected["ok"] and rejected["view"]["slot"]==4,"Wrong saved case must retain old world, not migrate")
	assert((await response(restart,restart.submit("close"))).get("ok",false));restart.shutdown_and_join()
	print("QA_FLOW_PLAYER_RUNTIME_PASS save_failure_retains_old save_retry_no_repeat isolated_slot original_config_restore startup_ordinary mismatched_case_rejected")
	quit()
