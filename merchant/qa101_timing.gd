extends SceneTree
const Runtime=preload("res://merchant/merchant_runtime.gd")
const Save=preload("res://merchant/merchant_save.gd")
const FIXTURE="/workspace/shared/economy_10_experience/actual_gui/day11_pending_save/merchant_host_slot_4.json"
func _initialize() -> void:
	call_deferred("_run")
func _await_response(runtime: RefCounted, id: int) -> Dictionary:
	var until: int=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<until:
		for row: Dictionary in runtime.poll():
			if row.get("kind")=="progress":continue
			if row.get("id")==id:
				row=row.duplicate(true)
				row["receive_us"]=Time.get_ticks_usec()
				return row
		OS.delay_msec(2)
	return {}
func _run() -> void:
	for trial: int in range(7):
		DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
		DirAccess.copy_absolute(FIXTURE,ProjectSettings.globalize_path(Save.path(4)))
		var config:=ConfigFile.new();config.set_value("host","slot",4);config.save("user://merchant_host.cfg")
		var runtime:=Runtime.new();assert(runtime.start()==OK)
		var initial: Dictionary=_await_response(runtime,0)
		assert(initial.get("ok",false));print("TIMING ",JSON.stringify({"trial":trial,"kind":"init","timings":initial.get("timings",{})}))
		for kind: String in ["quote","save","advance"]:
			var payload: Dictionary={"site":"site:paris_market","good":"grain","price":3} if kind=="quote" else {"minutes":60} if kind=="advance" else {}
			if kind=="quote":payload["site"]=initial["view"]["site"]
			var id: int=runtime.submit(kind,payload);assert(id>0)
			var row: Dictionary=_await_response(runtime,id);assert(not row.is_empty())
			print("TIMING ",JSON.stringify({"trial":trial,"kind":kind,"ok":row.get("ok"),"result":row.get("result"),"timings":row.get("timings",{}),"total_us":row.get("total_us"),"response_transfer_us":int(row["receive_us"])-int(row.get("response_ready_us",row["receive_us"]))}))
		if trial==0:
			# Same legal world, finish the remaining 23 hourly actions; only the
			# final action crosses midnight and invokes the real durable commit.
			for hour: int in range(23):
				var daily: Dictionary=_await_response(runtime,runtime.submit("advance",{"minutes":60}))
				assert(daily.get("ok",false))
				if hour==22:print("DAILY_TIMING ",JSON.stringify({"kind":"cross_day_advance","timings":daily.get("timings",{}),"total_us":daily.get("total_us"),"result":daily.get("result")}))
		var close_id: int=runtime.submit("close");assert(_await_response(runtime,close_id).get("ok",false));runtime.shutdown_and_join()
	print("QA101_TIMING_PASS");quit()
