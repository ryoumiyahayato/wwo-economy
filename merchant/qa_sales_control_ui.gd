extends SceneTree
## Fixture-based UI assertions, not a normal GUI playthrough. Parent schedules execution.
const Opening=preload("res://merchant/merchant_opening.gd")
const DecisionView=preload("res://merchant/merchant_decision_projection.gd")
class QuietScene:
	extends "res://merchant/merchant_scene.gd"
	var sent: Array[Dictionary]=[]
	func _start() -> void:pass
	func _process(_delta: float) -> void:pass
	func _observe() -> void:pass
	func _send(kind: String,payload: Dictionary={}) -> void:sent.append({"kind":kind,"payload":payload.duplicate(true)})
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var scene=QuietScene.new();root.add_child(scene);await process_frame
	scene.world_ready=true;scene.busy=false;scene.pending_requests.clear()
	var listing: Dictionary={"sales_control_supported":true,"sales_paused":false,"active":true,"price":8,"expires_minute":20000,"stock_quantity":3,"free_quantity":2,"reserved_quantity":1,"reserved_order_ids":["old-sale"],"locked_sales":[{"id":"old-sale","price":8}],"future_quotes":[{"price":9,"effective_minute":17280}]}
	var op: Dictionary={"site_id":Opening.SITE,"stock_place_id":"place:paris","inventory":{"bread":3},"free_inventory":{"bread":2},"committed_inventory":{"bread":1},"incoming":{},"quotations":{"bread":{"listing":listing}}}
	var historic: Dictionary={"id":"old-sale","kind":"SALE","seller":Opening.FIRM,"buyer":"firm:regional_food","seller_site":Opening.SITE,"buyer_site":"site:regional_food:lyon","good":"bread","quantity":2,"price":9,"pending":0,"transit":0,"delivered":2,"shipments":[{"to_place_id":"place:lyon","from_place_id":"place:paris","quantity":2,"stage":"DELIVERED"}]}
	scene.view={"cash":318,"reserved":0,"operations":[op],"orders":[],"sales_orders":[historic]}
	scene.snapshot={"slot":5,"site":Opening.SITE,"player_place":"place:paris","personal_available":2500,"opportunities":[],"business":{"offers":[]},"market_feedback":{},"trade_review":{}}
	scene.selected_site=Opening.SITE;scene.selected_place="place:lyon";scene._refresh()
	assert(scene.home_hint.text.contains("本人在巴黎") and scene.home_hint.text.contains("浏览里昂"))
	assert(scene.facilities[4].visible and not scene.facilities[4].disabled)
	assert(scene._freight_summary().contains("当前无未结货运；历史到货1条"))
	scene._enter_facility(4);assert(scene.selected_tab==6 and scene.detail.text.contains("里昂食品分店"))
	scene._secondary();assert(scene.selected_tab==2 and scene.order_key=="old-sale")
	scene._select_place("place:paris");assert(scene.cargo_buttons[0].visible);scene._inspect_cargo(0)
	assert(scene.selected_site==Opening.SITE and scene.selected_good=="bread" and scene.sales_control.visible)
	assert(scene.detail.text.contains("在库3") and scene.detail.text.contains("自由2") and scene.detail.text.contains("承诺1") and scene.detail.text.contains("未来价9"))
	var before: Dictionary=scene.view.duplicate(true)
	scene._preview_sales_control()
	assert(scene.confirm_kind=="sales_control" and scene.confirm_payload=={"site":Opening.SITE,"good":"bread","paused":true})
	assert(scene.sent.is_empty() and scene.view==before and scene.confirm_expand.visible)
	assert(scene.confirm_detail.text.contains("旧订单") and not scene.confirm_expanded)
	scene._confirm_details_action("details");assert(scene.confirm_expanded and scene.confirm_detail.text.contains("原控制边界"))
	scene._confirm();scene.dialog.hide()
	assert(scene.sent.size()==1 and scene.sent[0]["kind"]=="sales_control" and scene.view==before)
	listing["sales_paused"]=true;listing["active"]=false;scene._refresh()
	assert(scene.sales_control.text.contains("恢复") and scene.detail.text.contains("已暂停") and scene.detail.text.contains("未来价9"))
	scene._preview_sales_control();assert(scene.confirm_payload["paused"]==false)
	scene._cancel_preview();scene.dialog.hide();assert(scene.sent.size()==1)
	scene.snapshot["save_pending"]=true;scene._refresh();assert(scene.sales_control.disabled)
	scene._preview_sales_control();assert(scene.confirm_kind.is_empty())
	scene.snapshot["save_pending"]=false
	var comparison: Dictionary={"requested_quantity":2,"acceptable_quantity":2,"supplier_price":8,"goods_commitment":16,"inbound_freight_commitment":2,"maximum_cash_commitment":18,"own_listing":listing,"scenario":{"known":false}}
	var offer: Dictionary={"good":"bread","price":8,"freight_per_unit":1,"expires_minute":19000,"earliest_arrival_day":12,"comparison":comparison,"request":{"quantity":2},"seller_site":"site:regional_food:lyon","route_id":"route-fixture","can_order":true}
	scene.display_offers.assign([offer]);scene.offer_key=scene._offer_key(offer);scene._show_trade_preview()
	assert(scene.confirm_detail.text.contains("最高现金承诺18") and scene.confirm_detail.text.contains("已暂停") and scene.confirm_detail.text.contains("后续配送费用：未知"))
	assert(not scene.confirm_detail.text.contains("route-fixture") and scene.confirm_rules.contains("route-fixture"))
	scene._confirm_details_action("details");assert(scene.confirm_detail.text.contains("route-fixture"))
	scene._cancel_preview();scene.dialog.hide();assert(scene.sent.size()==1)
	comparison["maximum_cash_commitment"]=null
	assert(DecisionView.purchase_summary_text(offer,"目的仓","来源").contains("最高现金承诺未知"))
	scene._return_city()
	for size: Vector2 in [Vector2(960,600),Vector2(1180,812),Vector2(1280,600)]:
		scene.layout_size=size;scene._layout_controls();scene._refresh_priority_notice()
		for facility: Button in scene.facilities:
			assert(facility.size.x>=100 and facility.size.y>=80)
			assert(facility.get_rect().end.x<=size.x and facility.get_rect().end.y<scene.home_goal.position.y)
		assert(scene.home_goal.get_rect().end.y<=scene.notice.position.y)
		assert(scene.payment_notice.get_rect().end.y<=scene.buttons[0].position.y)
		assert(not scene.home_next.visible)
	# Completed residents have no buyer_site and may have no remaining shipments.
	var resident: Dictionary=historic.duplicate(true)
	resident.merge({"id":"resident-sale","buyer":"cohort:regional:paris_food","buyer_site":"","to_place_id":"place:paris","shipments":[]},true)
	scene.view["sales_orders"]=[resident];scene.snapshot["opportunities"]=[]
	scene.selected_place="place:paris"
	assert(scene._local_sales_orders().size()==1 and scene._buyer_sales_text().contains("已成交居民买方"))
	scene.selected_place="place:lyon"
	assert(scene._local_sales_orders().is_empty() and scene._buyer_label()=="暂无已知买方")
	scene.selected_place="place:paris";scene.selected_contract="selected-textile"
	scene.snapshot["opportunities"]=[{"id":"food","buyer_site":"site:regional_food:paris"},{"id":"selected-textile","buyer_site":"site:regional_textile:paris"}]
	assert(scene._buyer_label()=="巴黎纺织分店")
	scene.queue_free();await process_frame
	print("QA_SALES_CONTROL_UI_PASS fixture_only facilities local_city history pause_resume_payload save_pending concise_details responsive")
	quit()
