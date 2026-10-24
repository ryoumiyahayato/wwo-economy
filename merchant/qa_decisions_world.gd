extends SceneTree
const Save=preload("res://merchant/merchant_save.gd")
const Runtime=preload("res://merchant/merchant_runtime.gd")
const Opening=preload("res://merchant/merchant_opening.gd")
const DecisionView=preload("res://merchant/merchant_decision_projection.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	var decoded: Dictionary=Save._read(args[0],5);assert(decoded.get("error","").is_empty())
	var restorer: FormalPersistence=FormalPersistence.new()
	var built: WorldBuildResult=restorer.restore_candidate(decoded["core"]);assert(built.success)
	var runtime=Runtime.new();runtime._slot=5
	var initial: Dictionary=runtime._view(built)
	assert(initial["minute"]==7201 and initial["firm"]["cash"]==318 and initial["personal_available"]==2500)
	var core: Dictionary=built.persistence.snapshot()
	for key: String in ["economy_native","ledger","total_minutes"]:assert(decoded["core"][key]==core[key])
	var currency: String=FormalLedgerState.DENOMINATION
	assert(initial["trade_review"]["sales_received"][currency]==16)
	assert(initial["trade_review"]["goods_paid"][currency]==16 and initial["trade_review"]["freight_paid"][currency]==2)
	var paid: int=0;var events: int=0
	for event: Dictionary in initial["market_feedback"]["events"]:
		if event.get("kind")=="payment":
			paid+=int(event["amount"]);events+=1;assert(not event["payment_ids"].is_empty() and not event["receipt_id"].is_empty())
	assert(events==2 and paid==16)
	var bread: Dictionary={}
	for offer: Dictionary in initial["business"]["offers"]:
		if offer.get("good")=="bread" and offer.get("seller_site")=="site:regional_food:lyon":bread=offer;break
	assert(not bread.is_empty() and bread["can_order"])
	var c: Dictionary=bread["comparison"]
	print("INITIAL_COMPARISON ",JSON.stringify(c))
	assert(c["goods_commitment"]==16 and c["inbound_freight_commitment"]==2 and c["maximum_cash_commitment"]==18)
	assert(c["scenario"]["known_cash_difference"]==-2)
	assert(DecisionView.purchase_text(bread,"仓库","货源").contains("警告"))
	assert(core==built.persistence.snapshot(),"All observation and presentation must be read-only")
	var saved: Dictionary=Save.new().save(built,5,decoded["plans"]);assert(saved["success"])
	var restored: WorldBuildResult=Save.new().load_slot(5);assert(restored.success)
	for key: String in ["economy_native","ledger","total_minutes"]:assert(core[key]==restored.persistence.snapshot()[key])
	var restored_view: Dictionary=runtime._view(restored)
	for key: String in ["firm","trade_review","market_feedback"]:assert(restored_view[key]==initial[key],"Restored authorized projection exact: "+key)
	var out: Dictionary={"initial_view":initial,"restore_diagnostics":restorer.restore_diagnostics,"save_restore_exact":true,"readonly_exact":true}
	var file=FileAccess.open(args[1],FileAccess.WRITE);file.store_string(JSON.stringify(out,"\t"));file.close()
	print("QA_DECISIONS_WORLD_PASS original318 personal2500 Ledger16 goods16 freight2 two unique receipts, preview18 estimated_minus2, pure query, exact save restore")
	quit()
