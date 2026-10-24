extends Node2D
signal host_continuation_ready(context: Dictionary)
signal host_checkpoint_ready(context: Dictionary)
const Opening=preload("res://merchant/merchant_opening.gd")
const SupplyProjection=preload("res://merchant/merchant_supply_projection.gd")
const Runtime=preload("res://merchant/merchant_runtime.gd")
const GOODS={"all":"全部商品","grain":"粮食","beans":"豆类","fiber":"纤维","oil":"油料","bread":"面包","clothes":"衣服","soap":"肥皂","flour":"面粉"}
const PLACES={"place:paris":"巴黎","place:lyon":"里昂","place:marseille":"马赛"}
var returned_host_context: Dictionary={}
var external_host_context: Dictionary={}
var runtime: RefCounted
var snapshot: Dictionary={}
var view: Dictionary={}
var current_minute: int=0
var world_ready: bool=false
var busy: bool=true
var stepping: bool=false
var running: bool=false
var speed: int=1
var pulse: float=0.0
var queued_minutes: int=0
var close_requested: bool=false
var close_ack: bool=false
var save_requested: bool=false
var selected_place: String="place:paris"
var selected_site: String=Opening.SITE
var selected_good: String="all"
var selected_tab: int=0
var city_home: bool=true
var facilities: Array[Button]=[]
var home_goal: Button
var home_next: Button
var home_records: Button
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
var font: Font=preload("res://assets/fonts/map/SourceHanSerifCN-Regular.otf")
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
var confirm_detail: RichTextLabel
var identity_button: Button
var guide_text: RichTextLabel
var frame_histogram: Dictionary={}
var frame_count: int=0
var peak_memory_bytes: int=0
var guide: AcceptDialog
var guide_opened: bool=false
var cargo_buttons: Array[Button]=[]
var dialog: ConfirmationDialog

func _ready() -> void:
	get_tree().auto_accept_quit=false
	get_viewport().gui_embed_subwindows=true
	RenderingServer.set_default_clear_color(Color("132832"))
	header=_label(Vector2(20,8),Vector2(730,68),17)
	identity_button=_button("人物与入门",Vector2(760,12),Vector2(180,56),_show_guide)
	guide=AcceptDialog.new();guide.title="我的商贸生活";guide.dialog_autowrap=true;guide.min_size=Vector2i(790,390);guide.add_theme_font_override("font",font);guide.add_theme_font_size_override("font_size",19);add_child(guide)
	guide_text=RichTextLabel.new();guide_text.add_theme_font_override("normal_font",font);guide_text.add_theme_font_size_override("normal_font_size",18);guide_text.custom_minimum_size=Vector2(750,380);guide_text.scroll_active=true;guide.add_child(guide_text)
	guide.get_ok_button().text="明白了，自己选择";guide.get_ok_button().custom_minimum_size=Vector2(220,52)
	var places: Array[String]=["place:lyon","place:paris","place:marseille"]
	for i: int in range(3):
		var b: Button=_button(PLACES[places[i]],Vector2(65+i*310,93),Vector2(210,55),_select_place.bind(places[i]));map_buttons.append(b)
	route_hint=_label(Vector2(24,163),Vector2(912,34),14);route_hint.text="贸易路线示意 · 蓝点：本人所在地 · 金点：已有在途合同（不代表实时位置）"
	back_city=_button("← 城市",Vector2(20,204),Vector2(150,42),_return_city)
	section_select=_option(Vector2(180,204),Vector2(330,42))
	for title: String in ["市场 · 采购","仓库 · 资产与调拨","货站 · 合同运输","商号 · 消息账款","商号 · 补货委托","商号 · 行程营业","买方 · 城市供货"]:section_select.add_item(title)
	section_select.item_selected.connect(_set_tab)
	home_goal=_button("正在读取经营目标…",Vector2(20,138),Vector2(920,76),_open_supply)
	home_goal.add_theme_font_size_override("font_size",17)
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
	var titles: Array[String]=["开始","速度 1×","推进一天","保存","切换场景"]
	for i: int in range(5):buttons.append(_button(titles[i],Vector2(20+i*186,540),Vector2(178,44),_time_button.bind(i)))
	dialog=ConfirmationDialog.new();dialog.title="核对经营操作";dialog.dialog_autowrap=true;dialog.min_size=Vector2i(780,320);dialog.add_theme_font_override("font",font);dialog.add_theme_font_size_override("font_size",19);dialog.confirmed.connect(_confirm);dialog.canceled.connect(_cancel_preview);add_child(dialog)
	for b: Button in [dialog.get_ok_button(),dialog.get_cancel_button()]:
		b.custom_minimum_size=Vector2(150,50);b.add_theme_font_override("font",font);b.add_theme_font_size_override("font_size",20)
	dialog.get_ok_button().text="确认提交";dialog.get_cancel_button().text="取消返回"
	confirm_detail=RichTextLabel.new();confirm_detail.scroll_active=true;confirm_detail.add_theme_font_override("normal_font",font);confirm_detail.add_theme_font_size_override("normal_font_size",19);dialog.add_child(confirm_detail)
	quantity_minus=_button("−1",Vector2(550,204),Vector2(70,48),_adjust_quantity.bind(-1))
	quantity_plus=_button("＋1",Vector2(630,204),Vector2(70,48),_adjust_quantity.bind(1))
	for i: int in range(4):
		var cargo: Button=_button("",Vector2(20,312+i*38),Vector2(210,36),_inspect_cargo.bind(i));cargo.add_theme_font_size_override("font_size",14);cargo_buttons.append(cargo)
	get_viewport().size_changed.connect(_fit);_fit();_refresh();_start.call_deferred()

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
func _layout_controls() -> void:
	if dialog==null:return
	var w: float=layout_size.x
	var h: float=layout_size.y
	header.size.x=w-240;identity_button.position.x=w-210;notice.position.y=h-110;notice.size=Vector2(w-40,48)
	home_goal.size.x=w-270;home_records.position.x=w-240;home_records.size=Vector2(220,76);technical_toggle.position.x=w-240;home_next.position.y=h-163;home_next.size=Vector2(w-40,52)
	home_hint.size.x=w-50
	for i: int in range(buttons.size()):
		buttons[i].position=Vector2(20+i*(w-40)/5,h-54)
		buttons[i].size=Vector2((w-40)/5-8,48)
	for control: Control in [site_select,good_select,quantity,price,primary,row_select,secondary,batch,cash_floor,back_city,section_select]:control.size.y=48
	if not city_home:
		route_hint.visible=false
		for b: Button in map_buttons:b.position.y=80;b.size.y=48
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
	runtime=Runtime.new();var error: Error=runtime.start_external(external_host_context) if not external_host_context.is_empty() else runtime.start()
	if error!=OK:message="线程启动失败："+error_string(error);busy=false;_refresh()
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
	if close_ack and runtime.finished():
		runtime.join_finished();print("MERCHANT_SAFE_EXIT minute=",current_minute," slot=",snapshot.get("slot"))
		if not external_host_context.is_empty():
			host_continuation_ready.emit(returned_host_context.duplicate(true));queue_free()
		else:get_tree().quit()
		return
	if busy or stepping or not world_ready or close_requested or save_requested or dialog.visible or guide.visible:return
	if queued_minutes>0:stepping=runtime.submit("advance",{"minutes":mini(60,queued_minutes)})>=0
	elif running:
		pulse+=delta
		if pulse>=1.0/float(speed):pulse=0.0;stepping=runtime.submit("advance",{"minutes":60})>=0
func _receive(response: Dictionary) -> void:
	var kind: String=response["kind"]
	if response.get("fatal",false):world_ready=false;running=false;queued_minutes=0
	if not response.get("view",{}).is_empty():
		var previous_news: String=news[0] if not news.is_empty() else ""
		var previous_paid: int=int(observed_supply.get("paid",0))
		snapshot=response["view"];view=snapshot["firm"];current_minute=int(snapshot["minute"]);selected_site=str(snapshot["site"])
		if kind=="switch":observed_orders.clear();observed_prices.clear();observed_supply.clear();observed_opportunities.clear();selected_contract="";news.clear()
		_record_news(kind not in ["init","switch"])
		if kind=="advance":
			if not news.is_empty() and news[0]!=previous_news:message="经营变化："+news[0]
			var actual_paid: int=int(observed_supply.get("paid",0))
			if actual_paid>previous_paid:
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
			page_offset=0;offer_key="";order_key="";selected_good="all"
			message="已切换独立存档，时间暂停。" if response["ok"] else "未切换："+str(result)
		elif response["ok"]:
			message="受理 %s：数量 %s；%s"%[{"accept_supply_contract":"接受供货","submit_supply_batch":"分批供货","terminate_supply_contract":"终止供货","plan":"补货委托","travel":"本人行程","set_site_status":"营业变更","buy":"采购","quote":"报价","cancel":"撤单","transfer_goods":"调拨"}.get(kind,kind),str(result.get("quantity","按请求")),_reason(str(result.get("reason","")))]
			_add_news(message)
		else:message="未受理："+_reason(str(result.get("reason",result.get("error","未知"))))
	if response.get("result",{}).get("save_pending",false):
		_pause();message="内存操作已发生但尚未保存。请点保存重试，勿重发交易。 "+str(response["result"].get("message",""))
	_refresh()
	if kind=="init" and world_ready and not guide_opened:
		guide_opened=true;_show_guide.call_deferred()
	if kind=="observe" and pending_preview:pending_preview=false;_show_trade_preview()
func _send(kind: String,payload: Dictionary={}) -> void:
	if runtime==null or kind.is_empty() or (busy and kind not in ["save","close"]):return
	busy=runtime.submit(kind,payload)>=0
	message="请求处理中，地图仍可查看。" if busy else "未入队，请稍后重试。"
	if not busy:save_requested=false;close_requested=false;pending_preview=false
	_refresh()
func _pause() -> void:
	running=false;queued_minutes=0;pulse=0.0
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
	elif selected_tab==6 and index<snapshot.get("opportunities",[]).size():
		selected_contract=str(snapshot["opportunities"][index]["id"]);_pause();_observe();return
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
		_show_confirm("在%s给%s报价 %d。\n次日生效，同地点商品每天最多一次；原合同锁价不变。\n当前在库 %s，承诺 %s。售出不保证，不能预设利润。"%[_site_name(selected_site),GOODS[good],int(price.value),op.get("inventory",{}).get(good,0),op.get("committed_inventory",{}).get(good,0)])
	elif selected_tab==2:
		var order: Dictionary=_selected_order()
		if order.is_empty() or order.get("buyer")!=Opening.FIRM or int(order.get("pending",0))<=0:message="该合同没有可撤的未发货采购。";_refresh();return
		confirm_kind="cancel";confirm_payload={"order_id":order["id"]};_show_confirm("仅撤销所选%s合同尚未发出的 %s 件。\n在途与到期付款义务保留，预留释放由正式系统处理。"%[GOODS.get(order.get("good"),"商品"),order["pending"]])
	elif selected_tab==4:
		confirm_kind="plan";confirm_payload=_plan_payload(true)
		_show_confirm("委托自动补货 %s → %s：\n自由库存＋待入库目标%d，每日最多申请%d，含运费每件不超过%d，至少留现%d。\n从下一日开始，只选已知有效报价；扣除已预留货款运费及已知工资/借款/租约责任，逐笔交正式系统批准。\n这会持续产生真实采购承诺，直到你暂停；不保证售出或利润。"%[GOODS[confirm_payload["good"]],_site_name(selected_site),confirm_payload["target"],confirm_payload["batch"],confirm_payload["ceiling"],confirm_payload["floor"]])
	elif selected_tab==5:
		var trip: Dictionary=_travel_quote()
		if trip.is_empty():message="当前没有可用客运报价："+str(trip);_refresh();return
		confirm_kind="travel";confirm_payload={"destination_place_id":selected_place}
		_show_confirm("本人前往%s，个人账户支付票款%s，预计最少%s分钟。\n受座位/线路/工作预约约束，可能途中等待；没有取消旅程接口。\n商号仍可按已有权限经营；旅行不解锁商号未知货源。"%[PLACES[selected_place],trip.get("fare","?"),trip.get("minutes","?")])
	elif selected_tab==6:
		var c: Dictionary=snapshot.get("supply",{})
		if c.is_empty():message="切换场景可进入第4槽自主商贸；旧场景继续保留。";_refresh();return
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
	if not offer.get("can_order",false):message="当前不能采购："+_reason(str(offer.get("order_reason",offer.get("reason"))));_refresh();return
	confirm_kind="buy";confirm_payload=offer["request"].duplicate(true)
	var q: int=int(confirm_payload["quantity"]);var unit: int=int(offer["price"]);var freight: int=int(offer["freight_per_unit"])
	_show_confirm("%s · %s\n从 %s 运至 %s，申请 %d 件\n商品 %d + 运费 %d = 最高预留 %d %s\n路径 %s；当前可供 %s。实际受理量由库存、资金和运力决定，可能部分成交。\n只有实际交付才履行对应结算；不保证到货日期。"%[GOODS.get(offer["good"],offer["good"]),_site_name(str(offer["seller_site"])),PLACES.get(offer["from_place_id"],offer["from_place_id"]),_site_name(selected_site),q,q*unit,q*freight,q*(unit+freight),_currency(str(offer["denomination"])),("本地配送" if offer["from_place_id"]==offer["to_place_id"] else "城际货运"),offer["quantity"]])
func _secondary() -> void:
	if busy:return
	_pause()
	if selected_tab==6:
		var c: Dictionary=snapshot.get("supply",{})
		if c.get("status") not in ["ACCEPTED","PARTIAL"]:_observe();return
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
func _show_confirm(text: String) -> void:
	message="仅打开预览，尚未提交；请核对金额、期限与责任。"
	dialog.dialog_text="";confirm_detail.text=text;confirm_detail.scroll_to_line(0)
	dialog.popup_centered(Vector2i(mini(900,int(layout_size.x)-40),mini(480,int(layout_size.y)-40)))
	confirm_detail.position=Vector2(20,20);confirm_detail.size=Vector2(dialog.size.x-40,dialog.size.y-95)
	_refresh()
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
	if index==0:running=not(running or queued_minutes>0);queued_minutes=0;pulse=0.0;_refresh();return
	if index==1:speed=4 if speed==1 else 1;_refresh();return
	if busy:return
	match index:
		2:_pause();queued_minutes=1440
		3:_pause();save_requested=true;_send("save")
		4:
			_pause();confirm_kind="switch";var target: int=int(snapshot.get("slot",1))%4+1;confirm_payload={"slot":target}
			_show_confirm("先保存，再继续%s；只有无该槽时才新开。四槽完全独立，旧存档不迁移。\n第4槽继承第3槽有限真实开局资金、商品和运输条件；新增有限采购授权与公告信息延迟，不增发货币或商品。80粮大合同仍截止第11天00:00。\n可选现货贸易、等待或接单；不保证成交、完成或盈利。"%["原商号（槽1）","区域商贸（槽2）","巴黎限期供货（槽3）","自主商贸（槽4）"][target-1])
	_refresh()
func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_GO_BACK_REQUEST:
		if dialog!=null and dialog.visible:dialog.hide();_cancel_preview();return
		if guide!=null and guide.visible:guide.hide();return
		if not city_home:_return_city();return
	if what not in [NOTIFICATION_APPLICATION_PAUSED,NOTIFICATION_WM_CLOSE_REQUEST,NOTIFICATION_WM_GO_BACK_REQUEST]:return
	_pause()
	if runtime==null:return
	if runtime.finished():runtime.join_finished();get_tree().quit();return
	if close_requested:return
	close_requested=what!=NOTIFICATION_APPLICATION_PAUSED;save_requested=true
	_send("close" if close_requested else "save")
func _exit_tree() -> void:
	_write_performance()
	if runtime!=null and runtime.has_method("shutdown_and_join"):runtime.shutdown_and_join()
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
	return {"SUPPLY_ACCEPTED_FUNDED":"供货合同已接受，买方货款已预留", "SUPPLY_BATCH_DISPATCH_ACCEPTED":"本批现货已安排，待实际到货付款", "SUPPLY_ENDED":"供货合同已结束", "SUPPLY_TERMINATED_EXISTING_BATCHES_RETAINED":"未来责任已终止，旧运输继续", "PLAN_SAVED":"补货委托已保存","TRAVEL_STARTED":"客运行程已出发","OPERATING_CHANGE_QUEUED":"营业变更已排队，次日生效","NO_UNCOMMITTED_STOCK":"没有可自由出售的库存","NO_KNOWN_ROUTE":"没有已知可用路线","INSUFFICIENT_AVAILABLE_CASH":"可用经营资金不足","QUANTITY_EXCEEDS_CURRENT_OFFER":"申请量超过当前报价数量","ACCEPTED":"已受理","OFFER":"有效报价","FUTURE_GOODS_QUOTE_PUBLISHED":"报价次日生效","EXPIRED_QUOTE":"报价已过期，请刷新后重新确认","GOODS_QUOTE_ALREADY_POSTED_TODAY":"今日已报价或自动续报，明日再调价","NO_MANAGED_GOODS_QUOTE_AUTHORITY":"报价授权范围/有效期/价格上限不满足","NO_TRANSFER_STOCK_CASH_OR_CAPACITY":"调拨库存、资金或运力不足","NOT_READY":"未到约定发运日","CUMULATIVE_BUDGET_OR_WINDOW":"累计预算或窗口不允许新承诺"}.get(code,code)

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
		var fact: Dictionary={"status":contract.get("status"),"paid":contract.get("paid",0),"ontime":contract.get("ontime",0)}
		if announce and not observed_supply.is_empty() and fact!=observed_supply:
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
	var slot: int=int(snapshot.get("slot",1))
	header.text="经济经营 1.0候选 · 第%d天 %02d:%02d · %s\n本人在%s · 个人可用%s ｜ 浏览%s（不会移动人物）\n商号可用%s / 预留%s · 回款归商号，不是个人收入"%[current_minute/1440+1,(current_minute/60)%24,current_minute%60,"运行%d×"%speed if running else "推进中" if queued_minutes>0 else "暂停",_person_location(),_known(snapshot.get("personal_available")),PLACES[selected_place],int(view.get("cash",0))-int(view.get("reserved",0)),view.get("reserved",0)]
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
	price.visible=selected_tab in [1,4];quantity.visible=selected_tab in [0,1,4,6];good_select.visible=selected_tab in [0,1,4]
	quantity.prefix="目标 " if selected_tab==4 else "数量 ";price.prefix="到岸上限 " if selected_tab==4 else "单价 "
	batch.visible=selected_tab==4;cash_floor.visible=selected_tab==4;row_select.visible=selected_tab!=4
	batch.editable=not busy;cash_floor.editable=not busy
	row_select.clear();display_offers.clear();display_orders.clear()
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
		text="%s · 实际存货地点 %s\n%s\n当前%s售价 %s；新价次日生效。\n授权：%s；历史成交不改价。"%[_site_name(selected_site),PLACES.get(op.get("stock_place_id"),"?"),"\n".join(lines),GOODS.get(good,good),quotation.get("price","未授权"),_management_label()]
		row_select.add_item("报价商品："+GOODS.get(good,good)+"；调拨目的地："+("另一商号仓" if slot>=2 else "无"))
		primary.text="报价预览";secondary.text="调拨至另一仓"
	elif selected_tab==2:
		var sorted_orders: Array=view.get("orders",[])+view.get("sales_orders",[])
		sorted_orders.sort_custom(_order_priority)
		for order: Dictionary in sorted_orders:
			if display_orders.any(func(row: Dictionary)->bool:return row["id"]==order["id"]):continue
			display_orders.append(order)
			row_select.add_item("%s %s %s · 待%s/途%s/到%s"%["第%d笔"%(display_orders.size()),"售" if order.get("seller")==Opening.FIRM and order.get("kind")=="SALE" else "调" if order.get("kind")=="TRANSFER" else "购",GOODS.get(order.get("good"),order.get("good")),order.get("pending",0),order.get("transit",0),order.get("delivered",0)])
		var order: Dictionary=_selected_order()
		if not order.is_empty():
			order_key=str(order["id"]);row_select.select(display_orders.find(order))
			text="%s → %s\n锁定货款%s / 运费%s；本订单买方预留%s\n已交付货款%s / 运费%s；待发原因：%s\n"%[_site_name(str(order.get("seller_site"))),_site_name(str(order.get("buyer_site"))),order.get("locked_goods_amount",0),order.get("locked_freight_amount",0),order.get("reserved_amount",0),order.get("paid_goods_amount",0),order.get("paid_freight_amount",0),_reason(str(order.get("pending_waiting_reason","")))]
			for cargo: Dictionary in order.get("shipments",[]):text+="%s ×%s：%s，%s → %s，%s\n"%["货批",cargo.get("quantity"),cargo.get("stage"),PLACES.get(cargo.get("from_place_id"),"?"),PLACES.get(cargo.get("to_place_id"),"?"),_reason(str(cargo.get("waiting_reason","")))]
			text+="最早到达：%s（非保证）。撤销只影响未发货部分。"%("未知" if order.get("earliest_arrival_day")==null else "第%d天"%(int(order["earliest_arrival_day"])+1))
		else:text="尚无商号合同。采购、销售、调拨都使用同一履约系统。"
		primary.text="撤销未发货";secondary.text="刷新履约"
	elif selected_tab==4:
		var key: String=selected_site+"|"+("grain" if selected_good=="all" else selected_good)
		var plan: Dictionary=snapshot.get("plans",{}).get("plans",{}).get(key,{})
		text="当前委托：%s\n%s\n决策只选已知报价，按含运费价格排序，每计划每日最多一笔。库存口径扣销售承诺并计入待入库。\n编辑上方目标/到岸单价，第二行每日批量/留存现金，确认才生效。"%["未设定" if plan.is_empty() else "开启" if plan["enabled"] else "暂停",("目标%s / 每日批量%s / 到岸上限%s / 留现%s\n下次复核第%s日；%s"%[plan["target"],plan["batch"],plan["ceiling"],plan["floor"],int(plan["next_day"])+1,plan["status"]]) if not plan.is_empty() else "尚未开立。所有委托默认关闭。"]
		primary.text="确认补货委托";secondary.text="暂停该商品委托"
	elif selected_tab==5:
		var trip: Dictionary=_travel_quote()
		row_select.add_item("目的地："+PLACES[selected_place]+" · 票款由人物个人账户支付")
		var journey: Dictionary=snapshot.get("travel",{})
		var journey_text: String="暂无行程" if journey.is_empty() else "%s → %s · %s · 尚余%s分钟"%[PLACES.get(journey.get("origin"),journey.get("origin","?")),PLACES.get(journey.get("destination"),journey.get("destination","?")),{"TRAVELLING":"途中","ARRIVED":"已到达","BLOCKED":"等待通行"}.get(journey.get("status"),journey.get("status","?")),journey.get("remaining_minutes","?")]
		text="个人资金%s · 本人行程：%s\n所选目的地：%s\n当前仓库新业务：%s；点击右侧可请求次日暂停/恢复。\n经营待生效：%s"%[_known(snapshot.get("personal_available")),journey_text,"无可用客运报价" if trip.is_empty() else "%s · 票款%s · 最少%s分钟"%[PLACES[selected_place],trip["fare"],trip["minutes"]],"接受" if _operation().get("site_status",{}).get("accepting_business",true) else "暂停","；".join(_pending_changes())]
		primary.text="前往地图所选地";secondary.text="暂停 / 恢复新业务"
	elif selected_tab==6:
		var c: Dictionary=snapshot.get("supply",{})
		for option: Dictionary in snapshot.get("opportunities",[]):
			row_select.add_item("%s · %s × %s · %s"%[_site_name(option["buyer_site"]),GOODS.get(option["good"],option["good"]),option["quantity"],_supply_status(option["status"])])
			if option["id"]==c.get("id"):row_select.select(row_select.item_count-1)
		if c.is_empty():text="商业机会在第3/4槽；可先继续现货贸易。未接受任何合同不会扣钱或违约。"
		elif not c.has("accept_action") and c.get("status")!="RECRUITING":
			text="%s · %s\n这项机会当前不能接受，未为你创建供货责任。\n可选其他已知机会、查看现货市场或等待新消息。"%[_site_name(c["buyer_site"]),_supply_status(c["status"])]
		elif not c.has("accept_action"):
			text="%s · %s\n%s × %s，单价%s / 总货款%s（未到账）\n交至%s；截止第%d天00:00。\n%s\n可暂不接受。点接受先核对完整资金、运费与责任。"%[_site_name(c["buyer_site"]),_supply_status(c["status"]),GOODS.get(c["good"],c["good"]),c["quantity"],c["price"],int(c["quantity"])*int(c["price"]),_site_name(c["buyer_site"]),int(c["deadline"])/1440+1,SupplyProjection.project(c,view,current_minute).get("short_risk","")]
		else:
			var left: int=maxi(0,int(c["deadline"])-current_minute)
			text="买方%s · %s · %s%s，锁价%s\n收货%s；剩余%d日%d时；按时%s，迟到%s，待发/在途%s\n已收货款%s；实际可交库存%s，尚未安排%s。\n详情与批次继续保留；终止仅解除未来未安排部分，已受理运输仍执行。\n%s"%[_site_name(c["buyer_site"]),_supply_status(c["status"]),c["quantity"],GOODS.get(c["good"],c["good"]),c["price"],_site_name(c["buyer_site"]),left/1440,(left/60)%24,c["ontime"],c["late"],c["in_transit"],c["paid"],c["free_stock"],c["unallocated"],SupplyProjection.project(c,view,current_minute).get("short_risk","")]
		primary.text="接受所选合同" if c.get("status")=="RECRUITING" else "提交所选合同现货" if c.get("status") in ["ACCEPTED","PARTIAL"] else "当前无新供货操作"
		secondary.text="终止未来供货责任"
	else:
		row_select.add_item("本次会话消息；依据自身合同与已知报价，不读取全市场秘密")
		var review: Dictionary=snapshot.get("trade_review",{})
		text="经营回顾（自本局开局）\n实际买入到仓：%s；当前仍在仓：%s\n已付货款%s / 已付运费%s / 已收货款%s\n已知交易现金差额%s；只含商品与货运，不是完整净利润，库存不是已实现亏损。\n未结采购货款%s / 未结销售货款%s；仍履行供货合同%s份。\n\n%s"%[_goods_summary(review.get("delivered_purchases",{})),_goods_summary(review.get("current_inventory",{})),_money(review.get("goods_paid",{})),_money(review.get("freight_paid",{})),_money(review.get("sales_received",{})),_money(review.get("known_trade_cash_difference",{})),review.get("unsettled_goods_purchases",0),review.get("unsettled_goods_sales",0),review.get("open_supply_contracts",[]).size(),"\n".join(news) if not news.is_empty() else "尚无新变化；订单与账本已从正式存档恢复。"]
		primary.text="更新观察";secondary.text="刷新账款"
	detail.position.x=20 if selected_tab==6 else 240
	detail.size.x=920 if selected_tab==6 else 700
	detail.size.y=135
	if selected_tab==6:detail.position.y=305;detail.size.y=177
	else:detail.position.y=352
	detail.text=text;notice.text=message
	technical_toggle.text="收起技术详情" if show_technical else "展开技术详情"
	primary.disabled=busy or not world_ready;secondary.disabled=busy or not world_ready
	row_select.disabled=busy or not world_ready or selected_tab not in [0,2,6] or row_select.item_count==0
	previous.visible=selected_tab==0;next_page.visible=selected_tab==0
	previous.disabled=busy or page_offset==0;next_page.disabled=busy or page_offset+16>=int(business.get("offer_total",0))
	buttons[0].text="暂停" if running or queued_minutes>0 else "开始";buttons[1].text="速度%d×"%speed
	for b: Button in buttons:b.disabled=busy or not world_ready or close_requested or save_requested
	buttons[0].disabled=not world_ready or close_requested or save_requested
	buttons[1].disabled=not world_ready or close_requested
	if snapshot.get("save_pending",false):
		primary.disabled=true;secondary.disabled=true
		for index: int in [0,2,4]:buttons[index].disabled=true
	if not external_host_context.is_empty():
		for index: int in [0,1,2,4]:buttons[index].disabled=true
	if not world_ready:header.text="经济经营 1.0候选 · 正在准备世界，请稍候…"
	_refresh_city();_layout_controls();_refresh_cargo()
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
	_set_tab(6)
func _enter_facility(index: int) -> void:
	var target: int=[0,1,2,3,6][index]
	if index==1:
		for op: Dictionary in view.get("operations",[]):
			if op.get("stock_place_id")==selected_place:
				selected_site=str(op["site_id"]);_pause();_observe();break
	_set_tab(target)
func _next_action() -> void:
	if busy or not world_ready:return
	var c: Dictionary=snapshot.get("supply",{})
	var p: Dictionary=SupplyProjection.project(c,view,current_minute)
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
	if not city_home and selected_tab==3:detail.text=_feedback_text()+"\n\n"+detail.text+"\n\n"+_cost_text()
	if not city_home and show_technical:detail.text+="\n\n技术核验（原业务引用）\n"+_technical_text()
	city_state=_project_city()
	var c: Dictionary=snapshot.get("supply",{})
	var p: Dictionary=SupplyProjection.project(c,view,current_minute)
	var has_local_warehouse: bool=false
	for op: Dictionary in view.get("operations",[]):
		if op.get("stock_place_id")==selected_place:has_local_warehouse=true
	for i: int in range(facilities.size()):
		facilities[i].visible=city_home and not (i==1 and not has_local_warehouse) and not (i==4 and (selected_place!="place:paris" or c.is_empty()))
		facilities[i].disabled=not world_ready or (i==1 and not has_local_warehouse) or (i==4 and (selected_place!="place:paris" or c.is_empty()))
	facilities[1].text=""
	facilities[4].text=""
	home_hint.text="浏览"+PLACES[selected_place]+" · "+_latest_feedback()
	home_goal.disabled=not world_ready;home_next.disabled=not world_ready
	var count: int=snapshot.get("opportunities",[]).size()
	if c.is_empty():
		home_goal.text="自主经营 · 采购、运输、出售\n未接单也可以继续贸易"
		home_next.text="查看已知现货贸易机会";return
	home_goal.text="机会%s份 · %s × %s · %s\n交至%s · %s / 到账%s%s"%[count,GOODS.get(c["good"],c["good"]),c["quantity"],_supply_status(c["status"]),_site_name(str(c.get("buyer_site","未知"))),_home_supply_stock(c),c.get("paid",0),(" · 截止第%d天"%(int(c["deadline"])/1440+1)) if c.get("status") in ["RECRUITING","ACCEPTED","PARTIAL"] else ""]
	home_next.text="下一步："+str(p.get("next_action","查看机会"))
	if selected_tab==6 and not city_home and c.has("accept_action"):
		detail.text+="\n"+str(p.get("arrival_summary","到达下限未知"))
	if selected_tab==6 and not city_home:
		primary.disabled=primary.disabled or (c.get("status")=="RECRUITING" and not c.get("ready",false)) or (c.get("status")!="RECRUITING" and (c.get("status") not in ["ACCEPTED","PARTIAL"] or int(c.get("free_stock",0))<=0 or int(c.get("unallocated",0))<=0))
		secondary.disabled=secondary.disabled or c.get("status") not in ["ACCEPTED","PARTIAL"]

func _facility_rect(index: int) -> Rect2:
	return [Rect2(35,248,150,120),Rect2(215,320,160,112),Rect2(400,245,175,115),Rect2(595,319,145,113),Rect2(760,248,165,122)][index]
func _city_label(text: String,pos: Vector2,width: float=160) -> void:
	draw_string(font,pos,text,HORIZONTAL_ALIGNMENT_CENTER,width,17,Color("f0e8cb"))
func _window_grid(x: float,y: float,columns: int,rows: int) -> void:
	for col: int in range(columns):
		for row: int in range(rows):
			draw_rect(Rect2(x+col*27,y+row*25,13,15),Color("e7c97e"))
			draw_line(Vector2(x+col*27+6,y+row*25),Vector2(x+col*27+6,y+row*25+15),Color("4c625c"),2)
func _draw_city_space() -> void:
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
		_city_label("合同买方 · 验收",Vector2(760,365),165)
	else:
		# Unowned waterfront/park space, not an invented buyer facility.
		draw_rect(Rect2(790,267,120,55),Color("4d7275"))
		for y: int in [279,295,310]:draw_line(Vector2(805,y),Vector2(894,y),Color("789894"),2)
		_city_label("暂无已知供货关系",Vector2(755,357),175)

func _draw_city_status() -> void:
	_draw_status_badge("可执行报价 %s"%city_state.get("available_offers",0),Vector2(35,275),150)
	if facilities[1].visible:
		_draw_status_badge("总在库%s / 自由%s"%[city_state.get("stock",0),city_state.get("free",0)],Vector2(215,346),160)
		_draw_status_badge("承诺%s / 待入%s"%[city_state.get("committed",0),city_state.get("incoming",0)],Vector2(215,319),160)
	_draw_status_badge("全号待发%s / 途%s"%[city_state.get("pending",0),city_state.get("transit",0)],Vector2(400,245),175)
	if int(city_state.get("transit",0))>0:
		draw_rect(Rect2(540,323,32,12),Color("e0bc73"));draw_circle(Vector2(548,337),4,Color("182b30"));draw_circle(Vector2(566,337),4,Color("182b30"))
	_draw_status_badge("可用%s / 预留%s"%[int(view.get("cash",0))-int(view.get("reserved",0)),view.get("reserved",0)],Vector2(585,317),170)
	if facilities[4].visible:
		var c: Dictionary=snapshot.get("supply",{})
		_draw_status_badge("验收%s / 到账%s"%[int(c.get("ontime",0))+int(c.get("late",0)),c.get("paid",0)],Vector2(760,248),165)
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
	var cheapest: int=-1
	if sources.is_empty():lines.append("尚无已知供应报价；新增采购成本和到仓时间未知。")
	for q: Dictionary in sources.slice(0,4):
		if q.get("price")!=null and q.get("freight_per_unit")!=null and int(q.get("quantity",0))>0:
			var landed: int=int(q["price"])+int(q["freight_per_unit"])
			cheapest=landed if cheapest<0 else mini(cheapest,landed)
		lines.append("已知%s：货价%s＋运费%s，可执行%s，到仓下限%s。"%[_site_name(str(q.get("seller_site",""))),_known(q.get("price")),_known(q.get("freight_per_unit")),q.get("quantity",0),"未知" if q.get("earliest_arrival_day")==null else "第%d天"%(int(q["earliest_arrival_day"])+1)])
	if cheapest>=0:
		lines.append("按当前已知最低到岸单价%s估算，缺口采购约需%s；报价量/运力未必覆盖，非预算或未来保证。"%[cheapest,maxi(0,int(c["quantity"])-free)*cheapest])
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
	for event: Dictionary in feedback.get("events",[]).slice(0,12):lines.append(str(event.get("text","")))
	if feedback.get("events",[]).is_empty():lines.append("暂无新增记录；下方保留自身交易账款。")
	return "\n".join(lines)
func _technical_text() -> String:
	var lines: Array[String]=["存档槽：%s；游戏分钟：%s；仓库：%s"%[snapshot.get("slot"),current_minute,selected_site],"正式人物："+str(snapshot.get("person_id","未知")),"商号："+str(snapshot.get("identity",{}).get("firm_id","未知")),"管理来源："+str(snapshot.get("identity",{}).get("management_basis","未知")),"底层地点："+str(snapshot.get("player_place","未知"))+"；正式旅程："+str(snapshot.get("travel",{}))]
	if selected_tab==6:
		var c: Dictionary=snapshot.get("supply",{})
		for key: String in ["id","buyer","buyer_site","source","accept_action","batches"]:
			if c.has(key):lines.append(key+"："+str(c[key]))
	elif selected_tab==2:
		var order: Dictionary=_selected_order()
		for key: String in ["id","buyer","seller","seller_site","buyer_site","shipments","earliest_arrival_day"]:
			if order.has(key):lines.append(key+"："+str(order[key]))
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
func _show_guide() -> void:
	_pause()
	var identity: Dictionary=snapshot.get("identity",{})
	var review: Dictionary=snapshot.get("trade_review",{})
	var personal_id: String="当前受控商人（正式身份见经营页技术详情）"
	guide_text.text="你控制：%s\n实际所在地：%s；浏览：%s。地图按钮只看城市，出行需在行程页付个人车票。\n个人可用：%s；商号可用：%s；商号预留：%s。公司资产不能当作你的私人收入。\n管理关系：%s\n\n%s\n\n未结：采购货款%s / 销售应收%s / 供货合同%s份。\n自由库存才能新出售或供货；在途货未入库，验收后才收款。\n你可以选择小批采购、大批采购或等待；预览货款＋运费＋预留后再决定。机会可能失效，回市场找新报价。没有新手赠品或保底利润。\n随时点右上角重看；关闭提示不会执行交易。"%[personal_id,_person_location(),PLACES[selected_place],_known(snapshot.get("personal_available")),int(view.get("cash",0))-int(view.get("reserved",0)),view.get("reserved",0),_management_label()+"\n"+_personal_responsibilities(),_guide_next(),review.get("unsettled_goods_purchases",0),review.get("unsettled_goods_sales",0),review.get("open_supply_contracts",[]).size()]
	guide.popup_centered(Vector2i(int(minf(layout_size.x-40,900)),470))
func _guide_next() -> String:
	if int(city_state.get("transit",0))+int(city_state.get("pending",0))>0:return "当前建议：货站有未结运输，先看货物在哪里与等待原因，再决定是否继续采购。"
	if int(city_state.get("free",0))>0:return "当前建议：仓库有自由货物。点货箱核对地点、已承诺数量，再决定报价出售、合同供货或等待。"
	return "当前建议：先看市场已知报价，或买方的真实采购机会。接受合同会留下责任，可以暂不接受。"
func _cargo_rows() -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	var op: Dictionary=_operation()
	for good: String in op.get("inventory",{}):
		if int(op["inventory"][good])+int(op.get("incoming",{}).get(good,0))>0:result.append({"good":good,"stock":op["inventory"][good],"free":op.get("free_inventory",{}).get(good,0)})
	return result
func _refresh_cargo() -> void:
	var rows: Array[Dictionary]=_cargo_rows()
	for i: int in range(cargo_buttons.size()):
		cargo_buttons[i].visible=not city_home and selected_tab==1 and i<rows.size()
		cargo_buttons[i].disabled=busy or not world_ready
		if i<rows.size():cargo_buttons[i].text="▣ %s 在库%s / 可用%s"%[GOODS.get(rows[i]["good"],rows[i]["good"]),rows[i]["stock"],rows[i]["free"]]
func _inspect_cargo(index: int) -> void:
	var rows: Array[Dictionary]=_cargo_rows()
	if index>=rows.size() or busy:return
	selected_good=str(rows[index]["good"]);_refresh()
	message="%s：可报价出售；有对应合同可到买方供货，也可调拨或等待。所有动作仍核验自由库存与地点。"%GOODS.get(selected_good,selected_good);notice.text=message

func _write_performance() -> void:
	var bins: Array=frame_histogram.keys();bins.sort()
	var seen: int=0;var p95: int=0
	for bucket: int in bins:
		seen+=int(frame_histogram[bucket])
		if seen>=int(ceil(frame_count*0.95)):p95=bucket;break
	var sample: Dictionary={"platform":OS.get_name(),"frames":frame_count,"frame_p95_ms_bucket":p95,"frame_max_us":frame_max_us,"worker_max_us":worker_max_us,"worker_by_kind":worker_by_kind,"main_refresh_max_us":main_refresh_max_us,"peak_static_memory_bytes":peak_memory_bytes,"minute":current_minute,"note":"Includes loading, pauses and UI; desktop results are not Android device measurements."}
	var file: FileAccess=FileAccess.open("user://merchant_10_performance.json",FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(sample,"  "));file.close()
	print("MERCHANT_10_PERFORMANCE ",JSON.stringify(sample))

# Caller configures this before adding the scene to the tree. No WorldState crosses UI.
func enter_host_context(context: Dictionary) -> Error:
	if runtime!=null or not Runtime._plain(context) or context.is_empty():return ERR_INVALID_PARAMETER
	external_host_context=context.duplicate(true)
	return OK

func leave_host_context() -> void:
	if external_host_context.is_empty() or runtime==null or close_requested:return
	_pause();close_requested=true;save_requested=true;_send("close")

func _cost_text() -> String:
	var finance: Dictionary=snapshot.get("business",{}).get("finance",{})
	var costs: Dictionary=finance.get("direct_costs",{})
	var lines: Array[String]=["取得成本与经营责任"]
	if not costs.get("enabled",false):lines.append("成本资料未启用或不足，不能计算完整净利润。")
	else:
		for good: String in costs.get("inventory",{}):
			var row: Dictionary=costs["inventory"][good]
			lines.append("%s：持有%s，已知取得成本%s；成本未知数量%s"%[GOODS.get(good,good),row.get("owned_quantity",0),_money(row.get("known_cost",{})),row.get("unknown_cost_quantity",0)])
		lines.append("最近窗口自第%s日：已知售出成本%s / 可比交易贡献%s；未知成本销售%s笔。仅已知直接成本，不是净利润。"%[int(finance.get("window_start_day",0))+1,_money(costs.get("sold_known_cost",{})),_money(costs.get("contribution",{})),costs.get("unknown_sales",0)])
	lines.append("实际未付工资%s；贷款、租约及其他责任以原正式业务明细为准。"%_money(finance.get("wages_unpaid",{})))
	return "\n".join(lines)

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
