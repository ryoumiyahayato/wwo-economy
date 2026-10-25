extends SceneTree
## Independent negative test only. Explicitly reserves opening cash in Ledger.
## Not a player action, gameplay scenario, or recorded demonstration.
func _initialize() -> void:
 var built := WorldBootstrap.new().build(null, [], [], FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT, true, EconomyDevelopmentConfig.formal_limited())
 if not built.success: push_error(built.error); quit(1); return
 var w := built.world
 var actor := w.player_state.player_id()
 var before := LivelihoodAction.query(w, actor)
 var account := FormalPersonalEconomyState.personal_account_id(actor)
 if not w.ledger_state.reserve("independent-test:cash-lock", account, before["cash"]): quit(2); return
 var quoted := LivelihoodAction.query(w, actor)
 var offer: Dictionary = {}
 for q: Dictionary in quoted["offers"]:
  if q["good"] == "soap": offer = q; break
 var orders_before: int = w.economy_r1.snapshot()["orders"].size()
 var result := LivelihoodAction.execute(w, actor, {"action_id":"independent-test:cash-rejection", "minute":0, "kind":"buy", "payload":{"quote_id":offer["quote_id"], "seller":offer["seller"], "seller_site":offer["seller_site"], "good":"soap", "quantity":1, "denomination":offer["denomination"], "max_price":offer["price"], "need_category":"household"}})
 var after := LivelihoodAction.query(w, actor)
 var ok: bool = offer["reason"] == "INSUFFICIENT_AVAILABLE_CASH" and result["accepted"] == false and result["reason"] == "INSUFFICIENT_CASH_OR_CAPACITY_OR_NEED" and after["cash"] == before["cash"] and after["reserved"] == before["cash"] and w.economy_r1.snapshot()["orders"].size() == orders_before and w.game_clock.total_minutes() == 0
 print("INDEPENDENT_CASH_TEST ", JSON.stringify({"ok":ok, "fixture":"original Ledger.reserve of all opening cash; not player action", "quote":offer, "result":result, "cash":after["cash"], "reserved":after["reserved"]}))
 quit(0 if ok else 3)
