from copy import deepcopy
import os
import subprocess
from pathlib import Path
import unittest

import formal_economy as formal
import wwo_current as w


class ObservationTests(unittest.TestCase):
    def test_transferred_child_is_not_new_production_and_consumption_is_delta(self):
        lot = dict(id="portion:1", source_id="production:1:soap", parent_portion_id="", quantity=4,
                   consumed=1, remaining=3, owner="firm:soap", custodian="site:soap", good="soap", location="SITE|soap")
        before = {"native": {"stock_lots": {"portions": {"portion:1": lot}}, "orders": {}}, "ledger": {"transactions": []}, "minute": 1440}
        after = deepcopy(before)
        after["native"]["stock_lots"]["portions"]["portion:1"].update(consumed=2, remaining=2)
        after["native"]["stock_lots"]["portions"]["portion:2"] = dict(lot, id="portion:2", parent_portion_id="portion:1", consumed=0)
        observed = formal.changes(before, after, 2)
        self.assertEqual([(e["kind"], e["quantity"]) for e in observed], [("material_used", 1)])
        self.assertEqual(observed[0]["nativeRecordId"], "portion:1")
        self.assertEqual(before["native"]["stock_lots"]["portions"]["portion:1"]["consumed"], 1)


@unittest.skipUnless(os.environ.get("WWO_FORMAL_REPO_PATH"), "requires pinned original formal Godot source")
class OriginalFormalTests(unittest.TestCase):
    def test_real_player_purchase_delivery_consumption_and_production(self):
        provider = formal.Provider(w.Provider("economy").metadata, w.runtime_environment)
        scenario = deepcopy(provider.metadata["defaultScenario"])
        scenario["params"]["stepMinutes"] = 1440
        session = provider.create(scenario)
        try:
            initial = session.snapshot()
            self.assertEqual(initial, session.snapshot())
            f = initial["observations"]["nativeEconomy"]
            offer = next(o for o in f["personal"]["offers"] if o["good"] == "soap")
            payload = dict(quote_id=offer["quote_id"], seller=offer["seller"], seller_site=offer["seller_site"],
                           good="soap", quantity=1, max_price=offer["price"], denomination=offer["denomination"], need_category="household")
            forbidden = session.command(dict(id="sandbox:unauthorized", op="livelihood", parameters=dict(kind="buy", payload=dict(payload, firm="firm:development_farm"))))
            self.assertFalse(forbidden["receipt"]["accepted"])
            self.assertEqual(forbidden["receipt"]["reason"], "NOT_PROCUREMENT_MANAGER")
            self.assertEqual(session.state["ledger"], f["ledger"])
            request = dict(id="sandbox:purchase", op="livelihood", parameters=dict(kind="buy", payload=payload))
            accepted = session.command(request)
            self.assertTrue(accepted["receipt"]["accepted"])
            self.assertEqual(accepted["snapshot"]["tick"], 0)
            self.assertEqual(session.state["personal"]["cash"], 2500)
            self.assertEqual(session.state["personal"]["reserved"], offer["price"])
            state = deepcopy(session.state)
            self.assertTrue(session.command(request)["receipt"]["accepted"])
            self.assertEqual(session.state, state, "Original command retry must not buy twice")
            session.step()
            self.assertFalse(any(c["kind"] == "production" for c in session.observed))
            session.step()
            self.assertEqual(session.state["personal"]["cash"], 2500 - offer["price"])
            self.assertEqual(session.state["personal"]["orders"][0]["delivered"], 1)
            self.assertTrue(any(r["kind"] == "native_consume" and r["good"] == "soap" and r["source"] == "needs" for r in session.state["living"]))
            session.step()
            production = [c for c in session.observed if c["kind"] == "production" and c["good"] == "soap"]
            self.assertEqual(len(production), 1)
            self.assertEqual(production[0]["quantity"], 4)
            self.assertEqual(production[0]["nativeRecordId"], production[0]["raw"]["source_id"])
            self.assertEqual(len({c["id"] for c in session.observed}), len(session.observed))
            self.assertEqual(session.snapshot(), session.snapshot())
        finally:
            session.close()


    def test_independent_reserved_cash_refusal_fixture(self):
        result = subprocess.run([os.environ.get("WWO_GODOT_BIN", "godot"), "--headless", "--path", str(formal.source()), "--script", str(Path(__file__).with_name("test_formal_cash_fixture.gd").resolve())], env=w.runtime_environment(), capture_output=True, text=True, encoding="utf-8", timeout=45)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('"ok":true', result.stdout)

    def test_job_travel_wage_custody_and_manual_consumption(self):
        provider = formal.Provider(w.Provider("economy").metadata, w.runtime_environment)
        session = provider.create(provider.metadata["defaultScenario"])
        def command(key, kind, **payload):
            return session.command(dict(id="test:"+key, op="livelihood", parameters=dict(kind=kind, payload=payload)))
        def accepted(key, kind, **payload):
            r = command(key, kind, **payload)
            self.assertTrue(r["receipt"]["accepted"], r["receipt"])
            return r
        try:
            for _ in range(4): session.step()
            self.assertEqual(command("no-vacancy", "apply", job_id="job:development_farm")["receipt"]["reason"], "NO_VACANCY")
            accepted("job", "apply", job_id="job:development_workshop")
            accepted("away", "travel", destination_place_id="place:lyon")
            self.assertEqual(command("journey-work", "work", hours=2)["receipt"]["reason"], "PERSON_JOURNEY_NOT_COMPLETED")
            session.step()
            self.assertEqual(command("wrong-place", "work", hours=2)["receipt"]["reason"], "OUTSIDE_JOB_PLACE")
            accepted("return", "travel", destination_place_id="place:paris"); session.step()
            accepted("work", "work", hours=2)
            self.assertEqual(command("duplicate-work-period", "work", hours=2)["receipt"]["reason"], "WORK_PERIOD_ALREADY_CLAIMED")
            for _ in range(4): session.step()
            self.assertEqual(sum(session.state["personal"]["income_by_currency"].values()), 6)
            before = deepcopy(session.state)
            accepted("work", "work", hours=2)
            self.assertEqual(session.state, before, "Same action_id after time advance must retain original envelope and result")
            self.assertEqual(command("work", "work", hours=1)["receipt"]["reason"], "ACTION_ID_CONFLICT")
            offer = next(o for o in session.state["personal"]["offers"] if o["good"] == "beans" and o["quantity"] > 0)
            purchase = dict(quote_id=offer["quote_id"], seller=offer["seller"], seller_site=offer["seller_site"], good="beans", quantity=1, denomination=offer["denomination"], max_price=offer["price"], need_category="food")
            accepted("buy", "buy", **purchase)
            before = deepcopy(session.state); accepted("buy", "buy", **purchase)
            self.assertEqual(session.state, before)
            accepted("away-cargo", "travel", destination_place_id="place:lyon")
            for _ in range(8):
                session.step()
                cargo = [s for o in session.state["personal"]["orders"] for s in o["shipments"] if s["stage"] == "AWAITING_RECIPIENT"]
                if cargo: break
            self.assertTrue(cargo)
            self.assertEqual(command("wrong-collect", "collect", shipment_id=cargo[0]["id"])["receipt"]["reason"], "RECIPIENT_NOT_AT_CUSTODY_PLACE")
            accepted("return-cargo", "travel", destination_place_id="place:paris"); session.step()
            self.assertEqual(session.state["personal"]["inventory"]["beans"], 0)
            accepted("collect", "collect", shipment_id=cargo[0]["id"])
            self.assertEqual(session.state["personal"]["inventory"]["beans"], 1)
            accepted("consume", "consume", commodity_id="native:beans", quantity=1, need_category="food", source="manual")
            self.assertEqual(session.state["personal"]["inventory"]["beans"], 0)
            self.assertTrue(any(r["kind"] == "native_consume" and r.get("source") == "manual" for r in session.state["living"]))
            self.assertTrue(any(c["kind"] == "consumed" and c["good"] == "beans" for c in session.observed))
            before = deepcopy(session.state)
            for _ in range(5): session.snapshot()
            self.assertEqual(session.state, before, "Read-only snapshots must not advance or settle")
        finally: session.close()


if __name__ == "__main__":
    unittest.main()
