extends RefCounted
## Host execution boundary only. No economic calculations live here.
## The worker's local `built` is never exposed to the scene/UI thread.
const MarketNetwork=preload("res://merchant/merchant_market_network.gd")
const MarketContacts=preload("res://merchant/merchant_market_contacts.gd")
const NetworkExperiment=preload("res://merchant/network_experiment_opening.gd")
const MultiSourceExperiment=preload("res://merchant/multisource_opening.gd")
const RegionalReaction=preload("res://merchant/regional_reaction_opening.gd")
const AdaptiveContacts=preload("res://merchant/adaptive_contacts_opening.gd")
const ConsumerAccess=preload("res://merchant/consumer_access_opening.gd")
const ConsumerProjection=preload("res://merchant/consumer_access_projection.gd")
const CommercialAdaptation=preload("res://merchant/commercial_adaptation_opening.gd")
const Opening=preload("res://merchant/merchant_opening.gd")
const Plans=preload("res://merchant/merchant_plans.gd")
const HostSave=preload("res://merchant/merchant_save.gd")
var _plans: RefCounted=Plans.new()
var _save: RefCounted=HostSave.new()
var _save_blocked: bool=false
var _load_notice: String=""
var _thread: Thread=Thread.new()
var _mutex: Mutex=Mutex.new()
var _wake: Semaphore=Semaphore.new()
var _requests: Array[Dictionary]=[]
var _responses: Array[Dictionary]=[]
var _next_id: int=1
var _generation: int=1
var _accepting: bool=true
var _closing: bool=false
var _stop_requested: bool=false
var _slot: int=4
var _site: String=Opening.SITE
var _quantity: int=2
var _offset: int=0
var _contract_id: String=""
const HOST_SCHEMA: String="merchant_external_host_v1"
var _external: bool=false
var _host_context: Dictionary={}
var _quote_authority: String=""
var _host_metadata: Dictionary={}
var _progress: Array[Dictionary]=[]
var _active_id: int=0
var _timings: Dictionary={}
var _observer_only: bool=false
var _network_experiment: bool=false
var _multisource_condition: String=""
var _research_subject: String=""
var _business_experiment: bool=false
var _trial_persistent: bool=false
var _global_experiment: bool=false
var _global_scenario: String="baseline"

func start_global(scenario: String="baseline") -> Error:
	if _thread.is_started():return ERR_ALREADY_IN_USE
	if ProjectSettings.get_setting("application/config/custom_user_dir_name","")!="wwo_economy_map_test_global_resume_20261024" or scenario not in ["baseline","shocks"]:return ERR_UNAUTHORIZED
	_global_experiment=true;_global_scenario=scenario;_network_experiment=true;_slot=7
	return start()
const PUBLICITY_ACTIONS=["apply","work","leave_job","publish_notice","request_service","withdraw_announcement","set_publicity_policy"]

func start_trial() -> Error:
	if _thread.is_started():return ERR_ALREADY_IN_USE
	if ProjectSettings.get_setting("application/config/custom_user_dir_name","") not in ["wwo_economy_map_test_dated_procurement_20261023","wwo_economy_map_test_global_resume_20261024"]:return ERR_UNAUTHORIZED
	if not HostSave.has_slot(6):return ERR_FILE_NOT_FOUND
	_business_experiment=true;_trial_persistent=true;_slot=6;_quote_authority=Opening.REGIONAL_AUTHORITY
	return start()

func start_multisource_experiment(condition: String) -> Error:
	if _thread.is_started():return ERR_ALREADY_IN_USE
	if condition not in MultiSourceExperiment.CONDITIONS and condition not in RegionalReaction.CONDITIONS and condition not in AdaptiveContacts.CONDITIONS and condition not in CommercialAdaptation.CONDITIONS and condition not in ConsumerAccess.CONDITIONS:return ERR_INVALID_PARAMETER
	_multisource_condition=condition
	return start_network_experiment()

# Explicit disposable development opening. No persisted slot is read or written.
func start_network_experiment() -> Error:
	if not str(ProjectSettings.get_setting("application/config/custom_user_dir_name","")).begins_with("wwo_economy_map_test_"):return ERR_UNAUTHORIZED
	if _thread.is_started():return ERR_ALREADY_IN_USE
	_network_experiment=true;_slot=0
	return start()

# Explicit existing-slot observer. Does not use startup preferences or create a world.
func start_observer(slot: int) -> Error:
	if _thread.is_started():return ERR_ALREADY_IN_USE
	if slot not in [1,2,3,4,5] or not HostSave.has_slot(slot):return ERR_FILE_NOT_FOUND
	_observer_only=true
	_slot=slot
	return start()

func _stage(name: String) -> void:
	var event: Dictionary={"id":_active_id,"stage":name,"at_us":Time.get_ticks_usec()}
	_mutex.lock()
	# Keep only current stage: consumers may ignore this optional observation channel.
	_progress=[event]
	_mutex.unlock()

func poll_progress() -> Array[Dictionary]:
	_mutex.lock()
	var events: Array[Dictionary]=_progress
	_progress=[]
	_mutex.unlock()
	return events

# Called before start; the host relinquishes its mutable world while this worker
# owns the restored continuation. No WorldState/RefCounted crosses the mailbox.
static func host_context(snapshot: Dictionary, person_id: String, firm_id: String, site_id: String, plans: Dictionary={}, quote_authority_id: String="", save_metadata: Dictionary={}) -> Dictionary:
	return {"schema":HOST_SCHEMA,"snapshot_document":FormalWorldPersistenceDocument.encode(snapshot,save_metadata),"person_id":person_id,"firm_id":firm_id,"site_id":site_id,"plans":(Plans.new().state if plans.is_empty() else plans).duplicate(true),"quote_authority_id":quote_authority_id}


func start(context: Dictionary={}) -> Error:
	if _thread.is_started():return ERR_ALREADY_IN_USE
	if not _plain(context):return ERR_INVALID_DATA
	_external=not context.is_empty()
	_host_context=context.duplicate(true)
	var error: Error=_thread.start(_run)
	if error!=OK:_accepting=false
	return error

func start_external(context: Dictionary) -> Error:
	if context.is_empty():return ERR_INVALID_DATA
	return start(context)

func submit(kind: String, payload: Dictionary={}) -> int:
	if _global_experiment and kind in ["global_advance","global_save","global_enter_business"]:return _enqueue(kind,payload)
	if kind=="enable_trial_save" and not _business_experiment:return -1
	if kind=="save" and _business_experiment and not _trial_persistent:return -1
	if _business_experiment and kind not in ["observe","advance","close","save","enable_trial_save","accept_supply_contract","submit_supply_batch","terminate_supply_contract","buy","cancel","transfer_goods","travel","set_site_status","quote","sales_control","plan"]+PUBLICITY_ACTIONS:return -1
	if kind=="research_subject" and (not _network_experiment or _multisource_condition not in RegionalReaction.CONDITIONS+AdaptiveContacts.CONDITIONS+CommercialAdaptation.CONDITIONS+ConsumerAccess.CONDITIONS):return -1
	if _network_experiment and not _business_experiment and kind not in ["observe","advance","network_capacity","close","research_subject","enter_business"]:return -1
	if kind=="enter_business" and (not _network_experiment or _multisource_condition not in ConsumerAccess.TURNOVER_CHOICES+ConsumerAccess.PUBLICITY_CHOICES):return -1
	if _observer_only and kind not in ["observe","close"]:return -1
	if kind=="switch" and int(payload.get("slot",0))==5 and payload.get("feedback_opt_in",false)!=true:return -1
	if kind=="host_advance" or (_external and kind in ["advance","switch","stop"]):return -1
	return _enqueue(kind,payload)

func advance_from_host(minutes: int) -> int:
	if not _external or minutes<0 or minutes>60:return -1
	return _enqueue("host_advance",{"minutes":minutes})

func _enqueue(kind: String, payload: Dictionary={}) -> int:
	# Copy before crossing ownership; only primitive values may cross.
	var request: Dictionary={"kind":kind,"payload":payload.duplicate(true)}
	if not _plain(request):return -1
	_mutex.lock()
	if not _accepting or _closing or _requests.size()>=8:
		_mutex.unlock();return -1
	var id: int=_next_id;_next_id+=1
	request["id"]=id
	request["enqueued_us"]=Time.get_ticks_usec()
	request["generation"]=_generation
	if kind in ["close","switch"]:_closing=true
	_requests.append(request)
	_mutex.unlock()
	_wake.post()
	return id

func poll() -> Array[Dictionary]:
	_mutex.lock()
	var result: Array[Dictionary]=_responses
	_responses=[]
	_mutex.unlock()
	return result

func finished() -> bool:
	return _thread.is_started() and not _thread.is_alive()

func join_finished() -> void:
	if finished():_thread.wait_to_finish()

func request_stop() -> void:
	# Control-plane stop cannot be rejected by business queue capacity or closing.
	_mutex.lock();_stop_requested=true;_accepting=false;_mutex.unlock()
	_wake.post()

func shutdown_and_join() -> void:
	# Only the forced scene teardown barrier blocks. Normal close remains async.
	request_stop()
	if _thread.is_started():_thread.wait_to_finish()


static func _plain(value: Variant) -> bool:
	if value is Dictionary:
		for key: Variant in value:
			if not _plain(key) or not _plain(value[key]):return false
		return true
	if value is Array:
		for item: Variant in value:
			if not _plain(item):return false
		return true
	return typeof(value) in [TYPE_NIL,TYPE_BOOL,TYPE_INT,TYPE_FLOAT,TYPE_STRING]

static func _freeze(value: Variant) -> void:
	if value is Dictionary:
		for item: Variant in value.values():_freeze(item)
		value.make_read_only()
	elif value is Array:
		for item: Variant in value:_freeze(item)
		value.make_read_only()

func _publish(value: Dictionary) -> bool:
	var valid: bool=_plain(value)
	if not valid:
		# A fail-closed primitive response is safe even in release builds.
		value={"id":value.get("id",0),"kind":value.get("kind","init"),"ok":false,"fatal":true,"message":"视图包含不允许跨线程的对象，已停止接受操作。","result":{"success":false,"error":"NON_VALUE_MAILBOX"},"view":{}}
		_mutex.lock();_accepting=false;_mutex.unlock()
	value=value.duplicate(true)
	_freeze(value)
	_mutex.lock();_responses.append(value);_mutex.unlock()
	return valid

func _open(slot: int) -> WorldBuildResult:
	# Slot 5 is only entered by an explicit scene confirmation, never startup preference.
	if slot not in [1,2,3,4,5,6] or (slot==6 and not _trial_persistent):
		var invalid:=WorldBuildResult.new();invalid.error="INVALID_HOST_SLOT";return invalid
	if HostSave.has_slot(slot):
		var loader: RefCounted=HostSave.new()
		var loaded: WorldBuildResult=loader.load_slot(slot)
		if loaded.success and slot==5 and (loaded.world.economy_r1==null or loaded.world.economy_r1.config.get("case_id","")!="MERCHANT_REGION_FEEDBACK_CANDIDATE"):
			loaded.success=false;loaded.error="实验存档配置不匹配，未迁移或重建世界。"
		if loaded.success and slot==6:
			var e: EconomyR1Slice=loaded.world.economy_r1
			if e==null or e.config.get("case_id","")!=ConsumerAccess.CASE or e.firm_manager_at(Opening.FIRM,loaded.world.game_clock.total_minutes())!=loaded.world.player_state.player_id() or loaded.world.organization_state.authority_grant(Opening.REGIONAL_AUTHORITY).is_empty():
				loaded.success=false;loaded.error="试玩档人物、商号或原授权不匹配；未重建世界。"
		if loaded.success:
			_save=loader
			_plans=Plans.new()
			if not _save.plans.is_empty():_plans.state=_save.plans.duplicate(true)
			_load_notice=_save.message
		return loaded
	if _observer_only or slot==6:
		var missing:=WorldBuildResult.new();missing.error="OBSERVER_SAVE_MISSING";return missing
	var configuration: Dictionary=Opening.feedback_configuration() if slot==5 else Opening.opportunities_configuration() if slot==4 else Opening.supply_configuration() if slot==3 else Opening.regional_configuration() if slot==2 else Opening.configuration()
	var built: WorldBuildResult=WorldBootstrap.new().build(null,[],[],FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT,false,{"format":"HOST_REGION_SELECTION","person_ids":[],"select_people_at_sites":true,"configuration":configuration})
	if built.success:
		var granted: bool=Opening.grant_regional_authority(built.world) if slot>=2 else Opening.grant_quote_authority(built.world)
		if not granted:built.success=false;built.error="Opening quote authority failed"
	if built.success:
		var first: Dictionary=built.simulation_step.advance_minutes(1)
		if not first.get("success",true):built.success=false;built.error=str(first)
	if built.success:_plans=Plans.new();_save=HostSave.new();_load_notice=""
	return built

func _restore_host() -> WorldBuildResult:
	var failed:=WorldBuildResult.new()
	failed.error="INVALID_HOST_CONTEXT"
	if not FormalLedgerState.exact_fields(_host_context,["schema","snapshot_document","person_id","firm_id","site_id","plans","quote_authority_id"]):return failed
	if _host_context.get("schema")!=HOST_SCHEMA or not _host_context.get("snapshot_document") is Dictionary:return failed
	for key: String in ["person_id","firm_id","site_id","quote_authority_id"]:
		if not _host_context.get(key) is String:return failed
	if _host_context["firm_id"]!=Opening.FIRM:
		failed.error="UNSUPPORTED_HOST_FIRM";return failed
	var decoded: Dictionary=FormalWorldPersistenceDocument.decode(_host_context["snapshot_document"])
	if not decoded.get("success",false):failed.error=str(decoded.get("error","INVALID_HOST_DOCUMENT"));return failed
	var core: Dictionary=decoded["snapshot"]
	var problem: String=Plans.validate(_host_context["plans"],core)
	if not problem.is_empty():failed.error=problem;return failed
	var candidate: WorldBuildResult=FormalPersistence.new().restore_candidate(core)
	if not candidate.success:return candidate
	var world: WorldState=candidate.world
	var person: String=_host_context["person_id"]
	if world.economy_r1==null or world.player_state.player_id()!=person or LivelihoodAction.query(world,person).is_empty():return failed
	var managed: Dictionary=LivelihoodAction.query_firm(world,person,Opening.FIRM)
	if managed.is_empty() or not managed.get("operations",[]).any(func(row: Dictionary)->bool:return row.get("site_id")==_host_context["site_id"]):
		failed.error="HOST_MANAGEMENT_OR_SITE_UNAUTHORIZED";return failed
	_quote_authority=_host_context["quote_authority_id"]
	if not _quote_authority.is_empty() and world.organization_state.authority_grant(_quote_authority).is_empty():
		failed.error="UNKNOWN_HOST_QUOTE_AUTHORITY";return failed
	_host_metadata=decoded.get("save_metadata",{}).duplicate(true)
	_site=_host_context["site_id"]
	_slot=0
	_plans=Plans.new();_plans.state=_host_context["plans"].duplicate(true)
	_host_context={} # The worker retains one authoritative continuation, not a backup world.
	return candidate

func _export_host(built: WorldBuildResult) -> Dictionary:
	return host_context(built.persistence.snapshot(),built.world.player_state.player_id(),Opening.FIRM,_site,_plans.state,_quote_authority,_host_metadata)

func _remember_slot() -> void:
	# Keep the last ordinary slot as the startup destination, even after experimental play.
	if _slot>=5:return
	var config:=ConfigFile.new();config.set_value("host","slot",_slot);config.save("user://merchant_host.cfg")

func _run() -> void:
	var preference:=ConfigFile.new()
	if not _external and not _observer_only and not _network_experiment and not _trial_persistent and preference.load("user://merchant_host.cfg")==OK:_slot=clampi(int(preference.get_value("host","slot",4)),1,4)
	var load_started: int=Time.get_ticks_usec()
	_stage("loading")
	var built: WorldBuildResult
	if _global_experiment:
		built=_save.load_slot(7 if HostSave.has_slot(7) else 6)
		if built.success:
			_plans.state=_save.plans.duplicate(true)
		if built.success and built.world.economy_state.reference_market==null:
			if not built.world.economy_state.enable_reference_market(_global_scenario):built.success=false;built.error="REFERENCE_MARKET_NOT_ENABLED"
	elif _network_experiment:
		built=ConsumerAccess.build(_multisource_condition) if _multisource_condition in ConsumerAccess.CONDITIONS else CommercialAdaptation.build(_multisource_condition) if _multisource_condition in CommercialAdaptation.CONDITIONS else AdaptiveContacts.build() if _multisource_condition in AdaptiveContacts.CONDITIONS else RegionalReaction.build() if _multisource_condition in RegionalReaction.CONDITIONS else NetworkExperiment.build() if _multisource_condition.is_empty() else MultiSourceExperiment.build(_multisource_condition)
		if built.success and not _multisource_condition.is_empty() and built.world.economy_r1!=null:
			var condition_action: Dictionary=ConsumerAccess.apply_condition(built.world,_multisource_condition) if _multisource_condition in ConsumerAccess.CONDITIONS else CommercialAdaptation.apply_condition(built.world,_multisource_condition) if _multisource_condition in CommercialAdaptation.CONDITIONS else AdaptiveContacts.apply_condition(built.world,_multisource_condition) if _multisource_condition in AdaptiveContacts.CONDITIONS else RegionalReaction.apply_condition(built.world,_multisource_condition) if _multisource_condition in RegionalReaction.CONDITIONS else MultiSourceExperiment.capacity(built.world,0 if _multisource_condition=="blocked" else 10)
			if not condition_action.get("accepted",false):built.success=false;built.error=str(condition_action)
	elif _observer_only:
		# Recheck on the worker: a deleted/missing save must never fall through to bootstrap.
		built=_open(_slot) if HostSave.has_slot(_slot) else WorldBuildResult.new()
		if not HostSave.has_slot(_slot):built.error="OBSERVER_SAVE_MISSING"
	else:built=_restore_host() if _external else _open(_slot)
	var ready: bool=built.success and built.world.economy_r1!=null
	var message: String="已继续存档；时间暂停。选择地图与经营页开始。" if ready else "世界未能恢复，存档未覆盖："+built.error
	if ready:
		built.world.economy_r1._dated_input_procurement_enabled=(_network_experiment or _business_experiment) and built.world.economy_r1.config.get("case_id")==ConsumerAccess.CASE and ProjectSettings.get_setting("application/config/custom_user_dir_name","") in ["wwo_economy_map_test_dated_procurement_20261023","wwo_economy_map_test_global_resume_20261024"]
		if _external:message="已接入宿主原世界；由宿主独占推进时间。"
		if not _external and not _observer_only and not _network_experiment:_remember_slot()
		if _observer_only:message="只读观察已恢复；时间暂停，关闭不写存档。"
		if not _load_notice.is_empty():message=_load_notice
	var load_us: int=Time.get_ticks_usec()-load_started
	_stage("observation")
	var initial_view_started: int=Time.get_ticks_usec()
	var initial_view: Dictionary=_view(built) if ready else {}
	if not _publish({"timings":{"first_load_us":load_us,"observation_us":Time.get_ticks_usec()-initial_view_started},"id":0,"kind":"init","generation":_generation,"ok":ready,"message":message,"view":initial_view}):return
	while true:
		_wake.wait()
		_mutex.lock()
		var request: Dictionary=_requests.pop_front() if not _requests.is_empty() else {}
		var stopping: bool=_stop_requested
		_mutex.unlock()
		if request.is_empty():
			if stopping:
				if ready and not _observer_only:
					var saved: Dictionary=_commit(built)
					if _external and saved["success"]:_publish({"id":0,"kind":"host_detached","ok":true,"result":{"success":true,"host_context":_export_host(built)},"view":{}})
					if not saved["success"]:push_error("Forced shutdown save failed; previous complete save retained: "+str(saved["message"]))
				break
			continue
		var kind: String=request["kind"]
		if kind=="stop":break
		var start_us: int=Time.get_ticks_usec()
		_active_id=int(request["id"])
		_timings={"queue_us":start_us-int(request["enqueued_us"])}
		var result: Dictionary={"success":false,"error":"WORLD_NOT_READY"}
		var payload: Dictionary=request["payload"]
		if ready and request["generation"]==_generation and (not _save_blocked or kind in ["save","close","observe"]):
			if kind in ["advance","host_advance","accept_supply_contract","submit_supply_batch","terminate_supply_contract","buy","cancel","transfer_goods","travel","set_site_status","quote","sales_control","plan"]:_stage("domain")
			match kind:
				"global_enter_business":
					var allowed: bool=built.world.economy_r1.firm_manager_at(Opening.FIRM,built.world.game_clock.total_minutes())==built.world.player_state.player_id()
					if allowed:_business_experiment=true;_trial_persistent=true;_research_subject="";_quote_authority=Opening.REGIONAL_AUTHORITY;_site=Opening.SITE
					result={"success":allowed,"reason":"SAME_RUNTIME_EXISTING_MANAGER" if allowed else "NO_CURRENT_MANAGER_AUTHORITY"}
				"global_advance":
					result=built.simulation_step.advance_minutes(clampi(int(payload.get("days",1)),1,7)*1440)
				"global_save":
					result=_save.save(built,7,_plans.state)
				"enable_trial_save":
					if not _business_experiment or _trial_persistent or HostSave.has_slot(6) or ProjectSettings.get_setting("application/config/custom_user_dir_name","")!="wwo_economy_map_test_dated_procurement_20261023":
						result={"success":false,"message":"独立试玩档已存在或当前会话不允许另存；请从F6继续已有试玩档。"}
					else:
						_trial_persistent=true;_slot=6
						result=_commit(built)
				"apply","work","leave_job","publish_notice","request_service","withdraw_announcement","set_publicity_policy":result=LivelihoodAction.execute_current(built.world,kind,payload)
				"enter_business":
					var allowed: bool=_network_experiment and not _business_experiment and _multisource_condition in ConsumerAccess.TURNOVER_CHOICES+ConsumerAccess.PUBLICITY_CHOICES and built.world.economy_r1.firm_manager_at(Opening.FIRM,built.world.game_clock.total_minutes())==built.world.player_state.player_id()
					if allowed and built.world.organization_state.authority_grant(Opening.REGIONAL_AUTHORITY).is_empty():allowed=Opening.grant_regional_authority(built.world)
					if allowed:
						_business_experiment=true;_research_subject="";_site=Opening.SITE;_quote_authority=Opening.REGIONAL_AUTHORITY
					result={"success":allowed,"reason":"SAME_RUNTIME_LEGAL_BUSINESS_NO_SAVE" if allowed else "NO_EXISTING_MERCHANT_AUTHORITY"}
				"research_subject":
					var subject: String=str(payload.get("firm",""))
					var allowed: bool=_network_experiment and not _business_experiment and _research_subject_rows(built.world).any(func(row: Dictionary):return row.id==subject)
					if allowed:_research_subject=subject
					result={"success":allowed,"reason":"READ_ONLY_DEVELOPER_OBSERVER" if allowed else "NO_RESEARCH_OBSERVER"}
				"network_capacity":
					if not _network_experiment:result={"accepted":false,"reason":"EXPERIMENT_ONLY"}
					elif _multisource_condition in RegionalReaction.CONDITIONS+AdaptiveContacts.CONDITIONS+CommercialAdaptation.CONDITIONS+ConsumerAccess.CONDITIONS:result={"accepted":false,"reason":"SCHEDULED_RESEARCH_CONDITION"}
					elif _multisource_condition.is_empty():result=NetworkExperiment.capacity(built.world,int(payload.get("capacity",-1)))
					else:result=MultiSourceExperiment.capacity(built.world,int(payload.get("capacity",-1)))
				"advance","host_advance":
					var before_day: int=built.world.economy_r1.day
					var minutes: int=clampi(int(payload.get("minutes",60)),0,60)
					if _multisource_condition in AdaptiveContacts.CONDITIONS:minutes=mini(minutes,AdaptiveContacts.minutes_to_boundary(built.world.game_clock.total_minutes()))
					elif _multisource_condition in RegionalReaction.CONDITIONS:minutes=mini(minutes,RegionalReaction.minutes_to_boundary(built.world.game_clock.total_minutes()))
					result=built.simulation_step.advance_minutes(minutes)
					if result.get("success",true) and _multisource_condition in RegionalReaction.CONDITIONS+AdaptiveContacts.CONDITIONS:
						var schedule: Dictionary=AdaptiveContacts.apply_condition(built.world,_multisource_condition) if _multisource_condition in AdaptiveContacts.CONDITIONS else RegionalReaction.apply_condition(built.world,_multisource_condition)
						if not schedule.get("accepted",false):result={"success":false,"message":str(schedule)}
					if result.get("success",true) and built.world.economy_r1.day>before_day:
						_plans.review(built.world)
						var durable: Dictionary=_commit(built)
						if not durable["success"]:result={"success":false,"save_pending":true,"message":durable["message"]}
				"accept_supply_contract","submit_supply_batch","terminate_supply_contract","buy","cancel","transfer_goods","travel","set_site_status":result=LivelihoodAction.execute_current(built.world,kind,payload)
				"plan":result=_plans.edit(built.world,payload)
				"quote":
					var authority: String=_quote_authority if _external or _business_experiment else (Opening.REGIONAL_AUTHORITY if _slot>=2 else Opening.AUTHORITY)
					var context: Dictionary=OrganizationState.acting_context(built.world.player_state.player_id(),Opening.ORGANIZATION,Opening.ORGANIZATION,authority,"opening_operator")
					result=LivelihoodAction.execute_current(built.world,"post_managed_goods_quote",{"firm":Opening.FIRM,"site":payload.get("site",Opening.SITE),"good":payload.get("good","grain"),"price":payload.get("price"),"authorization_context":context})
				"sales_control":
					var authority: String=_quote_authority if _external or _business_experiment else (Opening.REGIONAL_AUTHORITY if _slot>=2 else Opening.AUTHORITY)
					var context: Dictionary=OrganizationState.acting_context(built.world.player_state.player_id(),Opening.ORGANIZATION,Opening.ORGANIZATION,authority,"opening_operator")
					result=LivelihoodAction.execute_current(built.world,"set_managed_goods_sales",{"firm":Opening.FIRM,"site":payload.get("site",Opening.SITE),"good":payload.get("good","bread"),"paused":payload.get("paused"),"authorization_context":context})
				"save","close","export":
					result=_commit(built)
					if _external and result.get("success",false):result["host_context"]=_export_host(built)
				"observe":
					_contract_id=str(payload.get("contract_id",_contract_id));_site=str(payload.get("site",_site));_quantity=clampi(int(payload.get("quantity",_quantity)),1,1000000);_offset=maxi(0,int(payload.get("offset",_offset)))
					result={"success":true}
				"switch":
					var target: int=int(payload.get("slot",_slot))
					var saved: Dictionary=_commit(built)
					result={"success":false,"message":saved["message"]}
					if saved["success"] and target in [1,2,3,4,5]:
						var candidate: WorldBuildResult=_open(target)
						if candidate.success:
							built=candidate;_slot=target;_site=Opening.SITE;_quantity=2;_offset=0;_contract_id=""
							_mutex.lock();_generation+=1;_mutex.unlock()
							_remember_slot();result={"success":true,"slot":_slot}
						else:result={"success":false,"message":candidate.error}
			if kind in ["accept_supply_contract","submit_supply_batch","terminate_supply_contract","buy","cancel","transfer_goods","travel","set_site_status","quote","sales_control","plan"]+PUBLICITY_ACTIONS:
				var durable: Dictionary=_commit(built)
				if not durable["success"]:result={"success":false,"save_pending":true,"executed_result":result,"message":durable["message"]}
		if _save_blocked and not result.get("save_pending",false):result={"success":false,"save_pending":true,"message":"内存结果等待保存；只能重试保存，不重发交易。"}
		var fatal: bool=kind in ["advance","host_advance","global_advance"] and not result.get("success",true) and not result.get("save_pending",false)
		if fatal:
			ready=false
			_mutex.lock();_generation+=1;_mutex.unlock()
		var operation_us: int=Time.get_ticks_usec()-start_us
		if kind not in ["save","close","export","observe"]:_timings["action_dispatch_excluding_save_us"]=operation_us-int(_timings.get("commit_total_us",0))
		_stage("observation")
		var view_started: int=Time.get_ticks_usec()
		var snapshot: Dictionary=_view(built) if ready else {}
		_timings["observation_us"]=Time.get_ticks_usec()-view_started
		var response: Dictionary={"timings":_timings.duplicate(true),"enqueued_us":request["enqueued_us"],"response_ready_us":Time.get_ticks_usec(),"id":request["id"],"kind":kind,"generation":_generation,"fatal":fatal,"ok":result.get("accepted",result.get("success",true)),"result":result,"view":snapshot,"operation_us":operation_us,"total_us":Time.get_ticks_usec()-start_us}
		if not _publish(response):break
		if kind=="close" and (not ready or response["ok"]):break
		if kind in ["close","switch"]:
			_mutex.lock();_closing=false;_mutex.unlock()
	_mutex.lock();_accepting=false;_mutex.unlock()
	built=null

func _commit(built: WorldBuildResult) -> Dictionary:
	if _global_experiment:
		return _save.save(built,7,_plans.state) if _business_experiment else {"success":true,"persistence":"EXPLICIT_GLOBAL_SAVE_ONLY"}
	if _network_experiment and not _trial_persistent:return {"success":true,"persistence":"DISPOSABLE_EXPERIMENT_NO_WRITE"}
	if _observer_only:return {"success":true,"persistence":"READ_ONLY_NO_WRITE"}
	if _external:
		# External durability belongs to the host. Never write a standalone slot.
		return {"success":true,"persistence":"HOST_OWNED_EXPORT_REQUIRED"}
	_save.stage_callback=_stage
	var commit_started: int=Time.get_ticks_usec()
	var result: Dictionary=_save.save(built,_slot,_plans.state)
	_save.stage_callback=Callable() # Do not retain a runtime -> save -> bound runtime cycle.
	_timings["commit_total_us"]=int(_timings.get("commit_total_us",0))+Time.get_ticks_usec()-commit_started
	for key: String in _save.timings:_timings[key]=int(_timings.get(key,0))+int(_save.timings[key])
	_save_blocked=not result["success"]
	return result

func _view(built: WorldBuildResult) -> Dictionary:
	var world: WorldState=built.world
	var person: String=world.player_state.player_id()
	var firm: Dictionary=LivelihoodAction.query_firm(world,person,Opening.FIRM)
	var own: Dictionary={}
	for key: String in ["day","cash","reserved","inventory","offers","orders","sales_orders","operations","transactions","lifecycle"]:own[key]=firm.get(key)
	for key: String in ["operations","orders","sales_orders"]:own[key]=firm.get(key,[])
	var personal: Dictionary=LivelihoodAction.query(world,person)
	var personal_available: Variant=null
	if personal.get("cash") is int and personal.get("reserved") is int:personal_available=int(personal["cash"])-int(personal["reserved"])
	var observed: Dictionary=world.economy_r1.regional_observation(person)
	var regions_by_place: Dictionary={}
	for place_id: String in ["place:paris","place:lyon","place:marseille"]:
		var place: Dictionary=world.spatial_catalog.get_place(place_id)
		var region_id: String=str(place.get("parent_region_id",""))
		if region_id.is_empty():region_id=world.population_state.unit_for_place(place_id)
		for row: Dictionary in observed.get("regions",[]):
			if row.get("region_id")==region_id:regions_by_place[place_id]=row;break
	var operations: Array=own.get("operations",[])
	if not operations.any(func(row: Dictionary)->bool:return row["site_id"]==_site):_site=Opening.SITE
	# Attach only this manager's existing-sale references to the detached own view.
	for operation: Dictionary in operations:
		for good: String in operation.get("quotations",{}):
			var listing: Dictionary=operation["quotations"][good].get("listing",{})
			listing["locked_sales"]=world.economy_r1._managed_locked_sales(person,Opening.FIRM,operation["site_id"],good)
	var management_basis: String=""
	for operation: Dictionary in operations:
		if operation.get("site_id")==_site:management_basis=str(operation.get("management_basis",""))
	var manager: String=world.economy_r1.firm_manager_at(Opening.FIRM,world.game_clock.total_minutes())
	var identity: Dictionary={"person_id":person,"personal":personal,"firm_id":Opening.FIRM,"site_id":_site,"manager_person_id":manager,"can_manage":not firm.is_empty(),"management_basis":management_basis,"management_summary":(("现任经营负责人" if manager==person else "获准查看经营")+" · "+management_basis) if not firm.is_empty() else "无当前经营权限"}
	# Existing authorized business view supplies the exact executable request.
	var business: Dictionary=world.economy_r1.business_view(person,Opening.FIRM,_site,_quantity,_offset,16)
	var transfers: Array[Dictionary]=world.economy_r1.managed_transfer_options(person,Opening.FIRM,_site)
	var travel_options: Array[Dictionary]=[]
	for destination: String in ["place:paris","place:lyon","place:marseille"]:
		travel_options.append({"place":destination,"quote":world.person_travel.quote(person,destination)})
	var opportunities: Array[Dictionary]=world.economy_r1.supply_business_view(person)
	var supply: Dictionary={}
	for c: Dictionary in opportunities:
		if c["id"]==_contract_id:supply=c
	if supply.is_empty() and not opportunities.is_empty():supply=opportunities[0];_contract_id=supply["id"]
	var contacts: Dictionary=MarketContacts.project(own,world.economy_r1.managed_network_contacts(person,Opening.FIRM),world.game_clock.total_minutes())
	var view: Dictionary={"date":world.game_clock.current_date(),"world_case":world.economy_r1.config.get("case_id",""),"observer_only":_observer_only,"market_network":MarketNetwork.project(own),"market_contacts":contacts,"network_experiment":_network_experiment,"experiment_condition":_multisource_condition,"person_id":person,"identity":identity,"external_host":_external,"clock_owner":"EXTERNAL_HOST" if _external else "STANDALONE_HOST","regional_statistics_basis":observed.get("coverage","UNKNOWN"),"market_feedback":world.economy_r1.managed_market_feedback(person,Opening.FIRM),"supply":supply,"opportunities":opportunities,"trade_review":world.economy_r1.managed_trade_review(person,Opening.FIRM),"plans":_plans.state,"save_pending":_save_blocked,"travel":world.person_travel.view(person),"travel_options":travel_options,"minute":world.game_clock.total_minutes(),"slot":_slot,"site":_site,"quantity":_quantity,"business":business,"transfers":transfers,"firm":own,"personal_cash":personal.get("cash"),"personal_reserved":personal.get("reserved"),"personal_available":personal_available,"player_place":world.person_overlay.current_place(person),"regions_by_place":regions_by_place}.duplicate(true)

	view["business_experiment"]=_business_experiment
	view["trial_persistent"]=_trial_persistent
	if _business_experiment and world.economy_state.reference_market!=null:
		view["public_reference"]=world.economy_state.reference_market.bulletin("country_fra","wheat",world.game_clock.total_minutes()/1440)
	if _global_experiment and world.economy_state.reference_market!=null:
		view["global_market"]=world.economy_state.reference_market.observe_public() if _business_experiment else world.economy_state.reference_market.observe()
		view["global_market"]["scope"]="F6_DEVELOPMENT_REFERENCE_OBSERVATION_NOT_OTHER_FIRMS_PRIVATE_ACCOUNTS"
	if _network_experiment and not _business_experiment and world.economy_r1.config.get("case_id") in [RegionalReaction.CASE,AdaptiveContacts.CASE,CommercialAdaptation.CASE,ConsumerAccess.CASE]:
		view["research_subjects"]=_research_subject_rows(world)
		view["research_subject"]=_research_subject
		view["experiment_main_capacity"]=world.economy_r1._transport.edges[MultiSourceExperiment.EDGE].capacity
		view["experiment_bypass_capacity"]=world.economy_r1._transport.edges[RegionalReaction.BYPASS].capacity
		if not _research_subject.is_empty():
			var research: Dictionary=world.economy_r1.visible_internal(_research_subject)
			view["research_only"]=true
			view["firm"]=research
			view["identity"]={"firm_id":_research_subject,"can_manage":false,"management_summary":"研究观察，不赋予玩家经营权"}
			view["business"]={}
			view["market_network"]=MarketNetwork.project(research)
			view["market_contacts"]=MarketContacts.project(research,world.economy_r1.managed_network_contacts(_research_subject,_research_subject),world.game_clock.total_minutes())
			view["trade_review"]=world.economy_r1.managed_trade_review(_research_subject,_research_subject)
	if _network_experiment and not _business_experiment and world.economy_r1.config.get("case_id")==ConsumerAccess.CASE:
		view["consumer_access"]=ConsumerProjection.project(world.economy_r1)
	return view

func _research_subject_rows(world: WorldState) -> Array[Dictionary]:
	return ConsumerAccess.subjects(world) if world.economy_r1.config.get("case_id")==ConsumerAccess.CASE else CommercialAdaptation.subjects(world) if world.economy_r1.config.get("case_id")==CommercialAdaptation.CASE else AdaptiveContacts.subjects(world) if world.economy_r1.config.get("case_id")==AdaptiveContacts.CASE else RegionalReaction.subjects(world)
