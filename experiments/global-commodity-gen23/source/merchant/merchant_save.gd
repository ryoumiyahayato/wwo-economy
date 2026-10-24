extends RefCounted
## Host-only envelope. Formal snapshot encoding, restoration and atomic writer are reused.
const Plans=preload("res://merchant/merchant_plans.gd")
const SCHEMA="merchant_host_v1"
var recovered: bool=false
var plans: Dictionary={}
var message: String=""
var metadata: Dictionary={}
var timings: Dictionary={}
var stage_callback: Callable

func _stage(name: String) -> void:
	if stage_callback.is_valid():stage_callback.call(name)

static func path(slot: int) -> String:
	if slot==7:return "user://global_market/merchant_host_global_7.json"
	if slot==6:return "user://regional_trial/merchant_host_trial_6.json"
	if slot==5:return "user://merchant_host_feedback_slot_5.json"
	return "user://merchant_host_slot_%d.json"%slot

func load_slot(slot: int) -> WorldBuildResult:
	recovered=false;plans={};message=""
	var primary: String=path(slot)
	if not FileAccess.file_exists(primary) and not FileAccess.file_exists(primary+".bak"):
		if slot==6:
			var missing:=WorldBuildResult.new();missing.error="独立试玩档不存在；没有新建世界。";return missing
		var legacy: WorldBuildResult=FormalPersistence.new().load_from_user(slot)
		if legacy.success:metadata=legacy.persistence._save_metadata.duplicate(true)
		return legacy
	for candidate: String in [primary,primary+".bak"]:
		if not FileAccess.file_exists(candidate):continue
		var row: Dictionary=_read(candidate,slot)
		if not row.get("error","").is_empty():message=str(row["error"]);continue
		var built: WorldBuildResult=FormalPersistence.new().restore_candidate(row["core"])
		if built.success:
			plans=row["plans"];metadata=row["metadata"];recovered=candidate!=primary
			message="主存档不可用，已恢复上一完整备份；世界和委托一起回退。" if recovered else ""
			return built
		message=built.error
	var failed:=WorldBuildResult.new();failed.error="宿主封套恢复失败，未退回旧世界："+message;return failed

static func has_slot(slot: int) -> bool:
	if slot==6:return FileAccess.file_exists(path(slot)) or FileAccess.file_exists(path(slot)+".bak")
	return FileAccess.file_exists(path(slot)) or FileAccess.file_exists(path(slot)+".bak") or not FormalPersistence.existing_slot_path(slot).is_empty()

func save(built: WorldBuildResult,slot: int,state: Dictionary) -> Dictionary:
	timings={}
	if slot in [6,7]:
		var directory_error: Error=DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://regional_trial"))
		if directory_error!=OK:return {"success":false,"message":error_string(directory_error)}
	if slot==7:
		var directory_error: Error=DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://global_market"))
		if directory_error!=OK:return {"success":false,"message":error_string(directory_error)}
	_stage("snapshot")
	var started: int=Time.get_ticks_usec()
	var core: Dictionary=built.persistence.snapshot()
	timings["snapshot_us"]=Time.get_ticks_usec()-started
	started=Time.get_ticks_usec()
	var problem: String=Plans.validate(state,core)
	if not problem.is_empty():return {"success":false,"message":problem}
	var document: Dictionary={"schema":SCHEMA,"slot":slot,"minute":core["total_minutes"],"core":FormalWorldPersistenceDocument.encode(core,metadata),"plans":Marshalls.raw_to_base64(var_to_bytes(state))}
	timings["envelope_encode_us"]=Time.get_ticks_usec()-started
	# Recovery must not replace the only good .bak with an invalid primary.
	# Write the complete recovered envelope to primary with writer backup rotation
	# disabled only when that primary has first been quarantined, never deleted.
	if recovered and FileAccess.file_exists(path(slot)):
		var quarantine: String=path(slot)+".invalid_"+str(Time.get_unix_time_from_system()).replace(".","_")
		var moved: Error=DirAccess.rename_absolute(ProjectSettings.globalize_path(path(slot)),ProjectSettings.globalize_path(quarantine))
		if moved!=OK:return {"success":false,"message":"不能保留无效主档："+error_string(moved)}
	_stage("atomic_write")
	var writer_started: int=Time.get_ticks_usec()
	var error: String=AtomicJsonFileStore.write_verified(path(slot),document,func(temporary: String)->String:
		_stage("candidate_validation")
		var verify_started: int=Time.get_ticks_usec()
		var decoded: Dictionary=_read(temporary,slot)
		timings["temporary_decode_us"]=Time.get_ticks_usec()-verify_started
		if not str(decoded.get("error","")).is_empty():return decoded["error"]
		verify_started=Time.get_ticks_usec()
		var restorer: FormalPersistence=FormalPersistence.new()
		var candidate: WorldBuildResult=restorer.restore_candidate(decoded["core"])
		for key: String in restorer.restore_diagnostics:timings["diagnostic_"+key]=restorer.restore_diagnostics[key]
		timings["candidate_restore_us"]=Time.get_ticks_usec()-verify_started
		if candidate.success:_stage("atomic_replace")
		return "" if candidate.success else candidate.error,true)
	timings["atomic_io_encode_rotate_us"]=Time.get_ticks_usec()-writer_started-int(timings.get("temporary_decode_us",0))-int(timings.get("candidate_restore_us",0))
	if error.is_empty():
		recovered=false;metadata=document["core"]["save_metadata"].duplicate(true)
	return {"success":error.is_empty(),"message":error}

static func _read(filename: String,slot: int) -> Dictionary:
	var file: FileAccess=FileAccess.open(filename,FileAccess.READ)
	if file==null:return {"error":"封套无法读取"}
	var json:=JSON.new();var code: Error=json.parse(file.get_as_text());file.close()
	if code!=OK or not json.data is Dictionary:return {"error":"封套JSON不完整"}
	var row: Dictionary=json.data
	if not FormalLedgerState.exact_fields(row,["schema","slot","minute","core","plans"]) or row.get("schema")!=SCHEMA or row.get("slot")!=slot or not row.get("core") is Dictionary:return {"error":"封套版本或槽位无效"}
	var decoded: Dictionary=FormalWorldPersistenceDocument.decode(row["core"])
	if not decoded.get("success",false):return {"error":str(decoded.get("error","核心编码无效"))}
	var core: Dictionary=decoded["snapshot"]
	if not FormalLedgerState.valid_amount(core.get("total_minutes")) or row["minute"]!=core["total_minutes"]:return {"error":"封套时间与世界不一致"}
	if not row["plans"] is String:return {"error":"委托编码无效"}
	var plan_state: Variant=bytes_to_var(Marshalls.base64_to_raw(row["plans"]))
	var problem: String=Plans.validate(plan_state,core)
	return {"error":problem,"core":core,"plans":plan_state,"metadata":decoded.get("save_metadata",{})}
