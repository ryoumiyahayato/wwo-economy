extends SceneTree
const Runtime=preload("res://merchant/merchant_runtime.gd")
const Save=preload("res://merchant/merchant_save.gd")
class FailOnce:
	extends "res://merchant/merchant_save.gd"
	var fail_next: bool=true
	func save(built: WorldBuildResult,slot: int,state: Dictionary) -> Dictionary:
		if fail_next:
			fail_next=false;timings={}
			return {"success":false,"message":"QA injected failure before writer; old slot retained"}
		return super.save(built,slot,state)
class ProbeRuntime:
	extends "res://merchant/merchant_runtime.gd"
	var initial_opened: bool=false
	func _open(slot: int) -> WorldBuildResult:
		if initial_opened:return super._open(slot)
		initial_opened=true
		_slot=5
		var built: WorldBuildResult=super._open(5)
		var fault=FailOnce.new();fault.metadata=_save.metadata.duplicate(true);fault.plans=_save.plans.duplicate(true);fault.recovered=_save.recovered
		_save=fault
		return built
func _initialize() -> void:call_deferred("run")
func response(runtime: RefCounted,id: int) -> Dictionary:
	var until: int=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<until:
		for row: Dictionary in runtime.poll():
			if row.get("id")==id:return row
		await create_timer(0.005).timeout
	return {}
func run() -> void:
	var fixture: String=OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	assert(DirAccess.copy_absolute(fixture,ProjectSettings.globalize_path(Save.path(5)))==OK)
	var config:=ConfigFile.new();config.set_value("host","slot",4);config.save("user://merchant_host.cfg")
	var original_hash: String=FileAccess.get_sha256(Save.path(5))
	var runtime=ProbeRuntime.new();assert(runtime.start()==OK)
	var init: Dictionary=await response(runtime,0);assert(init.get("ok",false))
	var request: Dictionary={}
	for offer: Dictionary in init["view"]["business"].get("offers",[]):
		if offer.get("can_order",false):request=offer["request"].duplicate(true);break
	assert(not request.is_empty(),"fixture requires real purchasable offer")
	var bought: Dictionary=await response(runtime,runtime.submit("buy",request))
	assert(bought["result"].get("save_pending",false) and bought["result"]["executed_result"].get("accepted",false))
	assert(FileAccess.get_sha256(Save.path(5))==original_hash)
	var firm_after: Dictionary=bought["view"]["firm"].duplicate(true)
	var blocked: Dictionary=await response(runtime,runtime.submit("buy",request))
	assert(blocked["result"].get("save_pending",false) and blocked["view"]["firm"]==firm_after)
	var retry: Dictionary=await response(runtime,runtime.submit("save"))
	assert(retry.get("ok",false) and not retry["view"]["save_pending"])
	assert(retry["view"]["firm"]==firm_after,"retry cannot execute purchase again")
	var decoded: Dictionary=Save._read(Save.path(5),5)
	assert(decoded.get("error","").is_empty())
	var restored: WorldBuildResult=FormalPersistence.new().restore_candidate(decoded["core"])
	assert(restored.success)
	var inspector=Runtime.new();inspector._plans.state=decoded["plans"].duplicate(true)
	var view: Dictionary=inspector._view(restored)
	assert(view["firm"]==firm_after)
	var bad=FileAccess.open(Save.path(4),FileAccess.WRITE);bad.store_string("{bad candidate");bad.close()
	var failed_switch: Dictionary=await response(runtime,runtime.submit("switch",{"slot":4}))
	assert(not failed_switch["ok"] and failed_switch["view"]["slot"]==5 and failed_switch["view"]["firm"]==firm_after)
	assert((await response(runtime,runtime.submit("close"))).get("ok",false));runtime.shutdown_and_join()
	print("QA_DECISIONS_SAVE_RETRY_PASS actual_buy_injected_save_failure original_file_preserved second_buy_blocked retry_save_exact_no_repeat candidate_restored")
	quit()
