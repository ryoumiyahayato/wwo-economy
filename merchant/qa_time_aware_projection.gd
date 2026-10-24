extends SceneTree
const Save=preload("res://merchant/merchant_save.gd")
var checks: Array=[]
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
	assert(ok,label);checks.append(label)
func requirement(date: int,quantity: int) -> Dictionary:
	return {"day":date,"boundary_minute":date*1440,"quantity":quantity,"purpose":"PLANNED_PRODUCTION"}
func input(e: EconomyR1Slice,needs: Array,batches: Array,stock: int=0,regular: int=0,unknown: int=0) -> Dictionary:
	var p: Dictionary=e._project_input_timing(needs,stock,batches);p["unknown_responsibility_hold"]=unknown
	return {"quantity":regular,"regular_quantity":regular,"need_by_day":needs[0]["day"],"on_hand":stock,"incoming_observation":{"batches":batches},"timing_projection":p}
func run() -> void:
	var args:=OS.get_cmdline_user_args();var raw: Dictionary=Save._read(args[0],5)
	var b: WorldBuildResult=FormalPersistence.new().restore_candidate(raw["core"]);assert(b.success)
	var e: EconomyR1Slice=b.world.economy_r1;var before: Dictionary=b.persistence.snapshot()
	var needs: Array=[requirement(13,1),requirement(14,1),requirement(15,1)]
	var late: Array=[{"quantity":3,"earliest_arrival_day":16,"observed_arrival_day":16}]
	var n:=input(e,needs,late)
	check(e._input_candidate_need(n,13,3,1)["timing_quantity"]==3,"Candidate split1/day covers13,14,15 without deleting late3")
	check(e._input_candidate_need(n,14,3,1)["timing_quantity"]==2,"Later candidate cannot recover13 but can improve14,15")
	check(e._input_candidate_need(n,14,3,1)["need_by_day"]==14,"Adoption references first actually improved boundary")
	check(e._input_candidate_need(n,16,3,1)["quantity"]==0,"All alternatives late: wait")
	var early: Array=[{"quantity":3,"earliest_arrival_day":13,"observed_arrival_day":13}]
	check(e._input_candidate_need(input(e,needs,early),13,3)["quantity"]==0,"Existing timely responsibility prevents duplicate rescue")
	check(e._input_candidate_need(input(e,needs,late,0,0,3),13,3)["quantity"]==0,"Unknown liability conservatively holds extra risk")
	check(e._input_candidate_need(n,null,3)["timing_quantity"]==0,"Unknown candidate is not timely coverage")
	check(e._input_candidate_need(n,13,0)["quantity"]==0,"Zero real capacity cannot rescue")
	var concentrated:=input(e,[requirement(13,3)],late)
	check(e._input_candidate_need(concentrated,13,3,1)["timing_quantity"]==1,"First-leg admission3 does not pretend later batch2 arrive same day")
	var mixed: Array=[{"quantity":1,"earliest_arrival_day":13,"observed_arrival_day":13},{"quantity":2,"earliest_arrival_day":16,"observed_arrival_day":16}]
	check(input(e,needs,mixed)["timing_projection"]["uncovered_future_quantity"]==2,"One order split early1 late2 covers only one boundary")
	check(input(e,[requirement(13,1),requirement(13,1)],[],1)["timing_projection"]["uncovered_future_quantity"]==1,"One physical unit is allocated only once")
	check(before==b.persistence.snapshot(),"Projection-only fixtures leave world exactly unchanged")
	var f=FileAccess.open(args[1],FileAccess.WRITE);f.store_string(JSON.stringify({"status":"PASS_PURE_PROJECTION_NOT_ORDER_FULFILMENT","checks":checks},"\t"));f.close();print("QA_TIME_AWARE_PROJECTION_PASS ",checks.size());quit()
