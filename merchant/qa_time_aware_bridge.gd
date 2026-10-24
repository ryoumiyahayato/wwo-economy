extends SceneTree
const Save=preload("res://merchant/merchant_save.gd")
const BRIDGE="/tmp/economy_time_aware_day12_old_boundary.bin"
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var args:=OS.get_cmdline_user_args();var create: bool=args[2]=="bridge_create"
	var b: WorldBuildResult
	if create:
		var raw: Dictionary=Save._read(args[0],5)
		b=FormalPersistence.new().restore_candidate(raw["core"]);assert(b.success)
		for h: int in range(24):assert(b.simulation_step.advance_minutes(60).get("success",true))
		var order: Dictionary=b.world.economy_r1._orders["order:82"]
		assert(order["quantity"]==3 and order["transit"]==3 and order["accepted_minute"]==17280)
		var f=FileAccess.open(BRIDGE,FileAccess.WRITE);f.store_buffer(var_to_bytes(b.persistence.snapshot()));f.close()
		var j=FileAccess.open(args[1],FileAccess.WRITE);j.store_string(JSON.stringify({"status":"OLD_RULE_ACTUAL_SIGNED_3_CREATED","bridge_sha256":FileAccess.get_sha256(BRIDGE),"minute":b.world.game_clock.total_minutes(),"order82":order},"\t"));j.close()
		print("QA_BRIDGE_CREATED_ORIGINAL_ORDER82_3");quit();return
	var original: Dictionary=bytes_to_var(FileAccess.get_file_as_bytes(BRIDGE))
	b=FormalPersistence.new().restore_candidate(original);assert(b.success)
	var e: EconomyR1Slice=b.world.economy_r1
	assert(original["economy_native"]["orders"]["order:82"]==e._orders["order:82"])
	var need: Dictionary=e._input_need("site:regional_food:paris","grain")
	assert(need["quantity"]==0 and need["regular_quantity"]==0 and need["incoming"]==3)
	assert(need["timing_projection"]["missed_production_quantity"]==1 and need["timing_projection"]["uncovered_future_quantity"]==0)
	assert(e.call("_input_candidate_need",need,13,3)["quantity"]==0)
	var records: Array=[]
	for d: int in range(5):
		for h: int in range(24):assert(b.simulation_step.advance_minutes(60).get("success",true))
		records.append({"day":e.day,"order82":e._orders["order:82"].duplicate(true),"need":e._input_need("site:regional_food:paris","grain")})
	var paid:=0
	for tx: Dictionary in b.world.ledger_state.transactions():
		if tx.get("reference_id")=="order:82" and tx.get("kind")=="goods":paid+=int(tx["amount"])
	assert(e._orders["order:82"]["quantity"]==3 and e._orders["order:82"]["delivered"]==3 and paid==15)
	var j=FileAccess.open(args[1],FileAccess.WRITE);j.store_string(JSON.stringify({"status":"PASS_ORIGINAL_SIGNED_LATE3_PRESERVED_DELIVERED_PAID","bridge_sha256":FileAccess.get_sha256(BRIDGE),"boundary_need":need,"records":records,"actual_goods_paid":paid},"\t"));j.close()
	print("QA_BRIDGE_RESTORE_PASS_OLD3_DELIVERED_PAID15");quit()
