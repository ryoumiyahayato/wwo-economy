extends SceneTree
const Opening=preload("res://merchant/merchant_opening.gd")
const DecisionView=preload("res://merchant/merchant_decision_projection.gd")
class QuietScene:
	extends "res://merchant/merchant_scene.gd"
	func _start() -> void:pass
	func _process(_delta: float) -> void:pass
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var scene=QuietScene.new();root.add_child(scene);await process_frame
	scene.world_ready=true;scene.busy=false;scene.pending_requests.clear()
	var event: Dictionary={"event_id":"ledger:p1","kind":"payment","priority":100,"minute":7201,"text":"面包1单位已交付，实收8","order_id":"o1","receipt_id":"r1","payment_ids":["p1"],"amount":8}
	var state: Dictionary={"firm":{"cash":318,"reserved":0,"operations":[],"orders":[],"sales_orders":[]},"minute":7201,"site":Opening.SITE,"slot":5,"opportunities":[],"business":{},"market_feedback":{"events":[event]}}
	scene._receive({"id":1,"kind":"observe","generation":1,"ok":true,"result":{},"view":state})
	assert(scene.priority_payment.get("event_id")=="ledger:p1")
	var count: int=scene.news.size();scene._receive({"id":2,"kind":"observe","generation":1,"ok":true,"result":{},"view":state});assert(scene.news.size()==count)
	assert(scene.payment_notice.visible and not scene.notice.visible)
	var quote: Dictionary={"event_id":"q1","kind":"quote","minute":7300,"text":"普通报价更新"}
	state["market_feedback"]["events"].push_front(quote)
	scene._receive({"id":3,"kind":"observe","generation":1,"ok":true,"result":{},"view":state});assert(scene.priority_payment.get("event_id")=="ledger:p1")
	scene._receive({"id":4,"kind":"save","generation":1,"ok":false,"result":{"message":"Injected failure","save_pending":true},"view":state});assert(not scene.critical_notice.is_empty() and not scene.payment_notice.visible)
	scene._receive({"id":5,"kind":"save","generation":1,"ok":true,"result":{},"view":state});assert(scene.critical_notice.is_empty() and scene.payment_notice.visible)
	scene._receive({"id":6,"kind":"switch","generation":1,"ok":false,"result":{},"view":state});assert(scene.priority_payment.get("event_id")=="ledger:p1")
	scene._receive({"id":7,"kind":"switch","generation":2,"ok":true,"result":{},"view":state});assert(scene.priority_payment.is_empty() and scene.observed_payment_events.has("ledger:p1"))
	scene.priority_payment=event.duplicate(true);scene._open_payment_receipt();assert(scene.selected_tab==2 and scene.order_key=="o1" and scene.priority_payment.is_empty())
	scene.snapshot["opportunities"]=[{"id":"due","accept_action":"accepted","status":"ACCEPTED","deadline":8000,"good":"bread","remaining":2}]
	assert(not scene._deadline_notice().is_empty())
	scene.snapshot["opportunities"]=[]
	var minute: int=scene.current_minute;var stale: Dictionary=state.duplicate(true);stale["minute"]=1
	scene._receive({"id":8,"kind":"observe","generation":1,"ok":true,"result":{},"view":stale});assert(scene.current_minute==minute)
	var c: Dictionary={"requested_quantity":2,"acceptable_quantity":2,"supplier_price":8,"goods_commitment":16,"inbound_freight_commitment":2,"maximum_cash_commitment":18,"own_listing":{"active":true,"price":8,"free_quantity":0,"reserved_quantity":0,"future_quotes":[]},"scenario":{"known":true,"sales_amount":16,"known_cash_difference":-2}}
	var offer: Dictionary={"good":"bread","price":8,"freight_per_unit":1,"comparison":c}
	var text: String=DecisionView.purchase_text(offer,"巴黎销售仓","里昂食品厂")
	assert(text.contains("18") and text.contains("-2") and text.contains("不是成交预测") and text.contains("后续配送费用：未知"))
	c["scenario"]={"known":false};c["maximum_cash_commitment"]=null
	assert(DecisionView.purchase_text(offer,"仓库","货源").contains("最高现金承诺未知"))
	var denied_source: Dictionary={"price":8,"freight_per_unit":1,"quantity":80,"comparison":{"acceptable_quantity":0},"seller_site":"site:regional_food:lyon"}
	var opportunity_text: String=scene._opportunity_preview({"quantity":80,"free_stock":0,"good":"bread","known_sources":[denied_source]})
	assert(opportunity_text.contains("可执行0") and not opportunity_text.contains("运费720"))
	scene.confirm_kind="buy";scene.confirm_payload={"quantity":1};scene._cancel_preview();assert(scene.confirm_kind.is_empty() and scene.confirm_payload.is_empty())
	for size: Vector2 in [Vector2(960,600),Vector2(1180,812)]:
		scene.layout_size=size;scene._layout_controls();scene._refresh_priority_notice();assert(scene.payment_notice.position.y+scene.payment_notice.size.y<=size.y)
	scene.queue_free();await process_frame
	print("QA_DECISIONS_UI_PASS ledger event dedup, priority, retry, generation isolation, historical reopen, comparison unknown/cancel, desktop dimensions")
	quit()
