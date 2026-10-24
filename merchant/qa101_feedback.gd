extends SceneTree
const Scene=preload("res://merchant/merchant_scene.gd")
const Runtime=preload("res://merchant/merchant_runtime.gd")
class Mailbox:
	extends RefCounted
	var calls: Array=[]
	func submit(kind: String,payload: Dictionary) -> int:
		calls.append({"kind":kind,"payload":payload.duplicate(true)})
		return calls.size()
func _initialize() -> void:
	var scene=Scene.new()
	scene.stepping=true;scene.current_minute=1441;scene.requested_day_start=1381;scene.queued_minutes=1380
	scene.wait_stage="candidate_validation"
	assert(scene._wait_text(3).contains("恢复校验"))
	assert(scene._wait_text(3).contains("60/1440"))
	scene._pause()
	assert(scene.current_minute==1441 and scene.queued_minutes==0 and scene.stepping)
	assert(scene._wait_text(4).contains("本小时后暂停"))
	var runtime=Runtime.new()
	runtime._stage("domain")
	assert(runtime.poll().is_empty(),"progress cannot alter legacy response interface")
	assert(Runtime._plain(runtime.poll_progress()))
	assert(runtime.poll_progress().is_empty())
	assert(runtime.submit("buy",{"node":scene})==-1,"Object must be rejected")
	var mailbox=Mailbox.new()
	scene.runtime=mailbox;scene.busy=false;scene.confirm_kind="buy";scene.confirm_payload={"quantity":2}
	scene._confirm();scene._confirm();scene._send("buy",{"quantity":2})
	assert(mailbox.calls.size()==1 and scene.confirm_kind.is_empty())
	scene.free();runtime=null
	print("QA101_FEEDBACK_PASS confirmed_boundary pause_no_rollback original_poll pure_values")
	quit()
