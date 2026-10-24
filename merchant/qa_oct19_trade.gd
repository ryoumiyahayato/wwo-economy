extends SceneTree
const Save=preload("res://merchant/merchant_save.gd")
const Runtime=preload("res://merchant/merchant_runtime.gd")
const Opening=preload("res://merchant/merchant_opening.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	var decoded: Dictionary=Save._read(args[0],5);assert(decoded.get("error","").is_empty())
	var built: WorldBuildResult=FormalPersistence.new().restore_candidate(decoded["core"]);assert(built.success)
	var runtime=Runtime.new();runtime._slot=5
	var records: Array=[]
	var sale_ids: Array[String]=[]
	for order: Dictionary in built.world.economy_r1._orders.values():
		if order["seller"]==Opening.FIRM:sale_ids.append(order["id"])
	assert(sale_ids.size()==2)
	for day: int in range(5):
		var view: Dictionary=runtime._view(built)
		var own: Array=[]
		for id: String in sale_ids:own.append(built.world.economy_r1._orders[id].duplicate(true))
		records.append({"minute":view["minute"],"cash":view["firm"]["cash"],"sales":own,"trade_review":view["trade_review"]})
		print("TRADE_DAY ",JSON.stringify(records[-1]))
		if day==0:assert(view["firm"]["cash"]==302 and view["trade_review"]["sales_received"].is_empty())
		if not view["trade_review"]["sales_received"].is_empty():break
		for hour: int in range(24):assert(built.simulation_step.advance_minutes(60).get("success",true))
	var end: Dictionary=runtime._view(built)
	assert(not end["trade_review"]["sales_received"].is_empty(),"Observed sale must actually settle within bounded 4 days")
	var saved: Dictionary=Save.new().save(built,5,decoded["plans"]);assert(saved["success"])
	var roundtrip: WorldBuildResult=Save.new().load_slot(5);assert(roundtrip.success)
	assert(runtime._view(roundtrip)["firm"]==end["firm"],"Full firm projection exact after settled natural trade")
	for key: String in ["economy_native","ledger","total_minutes"]:assert(built.persistence.snapshot()[key]==roundtrip.persistence.snapshot()[key])
	var report: Dictionary={"method":"Archived actual GUI day4 checkpoint, natural simulation_step 60-minute steps, no added player purchases or injected NPC/cash/stock changes","records":records,"end_view":end,"transactions":built.world.ledger_state.own_transactions(Opening.FIRM,4322,built.world.game_clock.total_minutes()+1),"save_restore_exact":true}
	var file=FileAccess.open(args[1],FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("QA_OCT19_TRADE_PASS minute=",end["minute"]," cash=",end["firm"]["cash"])
	quit()
