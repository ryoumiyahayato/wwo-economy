extends RefCounted
## Optional contract on existing activities. No stock, money, clock or executor.
## Cycle means an eligible daily batch boundary; there is no hidden WIP storage.
const FORMAT = "production_process_v1"

static func valid(a: Dictionary) -> bool:
	if not a.has("process"): return true
	var p: Variant = a.process
	if not p is Dictionary or not FormalLedgerState.exact_fields(p,["format","technology_id","batch_unit","source","gross_outputs","rejects","first_day","cycle_days","max_batches_per_cycle","lifetime_batch_limit","constraints"]): return false
	if p.format != FORMAT: return false
	for key: String in ["technology_id","batch_unit"]:
		if not p[key] is String or p[key].is_empty(): return false
	var s: Variant = p.source
	if not s is Dictionary or not FormalLedgerState.exact_fields(s,["id","basis","estimated","hours_unit","capacity_unit"]) or not s.estimated is bool or s.hours_unit != "person_hour" or s.capacity_unit != "capacity_unit_per_eligible_day": return false
	for key: String in ["id","basis"]:
		if not s[key] is String or s[key].is_empty(): return false
	for key: String in ["first_day","cycle_days","max_batches_per_cycle","lifetime_batch_limit"]:
		if not FormalLedgerState.valid_amount(p[key]) or p[key] > 1000000: return false
	if p.first_day < 1 or p.cycle_days < 1 or p.max_batches_per_cycle < 1 or p.lifetime_batch_limit < 1: return false
	if not p.gross_outputs is Dictionary or not p.rejects is Dictionary or p.gross_outputs.size()!=a.outputs.size() or p.rejects.size()!=a.outputs.size(): return false
	for good: String in a.outputs:
		if not FormalLedgerState.valid_amount(p.gross_outputs.get(good)) or not FormalLedgerState.valid_amount(p.rejects.get(good)): return false
		if int(p.gross_outputs[good])-int(p.rejects[good]) != int(a.outputs[good]): return false
	if not p.constraints is Array or p.constraints.size()>16: return false
	for c: Variant in p.constraints:
		if not c is Dictionary or not FormalLedgerState.exact_fields(c,["kind","availability","source","unit"]): return false
		if c.kind not in ["LAND","BIOLOGICAL_CYCLE","MINERAL_DEPOSIT","ACTIVITY_LABOR_ROLE","SPECIFIC_EQUIPMENT","FUEL","SERVICE_OUTPUT","MULTIDAY_WIP"] or c.availability != "UNAVAILABLE": return false
		for key: String in ["source","unit"]:
			if not c[key] is String or c[key].is_empty(): return false
	return true

static func reason(a: Dictionary, day: int, completed: int) -> String:
	if not a.has("process"): return "LEGACY_UNSPECIFIED"
	var p: Dictionary = a.process
	if not p.constraints.is_empty(): return "UNAVAILABLE_"+str(p.constraints[0].kind)
	if completed>=int(p.lifetime_batch_limit): return "BATCH_QUOTA_EXHAUSTED"
	if day<int(p.first_day) or (day-int(p.first_day))%int(p.cycle_days)!=0: return "OUTSIDE_PROCESS_CYCLE"
	return "ELIGIBLE"

static func limit(a: Dictionary, day: int, completed: int) -> int:
	if not a.has("process"): return FormalLedgerState.MAX_AMOUNT
	if reason(a,day,completed)!="ELIGIBLE": return 0
	return mini(int(a.process.max_batches_per_cycle),int(a.process.lifetime_batch_limit)-completed)
