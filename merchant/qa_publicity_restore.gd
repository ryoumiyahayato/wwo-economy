extends SceneTree
## Reopen the unchanged document, then reject a forged merchant grain notice price.
var completed: bool=false
var started: int=Time.get_ticks_msec()
func _initialize() -> void:call_deferred("run")
func _process(_delta: float) -> bool:
	if not completed and Time.get_ticks_msec()-started>60000:quit(1)
	return false
func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	var source: PackedByteArray=FileAccess.get_file_as_bytes(args[0])
	var decoded: Dictionary=FormalWorldPersistenceDocument.decode(JSON.parse_string(source.get_string_from_utf8()))
	assert(decoded.success)
	var built: WorldBuildResult=FormalPersistence.new().restore_candidate(decoded.snapshot)
	assert(built.success,built.error)
	for key: String in ["economy_native","ledger","total_minutes"]:assert(built.persistence.snapshot()[key]==decoded.snapshot[key])
	var selected: String=""
	for id: String in decoded.snapshot.economy_native.commercial_information.publications:
		var row: Dictionary=decoded.snapshot.economy_native.commercial_information.publications[id]
		if row.firm=="firm:merchant_prototype" and row.item=="grain":selected=id;break
	assert(not selected.is_empty(),"No actual merchant grain announcement")
	var forged: Dictionary=decoded.snapshot.duplicate(true)
	forged.economy_native.commercial_information.publications[selected].quote.price+=1
	var rejected: WorldBuildResult=FormalPersistence.new().restore_candidate(forged)
	assert(not rejected.success and "Goods notice differs from original adopted price observation" in rejected.error,"Forged merchant announcement escaped its adopted quote observation")
	assert(source==FileAccess.get_file_as_bytes(args[0]))
	var output: Dictionary={"same_failed_document_restored":true,"economic_state_exact":true,"historical_announcements":built.world.economy_r1._commercial.publications.size(),"forged_announcement_price_rejected":true,"expected_rejection":rejected.error,"source_bytes_unchanged":true}
	var file: FileAccess=FileAccess.open(args[1],FileAccess.WRITE);file.store_string(JSON.stringify(output));file.close();completed=true;print("PUBLICITY_RESTORE_FINISHED ",JSON.stringify(output));quit()
