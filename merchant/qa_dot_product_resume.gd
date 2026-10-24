extends SceneTree
## Cold restore of original day16 product save; observations only, no seeded transactions.
const Save = preload("res://merchant/merchant_save.gd")
const Opening = preload("res://merchant/merchant_opening.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var args := OS.get_cmdline_user_args()
	var raw: Dictionary = Save._read(args[0], 5)
	assert(raw.get("error", "").is_empty())
	var b: WorldBuildResult = FormalPersistence.new().restore_candidate(raw["core"])
	assert(b.success, b.error)
	var e: EconomyR1Slice = b.world.economy_r1
	var before: Dictionary = b.persistence.snapshot()
	var different: Array = []
	for key: Variant in raw["core"]:
		if raw["core"][key] != before.get(key): different.append(key)
	var person: String = b.world.player_state.player_id()
	var offers: Array = []
	var offset: int = 0
	while true:
		var business: Dictionary = e.business_view(person, Opening.FIRM, Opening.SITE, 2, offset, 16)
		offers.append_array(business.get("offers", []))
		offset += 16
		if offset >= int(business.get("offer_total", 0)): break
	var opportunities: Array = e.supply_business_view(person)
	var personal: Dictionary = LivelihoodAction.query(b.world, person)
	var record := {"origin":"dot", "source_sha256":FileAccess.get_sha256(args[0]), "minute":b.world.game_clock.total_minutes(), "cash":b.world.ledger_state.balance(e._account(Opening.FIRM)), "personal_cash":personal.get("cash"), "bread":e._stocks[Opening.SITE]["bread"], "sales_paused":e._local_quotes.sales_paused(Opening.SITE, "bread"), "restore_different_fields":different, "offers":offers, "opportunities":opportunities, "review":e.managed_trade_review(person, Opening.FIRM), "query_unchanged":before == b.persistence.snapshot(), "scope":"COLD_PRODUCT_RESTORE_AND_READ_ONLY_PRECONDITIONS_NOT_GUI_FULFILMENT"}
	var f := FileAccess.open(args[1], FileAccess.WRITE)
	assert(f != null); f.store_string(JSON.stringify(record, "\t")); f.close()
	assert(different.is_empty(), "All original product snapshot fields must restore equally: " + str(different))
	assert(record["minute"] == 21601 and record["cash"] == 318 and record["personal_cash"] == 2500 and record["bread"] == 0 and record["sales_paused"])
	assert(before == b.persistence.snapshot(), "Offer/supply queries must not mutate the world")
	print("QA_DOT_PRODUCT_RESUME_PASS exact day16 original continuation and pure business queries")
	quit()
