extends SceneTree
const Scene=preload("res://merchant/merchant_scene.gd")
class Mailbox:
	extends RefCounted
	var calls: Array=[]
	func submit(kind: String,payload: Dictionary) -> int:
		calls.append({"kind":kind,"payload":payload.duplicate(true)})
		return calls.size()
func _initialize() -> void:
	var scene: Node=Scene.new()
	var mailbox:=Mailbox.new()
	scene.runtime=mailbox;scene.busy=false
	scene.confirm_kind="buy";scene.confirm_payload={"quantity":2}
	scene._confirm();scene._confirm()
	assert(mailbox.calls.size()==1 and scene.confirm_kind.is_empty() and scene.busy)
	scene._send("buy",{"quantity":2})
	assert(mailbox.calls.size()==1)
	scene.busy=false;scene._confirm()
	assert(mailbox.calls.size()==1)
	scene.view={"operations":[{"stock_place_id":"place:paris","inventory":{"grain":3},"free_inventory":{"grain":2},"committed_inventory":{"grain":1},"incoming":{"grain":4}}],"orders":[{"id":"a","pending":2,"transit":1}],"sales_orders":[{"id":"a","pending":2,"transit":1}]}
	var before: Dictionary=scene.view.duplicate(true)
	var state: Dictionary=scene._project_city()
	assert(state["stock"]==3 and state["free"]==2 and state["committed"]==1 and state["incoming"]==4)
	assert(state["pending"]==2 and state["transit"]==1)
	assert(scene.view==before and state==scene._project_city())
	scene.observed_supply={"paid":0,"ontime":0,"status":"ACCEPTED"}
	var response: Dictionary={"kind":"advance","ok":true,"view":{"firm":{},"minute":10081,"site":"site:merchant_prototype:paris","supply":{"paid":10,"ontime":2,"quantity":80,"status":"PARTIAL"}}}
	scene._receive(response)
	assert("本次到账＋10" in scene.message and "按时验收2/80" in scene.message)
	var message: String=scene.message
	scene._receive(response)
	assert(scene.message==message)
	scene.observed_orders={"purchase":{"pending":0,"transit":2,"delivered":0,"cancelled":0}}
	response["view"]["firm"]={"orders":[{"id":"purchase","buyer":"firm:merchant_prototype","good":"grain","pending":0,"transit":0,"delivered":2,"cancelled":0}]}
	scene._receive(response)
	assert("到仓：purchase 粮食＋2" in scene.message)
	scene.free()
	print("INPUT07_PASS confirmation_token_consumed duplicate_submit_blocked snapshot_pure cargo_deduplicated actual_payment_notice no_repeat_notice")
	quit()
