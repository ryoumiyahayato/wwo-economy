extends RefCounted
## Indicator algorithm owned by FormalWorldEconomyState. No accounts, lots,
## purchase API or independent clock. Estimated cover cannot be handed over.
const FORMAT="GLOBAL_COMMODITY_REFERENCE_V1"
const BASIS="DEVELOPMENT_SCENARIO_NOT_VERIFIED_1900_STATISTICS"
const GOODS=["wheat","coal","iron_ore","steel","copper","timber","raw_cotton","wool","crude_petroleum","sugar","coffee","natural_rubber","rice","maize","oilseeds","jute"]
const SAMPLE_BASIS="FINITE_GRAIN_POINTS_V2_DEVELOPMENT_KG_NO_NATIONAL_EXPANSION"
const HISTORY=181
const MAX_DELAY=60
const RATE=[180.0,130.0,75.0,55.0,8.0,65.0,20.0,10.0,22.0,34.0,2.0,3.0,160.0,90.0,18.0,6.0]
var data: Dictionary={}
var _state: WeakRef
var _nodes: Dictionary={}
var _definitions: Dictionary={}
var _inbound: Dictionary={}

func bind(state: RefCounted) -> void:
	_state=weakref(state)
	for c: Dictionary in state._static_evidence.commodities():_definitions[c.commodity_id]=c
	var file:=FileAccess.open("res://merchant/global_market_scenario.json",FileAccess.READ)
	for n: Dictionary in JSON.parse_string(file.get_as_text()).nodes:_nodes[n.id]=n

func initialize(start_day: int, scenario: String="baseline", copies: int=1) -> void:
	data={"format":FORMAT,"basis":BASIS,"day":start_day,"start_day":start_day,"scenario":scenario,"cells":{},"nodes":{},"edges":[],"arrivals":{},"flows":[],"shocks":[],"local":{},"policy_receipts":{}}
	var state: RefCounted=_state.get_ref()
	for replica: int in copies:
		for record: Dictionary in state._static_evidence.countries():
			var id: String=record.entity_id
			var n: Dictionary=_nodes[id].duplicate(true)
			if replica>0:n.id=id+"#stress"+str(replica)
			n["source_id"]=id;n["market_id"]=state.market_id_for_economic_aggregate(id)
			n["population"]=state.current_population(id)
			n["industry"]=float(record.production.industrial_capacity_index)/100.0
			data.nodes[n.id]=n
			var mineral: Dictionary=record.production.mineral_capacity_index
			for gi: int in GOODS.size():
				var good: String=GOODS[gi]
				var demand: float=maxf(1.0,float(n.population)/1000000.0*RATE[gi])
				if good in ["coal","iron_ore","steel","copper","crude_petroleum","natural_rubber","jute","raw_cotton"]:demand*=0.2+n.industry*1.4
				var factor: float=_capacity(record,good,mineral)
				data.cells[_key(n.id,good)]={"price":100.0,"lag":100.0,"cover":10.0,"base":demand,"capacity":factor,"supply":0.0,"demand":0.0,"absorbed":0.0,"unmet":0.0,"imports":0.0,"exports":0.0,"signal":100.0,"history":[100.0],"pressure":0.0,"cause":"开发情景初值"}
	_build_edges(copies)
	if scenario in ["shocks","shocks_french_wheat","supply","demand","transport"]:
		data.shocks=[{"kind":"supply","node":"united_states_1900","good":"wheat","from":start_day+15,"until":start_day+60,"factor":0.45,"label":"美国小麦产能减产55%"},{"kind":"demand","node":"german_empire","good":"coal","from":start_day+30,"until":start_day+90,"factor":1.65,"label":"德国工业煤需求增加65%"},{"kind":"transport","node":"british_isles_1900","good":"all","from":start_day+45,"until":start_day+75,"factor":0.2,"label":"英国相邻估计通道容量降至20%"}]
		if scenario in ["supply","demand","transport"]:data.shocks=data.shocks.filter(func(s: Dictionary)->bool:return s.kind==scenario)
		# Declared only at initialization. Restore reconstructs and compares this
		# exact event list; callers cannot attach a live shock to a running market.
		if scenario=="shocks_french_wheat":data.shocks.append({"kind":"supply","node":"country_fra","good":"wheat","from":start_day+15,"until":start_day+60,"factor":0.45,"label":"法国小麦参考供给减产55%（开发压力情景）"})

func _capacity(r: Dictionary,g: String,m: Dictionary) -> float:
	var a: float=float(r.production.agriculture_capacity_index)/100.0
	var i: float=float(r.production.industrial_capacity_index)/100.0
	var mineral: String={"crude_petroleum":"petroleum"}.get(g,g)
	if g in ["coal","iron_ore","copper","timber","crude_petroleum"]:return clampf(float(m.get(mineral,10))/48.0,0.08,2.2)
	if g=="steel":return clampf(i*2.0,0.15,1.9)
	# Crop specialization is an explicit bounded scenario, not a historical table.
	var profiles: Dictionary={"wheat":["united_states_1900","russian_empire","argentina_1900","dominion_of_canada","australia_colonies_1900"],"rice":["qing_empire","empire_of_japan","kingdom_of_siam","cshapes_gw_750"],"maize":["united_states_1900","mexican_republic","argentina_1900"],"coffee":["brazil_1900","republic_of_colombia_1900","venezuela_1900"],"sugar":["cuba_occupation_1900","brazil_1900","cshapes_gw_750"],"raw_cotton":["united_states_1900","cshapes_gw_750","khedivate_of_egypt"],"wool":["australia_colonies_1900","argentina_1900","cshapes_gw_920"],"natural_rubber":["brazil_1900","congo_free_state","kingdom_of_siam"],"jute":["cshapes_gw_750"],"oilseeds":["russian_empire","cshapes_gw_750","qing_empire"]}
	return 1.7 if r.entity_id in profiles.get(g,[]) else clampf(0.6+a*0.65,0.4,1.35)

func _build_edges(copies: int) -> void:
	var pairs: Dictionary={}
	var state: RefCounted=_state.get_ref()
	for replica: int in copies:
		var suffix: String="" if replica==0 else "#stress"+str(replica)
		for r: Dictionary in state.routes:
			_add_edge(str(r.from)+suffix,str(r.to)+suffix,maxi(1,int(r.duration_hours)/24),"EXISTING_AGGREGATE_CORRIDOR",pairs)
		# Geography is used once at setup; daily matching is O(edges * goods).
		for id: String in _nodes:
			var candidates: Array=[]
			for other: String in _nodes:
				if other!=id:candidates.append({"id":other,"distance":_distance(_nodes[id].lon_lat,_nodes[other].lon_lat)})
			candidates.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return a.distance<b.distance)
			for j: int in mini(3,candidates.size()):
				_add_edge(id+suffix,str(candidates[j].id)+suffix,maxi(1,int(ceil(float(candidates[j].distance)/1800.0))),"DEVELOPMENT_PROXIMITY_REFERENCE_LINK_NOT_PHYSICAL_ROUTE",pairs)

func _add_edge(a: String,b: String,days: int,basis: String,pairs: Dictionary) -> void:
	if not data.nodes.has(a) or not data.nodes.has(b):return
	var k: String=(a+"|"+b) if a<b else (b+"|"+a)
	if pairs.has(k):return
	pairs[k]=true
	var length: float=_distance(data.nodes[a].lon_lat,data.nodes[b].lon_lat)
	var capacity: float=0.0
	for good: String in GOODS:capacity+=minf(data.cells[_key(a,good)].base,data.cells[_key(b,good)].base)*0.16
	data.edges.append({"a":a,"b":b,"days":clampi(days,1,MAX_DELAY),"capacity":maxf(1.0,capacity),"friction":0.025+length/180000.0,"basis":basis})

func _distance(a: Array,b: Array) -> float:
	var x:=Vector2(deg_to_rad(float(a[0])),deg_to_rad(float(a[1])))
	var y:=Vector2(deg_to_rad(float(b[0])),deg_to_rad(float(b[1])))
	return acos(clampf(sin(x.y)*sin(y.y)+cos(x.y)*cos(y.y)*cos(x.x-y.x),-1.0,1.0))*6371.0

func _key(n: String,g: String) -> String:return n+"|"+g

func _factor(kind: String,node: String,good: String,day: int) -> float:
	var result:=1.0
	for s: Dictionary in data.shocks:
		if s.kind==kind and s.node==node and (s.good==good or s.good=="all") and day>=int(s.from) and day<int(s.until):result*=float(s.factor)
	return result

func settle(day: int,native: RefCounted=null) -> void:
	if data.is_empty() or day<=int(data.day):return
	assert(day==int(data.day)+1,"Reference market must follow each formal day boundary")
	data.day=day;data.flows=[]
	_observe_native(native)
	var arriving: Dictionary=data.arrivals.get(str(day),{})
	data.arrivals.erase(str(day))
	var signals: Dictionary=_delayed_signals(day)
	for id: String in data.nodes:
		var steel_index: float=data.cells[_key(id,"steel")].lag
		for good: String in GOODS:
			var k:=_key(id,good);var c: Dictionary=data.cells[k]
			var a: Dictionary=arriving.get(k,{})
			c.imports=float(a.get("units",0.0));c.exports=0.0
			var received_signal: Dictionary=signals.get(k,{})
			var weight_sum: float=float(a.get("weight",0.0))+float(received_signal.get("weight",0.0))
			if weight_sum>0:c["signal"]=(float(a.get("signal",0.0))+float(received_signal.get("sum",0.0)))/weight_sum
			var price: float=c.price
			var industry: float=1.0
			if good in ["coal","iron_ore","natural_rubber"]:
				industry=0.8+0.2*steel_index/100.0
			c.demand=float(c.base)*pow(price/100.0,-0.22)*industry*_factor("demand",id,good,day)
			c.supply=float(c.base)*float(c.capacity)*clampf(0.65+0.35*float(c.lag)/100.0,0.6,1.5)*_factor("supply",id,good,day)
			# Only the explicitly reserved finite developer block is replaced. Unit
			# conversion (kg -> t), census scope and weight=1 are independent.
			if good=="wheat" and data.local.get("basis")==SAMPLE_BASIS and data.local.adopt_flows:
				var sample: Dictionary=data.local.regions.get(id,{})
				if not sample.is_empty():
					c.supply=maxf(0.0,c.supply-float(sample.baseline_produced)+float(sample.produced_tonnes))
					c.demand=maxf(0.0,c.demand-float(sample.baseline_used)+float(sample.used_tonnes))
			var estimated: float=float(c.cover)*float(c.base)+float(c.supply)+float(c.imports)
			c.absorbed=minf(estimated,float(c.demand));c.unmet=maxf(0.0,float(c.demand)-float(c.absorbed))
			c.cover=clampf((estimated-float(c.absorbed))/float(c.base)*0.998,0.0,60.0)
			c.pressure=clampf((float(c.demand)-float(c.supply))/float(c.base)+(8.0-float(c.cover))*0.085,-1.8,2.5)
			var target: float=100.0*exp(float(c.pressure)*0.42)
			# Received export-area signal matters most for import dependent regions.
			var weight: float=0.25 if float(c.capacity)<1.0 else 0.08
			target=target*(1.0-weight)+float(c.signal)*weight
			c.price=clampf(lerpf(price,target,0.12),maxf(25.0,price*0.95),minf(400.0,price*1.05))
			c.lag=lerpf(float(c.lag),price,0.08)
			c.cause="缺货" if float(c.unmet)>0 else "供给低于需求" if float(c.supply)<float(c.demand) else "供给和缓冲充足"
			if c.history.size()<HISTORY:c.history.append(snappedf(float(c.price),0.01))
			else:c.history[(day-int(data.start_day))%HISTORY]=snappedf(float(c.price),0.01)
	# Capacity is shared by ALL commodities and directions on each edge per day.
	_inbound.clear()
	for bucket: Dictionary in data.arrivals.values():
		for k: String in bucket:_inbound[k]=float(_inbound.get(k,0.0))+float(bucket[k].units)
	var offset: int=day%maxi(1,data.edges.size())
	for j: int in data.edges.size():
		var edge: Dictionary=data.edges[(j+offset)%data.edges.size()]
		var capacity: float=float(edge.capacity)*minf(_factor("transport",edge.a,"all",day),_factor("transport",edge.b,"all",day))
		var choices: Array=[]
		for good: String in GOODS:
			var ca: Dictionary=data.cells[_key(edge.a,good)];var cb: Dictionary=data.cells[_key(edge.b,good)]
			var origin: String=edge.a if float(ca.price)<float(cb.price) else edge.b
			var dest: String=edge.b if origin==edge.a else edge.a
			var src: Dictionary=data.cells[_key(origin,good)];var dst: Dictionary=data.cells[_key(dest,good)]
			var spread: float=float(dst.price)-float(src.price)*(1.0+float(edge.friction))
			if spread>0 and float(src.cover)>6 and float(dst.cover)<10:choices.append({"origin":origin,"dest":dest,"good":good,"spread":spread})
		choices.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return a.spread>b.spread)
		for choice: Dictionary in choices:
			if capacity<=0.00001:break
			var src: Dictionary=data.cells[_key(choice.origin,choice.good)];var dst: Dictionary=data.cells[_key(choice.dest,choice.good)]
			var inbound: float=_incoming(choice.dest,choice.good)
			var quantity: float=minf(capacity,minf(maxf(0.0,(float(src.cover)-6.0)*float(src.base)),maxf(0.0,(10.0-float(dst.cover))*float(dst.base)-inbound)))
			if quantity<=0.00001:continue
			src.cover-=quantity/float(src.base);src.exports+=quantity;capacity-=quantity
			_schedule(day+int(edge.days),_key(choice.dest,choice.good),quantity,float(src.price)*(1.0+float(edge.friction)))
			data.flows.append({"from":choice.origin,"to":choice.dest,"good":choice.good,"estimated_units":quantity,"arrival_day":day+int(edge.days),"basis":edge.basis})
	# Explicit public reference subscriptions. These confer no supplier discovery,
	# trade authority or executable prices. Original quote notices still use R1.
	if native!=null:
		for rule: Dictionary in native._local_quotes.rules():
			if rule.good!="grain":continue
			var notice: Dictionary=bulletin("country_fra","wheat",day)
			if notice.is_empty():continue
			notice["recipient"]=rule.firm
			notice["id"]="public_index:"+str(rule.firm)+":wheat:"+str(notice.observed_day)
			data.policy_receipts[str(rule.firm)+"|wheat"]=notice

func _delayed_signals(day: int) -> Dictionary:
	# Read only already published historical indices after the edge's information
	# delay. No queue entry per commodity/day is needed for the same public series.
	var result: Dictionary={}
	for edge: Dictionary in data.edges:
		var observed: int=day-int(edge.days)
		if observed<int(data.start_day):continue
		for good: String in GOODS:
			for direction: Array in [[edge.a,edge.b],[edge.b,edge.a]]:
				var key:=_key(direction[1],good)
				if not result.has(key):result[key]={"sum":0.0,"weight":0.0}
				result[key].sum+=float(data.cells[_key(direction[0],good)].history[(observed-int(data.start_day))%HISTORY])*(1.0+float(edge.friction))
				result[key].weight+=1.0
	return result

func _schedule(day: int,key: String,units: float,index_value: float) -> void:
	var date:=str(day)
	if not data.arrivals.has(date):data.arrivals[date]={}
	if not data.arrivals[date].has(key):data.arrivals[date][key]={"units":0.0,"signal":0.0,"weight":0.0}
	var a: Dictionary=data.arrivals[date][key];a.units+=units;a["signal"]+=index_value;a.weight+=1.0
	_inbound[key]=float(_inbound.get(key,0.0))+units

func _incoming(node: String,good: String) -> float:
	return float(_inbound.get(_key(node,good),0.0))

func native_region(e: RefCounted,place: String) -> String:
	var row: Dictionary=e._world.spatial_catalog.get_place(place)
	var parent: String=str(row.get("parent_country_id",""))
	if parent=="country_fra":return "country_fra"
	# London city and port remain separate places. A polity's overseas territory
	# is not automatically part of the British Isles statistical aggregate.
	# Exact London-place crosswalk: host catalog parent is british_empire; the
	# existing market scenario anchors british_isles_1900 at London. These IDs
	# are different domains, not equality of country and statistical identities.
	if place in ["place:london","place:port_london"] and parent=="british_empire" and data.nodes.has("british_isles_1900"):return "british_isles_1900"
	return ""

func _observe_native(e: RefCounted) -> void:
	if e==null:return
	var minute: int=e._world.game_clock.total_minutes()
	var previous: Dictionary=data.local
	# Restoring a legacy snapshot does not backfill or silently migrate its scope.
	if not previous.is_empty() and previous.get("basis")!=SAMPLE_BASIS:return
	if previous.get("through_minute",-1)==minute:return
	var opening: bool=previous.is_empty()
	var points: Dictionary=previous.get("points",{}).duplicate(true)
	if opening:
		for point: String in e._physical_totals:
			var place: String=e._place(point)
			var region: String=native_region(e,place)
			if region.is_empty():continue
			var totals: Dictionary=e._physical_totals[point]
			var active_day: int=int(e._subject_activation.get(point,0))/1440
			var days: int=maxi(0,e.day-active_day)
			points[point]={"place":place,"region":region,"produced":int(totals.produced.get("grain",0)),"used":int(totals.used.get("grain",0)),"baseline_days":days,"baseline_produced":float(totals.produced.get("grain",0))*0.001/maxi(1,days),"baseline_used":float(totals.used.get("grain",0))*0.001/maxi(1,days)}
	var regions: Dictionary={}
	for point: String in points:
		var row: Dictionary=points[point]
		if not regions.has(row.region):regions[row.region]={"baseline_produced":0.0,"baseline_used":0.0,"produced_tonnes":0.0,"used_tonnes":0.0,"stock_native":0,"cross_border_delivered_native":0,"adopted_import_tonnes":0.0}
		var r: Dictionary=regions[row.region]
		var current: Dictionary=e._physical_totals.get(point,{"produced":{},"used":{}})
		var produced: int=int(current.produced.get("grain",0));var used: int=int(current.used.get("grain",0))
		# Frozen identities; a relocated/retired point cannot move its historical
		# counters to another region or manufacture a new sample contribution.
		if e._place(point)==row.place and int(row.baseline_days)>0:
			r.baseline_produced+=float(row.baseline_produced);r.baseline_used+=float(row.baseline_used)
			if not opening:
				r.produced_tonnes+=maxi(0,produced-int(row.produced))*0.001
				r.used_tonnes+=maxi(0,used-int(row.used))*0.001
		row.produced=produced;row.used=used
	# Lots are stocks at their actual location. CARGO is never destination stock.
	for portion: Dictionary in e._lots.portions.values():
		if portion.good!="grain" or int(portion.remaining)<=0 or str(portion.location).begins_with("CARGO|"):continue
		var region: String=native_region(e,str(portion.place_id))
		if regions.has(region):regions[region].stock_native+=int(portion.remaining)
	var deliveries: Array=[]
	var cutoff: int=int(previous.get("through_minute",minute))
	for receipt: Dictionary in e._delivery_receipts.values():
		if int(receipt.delivered_minute)<=cutoff or int(receipt.delivered_minute)>minute:continue
		var order: Dictionary=e._orders[receipt.order_id]
		if order.good!="grain":continue
		var origin: String=native_region(e,str(order.from_place_id))
		var destination: String=native_region(e,str(order.to_place_id))
		var cross: bool=not origin.is_empty() and not destination.is_empty() and origin!=destination
		if cross and regions.has(destination):regions[destination].cross_border_delivered_native+=int(receipt.quantity)
		deliveries.append({"receipt_id":receipt.id,"order_id":order.id,"good":order.good,"quantity_native":receipt.quantity,"tonnes":float(receipt.quantity)*0.001,"from_place":order.from_place_id,"to_place":order.to_place_id,"origin_region":origin,"destination_region":destination,"delivered_minute":receipt.delivered_minute,"cross_border":cross,"adopted_import_tonnes":0.0,"overlap":"UNVERIFIED_ESTIMATED_FLOWS_HAVE_NO_IDENTIFIED_NATIVE_CONTRACT_COVERAGE" if cross else "DOMESTIC_TRANSFER_OR_UNKNOWN_REGION_NOT_NEW_SUPPLY"})
	data.local={"basis":SAMPLE_BASIS,"from_minute":cutoff,"through_minute":minute,"adopt_flows":previous.get("adopt_flows",true),"conversion":"DEVELOPMENT_ASSUMPTION_1_NATIVE_GRAIN_UNIT_1_KG_0_001_TONNE","weight":1.0,"scope":"FROZEN_NAMED_NATIVE_POINTS_ONLY","replacement":"DEVELOPMENT_RESERVED_POINT_BLOCK_OPENING_OBSERVED_DAILY_MEAN_NOT_NATIONAL_SAMPLE_ESTIMATE","points":points,"regions":regions,"deliveries":deliveries}

func _native_french_point(e: RefCounted,point: String) -> bool:
	return native_region(e,e._place(point))=="country_fra"

func bulletin(node: String,good: String,day: int) -> Dictionary:
	var c: Dictionary=data.get("cells",{}).get(_key(node,good),{})
	if c.is_empty():return {}
	# Public index bulletin is published with two days' delay, not a supplier quote.
	var age: int=2;var h: Array=c.history
	if day<int(data.start_day)+age or h.size()<=age:return {}
	return {"source":"PUBLIC_REFERENCE_INDEX_SERVICE_DEVELOPMENT","region":node,"commodity":good,"observed_day":int(data.day)-age,"received_day":int(data.day),"valid_until_day":int(data.day)+3,"index":h[(int(data.day)-age-int(data.start_day))%HISTORY],"basis":BASIS,"executable_quote":false}

func received_bulletin(firm: String,good: String,day: int) -> Dictionary:
	var row: Dictionary=data.get("policy_receipts",{}).get(firm+"|"+good,{})
	return row.duplicate(true) if not row.is_empty() and int(row.received_day)<=day and day<int(row.valid_until_day) else {}

func observe() -> Dictionary:
	var result: Dictionary={"day":data.day,"start_day":data.start_day,"basis":BASIS,"nodes":data.nodes.duplicate(true),"goods":[],"cells":data.cells.duplicate(true),"flows":data.flows.duplicate(true),"shocks":data.shocks.duplicate(true),"local":data.local.duplicate(true),"edge_count":data.edges.size(),"reference":{},"bulletins":{}}
	if int(data.day)-int(data.start_day)>=HISTORY:
		var cursor: int=(int(data.day)-int(data.start_day)+1)%HISTORY
		for c: Dictionary in result.cells.values():c.history=c.history.slice(cursor)+c.history.slice(0,cursor)
	for good: String in GOODS:
		result.goods.append({"id":good,"name":_definitions.get(good,{}).get("name_zh",good)})
		var weighted:=0.0;var total:=0.0
		for id: String in data.nodes:
			var c: Dictionary=data.cells[_key(id,good)];weighted+=float(c.price)*float(c.base);total+=float(c.base)
		result.reference[good]=weighted/maxf(1.0,total)
		result.bulletins[good]=bulletin("country_fra",good,data.day)
	return result

func observe_public() -> Dictionary:
	# Development public index service: only published, two-day-old indices.
	# Current balances, buffer estimates, shocks and matching are not disclosed.
	var full: Dictionary=observe()
	var result: Dictionary={"day":int(data.day)-2,"received_day":data.day,"start_day":data.start_day,"basis":BASIS,"visibility":"PUBLIC_DELAYED_INDICES","nodes":full.nodes,"goods":full.goods,"cells":{},"flows":[],"shocks":[],"local":{},"edge_count":data.edges.size(),"reference":{}}
	if int(data.day)<int(data.start_day)+2:return {}
	for good: String in GOODS:
		var sum:=0.0;var weight:=0.0
		for id: String in data.nodes:
			var k:=_key(id,good);var h: Array=full.cells[k].history.slice(0,-2)
			var price: float=h.back()
			result.cells[k]={"price":price,"history":h}
			sum+=price*float(data.cells[k].base);weight+=float(data.cells[k].base)
		result.reference[good]=sum/maxf(1.0,weight)
	return result

func restore(value: Variant,total_day: int) -> bool:
	if not value is Dictionary or value.get("format")!=FORMAT or value.get("basis")!=BASIS or not value.get("day") is int or value.day!=total_day:return false
	if not FormalLedgerState.exact_fields(value,["format","basis","day","start_day","scenario","cells","nodes","edges","arrivals","flows","shocks","local","policy_receipts"]):return false
	if not value.get("start_day") is int or value.start_day<0 or value.start_day>total_day or value.get("scenario") not in ["baseline","shocks","shocks_french_wheat","supply","demand","transport"]:return false
	for key: String in ["nodes","cells","arrivals","local","policy_receipts"]:
		if not value.get(key) is Dictionary:return false
	for key: String in ["edges","flows","shocks"]:
		if not value.get(key) is Array:return false
	if value.nodes.size()!=50 or value.cells.size()!=50*GOODS.size() or value.edges.size()>400 or value.arrivals.size()>MAX_DELAY:return false
	initialize(value.start_day,value.scenario)
	if value.edges!=data.edges or value.shocks!=data.shocks:return false
	for id: String in value.nodes:
		if not _nodes.has(id) or not value.nodes[id] is Dictionary:return false
		var node: Dictionary=value.nodes[id]
		if not FormalLedgerState.exact_fields(node,["id","name","polity_id","lon_lat","anchor_basis","source_id","market_id","population","industry"]):return false
		for field: String in ["id","name","polity_id","lon_lat","anchor_basis","source_id","market_id","industry"]:
			if node[field]!=data.nodes[id][field]:return false
		if not node.population is int or node.population<0:return false
		for good: String in GOODS:
			var c: Variant=value.cells.get(_key(id,good))
			if not c is Dictionary or not c.get("history") is Array or c.history.is_empty() or c.history.size()>HISTORY:return false
			if not FormalLedgerState.exact_fields(c,["price","lag","cover","base","capacity","supply","demand","absorbed","unmet","imports","exports","signal","history","pressure","cause"]) or not c.cause is String:return false
			for field: String in ["price","lag","cover","base","capacity","supply","demand","absorbed","unmet","imports","exports","signal","pressure"]:
				if typeof(c.get(field)) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(c[field])):return false
			if c.price<25 or c.price>400 or c.cover<0 or c.cover>60 or c.base<=0:return false
			if c.capacity!=data.cells[_key(id,good)].capacity or c.history.size()!=mini(HISTORY,total_day-int(value.start_day)+1):return false
			for price: Variant in c.history:
				if typeof(price) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(price)) or price<25 or price>400:return false
			if absf(float(c.history[(total_day-int(value.start_day))%HISTORY])-snappedf(float(c.price),0.01))>0.00001:return false
	for edge: Variant in value.edges:
		if not edge is Dictionary or not _nodes.has(edge.get("a")) or not _nodes.has(edge.get("b")) or int(edge.get("days",0))<1 or int(edge.get("days",MAX_DELAY+1))>MAX_DELAY or float(edge.get("capacity",-1))<0:return false
	for date: String in value.arrivals:
		if not date.is_valid_int() or int(date)<=total_day or int(date)>total_day+MAX_DELAY or not value.arrivals[date] is Dictionary:return false
		for k: String in value.arrivals[date]:
			var a: Variant=value.arrivals[date][k]
			if not value.cells.has(k) or not a is Dictionary:return false
			for field: String in ["units","signal","weight"]:
				if typeof(a.get(field)) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(a[field])) or a[field]<0:return false
	if value.flows.size()>value.edges.size()*GOODS.size():return false
	for flow: Variant in value.flows:
		if not flow is Dictionary or not FormalLedgerState.exact_fields(flow,["from","to","good","estimated_units","arrival_day","basis"]):return false
		if not _nodes.has(flow.from) or not _nodes.has(flow.to) or flow.good not in GOODS or typeof(flow.estimated_units) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(flow.estimated_units)) or flow.estimated_units<=0 or not flow.arrival_day is int or flow.arrival_day<=total_day or flow.arrival_day>total_day+MAX_DELAY:return false
	if not value.local.is_empty():
		if value.local.get("basis")==SAMPLE_BASIS:
			if not _valid_sample(value.local,total_day):return false
		else:
			if not FormalLedgerState.exact_fields(value.local,["basis","produced_total","used_total","produced_tonnes","used_tonnes","baseline_produced","baseline_used","grain_stock_native","delivered_all_goods_native_today"]) or value.local.basis!="DEVELOPMENT_GRAIN_WHEAT_SAMPLE_1_NATIVE_UNIT_1_KG_NOT_ALL_FRANCE":return false
			for field: String in ["produced_total","used_total","produced_tonnes","used_tonnes","baseline_produced","baseline_used","grain_stock_native","delivered_all_goods_native_today"]:
				if typeof(value.local[field]) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value.local[field])) or value.local[field]<0:return false
	if value.policy_receipts.size()>11:return false
	for k: String in value.policy_receipts:
		var b: Variant=value.policy_receipts[k]
		if not b is Dictionary or b.get("basis")!=BASIS or b.get("source")!="PUBLIC_REFERENCE_INDEX_SERVICE_DEVELOPMENT" or b.get("region")!="country_fra" or b.get("commodity")!="wheat" or not b.get("recipient") is String or k!=str(b.recipient)+"|wheat" or b.get("executable_quote")!=false:return false
		for field: String in ["observed_day","received_day","valid_until_day"]:
			if not b.get(field) is int:return false
		if int(b.observed_day)+2!=int(b.received_day) or b.received_day>total_day or b.valid_until_day!=int(b.received_day)+3 or typeof(b.get("index")) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(b.index)) or b.index<25 or b.index>400:return false
	data=value.duplicate(true)
	return true

func _valid_sample(sample: Dictionary,total_day: int) -> bool:
	if not FormalLedgerState.exact_fields(sample,["basis","from_minute","through_minute","adopt_flows","conversion","weight","scope","replacement","points","regions","deliveries"]):return false
	if not sample.adopt_flows is bool or sample.weight!=1.0 or sample.conversion!="DEVELOPMENT_ASSUMPTION_1_NATIVE_GRAIN_UNIT_1_KG_0_001_TONNE" or sample.scope!="FROZEN_NAMED_NATIVE_POINTS_ONLY" or sample.replacement!="DEVELOPMENT_RESERVED_POINT_BLOCK_OPENING_OBSERVED_DAILY_MEAN_NOT_NATIONAL_SAMPLE_ESTIMATE":return false
	if not sample.from_minute is int or not sample.through_minute is int or sample.from_minute<0 or sample.through_minute<sample.from_minute or sample.through_minute<total_day*1440 or sample.through_minute>=total_day*1440+1440:return false
	if not sample.points is Dictionary or not sample.regions is Dictionary or not sample.deliveries is Array:return false
	for row: Variant in sample.points.values():
		if not row is Dictionary or not FormalLedgerState.exact_fields(row,["place","region","produced","used","baseline_days","baseline_produced","baseline_used"]) or not row.place is String or not data.nodes.has(row.region):return false
		for f: String in ["produced","used","baseline_days","baseline_produced","baseline_used"]:
			if typeof(row[f]) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(row[f])) or row[f]<0:return false
	for id: String in sample.regions:
		if not data.nodes.has(id) or not sample.regions[id] is Dictionary:return false
		var row: Dictionary=sample.regions[id]
		if not FormalLedgerState.exact_fields(row,["baseline_produced","baseline_used","produced_tonnes","used_tonnes","stock_native","cross_border_delivered_native","adopted_import_tonnes"]):return false
		for f: String in row:
			if typeof(row[f]) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(row[f])) or row[f]<0:return false
		if row.adopted_import_tonnes!=0.0:return false
	for row: Variant in sample.deliveries:
		if not row is Dictionary or not FormalLedgerState.exact_fields(row,["receipt_id","order_id","good","quantity_native","tonnes","from_place","to_place","origin_region","destination_region","delivered_minute","cross_border","adopted_import_tonnes","overlap"]):return false
		if row.good!="grain" or not row.cross_border is bool or not row.quantity_native is int or row.quantity_native<=0 or row.tonnes!=float(row.quantity_native)*0.001 or row.adopted_import_tonnes!=0.0:return false
		if not row.delivered_minute is int or row.delivered_minute<=sample.from_minute or row.delivered_minute>sample.through_minute:return false
	return true
