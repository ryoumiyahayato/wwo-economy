extends SceneTree
## Negative restore tests. Run explicitly; this file does not modify saves.
const Opening=preload("res://merchant/merchant_opening.gd")
var failures: int=0
var built: WorldBuildResult

func _initialize() -> void:
	call_deferred("run")

func require(ok: bool,label: String) -> bool:
	if not ok:
		failures+=1
		push_error("QA08_INTEGRITY_FAIL "+label)
	return ok

func expect_rejected(label: String,snapshot: Dictionary) -> void:
	var restored: WorldBuildResult=FormalPersistence.new().restore_candidate(snapshot)
	if require(not restored.success,label+" accepted a tampered snapshot"):
		print("QA08_INTEGRITY_REJECT ",label," error=",restored.error)
	restored=null

func remove_notice_message(native: Dictionary,id: String) -> void:
	native["receipts"].erase("supply_notice:"+id)
	var messages: Array=[]
	for m: Dictionary in native["messages"]:
		if m.get("id")!="supply_notice:"+id:messages.append(m)
	native["messages"]=messages

func run() -> void:
	built=WorldBootstrap.new().build(null,[],[],FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT,false,{"format":"HOST_REGION_SELECTION","person_ids":[],"select_people_at_sites":true,"configuration":Opening.opportunities_configuration()})
	if not require(built.success,"fixture build: "+built.error):quit(1);return
	if not require(Opening.grant_regional_authority(built.world),"fixture authority"):quit(1);return
	for minutes: int in [1,1440,1440,1440]:
		if not require(built.simulation_step.advance_minutes(minutes).get("success",true),"fixture advance"):quit(1);return
	var e: EconomyR1Slice=built.world.economy_r1
	var actor: String=built.world.player_state.player_id()
	var baseline: Dictionary=built.persistence.snapshot()
	var good: WorldBuildResult=FormalPersistence.new().restore_candidate(baseline)
	if not require(good.success,"baseline restore: "+good.error):quit(1);return
	good=null
	var native: Dictionary=baseline["economy_native"]
	var notices: Dictionary=native["supply_contracts"]["notices"]
	if not require(not notices.is_empty(),"fixture has real NPC publication"):quit(1);return
	var id: String=str(notices.keys()[0])
	var changed: Dictionary=baseline.duplicate(true)
	changed["economy_native"]["supply_contracts"]["notices"].erase(id)
	remove_notice_message(changed["economy_native"],id)
	expect_rejected("orphan_successful_publication",changed)
	changed=baseline.duplicate(true)
	remove_notice_message(changed["economy_native"],id)
	expect_rejected("missing_notice_delivery",changed)
	changed=baseline.duplicate(true)
	var n: Dictionary=changed["economy_native"]["supply_contracts"]["notices"][id]
	var insufficient: int=int(n["price"])*int(n["terms"]["quantity"])-1
	if require(insufficient>0,"fixture supports positive insufficient mandate"):
		for p: Dictionary in changed["economy_native"]["config"]["supply_opportunity_policies"]:
			if p["id"]==n["policy_id"]:p["max_commitment"]=insufficient
		n["terms"]["max_commitment"]=insufficient
		changed["economy_native"]["commands"][n["publication_action"]]["result"]["notice"]=n.duplicate(true)
		expect_rejected("coherent_unaccepted_notice_over_mandate",changed)
	changed=baseline.duplicate(true)
	changed["economy_native"]["receipts"]="malformed"
	expect_rejected("malformed_receipt_container",changed)
	var before: Dictionary=built.persistence.snapshot()
	e.supply_business_view(actor)
	e.managed_transfer_options(actor,Opening.FIRM,Opening.SITE)
	require(before==built.persistence.snapshot(),"queries preserve authoritative snapshot")
	require(e.supply_business_view("unknown").is_empty(),"unauthorized supply query")
	require(e.managed_transfer_options("unknown",Opening.FIRM,Opening.SITE).is_empty(),"unauthorized transfer query")
	require(e.managed_transfer_options(actor,Opening.FIRM,"site:regional_food:paris").is_empty(),"foreign transfer origin")
	var selected: Dictionary={}
	for c: Dictionary in e.supply_business_view(actor):
		if str(c["id"]).begins_with("procurement:") and c.get("ready",false):selected=c;break
	if not require(not selected.is_empty(),"fixture has a receivable real notice"):quit(1);return
	var accepted: Dictionary=LivelihoodAction.execute_current(built.world,"accept_supply_contract",{"contract_id":selected["id"],"price":selected["price"]})
	if not require(accepted.get("accepted",false),"fixture acceptance: "+str(accepted)):quit(1);return
	require(not accepted.has("cash_at_accept") and not accepted.has("buyer_available"),"public acceptance hides buyer cash")
	var accepted_snapshot: Dictionary=built.persistence.snapshot()
	good=FormalPersistence.new().restore_candidate(accepted_snapshot)
	if not require(good.success,"accepted baseline restore: "+good.error):quit(1);return
	good=null
	changed=accepted_snapshot.duplicate(true)
	changed["economy_native"]["receipts"]["supply_notice:"+str(selected["id"])]["source_receipt"]="forged:unknown_supplier"
	expect_rejected("forged_accepted_notice_source",changed)
	changed=accepted_snapshot.duplicate(true)
	remove_notice_message(changed["economy_native"],selected["id"])
	expect_rejected("accepted_without_received_notice",changed)
	print("QA08_INTEGRITY_RESULT failures=",failures," minute=",built.world.game_clock.total_minutes())
	built=null
	quit(0 if failures==0 else 1)
