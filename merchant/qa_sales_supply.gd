extends SceneTree
const Opening=preload("res://merchant/merchant_opening.gd")
var failed := false
func _initialize() -> void:call_deferred("run")
func check(ok: bool,message: String) -> bool:
	if not ok:push_error(message);failed=true;quit(1);return false
	print("PASS ",message);return true
func control(b: WorldBuildResult,paused: bool) -> Dictionary:
	var p: String=b.world.player_state.player_id()
	return LivelihoodAction.execute_current(b.world,"set_managed_goods_sales",{"firm":Opening.FIRM,"site":Opening.SITE,"good":"grain","paused":paused,"authorization_context":OrganizationState.acting_context(p,Opening.ORGANIZATION,Opening.ORGANIZATION,Opening.REGIONAL_AUTHORITY,"opening_operator")})
func run() -> void:
	var built: WorldBuildResult=WorldBootstrap.new().build(null,[],[],FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT,false,{"format":"HOST_REGION_SELECTION","person_ids":[],"select_people_at_sites":true,"configuration":Opening.opportunities_configuration()})
	if not check(built.success and Opening.grant_regional_authority(built.world),"Original configured supply scenario with original quotation authority"):return
	if not check(built.simulation_step.advance_minutes(1).get("success",true),"Start original clock"):return
	var e: EconomyR1Slice=built.world.economy_r1
	var person: String=built.world.player_state.player_id()
	var bought := false
	for offer: Dictionary in e.business_view(person,Opening.FIRM,Opening.SITE,8,0,16).get("offers",[]):
		if offer["good"]=="grain" and offer["seller"]=="firm:regional_upstream" and offer.get("can_order",false):
			bought=LivelihoodAction.execute_current(built.world,"buy",offer["request"]).get("accepted",false);break
	if not check(bought,"Real eight-grain procurement"):return
	for h: int in range(72):
		if not check(built.simulation_step.advance_minutes(60).get("success",true),"Original day advance"):return
	var contract: Dictionary=e._supply.view(person)
	if not check(contract.get("ready",false),"Actual still-open supply commitment available"):return
	if not check(control(built,true).get("accepted",false),"Pause grain new sales before supply acceptance"):return
	var ledger: Dictionary=built.world.ledger_state.snapshot();var lots: Dictionary=e._lots.snapshot()
	var rejected: Dictionary=LivelihoodAction.execute_current(built.world,"accept_supply_contract",{"contract_id":contract["id"],"price":contract["price"]})
	if not check(rejected.get("reason")=="GOODS_NEW_SALES_PAUSED" and ledger==built.world.ledger_state.snapshot() and lots==e._lots.snapshot(),"Paused new supply acceptance rejected without reservation"):return
	if not check(control(built,false).get("accepted",false),"Explicit grain resume"):return
	var accepted: Dictionary=LivelihoodAction.execute_current(built.world,"accept_supply_contract",{"contract_id":contract["id"],"price":contract["price"]})
	if not check(accepted.get("accepted",false),"New legal supply accepted after resume"):return
	if not check(control(built,true).get("accepted",false),"Re-pause leaves accepted contract intact"):return
	var batch: Dictionary=LivelihoodAction.execute_current(built.world,"submit_supply_batch",{"contract_id":contract["id"],"quantity":2})
	if not check(batch.get("accepted",false),"Explicit fulfilment of already-accepted supply continues while paused"):return
	var snapshot: Dictionary=built.persistence.snapshot()
	var candidate: WorldBuildResult=FormalPersistence.new().restore_candidate(snapshot)
	print("SUPPLY_RESTORE_SUCCESS ",candidate.success," ",candidate.error)
	if candidate.success:
		for key: String in snapshot:
			if candidate.persistence.snapshot().get(key)!=snapshot[key]:print("SUPPLY_RESTORE_DIFFERENCE ",key)
	if not check(candidate.success and candidate.persistence.snapshot()["economy_native"]==snapshot["economy_native"] and candidate.persistence.snapshot()["ledger"]==snapshot["ledger"] and candidate.persistence.snapshot()["total_minutes"]==snapshot["total_minutes"],"Same-minute supply acceptance pause and old batch native ledger clock restore exactly"):return
	candidate=null
	for h: int in range(48):
		if not check(built.simulation_step.advance_minutes(60).get("success",true),"Continue original transport and payment"):return
	var order: Dictionary=e._orders[batch["order_id"]]
	var paid := 0
	for tx: Dictionary in built.world.ledger_state.transactions():
		if tx.get("reference_id")==order["id"] and tx.get("kind")=="goods":paid+=int(tx["amount"])
	if not check(order["delivered"]==2 and order["price"]==contract["price"] and paid==2*int(contract["price"]),"Paused old supply batch delivered and paid at original locked price"):return
	snapshot=built.persistence.snapshot();candidate=FormalPersistence.new().restore_candidate(snapshot)
	if not check(candidate.success and candidate.persistence.snapshot()["economy_native"]==snapshot["economy_native"] and candidate.persistence.snapshot()["ledger"]==snapshot["ledger"] and candidate.persistence.snapshot()["total_minutes"]==snapshot["total_minutes"],"Post-payment paused old supply native ledger clock restores exactly"):return
	print("QA_SALES_SUPPLY_PASS order=",order["id"]," paid=",paid," remaining accepted supply not erased")
	quit()
