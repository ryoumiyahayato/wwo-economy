extends SceneTree
const Save=preload("res://merchant/merchant_save.gd")
const Opening=preload("res://merchant/merchant_opening.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	var legacy: String=args[0] if args.size()>0 else "/workspace/shared/economy_09_feedback/checkpoint/day6_slot4.json"
	var raw: Dictionary=Save._read(legacy,4)
	assert(raw.get("error","").is_empty())
	var built: WorldBuildResult=FormalPersistence.new().restore_candidate(raw["core"])
	assert(built.success)
	var snap: Dictionary=built.persistence.snapshot()
	var e: EconomyR1Slice=built.world.economy_r1
	var view: Dictionary=e.managed_market_feedback(built.world.player_state.player_id(),Opening.FIRM)
	assert(view["events"].size()<=12)
	var seen: Dictionary={}
	for event: Dictionary in view["events"]:
		var key: String=str(event["refs"])
		assert(not seen.has(key));seen[key]=true
	assert(e._delivery_minute({"delivered_day":3})==4320)
	assert(e.managed_market_feedback("unknown",Opening.FIRM).is_empty())
	assert(snap==built.persistence.snapshot())
	print("QA09_PROJECTION_PASS ",JSON.stringify(view))
	built=null;quit()
