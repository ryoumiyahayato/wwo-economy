extends "res://merchant/economy_multisource_experiment.gd"
const Consumer=preload("res://merchant/consumer_access_opening.gd")
var play_button: Button
var resume_button: Button
func _ready() -> void:
	super._ready()
	var row:=HBoxContainer.new();row.position=Vector2(12,110);add_child(row)
	play_button=_button(row,"以本商号接手经营（本次不保存）",func():_submit("enter_business"))
	resume_button=_button(row,"继续独立试玩档",_resume_trial)
	map_view.offset_top=150
	_controls()
	DisplayServer.window_set_title("WWO 居民消费选择 · 隔离研究")
	note.text="显式研究世界，不读写存档。公告组织两组共用一小时岗位（时薪3）与本站公告条件；接手后须实际申请、工作和发布。工资由商号承担。"
func _description() -> String:return "居民消费选择 · 原需要、买单、货批与Ledger · 显式研究世界"
func _conditions() -> Array:return ["参照起点·原顺序","参照起点·7日服务比较","参照起点·服务与现金缓冲","报价起点·原顺序","报价起点·7日服务比较","报价起点·服务与现金缓冲","需求时效·原路线·原响应","需求时效·原路线·期限判断","需求时效·原路线·有限风险","需求时效·快线·原响应","需求时效·快线·期限判断","需求时效·快线·有限风险","区域连续经营·参照","区域连续经营·资金与经验","公告组织·同起点参照","公告组织·合法工作与发布"]
func _start_runtime() -> Error:return runtime.start_multisource_experiment((Consumer.CHOICES+Consumer.TIME_CHOICES+Consumer.TURNOVER_CHOICES+Consumer.PUBLICITY_CHOICES)[choices.selected])
func _controls() -> void:
	super._controls()
	if capacity_button!=null:capacity_button.disabled=true
	if play_button!=null:play_button.disabled=runtime==null or closing or not pending.is_empty() or target_minute>=0 or not confirmed.get("experiment_condition","") in Consumer.TURNOVER_CHOICES+Consumer.PUBLICITY_CHOICES
	if resume_button!=null:resume_button.disabled=runtime!=null or not preload("res://merchant/merchant_save.gd").has_slot(6)

func _resume_trial() -> void:
	if runtime!=null:return
	var merchant: Node=load("res://merchant/main.tscn").instantiate()
	merchant.resume_trial=true
	get_parent().add_child(merchant)
	if get_tree().current_scene==self:get_tree().current_scene=merchant
	queue_free()

func _on_response(kind: String) -> void:
	if kind=="enter_business" and confirmed.get("business_experiment",false):
		set_process(false);_open_business.call_deferred()

func _open_business() -> void:
	var merchant: Node=load("res://merchant/main.tscn").instantiate()
	if merchant.adopt_runtime(runtime,confirmed)!=OK:
		merchant.free();set_process(true);note.text="接手失败；当前世界仍由原Runtime持有。";return
	runtime=null # Transfer the existing worker; _exit_tree must not stop it.
	get_parent().add_child(merchant)
	if get_tree().current_scene==self:get_tree().current_scene=merchant
	queue_free()
