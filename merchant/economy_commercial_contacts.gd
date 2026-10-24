extends "res://merchant/economy_multisource_experiment.gd"
## Same map and Runtime, focused entry for the four contact conditions.
const Adaptive=preload("res://merchant/commercial_adaptation_opening.gd")
func _ready() -> void:
	super._ready()
	DisplayServer.window_set_title("WWO 商贸联系与经营库存 · 隔离研究")
	note.text="显式新建；四项策略只改变库存或报价规则。相同居民、钱货、公告及通行条件。研究观察不授予经营权，不读写存档。"
func _description() -> String:return "商贸适应研究 · 自身销量、库存和报价 · 原账物 · 不读写存档"
func _conditions() -> Array:return ["原策略参照","仅经营库存适应","仅同价报价维持","组合（分项对照）"]
func _start_runtime() -> Error:return runtime.start_multisource_experiment(Adaptive.CONDITIONS[choices.selected])
func _controls() -> void:
	super._controls()
	if capacity_button!=null:capacity_button.disabled=true
