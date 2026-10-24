extends "res://merchant/economy_network_experiment.gd"
const Multi=preload("res://merchant/multisource_opening.gd")
const Reaction=preload("res://merchant/regional_reaction_opening.gd")
func _ready() -> void:
	super._ready()
	map_view.research_subject_requested.connect(func(firm: String):_submit("research_subject",{"firm":firm}))
func _description() -> String:return "隔离经济研究 · 原自主采购、生产与报价 · 原账物 · 不读写存档"
func _conditions() -> Array:return ["正常：三地已知供应","里昂→巴黎共用末段关闭","商号资金20（总资本不变）","马赛介绍延迟至day3","粮食6与肥皂2并行备货","区域生产：通道正常","区域生产：6日关、15日恢复","区域生产：受阻期有限替代"]
func _selected_capacity() -> int:return 0 if choices.selected==1 else 10
func _start_runtime() -> Error:return runtime.start_multisource_experiment((Multi.CONDITIONS+Reaction.CONDITIONS)[choices.selected])
func _on_initialized() -> void:pass # Worker applies condition before its first confirmed view.
func _controls() -> void:
	super._controls()
	if choices!=null and choices.selected>=Multi.CONDITIONS.size():capacity_button.disabled=true
