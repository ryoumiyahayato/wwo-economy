extends SceneTree
const Runtime=preload("res://merchant/merchant_runtime.gd")
var failures: int=0
func _initialize() -> void:call_deferred("run")
func wait_init(r: RefCounted) -> Dictionary:
	var until: int=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<until:
		for response: Dictionary in r.poll():
			if response.get("kind")=="init":return response
		await create_timer(0.01).timeout
	return {}
func run() -> void:
	for round: int in range(3):
		var r: RefCounted=Runtime.new()
		assert(r.start()==OK)
		var first: Dictionary=await wait_init(r)
		assert(first.get("ok",false))
		# Fill business queue, including closing state. Stop must bypass both gates.
		if round==1:r.submit("switch",{"slot":3})
		for i: int in range(8):r.submit("observe",{"quantity":i+1})
		r.request_stop()
		r.shutdown_and_join()
		assert(not r._thread.is_started())
		assert(r.submit("buy",{})==-1)
		print("QA08_FORCED_JOIN round=",round," responses=",r.poll().size())
		r=null
		await process_frame
	var r: RefCounted=Runtime.new()
	assert(r.start()==OK)
	var first: Dictionary=await wait_init(r)
	assert(first.get("ok",false))
	assert(r.submit("close")>0)
	while not r.finished():await create_timer(0.01).timeout
	var acknowledged: bool=false
	for row: Dictionary in r.poll():
		if row.get("kind")=="close" and row.get("ok",false):acknowledged=true
	assert(acknowledged)
	r.join_finished();r=null
	print("QA08_THREAD_PASS forced_queue_shutdown normal_save_ack join")
	quit()
