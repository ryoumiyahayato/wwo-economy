extends SceneTree
const Scene=preload("res://merchant/merchant_scene.gd")
class Mailbox:
	extends RefCounted
	var calls: Array=[]
	var responses: Array[Dictionary]=[]
	var done: bool=false
	var forced: bool=false
	var joined: bool=false
	func submit(kind: String,payload: Dictionary={}) -> int:
		calls.append({"kind":kind,"payload":payload});return calls.size()
	func poll() -> Array[Dictionary]:
		var result: Array[Dictionary]=responses;responses=[];return result
	func finished() -> bool:return done
	func join_finished() -> void:joined=true
	func shutdown_and_join() -> void:
		joined=true
		if forced:responses.append({"id":0,"kind":"host_detached","ok":true,"result":{"host_context":{"schema":"exact-test","minute":99}},"view":{}})
var emitted: int=0
var failed_emitted: int=0
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var scene=Scene.new();var runtime=Mailbox.new();scene.runtime=runtime;scene.pending_requests.clear();scene.busy=false;scene.world_ready=true
	scene._send("buy",{"quantity":2});scene.close_requested=true;scene.save_requested=true;scene._send("close")
	scene._receive({"id":1,"kind":"buy","ok":true,"result":{},"view":{}})
	assert(scene.busy and scene.pending_requests.has(2) and scene.close_requested)
	assert(scene.wait_started_us>0)
	scene._receive({"id":2,"kind":"close","ok":false,"result":{"save_pending":true,"message":"injected disk failure"},"view":{}})
	assert(not scene.close_ack and not scene.close_requested and not scene.busy)
	scene._send("save")
	assert(runtime.calls.size()==3 and runtime.calls[2]["kind"]=="save")
	scene._receive({"id":3,"kind":"save","ok":true,"result":{},"view":{}})
	assert(not scene.busy)
	scene.free()
	# A finished worker still owns an unconsumed close response.
	scene=Scene.new();runtime=Mailbox.new();scene.runtime=runtime;scene.external_host_context={"source":"host"};scene.pending_requests.clear()
	scene.host_continuation_ready.connect(func(_context: Dictionary)->void:emitted+=1)
	runtime.done=true;runtime.responses.append({"id":4,"kind":"close","ok":true,"result":{"host_context":{"schema":"exact-test","minute":99}},"view":{}})
	scene._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	assert(runtime.joined and emitted==1 and scene.returned_host_context["minute"]==99)
	scene._exit_tree();assert(emitted==1)
	await process_frame
	# Forced exit must drain host_detached, without a second signal.
	scene=Scene.new();runtime=Mailbox.new();scene.runtime=runtime;scene.external_host_context={"source":"host"};runtime.forced=true
	scene.host_continuation_ready.connect(func(_context: Dictionary)->void:emitted+=1)
	scene._exit_tree();assert(emitted==2 and runtime.joined)
	scene._exit_tree();assert(emitted==2)
	scene.free()
	# Invalid initial payload fails before creating a thread; pause is not exit.
	scene=Scene.new();scene.external_host_context={"invalid_object":RefCounted.new()}
	scene.host_continuation_failed.connect(func(_message: String)->void:failed_emitted+=1)
	scene._start();assert(scene.startup_failed and scene.pending_requests.is_empty())
	scene._notification(Node.NOTIFICATION_APPLICATION_PAUSED);assert(failed_emitted==0)
	scene._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST);assert(failed_emitted==1)
	await process_frame
	# Finished fatal worker without context must signal failure rather than hang.
	scene=Scene.new();runtime=Mailbox.new();runtime.done=true;scene.runtime=runtime;scene.external_host_context={"source":"host"}
	scene.host_continuation_failed.connect(func(_message: String)->void:failed_emitted+=1)
	scene._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST);assert(failed_emitted==2)
	await process_frame
	print("QA101_RACES_PASS pending_ids close_failure_save_only finished_drain forced_drain exactly_once")
	quit()
