extends SceneTree
const Save=preload("res://merchant/merchant_save.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var filename: String=OS.get_cmdline_user_args()[0]
	var raw: Dictionary=Save._read(filename,3)
	assert(raw.get("error","").is_empty())
	var built: WorldBuildResult=FormalPersistence.new().restore_candidate(raw["core"])
	assert(built.success)
	var snap: Dictionary=built.persistence.snapshot()
	assert(snap["ledger"]==raw["core"]["ledger"])
	assert(snap["economy_native"]==raw["core"]["economy_native"])
	assert(not built.world.economy_r1.config.has("supply_opportunity_policies"))
	print("QA08_LEGACY_FILE_PASS minute=",snap["total_minutes"]," native_and_ledger_exact old_configuration_retained")
	built=null;quit()
