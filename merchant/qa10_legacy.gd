extends SceneTree
## Narrow 09 -> 1.0 compatibility; does not rerun historical long simulations.
const Save=preload("res://merchant/merchant_save.gd")
const Runtime=preload("res://merchant/merchant_runtime.gd")
const Opening=preload("res://merchant/merchant_opening.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	var filename: String=args[0] if args.size()>0 else "/workspace/shared/economy_10_experience/checkpoint/legacy09_day8_slot4.json"
	var original_hash: String=FileAccess.get_sha256(filename)
	assert(not original_hash.is_empty())
	var raw: Dictionary=Save._read(filename,4)
	assert(raw.get("error","").is_empty(),str(raw))
	var core: Dictionary=raw["core"]
	var built: WorldBuildResult=FormalPersistence.new().restore_candidate(core)
	assert(built.success,built.error)
	var restored: Dictionary=built.persistence.snapshot()
	for field: String in ["ledger","economy_native","total_minutes"]:
		assert(restored[field]==core[field],"legacy restore changed "+field)
	var person: String=built.world.player_state.player_id()
	var before: Dictionary=LivelihoodAction.query_firm(built.world,person,Opening.FIRM)
	var runtime: RefCounted=Runtime.new();runtime._slot=4;runtime._plans.state=raw["plans"].duplicate(true)
	var view: Dictionary=runtime._view(built)
	assert(view["identity"]["person_id"]==person)
	assert(view["firm"]["orders"]==before["orders"] and view["firm"]["reserved"]==before["reserved"])
	runtime._site=Opening.LYON_SITE
	var remote: Dictionary=runtime._view(built)
	assert(remote["player_place"]==view["player_place"] and remote["minute"]==view["minute"])
	assert(built.persistence.snapshot()==restored,"observe must not mutate authoritative snapshot")
	# Same encoder and atomic writer as HostSave, but an isolated QA filename.
	var temp: String="user://qa10_legacy_roundtrip.json"
	var envelope: Dictionary={"schema":Save.SCHEMA,"slot":4,"minute":restored["total_minutes"],"core":FormalWorldPersistenceDocument.encode(restored,raw["metadata"]),"plans":Marshalls.raw_to_base64(var_to_bytes(raw["plans"]))}
	var error: String=AtomicJsonFileStore.write_verified(temp,envelope,func(path: String)->String:return str(Save._read(path,4).get("error","")),true)
	assert(error.is_empty(),error)
	var again: Dictionary=Save._read(temp,4)
	assert(again.get("error","").is_empty())
	var second: WorldBuildResult=FormalPersistence.new().restore_candidate(again["core"])
	assert(second.success,second.error)
	var second_core: Dictionary=second.persistence.snapshot()
	for field: String in ["ledger","economy_native","total_minutes"]:
		assert(second_core[field]==core[field],"save/reload changed "+field)
	var after: Dictionary=LivelihoodAction.query_firm(second.world,person,Opening.FIRM)
	assert(after["orders"]==before["orders"] and after["reserved"]==before["reserved"],"unresolved order identities or reservations changed")
	assert(again["plans"]==raw["plans"],"plans changed on old-save restoration")
	# Exact native equality includes all NPC commands, inventories and queues;
	# restoration must not execute simulation or replay a command twice.
	assert(second_core["economy_native"]["commands"]==core["economy_native"]["commands"])
	var damaged: String="user://qa10_legacy_damaged.json"
	var file: FileAccess=FileAccess.open(damaged,FileAccess.WRITE);assert(file!=null)
	file.store_string("{\"schema\":");file.close()
	assert(not Save._read(damaged,4).get("error","").is_empty(),"truncated envelope accepted")
	envelope["minute"]=int(envelope["minute"])+1
	file=FileAccess.open(damaged,FileAccess.WRITE);assert(file!=null);file.store_string(JSON.stringify(envelope));file.close()
	assert(not Save._read(damaged,4).get("error","").is_empty(),"mismatched world clock accepted")
	assert(FileAccess.get_sha256(filename)==original_hash,"legacy source overwritten")
	print("QA10_LEGACY_PASS minute=",restored["total_minutes"]," orders=",before["orders"].size()," reserved=",before["reserved"]," exact_ledger_native_clock plans read_only_observe corrupt_rejected source_hash_unchanged")
	built=null;second=null;runtime=null
	quit()
