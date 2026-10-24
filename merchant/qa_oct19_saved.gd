extends SceneTree
const Save=preload("res://merchant/merchant_save.gd")
const Runtime=preload("res://merchant/merchant_runtime.gd")
const Opening=preload("res://merchant/merchant_opening.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var args=OS.get_cmdline_user_args()
	var raw: Dictionary=Save._read(args[0],5);assert(raw.get("error","").is_empty())
	var built: WorldBuildResult=FormalPersistence.new().restore_candidate(raw["core"]);assert(built.success)
	var runtime=Runtime.new();runtime._slot=5
	var view: Dictionary=runtime._view(built)
	assert(view["minute"]==7201 and view["firm"]["cash"]==318)
	var c: String=FormalLedgerState.DENOMINATION
	assert(view["trade_review"]["sales_received"][c]==16)
	assert(view["trade_review"]["goods_paid"][c]==16 and view["trade_review"]["freight_paid"][c]==2)
	assert(view["trade_review"]["known_trade_cash_difference"][c]==-2 and view["trade_review"]["unsettled_goods_sales"]==0)
	for field: String in ["economy_native","ledger","total_minutes"]:assert(raw["core"][field]==built.persistence.snapshot()[field])
	var again: WorldBuildResult=FormalPersistence.new().restore_candidate(built.persistence.snapshot());assert(again.success)
	assert(runtime._view(again)["firm"]==view["firm"])
	var file=FileAccess.open(args[1],FileAccess.WRITE)
	file.store_string(JSON.stringify({"view":view,"transactions":built.world.ledger_state.own_transactions(Opening.FIRM,4322,7202),"exact_native_ledger_clock_and_full_firm":true},"\t"));file.close()
	print("QA_OCT19_SAVED_PASS actual_GUI_day6 minute7201 cash318 sales16 purchase16 freight2 delta_minus2 full_firm_exact")
	quit()
