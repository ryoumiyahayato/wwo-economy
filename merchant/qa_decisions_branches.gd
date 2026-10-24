extends SceneTree
const Save=preload("res://merchant/merchant_save.gd")
const Runtime=preload("res://merchant/merchant_runtime.gd")
const Opening=preload("res://merchant/merchant_opening.gd")
func _initialize() -> void:call_deferred("run")
func record(built: WorldBuildResult,runtime: RefCounted) -> Dictionary:
	var e: EconomyR1Slice=built.world.economy_r1
	return {"view":runtime._view(built),"research_only":{"food_site":e._site_operating_view("site:regional_food:lyon"),"plans":e._plans.duplicate(true),"work":e._work_records.duplicate(true),"wages":e._wages.duplicate(true),"households":e._actors.duplicate(true),"regional_transactions":built.world.ledger_state.transactions()}}
func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	var decoded: Dictionary=Save._read(args[0],5);assert(decoded.get("error","").is_empty())
	var branches: Dictionary={}
	for strategy: String in ["A_keep_listing8","B_future_listing9"]:
		var built: WorldBuildResult=FormalPersistence.new().restore_candidate(decoded["core"]);assert(built.success)
		var runtime=Runtime.new();runtime._slot=5
		var records: Array=[record(built,runtime)]
		var actions: Array=[]
		if strategy=="B_future_listing9":
			var person: String=built.world.player_state.player_id()
			var context: Dictionary=OrganizationState.acting_context(person,Opening.ORGANIZATION,Opening.ORGANIZATION,Opening.REGIONAL_AUTHORITY,"opening_operator")
			var result: Dictionary=LivelihoodAction.execute_current(built.world,"post_managed_goods_quote",{"firm":Opening.FIRM,"site":Opening.SITE,"good":"bread","price":9,"authorization_context":context})
			actions.append({"action":"post_managed_goods_quote","result":result});assert(result.get("accepted",false))
		var business: Dictionary=built.world.economy_r1.business_view(built.world.player_state.player_id(),Opening.FIRM,Opening.SITE,2,0,16)
		var selected: Dictionary={}
		for offer: Dictionary in business["offers"]:
			if offer.get("good")=="bread" and offer.get("seller_site")=="site:regional_food:lyon":selected=offer;break
		assert(selected.get("can_order",false))
		actions.append({"preview":selected["comparison"]})
		var purchase: Dictionary=LivelihoodAction.execute_current(built.world,"buy",selected["request"]);assert(purchase.get("accepted",false));actions.append({"action":"buy","result":purchase})
		for day: int in range(6):
			for hour: int in range(24):assert(built.simulation_step.advance_minutes(60).get("success",true))
			records.append(record(built,runtime))
		var save: RefCounted=Save.new();assert(save.save(built,5,decoded["plans"])["success"])
		var reloaded: WorldBuildResult=save.load_slot(5);assert(reloaded.success)
		for key: String in ["economy_native","ledger","total_minutes"]:assert(built.persistence.snapshot()[key]==reloaded.persistence.snapshot()[key])
		DirAccess.copy_absolute(ProjectSettings.globalize_path(Save.path(5)),args[2]+"/"+strategy+".json")
		branches[strategy]={"actions":actions,"records":records,"final_view":runtime._view(built),"same_start_hash":FileAccess.get_sha256(args[0]),"save_restore_exact":true}
		print("BRANCH_RESULT ",strategy," ",JSON.stringify({"minute":branches[strategy]["final_view"]["minute"],"cash":branches[strategy]["final_view"]["firm"]["cash"],"review":branches[strategy]["final_view"]["trade_review"]}))
		built=null;reloaded=null;runtime=null
	var file=FileAccess.open(args[1],FileAccess.WRITE);file.store_string(JSON.stringify(branches,"\t"));file.close()
	print("QA_DECISIONS_BRANCHES_PASS two same-start legal decisions natural NPC 6 days save restore; domain automation not GUI")
	quit()
