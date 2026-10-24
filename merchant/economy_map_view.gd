extends Control
## Economy content over the real synchronized WWO map. No economic world owner.
signal refresh_requested
signal back_requested
signal business_requested(place_id: String, site_id: String)
signal research_subject_requested(firm_id: String)
const Catalog = preload("res://scripts/vnext/spatial/spatial_catalog.gd")
const Globe = preload("res://shared/wwo_map/scripts/presentation/map/globe_projection.gd")
const Foundation = preload("res://merchant/wwo_map_foundation.tscn")
const GOODS = {"grain":"粮食", "bread":"面包", "flour":"面粉", "beans":"豆类", "fiber":"纤维", "oil":"油料", "clothes":"衣服", "soap":"肥皂", "building_material":"建材", "production_tool":"生产工具", "machine":"机器"}
const OWN = Color("67dbc1")
const CONTRACT = Color("f1bf72")
const BACKGROUND = Color("71899c")
const FIRM_NAMES={"firm:merchant_prototype":"本商号","firm:regional_food":"食品厂","firm:regional_upstream":"里昂上游企业","firm:regional_textile":"纺织企业","firm:regional_household":"马赛日用品厂"}
var catalog = Catalog.new()
var snapshot: Dictionary = {}
var network: Dictionary = {}
var contacts: Dictionary = {}
var selected_good: String = "all"
var show_contacts: bool = false
var show_received_flows: bool = true
var places: Dictionary = {}
var unlocated: Array[String] = []
var selected_place: String = "place:paris"
var selected_order: String = ""
var show_history: bool = false
var business_enabled: bool = false
var _hits: Dictionary = {}
var _edge_hits: Array[Dictionary] = []
var map_base: Control
var canvas: Control
var heading: Label
var status: Label
var details: RichTextLabel
var place_select: OptionButton
var order_select: OptionButton
var technical: CheckButton
var business_button: Button
var side: PanelContainer
var research_row: HBoxContainer
var research_select: OptionButton
var _accept_selection: bool = false

class EconomyOverlay extends Control:
	var presenter
	func _draw() -> void: presenter.draw_economy(self)

func _ready() -> void:
	var theme_value := Theme.new()
	var face: Font = preload("res://assets/fonts/map/HomeSans.otf").duplicate()
	face.fallbacks = [preload("res://assets/fonts/map/SourceHanSerifCN-Regular.otf")]
	theme_value.default_font=face; theme_value.default_font_size=16; theme=theme_value
	map_base=Foundation.instantiate(); add_child(map_base)
	canvas=EconomyOverlay.new(); canvas.presenter=self
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter=Control.MOUSE_FILTER_IGNORE; canvas.clip_contents=true; add_child(canvas)
	map_base.map_ready.connect(func():
		_accept_selection=true
		map_base.renderer.gui_input.connect(_map_input)
		canvas.queue_redraw())
	map_base.place_selected.connect(func(id: String):
		if _accept_selection and places.has(id): select_place(id))
	map_base.controller.view_changed.connect(func(): canvas.queue_redraw())
	canvas.resized.connect(func(): canvas.queue_redraw())
	var top := VBoxContainer.new(); top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left=12; top.offset_top=10; top.offset_right=-12; add_child(top)
	var toolbar := HBoxContainer.new(); top.add_child(toolbar)
	_button(toolbar,"← 经营 / 返回",func(): back_requested.emit())
	_button(toolbar,"巴黎",func(): focus_place("place:paris"))
	_button(toolbar,"里昂",func(): focus_place("place:lyon"))
	_button(toolbar,"全球",func(): map_base.focus_place(""))
	_button(toolbar,"区域",func(): map_base.focus_region(selected_place))
	_button(toolbar,"刷新观察",func(): refresh_requested.emit())
	var history := CheckButton.new(); history.text="历史关系"; toolbar.add_child(history)
	history.toggled.connect(func(on: bool): show_history=on; canvas.queue_redraw())
	_button(toolbar,"地点 / 订单",func(): side.visible=not side.visible)
	var modes := OptionButton.new(); modes.add_item("经济视角 · 地理底图"); modes.add_item("经济视角 · 历史政治参考")
	toolbar.add_child(modes); modes.item_selected.connect(func(index: int): map_base.controller.set_map_mode("geographic" if index==0 else "political"))
	var filters := HBoxContainer.new(); top.add_child(filters)
	var goods := OptionButton.new(); goods.add_item("全部商品"); goods.set_item_metadata(0,"all")
	for good: String in GOODS:
		goods.add_item(GOODS[good]); goods.set_item_metadata(goods.item_count-1,good)
	filters.add_child(goods)
	goods.item_selected.connect(func(index: int): selected_good=str(goods.get_item_metadata(index)); _detail(); canvas.queue_redraw())
	var candidates := CheckButton.new(); candidates.text="已知供应联系"; filters.add_child(candidates)
	candidates.toggled.connect(func(on: bool): show_contacts=on; canvas.queue_redraw())
	var delivered_flows:=CheckButton.new();delivered_flows.text="近7日到货联系";delivered_flows.button_pressed=true;filters.add_child(delivered_flows)
	delivered_flows.toggled.connect(func(on: bool):show_received_flows=on;canvas.queue_redraw())
	var coverage := Label.new(); coverage.text="圆环：观察主体近7日该商品实际到货；不划定腹地";coverage.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;coverage.size_flags_horizontal=Control.SIZE_EXPAND_FILL;filters.add_child(coverage)
	research_row=HBoxContainer.new();top.add_child(research_row)
	var research_label:=Label.new();research_label.text="隔离研究视角";research_row.add_child(research_label)
	research_select=OptionButton.new();research_row.add_child(research_select)
	research_select.item_selected.connect(func(index: int):research_subject_requested.emit(str(research_select.get_item_metadata(index))))
	var research_note:=Label.new();research_note.text="只改变观察，不改变经理或授权";research_row.add_child(research_note)
	research_row.hide()
	heading=Label.new(); heading.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; top.add_child(heading)
	side=PanelContainer.new(); side.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	side.anchor_top=0.18; side.anchor_bottom=0.92; side.offset_left=-354; side.offset_right=-12; add_child(side)
	var column := VBoxContainer.new(); column.custom_minimum_size.x=330; side.add_child(column)
	_button(column,"收起详情 ×",func(): side.hide())
	place_select=OptionButton.new(); place_select.fit_to_longest_item=false; column.add_child(place_select)
	place_select.item_selected.connect(func(index: int): select_place(str(place_select.get_item_metadata(index))))
	order_select=OptionButton.new(); order_select.fit_to_longest_item=false; column.add_child(order_select)
	order_select.item_selected.connect(func(index: int): select_order(str(order_select.get_item_metadata(index))))
	technical=CheckButton.new(); technical.text="展开原始引用与来源"; column.add_child(technical)
	technical.toggled.connect(func(_on: bool): _detail())
	details=RichTextLabel.new(); details.size_flags_vertical=Control.SIZE_EXPAND_FILL; details.selection_enabled=true; column.add_child(details)
	business_button=_button(column,"进入原经营详情",_business); business_button.visible=business_enabled
	side.hide()
	status=Label.new(); status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	status.offset_left=12; status.offset_top=-90; status.offset_right=-12; status.offset_bottom=-20
	status.add_theme_font_size_override("font_size",14)
	status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; status.mouse_filter=Control.MOUSE_FILTER_IGNORE; add_child(status)
	if catalog.load_legacy_world_map():
		for row: Dictionary in catalog.cities()+catalog.ports(): places[row.place_id]=row
	else: status.text="地理 Catalog 读取失败："+str(catalog.errors())
	_rebuild()

func _rebuild() -> void:
	unlocated.clear()
	for id: String in network.get("nodes",{}):
		if not _located(id):unlocated.append(id)
		elif not places.has(id):places[id]=catalog.get_place(id)
	for id: String in contacts.get("nodes",{}):
		if not _located(id):
			if id not in unlocated:unlocated.append(id)
		elif not places.has(id):places[id]=catalog.get_place(id)
	place_select.clear()
	var ids: Array=network.get("nodes",{}).keys()
	for id: String in contacts.get("nodes",{}):
		if id not in ids:ids.append(id)
	for id: String in places:
		if id not in ids:ids.append(id)
	for id: String in ids:
		place_select.add_item(place_name(id)+(" · 未定位" if id in unlocated else " · 自有仓" if not network.get("nodes",{}).get(id,{}).get("known_own_sites",[]).is_empty() else " · 合同相关" if network.get("nodes",{}).has(id) else " · 已知供应" if contacts.get("nodes",{}).has(id) else " · 地理背景"))
		place_select.set_item_metadata(place_select.item_count-1,id)
		if id==selected_place:place_select.select(place_select.item_count-1)
	order_select.clear(); order_select.add_item("选择订单（含历史）"); order_select.set_item_metadata(0,"")
	for id: String in network.get("edges",{}):
		var edge: Dictionary=network.edges[id]
		order_select.add_item("%s · %s · %s → %s"%[id,_edge_status(edge),place_name(edge.from_node),place_name(edge.to_node)])
		order_select.set_item_metadata(order_select.item_count-1,id)
		if id==selected_order:order_select.select(order_select.item_count-1)
	if not network.get("edges",{}).has(selected_order):selected_order=""
	var minute: int=int(snapshot.get("minute",0))
	research_row.visible=not snapshot.get("research_subjects",[]).is_empty()
	research_select.clear()
	for subject: Dictionary in snapshot.get("research_subjects",[]):
		research_select.add_item(subject.label);research_select.set_item_metadata(research_select.item_count-1,subject.id)
		if subject.id==snapshot.get("research_subject",""):research_select.select(research_select.item_count-1)
	var firm_id: String=str(snapshot.get("identity",{}).get("firm_id","尚未加载经济世界"))
	heading.text="WWO 经济地图 · 槽 %s · %s · 第%d天 %02d:%02d%s"%[str(snapshot.get("slot","未加载")),FIRM_NAMES.get(firm_id,firm_id),minute/1440+1,(minute/60)%24,minute%60," · 保存待确认" if snapshot.get("save_pending",false) else ""]
	heading.text+="\n世界配置：%s · %s"%[snapshot.get("world_case","尚未加载"),"原验证证据回放 · 非实时" if snapshot.get("map_replay",false) else "只读观察" if snapshot.get("observer_only",false) else "同一商号 Runtime"]
	if snapshot.get("network_experiment",false):heading.text=heading.text.replace("槽 0","独立开发世界（无存档槽）")
	if not str(snapshot.get("experiment_condition","")).is_empty():heading.text+=" · 条件 "+str(snapshot.experiment_condition)
	if snapshot.get("research_only",false):heading.text+="\n开发者研究观察 · 非玩家经营权限；该企业自身所知的供应和合同"
	status.text="绿：本商号仓 · 橙虚线：订单关系 · 灰：地理地点\n左拖旋转/平移 · 滚轮缩放 · 右拖方位 · 精确货运位置未知时仅列阶段"
	status.text+="\n蓝细线：当前至少可下单1单位；红细线：已知但当前不能下单。不代表交通路径或成交。"
	status.text+="\n青线：所选商品近7日已到货关系，非当前运输；全部商品时不合并画线。"
	if snapshot.get("research_only",false):status.text=status.text.replace("本商号仓","观察企业仓")
	if not unlocated.is_empty():status.text+="\n未定位（仍可选）："+", ".join(unlocated)
	if not network.get("issues",[]).is_empty():status.text+="\n投影警告："+str(network.issues)
	map_base.set_reference_date(snapshot.get("date",{}))
	_detail(); canvas.queue_redraw()

func draw_economy(surface: Control) -> void:
	_hits.clear(); _edge_hits.clear()
	if not map_base.loaded:return
	if show_received_flows and selected_good!="all":
		for flow: Dictionary in contacts.get("flows",{}).values():
			if flow.good!=selected_good or int(flow.received_in_window)<=0 or flow.from_place_id==flow.to_place_id:continue
			if not _located(flow.from_place_id) or not _located(flow.to_place_id):continue
			var line: PackedVector3Array=_arc(flow.from_place_id,flow.to_place_id)
			for index: int in range(line.size()-1):
				var p: Vector2=map_base.visible_point(line[index]);var q: Vector2=map_base.visible_point(line[index+1])
				if p.is_finite() and q.is_finite():surface.draw_line(p,q,Color("85c9c0"),2.0,true)
	if show_contacts:
		var drawn: Dictionary={}
		for contact: Dictionary in contacts.get("contacts",[]):
			if selected_good!="all" and contact.good!=selected_good:continue
			var a: String=contact.from_place_id; var b: String=contact.to_place_id
			if a==b or not _located(a) or not _located(b):continue
			var key: String=a+"|"+b+"|"+str(contact.good)
			if not drawn.has(key):drawn[key]={"from":a,"to":b,"offered":false}
			drawn[key].offered=drawn[key].offered or bool(contact.get("can_order_one",int(contact.get("quantity",0))>0))
		for relation: Dictionary in drawn.values():
			var a: String=relation.from;var b: String=relation.to
			var arc: PackedVector3Array=_arc(a,b)
			for index: int in range(arc.size()-1):
				var p: Vector2=map_base.visible_point(arc[index]);var q: Vector2=map_base.visible_point(arc[index+1])
				if p.is_finite() and q.is_finite():surface.draw_line(p,q,Color("4fa8c6") if relation.offered else Color("b56868"),1.0,true)
	for id: String in network.get("edges",{}):
		var edge: Dictionary=network.edges[id]
		if selected_good!="all" and edge.good!=selected_good:continue
		if edge.from_node==edge.to_node or not _located(edge.from_node) or not _located(edge.to_node):continue
		var history: bool=_edge_status(edge)=="历史关系"
		if history and not show_history and id!=selected_order:continue
		var line: PackedVector3Array=_arc(edge.from_node,edge.to_node)
		for index: int in range(line.size()-1):
			var a: Vector2=map_base.visible_point(line[index]); var b: Vector2=map_base.visible_point(line[index+1])
			if not a.is_finite() or not b.is_finite():continue
			if index%2==0:surface.draw_line(a,b,Color("7a7769") if history else CONTRACT,4.0 if id==selected_order else 2.0,true)
			_edge_hits.append({"id":id,"points":PackedVector2Array([a,b])})
	var occupied: Array[Rect2]=[]
	var ids: Array=places.keys(); ids.sort_custom(func(a: String,b: String): return _priority(a)>_priority(b))
	for id: String in ids:
		if not _located(id):continue
		var position: Vector2=map_base.visible_point(_unit(id))
		if not position.is_finite():continue
		var node: Dictionary=network.get("nodes",{}).get(id,{})
		var own: bool=not node.get("known_own_sites",[]).is_empty()
		var color: Color=OWN if own else CONTRACT if not node.is_empty() else Color("4fa8c6") if contacts.get("nodes",{}).has(id) else BACKGROUND
		_hits[id]=position
		if selected_good!="all":
			var activity: Dictionary=contacts.get("nodes",{}).get(id,{}).get("goods",{}).get(selected_good,{})
			var volume: int=int(activity.get("received",0))+int(activity.get("sent",0))
			if volume>0:surface.draw_arc(position,12.0+minf(12.0,log(1.0+volume)*2.0),0,TAU,40,Color("93c8d5"),2.0,true)
		surface.draw_circle(position,6.0 if not node.is_empty() else 2.5,color)
		if id==selected_place:surface.draw_arc(position,10,0,TAU,32,Color.WHITE,1.5,true)
		if node.is_empty() and not contacts.get("nodes",{}).has(id):continue # Main renderer owns background labels.
		var text: String=place_name(id); var face: Font=get_theme_default_font()
		var extent: Vector2=face.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,16)
		var box:=Rect2(position+Vector2(12,-24),extent+Vector2(8,6))
		if occupied.any(func(other: Rect2): return other.grow(3).intersects(box)) and id!=selected_place:continue
		occupied.append(box); surface.draw_rect(box,Color("10202ee8"))
		surface.draw_string(face,box.position+Vector2(4,18),text,HORIZONTAL_ALIGNMENT_LEFT,-1,16,color)

func _priority(id: String) -> int:
	return 10000 if id==selected_place else 1000 if network.get("nodes",{}).has(id) else 0

func _map_input(event: InputEvent) -> void:
	# Renderer/controller handle all camera events. Only attach economy hit targets
	# to a native click after the controller has ruled out a drag.
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:
		if not map_base.controller._drag_moved and not map_base.renderer.unit_at(event.position).is_zero_approx():_pick(event.position)

func _pick(point: Vector2) -> void:
	var best: String=""; var distance: float=13.0
	for id: String in _hits:
		var candidate: float=point.distance_to(_hits[id])
		if candidate<distance:best=id; distance=candidate
	if not best.is_empty():select_place(best); return
	for edge: Dictionary in _edge_hits:
		var points: PackedVector2Array=edge.points
		if point.distance_to(Geometry2D.get_closest_point_to_segment(point,points[0],points[1]))<7:select_order(edge.id); return


func _button(parent: Node, title: String, action: Callable) -> Button:
	var button := Button.new(); button.text=title; button.custom_minimum_size.y=36
	button.pressed.connect(action); parent.add_child(button); return button

func update_snapshot(value: Dictionary) -> void:
	# Deep copy detaches UI data even when caller owns a mutable dictionary.
	if not _plain(value):return
	snapshot=value.duplicate(true)
	network=snapshot.get("market_network",{})
	contacts=snapshot.get("market_contacts",{})
	if contacts.get("schema","") not in ["merchant_observed_contacts_v1","merchant_observed_contacts_v2"]:contacts={}
	if network.get("schema","")!="merchant_local_network_projection_v1":network={}
	if is_node_ready():_rebuild()

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

func _located(id: String) -> bool:
	var map_id: String=Catalog.place_query_to_map_id(id)
	var row: Dictionary=catalog.get_place(map_id)
	var coordinates: Variant=row.get("lon_lat")
	return Catalog.map_id_to_place_id(map_id)==id and coordinates is Array and coordinates.size()==2 and (coordinates[0] is float or coordinates[0] is int) and (coordinates[1] is float or coordinates[1] is int) and is_finite(float(coordinates[0])) and is_finite(float(coordinates[1])) and absf(float(coordinates[0]))<=180 and absf(float(coordinates[1]))<=90

func _unit(id: String) -> Vector3:
	var coordinates: Array=catalog.get_place(id).lon_lat
	return Globe.lon_lat_to_unit(Vector2(coordinates[0],coordinates[1]))

func _arc(a: String,b: String) -> PackedVector3Array:
	var line := PackedVector3Array(); var start: Vector3=_unit(a); var end: Vector3=_unit(b)
	for index: int in range(33):line.append(start.slerp(end,index/32.0))
	return line

func place_name(id: String) -> String:
	return str(catalog.get_place(id).get("name",id))


func _edge_status(edge: Dictionary) -> String:
	var raw: Dictionary=_raw_order(str(edge.order_id))
	if int(edge.get("pending_responsibility",0))+int(edge.get("transit_responsibility",0))>0:return "未结"
	if int(raw.get("unresolved_loss_quantity",0))>0:return "待处理损失"
	return "历史关系"

func _raw_order(id: String) -> Dictionary:
	var firm: Dictionary=snapshot.get("firm",{})
	for key: String in ["orders","sales_orders"]:
		var rows: Variant=firm.get(key,[])
		if rows is Array:
			for order: Dictionary in rows:
				if order.get("id")==id:return order
	return {}

func select_place(id: String) -> void:
	selected_place=id; selected_order=""; side.show(); _detail(); canvas.queue_redraw()
	details.scroll_to_line(0)
	for index: int in place_select.item_count:
		if place_select.get_item_metadata(index)==id:place_select.select(index)
	order_select.select(0)

func focus_place(id: String) -> void:
	map_base.focus_place(id)
	select_place(id)

func select_order(id: String) -> void:
	selected_order=id; side.show(); _detail(); canvas.queue_redraw()
	details.scroll_to_line(0)
	for index: int in order_select.item_count:
		if order_select.get_item_metadata(index)==id:order_select.select(index)

func _goods(values: Dictionary) -> String:
	var rows: Array[String]=[]
	for good: String in values:
		if values[good]!=0:rows.append("%s %s"%[GOODS.get(good,good),values[good]])
	return "、".join(rows) if not rows.is_empty() else "0（已有视图）"

func _money(values: Dictionary) -> String:
	var rows: Array[String]=[]
	for denomination: String in values:
		var label: String="原记账单位" if denomination==FormalLedgerState.DENOMINATION else denomination
		rows.append("%s（%s）"%[values[denomination],label])
	return "、".join(rows) if not rows.is_empty() else "0（已有收据）"

func _cargo_text(order_id: String="",place_id: String="") -> String:
	var rows: Array[String]=[]
	for id: String in network.get("cargo",{}):
		var cargo: Dictionary=network.cargo[id]
		if not order_id.is_empty() and cargo.order_id!=order_id:continue
		if not place_id.is_empty() and cargo.from_node!=place_id and cargo.to_node!=place_id and cargo.place_id!=place_id:continue
		if not cargo.get("physical_quantity") is int or int(cargo.physical_quantity)<=0:continue
		rows.append("%s · %s %s · 阶段 %s\n所涉 %s → %s；已知地点 %s\n精确位置未知；不作实时移动"%[id,GOODS.get(cargo.good,cargo.good),cargo.physical_quantity,cargo.stage,place_name(cargo.from_node),place_name(cargo.to_node),place_name(cargo.place_id) if not str(cargo.place_id).is_empty() else "未知"])
		if cargo.get("earliest_arrival_day")!=null:rows.append("最早到货下限：第%s天（非保证到达）"%str(int(cargo.earliest_arrival_day)+1))
		if not str(cargo.get("arrival_blocked_reason","")).is_empty():rows.append("阻塞："+str(cargo.arrival_blocked_reason))
	return "\n".join(rows) if not rows.is_empty() else "当前没有已确认在途货批"

func _detail() -> void:
	if details==null:return
	var rows: Array[String]=[]
	if not selected_order.is_empty() and network.get("edges",{}).has(selected_order):
		var edge: Dictionary=network.edges[selected_order]; var raw: Dictionary=_raw_order(selected_order)
		rows.append("订单 %s · %s\n%s · %s → %s\n起点 %s\n终点 %s\n待发责任 %s · 在途责任 %s\n已交付 %s · 已取消 %s"%[selected_order,_edge_status(edge),GOODS.get(edge.good,edge.good),place_name(edge.from_node),place_name(edge.to_node),edge.from_node,edge.to_node,edge.pending_responsibility,edge.transit_responsibility,edge.delivered,raw.get("cancelled","未知")])
		rows.append("订单关系不证明铁路或实际轨迹。" if edge.from_node!=edge.to_node else "同城订单，不绘跨城线。")
		if not str(raw.get("pending_waiting_reason","")).is_empty():rows.append("待发原因："+str(raw.pending_waiting_reason))
		rows.append(_cargo_text(selected_order))
		for receipt: Dictionary in raw.get("deliveries",[]):rows.append("实际到货 %s · 数量 %s · 第%s天"%[receipt.get("id",""),receipt.get("quantity","未知"),int(receipt.get("delivered_day",-1))+1])
		for cash: Dictionary in snapshot.get("trade_review",{}).get("order_rows",[]):
			if cash.get("order_id")==selected_order:
				rows.append("原账本已付货款 %s / 运费 %s / 已收货款 %s"%[_money(cash.get("goods_paid",{})),_money(cash.get("freight_paid",{})),_money(cash.get("sales_received",{}))])
		if technical.button_pressed:rows.append("经济路线ID："+str(edge.get("route_id",""))+"\n合法订单引用：\n"+JSON.stringify(raw,"  "))
	else:
		var node: Dictionary=network.get("nodes",{}).get(selected_place,{})
		rows.append(place_name(selected_place)+"\n"+selected_place)
		if _located(selected_place):rows.append("地图ID %s · 经度 %s · 纬度 %s"%[Catalog.place_query_to_map_id(selected_place),catalog.get_place(selected_place).lon_lat[0],catalog.get_place(selected_place).lon_lat[1]])
		else:rows.append("未定位：Catalog 无可用坐标；不猜测位置。")
		var consumer_text: String=_consumer_text(selected_place)
		if node.is_empty():rows.append("收到的供应联系地点；未取得对方总库存。" if contacts.get("nodes",{}).has(selected_place) else "仅有地理资料；当前没有本商号可见经营事实。")
		elif node.get("known_own_sites",[]).is_empty():rows.append("合同相关地点；没有本商号已知仓库，不推定对方库存。")
		else:
			rows.append("本商号已有站点汇总（只读）\n在库：%s\n自由：%s\n已承诺：%s"%[_goods(node.known_own_stock_by_good),_goods(node.known_own_free_by_good),_goods(node.known_own_reserved_by_good)])
			for operation: Dictionary in snapshot.get("firm",{}).get("operations",[]):
				if operation.get("site_id") in node.known_own_sites:rows.append("站点 %s\n在库 %s\n自由 %s\n承诺 %s"%[operation.site_id,_goods(operation.get("inventory",{})),_goods(operation.get("free_inventory",{})),_goods(operation.get("committed_inventory",{}))])
		rows.append(_cargo_text("",selected_place))
		rows.append(_sales_observation_text(selected_place))
		if not consumer_text.is_empty():rows.append(consumer_text)
		rows.append(_contacts_text(selected_place))
		for id: String in network.get("edges",{}):
			var edge: Dictionary=network.edges[id]
			if selected_place in [edge.from_node,edge.to_node]:rows.append("%s · %s · %s\n%s → %s · 待发 %s / 在途责任 %s / 到货 %s"%[id,_edge_status(edge),GOODS.get(edge.good,edge.good),place_name(edge.from_node),place_name(edge.to_node),edge.pending_responsibility,edge.transit_responsibility,edge.delivered])
		if technical.button_pressed:rows.append("合法节点引用：\n"+JSON.stringify(node,"  "))
	if technical.button_pressed:rows.append(str(snapshot.get("map_source","尚未取得经济观察"))+"\n主地图渲染器：res://shared/wwo_map/scripts/presentation/map/globe_renderer.gd"+("（资料装载中）" if not map_base.loaded else ""))
	details.text="\n\n".join(rows)
	if snapshot.get("research_only",false):details.text=details.text.replace("本商号","观察企业")
	business_button.visible=business_enabled and not snapshot.get("research_only",false) and selected_order.is_empty() and not network.get("nodes",{}).get(selected_place,{}).get("known_own_sites",[]).is_empty()

func _business() -> void:
	var sites: Array=network.get("nodes",{}).get(selected_place,{}).get("known_own_sites",[])
	if not sites.is_empty():business_requested.emit(selected_place,str(sites[0]))

func _sales_observation_text(place: String) -> String:
	var rows: Array[String]=["本站实际收到的销售尝试（各买方最近记录）"]
	var day: int=int(snapshot.get("minute",0))/1440
	for operation: Dictionary in snapshot.get("firm",{}).get("operations",[]):
		if operation.get("stock_place_id")!=place:continue
		for good: String in operation.get("stock_costs",{}):
			if selected_good!="all" and good!=selected_good:continue
			var cost: Dictionary=operation.stock_costs[good]
			var known: Variant=cost.known_cost.get("denomination:formal_simulation_minor_v1")
			rows.append("%s自由库存%s · 已知原成本%s；成本未全明%s件；持有最长%s日。成本不是可用资金或现售价。"%[GOODS.get(good,good),cost.quantity,known if known!=null else "未知／其他币种",cost.unknown_cost_quantity,cost.oldest_own_holding_days])
		for good: String in operation.get("product_needs",{}):
			if selected_good!="all" and good!=selected_good:continue
			var market: Dictionary=operation.product_needs[good].get("inventory_adaptation",{}).get("market_time_signal",{})
			if not market.is_empty():rows.append("%s：正式未交付合同%s；询购%s（仅当时可付，未冻结）；近期过期买方%s。到仓与再次购买均不保证。"%[GOODS.get(good,good),market.contracted_pending_quantity,market.active_funded_at_attempt,market.expired_buyers])
		for good: String in operation.get("received_requests",{}):
			if selected_good!="all" and good!=selected_good:continue
			var latest: Dictionary={}
			for request: Dictionary in operation.received_requests[good]:
				if int(request.day)<day-6:continue
				if not latest.has(request.buyer) or int(request.day)>=int(latest[request.buyer].day):latest[request.buyer]=request
			if latest.is_empty():continue
			var refusals: Dictionary={};var current_stock_requests: int=0
			for request: Dictionary in latest.values():
				for kind: String in request.get("limit_observation",{}).get("refused",{}):refusals[kind]=int(refusals.get(kind,0))+int(request.limit_observation.refused[kind])
				if int(request.need_by_day)>=day:current_stock_requests+=int(request.get("physical_unmet",0))
			rows.append("%s · %s位已联系买方\n最近尝试拒绝数量：缺货%s／支付条件%s／运力%s／接收或需要%s／报价%s\n未过需要边界的缺货尝试%s；不是保证销售。"%[GOODS.get(good,good),latest.size(),refusals.get("seller_stock",0),refusals.get("cash",0),refusals.get("logistics",0),refusals.get("buyer_capacity",0),int(refusals.get("price",0))+int(refusals.get("information",0)),current_stock_requests])
	rows.append("只据本站收到的行动，不显示买方余额；未联系不代表没有需要。")
	return "\n".join(rows) if rows.size()>2 else ""

func _consumer_text(place: String) -> String:
	var access: Dictionary=snapshot.get("consumer_access",{})
	if access.get("schema")!="developer_consumer_access_v1" or selected_good not in ["all","bread","beans","clothes","soap"]:return ""
	var rows: Array[String]=["研发：终端消费可达性（私人诊断，不是商人知识）"]
	var time_rows: int=0
	for observed: Dictionary in access.get("market_responses",[]):
		if observed.place_id!=place or (selected_good!="all" and observed.good!=selected_good):continue
		time_rows+=1
		var capital: Dictionary=observed.response.get("turnover_response",{})
		if not capital.is_empty():rows.append("经营原判断 · %s\n%s；允许新备%s\n近期成交%s日／%s位买方，复购买方%s；过期未在本店及时成交%s次\n原成本占用%s；入货原预留%s；未定成本%s件。"%[GOODS.get(observed.good,observed.good),_capital_response_label(capital.reason),capital.optional_quantity_limit,capital.experience.sale_days,capital.experience.distinct_buyers,capital.experience.repeat_buyers,capital.experience.expired_without_own_timely_sale,capital.capital.known_free_resale_cost,capital.capital.incoming_original_reservations,capital.capital.unknown_cost_quantity])
		var response: Dictionary=observed.response.get("market_time_response",{})
		if response.is_empty():
			if time_rows>=3:break
			continue
		var market: Dictionary=response["signal"]
		rows.append(("期限子判断（未含资金与经验约束）" if not capital.is_empty() else "商人原判断")+" 第%s天 · %s\n补至本仓下限day%s；赶得上询购%s／迟到%s／时间未知%s\n%s；数量上限%s；独立风险试购%s。均非保证销量。"%[int(observed.minute)/1440+1,GOODS.get(observed.good,observed.good),market.stock_arrival_lower_bound,market.timely_quantity,market.late_quantity,market.unknown_time_quantity,_market_response_label(response.reason),response.new_optional_quantity_limit,"是" if response.independent_risk_trial else "否"])
		if time_rows>=3:break
	var purchases: int=0
	for order: Dictionary in access.get("recent_replenishment",[]):
		if order.place_id!=place or (selected_good!="all" and order.good!=selected_good):continue
		var why: String=_capital_response_label(str(order.turnover.reason)) if not order.get("turnover",{}).is_empty() else _market_response_label(str(order.get("decision",{}).get("reason","原经营规则")))
		rows.append("原补货 %s · %s×%s\n待发%s／在途%s／实际到仓%s；当时依据：%s"%[order.order_id,GOODS.get(order.good,order.good),order.quantity,order.pending,order.transit,order.delivered,why])
		purchases+=1
		if purchases>=3:break
	for h: Dictionary in access.get("places",{}).get(place,[]):
		var category: String="clothing" if selected_good=="clothes" else "household" if selected_good=="soap" else "food"
		var category_name: String={"food":"食物","clothing":"衣着服务","household":"日用品"}[category]
		var today: Dictionary=h.get("category_today",{}).get(category,h.food_today);var total: Dictionary=h.get("category_totals",{}).get(category,h.food_total)
		rows.append("居民 %s\n今日%s满足 %s／%s；累计 %s／%s\n现金%s－预留%s＝可用%s；到期欠薪%s（不是现金）"%[h.actor,category_name,today.get("satisfied",0),today.get("required",0),total.get("satisfied",0),total.get("required",0),h.cash,h.reserved,h.available,h.wage_matured_unpaid])
		var choice: Dictionary=h.get("choice_observation",{}).get("plan",{})
		if not choice.is_empty():
			rows.append("最近比较 第%s天：%s · 窗口%s日 · 当时可用%s；未来工资计入0"%[int(h.choice_observation.day)+1,choice.mode,choice.horizon_days,choice.cash_available])
			for refused: Dictionary in choice.get("not_selected",[]).slice(0,2):
				if refused.get("reason")=="WAIT_BOUNDED_OTHER_FLOW_PURCHASING_POWER":rows.append("暂缓%s：单件需%s；其他流量购买力缓冲%s，未冻结。"%[GOODS.get(refused.good,refused.good),refused.unit_cash_cost,refused.reserve.amount])
		for chosen: Dictionary in h.get("recent_cross_category_choices",[]).slice(0,2):
			var decision: Dictionary=chosen.result.decision.household_choice
			rows.append("原买单 第%s天 · %s ×%s · %s\n拟付%s；服务改善%s；其他流量购买力缓冲%s（未冻结）"%[int(chosen.minute)/1440+1,GOODS.get(chosen.good,chosen.good),chosen.quantity,chosen.result.reason,decision.selected.cost,decision.selected.benefit.service_units,decision.selected.reserve.amount])
		if category=="food" and h.known_food_offers.is_empty():rows.append("没有已收到的食物供货介绍。")
		for o: Dictionary in h.get("known_consumption_offers",h.known_food_offers):
			if selected_good!="all" and o.good!=selected_good:continue
			rows.append("已知 %s · 价%s＋运费%s\n合法营业%s；自由%s／承诺%s；运力上限%s\n可负担%s件；当前可下单%s件\n%s；报价%s"%[GOODS.get(o.good,o.good),o.price if o.price!=null else "未知",o.freight,"是" if o.sales_role and o.site_selling else "否",o.free,o.committed,o.transport_cap,o.request_caps.caps.cash,o.executable_quantity,o.offer_reason,o.known_quote_reason if not str(o.known_quote_reason).is_empty() else "已收到可用条件"])
		if selected_good in ["all","bread","beans"] and not h.recent_real_attempts.is_empty():
			var attempt: Dictionary=h.recent_real_attempts[0]
			rows.append("最近正式食物尝试：第%s天 · %s"%[int(attempt.minute)/1440+1,attempt.result.get("reason","")])
		var clothing: Dictionary=h.get("category_totals",{}).get("clothing",{})
		rows.append("衣服实持%s；衣着服务累计%s／%s（耐用品保持，不每日销毁）"%[h.get("consumer_inventory",{}).get("clothes",0),clothing.get("satisfied",0),clothing.get("required",0)])
		if technical.button_pressed:rows.append(JSON.stringify(h,"  "))
	return "\n".join(rows) if rows.size()>1 else ""

func _market_response_label(reason: String) -> String:
	return {"TIMELY_ATTEMPT_STILL_NOT_GUARANTEED_SALE":"询购窗口内的条件机会，买方资金可能变化","OWN_SALES_CYCLE_ESTIMATE_NOT_BACKLOG":"近期实际销售的有限补货，不累计旧需要","FINITE_TRIAL_AT_MERCHANT_RISK":"商人自担风险的有限试购","NO_TIMELY_ATTEMPT_OR_OWN_SALES_WAIT":"缺少及时询购或自身销量，等待"}.get(reason,reason)

func _capital_response_label(reason: String) -> String:
	return {"CURRENT_TIMELY_ATTEMPT_NOT_FUTURE_CONTRACT":"新有效询购机会，非保证订单","REPEATED_FLOW_DELIVERIES_FINITE_COVER":"多日真实消耗品销售，有限覆盖","POSITIVE_SPREAD_FINITE_CAPITAL_TRIAL":"已知价差支持小量试购","SINGLE_ZERO_SPREAD_SALE_WAIT_NOT_STABLE_TURNOVER":"仅一次零价差销售，等待新证据","OPTIONAL_CAPITAL_OCCUPIED_OR_CASH_DUE":"已有资金占用或到期责任，暂缓","WAIT_NEW_ACTIONABLE_EVIDENCE":"等待新可执行信息"}.get(reason,reason)

func _contacts_text(place: String) -> String:
	var rows: Array[String]=["供货联系如何形成（本站收到的信息）"]
	var count: int=0
	for link: Dictionary in contacts.get("links",{}).values():
		if selected_good!="all" and link.good!=selected_good:continue
		if place not in [link.from_place_id,link.to_place_id]:continue
		count+=1
		if count>8:continue
		var source: String={"opening":"配置供货介绍","directory":"有限公开名录搜索","commercial":"企业本地商业公告"}.get(str(link.knowledge_source),"原记录未说明来源")
		var received: String="第%s天"%(int(link.received_day)+1) if link.received_day!=null else "日期未说明"
		var activity: String="近7日到货%s，%s次收货"%[link.received_in_window,link.receipt_count] if int(link.received_in_window)>0 else "近7日没有交付" if link.last_delivery_day!=null else "尚无实际交付"
		rows.append("%s · %s → %s\n来源：%s，%s收到\n%s；当前可下单1单位：%s\n待发责任%s／在途责任%s（不是现场库存）"%[GOODS.get(link.good,link.good),place_name(link.from_place_id),place_name(link.to_place_id),source,received,activity,"是" if link.can_order_one else "否",link.pending_responsibility,link.transit_responsibility])
		if int(link.get("buyer_good_received_in_window",0))>0:rows.append("本站该商品近7日到货份额：%s／%s；限本站已知交易。"%[link.received_in_window,link.buyer_good_received_in_window])
		if link.last_delivery_day!=null:rows.append("最近实际交付：第%s天；已知身份继续保留，不保证持续有货。"%(int(link.last_delivery_day)+1))
		var inventory: Dictionary=link.get("inventory_adaptation",{})
		if not inventory.is_empty():
			var decision: String={"OWN_RECEIVED_FUNDED_STOCK_ENQUIRY_OPTIONAL_TRIAL":"本站收到真实可负担缺货询购，有限补货尝试","DURABLE_TRIAL_CAPITAL_WITHOUT_OWN_SALES":"耐用品试购资金尚无实际销售回收，等待","FINITE_TRIAL_WITHOUT_SALES_EVIDENCE":"缺少本站销售证据，有限试购","OWN_DELIVERED_SALES_COVER":"按本站实际交付销售覆盖补货","IDLE_OWN_STOCK_WAIT_NO_RECENT_SALES":"现有库存积压，暂无近期销售，等待"}.get(inventory.reason,str(inventory.reason))
			rows.append("经营备货：%s\n配置储备%s／当前可选目标%s；近%s日实际销售%s\n生产、合同等用途另按原责任计算。当前可买不代表企业打算买。"%[decision,inventory.configured_buffer,inventory.optional_buffer_target,inventory.window_days,inventory.own_delivered_sales])
		if technical.button_pressed:rows.append("供货信息引用：\n"+JSON.stringify(link,"  "))
	if count>8:rows.append("另有%s条已知联系；选择具体商品缩小范围。"%(count-8))
	rows.append("已收到的供应联系（当前快照；可报价量不等于对方总库存）")
	for offer: Dictionary in contacts.get("contacts",[]):
		if selected_good!="all" and offer.good!=selected_good:continue
		if place not in [offer.from_place_id,offer.to_place_id]:continue
		var why: String={"OFFER":"当前可报价","TRANSPORT_LIMIT_OR_CLOSED":"运输限额已用尽或线路关闭","NO_UNCOMMITTED_STOCK":"暂无可报价货物","INSUFFICIENT_AVAILABLE_CASH":"可用资金不足","NO_KNOWN_PATH":"没有已知运输路径","GOODS_NEW_SALES_PAUSED":"卖方暂停新销售","QUOTATION_NOT_RECEIVED":"报价尚未收到","GOODS_QUOTE_NOT_RECEIVED":"报价消息尚未收到","GOODS_QUOTE_SUPERSEDED":"旧报价已替换，等待新消息","GOODS_QUOTE_EXPIRED":"已收到报价过期"}.get(str(offer.get("reason","")),str(offer.get("reason","未知")))
		var currency: String="原记账单位" if offer.get("denomination")=="denomination:formal_simulation_minor_v1" else str(offer.get("denomination","未知币种"))
		rows.append("%s · %s → %s\n当前可报价 %s · 单价 %s / 单位运费 %s %s\n%s · 本站待补 %s · 自动采购候选顺序 %s\n最早到货第%s天（下限）"%[GOODS.get(offer.good,offer.good),place_name(offer.from_place_id),place_name(offer.to_place_id),offer.get("quantity","未知"),offer.get("price","未知"),offer.get("freight_per_unit","未知"),currency,why,offer.need_quantity,offer.autonomous_rank if offer.autonomous_rank!=null else "未入选或无需求",int(offer.get("earliest_arrival_day",-1))+1])
		rows.append("单位到仓现金成本 %s · 当前可下单1单位：%s\n正式检查 %s · 已有晚到 %s / 未知货期 %s"%[offer.get("landed_unit_cost","未知"),"是" if offer.get("can_order_one",false) else "否",offer.get("order_reason","未知"),offer.get("known_late_quantity",0),offer.get("unknown_arrival_quantity",0)])
		if offer.has("observed_arrival_day"):
			rows.append("按当前路径与本商号经验观察到货：%s\n近期延误平均%s天（%s次到货）；非保证时间"%["第%s天"%(int(offer.observed_arrival_day)+1) if offer.observed_arrival_day!=null else "未知",offer.average_delay_days,offer.delivery_samples])
		if technical.button_pressed:rows.append("供应站点 %s\n本商号站点 %s\n经济路径 %s\n报价 %s"%[offer.seller_site,offer.buyer_site,offer.route_id,offer.quote_id])
	var activity: Dictionary=contacts.get("nodes",{}).get(place,{}).get("goods",{})
	rows.append("本商号近7日已确认到货活动（按商品；不是全市场中心排名）")
	for good: String in activity:
		if selected_good!="all" and good!=selected_good:continue
		rows.append("%s · 跨地输入 %s / 输出 %s · 同地到货 %s · 关联地点 %s"%[GOODS.get(good,good),activity[good].received,activity[good].sent,activity[good].get("local_received",0),activity[good].partners.size()])
	for flow: Dictionary in contacts.get("flows",{}).values():
		if int(flow.received_in_window)<=0 or place not in [flow.from_place_id,flow.to_place_id] or (selected_good!="all" and flow.good!=selected_good):continue
		rows.append("%s → %s · %s到货%s · %s次收货"%[place_name(flow.from_place_id),place_name(flow.to_place_id),GOODS.get(flow.good,flow.good),flow.received_in_window,flow.get("receipt_count",flow.delivery_ids.size())])
		if int(flow.get("lead_quantity",0))>0:rows.append("接受至收货平均%.1f日（范围%s–%s）；含待发，不是纯行驶时间"%[float(flow.lead_quantity_days)/float(flow.lead_quantity),flow.minimum_lead_days,flow.maximum_lead_days])
		if technical.button_pressed:rows.append("收货引用："+str(flow.delivery_ids))
	return "\n\n".join(rows)

