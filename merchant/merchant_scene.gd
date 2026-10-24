extends Node2D
signal host_continuation_ready(context: Dictionary)
signal host_checkpoint_ready(context: Dictionary)
signal host_continuation_failed(message: String)
const Opening=preload("res://merchant/merchant_opening.gd")
const SupplyProjection=preload("res://merchant/merchant_supply_projection.gd")
const DecisionProjection=preload("res://merchant/merchant_decision_projection.gd")
const Runtime=preload("res://merchant/merchant_runtime.gd")
const EconomyMapScene=preload("res://merchant/economy_map_view.tscn")
var economy_map_layer: CanvasLayer
var economy_map_view: Control
var economy_map_entry: Button
const GOODS={"all":"全部商品","grain":"粮食","beans":"豆类","fiber":"纤维","oil":"油料","bread":"面包","clothes":"衣服","soap":"肥皂","flour":"面粉"}
const PLACES={"place:paris":"巴黎","place:lyon":"里昂","place:marseille":"马赛"}
var returned_host_context: Dictionary={}
var external_host_context: Dictionary={}
var runtime: RefCounted
var continued_view: Dictionary={}
var publicity_index: int=0
var snapshot: Dictionary={}
var view: Dictionary={}
var current_minute: int=0
var display_generation: int=0
var world_ready: bool=false
var busy: bool=true
var stepping: bool=false
var running: bool=false
var speed: int=1
var pulse: float=0.0
var queued_minutes: int=0
var requested_day_start: int=-1
var wait_stage: String="loading"
var wait_started_us: int=0
var wait_last_second: int=-1
var stage_samples: Array[Dictionary]=[]
var pending_requests: Dictionary={0:{"kind":"init","started_us":0,"stage":"loading"}}
var active_progress_id: int=0
var host_return_emitted: bool=false
var startup_failed: bool=false
var close_requested: bool=false
var close_ack: bool=false
var save_requested: bool=false
var resume_trial: bool=false
var selected_place: String="place:paris"
var selected_site: String=Opening.SITE
var selected_good: String="all"
var selected_tab: int=0
var city_home: bool=true
var facilities: Array[Button]=[]
var home_goal: Button
var home_next: Button
var home_records: Button
var home_progress: ProgressBar
var contract_user_selected: bool=false
var home_delegate: Button
var technical_toggle: Button
var show_technical: bool=false
var route_hint: Label
var home_hint: Label
var back_city: Button
var section_select: OptionButton
var page_offset: int=0
var offer_key: String=""
var order_key: String=""
var pending_preview: bool=false
var confirm_kind: String=""
var confirm_payload: Dictionary={}
var display_offers: Array[Dictionary]=[]
var display_orders: Array[Dictionary]=[]
var news: Array[String]=[]
var observed_payment_events: Dictionary={}
var priority_payment: Dictionary={}
var critical_notice: String=""
var payment_notice: Button
var observed_orders: Dictionary={}
var observed_prices: Dictionary={}
var observed_supply: Dictionary={}
var observed_opportunities: Dictionary={}
var selected_contract: String=""
var updating: bool=false
var message: String="正在恢复上次经营世界…"
var main_poll_max_us: int=0
var main_refresh_max_us: int=0
var frame_max_us: int=0
var previous_frame_us: int=0
var worker_max_us: int=0
var worker_by_kind: Dictionary={}
var slowest_step_ms: int=0
var font: Font=preload("res://assets/fonts/map/HomeSans.otf")
var header: Label
var notice: Label
var detail: RichTextLabel
var map_buttons: Array[Button]=[]
var tabs: Array[Button]=[]
var buttons: Array[Button]=[]
var site_select: OptionButton
var good_select: OptionButton
var row_select: OptionButton
var quantity: SpinBox
var price: SpinBox
var batch: SpinBox
var cash_floor: SpinBox
var primary: Button
var secondary: Button
var previous: Button
var next_page: Button
var city_state: Dictionary={}
var layout_size: Vector2=Vector2(960,600)
var quantity_minus: Button
var quantity_plus: Button
var sales_control: Button
var confirm_expand: Button
var confirm_summary: String=""
var confirm_rules: String=""
var confirm_expanded: bool=false
var display_opportunities: Array[Dictionary]=[]
var confirm_detail: RichTextLabel
var identity_button: Button
var guide_text: RichTextLabel
var frame_histogram: Dictionary={}
var frame_count: int=0
var peak_memory_bytes: int=0
var guide: AcceptDialog
var guide_opened: bool=false
var feedback_entry: Button
var cargo_buttons: Array[Button]=[]
var dialog: ConfirmationDialog

func _ready() -> void:
	DisplayServer.window_set_title("经济经营 · "+str(ProjectSettings.get_setting("application/config/build_id","")))
	font.fallbacks=[preload("res://assets/fonts/map/SourceHanSerifCN-Regular.otf")]
	get_tree().auto_accept_quit=false
	get_viewport().gui_embed_subwindows=true
	RenderingServer.set_default_clear_color(Color("0b111b"))
	header=_label(Vector2(20,8),Vector2(730,68),17)
	identity_button=_button("人物与入门",Vector2(760,12),Vector2(180,56),_show_guide)
	guide=AcceptDialog.new();guide.title="我的商贸生活";guide.dialog_autowrap=true;guide.min_size=Vector2i(790,390);guide.add_theme_font_override("font",font);guide.add_theme_font_size_override("font_size",19);add_child(guide)
	guide_text=RichTextLabel.new();guide_text.add_theme_font_override("normal_font",font);guide_text.add_theme_font_size_override("normal_font_size",18);guide_text.custom_minimum_size=Vector2(750,380);guide_text.scroll_active=true;guide.add_child(guide_text)
	feedback_entry=guide.add_button("区域反馈实验（独立存档）",false,"feedback")
	feedback_entry.custom_minimum_size=Vector2(250,52)
	guide.custom_action.connect(_guide_action)
	guide.get_ok_button().text="明白了，自己选择";guide.get_ok_button().custom_minimum_size=Vector2(220,52)
	var places: Array[String]=["place:lyon","place:paris","place:marseille"]
	for i: int in range(3):
		var b: Button=_button(PLACES[places[i]],Vector2(65+i*310,93),Vector2(210,55),_select_place.bind(places[i]));map_buttons.append(b)
	route_hint=_label(Vector2(24,163),Vector2(912,34),14);route_hint.text="贸易路线示意 · 蓝点：本人所在地 · 金点：已有在途合同（不代表实时位置）"
	back_city=_button("← 城市",Vector2(20,204),Vector2(150,42),_return_city)
	section_select=_option(Vector2(180,204),Vector2(330,42))
	for title: String in ["市场 · 采购","仓库 · 资产与调拨","货站 · 合同运输","商号 · 消息账款","商号 · 补货委托","商号 · 行程营业","买方 · 机会与履约"]:section_select.add_item(title)
	section_select.item_selected.connect(_set_tab)
	home_goal=_button("正在读取经营目标…",Vector2(20,138),Vector2(920,76),_open_supply)
	home_goal.add_theme_font_size_override("font_size",17)
	home_progress=ProgressBar.new();home_progress.show_percentage=false;home_progress.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(home_progress)
	var track:=StyleBoxFlat.new();track.bg_color=Color("24384c");track.set_corner_radius_all(2);home_progress.add_theme_stylebox_override("background",track)
	var fill:=StyleBoxFlat.new();fill.bg_color=Color("65cfdb");fill.set_corner_radius_all(2);home_progress.add_theme_stylebox_override("fill",fill)
	home_delegate=_button("补货委托  ↗",Vector2.ZERO,Vector2(150,48),_set_tab.bind(4))
	home_records=_button("经营记录与目标",Vector2(730,138),Vector2(210,76),_set_tab.bind(3))
	technical_toggle=_button("展开技术详情",Vector2(720,140),Vector2(220,48),_toggle_technical)
	for i: int in range(5):
		var box: Rect2=_facility_rect(i)
		var b: Button=_button("",box.position,box.size,_enter_facility.bind(i))
		b.tooltip_text=["查看已知采购机会","查看自有库存与调拨","查看真实合同运输","查看经营账款与委托","查看供货与验收"][i]
		for state: String in ["normal","hover","pressed","focus","disabled"]:
			var style:=StyleBoxFlat.new();style.bg_color=Color(1,1,1,0.12) if state in ["hover","pressed"] else Color(0,0,0,0)
			if state=="focus":style.border_color=Color("e5cc86");style.set_border_width_all(2)
			b.add_theme_stylebox_override(state,style)
		facilities.append(b)
	home_next=_button("查看下一步",Vector2(20,443),Vector2(920,42),_next_action)
	home_hint=_label(Vector2(25,216),Vector2(910,26),14)
	site_select=_option(Vector2(20,255),Vector2(240,42));site_select.item_selected.connect(_site_changed)
	good_select=_option(Vector2(270,255),Vector2(150,42))
	for key: String in GOODS:good_select.add_item(GOODS[key]);good_select.set_item_metadata(good_select.item_count-1,key)
	good_select.item_selected.connect(_good_changed)
	quantity=SpinBox.new();quantity.position=Vector2(430,255);quantity.size=Vector2(120,42);quantity.min_value=1;quantity.max_value=999;quantity.value=2;quantity.prefix="数量 ";quantity.add_theme_font_override("font",font);add_child(quantity);quantity.value_changed.connect(_quantity_changed)
	price=SpinBox.new();price.position=Vector2(560,255);price.size=Vector2(130,42);price.min_value=1;price.max_value=120;price.value=5;price.prefix="单价 ";price.add_theme_font_override("font",font);add_child(price)
	batch=SpinBox.new();batch.position=Vector2(20,305);batch.size=Vector2(235,42);batch.min_value=1;batch.max_value=999;batch.value=3;batch.prefix="单日批量 ";batch.add_theme_font_override("font",font);add_child(batch)
	cash_floor=SpinBox.new();cash_floor.position=Vector2(270,305);cash_floor.size=Vector2(300,42);cash_floor.min_value=0;cash_floor.max_value=99999;cash_floor.value=20;cash_floor.prefix="至少留现 ";cash_floor.add_theme_font_override("font",font);add_child(cash_floor)
	primary=_button("采购预览",Vector2(700,255),Vector2(240,42),_primary)
	row_select=_option(Vector2(20,305),Vector2(680,42));row_select.item_selected.connect(_row_changed)
	secondary=_button("刷新报价",Vector2(710,305),Vector2(230,42),_secondary)
	previous=_button("上一页",Vector2(20,352),Vector2(100,36),_page.bind(-16))
	next_page=_button("下一页",Vector2(130,352),Vector2(100,36),_page.bind(16))
	detail=RichTextLabel.new();detail.position=Vector2(240,352);detail.size=Vector2(700,135);detail.add_theme_font_override("normal_font",font);detail.add_theme_font_size_override("normal_font_size",16);detail.scroll_active=true;add_child(detail)
	notice=_label(Vector2(20,490),Vector2(920,42),15)
	payment_notice=_button("",Vector2(20,490),Vector2(920,42),_open_payment_receipt)
	payment_notice.add_theme_font_size_override("font_size",14)
	payment_notice.alignment=HORIZONTAL_ALIGNMENT_LEFT
	payment_notice.clip_text=true;payment_notice.visible=false
	var titles: Array[String]=["开始","速度 1×","推进一天","保存","切换场景"]
	for i: int in range(5):buttons.append(_button(titles[i],Vector2(20+i*186,540),Vector2(178,44),_time_button.bind(i)))
	dialog=ConfirmationDialog.new();dialog.title="核对经营操作";dialog.dialog_autowrap=true;dialog.min_size=Vector2i(780,320);dialog.add_theme_font_override("font",font);dialog.add_theme_font_size_override("font_size",19);dialog.confirmed.connect(_confirm);dialog.canceled.connect(_cancel_preview);add_child(dialog)
	for b: Button in [dialog.get_ok_button(),dialog.get_cancel_button()]:
		b.custom_minimum_size=Vector2(150,50);b.add_theme_font_override("font",font);b.add_theme_font_size_override("font_size",20)
	dialog.get_ok_button().text="确认提交";dialog.get_cancel_button().text="取消返回"
	confirm_expand=dialog.add_button("展开规则与原ID",false,"details");confirm_expand.custom_minimum_size=Vector2(210,50);dialog.custom_action.connect(_confirm_details_action)
	confirm_detail=RichTextLabel.new();confirm_detail.scroll_active=true;confirm_detail.add_theme_font_override("normal_font",font);confirm_detail.add_theme_font_size_override("normal_font_size",19);dialog.add_child(confirm_detail)
	quantity_minus=_button("−1",Vector2(550,204),Vector2(70,48),_adjust_quantity.bind(-1))
	quantity_plus=_button("＋1",Vector2(630,204),Vector2(70,48),_adjust_quantity.bind(1))
	sales_control=_button("暂停该商品新销售",Vector2(20,312),Vector2(210,48),_preview_sales_control)
	sales_control.add_theme_font_size_override("font_size",15)
	for i: int in range(4):
		var cargo: Button=_button("",Vector2(20,312+i*38),Vector2(210,36),_inspect_cargo.bind(i));cargo.add_theme_font_size_override("font_size",14);cargo_buttons.append(cargo)
	_apply_home_theme()
	economy_map_entry=_button("经济地图",Vector2.ZERO,Vector2(130,48),_open_economy_map)
	economy_map_layer=CanvasLayer.new();economy_map_layer.layer=10;add_child(economy_map_layer)
	economy_map_layer.hide()
	get_viewport().size_changed.connect(_fit);_fit();_refresh();_start.call_deferred()

func _open_economy_map() -> void:
	if not world_ready or close_requested or save_requested:return
	if economy_map_view==null:
		if snapshot.has("global_market"):
			economy_map_view=Control.new();economy_map_view.set_script(preload("res://merchant/global_market_map.gd"));economy_map_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		else:economy_map_view=EconomyMapScene.instantiate()
		economy_map_view.business_enabled=true;economy_map_layer.add_child(economy_map_view)
		economy_map_view.back_requested.connect(_close_economy_map)
		economy_map_view.refresh_requested.connect(_observe)
		economy_map_view.business_requested.connect(_map_business)
	_pause();_update_economy_map();economy_map_layer.show()

func _close_economy_map() -> void:
	economy_map_layer.hide();_refresh()

func _update_economy_map() -> void:
	var value: Dictionary=snapshot.duplicate(true)
	var clock_note: String=" · 宿主拥有时钟" if snapshot.get("external_host",false) else " · 当前小时仍处理中" if stepping else " · 时间暂停"
	value["map_source"]="同一商号会话 · 配置 %s · 唯一 Runtime 已确认快照%s"%[snapshot.get("world_case","未知"),clock_note]
	economy_map_view.update_snapshot(value)

func _map_business(place_id: String, site_id: String) -> void:
	selected_place=place_id;selected_site=site_id;selected_tab=1;city_home=false
	_close_economy_map();_observe()

func _label(pos: Vector2,size: Vector2,points: int) -> Label:
	var n:=Label.new();n.position=pos;n.size=size;n.add_theme_font_override("font",font);n.add_theme_font_size_override("font_size",points);add_child(n);return n
func _button(title: String,pos: Vector2,size: Vector2,action: Callable) -> Button:
	var n:=Button.new();n.text=title;n.position=pos;n.size=size;n.add_theme_font_override("font",font);n.add_theme_font_size_override("font_size",18);n.pressed.connect(action);add_child(n);return n
func _option(pos: Vector2,size: Vector2) -> OptionButton:
	var n:=OptionButton.new();n.position=pos;n.size=size;n.add_theme_font_override("font",font);n.add_theme_font_size_override("font_size",17);n.fit_to_longest_item=false;add_child(n);return n
func _adjust_quantity(amount: int) -> void:
	if busy or dialog.visible:return
	quantity.value=clampf(quantity.value+amount,quantity.min_value,quantity.max_value)
func _fit() -> void:
	# Reflow into expanded logical canvas, rather than scaling a fixed 960x600 page.
	var available: Vector2=get_viewport_rect().size
	layout_size=Vector2(maxf(960,available.x),maxf(600,available.y))
	scale=Vector2.ONE;position=Vector2.ZERO
	if header!=null:_layout_controls()
	queue_redraw()
func _layout_controls() -> void:
	if dialog==null:return
	var w: float=layout_size.x
	var h: float=layout_size.y
	if economy_map_entry!=null:economy_map_entry.position=Vector2(w-350,14);economy_map_entry.disabled=not world_ready or close_requested or save_requested
	header.size.x=w-240;identity_button.position.x=w-210;notice.position.y=h-110;notice.size=Vector2(w-40,48)
	home_goal.size.x=w-270;home_records.position.x=w-240;home_records.size=Vector2(220,76);technical_toggle.position.x=w-240;home_next.position.y=h-163;home_next.size=Vector2(w-40,52)
	home_hint.size.x=w-50
	for i: int in range(buttons.size()):
		buttons[i].position=Vector2(20+i*(w-40)/5,h-54)
		buttons[i].size=Vector2((w-40)/5-8,48)
	for control: Control in [site_select,good_select,quantity,price,primary,row_select,secondary,batch,cash_floor,back_city,section_select]:control.size.y=48
	if city_home:_layout_home()
	if not city_home:
		header.position=Vector2(20,8);header.size=Vector2(w-240,64);header.add_theme_font_size_override("font_size",16)
		route_hint.visible=false
		for i: int in range(map_buttons.size()):
			map_buttons[i].position=Vector2(20+i*(w-40)/3,80);map_buttons[i].size=Vector2((w-40)/3-12,48)
		for control: Control in [back_city,section_select,quantity_minus,quantity_plus]:control.position.y=140
		for control: Control in [site_select,good_select,quantity,price,primary]:control.position.y=200
		for control: Control in [row_select,secondary,batch,cash_floor]:control.position.y=254
	primary.position.x=w-260;secondary.position.x=w-250
	row_select.size.x=w-280
	previous.position=Vector2(20,312);previous.size=Vector2(100,48)
	next_page.position=Vector2(130,312);next_page.size=Vector2(100,48)
	detail.position=Vector2(20,312) if selected_tab==6 else Vector2(240,312)
	detail.size=Vector2(w-detail.position.x-20,h-detail.position.y-115)
	quantity_minus.visible=not city_home and selected_tab in [0,1,4,6]
	quantity_plus.visible=quantity_minus.visible
	quantity_minus.disabled=busy or dialog.visible;quantity_plus.disabled=quantity_minus.disabled
func _toggle_technical() -> void:
	show_technical=not show_technical;_refresh()
func _start() -> void:
	if runtime!=null and not continued_view.is_empty():
		_receive({"id":0,"kind":"init","ok":true,"message":"沿用原世界和线程。可继续本次不保存试玩，或明确另存为独立试玩档。","view":continued_view})
		continued_view={};return
	runtime=Runtime.new();var error: Error=runtime.start_trial() if resume_trial else runtime.start_external(external_host_context) if not external_host_context.is_empty() else runtime.start()
	if error!=OK:startup_failed=true;pending_requests.clear();message="线程启动失败："+error_string(error);busy=false;_refresh()
func _process(delta: float) -> void:
	var now: int=Time.get_ticks_usec()
	if previous_frame_us>0:frame_max_us=maxi(frame_max_us,now-previous_frame_us)
	if previous_frame_us>0:
		var ms: int=mini(10000,int((now-previous_frame_us)/1000))
		frame_histogram[ms]=int(frame_histogram.get(ms,0))+1;frame_count+=1
	peak_memory_bytes=maxi(peak_memory_bytes,int(Performance.get_monitor(Performance.MEMORY_STATIC)))
	previous_frame_us=now
	if runtime==null:return
	var begin: int=Time.get_ticks_usec();var responses: Array[Dictionary]=runtime.poll();main_poll_max_us=maxi(main_poll_max_us,Time.get_ticks_usec()-begin)
	for response: Dictionary in responses:_receive(response)
	for event: Dictionary in runtime.poll_progress():
		var event_id: int=int(event["id"])
		if pending_requests.has(event_id):
			pending_requests[event_id]["stage"]=str(event["stage"])
			if int(pending_requests[event_id]["started_us"])==0:pending_requests[event_id]["started_us"]=int(event["at_us"])
			active_progress_id=event_id;wait_last_second=-1
	_sync_wait()
	if busy or stepping:
		var second: int=int((now-wait_started_us)/1000000) if wait_started_us>0 else 0
		if second!=wait_last_second:
			wait_last_second=second
			notice.text=_wait_text(second)
	if close_ack and runtime.finished():
		runtime.join_finished();print("MERCHANT_SAFE_EXIT minute=",current_minute," slot=",snapshot.get("slot"))
		_finish_exit()
		return
	if busy or stepping or not world_ready or close_requested or save_requested or dialog.visible or guide.visible:return
	if queued_minutes>0:_submit_step(mini(60,queued_minutes))
	elif running:
		pulse+=delta
		if pulse>=1.0/float(speed):pulse=0.0;_submit_step(60)
func _receive(response: Dictionary) -> void:
	var receive_started: int=Time.get_ticks_usec()
	var generation: int=int(response.get("generation",display_generation))
	if generation<display_generation:return
	display_generation=generation
	pending_requests.erase(int(response.get("id",0)))
	wait_last_second=-1
	_capture_host_result(response)
	var kind: String=response["kind"]
	if kind=="host_detached":close_ack=true;_sync_wait();return
	if response.get("fatal",false):world_ready=false;running=false;queued_minutes=0
	if not response.get("view",{}).is_empty():
		var previous_news: String=news[0] if not news.is_empty() else ""
		var previous_paid: int=int(observed_supply.get("paid",0))
		var previous_contract_id: String=str(observed_supply.get("id",""))
		snapshot=response["view"];view=snapshot["firm"];current_minute=int(snapshot["minute"]);selected_site=str(snapshot["site"])
		if kind=="switch" and response.get("ok",false):observed_orders.clear();observed_prices.clear();observed_supply.clear();observed_opportunities.clear();selected_contract="";contract_user_selected=false;news.clear();observed_payment_events.clear();priority_payment.clear();critical_notice=""
		_focus_contract()
		_record_news(kind not in ["init","switch"])
		_record_payments(kind not in ["init","switch"] or (kind=="switch" and not response.get("ok",false)))
		if kind=="advance":
			if not news.is_empty() and news[0]!=previous_news:message="经营变化："+news[0]
			var actual_paid: int=int(observed_supply.get("paid",0))
			if actual_paid>previous_paid and previous_contract_id==str(observed_supply.get("id","")):
				message="买方已实际验收；本次到账＋%d，累计%d。按时验收%s/%s。"%[actual_paid-previous_paid,actual_paid,observed_supply.get("ontime",0),snapshot.get("supply",{}).get("quantity","?")]

	worker_max_us=maxi(worker_max_us,int(response.get("total_us",0)))
	if response.has("total_us"):
		var metrics: Dictionary=worker_by_kind.get(kind,{"count":0,"total_max_us":0,"operation_max_us":0,"view_max_us":0})
		metrics["count"]+=1;metrics["total_max_us"]=maxi(metrics["total_max_us"],int(response["total_us"]));metrics["operation_max_us"]=maxi(metrics["operation_max_us"],int(response.get("operation_us",0)));metrics["view_max_us"]=maxi(metrics["view_max_us"],int(response["total_us"])-int(response.get("operation_us",0)));worker_by_kind[kind]=metrics
		if int(response["total_us"])>500000:print("MERCHANT_SLOW_RESPONSE ",JSON.stringify({"kind":kind,"minute":current_minute,"operation_us":response.get("operation_us",0),"total_us":response["total_us"]}))
	if kind=="init":world_ready=response["ok"];busy=false;message=response["message"]
	elif kind=="advance":
		stepping=false;queued_minutes=maxi(0,queued_minutes-60)
		if not response["ok"]:running=false;queued_minutes=0;message="推进停止："+str(response["result"])
	else:
		busy=false
		var result: Dictionary=response.get("result",{})
		if kind in ["save","close"]:
			save_requested=false;message=("已生成续接快照，须由外部宿主保存。" if not external_host_context.is_empty() else "已保存当前场景。") if response["ok"] else "保存失败，未退出："+str(result)
			if kind=="save" and response["ok"] and not external_host_context.is_empty():host_checkpoint_ready.emit(result.get("host_context",{}).duplicate(true))
			if kind=="close":
				returned_host_context=result.get("host_context",{}).duplicate(true)
				close_ack=response["ok"] or not world_ready;close_requested=close_ack
		elif kind=="observe":message="已更新当前已知报价；未知市场不展示。"
		elif kind=="switch":
			if response["ok"]:page_offset=0;offer_key="";order_key="";selected_good="all"
			message="已切换独立存档，时间暂停。" if response["ok"] else "未切换："+str(result)
		elif response["ok"]:
			message="受理 %s：数量 %s；%s"%[{"enable_trial_save":"另存独立试玩档","apply":"岗位申请","work":"工作预约","publish_notice":"地点公告","accept_supply_contract":"接受供货","submit_supply_batch":"分批供货","terminate_supply_contract":"终止供货","plan":"补货委托","travel":"本人行程","set_site_status":"营业变更","sales_control":"商品新销售控制","buy":"采购","quote":"报价","cancel":"撤单","transfer_goods":"调拨"}.get(kind,kind),str(result.get("quantity","按请求")),_reason(str(result.get("reason","")))]
			_add_news(message)
		else:message="未受理："+_reason(str(result.get("reason",result.get("error","未知"))))
	if response.get("result",{}).get("save_pending",false):
		_pause();message="内存操作已发生但尚未保存。请点保存重试，勿重发交易。 "+str(response["result"].get("message",""))
	if response.get("result",{}).get("save_pending",false) or (kind in ["save","close"] and not response.get("ok",false)):critical_notice=message
	elif kind in ["save","close","switch"] and response.get("ok",false):critical_notice=""
	_sync_wait()
	_refresh()
	if kind=="init" and world_ready and not guide_opened:
		guide_opened=true;_show_guide.call_deferred()
	if kind=="observe" and pending_preview:pending_preview=false;_show_trade_preview()
	var measurement: Dictionary={"kind":kind,"minute":current_minute,"timings":response.get("timings",{}).duplicate(true),"ui_receive_refresh_us":Time.get_ticks_usec()-receive_started}
	if response.has("response_ready_us"):
		measurement["response_transfer_us"]=receive_started-int(response["response_ready_us"])
		measurement["enqueue_to_ui_us"]=Time.get_ticks_usec()-int(response["enqueued_us"])
	stage_samples.append(measurement)
	if stage_samples.size()>512:stage_samples.pop_front()
	print("MERCHANT_STAGE_TIMING ",JSON.stringify(measurement))
func _send(kind: String,payload: Dictionary={}) -> void:
	if runtime==null or kind.is_empty() or (busy and kind not in ["save","close"]):return
	var request_id: int=runtime.submit(kind,payload)
	busy=request_id>=0
	if busy:_track_request(request_id,kind)
	message="请求处理中，地图仍可查看。" if busy else "未入队，请稍后重试。"
	if not busy:save_requested=false;close_requested=false;pending_preview=false
	_refresh()
func _pause() -> void:
	running=false;queued_minutes=0;pulse=0.0
	if stepping:message="暂停已请求：本小时处理完成后停止；不会撤回已结算时间。"
	requested_day_start=-1
func _observe() -> void:
	if not world_ready or busy:return
	_send("observe",{"site":selected_site,"quantity":int(quantity.value),"offset":page_offset,"contract_id":selected_contract})
func _select_place(place: String) -> void:
	selected_place=place;offer_key=""
	city_home=true
	_refresh()
func _set_tab(index: int) -> void:
	if index==2 and selected_tab!=2:order_key=""
	selected_tab=index;city_home=false;_refresh()
func _site_changed(index: int) -> void:
	if updating:return
	selected_site=str(site_select.get_item_metadata(index));page_offset=0;offer_key="";_pause();_observe()
func _good_changed(index: int) -> void:
	if updating:return
	selected_good=str(good_select.get_item_metadata(index));offer_key="";_refresh()
func _quantity_changed(_value: float) -> void:
	if updating:return
	# Quantity is checked again by the worker when requesting the preview.
	_refresh()
func _row_changed(index: int) -> void:
	if updating:return
	if selected_tab==0 and index<display_offers.size():offer_key=_offer_key(display_offers[index])
	elif selected_tab==2 and index<display_orders.size():order_key=str(display_orders[index]["id"])
	elif selected_tab==3:publicity_index=index
	elif selected_tab==6 and index<display_opportunities.size():
		contract_user_selected=true;selected_contract=str(display_opportunities[index]["id"]);_pause();_observe();return
	_refresh()
func _page(amount: int) -> void:
	if busy:return
	page_offset=maxi(0,page_offset+amount);offer_key="";_pause();_observe()
func _primary() -> void:
	if busy or dialog.visible or not world_ready:return
	_pause()
	if selected_tab==0:pending_preview=true;_observe()
	elif selected_tab==1:
		var good: String="grain" if selected_good=="all" else selected_good
		var op: Dictionary=_operation()
		if not op.get("quotations",{}).has(good):message="本地点没有该商品销售授权。";_refresh();return
		confirm_kind="quote";confirm_payload={"site":selected_site,"good":good,"price":int(price.value)}
		_show_confirm("在%s给%s报价 %d。\n次日生效，同地点商品每天最多一次；原合同锁价不变，调价不自动恢复新销售。\n当前在库 %s，承诺 %s。售出不保证，不能预设利润。"%[_site_name(selected_site),GOODS[good],int(price.value),op.get("inventory",{}).get(good,0),op.get("committed_inventory",{}).get(good,0)])
	elif selected_tab==2:
		var order: Dictionary=_selected_order()
		if order.is_empty() or order.get("buyer")!=Opening.FIRM or int(order.get("pending",0))<=0:message="该合同没有可撤的未发货采购。";_refresh();return
		confirm_kind="cancel";confirm_payload={"order_id":order["id"]};_show_confirm("仅撤销所选%s合同尚未发出的 %s 件。\n在途与到期付款义务保留，预留释放由正式系统处理。"%[GOODS.get(order.get("good"),"商品"),order["pending"]])
	elif selected_tab==3:
		var actions: Array[Dictionary]=_publicity_actions()
		if actions.is_empty():message="本站没有可用公告渠道。";_refresh();return
		var action: Dictionary=actions[mini(publicity_index,actions.size()-1)]
		if not action.can_execute:message=_publicity_reason(str(action.reason));_refresh();return
		confirm_kind=action.kind;confirm_payload=action.payload.duplicate(true)
		if action.kind in ["apply","work"]:
			_show_confirm("%s\n申请和工作分别由原领域裁决。预约不等于已完成工作。次日实际在岗才形成工作记录和工资责任；工资到期后由商号付款。"%action.label,str(action.payload));return
		_show_confirm("%s\n%s。\n消息延迟%s日，最多接触%s个原渠道接收者。公告不预留买方资金，不保证成交。"%[action.label,_publicity_reason(str(action.reason)),action.get("delay_days","按原消息"),action.get("recipient_limit","按原渠道")],str(action.payload))
	elif selected_tab==4:
		confirm_kind="plan";confirm_payload=_plan_payload(true)
		_show_confirm("委托自动补货 %s → %s：\n自由库存＋待入库目标%d，每日最多申请%d，含运费每件不超过%d，至少留现%d。\n从下一日开始，只选已知有效报价；保护当期到期未预留责任与所设留现，不重复扣正式预留；逐笔交正式系统批准。\n这会持续产生真实采购承诺，直到你暂停；不保证售出或利润。"%[GOODS[confirm_payload["good"]],_site_name(selected_site),confirm_payload["target"],confirm_payload["batch"],confirm_payload["ceiling"],confirm_payload["floor"]])
	elif selected_tab==5:
		var trip: Dictionary=_travel_quote()
		if trip.is_empty():message="当前没有可用客运报价："+str(trip);_refresh();return
		confirm_kind="travel";confirm_payload={"destination_place_id":selected_place}
		_show_confirm("本人前往%s，个人账户支付票款%s，预计最少%s分钟。\n受座位/线路/工作预约约束，可能途中等待；没有取消旅程接口。\n商号仍可按已有权限经营；旅行不解锁商号未知货源。"%[PLACES[selected_place],trip.get("fare","?"),trip.get("minutes","?")])
	elif selected_tab==6:
		var c: Dictionary=_selected_buyer_opportunity()
		if c.is_empty():message="当前城市没有可接受的已知供货机会；可查看真实销售记录或等待。";_refresh();return
		if c["status"]=="RECRUITING":
			confirm_kind="accept_supply_contract";confirm_payload={"contract_id":c["id"],"price":c["price"]}
			_show_confirm("%s采购%s%s，截止第%d天00:00；接受不会延期。\n固定单价%s，总货款%s由买方真实账户全额预留，尚未付给你。\n交付地点%s；在途不计履约，接受后承担数量与期限责任。\n无现金罚金；未完成记逾期，旧批次继续运输付款。\n%s"%[_site_name(c["buyer_site"]),c["quantity"],GOODS.get(c["good"],c["good"]),int(c["deadline"])/1440+1,c["price"],int(c["quantity"])*int(c["price"]),_site_name(c["buyer_site"]),_opportunity_preview(c)])
		elif c["status"] in ["ACCEPTED","PARTIAL"]:
			confirm_kind="submit_supply_batch";confirm_payload={"contract_id":c["id"],"quantity":int(quantity.value)}
			_show_confirm("提交%s单位所选合同商品，目的地为合同指定买方仓。\n当前自由库存%s，尚可分配%s；运力不足可部分受理。\n仍走真实本地货运，到货验收后才按锁价%s付款。\n截止第%d天00:00。\n%s\n%s"%[int(quantity.value),c["free_stock"],c["unallocated"],c["price"],int(c["deadline"])/1440+1,SupplyProjection.project(c,view,current_minute).get("new_batch_hint","未知"),SupplyProjection.project(c,view,current_minute).get("risk","")])
		else:message="合同已结束；原在途批次继续，详情保留。";_refresh()
	else:_observe()
func _plan_payload(enabled: bool) -> Dictionary:
	return {"site":selected_site,"good":"grain" if selected_good=="all" else selected_good,"target":int(quantity.value),"batch":int(batch.value),"ceiling":int(price.value),"floor":int(cash_floor.value),"enabled":enabled}
func _travel_quote() -> Dictionary:
	for row: Dictionary in snapshot.get("travel_options",[]):
		if row["place"]==selected_place:return row["quote"]
	return {}
func _show_trade_preview() -> void:
	var offer: Dictionary=_selected_offer()
	if offer.is_empty():message="本页该地点没有已知报价。可切商品、地点或翻页。";_refresh();return
	confirm_kind="buy" if offer.get("can_order",false) else ""
	confirm_payload=offer.get("request",{}).duplicate(true) if not confirm_kind.is_empty() else {}
	var text: String=DecisionProjection.purchase_summary_text(offer,_site_name(selected_site),_site_name(str(offer.get("seller_site",""))))
	var rules: String=DecisionProjection.purchase_text(offer,_site_name(selected_site),_site_name(str(offer.get("seller_site",""))))
	rules+="\n\n原业务引用\n来源站点：%s\n目的站点：%s\n路线：%s\n正式申请：%s"%[offer.get("seller_site","未知"),selected_site,offer.get("route_id","未知"),str(offer.get("request",{}))]
	if confirm_kind.is_empty():text="当前不能提交："+_reason(str(offer.get("order_reason",offer.get("reason"))))+"。可取消后减少数量或等待。\n\n"+text
	_show_confirm(text,rules)

func _secondary() -> void:
	if busy:return
	_pause()
	if selected_tab==6:
		var c: Dictionary=_selected_buyer_opportunity()
		if c.get("status") not in ["ACCEPTED","PARTIAL"]:
			var sales: Array[Dictionary]=_local_sales_orders()
			if not sales.is_empty():_set_tab(2);order_key=str(sales[0]["id"]);_refresh()
			else:_observe()
			return
		confirm_kind="terminate_supply_contract";confirm_payload={"contract_id":c["id"]}
		_show_confirm("明确终止尚未分配的供货责任并释放对应担保，记录未完成量。已经成立的货运/货款责任继续履行。没有约定现金罚金，不会凭空扣款。")
		return
	if selected_tab==4:
		var key: String=selected_site+"|"+("grain" if selected_good=="all" else selected_good)
		var old: Dictionary=snapshot.get("plans",{}).get("plans",{}).get(key,{})
		if old.is_empty():message="该仓库/商品尚未设委托。";_refresh();return
		confirm_kind="plan";confirm_payload={}
		for field: String in ["site","good","target","batch","ceiling","floor"]:confirm_payload[field]=old[field]
		confirm_payload["enabled"]=false;_show_confirm("暂停该商品未来补货。已成立采购/运输/付款照常履行。")
		return
	if selected_tab==5:
		var flags: Dictionary=_operation().get("site_status",{})
		confirm_kind="set_site_status";confirm_payload={"firm":Opening.FIRM,"site_id":selected_site,"enabled":flags.get("enabled",true),"production_enabled":flags.get("production_enabled",false),"accepting_business":not flags.get("accepting_business",true)}
		_show_confirm("%s %s 的新采购和新销售，按正式经营边界生效。\n旧合同继续运输付款，仓间调拨仍须真实库存和运费。"%["恢复" if confirm_payload["accepting_business"] else "暂停",_site_name(selected_site)])
		return
	if selected_tab!=1:_observe();return
	var transfers: Array=snapshot.get("transfers",[])
	if transfers.is_empty():message="旧场景仅一个仓库，没有可用调拨路径。";_refresh();return
	var route: Dictionary=transfers[0];var good: String="grain" if selected_good=="all" else selected_good
	confirm_kind="transfer_goods";confirm_payload={"firm":Opening.FIRM,"from_site":route["from_site"],"to_site":route["to_site"],"good":good,"quantity":int(quantity.value),"path_id":route["path_id"],"denomination":route["denomination"],"max_freight":route["freight_per_unit"]}
	_show_confirm("调拨自有 %s %d 件：%s → %s\n路径 %s；运费每件 %s，申请上限 %s。\n当前自由库存 %s。没有商品买卖收入；运力/库存不足可能部分受理。"%[GOODS.get(good,good),int(quantity.value),_site_name(route["from_site"]),_site_name(route["to_site"]),"正式货运路线",route["freight_per_unit"],int(quantity.value)*int(route["freight_per_unit"]),_operation().get("free_inventory",{}).get(good,0)])
func _show_confirm(text: String, rules: String="") -> void:
	message="仅打开预览，尚未提交；请核对金额、期限与责任。"
	dialog.get_ok_button().disabled=confirm_kind.is_empty()
	confirm_summary=text;confirm_rules=rules;confirm_expanded=false
	confirm_expand.visible=not rules.is_empty();confirm_expand.text="展开规则与原ID"
	dialog.dialog_text="";confirm_detail.text=text;confirm_detail.scroll_to_line(0)
	dialog.popup_centered(Vector2i(mini(900,int(layout_size.x)-40),mini(480,int(layout_size.y)-40)))
	confirm_detail.position=Vector2(20,20);confirm_detail.size=Vector2(dialog.size.x-40,dialog.size.y-95)
	_refresh()
func _confirm_details_action(action: StringName) -> void:
	if action!="details" or confirm_rules.is_empty():return
	confirm_expanded=not confirm_expanded
	confirm_expand.text="收起规则与原ID" if confirm_expanded else "展开规则与原ID"
	confirm_detail.text=confirm_summary+("\n\n完整成本、责任与原业务引用\n"+confirm_rules if confirm_expanded else "")
	confirm_detail.scroll_to_line(0)
func _selected_listing() -> Dictionary:
	var good: String="grain" if selected_good=="all" else selected_good
	return _operation().get("quotations",{}).get(good,{}).get("listing",{})
func _preview_sales_control() -> void:
	if busy or dialog.visible or not world_ready or snapshot.get("save_pending",false):return
	var listing: Dictionary=_selected_listing()
	if not listing.get("sales_control_supported",false):message="尚未取得该站点商品的新销售控制资料；请刷新查询。";_refresh();return
	_pause()
	var good: String="grain" if selected_good=="all" else selected_good
	var paused: bool=not listing.get("sales_paused",false)
	confirm_kind="sales_control";confirm_payload={"site":selected_site,"good":good,"paused":paused}
	var summary: String="%s · %s\n%s该商品的新销售。\n正式受理时按原行动采用序生效。其他商品、采购、运输继续。\n旧订单、锁价与已接受供货合同仍履行；实际库存不清零。\n%s"%[_site_name(selected_site),GOODS.get(good,good),"暂停" if paused else "恢复","未来调价不自动恢复销售。" if paused else "恢复须重检当前有效报价、授权和营业；不续期、不保证成交。"]
	_show_confirm(summary,DecisionProjection.listing_text(listing)+"\n站点：%s\n商品：%s\n原控制边界：%s / 采用序：%s\n关联报价：%s"%[selected_site,good,DecisionProjection.day_text(listing.get("sales_control_effective_minute")),_known(listing.get("sales_control_sequence")),listing.get("sales_control_quote_id","未知")])

func _confirm() -> void:
	if busy or confirm_kind.is_empty():return
	var kind: String=confirm_kind
	var payload: Dictionary=confirm_payload.duplicate(true)
	confirm_kind="";confirm_payload={}
	_send(kind,payload)
func _cancel_preview() -> void:
	confirm_kind="";confirm_payload={};message="已取消预览，未提交操作。";_refresh()
func _time_button(index: int) -> void:
	if not world_ready or close_requested or save_requested:return
	if snapshot.get("business_experiment",false):
		if index==4:
			message="请关闭后从F6继续独立试玩档；本会话不切换F5档案。";_refresh();return
		if index==3 and not snapshot.get("trial_persistent",false):
			_pause();confirm_kind="enable_trial_save";confirm_payload={}
			_show_confirm("将当前同一世界保存为候选独立试玩档。之后经营行动及每日边界沿原原子写入和正式恢复校验保存。\n研究检查点、F5槽1–5不覆盖；已有试玩档时拒绝另存，请从F6继续原档。研发观察权限不会保存或恢复。\n档案：regional_trial/merchant_host_trial_6.json");return
	if index==0:
		if running or queued_minutes>0 or stepping:_pause()
		else:running=true;pulse=0.0
		_refresh();return
	if index==1:speed=4 if speed==1 else 1;_refresh();return
	if busy:return
	match index:
		2:_pause();queued_minutes=1440;requested_day_start=current_minute
		3:_pause();save_requested=true;_send("save")
		4:
			_pause();confirm_kind="switch";var target: int=4 if int(snapshot.get("slot",1))==5 else int(snapshot.get("slot",1))%4+1;confirm_payload={"slot":target}
			_show_confirm("先保存，再继续%s；只有无该槽时才新开。普通槽1–4与实验槽5分别保存，旧存档不迁移。\n第4槽继承第3槽有限真实开局资金、商品和运输条件；新增有限采购授权与公告信息延迟，不增发货币或商品。80粮大合同仍截止第11天00:00。\n可选现货贸易、等待或接单；不保证成交、完成或盈利。"%["原商号（槽1）","区域商贸（槽2）","巴黎限期供货（槽3）","自主商贸（槽4）"][target-1])
	_refresh()
func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_GO_BACK_REQUEST:
		if dialog!=null and dialog.visible:dialog.hide();_cancel_preview();return
		if guide!=null and guide.visible:guide.hide();return
		if not city_home:_return_city();return
	if what not in [NOTIFICATION_APPLICATION_PAUSED,NOTIFICATION_WM_CLOSE_REQUEST,NOTIFICATION_WM_GO_BACK_REQUEST]:return
	_pause()
	if runtime==null or startup_failed:
		if what!=NOTIFICATION_APPLICATION_PAUSED:_finish_exit()
		return
	if runtime.finished():
		for response: Dictionary in runtime.poll():_receive(response)
		runtime.join_finished()
		_finish_exit()
		return
	if close_requested:return
	close_requested=what!=NOTIFICATION_APPLICATION_PAUSED;save_requested=true
	_send("close" if close_requested else "save")
func _exit_tree() -> void:
	_write_performance()
	if runtime!=null and runtime.has_method("shutdown_and_join"):
		runtime.shutdown_and_join()
		for response: Dictionary in runtime.poll():_capture_host_result(response)
		_emit_host_return()
func _offer_key(offer: Dictionary) -> String:
	return str(offer.get("seller_site"))+"|"+str(offer.get("good"))+"|"+str(offer.get("route_id"))
func _selected_offer() -> Dictionary:
	for offer: Dictionary in display_offers:
		if _offer_key(offer)==offer_key:return offer
	return display_offers[0] if not display_offers.is_empty() else {}
func _selected_order() -> Dictionary:
	for order: Dictionary in display_orders:
		if str(order["id"])==order_key:return order
	return display_orders[0] if not display_orders.is_empty() else {}
func _operation() -> Dictionary:
	for op: Dictionary in view.get("operations",[]):
		if op["site_id"]==selected_site:return op
	return {}
func _site_name(site: String) -> String:
	return {Opening.LYON_SITE:"里昂中转仓",Opening.SITE:"巴黎销售仓","site:city_competitor:paris":"巴黎竞争商号","site:regional_upstream:lyon":"里昂上游企业","site:regional_food:paris":"巴黎食品厂","site:regional_food:lyon":"里昂食品分店","site:regional_textile:lyon":"里昂纺织企业","site:regional_textile:marseille":"马赛纺织分店","site:regional_household:marseille":"马赛日用品厂","site:regional_textile:paris":"巴黎纺织分店","":"个人收货"}.get(site,"已知经营地点")
func _currency(code: String) -> String:
	return "记账单位" if code=="denomination:formal_simulation_minor_v1" else code
func _money(values: Dictionary) -> String:
	var rows: Array[String]=[]
	for key: String in values:rows.append(str(values[key])+_currency(key))
	return "、".join(rows) if not rows.is_empty() else "0"
func _reason(code: String) -> String:
	return {"SITE_NOTICE_PUBLISHED_NOT_A_SALE":"公告已受理，送达和成交分别确认","NO_VACANCY":"岗位当前没有空缺","ALREADY_EMPLOYED":"本人已有岗位","WORK_PERIOD_ALREADY_CLAIMED":"该期工作已经预约","UNKNOWN_JOB":"本人尚未收到岗位信息","SUPPLY_ACCEPTED_FUNDED":"供货合同已接受，买方货款已预留", "SUPPLY_BATCH_DISPATCH_ACCEPTED":"本批现货已安排，待实际到货付款", "SUPPLY_ENDED":"供货合同已结束", "SUPPLY_TERMINATED_EXISTING_BATCHES_RETAINED":"未来责任已终止，旧运输继续", "PLAN_SAVED":"补货委托已保存","GOODS_NEW_SALES_PAUSED":"该站点商品已暂停新销售","GOODS_NEW_SALES_RESUMED":"该站点商品已恢复新销售","NO_MANAGED_GOODS_SALES_AUTHORITY":"当前报价或商品经营授权不满足，未变更销售状态","GOODS_QUOTE_EXPIRED":"当前报价已过期，须先取得有效报价","TRAVEL_STARTED":"客运行程已出发","OPERATING_CHANGE_QUEUED":"营业变更已排队，次日生效","NO_UNCOMMITTED_STOCK":"没有可自由出售的库存","NO_KNOWN_ROUTE":"没有已知可用路线","INSUFFICIENT_AVAILABLE_CASH":"可用经营资金不足","QUANTITY_EXCEEDS_CURRENT_OFFER":"申请量超过当前报价数量","ACCEPTED":"已受理","OFFER":"有效报价","FUTURE_GOODS_QUOTE_PUBLISHED":"报价次日生效","EXPIRED_QUOTE":"报价已过期，请刷新后重新确认","GOODS_QUOTE_ALREADY_POSTED_TODAY":"今日已报价或自动续报，明日再调价","NO_MANAGED_GOODS_QUOTE_AUTHORITY":"报价授权范围/有效期/价格上限不满足","NO_TRANSFER_STOCK_CASH_OR_CAPACITY":"调拨库存、资金或运力不足","NOT_READY":"未到约定发运日","CUMULATIVE_BUDGET_OR_WINDOW":"累计预算或窗口不允许新承诺"}.get(code,code)

func _add_news(text: String) -> void:
	news.push_front("第%d天 %02d:%02d  %s"%[current_minute/1440+1,(current_minute/60)%24,current_minute%60,text])
	if news.size()>80:news.resize(80)
func _record_news(announce: bool=true) -> void:
	for c: Dictionary in snapshot.get("opportunities",[]):
		var id: String=c["id"]
		var fact: Array=[c["status"],c.get("paid",0),c.get("ontime",0),c.get("free_stock",0)]
		if announce and not observed_opportunities.has(id):_add_news("商业机会到达：%s采购%s%s，截止第%d天；可选择暂不接受。"%[_site_name(c["buyer_site"]),c["quantity"],GOODS.get(c["good"],c["good"]),int(c["deadline"])/1440+1])
		elif announce and observed_opportunities.get(id)!=fact:_add_news("%s：%s；验收%s，实际收款%s，可交现货%s"%[_site_name(c["buyer_site"]),_supply_status(c["status"]),c.get("ontime",0),c.get("paid",0),c.get("free_stock",0)])
		observed_opportunities[id]=fact
	var contract: Dictionary=snapshot.get("supply",{})
	if not contract.is_empty():
		var fact: Dictionary={"id":contract.get("id",""),"status":contract.get("status"),"paid":contract.get("paid",0),"ontime":contract.get("ontime",0)}
		if announce and not observed_supply.is_empty() and fact.get("id")==observed_supply.get("id") and fact!=observed_supply:
			_add_news("城市供货：%s，已验收%s，实际到账%s"%[_supply_status(str(fact["status"])),fact["ontime"],fact["paid"]])
		observed_supply=fact
	for order: Dictionary in view.get("orders",[])+view.get("sales_orders",[]):
		var id: String=str(order["id"])
		var state: Dictionary={"pending":order.get("pending",0),"transit":order.get("transit",0),"delivered":order.get("delivered",0),"cancelled":order.get("cancelled",0)}
		if observed_orders.has(id) and observed_orders[id]!=state:
			var arrived: int=int(state["delivered"])-int(observed_orders[id].get("delivered",0))
			if arrived>0 and order.get("buyer")==Opening.FIRM:
				_add_news("到仓：%s %s＋%d，本单累计交付%s。"%[_site_name(str(order.get("buyer_site",""))),GOODS.get(order.get("good"),order.get("good")),arrived,state["delivered"]])
			else:
				_add_news("%s %s：待发%s / 在途%s / 交付%s / 撤销%s"%["所选业务",GOODS.get(order.get("good"),order.get("good")),state["pending"],state["transit"],state["delivered"],state["cancelled"]])
		elif not observed_orders.has(id) and not snapshot.is_empty() and world_ready and announce:
			_add_news("新%s合同：%s · %s × %s，锁定单价%s"%["销售" if order.get("seller")==Opening.FIRM else "采购/调拨",_site_name(str(order.get("seller_site",""))),GOODS.get(order.get("good"),order.get("good")),order.get("quantity"),order.get("price")])
		observed_orders[id]=state
	for op: Dictionary in view.get("operations",[]):
		for offer: Dictionary in op.get("offers",[]):
			var key: String=str(op["site_id"])+_offer_key(offer)
			var current: Array=[offer.get("price"),offer.get("freight_per_unit"),offer.get("reason"),offer.get("quantity")]
			if observed_prices.has(key) and observed_prices[key]!=current:_add_news("已知供应更新：%s %s，单价%s/运费%s，%s，可供%s（原因未必是竞争）"%[_site_name(str(offer.get("seller_site"))),GOODS.get(offer.get("good"),offer.get("good")),current[0],current[1],_reason(str(current[2])),current[3]])
			observed_prices[key]=current
func _refresh() -> void:
	var begin: int=Time.get_ticks_usec();updating=true
	if header==null:return
	if economy_map_view!=null and economy_map_layer.visible:_update_economy_map()
	var slot: int=int(snapshot.get("slot",1))
	header.text="第%d天 %02d:%02d · %s · 本人%s · 个人可用%s\n浏览%s（仅看资料） · 全商号可用%s / 预留%s（回款归商号）"%[current_minute/1440+1,(current_minute/60)%24,current_minute%60,"运行%d×"%speed if running else "推进中" if queued_minutes>0 else "暂停",_person_location(),_known(snapshot.get("personal_available")),PLACES[selected_place],int(view.get("cash",0))-int(view.get("reserved",0)),view.get("reserved",0)]
	if snapshot.get("business_experiment",false):header.text=header.text.replace("（仅看资料）","（独立试玩档）" if snapshot.get("trial_persistent",false) else "（试玩未保存）")
	for i: int in range(map_buttons.size()):
		var place: String=["place:lyon","place:paris","place:marseille"][i]
		map_buttons[i].text=("● " if selected_place==place else "")+PLACES[place]
		map_buttons[i].disabled=not world_ready
	for i: int in range(tabs.size()):tabs[i].modulate=Color("e7c887") if selected_tab==i else Color.WHITE
	site_select.clear()
	for op: Dictionary in view.get("operations",[]):
		site_select.add_item(_site_name(op["site_id"]));var index: int=site_select.item_count-1;site_select.set_item_metadata(index,op["site_id"])
		if op["site_id"]==selected_site:site_select.select(index)
	for i: int in range(good_select.item_count):
		if good_select.get_item_metadata(i)==selected_good:good_select.select(i)
	site_select.disabled=busy or not world_ready;good_select.disabled=not world_ready
	quantity.editable=not busy;price.editable=not busy;price.max_value=99999 if selected_tab==4 else 120 if slot>=2 else 12
	price.visible=selected_tab in [1,4];quantity.visible=selected_tab in [0,1,4,6];good_select.visible=selected_tab in [0,1,3,4]
	quantity.prefix="目标 " if selected_tab==4 else "数量 ";price.prefix="到岸上限 " if selected_tab==4 else "单价 "
	batch.visible=selected_tab==4;cash_floor.visible=selected_tab==4;row_select.visible=selected_tab!=4
	batch.editable=not busy;cash_floor.editable=not busy
	row_select.clear();display_offers.clear();display_orders.clear();display_opportunities.clear()
	var text: String=""
	var business: Dictionary=snapshot.get("business",{})
	if selected_tab==0:
		for offer: Dictionary in business.get("offers",[]):
			if offer.get("from_place_id")!=selected_place or (selected_good!="all" and offer.get("good")!=selected_good):continue
			display_offers.append(offer)
			row_select.add_item("%s · %s · 货%s+运%s · 可供%s"%[GOODS.get(offer.get("good"),offer.get("good")),_site_name(str(offer.get("seller_site"))),_known(offer.get("price")),_known(offer.get("freight_per_unit")),offer.get("quantity",0)])
		var offer: Dictionary=_selected_offer()
		if not offer.is_empty():
			offer_key=_offer_key(offer);row_select.select(display_offers.find(offer))
			text="已知供应商：%s\n路径 %s → %s；%s\n报价状态：%s。申请%d件，若库存或可用资金不足可减小数量；预览后确认。\n当前显示总候选第%d–%d / %d条，再按地图和商品筛选。"%[_site_name(str(offer.get("seller_site"))),PLACES.get(offer.get("from_place_id"),"?"),PLACES.get(offer.get("to_place_id"),"?"),"本地配送" if offer.get("from_place_id")==offer.get("to_place_id") else "城际货运",(_reason(str(offer.get("order_reason",offer.get("reason")))) if int(quantity.value)==int(snapshot.get("quantity",-1)) else "数量已改，预览时重新核验库存与资金"),int(quantity.value),page_offset+1,mini(page_offset+16,int(business.get("offer_total",0))),business.get("offer_total",0)]
			text+="\n到仓下限%s（非保证）；可到货站核对已有货批，再决定采购或等待。"%DecisionProjection.arrival_day_text(offer.get("earliest_arrival_day"))
		else:text="本页没有符合所选地点/商品的已知报价。\n可切换地图、商品、收货仓库或翻页。\n不把未知供应商、无货报价或不可达路线伪装成可交易。"
		primary.text="采购预览";secondary.text="刷新已知报价"
	elif selected_tab==1:
		var op: Dictionary=_operation();var good: String="grain" if selected_good=="all" else selected_good
		var lines: Array[String]=[]
		for key: String in op.get("inventory",{}):
			if key not in GOODS and int(op["inventory"][key])==0:continue
			if selected_good!="all" and key!=selected_good:continue
			lines.append("%s 在库%s / 自由%s / 承诺%s / 待入%s"%[GOODS.get(key,key),op["inventory"][key],op.get("free_inventory",{}).get(key,0),op.get("committed_inventory",{}).get(key,0),op.get("incoming",{}).get(key,0)])
		var quotation: Dictionary=op.get("quotations",{}).get(good,{})
		text="%s · 实际存货地点 %s\n%s\n%s\n授权：%s。\n单商品新销售控制见左侧；旧合同与库存承诺继续。"%[_site_name(selected_site),PLACES.get(op.get("stock_place_id"),"?"),"\n".join(lines),DecisionProjection.listing_text(quotation.get("listing",{})),_management_label()]
		row_select.add_item("报价商品："+GOODS.get(good,good)+"；调拨目的地："+("另一商号仓" if slot>=2 else "无"))
		primary.text="报价预览";secondary.text="调拨至另一仓"
	elif selected_tab==2:
		var sorted_orders: Array=view.get("orders",[])+view.get("sales_orders",[])
		sorted_orders.sort_custom(_order_priority)
		for order: Dictionary in sorted_orders:
			if display_orders.any(func(row: Dictionary)->bool:return row["id"]==order["id"]):continue
			display_orders.append(order)
			row_select.add_item("%s %s %s · 待%s/途%s/到%s"%[("当前" if int(order.get("pending",0))+int(order.get("transit",0))>0 else "历史")+"第%d笔"%(display_orders.size()),"售" if order.get("seller")==Opening.FIRM and order.get("kind")=="SALE" else "调" if order.get("kind")=="TRANSFER" else "购",GOODS.get(order.get("good"),order.get("good")),order.get("pending",0),order.get("transit",0),order.get("delivered",0)])
		var order: Dictionary=_selected_order()
		if not order.is_empty():
			order_key=str(order["id"]);row_select.select(display_orders.find(order))
			text="货站 · 全商号责任（含跨城）\n"+_freight_summary()+"\n%s → %s\n锁定货款%s / 运费%s；本订单买方预留%s\n已交付货款%s / 运费%s；待发原因：%s\n"%[_site_name(str(order.get("seller_site"))),_site_name(str(order.get("buyer_site"))),order.get("locked_goods_amount",0),order.get("locked_freight_amount",0),order.get("reserved_amount",0),order.get("paid_goods_amount",0),order.get("paid_freight_amount",0),_reason(str(order.get("pending_waiting_reason","")))]
			text+=DecisionProjection.order_timing_text(order,_order_supply_contract(order),current_minute)+"\n\n"
			text+=DecisionProjection.order_receipts_text(str(order["id"]),snapshot.get("trade_review",{}))
		else:text="尚无商号合同。采购、销售、调拨都使用同一履约系统。"
		primary.text="撤销未发货";secondary.text="刷新履约"
	elif selected_tab==4:
		var key: String=selected_site+"|"+("grain" if selected_good=="all" else selected_good)
		var plan: Dictionary=snapshot.get("plans",{}).get("plans",{}).get(key,{})
		text="当前委托：%s\n%s\n此委托仅自动补货；暂停补货不影响新销售状态；销售开放时NPC仍可能买走自由库存。\n决策只选已知报价，按含运费价格排序，每计划每日最多一笔。库存口径扣销售承诺并计入待入库。\n编辑上方目标/到岸单价，第二行每日批量/留存现金，确认才生效。"%["未设定" if plan.is_empty() else "开启" if plan["enabled"] else "暂停",("目标%s / 每日批量%s / 到岸上限%s / 留现%s\n下次复核第%s日；%s"%[plan["target"],plan["batch"],plan["ceiling"],plan["floor"],int(plan["next_day"])+1,plan["status"]]) if not plan.is_empty() else "尚未开立。所有委托默认关闭。"]
		primary.text="确认补货委托";secondary.text="暂停该商品委托"
	elif selected_tab==5:
		var trip: Dictionary=_travel_quote()
		row_select.add_item("目的地："+PLACES[selected_place]+" · 票款由人物个人账户支付")
		var journey: Dictionary=snapshot.get("travel",{})
		var journey_text: String="暂无行程" if journey.is_empty() else "%s → %s · %s · 尚余%s分钟"%[PLACES.get(journey.get("origin"),journey.get("origin","?")),PLACES.get(journey.get("destination"),journey.get("destination","?")),{"TRAVELLING":"途中","ARRIVED":"已到达","BLOCKED":"等待通行"}.get(journey.get("status"),journey.get("status","?")),journey.get("remaining_minutes","?")]
		text="个人资金%s · 本人行程：%s\n所选目的地：%s\n当前仓库新采购及新销售：%s；点击右侧请求次日暂停/恢复，旧订单继续履约。\n经营待生效：%s"%[_known(snapshot.get("personal_available")),journey_text,"无可用客运报价" if trip.is_empty() else "%s · 票款%s · 最少%s分钟"%[PLACES[selected_place],trip["fare"],trip["minutes"]],"接受" if _operation().get("site_status",{}).get("accepting_business",true) else "暂停","；".join(_pending_changes())]
		primary.text="前往地图所选地";secondary.text="暂停 / 恢复新业务"
	elif selected_tab==6:
		var c: Dictionary=_selected_buyer_opportunity()
		for option: Dictionary in _local_opportunities():
			display_opportunities.append(option)
			row_select.add_item("%s · %s × %s · %s"%[_site_name(option["buyer_site"]),GOODS.get(option["good"],option["good"]),option["quantity"],_supply_status(option["status"])])
			if option["id"]==c.get("id"):row_select.select(row_select.item_count-1)
		if c.is_empty():text="%s · 目前无已知可接受的供货机会。\n%s\n真实销售记录可从右侧查看；未接受机会不会创建供货责任。"%[PLACES[selected_place],_buyer_sales_text()]
		elif not c.has("accept_action") and c.get("status")!="RECRUITING":
			text="%s · %s\n这项机会当前不能接受，未为你创建供货责任。\n可选其他已知机会、查看现货市场或等待新消息。"%[_site_name(c["buyer_site"]),_supply_status(c["status"])]
		elif not c.has("accept_action"):
			text="%s · %s\n%s × %s，单价%s / 总货款%s（未到账）\n交至%s；截止第%d天00:00。\n%s\n可暂不接受。点接受先核对完整资金、运费与责任。"%[_site_name(c["buyer_site"]),_supply_status(c["status"]),GOODS.get(c["good"],c["good"]),c["quantity"],c["price"],int(c["quantity"])*int(c["price"]),_site_name(c["buyer_site"]),int(c["deadline"])/1440+1,SupplyProjection.project(c,view,current_minute).get("short_risk","")]
		else:
			var left: int=maxi(0,int(c["deadline"])-current_minute)
			text="买方%s · %s · %s%s，锁价%s\n收货%s；剩余%d日%d时；按时%s，迟到%s，待发/在途%s\n已收货款%s；实际可交库存%s，尚未安排%s。\n详情与批次继续保留；终止仅解除未来未安排部分，已受理运输仍执行。\n%s"%[_site_name(c["buyer_site"]),_supply_status(c["status"]),c["quantity"],GOODS.get(c["good"],c["good"]),c["price"],_site_name(c["buyer_site"]),left/1440,(left/60)%24,c["ontime"],c["late"],c["in_transit"],c["paid"],c["free_stock"],c["unallocated"],SupplyProjection.project(c,view,current_minute).get("short_risk","")]
		primary.text="接受所选合同" if c.get("status")=="RECRUITING" else "提交所选合同现货" if c.get("status") in ["ACCEPTED","PARTIAL"] else "当前无新供货操作"
		secondary.text="终止未来供货责任" if c.has("accept_action") and c.get("status") in ["ACCEPTED","PARTIAL"] else "查看真实销售与收据"
		if not c.is_empty():text+="\n\n"+_buyer_sales_text()
	else:
		var actions: Array[Dictionary]=_publicity_actions()
		for action: Dictionary in actions:row_select.add_item(str(action.label)+("" if action.can_execute else " · "+_publicity_reason(str(action.reason))))
		if not actions.is_empty():publicity_index=mini(publicity_index,actions.size()-1);row_select.select(publicity_index)
		var review: Dictionary=snapshot.get("trade_review",{})
		text="经营回顾（全商号，自本局开局）\n实际买入到仓：%s；当前仍在仓：%s\n已付货款%s / 已付运费%s / 已收货款%s\n已知交易现金差额%s；只含商品与货运，不是完整净利润，库存不是已实现亏损。\n未结采购货款%s / 未结销售货款%s；仍履行供货合同%s份。\n\n%s"%[_goods_summary(review.get("delivered_purchases",{})),_goods_summary(review.get("current_inventory",{})),_money(review.get("goods_paid",{})),_money(review.get("freight_paid",{})),_money(review.get("sales_received",{})),_money(review.get("known_trade_cash_difference",{})),review.get("unsettled_goods_purchases",0),review.get("unsettled_goods_sales",0),review.get("open_supply_contracts",[]).size(),"\n".join(news) if not news.is_empty() else "尚无新变化；订单与账本已从正式存档恢复。"]
		text+="\n\n"+_publicity_text()
		primary.text="预览所选组织行动";secondary.text="刷新账款"
	detail.position.x=20 if selected_tab==6 else 240
	detail.size.x=920 if selected_tab==6 else 700
	detail.size.y=135
	if selected_tab==6:detail.position.y=305;detail.size.y=177
	else:detail.position.y=352
	detail.text=text;notice.text=_wait_text(maxi(0,int((Time.get_ticks_usec()-wait_started_us)/1000000))) if (busy or stepping) and wait_started_us>0 else message
	technical_toggle.text="收起技术详情" if show_technical else "展开技术详情"
	primary.disabled=busy or close_requested or save_requested or not world_ready;secondary.disabled=primary.disabled
	row_select.disabled=busy or not world_ready or selected_tab not in [0,2,3,6] or row_select.item_count==0
	previous.visible=selected_tab==0;next_page.visible=selected_tab==0
	previous.disabled=busy or page_offset==0;next_page.disabled=busy or page_offset+16>=int(business.get("offer_total",0))
	buttons[0].text="暂停" if running or queued_minutes>0 or stepping else "开始";buttons[1].text="速度%d×"%speed
	for b: Button in buttons:b.disabled=busy or not world_ready or close_requested or save_requested
	buttons[3].text="另存试玩" if snapshot.get("business_experiment",false) and not snapshot.get("trial_persistent",false) else "保存"
	if snapshot.get("business_experiment",false):buttons[4].disabled=true
	buttons[0].disabled=not world_ready or close_requested or save_requested
	buttons[1].disabled=not world_ready or close_requested
	if snapshot.get("save_pending",false):
		primary.disabled=true;secondary.disabled=true
		for index: int in [0,2,4]:buttons[index].disabled=true
	if not external_host_context.is_empty():
		for index: int in [0,1,2,4]:buttons[index].disabled=true
	if not world_ready:header.text="经济经营 1.0.2候选 · 正在准备世界，请稍候…"
	_refresh_city();_layout_controls();_refresh_cargo()
	sales_control.visible=not city_home and selected_tab==1
	sales_control.disabled=busy or not world_ready or close_requested or save_requested or snapshot.get("save_pending",false) or not _selected_listing().get("sales_control_supported",false)
	sales_control.text=("恢复" if _selected_listing().get("sales_paused",false) else "暂停")+"该商品新销售"
	if city_home:
		header.text="商路  /  城市经营     第%d天 · %02d:%02d · %s"%[current_minute/1440+1,(current_minute/60)%24,current_minute%60,"运行%d×"%speed if running else "推进中" if queued_minutes>0 else "暂停"]
		home_records.visible=false;home_next.visible=false
		home_hint.text="本人在%s · 浏览%s（仅看资料）\n浏览不移动人物；管理仍依原权限。"%[_person_location(),PLACES[selected_place]]
		home_hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		if not world_ready:header.text="商路  /  "+("世界恢复失败" if startup_failed else "正在读取经营世界…")
		home_goal.text=_home_action_text()

	if world_ready and slot==5:header.text=header.text.replace("城市经营","城市经营·实验5") if city_home else "实验5 · "+header.text
	var focus: Dictionary=snapshot.get("supply",{})
	home_progress.visible=city_home and _has_actionable_contract() and focus.has("ontime") and focus.has("quantity") and int(focus.get("quantity",0))>0
	if home_progress.visible:home_progress.value=100.0*int(focus["ontime"])/int(focus["quantity"])
	home_delegate.visible=city_home
	home_delegate.disabled=not world_ready
	var enabled_plans: int=0
	for plan: Dictionary in snapshot.get("plans",{}).get("plans",{}).values():
		if plan.get("enabled",false):enabled_plans+=1
	home_delegate.text="委托 · %s启用"%enabled_plans if world_ready else "补货委托  ↗"
	_refresh_priority_notice()
	updating=false;queue_redraw();main_refresh_max_us=maxi(main_refresh_max_us,Time.get_ticks_usec()-begin)
func _pending_changes() -> Array[String]:
	var result: Array[String]=[]
	for change: Dictionary in view.get("lifecycle",{}).get("changes",[]):
		if change.get("status")=="QUEUED":result.append("第%d日边界生效：%s"%[int(change.get("boundary_minute",0))/1440+1,("恢复新业务" if change.get("payload",{}).get("accepting_business",false) else "暂停新业务")])
	if result.is_empty():result.append("无")
	return result
func _draw() -> void:
	if city_home:
		_draw_city_space();_draw_city_status();return
	draw_rect(Rect2(20,76,layout_size.x-40,58),Color("274b47"))

func _supply_status(value: String) -> String:
	return {"RECRUITING":"招募中","ACCEPTED":"已接受","PARTIAL":"部分履约","COMPLETED":"按时完成","OVERDUE":"已逾期","TERMINATED":"已终止","NEED_ALREADY_COVERED":"买方需求已满足","BUYER_FUNDS_UNAVAILABLE":"买方暂不能保证货款","PROCUREMENT_MANDATE_EXHAUSTED":"采购授权额度耗尽"}.get(value,value)

func _return_city() -> void:
	city_home=true;_refresh()
func _open_supply() -> void:
	if _has_actionable_contract():
		var place: String=_site_place(str(snapshot.get("supply",{}).get("buyer_site","")))
		if not place.is_empty():selected_place=place
	_set_tab(6 if _has_actionable_contract() else 0)
func _enter_facility(index: int) -> void:
	var target: int=[0,1,2,3,6][index]
	if index==1:
		for op: Dictionary in view.get("operations",[]):
			if op.get("stock_place_id")==selected_place:
				selected_site=str(op["site_id"])
				var goods: Array=op.get("inventory",{}).keys()
				if selected_good=="all":
					for good: String in goods:
						if int(op["inventory"][good])>0:selected_good=good;break
					if selected_good=="all" and not goods.is_empty():selected_good=str(goods[0])
				_pause();_observe();break
	_set_tab(target)

func _next_action() -> void:
	if busy or not world_ready:return
	var c: Dictionary=snapshot.get("supply",{})
	var p: Dictionary=SupplyProjection.project(c,view,current_minute)
	if not _has_actionable_contract():p["next_tab"]=0
	_set_tab(int(p.get("next_tab",0)))
	if selected_tab==6 and c.get("status") in ["ACCEPTED","PARTIAL"] and int(c.get("free_stock",0))>0 and int(c.get("unallocated",0))>0:
		quantity.value=mini(int(quantity.value),mini(int(c["free_stock"]),int(c["unallocated"])))
		_primary()
func _refresh_city() -> void:
	back_city.visible=not city_home;section_select.visible=not city_home
	route_hint.visible=not city_home
	for i: int in range(map_buttons.size()):
		map_buttons[i].position.y=80 if city_home else 93
		map_buttons[i].size.y=45 if city_home else 55
	section_select.select(selected_tab)
	for node: Control in [site_select,good_select,quantity,price,batch,cash_floor,primary,row_select,secondary,previous,next_page,detail]:
		if city_home:node.visible=false
	if not city_home:
		site_select.visible=true;primary.visible=true;secondary.visible=true;detail.visible=true
	for node: Control in [home_goal,home_next,home_hint,home_records]:node.visible=city_home
	technical_toggle.visible=not city_home
	if not city_home and selected_tab==3:detail.text=_nontrade_cash_text(snapshot.get("trade_review",{}))+"\n\n"+detail.text+"\n\n"+_cost_text()+"\n\n"+_feedback_text()
	if not city_home and show_technical:detail.text+="\n\n技术核验（原业务引用）\n"+_technical_text()
	city_state=_project_city()
	var c: Dictionary=snapshot.get("supply",{})
	var p: Dictionary=SupplyProjection.project(c,view,current_minute)
	var has_local_warehouse: bool=false
	for op: Dictionary in view.get("operations",[]):
		if op.get("stock_place_id")==selected_place:has_local_warehouse=true
	for i: int in range(facilities.size()):
		facilities[i].visible=city_home and not (i==1 and not has_local_warehouse) and not (i==4 and _local_opportunities().is_empty() and _local_sales_orders().is_empty())
		facilities[i].disabled=not world_ready or (i==1 and not has_local_warehouse) or (i==4 and _local_opportunities().is_empty() and _local_sales_orders().is_empty())
	for facility: Button in facilities:facility.text=""
	facilities[1].text="" if has_local_warehouse else "本城无自有仓"
	home_hint.text="浏览"+PLACES[selected_place]+" · "+_latest_feedback()
	home_goal.disabled=not world_ready;home_next.disabled=not world_ready
	var count: int=snapshot.get("opportunities",[]).size()
	if not _has_actionable_contract():
		home_goal.text="自主经营 · 采购、运输、出售\n未接单也可以继续贸易"
		home_next.text="查看已知现货贸易机会"
	if not c.is_empty():home_goal.text="机会%s份 · %s × %s · %s\n交至%s · %s / 到账%s%s"%[count,GOODS.get(c["good"],c["good"]),c["quantity"],_supply_status(c["status"]),_site_name(str(c.get("buyer_site","未知"))),_home_supply_stock(c),c.get("paid",0),(" · 截止第%d天"%(int(c["deadline"])/1440+1)) if c.get("status") in ["RECRUITING","ACCEPTED","PARTIAL"] else ""]
	home_next.text="下一步："+("查看其他已知贸易机会" if not c.has("accept_action") and c.get("status")!="RECRUITING" else str(p.get("next_action","查看机会")))
	if selected_tab==6 and not city_home:
		c=_selected_buyer_opportunity();p=SupplyProjection.project(c,view,current_minute)
	if selected_tab==6 and not city_home and c.has("accept_action"):
		detail.text+="\n"+str(p.get("arrival_summary","到达下限未知"))
	if selected_tab==6 and not city_home:
		primary.disabled=primary.disabled or (c.get("status")=="RECRUITING" and not c.get("ready",false)) or (c.get("status")!="RECRUITING" and (c.get("status") not in ["ACCEPTED","PARTIAL"] or int(c.get("free_stock",0))<=0 or int(c.get("unallocated",0))<=0))
		secondary.disabled=secondary.disabled or (c.get("status") not in ["ACCEPTED","PARTIAL"] and _local_sales_orders().is_empty())

func _city_scale() -> float:
	return minf((layout_size.x-40.0)/920.0,maxf(0.8,(layout_size.y-400.0)/218.0))
func _city_origin() -> Vector2:
	var used: float=218.0*_city_scale()
	return Vector2((layout_size.x-920.0*_city_scale())*0.5,190+maxf(0,(layout_size.y-371-used)*0.5))
func _facility_rect(index: int) -> Rect2:
	var box: Rect2=[Rect2(35,248,150,120),Rect2(215,320,160,112),Rect2(400,245,175,115),Rect2(595,319,145,113),Rect2(760,248,165,122)][index]
	return Rect2(_city_origin()+(box.position-Vector2(20,220))*_city_scale(),box.size*_city_scale())
func _city_label(text: String,pos: Vector2,width: float=160) -> void:
	draw_string(font,pos,text,HORIZONTAL_ALIGNMENT_CENTER,width,17,Color("f0e8cb"))
func _window_grid(x: float,y: float,columns: int,rows: int) -> void:
	for col: int in range(columns):
		for row: int in range(rows):
			draw_rect(Rect2(x+col*27,y+row*25,13,15),Color("e7c97e"))
			draw_line(Vector2(x+col*27+6,y+row*25),Vector2(x+col*27+6,y+row*25+15),Color("4c625c"),2)

func _apply_home_theme() -> void:
	for node: Node in get_children():
		if node is Label:node.add_theme_color_override("font_color",Color("a9b9cc"))
		if node is Button or node is OptionButton:
			node.add_theme_color_override("font_color",Color("dce8f6"))
			node.add_theme_color_override("font_disabled_color",Color("617084"))
			for state: String in ["normal","hover","pressed","focus","disabled"]:
				var box:=StyleBoxFlat.new()
				box.bg_color=Color("18283b") if state in ["hover","pressed"] else Color("111e2e")
				box.border_color=Color("5cd4e6") if state=="focus" else Color("294056")
				box.set_border_width_all(1);box.set_corner_radius_all(9)
				node.add_theme_stylebox_override(state,box)
	for facility: Button in facilities:
		for state: String in ["normal","hover","pressed","focus","disabled"]:
			var box:=StyleBoxFlat.new();box.bg_color=Color(1,1,1,0.10) if state in ["hover","pressed"] else Color(0,0,0,0)
			if state=="focus":box.border_color=Color("e5cc86");box.set_border_width_all(2)
			facility.add_theme_stylebox_override(state,box)
	header.add_theme_color_override("font_color",Color("e9f2ff"))
	header.add_theme_font_size_override("font_size",20)
	home_goal.alignment=HORIZONTAL_ALIGNMENT_LEFT
	home_goal.clip_text=true
	home_goal.add_theme_font_size_override("font_size",17)
	home_next.add_theme_color_override("font_color",Color("08151d"))
	var main_style:=StyleBoxFlat.new();main_style.bg_color=Color("6ad8e4");main_style.set_corner_radius_all(9)
	home_next.add_theme_stylebox_override("normal",main_style)
	home_next.add_theme_stylebox_override("hover",main_style)
	home_next.add_theme_stylebox_override("pressed",main_style)

func _layout_home() -> void:
	var w: float=layout_size.x
	var h: float=layout_size.y
	header.position=Vector2(24,14);header.size=Vector2(w-250,36);header.add_theme_font_size_override("font_size",20)
	identity_button.position=Vector2(w-205,12);identity_button.size=Vector2(181,48)
	home_hint.position=Vector2(24,143);home_hint.size=Vector2(w-500,44);home_hint.add_theme_font_size_override("font_size",13)
	for i: int in range(map_buttons.size()):
		map_buttons[i].position=Vector2(w-465+i*149,142);map_buttons[i].size=Vector2(139,48)
	home_goal.position=Vector2(20,h-171);home_goal.size=Vector2(w-250,62)
	home_progress.position=home_goal.position+Vector2(18,home_goal.size.y-7);home_progress.size=Vector2(home_goal.size.x-36,3)
	for i: int in range(facilities.size()):
		var rect: Rect2=_facility_rect(i);facilities[i].position=rect.position;facilities[i].size=rect.size
	home_delegate.position=Vector2(w-220,h-171);home_delegate.size=Vector2(200,62);home_delegate.add_theme_font_size_override("font_size",16)
	home_next.visible=false
	notice.position=Vector2(24,h-100);notice.size=Vector2(w-48,40);notice.add_theme_font_size_override("font_size",13)
	for b: Button in buttons:b.add_theme_font_size_override("font_size",16)
func _home_action_text() -> String:
	if not world_ready:return "   正在读取合同与机会…" if not startup_failed else "   读取失败，请查看下方提示"
	var c: Dictionary=snapshot.get("supply",{})
	if _has_actionable_contract():
		return "   %s · %s × %s · %s  ↗\n   %s；已核验到账%s"%[_site_name(str(c.get("buyer_site",""))),GOODS.get(c.get("good"),"商品"),c.get("quantity","未知"),_supply_status(c.get("status","")),"已承担责任，查看库存与期限" if c.has("accept_action") else "尚未接受，查看条件后自行决定",c.get("paid",0)]
	var review: Dictionary=snapshot.get("trade_review",{})
	return "   下一笔：比较货源、成本与新销售状态  ↗\n   全商号已知交易现金差额%s（非净利润）；可少买、留货或等待"%_money(review.get("known_trade_cash_difference",{}))

func _home_contract_text() -> String:
	if not world_ready:return "   正在读取合同与机会…" if not startup_failed else "   读取失败，请查看下方提示"
	var c: Dictionary=snapshot.get("supply",{})
	if not _has_actionable_contract():
		var review: Dictionary=snapshot.get("trade_review",{})
		return "   继续经营 · 比较采购、运费与挂牌\n   已收%s − 货款%s − 运费%s\n   商品货运现金差额%s（工资、服务另列）\n   可少买、调整未来价或等待  ↗"%[_money(review.get("sales_received",{})),_money(review.get("goods_paid",{})),_money(review.get("freight_paid",{})),_money(review.get("known_trade_cash_difference",{}))]
	var p: Dictionary=SupplyProjection.project(c,view,current_minute)
	var status: String=_supply_status(str(c.get("status","未知")))
	var deadline: String="期限未知" if not c.has("deadline") else "截止第%d天"%(int(c["deadline"])/1440+1)
	var risk: String=str(p.get("risk","查看供货责任与履约详情"))
	if not c.has("accept_action"):
		return "   %s × %s   /   %s\n   交至%s · %s\n   未接受此机会 · 无本商号履约记录\n   查看条件与其他已知机会  ↗"%[GOODS.get(c.get("good"),c.get("good","未知")),_known(c.get("quantity")),status,_site_name(str(c.get("buyer_site","未知"))),deadline]
	if c.get("status")=="COMPLETED":risk="按时履约完成 · 查看批次与到账记录"
	elif c.get("status")=="OVERDUE":risk="已逾期；旧批次继续履约，不再安排新货"
	elif c.get("status")=="TERMINATED":risk="已终止未来供货；旧批次继续履约"
	if risk.length()>26:risk=risk.left(26)+"…"
	return "   %s × %s   /   %s\n   交至%s · %s\n   按时%s/%s · 迟到%s · 到账%s\n   %s  ↗"%[GOODS.get(c.get("good"),c.get("good","未知")),_known(c.get("quantity")),status,_site_name(str(c.get("buyer_site","未知"))),deadline,_known(c.get("ontime")),_known(c.get("quantity")),_known(c.get("late")),_known(c.get("paid")),risk]

func _focus_contract() -> void:
	# Read-only focus. Explicit player selection always wins; no contract is accepted here.
	if contract_user_selected:return
	var best: Dictionary={}
	var best_rank: int=99
	for c: Dictionary in snapshot.get("opportunities",[]):
		var status: String=str(c.get("status",""))
		var rank: int=3
		if c.has("accept_action") and status in ["ACCEPTED","PARTIAL"]:rank=0
		elif status=="RECRUITING" and c.get("ready",false):rank=1
		elif c.has("accept_action"):rank=2
		var wins_tie: bool=false
		if rank==best_rank:
			if rank==2:
				var ended: int=int(c.get("ended_minute",c.get("accepted_minute",-1)))
				var best_ended: int=int(best.get("ended_minute",best.get("accepted_minute",-1)))
				wins_tie=ended>best_ended or (ended==best_ended and int(c.get("accepted_minute",-1))>int(best.get("accepted_minute",-1)))
			else:wins_tie=int(c.get("deadline",2147483647))<int(best.get("deadline",2147483647))
		if rank<best_rank or wins_tie:best=c;best_rank=rank
	if not best.is_empty():
		var presentation: Dictionary=snapshot.duplicate()
		presentation["supply"]=best
		snapshot=presentation;selected_contract=str(best["id"])


func _home_text(text: String,pos: Vector2,points: int=16,color: Color=Color("a9b9cc"),width: float=-1) -> void:
	draw_string(font,pos,text,HORIZONTAL_ALIGNMENT_LEFT,width,points,color)

func _home_panel(rect: Rect2,accent: bool=false) -> void:
	var style:=StyleBoxFlat.new();style.bg_color=Color("102230") if accent else Color("101b29");style.set_corner_radius_all(12);style.border_color=Color("254553") if accent else Color("263448");style.set_border_width_all(1)
	draw_style_box(style,rect)

func _draw_city_space() -> void:
	var w: float=layout_size.x
	var a: float=(w-64)*0.46
	var b: float=(w-64)*0.25
	_home_panel(Rect2(20,68,a,68),true);_home_panel(Rect2(32+a,68,b,68));_home_panel(Rect2(44+a+b,68,w-64-a-b,68))
	_home_text("全商号可用资金",Vector2(35,89),13)
	_home_text(str(int(view["cash"])-int(view["reserved"])) if view.has("cash") and view.has("reserved") else "未知",Vector2(35,123),28,Color("80e0eb"))
	_home_text("全商号预留",Vector2(47+a,89),13);_home_text(_known(view.get("reserved")),Vector2(47+a,123),26,Color("e1eaf7"))
	_home_text("个人钱包 · 独立账户",Vector2(59+a+b,89),12);_home_text(_known(snapshot.get("personal_available")),Vector2(59+a+b,123),26,Color("e1eaf7"))
	_home_panel(Rect2(20,196,w-40,layout_size.y-377))
	var origin: Vector2=_city_origin()-Vector2(20,220)*_city_scale()
	draw_set_transform(origin,0,Vector2.ONE*_city_scale())
	_draw_facilities()
	_draw_status_badge("本页可执行报价%s"%city_state.get("available_offers",0),Vector2(35,269),150)
	if facilities[1].visible:
		_draw_status_badge("本城在库%s / 自由%s"%[city_state.get("stock",0),city_state.get("free",0)],Vector2(215,319),160)
	_draw_status_badge("全号待发%s / 途%s"%[city_state.get("pending",0),city_state.get("transit",0)],Vector2(400,246),175)
	if facilities[4].visible:_draw_status_badge("真实买方 · 机会与旧单",Vector2(760,248),165)
	draw_set_transform(Vector2.ZERO,0,Vector2.ONE)
	_home_text(_freight_summary(),Vector2(32,layout_size.y-186),13,Color("b5d7df"),w-64)

func _draw_facilities() -> void:
	var ground: Color={"place:paris":Color("304b44"),"place:lyon":Color("354f49"),"place:marseille":Color("3b5356")}[selected_place]
	draw_rect(Rect2(20,241,920,197),ground)
	# Schematic streets and facility footprints, never vehicle or GPS positions.
	var road:=PackedVector2Array([Vector2(20,387),Vector2(192,387),Vector2(300,287),Vector2(590,287),Vector2(750,390),Vector2(940,390)])
	draw_polyline(road,Color("65746a"),22,true);draw_polyline(road,Color("aaa48a"),2,true)
	for x: int in range(40,940,48):draw_line(Vector2(x,433),Vector2(x+20,433),Color("77877a"),2)
	# Public market awning, stalls, baskets. This represents a market entrance, not stock.
	draw_rect(Rect2(45,281,130,62),Color("796c4d"));draw_rect(Rect2(48,277,124,20),Color("d8bd86"))
	for x: int in range(48,172,24):draw_rect(Rect2(x,277,12,20),Color("ae6856"))
	for x: int in [55,107]:
		draw_rect(Rect2(x,309,50,17),Color("b09059"));draw_rect(Rect2(x+6,302,17,9),Color("d2b77d"))
	draw_line(Vector2(48,297),Vector2(48,347),Color("d0b477"),4);draw_line(Vector2(172,297),Vector2(172,347),Color("d0b477"),4)
	_city_label("市场 · 采购",Vector2(35,365),150)
	if facilities[1].visible:
		# Warehouse loading apron, roof and closed stock doors: no invented goods count.
		draw_rect(Rect2(221,395,150,16),Color("9a967c"));draw_rect(Rect2(227,350,137,49),Color("8a977e"))
		draw_colored_polygon(PackedVector2Array([Vector2(218,351),Vector2(247,328),Vector2(350,328),Vector2(371,351)]),Color("647c78"))
		for x: int in [240,302]:
			draw_rect(Rect2(x,367,45,32),Color("435c57"))
			for dx: int in range(6,45,9):draw_line(Vector2(x+dx,369),Vector2(x+dx,397),Color("768779"),2)
		_city_label("仓库 · 自有货物",Vector2(215,429),160)
	else:
		_city_label("此城无自有仓",Vector2(215,419),160)
		for x: int in [245,285,330]:draw_circle(Vector2(x,369),14,Color("587563"));draw_line(Vector2(x,377),Vector2(x,399),Color("9b8e66"),3)
	if facilities[1].visible:
		# Exact own inventory is shown as bounded decorative boxes; it never mutates stock.
		var crates: int=mini(8,int(city_state.get("stock",0)))
		for n: int in range(crates):
			draw_rect(Rect2(232+(n%4)*24,391-(n/4)*15,20,13),Color("dab778"))
	# Freight station with static tracks. No fake train, schedule or precise position.
	for y: int in [326,336]:draw_line(Vector2(388,y),Vector2(588,y),Color("aeb8ac"),2)
	for x: int in range(391,586,12):draw_line(Vector2(x,322),Vector2(x,340),Color("787862"),2)
	draw_rect(Rect2(416,274,145,45),Color("a4a088"));draw_rect(Rect2(409,270,158,9),Color("5e7775"))
	for x: int in [425,469,513]:draw_rect(Rect2(x,287,30,30),Color("405b59"))
	draw_rect(Rect2(470,253,44,19),Color("d3bc82"));_city_label("货站",Vector2(470,269),44)
	_city_label("货站 · 合同运输",Vector2(400,356),175)
	# Company ledger entrance can be used remotely; no extra owned property inferred.
	if facilities[1].visible:
		draw_rect(Rect2(618,342,99,66),Color("b4a286"));draw_colored_polygon(PackedVector2Array([Vector2(610,342),Vector2(666,320),Vector2(725,342)]),Color("826d63"))
		_window_grid(630,350,3,1);draw_rect(Rect2(652,380,28,28),Color("596d61"))
	else:
		draw_rect(Rect2(620,350,92,58),Color("8a876b"));draw_rect(Rect2(630,340,75,52),Color("e0d3a8"))
		for y: int in range(350,385,8):draw_line(Vector2(640,y),Vector2(695,y),Color("887e63"),2)
	_city_label("商号 · 经营账簿",Vector2(595,429),145)
	if facilities[4].visible:
		draw_rect(Rect2(780,285,128,55),Color("b19d81"));draw_rect(Rect2(891,255,13,40),Color("8f7f6a"))
		draw_colored_polygon(PackedVector2Array([Vector2(774,286),Vector2(774,271),Vector2(818,283),Vector2(818,267),Vector2(861,283),Vector2(861,269),Vector2(913,286)]),Color("917268"))
		_window_grid(791,294,4,1);draw_rect(Rect2(826,321,37,20),Color("5b6c61"))
		_city_label(_buyer_label(),Vector2(760,365),165)
	else:
		# Unowned waterfront/park space, not an invented buyer facility.
		draw_rect(Rect2(790,267,120,55),Color("4d7275"))
		for y: int in [279,295,310]:draw_line(Vector2(805,y),Vector2(894,y),Color("789894"),2)
		_city_label("暂无已知供货关系",Vector2(755,357),175)

func _draw_city_status() -> void:
	pass

func _project_city() -> Dictionary:
	var result: Dictionary={"stock":0,"free":0,"committed":0,"incoming":0,"pending":0,"transit":0,"available_offers":0,"transfers":0}
	for op: Dictionary in view.get("operations",[]):
		if op.get("stock_place_id")!=selected_place:continue
		for pair: Array in [["inventory","stock"],["free_inventory","free"],["committed_inventory","committed"],["incoming","incoming"]]:
			for value: Variant in op.get(pair[0],{}).values():result[pair[1]]+=int(value)
	var seen: Dictionary={}
	for order: Dictionary in view.get("orders",[])+view.get("sales_orders",[]):
		if seen.has(str(order.get("id"))):continue
		seen[str(order.get("id"))]=true
		result["pending"]+=int(order.get("pending",0));result["transit"]+=int(order.get("transit",0))
		if order.get("kind")=="TRANSFER":result["transfers"]+=int(order.get("pending",0))+int(order.get("transit",0))
	for offer: Dictionary in snapshot.get("business",{}).get("offers",[]):
		if offer.get("from_place_id")==selected_place and offer.get("can_order",false):result["available_offers"]+=1
	return result
func _draw_status_badge(text: String,pos: Vector2,width: float) -> void:
	draw_rect(Rect2(pos-Vector2(0,18),Vector2(width,21)),Color("173039"))
	draw_string(font,pos,text,HORIZONTAL_ALIGNMENT_CENTER,width,14,Color("f5dfaa"))

func _opportunity_preview(c: Dictionary) -> String:
	var free: int=int(c.get("free_stock",0))
	var lines: Array[String]=["自身可用资金%s；当前可交%s%s。"%[int(view.get("cash",0))-int(view.get("reserved",0)),free,GOODS.get(c.get("good"),"商品")]]
	var sources: Array=c.get("known_sources",[])
	var covered: int=0
	if sources.is_empty():lines.append("尚无已知供应报价；新增采购成本和到仓时间未知。")
	for q: Dictionary in sources.slice(0,4):
		var acceptable: int=int(q.get("comparison",{}).get("acceptable_quantity",0))
		if q.get("price")!=null and q.get("freight_per_unit")!=null and acceptable>0:
			var available: int=mini(maxi(0,int(c["quantity"])-free),acceptable)
			lines.append("仅该来源可供部分%s件的已知货款＋入库运费%s；不是全部缺口成本。"%[available,available*(int(q["price"])+int(q["freight_per_unit"]))])
			covered=maxi(covered,available)
		lines.append("已知%s：货价%s＋运费%s，可执行%s，到仓下限%s。"%[_site_name(str(q.get("seller_site",""))),_known(q.get("price")),_known(q.get("freight_per_unit")),acceptable,"未知" if q.get("earliest_arrival_day")==null else "第%d天"%(int(q["earliest_arrival_day"])+1)])
	if covered<maxi(0,int(c["quantity"])-free):lines.append("没有单一已知来源覆盖全部缺口；不同来源可能共用库存或运力，不合并成保证预算。")
	if free<int(c.get("quantity",0)):lines.append("还需采购或等待到仓；当前资料不能保证全部按时交付。")
	if c.get("new_batch_earliest_day")!=null:
		lines.append("现货本地交付下限第%d天；采购到仓后仍需这段运输。"%(int(c["new_batch_earliest_day"])+1))
		if int(c["new_batch_earliest_day"])*1440>int(c["deadline"]):lines.append("警告：即使现在交现货，最早也晚于截止。")
	else:lines.append("现货交割时间下限未知。")
	lines.append("报价及可供量随实际经营变化；没有未来库存、运力或利润保证。")
	return "\n".join(lines)

func _known(value: Variant) -> String:return "未知" if value==null else str(value)

func _goods_summary(goods: Dictionary) -> String:
	var parts: Array[String]=[]
	for good: String in goods:
		if int(goods[good])>0:parts.append("%s%s"%[GOODS.get(good,good),goods[good]])
	return "无" if parts.is_empty() else " / ".join(parts)

# Read-only presentation of the runtime's authorized, detached feedback.
func _latest_feedback() -> String:
	if not critical_notice.is_empty():return critical_notice.left(70)
	if not priority_payment.is_empty():return str(priority_payment.get("text","")).left(70)
	if not _deadline_notice().is_empty():return _deadline_notice().left(70)
	for event: Dictionary in snapshot.get("market_feedback",{}).get("events",[]):
		if event.get("kind")=="payment":return ("历史到账 · "+str(event.get("text",""))).left(70)
	var events: Array=snapshot.get("market_feedback",{}).get("events",[])
	if not events.is_empty():return str(events[0].get("text","暂无新的经营变化")).left(70)
	return news[0].left(70) if not news.is_empty() else "暂无新的经营变化 · 经营记录保留真实交易与到账"

func _feedback_text() -> String:
	var feedback: Dictionary=snapshot.get("market_feedback",{})
	var lines: Array[String]=["经营目标 · 只读进度，无额外奖励"]
	for goal: Dictionary in feedback.get("goals",[]):
		lines.append(("已达到 · " if goal.get("achieved",false) else "进行中 · ")+str(goal.get("title","经营观察"))+"  "+str(goal.get("progress","")))
	if feedback.get("goals",[]).is_empty():lines.append("尚无可核验目标数据；可继续经营。")
	lines.append("\n真实经营事件")
	for event: Dictionary in feedback.get("events",[]):
		lines.append(str(event.get("text","")))
		if event.get("kind")=="payment":lines.append("  收据%s / Ledger %s"%[event.get("receipt_id",""),str(event.get("payment_ids",[]))])
	if feedback.get("events",[]).is_empty():lines.append("暂无新增记录；下方保留自身交易账款。")
	return "\n".join(lines)
func _technical_text() -> String:
	var lines: Array[String]=["存档槽：%s；游戏分钟：%s；仓库：%s"%[snapshot.get("slot"),current_minute,selected_site],"正式人物："+str(snapshot.get("person_id","未知")),"商号："+str(snapshot.get("identity",{}).get("firm_id","未知")),"管理来源："+str(snapshot.get("identity",{}).get("management_basis","未知")),"底层地点："+str(snapshot.get("player_place","未知"))+"；正式旅程："+str(snapshot.get("travel",{}))]
	if selected_tab==6:
		var c: Dictionary=_selected_buyer_opportunity()
		for key: String in ["id","buyer","buyer_site","source","accept_action","batches"]:
			if c.has(key):lines.append(key+"："+str(c[key]))
	elif selected_tab==2:
		var order: Dictionary=_selected_order()
		for key: String in ["id","buyer","seller","seller_site","buyer_site","supply_contract_id","shipments","deliveries","earliest_arrival_day"]:
			if order.has(key):lines.append(key+"："+str(order[key]))
		var contract: Dictionary=_order_supply_contract(order)
		if not contract.is_empty():lines.append("关联已接受合同："+str(contract.get("id"))+"；deadline："+str(contract.get("deadline")))
	elif selected_tab==0:
		var offer: Dictionary=_selected_offer()
		for key: String in ["seller_site","route_id","reason","order_reason"]:
			if offer.has(key):lines.append(key+"："+str(offer[key]))
	if selected_tab==3:
		lines.append("数据口径："+str(snapshot.get("market_feedback",{}).get("basis","未知")))
		lines.append("地区统计权限："+str(snapshot.get("regional_statistics_basis","未知"))+"。公共地区统计是开发场景假设，不是企业报价或采购承诺。")
		for event: Dictionary in snapshot.get("market_feedback",{}).get("events",[]):lines.append(str(event.get("refs",[])))
	return "\n".join(lines)

# All tutorial/cargo text is reconstructed from detached authorized observations.
# These controls never own inventory, cash, grants or economic progression.
func _guide_action(action: StringName) -> void:
	if action!="feedback" or busy or not world_ready or snapshot.get("external_host",false) or int(snapshot.get("slot",0))==5:return
	_pause();guide.hide();confirm_kind="switch";confirm_payload={"slot":5,"feedback_opt_in":true}
	_show_confirm("区域反馈实验 · 独立槽5\n先保存当前普通存档；已有实验档则继续，只有无实验档才新开。旧槽1–4不迁移。\n旧1.0.1/1.0.2不能读取本实验档。启动仍回普通槽，实验需每次明确进入。\n复用真实交易、工资、货批和运输；仅4生产公司/4工人群体欠薪反馈及粮、面包两项未来报价反馈。参数是开发假设，无保底利润。\n新增反馈有额外计算开销；交易保存及恢复仍可能等待数秒，尚无长期性能保证。\n单商品新销售可在仓库暂停或恢复；恢复时重检当前报价与权限。开放销售时，到仓且可处分的商品可能被NPC买走。“委托0”只表示未启用补货计划，不表示停止挂牌。\n确认进入区域反馈实验？")

func _show_guide() -> void:
	_pause()
	var identity: Dictionary=snapshot.get("identity",{})
	var review: Dictionary=snapshot.get("trade_review",{})
	var personal_id: String="当前受控商人（正式身份见经营页技术详情）"
	guide_text.text="构建 %s · %s\n你控制：%s\n实际所在地：%s；浏览：%s。地图按钮只看城市，出行需在行程页付个人车票。\n个人可用：%s；商号可用：%s；商号预留：%s。公司资产不能当作你的私人收入。\n管理关系：%s\n\n%s\n\n未结：采购货款%s / 销售应收%s / 供货合同%s份。\n自由库存才能新出售或供货；在途货未入库，验收后才收款。\n单商品新销售可在仓库暂停或恢复；恢复时重检当前报价与权限。开放销售时，到仓且可处分的商品可能被NPC买走。“委托0”只表示未启用补货计划，不表示停止挂牌。\n你可以选择小批采购、大批采购或等待；预览货款＋运费＋预留后再决定。机会可能失效，回市场找新报价。没有新手赠品或保底利润。\n随时点右上角重看；关闭提示不会执行交易。"%[str(ProjectSettings.get_setting("application/config/build_id","未标识")),str(ProjectSettings.get_setting("application/config/build_label","未标识")),personal_id,_person_location(),PLACES[selected_place],_known(snapshot.get("personal_available")),int(view.get("cash",0))-int(view.get("reserved",0)),view.get("reserved",0),_management_label()+"\n"+_personal_responsibilities(),_guide_next(),review.get("unsettled_goods_purchases",0),review.get("unsettled_goods_sales",0),review.get("open_supply_contracts",[]).size()]
	feedback_entry.visible=not snapshot.get("external_host",false)
	if snapshot.get("business_experiment",false):feedback_entry.visible=false;guide_text.text="区域经营试玩：当前世界与NPC连续运行。另存试玩后可从F6恢复；尚未另存时关闭即结束。研发诊断不可用。\n\n"+guide_text.text
	feedback_entry.disabled=busy or not world_ready or int(snapshot.get("slot",0))==5
	if int(snapshot.get("slot",0))==5:guide_text.text="当前：区域反馈实验 · 独立槽5；旧版本不能读。切换场景将回普通槽4。\n\n"+guide_text.text
	guide.popup_centered(Vector2i(int(minf(layout_size.x-40,900)),470))
func _guide_next() -> String:
	if int(city_state.get("transit",0))+int(city_state.get("pending",0))>0:return "当前建议：货站有未结运输，先看货物在哪里与等待原因，再决定是否继续采购。"
	if int(city_state.get("free",0))>0:return "当前建议：仓库有自由货物。点货箱核对地点、已承诺数量，再决定报价出售、合同供货或等待。"
	return "当前建议：先看市场已知报价，或买方的真实采购机会。接受合同会留下责任，可以暂不接受。"
func _cargo_rows() -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	var op: Dictionary=_operation()
	if city_home:
		op={}
		for local: Dictionary in view.get("operations",[]):
			if local.get("stock_place_id")==selected_place:op=local;break
	for good: String in op.get("inventory",{}):
		if int(op["inventory"][good])+int(op.get("incoming",{}).get(good,0))>0:result.append({"site":op.get("site_id",selected_site),"good":good,"stock":op["inventory"][good],"free":op.get("free_inventory",{}).get(good,0)})
	return result
func _refresh_cargo() -> void:
	var rows: Array[Dictionary]=_cargo_rows()
	for i: int in range(cargo_buttons.size()):
		cargo_buttons[i].position=Vector2(20,370+i*40);cargo_buttons[i].size=Vector2(210,36)
		cargo_buttons[i].add_theme_font_size_override("font_size",14)
		cargo_buttons[i].visible=not city_home and selected_tab==1 and i<rows.size() and cargo_buttons[i].get_rect().end.y<notice.position.y
		if city_home and i==0 and not rows.is_empty():
			cargo_buttons[i].position=_facility_rect(1).position+Vector2(6,49)*_city_scale()
			cargo_buttons[i].size=Vector2(148,36)*_city_scale();cargo_buttons[i].add_theme_font_size_override("font_size",13)
			cargo_buttons[i].visible=true
		cargo_buttons[i].disabled=busy or not world_ready
		if i<rows.size():cargo_buttons[i].text=("%s 在库%s · 销售 ↗" if city_home else "▣ %s 在库%s / 可用%s")%([GOODS.get(rows[i]["good"],rows[i]["good"]),rows[i]["stock"]] if city_home else [GOODS.get(rows[i]["good"],rows[i]["good"]),rows[i]["stock"],rows[i]["free"]])
func _inspect_cargo(index: int) -> void:
	var rows: Array[Dictionary]=_cargo_rows()
	if index>=rows.size() or busy:return
	var from_city: bool=city_home
	selected_site=str(rows[index]["site"]);selected_good=str(rows[index]["good"])
	if from_city:_set_tab(1);_pause();_observe()
	else:_refresh()
	message="%s：可调整未来价、暂停或恢复新销售；旧合同继续，也可调拨或等待。所有动作仍经正式核验。"%GOODS.get(selected_good,selected_good);notice.text=message

func _write_performance() -> void:
	var bins: Array=frame_histogram.keys();bins.sort()
	var seen: int=0;var p95: int=0
	for bucket: int in bins:
		seen+=int(frame_histogram[bucket])
		if seen>=int(ceil(frame_count*0.95)):p95=bucket;break
	var sample: Dictionary={"platform":OS.get_name(),"frames":frame_count,"frame_p95_ms_bucket":p95,"frame_max_us":frame_max_us,"worker_max_us":worker_max_us,"worker_by_kind":worker_by_kind,"stage_samples":stage_samples,"main_refresh_max_us":main_refresh_max_us,"peak_static_memory_bytes":peak_memory_bytes,"minute":current_minute,"note":"Includes loading, pauses and UI; desktop results are not Android device measurements."}
	var file: FileAccess=FileAccess.open("user://merchant_101_performance.json",FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(sample,"  "));file.close()
	print("MERCHANT_101_PERFORMANCE ",JSON.stringify(sample))

# Caller configures this before adding the scene to the tree. No WorldState crosses UI.
func enter_host_context(context: Dictionary) -> Error:
	if runtime!=null or not Runtime._plain(context) or context.is_empty():return ERR_INVALID_PARAMETER
	external_host_context=context.duplicate(true)
	return OK

func leave_host_context() -> void:
	if external_host_context.is_empty() or runtime==null or close_requested:return
	_pause();close_requested=true;save_requested=true;_send("close")

func _nontrade_cash_text(review: Dictionary) -> String:
	var paid: Dictionary=review.get("nontrade_cash",{})
	return "本局累计商号现金流出：工资%s／公告服务%s／其他服务%s／其他现金流出%s。其他流出的性质以原业务引用为准，不一律视为成本或亏损。上述金额未计入累计商品与货运差额；应付未付工资另列。"%[_money(paid.get("wages_paid",{})),_money(paid.get("advertising_paid",{})),_money(paid.get("service_fees_paid",{})),_money(paid.get("other_cash_paid",{}))]

func _cost_text() -> String:
	var finance: Dictionary=snapshot.get("business",{}).get("finance",{})
	var costs: Dictionary=finance.get("direct_costs",{})
	var lines: Array[String]=["取得成本与经营责任"]
	var bulletin: Dictionary=snapshot.get("public_reference",{})
	if not bulletin.is_empty():lines.append("公开小麦参考指数%.2f（第%d日观察，第%d日收到）。这是开发情景行情信号，不是本地可执行报价或跨币种货币；采购仍需原供应商、货批及运输。"%[float(bulletin.index),int(bulletin.observed_day)+1,int(bulletin.received_day)+1])
	for currency: String in finance.get("procurement_cash",{}):
		var cash: Dictionary=finance.procurement_cash[currency]
		lines.append("账面%s－正式预留%s＝可用%s；到期未预留责任%s，经营保护下限%s；当前可安排%s。"%[cash.balance,cash.reserved,cash.available,cash.due_unreserved,cash.protected,cash.spendable])
	lines.append("库存原成本已形成资产，不再作为今日付款扣减；未实现销售应收不能支付采购。")
	if not costs.get("enabled",false):lines.append("成本资料未启用或不足，不能计算完整净利润。")
	else:
		for good: String in costs.get("inventory",{}):
			var row: Dictionary=costs["inventory"][good]
			lines.append("%s：持有%s，已知取得成本%s；成本未知数量%s"%[GOODS.get(good,good),row.get("owned_quantity",0),_money(row.get("known_cost",{})),row.get("unknown_cost_quantity",0)])
		lines.append("最近窗口自第%s日：已知售出成本%s / 可比交易贡献%s；未知成本销售%s笔。仅已知直接成本，不是净利润。"%[int(finance.get("window_start_day",0))+1,_money(costs.get("sold_known_cost",{})),_money(costs.get("contribution",{})),costs.get("unknown_sales",0)])
	lines.append("实际未付工资%s；贷款、租约及其他责任以原正式业务明细为准。"%_money(finance.get("wages_unpaid",{})))
	return "\n".join(lines)

func _publicity_actions() -> Array[Dictionary]:
	var rows: Array[Dictionary]=[]
	var good: String="grain" if selected_good=="all" else selected_good
	var person: Dictionary=snapshot.get("identity",{}).get("personal",{})
	var employment: Dictionary=person.get("employment",{})
	for job: Dictionary in person.get("known_jobs",[]):
		if job.get("employer")!=Opening.FIRM or job.get("site_id")!=selected_site:continue
		if employment.is_empty():rows.append({"kind":"apply","label":"申请本站岗位 · 时薪%s／每日%s小时"%[job.wage_per_hour,job.hours],"payload":{"job_id":job.id},"can_execute":true,"reason":"ORIGINAL_PERSON_JOB_ADMISSION_REQUIRED"})
		elif employment.get("job")==job.id:rows.append({"kind":"work","label":"预约本站工作%s小时 · 工资责任%s"%[job.hours,int(job.hours)*int(job.wage_per_hour)],"payload":{"hours":job.hours},"can_execute":true,"reason":"NEXT_BOUNDARY_ACTUAL_WORK_THEN_DUE_WAGE"})
	for action: Dictionary in snapshot.get("business",{}).get("commercial_information",{}).get("actions",[]):
		var item: String=str(action.payload.get("item",action.payload.get("announcement",{}).get("item","")))
		if not item.is_empty() and item!=good:continue
		var visible: Dictionary=action.duplicate(true)
		if action.kind=="publish_notice":
			visible.label=str(action.label)+(" · 商号地点渠道" if str(action.payload.get("channel_id","")).begins_with("channel:merchant_prototype:") else " · 地区地点渠道")
		rows.append(visible)
	return rows

func _publicity_reason(reason: String) -> String:
	return {"ORIGINAL_PERSON_JOB_ADMISSION_REQUIRED":"按本人资格、岗位空缺和所在地裁决","NEXT_BOUNDARY_ACTUAL_WORK_THEN_DUE_WAGE":"预约下一日工作，实际采用后形成工资责任","SITE_BOARD_REQUIRES_ACTUAL_STAFFED_BUSINESS":"地点公告需要本站当日真实工作记录","NO_ACTUAL_UNCOMMITTED_GOODS_TO_ANNOUNCE":"没有可公告的自由实物","PUBLICITY_COOLDOWN_OR_CUMULATIVE_ISSUE_LIMIT":"公告冷却或渠道额度未恢复","PUBLICATION_PREPARED":"公告条件当前满足，提交时重新核验","PRIOR_DELIVERED_MESSAGES_RETAINED":"停止后续接触，已经收到的消息保留","CURRENT_MANAGER_ONLY":"按当前经营授权执行"}.get(reason,reason)

func _publicity_text() -> String:
	var info: Dictionary=snapshot.get("business",{}).get("commercial_information",{})
	var lines: Array[String]=["供货信息传播：挂牌不等于买方已收到介绍。重复送达不等于新增客户，也不保证成交。本站无法知道所有潜在买方的私人信息。"]
	lines.append("本人申请岗位与预约工作均由原领域裁决。工作到次日边界才形成记录和工资责任；工资到期后从商号支付，不能提前当现金。")
	var person: Dictionary=snapshot.get("identity",{}).get("personal",{})
	lines.append("本人已完成工作%s小时；已到账工资%s；未付工资应收%s，其中到期%s。公告服务费与工资分别记账。"%[person.get("totals",{}).get("work_hours",0),_money(person.get("income_by_currency",{})),person.get("wage_outstanding",0),person.get("wage_matured_unpaid",0)])
	if not info.get("enabled",false):lines.append("本站没有原商业公告渠道。")
	for action: Dictionary in _publicity_actions():lines.append(str(action.label)+"："+_publicity_reason(str(action.reason)))
	for row: Dictionary in info.get("announcements",[]):
		lines.append("本商号%s公告：已发布第%s日，已送达%s／已安排%s；费用实付%s。公告后的销售记录不等于广告收益。"%[GOODS.get(row.item,row.item),int(row.published_minute)/1440+1,row.delivered_recipients,row.scheduled_recipients,row.fee_paid])
	return "\n".join(lines)

func adopt_runtime(worker: RefCounted,value: Dictionary) -> Error:
	if runtime!=null or worker==null or not value.get("business_experiment",false) or value.has("consumer_access") or value.has("research_subjects") or value.get("research_only",false):return ERR_INVALID_PARAMETER
	runtime=worker;continued_view=value.duplicate(true)
	return OK

func _personal_responsibilities() -> String:
	var personal: Dictionary=snapshot.get("identity",{}).get("personal",{})
	var open_orders: int=0
	for order: Dictionary in personal.get("orders",[]):
		if int(order.get("pending",0))+int(order.get("transit",0))>0:open_orders+=1
	return "个人预留%s；未结个人货单%s；到期未付工资应收%s。个人收入只认正式到账。"%[snapshot.get("personal_reserved","未知"),open_orders,personal.get("wage_matured_unpaid",0)]

func _management_label() -> String:
	var identity: Dictionary=snapshot.get("identity",{})
	if not identity.get("can_manage",false):return "当前无经营授权"
	return "现任经营负责人（既有授权）" if identity.get("manager_person_id")==identity.get("person_id") else "按既有授权管理商号"
func _person_location() -> String:
	var trip: Dictionary=snapshot.get("travel",{})
	if trip.get("status") in ["TRAVELLING","BLOCKED"]:
		return "%s→%s%s"%[PLACES.get(trip.get("origin"),"起点"),PLACES.get(trip.get("destination"),"目的地"),"等待通行" if trip.get("status")=="BLOCKED" else "途中"]
	return PLACES.get(snapshot.get("player_place"),"途中或未知")
func _order_priority(a: Dictionary,b: Dictionary) -> bool:
	var active_a: bool=int(a.get("pending",0))+int(a.get("transit",0))+int(a.get("reserved_amount",0))>0
	var active_b: bool=int(b.get("pending",0))+int(b.get("transit",0))+int(b.get("reserved_amount",0))>0
	if active_a!=active_b:return active_a
	return int(str(a.get("id","")).get_slice(":",1))>int(str(b.get("id","")).get_slice(":",1))

func _home_supply_stock(contract: Dictionary) -> String:
	var amount: String=str(contract.get("free_stock",0))
	if contract.get("status") not in ["RECRUITING","ACCEPTED","PARTIAL"]:return "自由存货"+amount+"／不可新交付"
	return "自由存货"+amount

func _submit_step(minutes: int) -> void:
	var request_id: int=runtime.submit("advance",{"minutes":minutes})
	stepping=request_id>=0
	if stepping:_track_request(request_id,"advance")

func _wait_text(seconds: int) -> String:
	var labels: Dictionary={"loading":"正在恢复并校验经营世界","queued":"请求已入队，等待经济线程处理","domain":"正在处理正式经济行动或时间推进","snapshot":"经济处理已返回，正在形成完整存档快照","atomic_write":"正在写入存档临时文件","candidate_validation":"正在恢复校验存档候选","atomic_replace":"候选校验已返回，正在处理原子替换","observation":"正在读取新的经营记录"}
	var text: String=str(labels.get(wait_stage,"请求正在处理中"))+" · 已等待%d秒。地图仍可查看。"%seconds
	if stepping:
		text+="\n已确认到第%d天 %02d:%02d；当前小时尚未确认。"%[current_minute/1440+1,(current_minute/60)%24,current_minute%60]
		if requested_day_start>=0:text+="本次已确认%d/1440分钟。"%clampi(current_minute-requested_day_start,0,1440)
		if not running and queued_minutes==0:text+="本小时后暂停。"
	return text

func _track_request(id: int, kind: String) -> void:
	pending_requests[id]={"kind":kind,"started_us":Time.get_ticks_usec(),"stage":"queued"}
	if not pending_requests.has(active_progress_id):active_progress_id=id
	wait_last_second=-1
	_sync_wait()

func _sync_wait() -> void:
	busy=false
	for request: Dictionary in pending_requests.values():
		if request["kind"]!="advance":busy=true
	if not pending_requests.has(active_progress_id) and not pending_requests.is_empty():active_progress_id=int(pending_requests.keys()[0])
	if pending_requests.has(active_progress_id):
		wait_stage=str(pending_requests[active_progress_id]["stage"])
		wait_started_us=int(pending_requests[active_progress_id]["started_us"])
	else:wait_started_us=0;wait_last_second=-1

func _capture_host_result(response: Dictionary) -> void:
	if external_host_context.is_empty() or not response.get("ok",false) or response.get("kind") not in ["close","host_detached"]:return
	var context: Dictionary=response.get("result",{}).get("host_context",{})
	if not context.is_empty():returned_host_context=context.duplicate(true)

func _emit_host_return() -> void:
	if host_return_emitted or external_host_context.is_empty():return
	host_return_emitted=true
	if returned_host_context.is_empty():
		host_continuation_failed.emit("经济线程已关闭但没有合法续接快照；请保留宿主原检查点，不可视为保存成功。")
	else:host_continuation_ready.emit(returned_host_context.duplicate(true))

func _finish_exit() -> void:
	if not external_host_context.is_empty():
		_emit_host_return();queue_free()
	else:get_tree().quit()

func _has_actionable_contract() -> bool:
	var c: Dictionary=snapshot.get("supply",{})
	return (c.has("accept_action") and c.get("status") in ["ACCEPTED","PARTIAL"]) or (c.get("status")=="RECRUITING" and c.get("ready",false))

func _record_payments(announce: bool) -> void:
	# Display-only seen set. On load all reconstructed receipts are history, never new income.
	# Successful world switch clears this set; a failed switch preserves it.
	for event: Dictionary in snapshot.get("market_feedback",{}).get("events",[]):
		if event.get("kind")!="payment":continue
		var key: String=str(event.get("event_id",""))
		if key.is_empty() or observed_payment_events.has(key):continue
		observed_payment_events[key]=true
		if announce:
			_add_news("原收据核验到账："+str(event.get("text","")))
			if priority_payment.is_empty() or int(event.get("minute",0))>=int(priority_payment.get("minute",0)):priority_payment=event.duplicate(true)

func _deadline_notice() -> String:
	for c: Dictionary in snapshot.get("opportunities",[]):
		if not c.has("accept_action") or c.get("status") not in ["ACCEPTED","PARTIAL"]:continue
		var left: int=int(c.get("deadline",0))-current_minute
		if left>=0 and left<=1440:return "合同截止风险：%s需在%s前验收，剩余%s件。"%[GOODS.get(c.get("good"),"商品"),DecisionProjection.day_text(c.get("deadline")),c.get("remaining",c.get("unallocated","未知"))]
	return ""

func _refresh_priority_notice() -> void:
	if payment_notice==null:return
	payment_notice.position=notice.position;payment_notice.size=notice.size
	payment_notice.visible=false;notice.visible=true
	if not critical_notice.is_empty():notice.text=critical_notice;return
	if busy or stepping:return
	if not priority_payment.is_empty():
		payment_notice.text="到账已核验 · "+str(priority_payment.get("text",""))+"  查看订单与收据 ↗"
		payment_notice.visible=true;notice.visible=false
	elif not _deadline_notice().is_empty():notice.text=_deadline_notice()

func _open_payment_receipt() -> void:
	if priority_payment.is_empty() or busy:return
	var event: Dictionary=priority_payment.duplicate(true)
	priority_payment.clear()
	_pause();_set_tab(2);order_key=str(event.get("order_id",""))
	message="已打开原订单；收据%s，Ledger付款%s。"%[event.get("receipt_id",""),str(event.get("payment_ids",[]))]
	_refresh()

func _freight_summary() -> String:
	if not world_ready:return "全商号货运正在读取…"
	var network: Dictionary=snapshot.get("market_network",{})
	if not network.is_empty():
		var warning: String="；数据不完整：%d项待核"%network.get("issues",[]).size() if not network.get("issues",[]).is_empty() else ""
		return "本商号已知网络：%d地点 / %d已确认货批；只引用本地仓与在途，不设国家总仓%s"%[network.get("nodes",{}).size(),network.get("cargo",{}).size(),warning]
	var counts: Array[int]=[0,0,0]
	var seen: Dictionary={}
	for order: Dictionary in view.get("orders",[])+view.get("sales_orders",[]):
		var id: String=str(order.get("id",""))
		if seen.has(id):continue
		seen[id]=true
		for i: int in range(3):
			if int(order.get(["pending","transit","delivered"][i],0))>0:counts[i]+=1
	return "全商号：当前无未结货运；历史到货%s条"%counts[2] if counts[0]+counts[1]==0 else "全商号：当前待发%s单 / 在途%s单；历史到货%s条"%counts
func _order_supply_contract(order: Dictionary) -> Dictionary:
	# Only a traceable accepted own contract establishes a public deadline.
	# An inbound purchase does not automatically inherit the next buyer's deadline.
	var contracts: Array=snapshot.get("opportunities",[]).duplicate()
	if not snapshot.get("supply",{}).is_empty():contracts.append(snapshot["supply"])
	for contract: Dictionary in contracts:
		if not contract.has("accept_action"):continue
		if str(order.get("id","")) in contract.get("batches",[]):return contract
		if not str(order.get("supply_contract_id","")).is_empty() and order["supply_contract_id"]==contract.get("id"):return contract
	return {}
func _site_place(site: String) -> String:
	for op: Dictionary in view.get("operations",[]):
		if op.get("site_id")==site:return str(op.get("stock_place_id",""))
	return {"site:city_competitor:paris":"place:paris","site:regional_upstream:lyon":"place:lyon","site:regional_food:paris":"place:paris","site:regional_food:lyon":"place:lyon","site:regional_textile:lyon":"place:lyon","site:regional_textile:marseille":"place:marseille","site:regional_household:marseille":"place:marseille","site:regional_textile:paris":"place:paris"}.get(site,"")
func _local_opportunities() -> Array[Dictionary]:
	var rows: Array[Dictionary]=[]
	for c: Dictionary in snapshot.get("opportunities",[]):
		if _site_place(str(c.get("buyer_site","")))==selected_place:rows.append(c)
	return rows
func _local_sales_orders() -> Array[Dictionary]:
	var rows: Array[Dictionary]=[]
	for order: Dictionary in view.get("sales_orders",[]):
		if order.get("seller")!=Opening.FIRM:continue
		# Own original order retains its destination even after shipment completion.
		var place: String=str(order.get("to_place_id",""))
		if place.is_empty():place=_site_place(str(order.get("buyer_site","")))
		if place.is_empty():
			for cargo: Dictionary in order.get("shipments",[]):
				if not str(cargo.get("to_place_id","")).is_empty():place=str(cargo["to_place_id"]);break
		if place==selected_place:rows.append(order)
	rows.sort_custom(_order_priority)
	return rows
func _selected_buyer_opportunity() -> Dictionary:
	var rows: Array[Dictionary]=_local_opportunities()
	for c: Dictionary in rows:
		if c.get("id")==selected_contract:return c
	return rows[0] if not rows.is_empty() else {}
func _buyer_label() -> String:
	var opportunity: Dictionary=_selected_buyer_opportunity()
	if not opportunity.is_empty():return _site_name(str(opportunity.get("buyer_site","")))
	var sales: Array[Dictionary]=_local_sales_orders()
	if not sales.is_empty():return _site_name(str(sales[0].get("buyer_site",""))) if not str(sales[0].get("buyer_site","")).is_empty() else "已成交居民买方"
	return "暂无已知买方"
func _buyer_sales_text() -> String:
	var sales: Array[Dictionary]=_local_sales_orders()
	if sales.is_empty():return "本城尚无已关联的本商号真实销售订单。"
	var lines: Array[String]=["本城真实买方与已有销售（本商号合法记录）："]
	for order: Dictionary in sales.slice(0,5):
		lines.append("%s · %s · 原锁价%s · 待发%s / 在途%s / 已交%s"%[_site_name(str(order.get("buyer_site",""))) if not str(order.get("buyer_site","")).is_empty() else "已成交居民买方",GOODS.get(order.get("good"),"商品"),order.get("price","未知"),order.get("pending",0),order.get("transit",0),order.get("delivered",0)])
	lines.append("销售额须以货站原收据与Ledger核验；历史买方不等于新的购买承诺。")
	return "\n".join(lines)
