extends SceneTree
const Opening = preload("res://merchant/merchant_opening.gd")
var built: WorldBuildResult
var sequence: int = 0
func _initialize() -> void:
	_run.call_deferred()
func _emit(stage: String, data: Variant) -> void:
	print("MERCHANT ",stage," ",JSON.stringify(data))
func _action(kind: String, payload: Dictionary) -> Dictionary:
	sequence+=1
	return LivelihoodAction.execute(built.world,built.world.player_state.player_id(),{"action_id":"merchant:check:"+str(sequence),"minute":built.world.game_clock.total_minutes(),"kind":kind,"payload":payload})
func _run() -> void:
	if "supply_chain" in OS.get_cmdline_user_args():
		_supply_chain();return
	if "supply" in OS.get_cmdline_user_args():
		_supply_check();return
	if "buy_save_fault" in OS.get_cmdline_user_args():
		_buy_save_fault();return
	if "plans" in OS.get_cmdline_user_args():
		_plans_check();return
	if "regional" in OS.get_cmdline_user_args():
		_regional();return
	if "threading" in OS.get_cmdline_user_args():
		_threading();return
	var valid: bool = EconomySliceConfig.valid(Opening.configuration())
	_emit("configuration",valid)
	if not valid: quit(3);return
	var begin: int = Time.get_ticks_msec()
	built=WorldBootstrap.new().build(null,[],[],FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT,false,{"format":"HOST_REGION_SELECTION","person_ids":[],"select_people_at_sites":true,"configuration":Opening.configuration()})
	_emit("bootstrap",{"success":built.success,"error":built.error,"native_error":built.world.native_economy_error,"ms":Time.get_ticks_msec()-begin})
	if not built.success or built.world.economy_r1==null: quit(1);return
	if not Opening.grant_quote_authority(built.world): _emit("grant",false);quit(2);return
	_emit("first_minute",built.simulation_step.advance_minutes(1))
	if "restore_file" in OS.get_cmdline_user_args():
		var loaded: WorldBuildResult=built.persistence.load_from_user(1)
		_emit("restore_file",{"success":loaded.success,"error":loaded.error})
		if not loaded.success:quit(30);return
		built=loaded
		_emit("restored_summary",_public_summary())
		quit(0);return
	if "feedback" in OS.get_cmdline_user_args():
		_feedback();return
	var quote: Dictionary={"firm":Opening.FIRM,"site":Opening.SITE,"good":"grain","price":5,"authorization_context":Opening.quote_context(built.world)}
	var refused: Dictionary=quote.duplicate(true);refused["price"]=13
	_emit("price_cap",_action("post_managed_goods_quote",refused))
	var result: Dictionary = _action("post_managed_goods_quote",quote)
	_emit("quote",result)
	if not result.get("accepted",false): quit(4);return
	var replay: Dictionary={"action_id":"merchant:check:"+str(sequence),"minute":built.world.game_clock.total_minutes(),"kind":"post_managed_goods_quote","payload":quote.duplicate(true)}
	var repeated: Dictionary=LivelihoodAction.execute(built.world,built.world.player_state.player_id(),replay)
	replay["payload"]["price"]=6
	var conflict: Dictionary=LivelihoodAction.execute(built.world,built.world.player_state.player_id(),replay)
	_emit("replay",{"same_result":repeated==result,"changed_id_rejected":conflict.get("reason")=="ACTION_ID_CONFLICT"})
	if repeated!=result or conflict.get("reason")!="ACTION_ID_CONFLICT":quit(15);return
	var view: Dictionary=LivelihoodAction.query_firm(built.world,built.world.player_state.player_id(),Opening.FIRM)
	_emit("firm_view",{"cash":view.get("cash"),"accounts":view.get("accounts"),"inventory":view.get("inventory"),"transactions":view.get("transactions")})
	if "trade" in OS.get_cmdline_user_args():
		_trade()
	else: quit(0)

func _firm() -> Dictionary:
	return LivelihoodAction.query_firm(built.world,built.world.player_state.player_id(),Opening.FIRM)
func _buy(quantity: int) -> Dictionary:
	for offer: Dictionary in _firm().get("offers",[]):
		if offer.get("good")!="grain" or offer.get("reason")!="OFFER" or int(offer.get("quantity",0))<quantity: continue
		return _action("buy",{"firm":Opening.FIRM,"quote_id":offer["quote_id"],"seller":offer["seller"],"seller_site":offer["seller_site"],"buyer_site":Opening.SITE,"good":"grain","quantity":quantity,"denomination":offer["denomination"],"max_price":offer["price"],"path_id":offer["route_id"]})
	return {"accepted":false,"reason":"NO_KNOWN_EXECUTABLE_OFFER"}
func _summary() -> Dictionary:
	var view: Dictionary=_firm()
	var paid: int=0
	var rows: Array=[]
	for order: Dictionary in view.get("sales_orders",[]):
		paid+=int(order.get("paid_goods_amount",0))
		rows.append({"id":order["id"],"quantity":order["quantity"],"delivered":order["delivered"],"pending":order["pending"],"transit":order["transit"],"paid":order.get("paid_goods_amount",0)})
	return {"day":view.get("day"),"cash":view.get("cash"),"reserved":view.get("reserved"),"grain":view.get("inventory",{}).get("grain"),"sales_paid":paid,"sales":rows,"purchases":view.get("orders",[])}
func _trade() -> void:
	var first: Dictionary=_buy(2)
	_emit("buy_first",first)
	if not first.get("accepted",false): quit(5);return
	var second: bool=false
	for day: int in range(12):
		var advance: Dictionary=built.simulation_step.advance_minutes(1440)
		if advance.get("success",true)==false: _emit("advance_failed",advance);quit(6);return
		if day==1:
			var saved: Dictionary=built.persistence.snapshot()
			var restored: WorldBuildResult=built.persistence.restore_candidate(saved)
			_emit("restore_in_transit",{"success":restored.success,"error":restored.error})
			if not restored.success: quit(9);return
			built=restored
		var view: Dictionary=_summary()
		_emit("trade_day",view)
		if int(view["sales_paid"])>=10 and not second:
			var result: Dictionary=_buy(2)
			_emit("buy_second",result)
			second=bool(result.get("accepted",false))
			if not second: quit(7);return
		if second and int(view["sales_paid"])>=20:
			_emit("two_cycles",view)
			_verify_save_and_revocation()
			return
	_emit("bounded_observation_complete",{"second_order_accepted":second,"state":_summary()})
	quit(8)

func _verify_save_and_revocation() -> void:
	var saved: SaveOperationResult = built.persistence.save_to_user(1)
	_emit("save_file",{"success":saved.success,"message":saved.message})
	if not saved.success: quit(10);return
	var loaded: WorldBuildResult=built.persistence.load_from_user(1)
	_emit("load_file",{"success":loaded.success,"error":loaded.error})
	if not loaded.success: quit(11);return
	built=loaded
	var corrupted: Dictionary=built.persistence.snapshot()
	var changed: bool=false
	for receipt: Dictionary in corrupted["economy_native"]["receipts"].values():
		if receipt.get("kind")=="goods_quote":
			receipt["observed_day"]=13;receipt["delivery_day"]=14;changed=true;break
	var rejected: WorldBuildResult=built.persistence.restore_candidate(corrupted)
	_emit("expected_future_receipt_rejection",{"modified":changed,"rejected":not rejected.success,"error":rejected.error})
	if not changed or rejected.success:quit(16);return
	var null_offer: Dictionary=_firm()["offers"][0].duplicate(true)
	null_offer["price"]=null;null_offer["reason"]="GOODS_QUOTE_NOT_RECEIVED"
	var comparison: Dictionary=built.world.economy_r1._comparison_cost(Opening.FIRM,null_offer,1,[])
	_emit("null_quote",comparison)
	if comparison.get("executable",true) or comparison.get("cost")!=null:quit(17);return
	var before: Dictionary=_summary()
	if int(before["cash"])!=84 or int(before["sales_paid"])!=20: quit(12);return
	var revoked: bool=built.world.organization_state.revoke_authority(Opening.AUTHORITY,built.world.game_clock.current_hour())
	var result: Dictionary=_action("post_managed_goods_quote",{"firm":Opening.FIRM,"site":Opening.SITE,"good":"grain","price":6,"authorization_context":Opening.quote_context(built.world)})
	_emit("revoked_quote",{"revoked":revoked,"result":result})
	if not revoked or result.get("accepted",false): quit(13);return
	var candidate: WorldBuildResult=built.persistence.restore_candidate(built.persistence.snapshot())
	_emit("revoked_history_restore",{"success":candidate.success,"error":candidate.error})
	quit(0 if candidate.success else 14)

# 0.2 focused continuation of the existing trade harness. No alternate economy.
func _public_summary() -> Dictionary:
	var observed: Dictionary=built.world.economy_r1.regional_observation(built.world.player_state.player_id())
	var result: Dictionary={"minute":built.world.game_clock.total_minutes(),"grain_produced":0,"bread_produced":0,"orders":0,"work_hours":0,"wages_paid":0,"food_grain_orders":[],"merchant_sales":_summary()["sales_paid"]}
	for row: Dictionary in observed.get("regions",[]):
		result["grain_produced"]+=int(row["produced"].get("grain",0))
		result["bread_produced"]+=int(row["produced"].get("bread",0))
		result["orders"]+=int(row.get("accepted_orders",0))
		result["work_hours"]+=int(row.get("labor_hours",0))
		for wage: Dictionary in row.get("wages_by_currency",{}).values():result["wages_paid"]+=int(wage.get("paid",0))
	# Test-only inspection of counterpart order facts. UI uses public aggregates.
	for row: Dictionary in built.world.economy_r1._orders.values():
		if row.get("buyer")=="firm:regional_food" and row.get("good")=="grain":
			result["food_grain_orders"].append({"seller":row["seller"],"quantity":row["quantity"],"accepted_day":row["accepted_day"],"delivered":row["delivered"]})
	return result

func _feedback() -> void:
	var baseline: Dictionary=built.persistence.snapshot()
	var cases: Dictionary={}
	var max_step_ms: int=0
	var max_day_ms: int=0
	for branch: String in ["no_player_trade","player_arrival","one_day_steps"]:
		var restored: WorldBuildResult=built.persistence.restore_candidate(baseline)
		if not restored.success:_emit("feedback_restore_failed",restored.error);quit(21);return
		built=restored;sequence=0
		if branch=="player_arrival":
			var order: Dictionary=_buy(2);_emit("feedback_purchase",order)
			if not order.get("accepted",false):quit(22);return
		for day: int in range(8):
			var count: int=1 if branch=="one_day_steps" else 24
			var minutes: int=1440 if count==1 else 60
			for hour: int in range(count):
				var started: int=Time.get_ticks_msec()
				var result: Dictionary=built.simulation_step.advance_minutes(minutes)
				if count==24:max_step_ms=maxi(max_step_ms,Time.get_ticks_msec()-started)
				else:max_day_ms=maxi(max_day_ms,Time.get_ticks_msec()-started)
				if not result.get("success",true):_emit("feedback_step_failed",result);quit(23);return
			_emit("feedback_day",{"branch":branch,"summary":_public_summary()})
			if day==2:
				var before: Dictionary=_public_summary()
				var transit_restore: WorldBuildResult=built.persistence.restore_candidate(built.persistence.snapshot())
				if not transit_restore.success:_emit("feedback_transit_restore_failed",transit_restore.error);quit(24);return
				built=transit_restore
				built.simulation_step.advance_minutes(0)
				if _public_summary()!=before:_emit("feedback_restore_duplicated",before);quit(25);return
		cases[branch]=_public_summary()
	var control: Dictionary=cases["no_player_trade"]
	var treated: Dictionary=cases["player_arrival"]
	var player_chosen: bool=false
	for order: Dictionary in treated["food_grain_orders"]:
		if order["seller"]==Opening.FIRM and order["accepted_day"]>=3:player_chosen=true
	var passed: bool=control["bread_produced"]>0 and control["orders"]>0 and control["work_hours"]>0 and control["wages_paid"]>0 and control==cases["one_day_steps"] and player_chosen and treated["merchant_sales"]>0
	_emit("feedback_comparison",{"passed":passed,"max_step_ms":max_step_ms,"max_day_ms":max_day_ms,"chunk_equivalence":control==cases["one_day_steps"],"player_chosen_after_arrival":player_chosen,"control":control,"treatment":treated})
	if not passed:quit(26);return
	# Actual 0.1 save copied to this isolated runtime, never overwrite the original.
	var legacy: WorldBuildResult=built.persistence.load_from_user(1)
	_emit("legacy_01_load",{"success":legacy.success,"error":legacy.error})
	if not legacy.success:quit(27);return
	built=legacy
	var previous: Dictionary=_public_summary()
	var again: WorldBuildResult=built.persistence.restore_candidate(built.persistence.snapshot())
	if not again.success:quit(28);return
	built=again;built.simulation_step.advance_minutes(0)
	_emit("legacy_01_no_duplicate",{"same":previous==_public_summary(),"minute":built.world.game_clock.total_minutes()})
	if previous!=_public_summary():quit(29);return
	_emit("legacy_01_continue",built.simulation_step.advance_minutes(60))
	quit(0)

func _await_runtime(runtime: RefCounted, id: int) -> Dictionary:
	while true:
		for response: Dictionary in runtime.poll():
			if response.get("id")==id:return response
		await process_frame
	return {}

func _threading() -> void:
	# Continue the existing 0.2 saved world. No fresh trade demonstration.
	var loaded: WorldBuildResult=FormalPersistence.new().load_from_user(1)
	if not loaded.success:_emit("threading_load_failed",loaded.error);quit(40);return
	built=loaded
	var baseline_start: int=built.world.game_clock.total_minutes()
	for hour: int in range(72):
		var advance: Dictionary=built.simulation_step.advance_minutes(60)
		if not advance.get("success",true):quit(41);return
	var expected_quote: Dictionary=LivelihoodAction.execute_current(built.world,"post_managed_goods_quote",{"firm":Opening.FIRM,"site":Opening.SITE,"good":"grain","price":7,"authorization_context":Opening.quote_context(built.world)})
	var expected: Dictionary=built.persistence.snapshot()
	built=null;loaded=null
	var runtime: RefCounted=load("res://merchant/merchant_runtime.gd").new()
	if runtime.start()!=OK:quit(42);return
	var init: Dictionary=await _await_runtime(runtime,0)
	if not init.get("ok",false):_emit("threading_init_failed",init);runtime.submit("stop");quit(43);return
	var frames_during_wait: int=0
	var worst_poll_us: int=0
	var worst_worker_us: int=0
	var immutable: bool=true
	for hour: int in range(71):
		var id: int=runtime.submit("advance",{"minutes":60})
		var done: bool=false
		while not done:
			var poll_start: int=Time.get_ticks_usec()
			var responses: Array[Dictionary]=runtime.poll()
			worst_poll_us=maxi(worst_poll_us,Time.get_ticks_usec()-poll_start)
			for response: Dictionary in responses:
				if response.get("id")!=id:quit(44);return
				if not response.get("ok",false):_emit("threading_advance_failed",response);quit(45);return
				worst_worker_us=maxi(worst_worker_us,int(response["operation_us"]))
				immutable=immutable and response.is_read_only() and response["view"].is_read_only() and response["view"]["firm"].is_read_only()
				done=true
			frames_during_wait+=1
			await process_frame
		if hour%24==23:_emit("threading_progress",{"hours":hour+1,"frames":frames_during_wait,"worker_max_us":worst_worker_us})
	# Enqueue a boundary, a quote and close before the first one finishes.
	# They must execute FIFO without dropping the accepted user command.
	var ids: Array[int]=[runtime.submit("advance",{"minutes":60}),runtime.submit("quote",{"price":7}),runtime.submit("close")]
	var after_close_rejected: bool=runtime.submit("quote",{"price":5})==-1
	var received: Array[int]=[]
	var quote_same: bool=false
	while not runtime.finished():
		for response: Dictionary in runtime.poll():
			received.append(int(response["id"]))
			if response["kind"]=="quote":quote_same=response["result"]==expected_quote
		await process_frame
	for response: Dictionary in runtime.poll():received.append(int(response["id"]))
	runtime.join_finished()
	var final_world: WorldBuildResult=load("res://merchant/merchant_save.gd").new().load_slot(1)
	var same: bool=final_world.success and final_world.persistence.snapshot()==expected
	_emit("threading_result",{"after_close_rejected":after_close_rejected,"full_world_equal":same,"fifo":received==ids,"quote_equal":quote_same,"immutable":immutable,"main_poll_max_us":worst_poll_us,"worker_operation_max_us":worst_worker_us,"main_frames_while_waiting":frames_during_wait,"start_minute":baseline_start,"end_minute":final_world.world.game_clock.total_minutes() if final_world.success else -1})
	quit(0 if same and received==ids and quote_same and immutable and after_close_rejected else 46)

func _regional() -> void:
	var valid: bool=EconomySliceConfig.valid(Opening.regional_configuration())
	_emit("regional_configuration",valid)
	if not valid:quit(60);return
	var original: WorldBuildResult=FormalPersistence.new().load_from_user(1)
	if not original.success:quit(61);return
	var prior: Dictionary=original.persistence.snapshot();original=null
	var runtime: RefCounted=load("res://merchant/merchant_runtime.gd").new()
	if runtime.start()!=OK:quit(62);return
	var response: Dictionary=await _await_runtime(runtime,0)
	if not response.get("ok",false):_emit("init_failed",response);quit(63);return
	response=await _await_runtime(runtime,runtime.submit("switch",{"slot":2}))
	if not response.get("ok",false):_emit("switch_failed",response);runtime.submit("stop");quit(64);return
	var initial: Dictionary=response["view"]
	_emit("regional_opening",{"slot":initial["slot"],"cash":initial["firm"]["cash"],"sites":initial["firm"]["operations"].size(),"inventory":initial["firm"]["inventory"]})
	if initial["firm"]["cash"]!=80 or initial["firm"]["operations"].size()!=2:quit(65);return
	var supplier_count: Dictionary={}
	for op: Dictionary in initial["firm"]["operations"]:
		if op["site_id"]!=Opening.LYON_SITE:continue
		for offer: Dictionary in op["offers"]:
			if offer["good"]=="bread":supplier_count[offer["seller_site"]]=true
	_emit("known_bread_suppliers",supplier_count.keys())
	if supplier_count.size()<2:quit(66);return
	# Continue a four-product procurement/warehouse/sales plan through real requests.
	for good: String in ["grain","fiber","oil","bread"]:
		response=await _await_runtime(runtime,runtime.submit("observe",{"site":Opening.LYON_SITE,"quantity":3,"offset":0}))
		var chosen: Dictionary={}
		for offset: int in [0,16,32,48]:
			if offset>0:response=await _await_runtime(runtime,runtime.submit("observe",{"site":Opening.LYON_SITE,"quantity":3,"offset":offset}))
			for offer: Dictionary in response["view"]["business"].get("offers",[]):
				if offer["good"]==good and offer["from_place_id"]=="place:lyon" and offer.get("can_order",false):chosen=offer;break
			if not chosen.is_empty():break
		if chosen.is_empty():_emit("no_product",good);quit(67);return
		response=await _await_runtime(runtime,runtime.submit("buy",chosen["request"]))
		_emit("regional_purchase",{"good":good,"result":response["result"]})
		if not response["ok"]:quit(68);return
		response=await _await_runtime(runtime,runtime.submit("quote",{"site":Opening.SITE,"good":good,"price":int(chosen["price"])+1}))
		if not response["ok"]:_emit("quote_failed",response["result"]);quit(69);return
	for hour: int in range(24*5):
		response=await _await_runtime(runtime,runtime.submit("advance",{"minutes":60}))
		if not response["ok"]:quit(70);return
		if hour%24==23:_emit("regional_progress",{"day":hour/24+1,"cash":response["view"]["firm"]["cash"]})
	response=await _await_runtime(runtime,runtime.submit("observe",{"site":Opening.LYON_SITE,"quantity":2,"offset":0}))
	var route: Dictionary=response["view"]["transfers"][0]
	for good: String in ["grain","fiber","oil","bread"]:
		var payload: Dictionary={"firm":Opening.FIRM,"from_site":route["from_site"],"to_site":route["to_site"],"good":good,"quantity":2,"path_id":route["path_id"],"denomination":route["denomination"],"max_freight":route["freight_per_unit"]}
		response=await _await_runtime(runtime,runtime.submit("transfer_goods",payload))
		_emit("regional_transfer",{"good":good,"result":response["result"]})
		if not response["ok"]:quit(71);return
	for hour: int in range(24*7):
		response=await _await_runtime(runtime,runtime.submit("advance",{"minutes":60}))
		if not response["ok"]:quit(72);return
		if hour%24==23:_emit("regional_progress",{"day":6+hour/24,"cash":response["view"]["firm"]["cash"]})
	var final_view: Dictionary=response["view"]
	var paid: int=0
	for sale: Dictionary in final_view["firm"]["sales_orders"]:paid+=int(sale.get("paid_goods_amount",0))
	response=await _await_runtime(runtime,runtime.submit("switch",{"slot":1}))
	if not response["ok"]:quit(73);return
	var close_id: int=runtime.submit("close")
	await _await_runtime(runtime,close_id)
	while not runtime.finished():await process_frame
	runtime.join_finished()
	var legacy: WorldBuildResult=FormalPersistence.new().load_from_user(1)
	var regional: WorldBuildResult=load("res://merchant/merchant_save.gd").new().load_slot(2)
	var old_equal: bool=legacy.success and legacy.persistence.snapshot()==prior
	var final_equal: bool=regional.success and regional.world.game_clock.total_minutes()==int(final_view["minute"])
	_emit("regional_result",{"legacy_full_world_unchanged":old_equal,"regional_restore":final_equal,"sales_paid":paid,"cash":final_view["firm"]["cash"],"inventory":final_view["firm"]["inventory"],"contracts":final_view["firm"]["orders"].size(),"sales_contracts":final_view["firm"]["sales_orders"].size(),"minute":final_view["minute"]})
	quit(0 if old_equal and final_equal else 74)

func _plans_check() -> void:
	# Isolated user directory seeded from the already-played 0.3 regional slot.
	var Runtime=load("res://merchant/merchant_runtime.gd")
	var HostSave=load("res://merchant/merchant_save.gd")
	var runtime: RefCounted=Runtime.new()
	if runtime.start()!=OK:quit(80);return
	var response: Dictionary=await _await_runtime(runtime,0)
	if not response.get("ok",false):_emit("plans_init_error",response);quit(81);return
	if response["view"]["slot"]!=2:
		response=await _await_runtime(runtime,runtime.submit("switch",{"slot":2}))
	if not response["ok"]:quit(82);return
	_emit("plans_existing_world",{"minute":response["view"]["minute"],"cash":response["view"]["firm"]["cash"],"empty_plans":response["view"]["plans"]["plans"].is_empty()})
	for good: String in ["grain","bread"]:
		response=await _await_runtime(runtime,runtime.submit("plan",{"site":Opening.SITE,"good":good,"target":5,"batch":2,"ceiling":10,"floor":10,"enabled":true}))
		if not response["ok"]:_emit("plan_edit_error",response);quit(83);return
	for hour: int in range(24*3):
		response=await _await_runtime(runtime,runtime.submit("advance",{"minutes":60}))
		if not response["ok"]:_emit("plan_advance_error",response);quit(84);return
		if hour%24==23:_emit("plan_day",{"minute":response["view"]["minute"],"cash":response["view"]["firm"]["cash"],"reserved":response["view"]["firm"]["reserved"],"plans":response["view"]["plans"]})
	var sequence_before: int=int(response["view"]["plans"]["sequence"])
	if sequence_before<1:quit(85);return
	response=await _await_runtime(runtime,runtime.submit("close"))
	while not runtime.finished():await process_frame
	runtime.join_finished()
	var store: RefCounted=HostSave.new()
	var loaded: WorldBuildResult=store.load_slot(2)
	if not loaded.success:_emit("plan_restore_error",loaded.error);quit(86);return
	var exact: Dictionary=loaded.persistence.snapshot()
	var saved_plans: Dictionary=store.plans.duplicate(true)
	loaded=null
	runtime=Runtime.new();runtime.start()
	response=await _await_runtime(runtime,0)
	_emit("plan_restart",{"same_plans":response["view"]["plans"]==saved_plans,"sequence":response["view"]["plans"]["sequence"]})
	if response["view"]["plans"]!=saved_plans:quit(87);return
	for good: String in ["grain","bread"]:
		response=await _await_runtime(runtime,runtime.submit("plan",{"site":Opening.SITE,"good":good,"target":5,"batch":2,"ceiling":10,"floor":10,"enabled":false}))
		if not response["ok"]:quit(88);return
	for hour: int in range(24*2):
		response=await _await_runtime(runtime,runtime.submit("advance",{"minutes":60}))
		if not response["ok"]:quit(89);return
	if int(response["view"]["plans"]["sequence"])!=sequence_before:quit(90);return
	_emit("paused_contracts_continue",{"sequence_unchanged":true,"minute":response["view"]["minute"],"orders":response["view"]["firm"]["orders"].size()})
	# Deliberately block only this isolated test directory's temporary save target.
	var tmp: String=ProjectSettings.globalize_path(HostSave.path(2)+".tmp")
	DirAccess.make_dir_absolute(tmp)
	response=await _await_runtime(runtime,runtime.submit("plan",{"site":Opening.SITE,"good":"grain","target":7,"batch":2,"ceiling":10,"floor":10,"enabled":true}))
	if not response["result"].get("save_pending",false):_emit("expected_save_failure",response);quit(91);return
	var pending_view: Dictionary=response["view"].duplicate(true)
	var blocked: Dictionary=await _await_runtime(runtime,runtime.submit("advance",{"minutes":60}))
	if blocked["view"]["minute"]!=pending_view["minute"] or not blocked["result"].get("save_pending",false):quit(92);return
	var failed_close: Dictionary=await _await_runtime(runtime,runtime.submit("close"))
	if failed_close["ok"] or runtime.finished():quit(93);return
	DirAccess.rename_absolute(tmp,tmp+".fault_retained")
	response=await _await_runtime(runtime,runtime.submit("save"))
	if not response["ok"] or response["view"]["plans"]!=pending_view["plans"]:quit(94);return
	_emit("save_failure_retry",{"blocked_advance":true,"close_did_not_exit":true,"same_plan_and_sequence":true})
	response=await _await_runtime(runtime,runtime.submit("close"))
	while not runtime.finished():await process_frame
	runtime.join_finished()
	store=HostSave.new();loaded=store.load_slot(2)
	if not loaded.success:quit(95);return
	var final_core: Dictionary=loaded.persistence.snapshot();var final_plans: Dictionary=store.plans.duplicate(true);loaded=null
	# Keep the valid primary under a named copy, then test recovery from a broken primary.
	var primary: String=ProjectSettings.globalize_path(HostSave.path(2))
	DirAccess.copy_absolute(primary,primary+".valid_retained")
	var file: FileAccess=FileAccess.open(primary,FileAccess.WRITE);file.store_string("{broken");file.close()
	store=HostSave.new();loaded=store.load_slot(2)
	var recovered: bool=loaded.success and store.recovered and loaded.persistence.snapshot()==final_core and store.plans==final_plans
	_emit("backup_recovery",{"complete_pair_equal":recovered,"notice":store.message})
	if not recovered:quit(96);return
	var resumed: Dictionary=store.save(loaded,2,store.plans)
	if not resumed["success"]:quit(97);return
	_emit("plans_result",{"success":true,"plans_sequence":final_plans["sequence"],"minute":final_core["total_minutes"],"old_snapshot_minute":exact["total_minutes"]})
	quit(0)

func _buy_save_fault() -> void:
	var Runtime=load("res://merchant/merchant_runtime.gd")
	var HostSave=load("res://merchant/merchant_save.gd")
	var runtime: RefCounted=Runtime.new();runtime.start()
	var response: Dictionary=await _await_runtime(runtime,0)
	if not response["ok"]:quit(100);return
	var chosen: Dictionary={}
	for offset: int in [0,16,32]:
		response=await _await_runtime(runtime,runtime.submit("observe",{"site":Opening.SITE,"quantity":1,"offset":offset}))
		for offer: Dictionary in response["view"]["business"].get("offers",[]):
			if offer.get("can_order",false) and offer.get("good")=="grain":chosen=offer;break
		if not chosen.is_empty():break
	if chosen.is_empty():_emit("fault_no_order",response["view"]["firm"]["cash"]);quit(101);return
	var count: int=response["view"]["firm"]["orders"].size()
	var tmp: String=ProjectSettings.globalize_path(HostSave.path(2)+".tmp")
	DirAccess.make_dir_absolute(tmp)
	response=await _await_runtime(runtime,runtime.submit("buy",chosen["request"]))
	if not response["result"].get("save_pending",false) or not response["result"].get("executed_result",{}).get("accepted",false):_emit("fault_buy_not_pending",response["result"]);quit(102);return
	var after: Dictionary=response["view"]["firm"].duplicate(true)
	var rejected: Dictionary=await _await_runtime(runtime,runtime.submit("buy",chosen["request"]))
	if rejected["view"]["firm"]!=after:quit(103);return
	DirAccess.rename_absolute(tmp,tmp+".buy_fault_retained")
	response=await _await_runtime(runtime,runtime.submit("save"))
	var same: bool=response["ok"] and response["view"]["firm"]==after and after["orders"].size()==count+1
	_emit("buy_save_fault",{"accepted_before_failed_save":true,"repeat_blocked":true,"same_memory_after_save":same,"one_new_contract":after["orders"].size()==count+1})
	await _await_runtime(runtime,runtime.submit("close"))
	while not runtime.finished():await process_frame
	runtime.join_finished()
	quit(0 if same else 104)

func _supply_check() -> void:
	var ledger:=FormalLedgerState.new();ledger.enable_economy_r1();ledger.configure(100)
	assert(ledger.open_account("account:test:cash","test:owner","r1_firm"))
	assert(ledger.transfer("test:opening",FormalLedgerState.SOURCE_ACCOUNT,"account:test:cash",100,0,"opening_cash","test"))
	assert(ledger.reserve("contract","account:test:cash",80))
	var before: Dictionary=ledger.snapshot()
	assert(not ledger.split_reservation("bad","contract","batch","other",20));assert(ledger.snapshot()==before)
	assert(not ledger.split_reservation("bad","contract","batch","account:test:cash",81));assert(ledger.snapshot()==before)
	assert(ledger.split_reservation("split","contract","batch","account:test:cash",20))
	assert(ledger.reserved_balance("account:test:cash")==80 and ledger.available_balance("account:test:cash")==20)
	var split: Dictionary=ledger.snapshot();assert(ledger.split_reservation("split","contract","batch","account:test:cash",20));assert(ledger.snapshot()==split)
	var copy:=FormalLedgerState.new();copy.enable_economy_r1();assert(copy.restore(split))
	_emit("supply_ledger",true)
	var cfg: Dictionary=Opening.supply_configuration();_emit("supply_configuration",EconomySliceConfig.valid(cfg))
	if not EconomySliceConfig.valid(cfg):quit(70);return
	built=WorldBootstrap.new().build(null,[],[],FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT,false,{"format":"HOST_REGION_SELECTION","person_ids":[],"select_people_at_sites":true,"configuration":cfg})
	_emit("supply_bootstrap",{"success":built.success,"error":built.error})
	if not built.success:quit(71);return
	assert(Opening.grant_regional_authority(built.world));assert(built.simulation_step.advance_minutes(1).get("success",true))
	var offer: Dictionary=built.world.economy_r1._supply.view(built.world.player_state.player_id());_emit("supply_offer",offer)
	var accepted: Dictionary=_action("accept_supply_contract",{"contract_id":offer["id"],"price":offer["price"]});_emit("supply_accept",accepted)
	if not accepted.get("accepted",false):quit(72);return
	var saved: Dictionary=built.persistence.snapshot()
	var restored: WorldBuildResult=FormalPersistence.new().restore_candidate(saved);_emit("supply_restore",{"success":restored.success,"error":restored.error})
	if not restored.success:quit(73);return
	built=restored
	var e: EconomyR1Slice=built.world.economy_r1
	var duplicate: Dictionary=_action("accept_supply_contract",{"contract_id":offer["id"],"price":offer["price"]})
	assert(not duplicate.get("accepted",false))
	var empty: Dictionary=_action("submit_supply_batch",{"contract_id":offer["id"],"quantity":10})
	assert(not empty.get("accepted",false))
	var native: Dictionary=e.snapshot()
	var bad: Dictionary=native.duplicate(true)
	bad["commands"][bad["commands"].keys()[0]]["envelope"]["command"]["payload"]=null
	assert(not e._supply.restore(bad["supply_contracts"],bad))
	assert(e._supply.restore(native["supply_contracts"],native))
	var terminated: Dictionary=_action("terminate_supply_contract",{"contract_id":offer["id"]})
	assert(terminated.get("accepted",false))
	assert(e._supply.remaining_money(offer["id"])==0)
	assert(not _action("submit_supply_batch",{"contract_id":offer["id"],"quantity":1}).get("accepted",false))
	var ended: WorldBuildResult=FormalPersistence.new().restore_candidate(built.persistence.snapshot())
	_emit("supply_negative_and_terminated_restore",{"success":ended.success,"error":ended.error,"duplicate_rejected":true,"empty_stock_rejected":true,"malformed_payload_rejected":true})
	quit(0 if ended.success else 74)

func _supply_chain() -> void:
	var cfg: Dictionary=Opening.supply_configuration()
	var target: int=10 if "small_completion" in OS.get_cmdline_user_args() else 80
	cfg["supply_contracts"]["quantity"]=target
	built=WorldBootstrap.new().build(null,[],[],FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT,false,{"format":"HOST_REGION_SELECTION","person_ids":[],"select_people_at_sites":true,"configuration":cfg})
	if not built.success:_emit("chain_build",built.error);quit(80);return
	Opening.grant_regional_authority(built.world);built.simulation_step.advance_minutes(1)
	var prepared: bool="prepared" in OS.get_cmdline_user_args()
	if prepared:
		_supply_buy(16)
		built.simulation_step.advance_minutes(1440);_supply_buy(4)
		built.simulation_step.advance_minutes(2880)
	var e: EconomyR1Slice=built.world.economy_r1
	var offer: Dictionary=e._supply.view(built.world.player_state.player_id())
	var accepted: Dictionary=_action("accept_supply_contract",{"contract_id":offer["id"],"price":offer["price"]})
	_emit("chain_accept",{"prepared":prepared,"minute":built.world.game_clock.total_minutes(),"result":accepted,"cash":e._world.ledger_state.balance(e._account(Opening.FIRM))})
	if not accepted.get("accepted",false):quit(81);return
	if "retain" in OS.get_cmdline_user_args():
		var context: Dictionary=OrganizationState.acting_context(built.world.player_state.player_id(),Opening.ORGANIZATION,Opening.ORGANIZATION,Opening.REGIONAL_AUTHORITY,"opening_operator")
		_emit("retain_quote",_action("post_managed_goods_quote",{"firm":Opening.FIRM,"site":Opening.SITE,"good":"grain","price":10,"authorization_context":context}))
	var first_batch: bool=false
	var interval: int=360 if "timed" in OS.get_cmdline_user_args() else 1440
	var steps: int=44 if interval==360 else 12
	for index: int in range(steps):
		var c: Dictionary=e._supply.view(built.world.player_state.player_id())
		if c.get("status") in ["ACCEPTED","PARTIAL"] and int(c["free_stock"])>0 and c["unallocated"]>0:
			var payload: Dictionary={"contract_id":c["id"],"quantity":mini(5,int(c["free_stock"])) if target==10 else int(c["free_stock"])}
			var result: Dictionary=_action("submit_supply_batch",payload)
			_emit("chain_batch",result)
			if result.get("accepted",false) and not first_batch:
				first_batch=true
				var snap: Dictionary=built.persistence.snapshot()
				var restored: WorldBuildResult=FormalPersistence.new().restore_candidate(snap)
				_emit("chain_intransit_restore",{"success":restored.success,"error":restored.error})
				if not restored.success:quit(82);return
				built=restored;e=built.world.economy_r1
		if built.world.game_clock.total_minutes()<8*1440:
			var exposure: int=e._exposure(Opening.SITE,"grain")
			_supply_buy(mini(16,maxi(0,target-int(c.get("allocated",0))-exposure)))
		var progress: Dictionary=e._supply.view(built.world.player_state.player_id())
		var npc_orders: int=0;var npc_quantity: int=0;var npc_delivered: int=0
		for order: Dictionary in e._orders.values():
			if order["buyer"]==Opening.COMPETITOR:npc_orders+=1;npc_quantity+=int(order["quantity"]);npc_delivered+=int(order["delivered"])
		_emit("chain_day",{"index":index,"minute":built.world.game_clock.total_minutes(),"contract":progress,"merchant_cash":e._world.ledger_state.balance(e._account(Opening.FIRM)),"merchant_reserved":e._world.ledger_state.reserved_balance(e._account(Opening.FIRM)),"npc_orders":npc_orders,"npc_bought":npc_quantity,"npc_arrived":npc_delivered,"npc_cash":e._world.ledger_state.balance(e._account(Opening.COMPETITOR)),"npc_stock":e._stocks[Opening.COMPETITOR_SITE]["grain"]})
		if index<steps-1:
			var advance: Dictionary=built.simulation_step.advance_minutes(interval)
			if not advance.get("success",true):_emit("chain_advance_fail",advance);quit(83);return
	var final: WorldBuildResult=FormalPersistence.new().restore_candidate(built.persistence.snapshot())
	_emit("chain_final_restore",{"success":final.success,"error":final.error})
	var final_contract: Dictionary=e._supply.view(built.world.player_state.player_id())
	var batches: Array=final_contract.get("batches",[])
	var receipts: int=0
	for receipt: Dictionary in e._delivery_receipts.values():
		if receipt["order_id"] in batches:receipts+=1
	var player_receipts: Array[String]=[]
	for receipt_id: String in e._delivery_receipts:
		if e._delivery_receipts[receipt_id]["order_id"] in batches:player_receipts.append(receipt_id)
	var traced_inputs: Array[Dictionary]=[]
	var player_consumed: int=0
	for source: Dictionary in e._lots.sources.values():
		for input: Dictionary in source.get("inputs",[]):
			var portion: Dictionary=e._lots.portions.get(input.get("portion_id",""),{})
			if portion.get("owner")=="firm:regional_food" and portion.get("good")=="grain" and portion.get("acquisition_id") in player_receipts:
				player_consumed+=int(input["quantity"])
				traced_inputs.append({"output_source":source["id"],"output_good":source["good"],"input_portion":portion["id"],"receipt":portion["acquisition_id"],"grain_used":input["quantity"]})
	_emit("player_delivery_production_lineage",{"player_receipts":player_receipts,"player_grain_consumed":player_consumed,"production_inputs":traced_inputs})
	var consumed_delivery: int=0
	for portion: Dictionary in e._lots.portions.values():
		if portion["owner"]=="firm:regional_food" and portion["good"]=="grain" and int(portion["opened_minute"])>0:
			consumed_delivery+=int(portion["consumed"])
	_emit("chain_acceptance",{"completed_80_ontime":final_contract.get("ontime")==80,"ontime":final_contract.get("ontime"),"late":final_contract.get("late"),"receipts":receipts,"received_grain_consumed":consumed_delivery,"buyer_production":e._physical_totals["site:regional_food:paris"],"restored_continuation":first_batch,"all_gameplay_via_authorized_actions":true})
	assert(receipts>=2 and consumed_delivery>0 and final.success)
	if target==10:assert(final_contract.get("status")=="COMPLETED" and final_contract.get("ontime")==10)
	quit(0 if final.success else 84)

func _supply_buy(quantity: int) -> void:
	# Earlier local stock is a legal option, even though its unit price is higher.
	var sellers: Array=[Opening.COMPETITOR,"firm:regional_upstream"] if "local_first" in OS.get_cmdline_user_args() else ["firm:regional_upstream",Opening.COMPETITOR]
	for seller: String in sellers:
		for size: int in range(quantity,0,-1):
			var business: Dictionary=built.world.economy_r1.business_view(built.world.player_state.player_id(),Opening.FIRM,Opening.SITE,size,0,16)
			for q: Dictionary in business.get("offers",[]):
				if q.get("good")=="grain" and q.get("seller")==seller and q.get("can_order",false):
					_emit("chain_purchase",_action("buy",q["request"]));return
	_emit("chain_purchase_unavailable",{"minute":built.world.game_clock.total_minutes()})
