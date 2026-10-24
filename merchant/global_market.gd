extends Control
## Same MerchantRuntime worker and Formal world; batching never advances a UI clock.
const Runtime=preload("res://merchant/merchant_runtime.gd")
var runtime: RefCounted
var map_view: Control
var pending: Dictionary={}
var remaining: int=0
var note: Label
var actions: Array[Button]=[]
var scenario: OptionButton
var closed: bool=false

func _ready() -> void:
	get_tree().auto_accept_quit=false
	DisplayServer.window_set_title("WWO 第23代 · 全球大宗市场 · 开发情景")
	map_view=Control.new();map_view.set_script(preload("res://merchant/global_market_map.gd"));add_child(map_view)
	theme=map_view.theme
	map_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);map_view.offset_top=110
	map_view.back_requested.connect(_close);map_view.refresh_requested.connect(func():_submit("observe"))
	var panel:=VBoxContainer.new();panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE);panel.offset_left=12;panel.offset_right=-12;add_child(panel)
	var row:=HBoxContainer.new();panel.add_child(row)
	scenario=OptionButton.new();scenario.add_item("同起点基线");scenario.add_item("减产 / 煤需求 / 运输冲击");scenario.select(1);row.add_child(scenario)
	_button(row,"打开全球研究世界",_start)
	_button(row,"推进1日",func():_advance(1));_button(row,"推进30日",func():_advance(30));_button(row,"推进90日",func():_advance(90))
	var second:=HBoxContainer.new();panel.add_child(second)
	_button(second,"保存全球研究档",func():_submit("global_save"));_button(second,"关闭",_close)
	_button(second,"经营原商号",func():_submit("global_enter_business"))
	note=Label.new();note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;panel.add_child(note)
	note.text="从第22代第24日试玩副本续接；已有全球研究档则恢复原档。原试玩档不覆盖。选择情景仅在首次打开时生效。"
	_controls()

func _button(parent: Node,title: String,action: Callable) -> void:
	var b:=Button.new();b.text=title;parent.add_child(b);b.pressed.connect(action);actions.append(b)

func _start() -> void:
	if runtime!=null:return
	runtime=Runtime.new();var err: Error=runtime.start_global("baseline" if scenario.selected==0 else "shocks")
	if err!=OK:note.text=error_string(err);runtime=null;return
	pending[0]="init";scenario.disabled=true;note.text="正在恢复原Formal世界；尚未推进时间。";_controls()

func _submit(kind: String,payload: Dictionary={}) -> void:
	if runtime==null or not pending.is_empty():return
	var id: int=runtime.submit(kind,payload)
	if id>=0:pending[id]=kind
	_controls()

func _advance(days: int) -> void:
	if runtime==null or not pending.is_empty():return
	remaining=days;_next()

func _next() -> void:
	var batch: int=mini(7,remaining);remaining-=batch
	_submit("global_advance",{"days":batch})

func _process(_delta: float) -> void:
	if runtime==null:return
	for response: Dictionary in runtime.poll():
		pending.erase(response.get("id",-1))
		if not response.get("ok",false):remaining=0;note.text="未完成："+str(response.get("result",response.get("message","")));_controls();continue
		map_view.update_snapshot(response.get("view",{}))
		note.text="正式minute %d · 本次计算 %.2fs · 剩余推进%d日 · %s"%[int(response.get("view",{}).get("minute",0)),float(response.get("operation_us",0))/1000000.0,remaining,"已通过原Formal校验保存" if response.get("kind")=="global_save" else "正在按原世界推进，尚未完成" if remaining>0 else "行情暂停，等待下一项操作"]
		print("GLOBAL_MARKET_GUI ",JSON.stringify({"kind":response.get("kind"),"minute":response.get("view",{}).get("minute"),"remaining":remaining}))
		if response.get("kind")=="global_enter_business":
			var merchant: Node=load("res://merchant/main.tscn").instantiate()
			if merchant.adopt_runtime(runtime,response.view)!=OK:merchant.free();note.text="接手失败；仍保留当前Runtime";continue
			runtime=null;get_parent().add_child(merchant)
			if get_tree().current_scene==self:get_tree().current_scene=merchant
			queue_free();return
		if remaining>0:_next()
		_controls()

func _controls() -> void:
	for b: Button in actions:b.disabled=runtime==null or not pending.is_empty()
	if not actions.is_empty():actions[0].disabled=runtime!=null
	if actions.size()>5:actions[5].disabled=false

func _close() -> void:
	if closed:return
	closed=true
	if runtime!=null:runtime.shutdown_and_join();runtime=null
	get_tree().quit()

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST:_close()

func _exit_tree() -> void:
	if runtime!=null:runtime.shutdown_and_join();runtime=null
