extends SceneTree
const Save=preload("res://merchant/merchant_save.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	var raw: Dictionary=Save._read(args[0],5);assert(raw.get("error","").is_empty())
	var records: Array=[]
	for trial: int in range(3):
		var restorer: FormalPersistence=FormalPersistence.new();var start: int=Time.get_ticks_usec()
		var built: WorldBuildResult=restorer.restore_candidate(raw["core"]);assert(built.success)
		var row: Dictionary={"trial":trial,"same_start_minute":built.world.game_clock.total_minutes(),"restore_wall_us":Time.get_ticks_usec()-start,"restore_components":restorer.restore_diagnostics.duplicate(true),"cache_note":"first restore in this engine process" if trial==0 else "subsequent same-process restore; no persistent world reuse"}
		var writer: RefCounted=Save.new();start=Time.get_ticks_usec();assert(writer.save(built,5,raw["plans"])["success"])
		row["save_wall_us"]=Time.get_ticks_usec()-start;row["save_components"]=writer.timings.duplicate(true)
		start=Time.get_ticks_usec();assert(built.simulation_step.advance_minutes(60).get("success",true));row["ordinary_hour_domain_only_us"]=Time.get_ticks_usec()-start
		if trial==0:
			for hour: int in range(22):assert(built.simulation_step.advance_minutes(60).get("success",true))
			start=Time.get_ticks_usec();assert(built.simulation_step.advance_minutes(60).get("success",true));row["cross_day_domain_only_us"]=Time.get_ticks_usec()-start
			start=Time.get_ticks_usec();assert(writer.save(built,5,raw["plans"])["success"]);row["cross_day_save_separate_us"]=Time.get_ticks_usec()-start
		records.append(row);print("ISOLATED_PROFILE ",JSON.stringify(row));built=null;writer=null;restorer=null
	var file=FileAccess.open(args[1],FileAccess.WRITE);file.store_string(JSON.stringify({"records":records,"optimization":"NONE_NO_SAFE_EQUIVALENT_REUSE_PROVEN","samples":3,"percentile_claim":"NONE","overlap":"parent serial exclusive engine window required","intervals":"restore_components nested under save candidate_restore; do not sum nested intervals"},"\t"));file.close()
	print("QA_DECISIONS_PROFILE_PASS no mutable sharing, exact same archived initial state, no P95 claim")
	quit()
