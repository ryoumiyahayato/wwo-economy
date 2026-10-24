extends Control
## Explicit GUI replay of snapshots captured by the native legal-order test.
## No runtime, world, clock, inventory or settlement is created here.
const MapScene=preload("res://merchant/economy_map_view.tscn")
var map_view: Control
var selector: OptionButton
var records: Array=[]
var order_id: String=""

func _ready() -> void:
	DisplayServer.window_set_title("原验证证据回放 · 非实时经济世界")
	map_view=MapScene.instantiate();add_child(map_view)
	map_view.offset_top=44
	theme=map_view.theme
	selector=OptionButton.new();selector.position=Vector2(14,5);selector.size=Vector2(700,36);selector.fit_to_longest_item=false;add_child(selector)
	selector.item_selected.connect(_show_record)
	map_view.refresh_requested.connect(func():_show_record(selector.selected))
	map_view.back_requested.connect(func():get_tree().quit())
	var path: String=ProjectSettings.globalize_path("res://").path_join("../live_order_result.json").simplify_path()
	var value: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	# JSON.parse stores every JSON number as float. Restore exact whole numbers
	# before passing the typed native projection to the presentation contract.
	value=_json_numbers(value)
	if not value is Dictionary or value.get("status")!="PASS":selector.add_item("缺少本轮原生验证结果："+path);return
	order_id=str(value.get("purchase",{}).get("order_id",""))
	for row: Dictionary in value.get("records",[]):
		if row.has("map_snapshot"):
			records.append(row)
			selector.add_item("原验证证据回放 · minute %s · 待发 %s / 在途责任 %s / 实物 %s / 到货 %s"%[row.minute,row.order.pending,row.order.transit,row.cargo_physical,row.order.delivered])
	if not records.is_empty():_show_record(0)

func _show_record(index: int) -> void:
	if index<0 or index>=records.size():return
	var value: Dictionary=records[index].map_snapshot.duplicate(true)
	value["map_replay"]=true
	value["map_source"]="原验证证据回放 · 本轮正式 buy 及 SimulationStep 测试记录 · 非实时经济世界，不推进、不保存"
	map_view.update_snapshot(value);map_view.select_order(order_id)

func _json_numbers(value: Variant) -> Variant:
	if value is Dictionary:
		for key: Variant in value:value[key]=_json_numbers(value[key])
	elif value is Array:
		for index: int in value.size():value[index]=_json_numbers(value[index])
	elif value is float and is_finite(value) and value==floor(value):return int(value)
	return value
