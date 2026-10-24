extends "res://merchant/qa_market_network_live_order.gd"
## Reuses the delivered legal-order test, adding only presentation assertions.
const MapScene=preload("res://merchant/economy_map_view.tscn")
var map_view: Control

func run() -> void:
	map_view=MapScene.instantiate();root.add_child(map_view)
	super.run()

func record(built: WorldBuildResult,runtime: RefCounted,id: String) -> Dictionary:
	var before: Dictionary=built.persistence.snapshot()
	var result: Dictionary=super.record(built,runtime,id)
	var value: Dictionary=runtime._view(built)
	assert(before==built.persistence.snapshot(),"Original observation changed authoritative state")
	map_view.update_snapshot(value)
	assert(map_view._located("place:paris") and map_view._located("place:lyon"))
	assert(map_view.catalog.get_city("paris").lon_lat==[2.3522,48.8566])
	assert(map_view.catalog.get_city("lyon").lon_lat==[4.8357,45.764])
	assert(map_view.unlocated.is_empty(),str(map_view.unlocated))
	map_view.select_order(id)
	assert(id in map_view.details.text)
	if result.cargo_physical==0:assert("当前没有已确认在途货批" in map_view.details.text)
	else:
		assert("精确位置未知" in map_view.details.text)
		for sid: String in result.network.cargo:
			if result.network.cargo[sid].order_id==id:assert(sid in map_view.details.text)
	if result.order.pending==0 and result.order.transit==0:assert("历史关系" in map_view.details.text)
	assert(before==built.persistence.snapshot(),"Map interaction changed Ledger, lots or world time")
	result["map_snapshot"]=value
	result["map_order_text"]=map_view.details.text
	result["map_unlocated"]=map_view.unlocated.duplicate()
	return result
