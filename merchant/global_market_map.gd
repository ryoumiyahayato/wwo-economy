extends "res://merchant/economy_map_view.gd"
## Additional layer on the frozen WWO renderer/controller, with no world owner.
var global_mode: bool=true
var commodity: String="wheat"
var comparison: String="united_states_1900"
var market: Dictionary={}
var commodity_choice: OptionButton
var compare_choice: OptionButton
var chart: Control
var mode_button: Button
var color_change: bool=false

class PriceHistory extends Control:
	var presenter: Control
	func _draw() -> void:presenter.draw_history(self)

func _ready() -> void:
	super._ready()
	map_base.map_ready.connect(func():map_base.focus_place(""))
	var row:=HBoxContainer.new();row.position=Vector2(12,148);add_child(row)
	mode_button=_button(row,"切到实物订单层",func():global_mode=not global_mode;_rebuild())
	commodity_choice=OptionButton.new();row.add_child(commodity_choice)
	commodity_choice.item_selected.connect(func(index: int):commodity=commodity_choice.get_item_metadata(index);_detail();canvas.queue_redraw())
	var colors:=CheckButton.new();colors.text="按30日涨跌着色";row.add_child(colors)
	colors.toggled.connect(func(on: bool):color_change=on;canvas.queue_redraw())
	compare_choice=OptionButton.new();compare_choice.custom_minimum_size.x=160;row.add_child(compare_choice)
	compare_choice.item_selected.connect(func(index: int):comparison=compare_choice.get_item_metadata(index);_detail())
	chart=PriceHistory.new();chart.presenter=self;chart.custom_minimum_size=Vector2(320,130)
	var column: Node=details.get_parent();column.add_child(chart);column.move_child(chart,4)
	selected_place="market:country_fra";side.anchor_top=0.33;side.show()
	_rebuild()

func update_snapshot(value: Dictionary) -> void:
	market=value.get("global_market",{}).duplicate(true)
	super.update_snapshot(value)

func _rebuild() -> void:
	# Normalize the selection before the base rebuild dispatches _detail().
	# A reference-market node has no physical Catalog coordinates.
	if not global_mode and selected_place.begins_with("market:"):selected_place="place:paris"
	elif global_mode and not selected_place.begins_with("market:"):selected_place="market:country_fra"
	super._rebuild()
	if mode_button==null:return
	chart.visible=global_mode;commodity_choice.visible=global_mode;compare_choice.visible=global_mode
	heading.get_parent().get_child(1).visible=not global_mode
	research_row.hide()
	order_select.visible=not global_mode;technical.visible=not global_mode
	business_button.visible=not global_mode and business_enabled
	mode_button.text="切到实物订单层" if global_mode else "切到全球参考行情"
	if not global_mode:
		if selected_place.begins_with("market:"):selected_place="place:paris"
		super._detail();return
	if not selected_place.begins_with("market:"):selected_place="market:country_fra"
	place_select.clear();order_select.hide();technical.hide();business_button.hide()
	commodity_choice.clear();compare_choice.clear()
	for g: Dictionary in market.get("goods",[]):
		commodity_choice.add_item(g.name);commodity_choice.set_item_metadata(commodity_choice.item_count-1,g.id)
		if commodity==g.id:commodity_choice.select(commodity_choice.item_count-1)
	for id: String in market.get("nodes",{}):
		var name: String=market.nodes[id].name
		place_select.add_item(name);place_select.set_item_metadata(place_select.item_count-1,"market:"+id)
		compare_choice.add_item("比较："+name);compare_choice.set_item_metadata(compare_choice.item_count-1,id)
		if comparison==id:compare_choice.select(compare_choice.item_count-1)
		if selected_place=="market:"+id:place_select.select(place_select.item_count-1)
	heading.text="全球大宗商品 · %d区域 / 16商品 / %d稀疏联系 · 正式minute %d"%[market.get("nodes",{}).size(),market.get("edge_count",0),int(snapshot.get("minute",0))]
	heading.text+="\n开发情景参考指数：初值100；不代表历史币值，不是可成交报价。时间暂停时行情保持。"
	if market.get("visibility")=="PUBLIC_DELAYED_INDICES":heading.text+="\n公开行情：第%d日观察 / 第%d日收到。"%[int(market.day)+1,int(market.received_day)+1]
	status.text="颜色：蓝低红高；涨跌模式：蓝跌红涨。点选节点查看详情与曲线。\n默认标注选中地区和可见地区中涨跌最大的4处。细线仅显示选中地区最多6条估计调配。\n实物订单另见订单层；估计调配不代表已交付。"
	_detail();canvas.queue_redraw()

func _located(id: String) -> bool:
	if id.begins_with("market:"):return market.get("nodes",{}).has(id.trim_prefix("market:"))
	return super._located(id)

func _unit(id: String) -> Vector3:
	if id.begins_with("market:"):
		var ll: Array=market.nodes[id.trim_prefix("market:")].lon_lat
		return Globe.lon_lat_to_unit(Vector2(ll[0],ll[1]))
	return super._unit(id)

func place_name(id: String) -> String:
	if id.begins_with("market:"):return market.get("nodes",{}).get(id.trim_prefix("market:"),{}).get("name",id)
	return super.place_name(id)

func draw_economy(surface: Control) -> void:
	if not global_mode:super.draw_economy(surface);return
	_hits.clear();_edge_hits.clear()
	if not map_base.loaded or market.is_empty():return
	var selected_id: String=selected_place.trim_prefix("market:")
	var visible_flows: Array=market.get("flows",[]).filter(func(flow: Dictionary)->bool:return flow.good==commodity and selected_id in [flow.from,flow.to])
	visible_flows.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return float(a.estimated_units)>float(b.estimated_units))
	for flow: Dictionary in visible_flows.slice(0,6):
		var line: PackedVector3Array=_arc("market:"+str(flow.from),"market:"+str(flow.to))
		for i: int in line.size()-1:
			var p: Vector2=map_base.visible_point(line[i]);var q: Vector2=map_base.visible_point(line[i+1])
			if p.is_finite() and q.is_finite():surface.draw_line(p,q,Color(0.4,0.8,0.9,0.45),1.2,true)
	var font: Font=get_theme_default_font();var occupied: Array[Rect2]=[]
	var label_ids: Array[String]=important_label_ids()
	for id: String in market.nodes:
		var point: Vector2=map_base.visible_point(_unit("market:"+id))
		if not point.is_finite():continue
		var c: Dictionary=market.cells.get(id+"|"+commodity,{})
		if c.is_empty():continue
		var change: float=_change(c)
		var level: float=clampf((change+20.0)/40.0 if color_change else (float(c.price)-60.0)/100.0,0.0,1.0)
		var color: Color=Color("55bfe6").lerp(Color("fa8667"),level)
		_hits["market:"+id]=point
		surface.draw_circle(point,5.5+minf(4.0,float(c.get("unmet",0.0))/float(c.get("base",1.0))*4.0),color)
		if selected_place=="market:"+id:surface.draw_arc(point,12,0,TAU,32,Color.WHITE,2,true)
		if not label_ids.has(id):continue
		var label: String="%s %.1f%s"%[market.nodes[id].name,float(c.price),(" %+.1f%%"%change) if color_change else ""]
		var extent: Vector2=font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,14)
		var rect:=Rect2(point+Vector2(9,-20),extent+Vector2(6,6))
		if occupied.any(func(other: Rect2)->bool:return other.intersects(rect)) and selected_place!="market:"+id:continue
		occupied.append(rect);surface.draw_rect(rect,Color("10202ee8"));surface.draw_string(font,rect.position+Vector2(3,17),label,HORIZONTAL_ALIGNMENT_LEFT,-1,14,color)

func important_label_ids() -> Array[String]:
	var ids: Array[String]=[]
	for id: String in market.get("nodes",{}):
		if market.cells.has(id+"|"+commodity) and map_base.visible_point(_unit("market:"+id)).is_finite():ids.append(id)
	ids.sort_custom(func(a: String,b: String)->bool:return absf(_change(market.cells[a+"|"+commodity]))>absf(_change(market.cells[b+"|"+commodity])))
	if ids.size()>4:ids.resize(4)
	var selected_id: String=selected_place.trim_prefix("market:")
	if market.get("nodes",{}).has(selected_id) and not ids.has(selected_id):ids.append(selected_id)
	return ids

func _change(c: Dictionary) -> float:
	var h: Array=c.history
	return (float(c.price)/float(h[maxi(0,h.size()-31)])-1.0)*100.0

func _detail() -> void:
	if not global_mode:super._detail();return
	if details==null:return
	var id: String=selected_place.trim_prefix("market:")
	var c: Dictionary=market.get("cells",{}).get(id+"|"+commodity,{})
	if c.is_empty():details.text="选择全球市场节点。聚合估计不提供可购买库存。";return
	if market.get("visibility")=="PUBLIC_DELAYED_INDICES":
		details.text="%s · %s\n公开指数 %.2f / 30日 %+.2f%%\n世界基准需求加权参考 %.2f\n第%d日观察，第%d日通过开发公开行情服务收到。\n\n当前地区产需、缓冲和调配细节未公开。指数不提供可下单卖方、货批或币种汇兑。\n切回实物订单层查看本商号合法取得的报价、运输和已交付关系。"%[place_name(selected_place),commodity,float(c.price),_change(c),float(market.reference.get(commodity,100)),int(market.day)+1,int(market.received_day)+1]
		if chart!=null:chart.queue_redraw()
		return
	var text: String="%s · %s\n指数 %.2f · 30日 %+.2f%%\n世界基准需求加权参考 %.2f\n\n主要因素：%s\n估计供给 %.1f / 日需求 %.1f\n估计未满足 %.1f / 吸收 %.1f\n估计缓冲 %.2f日\n当日估计进口 %.1f / 出口 %.1f\n到达的外部信号 %.2f\n"%[place_name(selected_place),commodity,float(c.price),_change(c),float(market.reference.get(commodity,100)),c.cause,float(c.supply),float(c.demand),float(c.unmet),float(c.absorbed),float(c.cover),float(c.imports),float(c.exports),float(c.signal)]
	for s: Dictionary in market.get("shocks",[]):
		if s.node==id and s.good in [commodity,"all"]:text+="\n情景：%s · day%d—%d%s"%[s.label,int(s.from),int(s.until),"（生效）" if int(market.day)>=int(s.from) and int(market.day)<int(s.until) else "（未生效/已解除）"]
	var partners: int=0
	for flow: Dictionary in market.get("flows",[]):
		if flow.good==commodity and id in [flow.from,flow.to] and partners<6:
			text+="\n估计调配 %s→%s %.1f；预计day%d进入模型"%[place_name("market:"+str(flow.from)),place_name("market:"+str(flow.to)),float(flow.estimated_units),int(flow.arrival_day)];partners+=1
	text+="\n\n供需量为开发情景标准吨/日；缓冲是估计，不属于玩家或企业可取走货批。\n细线为估计调配，不计作销售款。国家节点无新账本。\n"
	if id=="country_fra":
		var local: Dictionary=market.get("local",{})
		# V2 stores the frozen sample by region; retain legacy display support.
		var sample: Dictionary=local.get("regions",{}).get("country_fra",local)
		if not sample.is_empty():text+="\n本日微观粮食样本：产出%.3f吨、投入%.3f吨；原库存%d单位。1单位按1kg估计，替代该小样本的聚合基线，不代表法国全部产需。"%[float(sample.get("produced_tonnes",0.0)),float(sample.get("used_tonnes",0.0)),int(sample.get("stock_native",sample.get("grain_stock_native",0)))]
		text+="\n公开指数有2日延迟；未授予任何新供应商知识。"
	details.text=text
	if chart!=null:chart.queue_redraw()

func draw_history(surface: Control) -> void:
	surface.draw_rect(Rect2(Vector2.ZERO,surface.size),Color("101d2c"))
	var id: String=selected_place.trim_prefix("market:")
	var a: Array=market.get("cells",{}).get(id+"|"+commodity,{}).get("history",[])
	var b: Array=market.get("cells",{}).get(comparison+"|"+commodity,{}).get("history",[])
	if a.is_empty():return
	var low:=100.0;var high:=100.0
	for values: Array in [a,b]:
		for p: Variant in values:low=minf(low,float(p));high=maxf(high,float(p))
	low=floor(low/10.0)*10.0-5;high=ceil(high/10.0)*10.0+5
	var font: Font=get_theme_default_font()
	surface.draw_string(font,Vector2(4,16),"%.0f—%.0f · 最近%d日 · 蓝本地 / 黄比较"%[low,high,a.size()],HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color.WHITE)
	for series: int in 2:
		var values: Array=a if series==0 else b
		for i: int in range(1,values.size()):
			var p:=Vector2(8.0+float(i-1)/maxi(1,values.size()-1)*(surface.size.x-16),surface.size.y-8-(float(values[i-1])-low)/(high-low)*(surface.size.y-34))
			var q:=Vector2(8.0+float(i)/maxi(1,values.size()-1)*(surface.size.x-16),surface.size.y-8-(float(values[i])-low)/(high-low)*(surface.size.y-34))
			surface.draw_line(p,q,Color("57cfef") if series==0 else Color("e8bd60"),2,true)
