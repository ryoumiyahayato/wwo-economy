extends SceneTree
const Opening=preload("res://merchant/merchant_opening.gd")
const Runtime=preload("res://merchant/merchant_runtime.gd")
var built: WorldBuildResult
var failed: bool=false
func check(ok: bool,message: String) -> void:
	if not ok:failed=true;push_error("QA08_FAIL "+message);quit(1);assert(ok)
func _initialize() -> void:
	call_deferred("run")
func restore_check(label: String) -> void:
	var snap: Dictionary=built.persistence.snapshot()
	var restored: WorldBuildResult=FormalPersistence.new().restore_candidate(snap)
	check(restored.success,"restore "+label+": "+restored.error)
	var roundtrip: Dictionary=restored.persistence.snapshot()
	for key: String in snap:
		if roundtrip.get(key)!=snap[key]:print("QA08_ROUNDTRIP_DIFFERENCE ",label," ",key)
	check(restored.world.economy_r1.snapshot()==built.world.economy_r1.snapshot(),"economic roundtrip "+label)
	check(roundtrip["ledger"]==snap["ledger"],"ledger roundtrip "+label)
	print("QA08_RESTORE ",label," minute=",built.world.game_clock.total_minutes())
	restored=null
func run() -> void:
	var cfg: Dictionary=Opening.opportunities_configuration()
	check(EconomySliceConfig.valid(cfg),"configuration")
	built=WorldBootstrap.new().build(null,[],[],FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT,false,{"format":"HOST_REGION_SELECTION","person_ids":[],"select_people_at_sites":true,"configuration":cfg})
	check(built.success,"build "+built.error)
	check(Opening.grant_regional_authority(built.world),"quote authority")
	check(built.simulation_step.advance_minutes(1).get("success",true),"first minute")
	var e: EconomyR1Slice=built.world.economy_r1
	var actor: String=built.world.player_state.player_id()
	var pure: Dictionary=built.persistence.snapshot()
	var view: Array[Dictionary]=e.supply_business_view(actor)
	check(pure==built.persistence.snapshot(),"public supply query is read only")
	check(view.size()==1 and view[0]["quantity"]==80 and view[0]["deadline"]==14400,"legacy mandate retained")
	check(not view[0].has("buyer_available") and not view[0].has("cash_at_accept"),"private buyer funds hidden")
	check(e.supply_business_view("unknown").is_empty(),"manager gate")
	var book: Dictionary=e.business_view(actor,Opening.FIRM,Opening.SITE,8,0,16)
	var bought: bool=false
	for q: Dictionary in book.get("offers",[]):
		if q.get("good")=="grain" and q.get("seller")=="firm:regional_upstream" and q.get("can_order",false):
			print("QA08_BUY_OFFER ",JSON.stringify(q))
			var result: Dictionary=LivelihoodAction.execute_current(built.world,"buy",q["request"])
			check(result.get("accepted",false),"real grain purchase "+str(result));bought=true;break
	print("QA08_PURCHASED ",bought)
	restore_check("opening_purchase")
	var accepted_ids: Array[String]=[]
	var submitted: bool=false
	for d: int in range(1,13):
		var step: Dictionary=built.simulation_step.advance_minutes(1440)
		check(step.get("success",true),"day step "+str(step))
		view=e.supply_business_view(actor)
		print("QA08_DAY ",d," opportunities=",JSON.stringify(view.map(func(c: Dictionary)->Dictionary:return {"id":c["id"],"quantity":c["quantity"],"status":c["status"],"free":c["free_stock"],"paid":c.get("paid",0)})))
		if d==1:check(view.size()==1,"published notice not visible before delivery")
		for c: Dictionary in view:
			if c["id"].begins_with("procurement:") and c["status"]=="RECRUITING" and not c["id"] in accepted_ids:
				var before_cash: int=int(e._world.ledger_state.own_accounts(Opening.FIRM)[0]["balance"])
				var command: Dictionary={"action_id":e.next_person_action_id(),"minute":built.world.game_clock.total_minutes(),"kind":"accept_supply_contract","payload":{"contract_id":c["id"],"price":c["price"]}}
				var result: Dictionary=LivelihoodAction.execute(built.world,actor,command)
				if result.get("accepted",false):
					accepted_ids.append(c["id"])
					var after: Dictionary=built.persistence.snapshot()
					check(LivelihoodAction.execute(built.world,actor,command)==result and built.persistence.snapshot()==after,"idempotent acceptance")
					check(int(e._world.ledger_state.own_accounts(Opening.FIRM)[0]["balance"])==before_cash,"acceptance is not earned income")
					print("QA08_ACCEPT ",JSON.stringify(result));restore_check("accepted_"+c["id"])
		if d==3:
			var c: Dictionary=e._supply.view(actor)
			var result: Dictionary=LivelihoodAction.execute_current(built.world,"accept_supply_contract",{"contract_id":c["id"],"price":c["price"]})
			print("QA08_LARGE_ACCEPT ",JSON.stringify(result))
			if result.get("accepted",false):
				accepted_ids.append(c["id"])
				var partial: Dictionary=LivelihoodAction.execute_current(built.world,"submit_supply_batch",{"contract_id":c["id"],"quantity":2})
				check(partial.get("accepted",false),"second contract shares original stock and route")
				print("QA08_LARGE_PARTIAL ",JSON.stringify(partial))
		for c: Dictionary in e.supply_business_view(actor):
			if c["id"].begins_with("procurement:grain") and c.get("status") in ["ACCEPTED","PARTIAL"] and int(c["free_stock"])>0 and int(c["unallocated"])>0:
				var result: Dictionary=LivelihoodAction.execute_current(built.world,"submit_supply_batch",{"contract_id":c["id"],"quantity":int(c["unallocated"])})
				print("QA08_BATCH ",JSON.stringify(result));submitted=submitted or result.get("accepted",false)
		if d in [2,4,6,10,12]:restore_check("day_"+str(d))
	check(accepted_ids.size()>=2,"multiple real accepted contracts")
	check(submitted,"actual supplied batch")
	print("QA08_FAIL_SUMMARY" if failed else "QA08_PASS", " accepted=",accepted_ids," minute=",built.world.game_clock.total_minutes())
	built=null
	quit(1 if failed else 0)
