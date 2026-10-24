extends SceneTree
const Save=preload("res://merchant/merchant_save.gd")
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	var raw: Dictionary=Save._read(args[0],5)
	check(raw.get("error","").is_empty(),"read original GUI day12 checkpoint")
	var built: WorldBuildResult=FormalPersistence.new().restore_candidate(raw["core"])
	check(built.success,"restore original accepted orders before new NPC policy")
	if not built.success:quit(1);return
	var e: EconomyR1Slice=built.world.economy_r1
	var before: Dictionary=built.persistence.snapshot()
	var site: String="site:regional_food:lyon"
	var offer: Dictionary={}
	for candidate: Dictionary in e._offers("firm:regional_food",site,"bread"):
		if candidate["seller"]=="firm:merchant_prototype":offer=candidate;break
	check(not offer.is_empty(),"same known merchant remains visible as legal supplier")
	var expensive: Dictionary=e._resale_replenishment_observation(site,"bread",offer)
	check(expensive["applicable"] and not expensive["eligible"] and expensive["own_price"]==8 and expensive["landed_unit_cost"]==10,"actual known resale8 versus landed10 optional replenishment rejected")
	var cheap: Dictionary=offer.duplicate(true);cheap["price"]=7
	var reasonable: Dictionary=e._resale_replenishment_observation(site,"bread",cheap)
	check(reasonable["eligible"] and reasonable["landed_unit_cost"]==8,"same seller same source permitted when goods7 plus freight1 covered by resale8 fixture")
	cheap["price"]=6;cheap["freight_per_unit"]=3
	check(not e._resale_replenishment_observation(site,"bread",cheap)["eligible"],"factory6 alone does not hide landed9 above resale8 fixture")
	var production: Dictionary=e._resale_replenishment_observation("site:regional_food:paris","grain",cheap)
	check(not production["applicable"] and production["eligible"],"production purpose not blocked by branch resale rule")
	check(e._supply.procurement_hold("site:regional_food:paris","grain")==0,"unaccepted current published opportunity is not committed inbound coverage")
	check(before==built.persistence.snapshot(),"observation and candidate filtering leave original money lots orders unchanged")
	# Explicit in-memory responsibility fixtures, never saved or executed.
	var saved_records: Dictionary=e._supply.records.duplicate(true)
	var need_by: int=int(e._input_need(site,"bread")["need_by_day"])*1440
	var fixture: Dictionary={"id":"qa:resale_supply","supplier_site":site,"buyer_site":"site:regional_textile:paris","good":"bread","quantity":3,"allocated":1,"ended_minute":-1,"deadline":need_by}
	e._supply.records[fixture["id"]]=fixture
	check(e._resale_replenishment_observation(site,"bread",offer)["eligible"],"existing accepted supply purpose retains explicit fulfilment even if resale buffer would reject fixture")
	fixture["supplier_site"]="site:merchant_prototype:paris";fixture["buyer_site"]=site
	check(e._supply.procurement_hold(site,"bread")==2,"parent3 allocated child1 leaves only unallocated2 future coverage fixture")
	fixture["deadline"]=need_by+1440
	check(e._supply.procurement_hold(site,"bread")==2,"late parent retains total responsibility rather than disappearing from stock position fixture")
	var future_responsibility: Dictionary=e._input_incoming_observation(site,"bread",need_by/1440)
	var parent_unknown: bool=false
	for batch: Dictionary in future_responsibility["batches"]:
		if batch.get("supply_contract_id","")==fixture["id"]:
			parent_unknown=int(batch["quantity"])==2 and batch["earliest_arrival_day"]==null and batch["observed_arrival_day"]==null
	check(parent_unknown,"unallocated parent deadline is not a scheduled arrival or timely coverage fixture")
	fixture["deadline"]=need_by;fixture["ended_minute"]=built.world.game_clock.total_minutes()
	check(e._supply.procurement_hold(site,"bread")==0,"ended responsibility does not cover further procurement fixture")
	e._supply.records=saved_records
	for active_site: String in e._site_ids():
		for good: String in e._goods:
			var position: Dictionary=e._input_incoming_observation(active_site,good,e.day+4)
			var total: int=int(position["accepted_pending"])+int(position["in_transit"])
			check(total==e._exposure(active_site,good)-int(e._stocks[active_site][good]),"original active responsibility counted once %s %s"%[active_site,good])
			check(total+int(position["unallocated_contract"])==int(position["earliest_by_need"])+int(position["known_late"])+int(position["unknown_arrival"]),"ETA classes partition child orders plus unallocated parent responsibility once %s %s"%[active_site,good])
	check(before==built.persistence.snapshot(),"all isolated fixture state restored exactly")
	var restored: WorldBuildResult=FormalPersistence.new().restore_candidate(before)
	check(restored.success,"pre-policy historical buyback remains restorable")
	if restored.success:check(restored.persistence.snapshot()["economy_native"]==before["economy_native"],"existing orders receipts and lots preserved after restore")
	print("QA_SALES_REPLENISHMENT failures=",failures,"; fixture eligibility is not a new executed sale or proof of endless-cycle absence")
	quit(1 if failures else 0)
