extends SceneTree
const Save=preload("res://merchant/merchant_save.gd")
const Opening=preload("res://merchant/merchant_opening.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	var raw: Dictionary=Save._read(args[0],4)
	var before: Dictionary=Save._read(args[1],4)
	assert(raw.get("error","").is_empty() and before.get("error","").is_empty())
	var b: WorldBuildResult=FormalPersistence.new().restore_candidate(raw["core"])
	assert(b.success)
	var snap: Dictionary=b.persistence.snapshot()
	assert(snap["ledger"]==raw["core"]["ledger"] and snap["economy_native"]==raw["core"]["economy_native"])
	var e: EconomyR1Slice=b.world.economy_r1
	var orders: Array[Dictionary]=[];var receipts: Array[Dictionary]=[];var commands: Array[Dictionary]=[]
	for id: String in e._orders:
		var o: Dictionary=e._orders[id]
		if not before["core"]["economy_native"]["orders"].has(id) and (o["buyer"]==Opening.FIRM or o["seller"]==Opening.FIRM):orders.append(o)
	for receipt: Dictionary in e._delivery_receipts.values():
		var o: Dictionary=e._orders[receipt["order_id"]]
		if e._delivery_minute(receipt)>int(before["core"]["total_minutes"]) and (o["buyer"]==Opening.FIRM or o["seller"]==Opening.FIRM):receipts.append(receipt)
	for id: String in e._commands:
		var entry: Dictionary=e._commands[id]
		if not before["core"]["economy_native"]["commands"].has(id) and entry["envelope"]["actor"]==b.world.player_state.player_id():commands.append(entry)
	var result: Dictionary={"minute":b.world.game_clock.total_minutes(),"cash":b.world.ledger_state.own_accounts(Opening.FIRM),"available":b.world.ledger_state.available_balance(e._account(Opening.FIRM)),"inventory":e._stocks[Opening.SITE],"new_own_orders":orders,"new_delivery_receipts":receipts,"new_player_commands":commands,"new_transactions":b.world.ledger_state.own_transactions(Opening.FIRM,int(before["core"]["total_minutes"])+1,b.world.game_clock.total_minutes()+1),"contracts":e.supply_business_view(b.world.player_state.player_id()),"feedback":e.managed_market_feedback(b.world.player_state.player_id(),Opening.FIRM),"economic_ledger_roundtrip_exact":true}
	assert(b.persistence.snapshot()==snap)
	var f: FileAccess=FileAccess.open(args[2],FileAccess.WRITE);assert(f!=null);f.store_string(JSON.stringify(result,"\t"));f.close()
	print("QA09_GUI_AUDIT_PASS minute=",result["minute"]," available=",result["available"]," new_orders=",orders.size()," new_receipts=",receipts.size())
	b=null;quit()
