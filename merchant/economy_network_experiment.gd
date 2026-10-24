extends Control
## Explicit disposable opening; MerchantRuntime remains the sole world owner.
const Runtime=preload("res://merchant/merchant_runtime.gd")
const MapScene=preload("res://merchant/economy_map_view.tscn")
var runtime: RefCounted
var map_view: Control
var choices: OptionButton
var start_button: Button
var day_button: Button
var hour_button: Button
var capacity_button: Button
var week_button: Button
var note: Label
var pending: Dictionary={}
var generation: int=0
var target_minute: int=-1
var confirmed: Dictionary={}
var capacity: int=10
var closing: bool=false
var frame_ms: Array[float]=[]
var view_updates_us: Array[int]=[]

func _ready() -> void:
	get_tree().auto_accept_quit=false
	DisplayServer.window_set_title("WWO 经济网络 · 原采购与线路容量实验")
	map_view=MapScene.instantiate();add_child(map_view);theme=map_view.theme
	map_view.offset_top=106
	map_view.refresh_requested.connect(_observe)
	map_view.back_requested.connect(_close)
	var bar:=VBoxContainer.new();bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE);bar.offset_left=12;bar.offset_right=-12;add_child(bar)
	var title:=Label.new();title.text=_description();bar.add_child(title)
	var row:=HBoxContainer.new();bar.add_child(row)
	choices=OptionButton.new()
	for title_value: String in _conditions():choices.add_item(title_value)
	row.add_child(choices)
	start_button=_button(row,"新建本次实验",_start)
	capacity_button=_button(row,"切换线路容量",_capacity)
	hour_button=_button(row,"推进1小时",func():_advance(60))
	day_button=_button(row,"推进至次日",func():_advance(1440-int(confirmed.get("minute",0))%1440))
	week_button=_button(row,"7日",func():_advance(7*1440))
	_button(row,"关闭实验",_close)
	note=Label.new();note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;bar.add_child(note)
	note.text="先选择条件，再显式新建。可关闭线路后等待采购，再恢复通行观察原自动采购与货批。"
	_controls()

func _button(parent: Node,label: String,action: Callable) -> Button:
	var button:=Button.new();button.text=label;button.pressed.connect(action);parent.add_child(button);return button

func _controls() -> void:
	var busy: bool=runtime==null or closing or not pending.is_empty() or target_minute>=0
	start_button.disabled=runtime!=null;choices.disabled=runtime!=null
	for button: Button in [day_button,hour_button,capacity_button,week_button]:button.disabled=busy

func _start() -> void:
	if runtime!=null:return
	capacity=_selected_capacity()
	runtime=Runtime.new()
	var result: Error=_start_runtime()
	if result!=OK:note.text=error_string(result);runtime=null;return
	pending={0:"init"};generation=0;confirmed={};_controls()
	note.text="正在通过原WorldBootstrap建立显式开发起点；尚未完成初始化。"

func _description() -> String:return "隔离开发世界 · 现有商号自动备货粮食6 · 原资金/StockLots/订单 · 不读写存档"
func _conditions() -> Array:return ["起点：里昂→巴黎通行","起点：里昂→巴黎关闭"]
func _selected_capacity() -> int:return 10 if choices.selected==0 else 0
func _start_runtime() -> Error:return runtime.start_network_experiment()
func _on_initialized() -> void:_submit("network_capacity",{"capacity":capacity})
func _on_response(_kind: String) -> void:pass

func _submit(kind: String,payload: Dictionary={}) -> void:
	if runtime==null or closing or not pending.is_empty():return
	var id: int=runtime.submit(kind,payload)
	if id>=0:pending[id]=kind
	_controls()

func _observe() -> void:_submit("observe")

func _capacity() -> void:
	capacity=0 if capacity>0 else 10
	_submit("network_capacity",{"capacity":capacity})

func _advance(minutes: int) -> void:
	if confirmed.is_empty() or runtime==null or not pending.is_empty():return
	target_minute=int(confirmed.minute)+minutes
	_submit("advance",{"minutes":mini(60,minutes)})

func _process(_delta: float) -> void:
	if map_view.map_base.loaded and frame_ms.size()<20000:frame_ms.append(_delta*1000.0)
	if runtime==null:return
	for response: Dictionary in runtime.poll():
		var id: int=int(response.get("id",-1))
		if not pending.has(id) or int(response.get("generation",0))<generation:continue
		var kind: String=pending[id];pending.erase(id);generation=int(response.get("generation",generation))
		if closing:continue
		if not response.get("ok",false):
			target_minute=-1;note.text="动作/推进失败："+str(response.get("result",response.get("message","")));push_error(note.text);_controls();continue
		confirmed=response.get("view",{}).duplicate(true)
		if not confirmed.is_empty():
			capacity=int(confirmed.get("experiment_main_capacity",capacity))
			confirmed["map_source"]="本次显式隔离实验；不等于F5或槽5存档。原Runtime独占世界。"
			var update_started: int=Time.get_ticks_usec()
			map_view.update_snapshot(confirmed)
			view_updates_us.append(Time.get_ticks_usec()-update_started)
			note.text="已确认 minute %s · 线路容量 %s · 观察企业粮食 %s · 订单 %s · 实际在途 %s"%[confirmed.minute,capacity,confirmed.firm.get("inventory",{}).get("grain",0),confirmed.market_network.edges.size(),map_view._goods(confirmed.market_network.known_contract_cargo_by_good)]
			if confirmed.has("experiment_bypass_capacity"):note.text+=" · 开发假设替代容量 "+str(confirmed.experiment_bypass_capacity)
			print("NETWORK_GUI_CONFIRMED ",JSON.stringify({"kind":kind,"minute":confirmed.minute,"capacity":capacity,"inventory":confirmed.firm.get("inventory",{}),"edges":confirmed.market_network.edges.size(),"cargo":confirmed.market_network.known_contract_cargo_by_good}))
		if kind=="init":_on_initialized()
		_on_response(kind)
		if target_minute>=0:
			if int(confirmed.get("minute",0))>=target_minute:target_minute=-1
			else:
				note.text+=" · 正在推进，目标 minute %s 尚未完成"%target_minute
				_submit("advance",{"minutes":mini(60,target_minute-int(confirmed.minute))})
		_controls()
	if runtime.finished():
		runtime.join_finished();runtime=null;pending.clear();closing=false;confirmed={};target_minute=-1;map_view.update_snapshot({});_controls()
		note.text="实验世界与唯一经济线程已释放；没有写入存档。"

func _close() -> void:
	target_minute=-1
	if runtime==null:get_tree().quit();return
	if closing:return
	closing=true;runtime.request_stop();_controls()

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST:
		if runtime!=null:runtime.shutdown_and_join();runtime=null
		get_tree().quit()

func _exit_tree() -> void:
	if runtime!=null:runtime.shutdown_and_join();runtime=null
	if not frame_ms.is_empty():
		frame_ms.sort();view_updates_us.sort()
		print("NETWORK_GUI_PERFORMANCE ",JSON.stringify({"frame_samples":frame_ms.size(),"frame_p95_ms":frame_ms[int(frame_ms.size()*0.95)],"frame_max_ms":frame_ms.back(),"map_update_samples":view_updates_us.size(),"map_update_p95_us":view_updates_us[int(view_updates_us.size()*0.95)] if not view_updates_us.is_empty() else null,"note":"PROCESS_DELTA_INCLUDING_INTERACTION_NOT_GPU_BENCHMARK"}))
