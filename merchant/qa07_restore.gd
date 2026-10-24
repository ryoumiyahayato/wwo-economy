extends SceneTree
const Save=preload("res://merchant/merchant_save.gd")
const Runtime=preload("res://merchant/merchant_runtime.gd")
const Opening=preload("res://merchant/merchant_opening.gd")
func _initialize() -> void:
	var built: WorldBuildResult=Save.new().load_slot(3)
	assert(built.success)
	var e: EconomyR1Slice=built.world.economy_r1
	var player: String=built.world.player_state.player_id()
	var firm: Dictionary=LivelihoodAction.query_firm(built.world,player,Opening.FIRM)
	var c: Dictionary=e._supply.view(player)
	var expected: Dictionary={"minute":10081,"ontime":2,"paid":10,"free":3,"cash":309,"batches":["order:44"]}
	if not OS.get_cmdline_user_args().is_empty():expected=JSON.parse_string(OS.get_cmdline_user_args()[0])
	assert(built.world.game_clock.total_minutes()==int(expected["minute"]))
	assert(c["ontime"]==expected["ontime"] and c["paid"]==expected["paid"] and c["free_stock"]==expected["free"] and c["batches"]==expected["batches"])
	assert(firm["cash"]==expected["cash"] and firm["reserved"]==0)
	print("RESTORE07_PASS ",JSON.stringify({"minute":expected["minute"],"cash":firm["cash"],"reserved":firm["reserved"],"supply":c}))
	var ids: Array[String]=[]
	for order: Dictionary in firm.get("orders",[])+firm.get("sales_orders",[]):
		if str(order["id"]) in ids:continue
		ids.append(str(order["id"]))
		print("OWN_ORDER ",JSON.stringify(order))
	print("OWN_TRANSACTIONS ",JSON.stringify(firm.get("transactions",[])))
	var receipts: Array[String]=[]
	for id: String in e._delivery_receipts:
		if e._delivery_receipts[id]["order_id"] in c["batches"]:
			receipts.append(id);print("SUPPLY_RECEIPT ",JSON.stringify(e._delivery_receipts[id]))
	var lineage: Dictionary={}
	for portion: Dictionary in e._lots.portions.values():
		if portion.get("owner")=="firm:regional_food" and portion.get("good")=="grain" and portion.get("acquisition_id") in receipts:
			var node: Dictionary=portion
			while not node.is_empty():
				lineage[str(node["id"])]=node.duplicate(true)
				node=e._lots.portions.get(node.get("parent_portion_id",""),{})
	print("SUPPLY_LOT_LINEAGE ",JSON.stringify(lineage))
	var before_preview: Dictionary=built.persistence.snapshot()
	var preview: Dictionary=Runtime.new()._view(built)
	assert(before_preview==built.persistence.snapshot())
	print("CURRENT_DISPATCH_HINT ",JSON.stringify(preview["supply"]))
	if expected.has("earliest"):assert(preview["supply"]["new_batch_earliest_day"]==expected["earliest"])
	# Decode and query only: no action submission, advance, save, or mutation.
	assert(built.world.game_clock.total_minutes()==int(expected["minute"]))
	quit()
