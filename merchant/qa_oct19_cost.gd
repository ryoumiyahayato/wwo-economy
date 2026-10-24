extends SceneTree
const Runtime=preload("res://merchant/merchant_runtime.gd")
const Opening=preload("res://merchant/merchant_opening.gd")
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func run() -> void:
	for slot: int in [1,2,3,4,5]:
		var runtime=Runtime.new()
		var built: WorldBuildResult=runtime._open(slot)
		check(built.success,"build slot%d"%slot)
		if not built.success:continue
		var before: Dictionary=runtime._view(built)["firm"].duplicate(true)
		var core: Dictionary=built.persistence.snapshot()
		var restored: WorldBuildResult=FormalPersistence.new().restore_candidate(core)
		check(restored.success,"restore slot%d"%slot)
		if not restored.success:continue
		check(runtime._view(restored)["firm"]==before,"FULL_FIRM_PROJECTION_EXACT slot%d"%slot)
		var after: Dictionary=restored.persistence.snapshot()
		for field: String in ["economy_native","ledger","total_minutes"]:check(core[field]==after[field],"slot%d exact %s"%[slot,field])
		built=null;restored=null;runtime=null
	var config: Dictionary=Opening.feedback_configuration()
	config["cost_accounting"]={"freight_treatment":"BUYER_ACQUISITION","joint_allocations":[],"npc_policies":[],"basis":"EXPLICIT_DEVELOPMENT_COST_POLICY"}
	var enabled: WorldBuildResult=WorldBootstrap.new().build(null,[],[],FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT,false,{"format":"HOST_REGION_SELECTION","person_ids":[],"select_people_at_sites":true,"configuration":config})
	check(enabled.success,"enabled build")
	if enabled.success:
		enabled.simulation_step.advance_minutes(1)
		var core: Dictionary=enabled.persistence.snapshot()
		var recovered: WorldBuildResult=FormalPersistence.new().restore_candidate(core)
		check(recovered.success,"enabled restore")
		if recovered.success:check(recovered.persistence.snapshot()["economy_native"]==core["economy_native"],"enabled native cost provenance exact")
		core["economy_native"].erase("cost_allocation")
		var legacy: WorldBuildResult=FormalPersistence.new().restore_candidate(core)
		check(legacy.success,"enabled legacy missing cost provenance restore")
		if legacy.success:check(legacy.world.economy_r1._costs.start_minute==1,"enabled legacy uses actual current boundary")
		core=enabled.persistence.snapshot();core["economy_native"]["cost_allocation"]["start_minute"]=999
		check(not FormalPersistence.new().restore_candidate(core).success,"future enabled cost boundary rejected")
	print("QA_OCT19_COST failures=",failures)
	quit(1 if failures else 0)
