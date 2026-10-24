extends SceneTree
const Opening=preload("res://merchant/merchant_opening.gd")
func _initialize() -> void:call_deferred("run")
func differences(a: Variant,b: Variant,path: String,result: Array) -> void:
	if a==b or result.size()>=20:return
	if a is Dictionary and b is Dictionary:
		for key: Variant in a:
			if not b.has(key):result.append({"path":path+"/"+str(key),"before":"present","after":"missing"})
			else:differences(a[key],b[key],path+"/"+str(key),result)
		for key: Variant in b:
			if not a.has(key):result.append({"path":path+"/"+str(key),"before":"missing","after":"present"})
	elif a is Array and b is Array and a.size()==b.size():
		for i: int in a.size():differences(a[i],b[i],path+"/"+str(i),result)
	else:result.append({"path":path,"before":str(a).left(300),"after":str(b).left(300)})
func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	var built: WorldBuildResult=WorldBootstrap.new().build(null,[],[],FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT,false,{"format":"HOST_REGION_SELECTION","person_ids":[],"select_people_at_sites":true,"configuration":Opening.opportunities_configuration()})
	assert(built.success and Opening.grant_regional_authority(built.world));assert(built.simulation_step.advance_minutes(1).get("success",true))
	var e: EconomyR1Slice=built.world.economy_r1;var person: String=built.world.player_state.player_id()
	var bought := false
	for offer: Dictionary in e.business_view(person,Opening.FIRM,Opening.SITE,8,0,16).get("offers",[]):
		if offer["good"]=="grain" and offer["seller"]=="firm:regional_upstream" and offer.get("can_order",false):bought=LivelihoodAction.execute_current(built.world,"buy",offer["request"]).get("accepted",false);break
	assert(bought)
	for h: int in range(72):assert(built.simulation_step.advance_minutes(60).get("success",true))
	var contract: Dictionary=e._supply.view(person);assert(contract.get("ready",false))
	assert(LivelihoodAction.execute_current(built.world,"accept_supply_contract",{"contract_id":contract["id"],"price":contract["price"]}).get("accepted",false))
	assert(LivelihoodAction.execute_current(built.world,"submit_supply_batch",{"contract_id":contract["id"],"quantity":2}).get("accepted",false))
	var original: Dictionary=built.persistence.snapshot();var recovered: WorldBuildResult=FormalPersistence.new().restore_candidate(original);assert(recovered.success)
	var current: Dictionary=recovered.persistence.snapshot();var changed: Array=[];var detailed: Array=[]
	for key: String in original:
		if original[key]!=current.get(key):changed.append(key);differences(original[key],current.get(key),key,detailed)
	for key: String in ["economy_native","ledger","total_minutes"]:assert(original[key]==current[key])
	var out := {"label":args[2],"fixture":"Same original opportunities configuration, grant, minute1 buy8grain,72hours,accept original80grain contract,submit2. No new sales controls in either run.","minute":built.world.game_clock.total_minutes(),"native_ledger_clock_exact":true,"changed_top_fields":changed,"first_twenty_differences":detailed,"source_build_id":ProjectSettings.get_setting("application/config/build_id")}
	var file=FileAccess.open(args[1],FileAccess.WRITE);file.store_string(JSON.stringify(out,"\t"));file.close()
	print("QA_SALES_NORMALIZATION ",JSON.stringify(out));quit()
