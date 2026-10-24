extends SceneTree
const Save=preload("res://merchant/merchant_save.gd")
const Opening=preload("res://merchant/merchant_opening.gd")
const View=preload("res://merchant/merchant_decision_projection.gd")
func _initialize() -> void:call_deferred("run")
func offer_for(built: WorldBuildResult,quantity: int) -> Dictionary:
	var e: EconomyR1Slice=built.world.economy_r1
	for offer: Dictionary in e.business_view(built.world.player_state.player_id(),Opening.FIRM,Opening.SITE,quantity,0,16)["offers"]:
		if offer.get("good")=="bread" and offer.get("seller_site")=="site:regional_food:lyon":return offer
	return {}
func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	var raw: Dictionary=Save._read(args[0],5);assert(raw.get("error","").is_empty())
	var built: WorldBuildResult=FormalPersistence.new().restore_candidate(raw["core"]);assert(built.success)
	var e: EconomyR1Slice=built.world.economy_r1;var person: String=built.world.player_state.player_id()
	var core: Dictionary=built.persistence.snapshot()
	var offer: Dictionary=offer_for(built,3)
	assert(not offer["can_order"] and offer["comparison"]["acceptable_quantity"]==2 and offer["comparison"]["maximum_cash_commitment"]==18)
	var unknown: Dictionary=offer.duplicate(true);unknown["freight_per_unit"]=null
	var unknown_view: Dictionary=e._managed_purchase_comparison(person,Opening.FIRM,Opening.SITE,unknown,3)
	assert(unknown_view["maximum_cash_commitment"]==null and not unknown_view["scenario"]["known"])
	assert(core==built.persistence.snapshot(),"Preview/cancel and unknown projection fixture are read only")
	var context: Dictionary=OrganizationState.acting_context(person,Opening.ORGANIZATION,Opening.ORGANIZATION,Opening.REGIONAL_AUTHORITY,"opening_operator")
	var changed: Dictionary=LivelihoodAction.execute_current(built.world,"post_managed_goods_quote",{"firm":Opening.FIRM,"site":Opening.SITE,"good":"bread","price":9,"authorization_context":context});assert(changed["accepted"])
	var preview: Dictionary=offer_for(built,3)["comparison"]
	assert(preview["own_listing"]["price"]==8 and preview["own_listing"]["future_quotes"][0]["price"]==9 and preview["scenario"]["known_cash_difference"]==-2)
	var second_quote: Dictionary=LivelihoodAction.execute_current(built.world,"post_managed_goods_quote",{"firm":Opening.FIRM,"site":Opening.SITE,"good":"bread","price":10,"authorization_context":context});assert(not second_quote["accepted"] and second_quote["reason"]=="GOODS_QUOTE_ALREADY_POSTED_TODAY")
	var partial: Dictionary=LivelihoodAction.execute_current(built.world,"buy",offer["request"]);assert(partial["accepted"] and partial["quantity"]==2)
	assert(built.world.ledger_state.reserved_balance("account:merchant_prototype")==18)
	var ledger: Dictionary=built.world.ledger_state.snapshot();var stocks: Dictionary=e._stocks.duplicate(true);var count: int=e._orders.size()
	var duplicate: Dictionary=LivelihoodAction.execute_current(built.world,"buy",offer["request"]);assert(not duplicate["accepted"] and e._orders.size()==count and ledger==built.world.ledger_state.snapshot() and stocks==e._stocks)
	assert(built.simulation_step.advance_minutes(60).get("success",true))
	ledger=built.world.ledger_state.snapshot();stocks=e._stocks.duplicate(true)
	var stale: Dictionary=LivelihoodAction.execute_current(built.world,"buy",offer["request"]);assert(not stale["accepted"] and stale["reason"]=="EXPIRED_QUOTE" and ledger==built.world.ledger_state.snapshot() and stocks==e._stocks)
	for order: Dictionary in e._orders.values():
		if order["seller"]==Opening.FIRM and int(order["accepted_minute"])<7201:assert(order["price"]==8)
	print("QA_DECISIONS_BOUNDARIES_PASS partial requested3 accepted2 promise18; no-money preview; unknown cost fixture; future9 current8; daily quote limit; repeated buy no new order; expired quote no cash/stock; old locked8")
	quit()
