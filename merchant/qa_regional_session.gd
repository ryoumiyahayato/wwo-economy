extends SceneTree
const Runtime=preload("res://merchant/merchant_runtime.gd")
var completed: bool=false
var started: int=Time.get_ticks_msec()
func _initialize() -> void:call_deferred("run")
func _process(_delta: float) -> bool:
	if not completed and Time.get_ticks_msec()-started>60000:push_error("Regional worker session incomplete");quit(1)
	return false
func receive(runtime: RefCounted,id: int) -> Dictionary:
	var begin: int=Time.get_ticks_msec()
	while Time.get_ticks_msec()-begin<20000:
		for row: Dictionary in runtime.poll():
			if int(row.id)==id:return row
		await create_timer(0.01).timeout
	push_error("Missing worker response "+str(id));quit(1);return {}
func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	var runtime: RefCounted=Runtime.new()
	var condition: String=args[1] if args.size()>1 else "regional_bypass"
	assert(runtime.start_multisource_experiment(condition)==OK)
	var init: Dictionary=await receive(runtime,0)
	assert(init.get("ok",false) and init.view.minute==0 and init.view.research_subject=="",str(init))
	var thread_id: String=runtime._thread.get_id()
	var generation: int=init.generation
	var samples: Array=[]
	for subject: String in ["firm:regional_food","firm:regional_upstream","firm:regional_household",""]:
		var id: int=runtime.submit("research_subject",{"firm":subject})
		assert(id>=0)
		var reply: Dictionary=await receive(runtime,id)
		assert(reply.get("ok",false) and reply.view.minute==0 and reply.generation==generation)
		assert(runtime._thread.get_id()==thread_id and reply.view.research_subject==subject)
		if not subject.is_empty():assert(reply.view.identity.firm_id==subject and reply.view.research_only and not reply.view.identity.can_manage and reply.view.business.is_empty())
		assert(runtime.submit("buy",{"quantity":1})==-1,"Research observer acquired trade authority")
		samples.append({"subject":subject,"minute":reply.view.minute,"identity":reply.view.identity,"thread_id":thread_id,"generation":reply.generation,"nodes":reply.view.market_network.nodes.keys()})
	var invalid: Dictionary=await receive(runtime,runtime.submit("research_subject",{"firm":"firm:not_configured"}))
	assert(not invalid.get("ok",false) and invalid.view.research_subject=="" and invalid.view.minute==0)
	var advanced: Dictionary=await receive(runtime,runtime.submit("advance",{"minutes":60}))
	assert(advanced.get("ok",false) and advanced.view.minute==60 and advanced.view.experiment_main_capacity==10 and advanced.view.experiment_bypass_capacity==0)
	var refreshed: Dictionary=await receive(runtime,runtime.submit("observe"))
	assert(refreshed.view.minute==60 and refreshed.view.firm==advanced.view.firm and refreshed.view.market_network==advanced.view.market_network)
	runtime.request_stop()
	while not runtime.finished():await create_timer(0.01).timeout
	runtime.join_finished()
	var normal: RefCounted=Runtime.new()
	assert(normal.submit("research_subject",{"firm":"firm:regional_food"})==-1)
	assert(not normal._thread.is_started())
	var out: Dictionary={"condition":condition,"samples":samples,"same_worker":true,"same_generation":true,"observation_did_not_advance":true,"rejected_unknown_subject":true,"rejected_trade":true,"normal_runtime_rejected_research":true,"advanced_only_on_explicit_request":true,"clean_worker_join":true,"scope":"NATIVE_WORKER_SESSION_NOT_GUI"}
	var file: FileAccess=FileAccess.open(args[0],FileAccess.WRITE);file.store_string(JSON.stringify(out,"\t"));file.close();completed=true;print("REGIONAL_SESSION_FINISHED");quit()
