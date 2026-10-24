extends SceneTree
## Same formal checkpoint before/after query changes. No cached economic authority.
const Runtime=preload("res://merchant/merchant_runtime.gd")
const Opening=preload("res://merchant/merchant_opening.gd")
var completed: bool=false
var started: int=Time.get_ticks_msec()
func _initialize() -> void:call_deferred("run")
func _process(_delta: float) -> bool:
	if not completed and Time.get_ticks_msec()-started>60000:push_error("Regional query check incomplete");quit(1)
	return false
func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	var decoded: Dictionary=FormalWorldPersistenceDocument.decode(JSON.parse_string(FileAccess.get_file_as_string(args[1])))
	assert(decoded.success,decoded.error)
	var b: WorldBuildResult=FormalPersistence.new().restore_candidate(decoded.snapshot)
	assert(b.success,b.error)
	var snapshot: Dictionary=b.persistence.snapshot()
	var e: EconomyR1Slice=b.world.economy_r1
	var person: String=b.world.player_state.player_id()
	var runtime: RefCounted=Runtime.new();runtime._slot=0;runtime._network_experiment=true
	var contact_us: Array=[];var view_us: Array=[];var contacts: Array=[];var view: Dictionary={}
	for repeat: int in 5:
		var begin: int=Time.get_ticks_usec();contacts=e.managed_network_contacts(person,Opening.FIRM);contact_us.append(Time.get_ticks_usec()-begin)
		begin=Time.get_ticks_usec();view=runtime._view(b);view_us.append(Time.get_ticks_usec()-begin)
	assert(e.managed_network_contacts("person:not_a_manager",Opening.FIRM).is_empty())
	assert(e.business_view("person:not_a_manager",Opening.FIRM,Opening.SITE).is_empty())
	var consumer_access: Dictionary=preload("res://merchant/consumer_access_projection.gd").project(e)
	var households: Dictionary={}
	for actor: String in e._actor_ids():
		if e._actors[actor].control=="automatic":households[actor]=e.visible_internal(actor)
	assert(snapshot==b.persistence.snapshot(),"Query altered formal state")
	var output: Dictionary={"contacts_us":contact_us,"view_us":view_us,"contacts":contacts,"view":view,"typed_value":Marshalls.raw_to_base64(var_to_bytes({"contacts":contacts,"view":view})),"formal_state_unchanged":true,"unauthorized_rejected":true,"compared_exact_to_baseline":false,"scope":"NATIVE_QUERY_MEASUREMENT_NOT_GUI"}
	var file: FileAccess=FileAccess.open(args[0],FileAccess.WRITE);file.store_string(JSON.stringify(output,"\t"));file.close()
	output["households"]=households
	output["consumer_access"]=consumer_access
	output["request_observations"]=e._request_window.duplicate(true)
	var compared: bool=false
	if args.size()>2:
		var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[2]))
		if expected.has("typed_value"):expected=bytes_to_var(Marshalls.base64_to_raw(expected.typed_value))
		assert(expected.contacts==contacts,"Contact legality/terms changed")
		assert(expected.view==view,"Value view changed")
		compared=true
	output.compared_exact_to_baseline=compared
	file=FileAccess.open(args[0],FileAccess.WRITE);file.store_string(JSON.stringify(output,"\t"));file.close()
	completed=true;print("REGIONAL_QUERY_FINISHED contacts_us=",contact_us," view_us=",view_us," exact_comparison=",compared);quit()
