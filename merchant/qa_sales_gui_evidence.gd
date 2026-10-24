extends SceneTree
const Save=preload("res://merchant/merchant_save.gd")
const Opening=preload("res://merchant/merchant_opening.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args();var rows: Dictionary={}
	for label: String in ["day14_paused","day16_final"]:
		var path: String=args[0].get_base_dir().path_join("GUI_"+label+"_slot5.json")
		var raw: Dictionary=Save._read(path,5);assert(raw.get("error","").is_empty())
		var built: WorldBuildResult=FormalPersistence.new().restore_candidate(raw["core"]);assert(built.success)
		var e: EconomyR1Slice=built.world.economy_r1;var native: Dictionary=built.persistence.snapshot()["economy_native"]
		assert(native==raw["core"]["economy_native"])
		for key: String in ["ledger","total_minutes"]:assert(built.persistence.snapshot()[key]==raw["core"][key])
		var actions: Array=[];var orders: Array=[]
		for entry: Dictionary in e._commands.values():
			if entry["envelope"]["actor"]==built.world.player_state.player_id() and int(entry["envelope"]["command"]["minute"])>=15841:actions.append(entry.duplicate(true))
		for o: Dictionary in e._orders.values():
			if int(o["accepted_minute"])>=15841 and (o["buyer"]==Opening.FIRM or o["seller"]==Opening.FIRM):orders.append(e._order_view(o))
		var person: String=built.world.player_state.player_id()
		rows[label]={"source":path.get_file(),"sha256":FileAccess.get_sha256(path),"minute":built.world.game_clock.total_minutes(),"cash":built.world.ledger_state.balance(e._account(Opening.FIRM)),"personal":LivelihoodAction.query(built.world,person),"stock":e._stocks[Opening.SITE]["bread"],"sales_paused":e._local_quotes.sales_paused(Opening.SITE,"bread"),"listing":e._managed_listing_view(Opening.SITE,"bread"),"actions":actions,"orders":orders,"trade_review":e.managed_trade_review(person,Opening.FIRM),"native_exact_restore":true,"ledger_clock_exact_restore":true}
		built=null
	assert(rows["day14_paused"]["minute"]==18721 and rows["day14_paused"]["cash"]==302 and rows["day14_paused"]["stock"]==2 and rows["day14_paused"]["sales_paused"])
	assert(rows["day16_final"]["minute"]==21601 and rows["day16_final"]["cash"]==318 and rows["day16_final"]["stock"]==0 and rows["day16_final"]["sales_paused"])
	assert(rows["day14_paused"]["personal"]["cash"]==2500 and rows["day16_final"]["personal"]["cash"]==2500)
	var f=FileAccess.open(args[1],FileAccess.WRITE);f.store_string(JSON.stringify(rows,"\t"));f.close();print("QA_SALES_GUI_EVIDENCE_PASS actual GUI saves restore original native exact");quit()
