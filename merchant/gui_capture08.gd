extends SceneTree
## Passive evidence only. No transactions, clock actions or suspended coroutines.
var scene: Node
var previous: String=""
var count: int=0
var next_sample: int=0
var deadline: int=0
var closing: bool=false
const BASE="/workspace/shared/economy_08_opportunities"
func _initialize() -> void:call_deferred("run")
func run() -> void:
	root.size=Vector2i(1280,720)
	scene=load("res://merchant/main.tscn").instantiate();root.add_child(scene)
	deadline=Time.get_ticks_msec()+480000
func _process(_delta: float) -> bool:
	if not is_instance_valid(scene) or closing:return false
	var now: int=Time.get_ticks_msec()
	if FileAccess.file_exists(BASE+"/stop_gui.request") or now>=deadline:
		closing=true;scene._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST);return false
	if now<next_sample:return false
	next_sample=now+300
	var c: Dictionary=scene.snapshot.get("supply",{})
	var state: String=str(scene.city_home)+"|"+str(scene.message)+"|"+str(scene.selected_tab)+"|"+str(scene.selected_place)+"|"+str(scene.current_minute)+"|"+str(scene.dialog.visible)+"|"+str(c.get("id",""))
	if state!=previous and not scene.busy and not scene.stepping:
		previous=state
		root.get_texture().get_image().save_png(BASE+"/gui_frames/frame_%03d.png"%count)
		var summary: Array=[]
		for row: Dictionary in scene.snapshot.get("opportunities",[]):summary.append({"id":row["id"],"status":row["status"],"good":row["good"],"quantity":row["quantity"],"free":row["free_stock"],"ontime":row.get("ontime",0),"paid":row.get("paid",0),"batches":row.get("batches",[])})
		print("GUI08_STATE ",count," ",state," slot=",scene.snapshot.get("slot")," cash=",scene.view.get("cash")," reserved=",scene.view.get("reserved")," opportunities=",JSON.stringify(summary))
		count+=1
	return false
