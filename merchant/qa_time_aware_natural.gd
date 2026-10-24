extends SceneTree
const Save=preload("res://merchant/merchant_save.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var args := OS.get_cmdline_user_args()
	print("NATURAL_STAGE read ",Time.get_ticks_msec())
	var raw: Dictionary=Save._read(args[0],5)
	var b: WorldBuildResult=FormalPersistence.new().restore_candidate(raw["core"]);assert(b.success)
	print("NATURAL_STAGE initial_restored ",Time.get_ticks_msec())
	var e: EconomyR1Slice=b.world.economy_r1
	var records: Array=[]
	var tracked: Dictionary={}
	for elapsed: int in range(5):
		print("NATURAL_STAGE advance_begin ",elapsed," ",Time.get_ticks_msec())
		for h: int in range(24): assert(b.simulation_step.advance_minutes(60).get("success",true))
		print("NATURAL_STAGE advance_done ",elapsed," ",Time.get_ticks_msec())
		var before: Dictionary=b.persistence.snapshot()
		var need: Dictionary=e._input_need("site:regional_food:paris","grain")
		assert(before==b.persistence.snapshot())
		var order: Dictionary=e._orders.get("order:82",{}).duplicate(true)
		records.append({"minute":b.world.game_clock.total_minutes(),"day":e.day,"phase":e.phase,"need":need,"order82":order,"production":e._plans["site:regional_food:paris"].duplicate(true)})
		if elapsed==0:
			for responsibility: Dictionary in need["incoming_observation"]["orders"]:
				tracked[responsibility["order_id"]]=e._orders[responsibility["order_id"]].duplicate(true)
			assert(b.world.game_clock.total_minutes()==17281)
			assert(need["requirements"][0]["day"]==12)
			if need.has("timing_projection"):
				assert(need["timing_projection"]["missed_production_quantity"]==1)
				assert(need["timing_projection"]["uncovered_future_quantity"]==0)
				assert(need["regular_quantity"]==0)
				assert(e.call("_input_candidate_need",need,13,3)["quantity"]==0)
		print("NATURAL_STAGE restore_begin ",elapsed," ",Time.get_ticks_msec())
		var restored: WorldBuildResult=FormalPersistence.new().restore_candidate(before)
		assert(restored.success)
		for key: String in ["economy_native","ledger","total_minutes"]: assert(before[key]==restored.persistence.snapshot()[key])
		restored=null
		print("NATURAL_STAGE restore_done ",elapsed," ",Time.get_ticks_msec())
	var tracked_final: Dictionary={}
	var all_arrived := true
	for id: String in tracked:
		tracked_final[id]=e._orders[id].duplicate(true)
		if int(e._orders[id]["delivered"]) < int(tracked[id]["delivered"])+int(tracked[id]["pending"])+int(tracked[id]["transit"]):all_arrived=false
	var paid: Array=[]
	for tx: Dictionary in b.world.ledger_state.transactions():
		if tracked.has(tx.get("reference_id","")): paid.append(tx)
	var out := {"case":"SAME_NATURAL_DAY12_INPUT_NOT_PRODUCT_DAY16","source_sha256":FileAccess.get_sha256(args[0]),"classification":"DAY12_PRODUCTION_ALREADY_CLOSED_WAIT_EXISTING_DAY13_CARGO_COVERS_DAYS13_AND14","records":records,"tracked_responsibilities_at_boundary":tracked,"tracked_final":tracked_final,"tracked_payments":paid,"all_tracked_arrived":all_arrived,"status":"PASS_NATURAL_WAIT_AND_OLD_ARRIVAL_NOT_FULL_GUI"}
	var f=FileAccess.open(args[1],FileAccess.WRITE);f.store_string(JSON.stringify(out,"\t"));f.close()
	assert(all_arrived)
	print("QA_TIME_AWARE_NATURAL_PASS tracked=",tracked.keys());quit()
