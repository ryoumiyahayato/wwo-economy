extends "res://merchant/qa_multisource_timing.gd"
## Test-only composition hook; original Population/zero-cash policy stay authoritative.
class NamedManagerBootstrap extends WorldBootstrap:
	func _bind_organization_reference_catalog(r: WorldBuildResult) -> bool:
		if r.world.person_overlay!=null and not r.world.person_overlay.has_person("person:research_regional_manager"):
			var original: Dictionary=r.world.person_overlay.person(WorldBootstrap.DEFAULT_FORMAL_PERSON_ID)
			var demographic: Dictionary=original.basic_demographic_identity.duplicate(true)
			# Reuse the original zero-opening-account policy, with no corporate policy.
			demographic.opening_cash_policy="ZERO_CASH_DEVELOPMENT_CORPORATE_MANAGER"
			var provenance: Dictionary=original.provenance.duplicate(true)
			provenance.basis="explicit_development_named_manager_fixture"
			if not r.world.person_overlay.materialize("person:research_regional_manager","claim:research_regional_manager",original.population_territory_id,demographic,original.current_place_id,provenance):r.error=r.world.person_overlay.last_error();return false
			r.organization_person_reference_ids=r.world.person_overlay.person_ids()
		return super._bind_organization_reference_catalog(r)

func money_total(b: WorldBuildResult) -> int:
	var total: int=0
	for id: String in b.world.ledger_state.account_ids():total+=int(b.world.ledger_state.balance(id))
	return total
func restore_fixture(b: WorldBuildResult) -> WorldBuildResult:
	# Original explicit-reference restore API. The default host deliberately
	# admits only its opening person; the extra test manager is not a new host.
	return FormalPersistence.new(b.world,b.organization_person_reference_ids,b.organization_place_reference_ids,true).restore_candidate(b.persistence.snapshot())
func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	var probe: WorldBuildResult=Allocation.build("normal")
	assert(probe.success,probe.error)
	var stranger: String="cohort:regional:lyon_upstream"
	var player: String=probe.world.player_state.player_id()
	var initial_money: int=money_total(probe)
	var person: Dictionary=probe.world.person_overlay.person(player)
	var named: Dictionary={"id":"person:research_regional_manager","kind":"named","control":"automatic","members":1,"account_id":FormalPersonalEconomyState.personal_account_id("person:research_regional_manager"),"cash":0,"stock":EconomySliceConfig.zero_stock(EconomySliceConfig.good_ids(configuration())),"skill":1,"daily_need":2,"needs":{"food":2,"clothing":1,"household":1},"population_start":0,"place_id":person.current_place_id,"population_unit_id":probe.world.population_state.unit_for_person(player)}
	probe=null
	var results: Dictionary={}
	for mode: String in ["named","dormant","budget_limited","authority_missing","unknown_arrival"]:
		var cfg: Dictionary=configuration()
		cfg.firm_management_permissions=[]
		var manager: Dictionary=named.duplicate(true)
		if mode=="dormant":manager.control="dormant"
		# Give the admitted person the existing Paris workers' local living
		# introductions. This grants no enterprise or treasury authority.
		var player_actor: String="cohort:regional:paris_food"
		var introductions: Array=[]
		for info: Dictionary in cfg.information:
			if info.actor==player_actor and info.kind=="supplier":
				var copied: Dictionary=info.duplicate(true);copied.actor=manager.id;introductions.append(copied)
		cfg.information.append_array(introductions)
		for route: Dictionary in cfg.routes:
			if player_actor in route.known_to:route.known_to.append(manager.id)
		for path: Dictionary in cfg.transport_paths:
			if player_actor in path.known_to:path.known_to.append(manager.id)
		cfg.actors.append(manager)
		assert(Allocation.totals(cfg)==Allocation.totals(configuration()))
		for firm: Dictionary in cfg.firms:
			if firm.id==BUYER:firm.manager=manager.id
		if mode=="dormant":
			assert(not EconomySliceConfig.valid(cfg),"Dormant manager was admitted")
			results[mode]={"configuration_rejected":true,"basis":"ORIGINAL_CONFIG_FORBIDS_DORMANT_MANAGER"};print("REGIONAL_MANAGER dormant admission_rejected");continue
		if mode=="unknown_arrival":
			for route: Dictionary in cfg.routes:
				if route.id==Allocation.EDGE:route.capacity_manager=BUYER
		if mode=="budget_limited":
			cfg.procurement_budgets=[{"id":"budget:research:grain","subject":BUYER,"root_authority":"research:explicit_grain_limit","denomination":FormalLedgerState.DENOMINATION,"category":"goods:grain","start_minute":0,"end_minute":30*1440,"limit":24,"carryover":"RETAIN_ORIGINAL_WINDOW","priority":"EXISTING_ACTION_ORDER","basis":"EXPLICIT_DEVELOPMENT_PROCUREMENT_AUTHORITY"}]
		if mode=="authority_missing":
			cfg.procurement_budgets=[{"id":"budget:research:ungranted","subject":BUYER,"root_authority":"authority:research:not_granted","denomination":FormalLedgerState.DENOMINATION,"category":"goods:grain","start_minute":0,"end_minute":30*1440,"limit":64,"carryover":"RETAIN_ORIGINAL_WINDOW","priority":"EXISTING_ACTION_ORDER","basis":"FORMAL_AUTHORITY_REQUIRED"}]
		var b: WorldBuildResult=NamedManagerBootstrap.new().build(null,[],[],FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT,false,{"format":"HOST_REGION_SELECTION","person_ids":[],"select_people_at_sites":true,"configuration":cfg})
		if mode=="authority_missing":
			assert(b.world.economy_r1==null and str(b.world.native_economy_error)=="Budget requires an actual economy.procure root authorization")
			results[mode]={"composition_rejected":true,"reason":b.world.native_economy_error,"basis":"ORIGINAL_ROOT_AUTHORITY_VALIDATION"};print("REGIONAL_MANAGER authority_missing composition_rejected");b=null;continue
		assert(b.success and b.world.economy_r1!=null,b.error+" "+str(b.world.native_economy_error))
		assert(money_total(b)==initial_money,"Named fixture added net money")
		assert(b.world.person_overlay.has_person(manager.id) and b.world.player_state.player_id()==player)
		assert(b.world.ledger_state.balance(manager.account_id)==0,"Test manager acquired free opening cash")
		assert(b.simulation_step.advance_minutes(1).get("success",true))
		var e: EconomyR1Slice=b.world.economy_r1
		assert(e._npc_timing_adoption(BUYER)==(mode!="dormant"))
		var offer: Dictionary=e._offer(BUYER,"firm:regional_upstream","grain",Allocation.EDGE,REMOTE,SITE)
		var payload: Dictionary={"quote_id":offer.quote_id,"seller":offer.seller,"seller_site":REMOTE,"buyer_site":SITE,"good":"grain","quantity":8,"denomination":offer.denomination,"max_price":offer.price,"path_id":offer.route_id,"need_by_day":7}
		var accepted: Dictionary=e.submit_internal(BUYER,e._auto_command(BUYER,"buy",payload,"EXPLICIT_INITIAL_LATE_CONTRACT"))
		assert(accepted.get("accepted",false),str(accepted))
		# An automatic person who is not this enterprise's manager cannot spend.
		var wrong: Dictionary=payload.duplicate(true);wrong.firm=BUYER;wrong.quantity=1
		var before: Dictionary=b.persistence.snapshot()
		var denied: Dictionary=e.submit_internal(stranger,e._auto_command(stranger,"buy",wrong,"NOT_THIS_MANAGER"))
		assert(not denied.get("accepted",false) and denied.reason=="NOT_PROCUREMENT_MANAGER",str(denied))
		var after: Dictionary=b.persistence.snapshot()
		assert(before.ledger==after.ledger and before.economy_native.stock_lots==after.economy_native.stock_lots,"Denied buyer changed money/lots")
		if mode=="unknown_arrival":assert(e.submit_internal(BUYER,e._auto_command(BUYER,"set_edge_capacity",{"edge_id":Allocation.EDGE,"capacity":0},"RESEARCH_CLOSURE")).get("accepted",false))
		var records: Array=[record(b)]
		for boundary: int in range(1,9):
			while b.world.game_clock.total_minutes()<boundary*1440:assert(b.simulation_step.advance_minutes(mini(60,boundary*1440-b.world.game_clock.total_minutes())).get("success",true))
			records.append(record(b))
		var rescue: Array=[]
		for order: Dictionary in e._orders.values():
			if order.buyer==BUYER and order.good=="grain" and order.seller_site==LOCAL:rescue.append(order.duplicate(true))
		if mode=="named":assert(rescue.size()==1 and rescue[0].quantity==4 and rescue[0].delivered==4)
		else:assert(rescue.is_empty(),"Unnecessary or unauthorized rescue order")
		var old: Dictionary=e._orders[accepted.order_id]
		assert(old.quantity==8 and old.cancelled==0)
		if mode=="unknown_arrival":assert(old.pending==8 and old.transit==0 and e._lots.reserved_quantity(old.id)==8 and records.back().buyer_stock.grain==0)
		else:
			assert(old.delivered==8)
			var paid: int=0
			for tx: Dictionary in b.world.ledger_state.transactions():
				if tx.get("reference_id")==old.id:paid+=int(tx.amount)
			assert(paid==32)
		var restored: WorldBuildResult=restore_fixture(b)
		assert(restored.success,restored.error)
		for key: String in ["economy_native","ledger","total_minutes"]:assert(restored.persistence.snapshot()[key]==b.persistence.snapshot()[key])
		results[mode]={"manager":manager.id,"denied_other_manager":denied,"records":records,"rescue_orders":rescue,"old_order":old.duplicate(true),"restore_exact":true}
		print("REGIONAL_MANAGER ",mode," rescue=",rescue.size()," old_delivered=",old.delivered)
		restored=null;b=null
	var file: FileAccess=FileAccess.open(args[0],FileAccess.WRITE);file.store_string(JSON.stringify(results,"\t"));file.close();completed=true;print("REGIONAL_MANAGERS_FINISHED");quit()
