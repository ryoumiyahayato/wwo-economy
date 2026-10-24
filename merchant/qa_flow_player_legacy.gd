extends SceneTree
const Runtime=preload("res://merchant/merchant_runtime.gd")
const Save=preload("res://merchant/merchant_save.gd")
const Opening=preload("res://merchant/merchant_opening.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	if OS.get_environment("ECONOMY_FLOW_PLAYER_QA")!="1" or not OS.get_user_data_dir().contains("flow_player_qa"):
		push_error("Require isolated flow_player_qa user directory");quit(2);return
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	for slot: int in [1,2,3,4]:
		assert(not Save.has_slot(slot),"Require fresh fixtures")
		var runtime=Runtime.new()
		var built: WorldBuildResult=runtime._open(slot);assert(built.success)
		var config: Dictionary=built.world.economy_r1.config.duplicate(true)
		assert(config["case_id"]!="MERCHANT_REGION_FEEDBACK_CANDIDATE")
		assert(config.get("liquidity_policies",[]).is_empty() and config.get("labor_response_policies",[]).is_empty())
		assert(config["local_quotation_experiment"]["rules"].size()<=8)
		assert(runtime._save.save(built,slot,runtime._plans.state)["success"])
		var original_view: Dictionary=runtime._view(built)
		var before: Dictionary=built.persistence.snapshot()
		built=null
		var recovered: WorldBuildResult=runtime._open(slot);assert(recovered.success)
		assert(recovered.world.economy_r1.config==config,"Do not inject feedback into ordinary saved configuration")
		var restored_view: Dictionary=runtime._view(recovered)
		if slot==4:
			for i: int in range(original_view["firm"]["operations"].size()):
				print("ORDINARY_PROJECTION_WINDOW ",JSON.stringify({"before":original_view["firm"]["operations"][i]["finances"]["direct_costs"].get("start_minute"),"restored":restored_view["firm"]["operations"][i]["finances"]["direct_costs"].get("start_minute")}))
		var after: Dictionary=recovered.persistence.snapshot()
		for key: String in ["economy_native","ledger","total_minutes"]:assert(before[key]==after[key],"Ordinary slot exact recovery: "+key)
		print("QA_FLOW_PLAYER_LEGACY_SLOT_PASS ",slot," case=",config["case_id"])
		recovered=null;runtime=null
	var external=Runtime.new();external._external=true
	assert(external.submit("switch",{"slot":5,"feedback_opt_in":true})==-1)
	print("QA_FLOW_PLAYER_LEGACY_PASS all_four_ordinary_configs saves restores unchanged external_switch_rejected")
	quit()
