extends "res://merchant/qa_company_procurement_priority.gd"
## One legal finite source-price case on the timing-fixed candidate.
## -- /absolute/report.json baseline|candidate known_new_material_loss
## baseline means pre-cost-policy current source, never the old sales-control.
## New purchase cash lower bound is 2*30=60 for output quoted48. No claim of
## historical inventory cost, net profit, or guaranteed future revenue is made.

func run() -> void:
	started=Time.get_ticks_msec()
	var args:=OS.get_cmdline_user_args()
	if args.size()!=3 or not args[0].is_absolute_path() or args[1] not in ["baseline","candidate"] or args[2]!="known_new_material_loss":
		push_error("Usage: -- /absolute/report.json baseline|candidate known_new_material_loss");quit(2);return
	output_path=args[0];baseline=args[1]=="baseline";case_name=args[2]
	var cfg:=configuration("priority_input_first")
	cfg["case_id"]="QA_FINITE_NEW_INPUT_CASH_LOWER_BOUND"
	firm_row(cfg,TEXTILE)["cash"]=400
	site_row(cfg,"site:regional_textile:z_optional")["targets"]["bread"]=0
	site_row(cfg,FARM)["prices"]["fiber"]=30
	site_row(cfg,WEAVE)["prices"]["clothes"]=48
	evidence={"initial_configuration":cfg,"configuration_sha256":JSON.stringify(cfg).sha256_text(),"scope":"Only optional replenishment using entirely new known external fiber. No old cost activation, backward cost fill, revenue guarantee, or accepted output obligation.","comparison":"Same initial world and quotes before/after the finite new-input cash policy; not a comparison with simultaneous price or resource edits."}
	write_report("FIXTURE_DECLARED_BEFORE_BOOTSTRAP")
	if not check(EconomySliceConfig.valid(cfg),"Original finite initial configuration is legal"): write_report("INVALID_FIXTURE");quit(1);return
	var b:WorldBuildResult=WorldBootstrap.new().build(null,[],[],FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT,true,{"format":"HOST_REGION_SELECTION","person_ids":[],"select_people_at_sites":false,"configuration":cfg})
	if not check(b.success,"Original WorldBootstrap accepts the source-price fixture: "+str(b.error)):write_report("BOOTSTRAP_FAILED");quit(1);return
	check(b.simulation_step.advance_minutes(1).get("success",true),"Day-zero source information is actually delivered")
	var e:EconomyR1Slice=b.world.economy_r1
	accept_original_employment(e)
	var offer:Dictionary=e._offer(TEXTILE,UPSTREAM,"fiber","edge:regional_local:lyon",FARM,WEAVE)
	var recipe:Dictionary=e._activity(WEAVE,"activity:regional_clothes")
	var lower:int=2*(int(offer["price"])+int(offer["freight_per_unit"]))
	check(int(recipe["materials"]["fiber"])==2 and recipe["outputs"].size()==1 and int(recipe["outputs"]["clothes"])==1,"Original single final-output recipe is fiber2 to clothes1")
	check(typeof(offer.get("price"))==TYPE_INT and offer["price"]==30 and offer["transport_quantity"]>=2,"New external material quote is actually known and executable")
	check(lower==60 and e._price(WEAVE,"clothes")==48,"Known new-material cash alone exceeds the quoted output receipt before wages or other unknown costs")
	check(int(e._stocks[WEAVE]["fiber"])==0 and int(e._stocks[WEAVE]["clothes"])==0,"No old unknown material or output cost is silently replaced with today's quote")
	check(e._committed(WEAVE,"clothes")==0,"Fixture has no accepted output obligation to erase for profitability")
	evidence["before"]={"minute":b.world.game_clock.total_minutes(),"offer":offer,"recipe":recipe,"known_new_material_cash_lower_bound":lower,"quoted_output_receipt_not_guaranteed":48,"historical_cost":"UNKNOWN_NOT_FILLED","wages":company_wages(e)}
	write_report("FIXTURE_READY_BEFORE_ORIGINAL_DAY")
	if advance_first_day(b):
		if e.has_method("_production_new_input_contribution"):
			var before_query: Dictionary = b.persistence.snapshot()
			var contribution: Dictionary = e.call("_production_new_input_contribution", WEAVE, "activity:regional_clothes")
			check(contribution == e.call("_production_new_input_contribution", WEAVE, "activity:regional_clothes") and b.persistence.snapshot() == before_query, "Known new-input contribution query leaves the complete world unchanged")
			check(contribution.get("known_new_material_cash_lower_bound") == 60 and contribution.get("quoted_output_receipt_not_guaranteed") == 48 and contribution.get("historical_material_cost") == null, "Known new cash and quoted possible receipt do not invent unknown historical costs")
			evidence["new_input_contribution"] = contribution
		var orders:=matching_orders(e,WEAVE,"fiber")
		evidence["outcome"]={"minute":b.world.game_clock.total_minutes(),"orders":orders,"commands":actual_commands(e,orders),"plan":e._plans[WEAVE].duplicate(true),"need":e._input_need(WEAVE,"fiber"),"physical":e._physical_totals[WEAVE].duplicate(true),"stocks":e._stocks[WEAVE].duplicate(true),"work_records":e._work_records.duplicate(true),"wages":company_wages(e),"ledger":b.world.ledger_state.snapshot()}
		check(quantity(orders)==0,"Finite optional production policy declines new material cash60 for quoted output48",true)
		check(int(e._stocks[WEAVE]["fiber"])==0 and int(e._stocks[WEAVE]["clothes"])==0,"No material or output is created while the optional batch waits")
		verify_order_replay(e,b,orders)
	if not baseline: verify_normalized_complete_restore(b)
	write_report("FINISHED")
	print("QA_PRODUCTION_CASH_FEEDBACK failures=",failures," elapsed_msec=",Time.get_ticks_msec()-started)
	quit(1 if failures>0 else 0)
