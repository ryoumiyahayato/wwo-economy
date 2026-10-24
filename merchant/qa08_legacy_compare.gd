extends SceneTree
const Opening=preload("res://merchant/merchant_opening.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	# Uses legacy configuration with all new opportunity rules absent.
	var built: WorldBuildResult=WorldBootstrap.new().build(null,[],[],FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT,false,{"format":"HOST_REGION_SELECTION","person_ids":[],"select_people_at_sites":true,"configuration":Opening.supply_configuration()})
	assert(built.success)
	assert(Opening.grant_regional_authority(built.world))
	built.simulation_step.advance_minutes(1)
	var snap: Dictionary=built.persistence.snapshot()
	var restored: WorldBuildResult=FormalPersistence.new().restore_candidate(snap)
	assert(restored.success)
	var after: Dictionary=restored.persistence.snapshot()
	for key: String in snap:
		if snap[key]!=after[key]:
			var detail: Dictionary={}
			if snap[key] is Dictionary and after[key] is Dictionary:
				for sub: String in snap[key]:
					if snap[key][sub]!=after[key].get(sub):
						detail[sub]={"before_size":snap[key][sub].size() if snap[key][sub] is Dictionary or snap[key][sub] is Array else -1,"after_size":after[key].get(sub,{}).size() if after[key].get(sub) is Dictionary or after[key].get(sub) is Array else -1}
			print("LEGACY_CONFIG_ROUNDTRIP_DIFFERENCE ",key," ",JSON.stringify(detail))
	assert(snap["economy_native"]==after["economy_native"] and snap["ledger"]==after["ledger"])
	print("LEGACY_ECONOMY_LEDGER_EXACT_PASS")
	restored=null;built=null;quit()
