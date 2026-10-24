extends "res://merchant/economy_multisource_experiment.gd"
## Existing map and Runtime; explicit terminal-access research conditions.
const Adaptive=preload("res://merchant/consumer_access_opening.gd")
func _ready() -> void:
	super._ready()
	DisplayServer.window_set_title("WWO 终端消费可达性 · 隔离研究")
	note.text="显式新建；沿用原库存组起点。比较有资金的正式询购、马赛原报价接续、公司现金与耐用品试购。消费诊断含私人资料，仅供研发观察。不读写存档。"
func _description() -> String:return "终端消费研究 · 原正式买单、货批、消费与付款 · 不读写存档"
func _conditions() -> Array:return ["原库存策略参照","仅有资金的缺货询购","仅马赛面包报价接续","仅公司现金与周转","询购＋报价","询购＋报价＋公司周转"]
func _start_runtime() -> Error:return runtime.start_multisource_experiment(Adaptive.CONDITIONS[choices.selected])
func _controls() -> void:
	super._controls()
	if capacity_button!=null:capacity_button.disabled=true

