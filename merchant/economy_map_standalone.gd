extends Control
## One existing MerchantRuntime worker, selected persisted world, no writes.
const Runtime=preload("res://merchant/merchant_runtime.gd")
const Save=preload("res://merchant/merchant_save.gd")
const MAP_PATH: String="res://merchant/economy_map_view.tscn"
var runtime: RefCounted
var map_view: Control
var picker: VBoxContainer
var explanation: Label
var slots: OptionButton
var open_button: Button
var restore_button: Button
var pending: Dictionary={}
var generation: int=0
var closing: bool=false
var quitting: bool=false
var confirmed: Dictionary={}
var last_failure: String=""

func _ready() -> void:
	get_tree().auto_accept_quit=false
	DisplayServer.window_set_title("WWO 经济地图 · 只读隔离观察")
	var style:=Theme.new();style.default_font=preload("res://assets/fonts/map/SourceHanSerifCN-Regular.otf");style.default_font_size=16;theme=style
	var panel:=MarginContainer.new(); panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left","right","top","bottom"]:panel.add_theme_constant_override("margin_"+side,30)
	add_child(panel)
	picker=VBoxContainer.new(); picker.add_theme_constant_override("separation",16); panel.add_child(picker)
	var title:=Label.new(); title.text="经济地图 · 选择已有世界"; title.add_theme_font_size_override("font_size",24); picker.add_child(title)
	explanation=Label.new(); explanation.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; picker.add_child(explanation)
	slots=OptionButton.new(); slots.custom_minimum_size.y=44; picker.add_child(slots)
	open_button=_button("只读打开所选存档",_open_selected)
	restore_button=_button("显式复制交接 day16 检查点到隔离槽5（不覆盖）",_restore_checkpoint)
	_button("退出",func():_leave(true))
	_reload_picker()
	print("ECONOMY_MAP_USER_DIR ",OS.get_user_data_dir())

func _ensure_map() -> void:
	if map_view!=null:return
	map_view=(load(MAP_PATH) as PackedScene).instantiate();add_child(map_view)
	map_view.refresh_requested.connect(_observe)
	map_view.back_requested.connect(_leave.bind(false))

func _button(title: String, action: Callable) -> Button:
	var button:=Button.new(); button.text=title; button.custom_minimum_size.y=44; picker.add_child(button); button.pressed.connect(action); return button

func _reload_picker(note: String="") -> void:
	slots.clear()
	for slot: int in range(1,6):
		if Save.has_slot(slot):
			slots.add_item("槽%d%s · %s"%[slot,"（区域反馈实验，显式选择）" if slot==5 else "",Save.path(slot)])
			slots.set_item_metadata(slots.item_count-1,slot)
	open_button.disabled=slots.item_count==0
	restore_button.disabled=Save.has_slot(5) or not _isolated() or not FileAccess.file_exists(_checkpoint())
	explanation.text="实际用户目录：%s\n只读恢复原正式存档；观察、旋转、点击、刷新和关闭均不推进、不保存。\n加载成功后显示商号、开局配置和正式时间。\n没有存档时不会自动开局。可在测试副本的原商号入口经营，再返回本场景。\n%s\n%s"%[OS.get_user_data_dir(),"当前没有合法存档。" if slots.item_count==0 else "选择槽位后按只读打开；槽5不会自动选入。",note]

func _isolated() -> bool:
	return str(ProjectSettings.get_setting("application/config/custom_user_dir_name","")).begins_with("wwo_economy_map_test_")

func _checkpoint() -> String:
	return ProjectSettings.globalize_path("res://").path_join("../original_checkpoint/GUI_day16_final_slot5.json").simplify_path()

func _restore_checkpoint() -> void:
	if runtime!=null or not _isolated() or Save.has_slot(5):return
	# Envelope decoding checks slot, clock and plans. The worker still performs
	# the full formal candidate restore before publishing economic observations.
	var row: Dictionary=Save._read(_checkpoint(),5)
	if not str(row.get("error","")).is_empty():_reload_picker("检查点未复制："+str(row.error)); return
	var target: String=ProjectSettings.globalize_path(Save.path(5))
	var error: Error=DirAccess.copy_absolute(_checkpoint(),target)
	_reload_picker("检查点复制结果：%s\n来源 %s\n目标 %s\n封套槽5、minute %s；尚未加载世界。"%[error_string(error),_checkpoint(),target,str(row.get("core",{}).get("total_minutes","未知"))])

func _open_selected() -> void:
	if runtime!=null or slots.item_count==0:return
	var slot: int=int(slots.get_item_metadata(slots.selected))
	runtime=Runtime.new(); var error: Error=runtime.start_observer(slot)
	if error!=OK:runtime=null; _reload_picker("未打开："+error_string(error)); return
	pending={0:"init"}; generation=0; closing=false; confirmed={}
	last_failure=""
	open_button.disabled=true; restore_button.disabled=true; slots.disabled=true
	explanation.text="正在正式恢复槽%d。\n%s\n校验结束前不展示经济数据。"%[slot,OS.get_user_data_dir()]

func _observe() -> void:
	if runtime==null or closing or not pending.is_empty():return
	var id: int=runtime.submit("observe")
	if id>=0:pending[id]="observe"

func _process(_delta: float) -> void:
	if runtime==null:return
	for response: Dictionary in runtime.poll():
		var id: int=int(response.get("id",-1))
		if not pending.has(id) or int(response.get("generation",0))<generation:continue
		pending.erase(id); generation=int(response.get("generation",generation))
		if closing:continue
		if not response.get("ok",false):
			last_failure="恢复/观察失败，未重建、未保存："+str(response.get("message",response.get("result",{})))
			explanation.text=last_failure
			push_error(explanation.text)
			if map_view!=null:map_view.hide()
			picker.get_parent().show(); _leave(false); continue
		var value: Dictionary=response.get("view",{})
		if value.is_empty():continue
		confirmed=value.duplicate(true); value=value.duplicate(true)
		value["map_source"]="只读原世界 · 配置 %s · %s · %s"%[value.get("world_case","未知"),Save.path(int(value.slot)),OS.get_user_data_dir()]
		_ensure_map();map_view.update_snapshot(value); picker.get_parent().hide(); map_view.show()
		print("ECONOMY_MAP_CONFIRMED ",JSON.stringify({"id":id,"generation":generation,"slot":value.slot,"minute":value.minute,"nodes":value.market_network.nodes.size(),"cargo":value.market_network.cargo.size(),"read_only":true}))
	if runtime.finished():
		runtime.join_finished(); runtime=null; pending.clear(); closing=false
		if quitting:get_tree().quit(); return
		if map_view!=null:map_view.queue_free();map_view=null
		picker.get_parent().show(); slots.disabled=false
		_reload_picker(last_failure+"\n已释放唯一工作线程；再次打开会从磁盘恢复。")

func _leave(quit_application: bool) -> void:
	quitting=quitting or quit_application
	if runtime==null:
		if quitting:get_tree().quit()
		return
	if closing:return
	closing=true
	var id: int=runtime.submit("close")
	if id>=0:pending[id]="close"
	else:runtime.request_stop()

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST:_leave(true)

func _exit_tree() -> void:
	if runtime!=null:runtime.shutdown_and_join(); runtime=null
