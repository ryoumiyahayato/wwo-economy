extends SceneTree
const Scene=preload("res://merchant/qa101_baseline_scene.gd")
class Mailbox:
	extends RefCounted
	var calls: Array=[]
	var responses: Array[Dictionary]=[]
	func submit(kind: String,payload: Dictionary={}) -> int:calls.append(kind);return calls.size()
	func poll() -> Array[Dictionary]:var result: Array[Dictionary]=responses;responses=[];return result
	func shutdown_and_join() -> void:responses.append({"id":0,"kind":"host_detached","ok":true,"result":{"host_context":{"marker":99}}})
var emitted: int=0
func _initialize() -> void:
	var scene=Scene.new();var runtime=Mailbox.new();scene.runtime=runtime;scene.busy=false;scene.world_ready=true
	scene._send("buy",{});scene.close_requested=true;scene.save_requested=true;scene._send("close")
	scene._receive({"id":1,"kind":"buy","ok":true,"result":{},"view":{}})
	print("OLD_RACE_REPRO busy_after_buy_with_close_pending=",scene.busy)
	assert(not scene.busy,"Expected baseline bug was not reproduced")
	scene.external_host_context={"source":"host"}
	scene.host_continuation_ready.connect(func(_context: Dictionary)->void:emitted+=1)
	scene._exit_tree()
	print("OLD_RACE_REPRO forced_exit_emissions=",emitted," unconsumed=",runtime.responses.size())
	assert(emitted==0 and runtime.responses.size()==1)
	scene.free();print("QA101_OLD_RACES_REPRODUCED");quit()
