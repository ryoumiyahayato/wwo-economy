extends SceneTree
const Save=preload("res://merchant/merchant_save.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	var raw: Dictionary=Save._read(args[0],5)
	var b: WorldBuildResult=FormalPersistence.new().restore_candidate(raw["core"]);assert(b.success)
	var e: EconomyR1Slice=b.world.economy_r1;var found: Array=[]
	for h: int in range(49):
		for site: String in e._site_ids():
			for good: String in e._goods:
				var n: Dictionary=e._input_need(site,good);var obs: Dictionary=n["incoming_observation"]
				var late: int=int(obs["known_late"])+int(obs["unknown_arrival"])
				if late>0 and n["target"]>n["on_hand"]:
					found.append({"minute":b.world.game_clock.total_minutes(),"site":site,"good":good,"need":n,"classification":"KNOWN_UNFINISHED_BOUNDARY: late/unknown accepted responsibility is still deducted from total procurement quantity; not claimed fixed"})
		if not found.is_empty():break
		assert(b.simulation_step.advance_minutes(60).get("success",true))
	var out: Dictionary={"same_day12_input":FileAccess.get_sha256(args[0]),"natural_npc_observation_only":true,"examples":found,"entry":"economy_r1_slice.gd::_input_need quantity=max(0,target-free_stock-incoming)","status":"UNFINISHED_NOT_PASS"}
	var f=FileAccess.open(args[1],FileAccess.WRITE);f.store_string(JSON.stringify(out,"\t"));f.close();print("QA_TIMING_BOUNDARY_OBSERVATION examples=",found.size());quit()
