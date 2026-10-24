extends SceneTree
## Shared-session lifecycle check through the existing formal host protocol.
const Save=preload("res://merchant/merchant_save.gd")
const Runtime=preload("res://merchant/merchant_runtime.gd")
const Opening=preload("res://merchant/merchant_opening.gd")
const Merchant=preload("res://merchant/main.tscn")
var merchant: Node
var returned: Dictionary={}
func _initialize() -> void:run.call_deferred()

func idle() -> void:
	var started: int=Time.get_ticks_msec()
	while merchant.busy or not merchant.pending_requests.is_empty():
		assert(Time.get_ticks_msec()-started<60000,"Session request timed out")
		await process_frame

func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args[0]=="--trade-value-resume":await trade_value_resume(args[1]);return
	if args[0]=="--regional":await regional_session(args[1]);return
	if args[0]=="--publicity":await regional_session(args[1],true);return
	if args[0]=="--publicity-trial":await regional_session(args[1],true,true);return
	var source: PackedByteArray=FileAccess.get_file_as_bytes(args[0])
	var decoded: Dictionary=Save._read(args[0],5);assert(decoded.get("error","").is_empty())
	merchant=Merchant.instantiate()
	merchant.external_host_context=Runtime.host_context(decoded.core,decoded.core.player.player_id,Opening.FIRM,Opening.SITE,decoded.plans,Opening.REGIONAL_AUTHORITY)
	merchant.guide_opened=true
	merchant.host_continuation_ready.connect(func(context: Dictionary): returned=context)
	root.add_child(merchant)
	await idle();assert(merchant.world_ready)
	var worker: RefCounted=merchant.runtime
	var worker_id: String=worker._thread.get_id()
	var first: Dictionary=merchant.snapshot.duplicate(true)
	for iteration: int in range(10):
		merchant._open_economy_map()
		assert(merchant.economy_map_view.snapshot.market_network==first.market_network)
		merchant.economy_map_view.focus_place("place:lyon")
		merchant._close_economy_map()
		assert(merchant.runtime==worker and worker._thread.get_id()==worker_id)
	merchant._observe();await idle()
	assert(merchant.snapshot.minute==first.minute and merchant.snapshot.firm==first.firm)
	merchant._open_economy_map();merchant.economy_map_view._business()
	await idle();assert(not merchant.economy_map_layer.visible)
	assert(merchant.selected_place=="place:lyon" and merchant.selected_site==Opening.LYON_SITE)
	assert(merchant.runtime==worker and worker._thread.get_id()==worker_id)
	merchant._send("close")
	while returned.is_empty():await process_frame
	var restored: Dictionary=FormalWorldPersistenceDocument.decode(returned.snapshot_document)
	assert(restored.success)
	for key: String in ["economy_native","ledger","total_minutes"]:assert(restored.snapshot[key]==decoded.core[key],"Session map changed "+key)
	assert(source==FileAccess.get_file_as_bytes(args[0]))
	while is_instance_valid(merchant):await process_frame
	var output: Dictionary={"status":"PASS","repeated_open_close":10,"same_runtime":true,"same_worker_thread":true,"thread_id":worker_id,"business_return_place":"place:lyon","business_return_site":Opening.LYON_SITE,"minute":first.minute,"formal_host_return":true,"economy_ledger_time_exact":true,"source_bytes_unchanged":true,"scope":"NATIVE_SHARED_SESSION_NOT_HUMAN_GUI"}
	var file:=FileAccess.open(args[1],FileAccess.WRITE);file.store_string(JSON.stringify(output,"\t"));file.close()
	print("QA_ECONOMY_MAP_SESSION_PASS ",JSON.stringify(output));quit()

func regional_session(output_path: String,publication: bool=false,trial: bool=false) -> void:
	var experiment: Control=load("res://merchant/economy_household_choices.tscn").instantiate()
	root.add_child(experiment);experiment.choices.select(experiment.choices.item_count-1 if publication else experiment.choices.item_count-3);experiment._start()
	var deadline: int=Time.get_ticks_msec()+60000
	while experiment.confirmed.is_empty() or not experiment.pending.is_empty():
		assert(Time.get_ticks_msec()<deadline);await process_frame
	if publication:
		experiment._advance(4*1440)
		while experiment.target_minute>=0 or not experiment.pending.is_empty():await process_frame
	var worker: RefCounted=experiment.runtime;var thread_id: String=worker._thread.get_id()
	experiment._submit("research_subject",{"firm":"firm:regional_food"})
	while not experiment.pending.is_empty():await process_frame
	assert(experiment.confirmed.get("research_only",false) and experiment.confirmed.has("consumer_access"))
	var minute: int=int(experiment.confirmed.minute)
	experiment._submit("enter_business")
	while is_instance_valid(experiment):await process_frame
	for child: Node in root.get_children():
		if child.get_script()==load("res://merchant/merchant_scene.gd"):merchant=child;break
	assert(merchant!=null);await idle();merchant.guide.hide()
	assert(merchant.runtime==worker and worker._thread.get_id()==thread_id)
	assert(merchant.snapshot.minute==minute and merchant.snapshot.business_experiment)
	for key: String in ["consumer_access","research_subjects","research_only"]:assert(not merchant.snapshot.has(key),"Private research view leaked: "+key)
	assert(merchant.snapshot.identity.firm_id==Opening.FIRM)
	for kind: String in ["research_subject","network_capacity","switch","save","enter_business"]:assert(worker.submit(kind,{"firm":"firm:regional_food","slot":4})==-1,"Player mode admitted "+kind)
	if publication:await player_publicity(output_path,worker,thread_id,trial);return
	merchant._send("sales_control",{"site":Opening.SITE,"good":"grain","paused":true});await idle()
	assert(merchant.snapshot.firm.operations.any(func(op: Dictionary):return op.site_id==Opening.SITE and op.quotations.grain.listing.sales_paused))
	merchant._submit_step(60);await idle()
	var chosen: Dictionary={}
	for hour: int in 72:
		var total: int=int(merchant.snapshot.business.offer_total)
		for offset: int in range(0,total,16):
			merchant._send("observe",{"offset":offset,"quantity":1});await idle()
			for offer: Dictionary in merchant.snapshot.business.offers:
				if offer.good=="grain" and offer.get("can_order",false):chosen=offer;break
			if not chosen.is_empty():break
		if not chosen.is_empty():break
		merchant._submit_step(60);await idle()
	assert(not chosen.is_empty(),"No legally received executable grain offer within 72h")
	merchant._send("buy",chosen.request);await idle()
	var order_id: String=""
	for order: Dictionary in merchant.snapshot.firm.orders:
		if order.good=="grain" and order.seller==chosen.seller:order_id=order.id
	assert(not order_id.is_empty())
	var accepted: Dictionary=merchant.snapshot.duplicate(true)
	var saw_cargo: bool=false;var delivered: bool=false
	for hour: int in 192:
		merchant._submit_step(60);await idle()
		for order: Dictionary in merchant.snapshot.firm.orders:
			if order.id==order_id:
				saw_cargo=saw_cargo or int(order.transit)>0
				delivered=int(order.delivered)>0
		if delivered:break
	assert(saw_cargo and delivered,"Player buy lacked original cargo/delivery")
	merchant._send("quote",{"site":Opening.SITE,"good":"grain","price":1});await idle()
	print("PLAYER_QUOTE_RESULT ",merchant.message," ",merchant._selected_listing())
	merchant._send("sales_control",{"site":Opening.SITE,"good":"grain","paused":false});await idle()
	print("PLAYER_RESUME_RESULT ",merchant.message)
	var sales: Array=[]
	for hour: int in 168:
		merchant._submit_step(60);await idle()
		sales=merchant.snapshot.firm.sales_orders.filter(func(order: Dictionary):return order.good=="grain" and order.seller_site==Opening.SITE and int(order.delivered)>0)
		if not sales.is_empty():break
	print("PLAYER_SALE_OBSERVATION paid_sales=",sales.size()," listing=",merchant._selected_listing()," own_inventory=",merchant.snapshot.firm.inventory)
	merchant.selected_tab=3;merchant.selected_good="grain";merchant._refresh()
	assert(merchant._cost_text().contains("正式预留") and merchant._publicity_text().contains("真实工作记录"))
	merchant._primary();assert(merchant.confirm_kind.is_empty() and merchant.message.contains("真实工作记录"),"Unstaffed publication must remain refused")
	var first: Dictionary=merchant.snapshot.duplicate(true)
	for iteration: int in 3:
		merchant._open_economy_map();merchant.economy_map_view.focus_place("place:lyon");merchant._close_economy_map()
		assert(merchant.runtime==worker and worker._thread.get_id()==thread_id)
		assert(not merchant.economy_map_view.snapshot.has("consumer_access") and not merchant.economy_map_view.research_row.visible)
	merchant._observe();await idle();assert(merchant.snapshot.minute==first.minute and merchant.snapshot.firm==first.firm)
	var output: Dictionary={"status":"PASS","scope":"NATIVE_REGIONAL_PLAYER_SESSION_NOT_HUMAN_GUI","same_runtime":true,"same_worker_thread":true,"handoff_minute":minute,"final_minute":first.minute,"research_removed_and_rejected":true,"purchase_order":order_id,"accepted_cash":accepted.firm.cash,"accepted_reserved":accepted.firm.reserved,"real_cargo_then_delivery":true,"autonomous_paid_sales":sales,"final_cash":first.firm.cash,"final_reserved":first.firm.reserved,"cash_position":first.business.finance.procurement_cash,"map_toggles":3,"persistence":"DISPOSABLE_NO_SLOT_WRITE"}
	merchant._send("close")
	while not worker.finished():await process_frame
	worker.join_finished();merchant.queue_free();await process_frame
	var file:=FileAccess.open(output_path,FileAccess.WRITE);file.store_string(JSON.stringify(output,"\t"));file.close()
	print("QA_REGIONAL_PLAYER_SESSION_PASS ",JSON.stringify(output));quit()

func player_publicity(output_path: String,worker: RefCounted,thread_id: String,trial: bool=false) -> void:
	merchant.selected_tab=3;merchant.selected_good="grain";merchant.city_home=false;merchant._refresh()
	var amount: Dictionary=merchant.snapshot.business.finance.procurement_cash[FormalLedgerState.DENOMINATION]
	assert(not amount.has("sources") and not amount.has("unknown_responsibilities"),"Internal money query details leaked")
	merchant.publicity_index=0;merchant._primary();assert(merchant.confirm_kind=="apply")
	merchant._confirm();merchant.dialog.hide();await idle()
	assert(merchant.snapshot.identity.personal.employment.job==preload("res://merchant/consumer_access_opening.gd").PUBLICITY_JOB)
	merchant.publicity_index=0;merchant._primary();assert(merchant.confirm_kind=="work")
	merchant._confirm();merchant.dialog.hide();await idle()
	await player_day()
	var chosen: int=-1;var actions: Array=merchant._publicity_actions()
	for i: int in actions.size():
		if actions[i].kind=="publish_notice" and actions[i].payload.channel_id==preload("res://merchant/consumer_access_opening.gd").PUBLICITY_CHANNEL:chosen=i
	assert(chosen>=0 and actions[chosen].can_execute)
	merchant.publicity_index=chosen;merchant._primary();assert(merchant.confirm_kind=="publish_notice")
	merchant._confirm();merchant.dialog.hide();await idle()
	var before: Dictionary=merchant.snapshot.business.commercial_information.announcements[-1]
	assert(before.scheduled_recipients==2 and before.delivered_recipients==0)
	await player_day()
	var after: Dictionary=merchant.snapshot.business.commercial_information.announcements[-1]
	assert(after.id==before.id and after.delivered_recipients==2)
	assert(merchant.snapshot.identity.personal.income_by_currency.get(FormalLedgerState.DENOMINATION,0)==3)
	var sales: Array=[]
	for date: int in 7:
		await player_day()
		sales=merchant.snapshot.firm.sales_orders.filter(func(row: Dictionary):return row.good=="grain" and int(row.delivered)>0)
		if not sales.is_empty():break
	var first: Dictionary=merchant.snapshot.duplicate(true)
	for iteration: int in 3:
		merchant._open_economy_map();merchant._close_economy_map()
		assert(merchant.runtime==worker and worker._thread.get_id()==thread_id)
		assert(not merchant.economy_map_view.snapshot.has("consumer_access") and not merchant.economy_map_view.research_row.visible)
	assert(merchant.snapshot.minute==first.minute)
	var output: Dictionary={"status":"PASS","scope":"NATIVE_SCENE_BUTTONS_NOT_HUMAN_GUI","same_runtime":true,"same_worker_thread":true,"handoff_minute":4*1440,"publication_before_delivery":before,"publication_after_delivery":after,"wage_received":3,"actual_sales":sales,"final_minute":first.minute,"money_summary_private_fields_absent":true,"research_unavailable":true,"map_toggles":3}
	var core: Dictionary={}
	if trial:
		assert(not Save.has_slot(6),"Existing trial must not be overwritten")
		merchant._time_button(3);assert(merchant.confirm_kind=="enable_trial_save")
		merchant._confirm();merchant.dialog.hide();await idle()
		assert(merchant.snapshot.trial_persistent and Save.has_slot(6))
		var decoded: Dictionary=Save._read(Save.path(6),6);assert(decoded.error.is_empty());core=decoded.core
		merchant._send("save");await idle()
	merchant._send("close")
	while not worker.finished():await process_frame
	worker.join_finished();merchant.queue_free();await process_frame
	if trial:
		merchant=Merchant.instantiate();merchant.resume_trial=true;merchant.guide_opened=true;root.add_child(merchant);await idle()
		assert(merchant.world_ready and merchant.snapshot.trial_persistent and merchant.snapshot.minute==first.minute)
		assert(merchant.snapshot.firm==first.firm and merchant.snapshot.identity==first.identity and merchant.snapshot.business==first.business)
		for key: String in ["consumer_access","research_subjects","research_only"]:assert(not merchant.snapshot.has(key))
		for kind: String in ["research_subject","network_capacity","switch","enter_business"]:assert(merchant.runtime.submit(kind,{})==-1)
		var decoded: Dictionary=Save._read(Save.path(6),6);assert(decoded.core==core,"Resume changed saved world")
		merchant._submit_step(60);await idle();assert(merchant.snapshot.minute==first.minute+60)
		merchant._send("save");await idle()
		output["trial_resume"]={"minute_before":first.minute,"minute_after":merchant.snapshot.minute,"formal_core_exact_on_reopen":true,"person_firm_business_exact":true,"research_rejected":true,"path":ProjectSettings.globalize_path(Save.path(6))}
		worker=merchant.runtime;merchant._send("close")
		while not worker.finished():await process_frame
		worker.join_finished();merchant.queue_free();await process_frame
	var file:=FileAccess.open(output_path,FileAccess.WRITE);file.store_string(JSON.stringify(output,"\t"));file.close()
	print("QA_PUBLICITY_PLAYER_SESSION_PASS ",JSON.stringify(output));quit()

func player_day() -> void:
	var target: int=merchant.current_minute+1440
	var until: int=Time.get_ticks_msec()+60000
	while merchant.current_minute<target:
		merchant._submit_step(60);await idle()
		assert(Time.get_ticks_msec()<until,"Day advance timeout")

## The existing copied trial, not another research opening. No time advance here.
func trade_value_resume(output_path: String) -> void:
	var decoded: Dictionary=Save._read(Save.path(6),6)
	assert(decoded.error.is_empty(),str(decoded))
	merchant=Merchant.instantiate();merchant.resume_trial=true;merchant.guide_opened=true;root.add_child(merchant);await idle()
	assert(merchant.world_ready and merchant.snapshot.minute==decoded.core.total_minutes)
	var first: Dictionary=merchant.snapshot.duplicate(true)
	var worker: RefCounted=merchant.runtime;var thread_id: String=worker._thread.get_id()
	for key: String in ["consumer_access","research_subjects","research_only"]:assert(not first.has(key))
	for kind: String in ["research_subject","network_capacity","switch","enter_business"]:assert(worker.submit(kind,{})==-1)
	assert(not first.business.finance.procurement_cash[FormalLedgerState.DENOMINATION].has("sources"))
	assert(not first.trade_review.is_empty() and first.trade_review.has("nontrade_cash"))
	var restored: WorldBuildResult=FormalPersistence.new().restore_candidate(decoded.core)
	assert(restored.success,restored.error)
	var e: EconomyR1Slice=restored.world.economy_r1
	assert(e.managed_trade_review("firm:regional_food",Opening.FIRM).is_empty(),"Another firm obtained merchant cash review")
	var paid: int=0
	for row: Dictionary in restored.world.ledger_state.own_transactions(Opening.FIRM):
		if row.kind=="wage" and row.from_account_id==e._account(Opening.FIRM):paid+=int(row.amount)
	assert(int(first.trade_review.nontrade_cash.wages_paid.get(FormalLedgerState.DENOMINATION,0))==paid)
	assert(merchant._nontrade_cash_text(first.trade_review).contains("工资"))
	assert(merchant._nontrade_cash_text(first.trade_review).contains("本局累计") and not merchant._nontrade_cash_text(first.trade_review).contains("同期"))
	assert(first.trade_review.nontrade_cash.basis=="LIFETIME_OWN_POSTED_NONTRADE_PAYMENTS_NOT_INCURRED_COST_OR_PROFIT")
	for repeat: int in 3:
		merchant._open_economy_map();merchant._close_economy_map()
		assert(merchant.runtime==worker and worker._thread.get_id()==thread_id)
	merchant._observe();await idle()
	assert(first.minute==merchant.snapshot.minute and first.trade_review==merchant.snapshot.trade_review and first.firm==merchant.snapshot.firm)
	merchant._send("close")
	while not worker.finished():await process_frame
	worker.join_finished();merchant.queue_free();await process_frame
	var reopened: Dictionary=Save._read(Save.path(6),6)
	assert(reopened.error.is_empty() and reopened.core==decoded.core,"Observation or close changed the saved economy")
	var output: Dictionary={"scope":"NATIVE_EXISTING_TRIAL_RESTORE_AND_READONLY_MAP_NOT_GUI","minute":first.minute,"identity":first.identity,"trade_review":first.trade_review,"finance":first.business.finance,"commercial_information":first.business.commercial_information,"wages_paid_from_original_ledger":paid,"same_runtime_map_toggles":3,"research_rejected":true,"other_firm_denied":true,"saved_core_exact":true}
	var file:=FileAccess.open(output_path,FileAccess.WRITE);file.store_string(JSON.stringify(output,"\t"));file.close()
	print("QA_TRADE_VALUE_RESUME_PASS minute=",first.minute," own_paid_wages=",paid," exact_saved_core=true");quit()
