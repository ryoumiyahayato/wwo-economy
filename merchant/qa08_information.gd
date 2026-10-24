extends SceneTree
## Synthetic information-boundary fixtures only. No save, purchase or UI action.
const Opening=preload("res://merchant/merchant_opening.gd")
class ReadOnlyScene:
	extends "res://merchant/merchant_scene.gd"
	func _start() -> void:
		# Override the deferred worker start: never open or write user save slots.
		pass

var failures: int=0
var built: WorldBuildResult

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool,label: String) -> bool:
	if ok:print("QA08_INFORMATION_CHECK ",label)
	else:
		failures+=1
		push_error("QA08_INFORMATION_FAIL "+label)
	return ok

func raw_offer() -> Dictionary:
	return {"seller_site":Opening.COMPETITOR_SITE,"good":"grain","quote_id":"qa:synthetic","price":73,"quantity":17,"transport_quantity":17,"reason":"OFFER"}

func hidden_capacity(row: Dictionary) -> bool:
	return not row.has("transport_quantity") or row["transport_quantity"]==null or row["transport_quantity"]==0

func run() -> void:
	built=WorldBootstrap.new().build(null,[],[],FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT,false,{"format":"HOST_REGION_SELECTION","person_ids":[],"select_people_at_sites":true,"configuration":Opening.opportunities_configuration()})
	if not check(built.success,"build: "+built.error):quit(1);return
	if not check(Opening.grant_regional_authority(built.world),"authority"):quit(1);return
	var e: EconomyR1Slice=built.world.economy_r1
	var actor: String=built.world.player_state.player_id()
	var originals: Dictionary=e._receipts.duplicate(true)
	var original_quotes: Dictionary=e._local_quotes.quotes.duplicate(true)
	var original_saved: Dictionary=e._local_quotes.saved_receipts.duplicate(true)
	e._local_quotes.saved_receipts={}
	# Remove only quote notices; supplier introductions remain unchanged.
	for key: Variant in e._receipts.keys():
		if e._receipts[key].get("kind")=="goods_quote":e._receipts.erase(key)
	var unknown: Dictionary=e._local_quotes.offer(Opening.SITE,raw_offer())
	check(unknown.get("reason")=="GOODS_QUOTE_NOT_RECEIVED","unknown quote fixture")
	check(hidden_capacity(unknown),"unknown quote hides transport_quantity")
	var c: Dictionary=e._supply.view(actor)
	check(c.get("competitor",{}).get("price")==null,"unknown competitor price stays unknown")
	var old: Dictionary=e._local_quotes.current(Opening.COMPETITOR_SITE,"grain").duplicate(true)
	if not check(not old.is_empty(),"competitor quote exists"):quit(1);return
	old["id"]="qa:received:competitor";old["version"]=100;old["price"]=41;old["effective_day"]=0;old["expires_day"]=100
	var newer: Dictionary=old.duplicate(true)
	newer["id"]="qa:unreceived:competitor";newer["version"]=101;newer["price"]=73
	e._local_quotes.quotes[old["id"]]=old
	e._local_quotes.quotes[newer["id"]]=newer
	e._receipts["qa:quote:receipt"]={"id":"qa:quote:receipt","actor":Opening.SITE,"kind":"goods_quote","candidate":old["id"],"observed_day":0,"delivery_day":0,"source_receipt":"qa:fixture"}
	check(e._local_quotes.known(Opening.SITE,Opening.COMPETITOR_SITE,"grain")["price"]==41 and e._local_quotes.current(Opening.COMPETITOR_SITE,"grain")["price"]==73,"known/current prices deliberately differ")
	c=e._supply.view(actor)
	check(c.get("competitor",{}).get("price")==41,"competitor price comes from received quote")
	var superseded: Dictionary=e._local_quotes.offer(Opening.SITE,raw_offer())
	check(superseded.get("reason")=="GOODS_QUOTE_SUPERSEDED","superseded quote fixture")
	check(hidden_capacity(superseded),"superseded quote hides transport_quantity")
	e._local_quotes.quotes.erase(newer["id"])
	old["expires_day"]=0
	var expired: Dictionary=e._local_quotes.offer(Opening.SITE,raw_offer())
	check(expired.get("reason")=="GOODS_QUOTE_EXPIRED","expired quote fixture")
	check(hidden_capacity(expired),"expired quote hides transport_quantity")
	# Restore synthetic modifications before the genuine read-only UI fixture.
	e._receipts=originals;e._local_quotes.quotes=original_quotes;e._local_quotes.saved_receipts=original_saved
	var before: Dictionary=built.persistence.snapshot()
	var opportunities: Array[Dictionary]=e.supply_business_view(actor)
	if not check(not opportunities.is_empty(),"UI has original genuine contract"):quit(1);return
	var scene:=ReadOnlyScene.new()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	scene.snapshot={"slot":4,"supply":opportunities[0],"opportunities":opportunities,"business":{},"travel":{},"regions_by_place":{},"player_place":"place:paris"}
	scene.view={};scene.world_ready=true;scene.busy=false;scene.city_home=false;scene.selected_tab=6
	scene._refresh()
	check(scene.row_select.item_count>0,"page6 has selectable contracts")
	check(scene.row_select.visible and not scene.row_select.disabled,"page6 normal row_select enabled")
	check(scene.runtime==null,"UI fixture never starts worker")
	check(before==built.persistence.snapshot(),"information and UI queries do not mutate authoritative snapshot")
	scene.free()
	built=null
	print("QA08_INFORMATION_RESULT failures=",failures)
	quit(0 if failures==0 else 1)
