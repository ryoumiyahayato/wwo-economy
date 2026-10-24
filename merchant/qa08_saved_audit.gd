extends SceneTree
const Save=preload("res://merchant/merchant_save.gd")
const Opening=preload("res://merchant/merchant_opening.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var raw: Dictionary=Save._read(OS.get_cmdline_user_args()[0],4)
	assert(raw.get("error","").is_empty())
	var built: WorldBuildResult=FormalPersistence.new().restore_candidate(raw["core"])
	assert(built.success)
	var e: EconomyR1Slice=built.world.economy_r1
	print("GUI08_SAVED_AUDIT minute=",raw["core"]["total_minutes"]," inventory=",e._stocks[Opening.SITE]," committed_grain=",e._committed(Opening.SITE,"grain"))
	for id: String in e._orders:
		var row: Dictionary=e._orders[id]
		if row.get("seller")==Opening.FIRM or row.get("buyer")==Opening.FIRM:print("GUI08_SAVED_ORDER ",JSON.stringify(row))
	var relevant: Array[String]=[]
	for id: String in e._orders:
		if e._orders[id].get("seller")==Opening.FIRM or e._orders[id].get("buyer")==Opening.FIRM:relevant.append(id)
	for row: Dictionary in e._delivery_receipts.values():
		if row.get("order_id") in relevant:print("GUI08_SAVED_RECEIPT ",JSON.stringify(row))
	for row: Dictionary in e._lots.portions.values():
		if row.get("good")=="grain" and (row.get("owner")==Opening.FIRM or row.get("acquisition_id") in relevant):print("GUI08_SAVED_LOT ",JSON.stringify(row))
	print("GUI08_SAVED_REVIEW ",JSON.stringify(e.managed_trade_review(built.world.player_state.player_id(),Opening.FIRM)))
	print("GUI08_SAVED_SUPPLY ",JSON.stringify(e.supply_business_view(built.world.player_state.player_id())))
	built=null;quit()
