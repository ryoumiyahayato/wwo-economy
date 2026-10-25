"""Path-only adapter to historical Python research owned by the WWO repository.

No real algorithm or fixture is bundled here. WWO_REPO_PATH must point to an
external, versioned WWO checkout containing the migration research directory.
Only input conversion, original calls, time advancement and observation happen
here; all physical settlement stays in the external Simulation implementation.
"""
from copy import deepcopy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys

RESEARCH_DIRECTORY = Path("research/economy-lab-20261007")
SANDBOX_ROOT = Path(__file__).resolve().parents[3]
SOURCE_COMMIT = "48b280a37be8f5fd72f0c277f4ae435e675efa1f"


def load_model():
    value = os.environ.get("WWO_REPO_PATH")
    if not value:
        raise ValueError("Set WWO_REPO_PATH to an external WWO checkout; there is no Lab algorithm fallback")
    world_root = Path(value).expanduser().resolve(strict=True)
    if world_root == SANDBOX_ROOT or world_root.is_relative_to(SANDBOX_ROOT):
        raise ValueError("The real model must live outside this sandbox repository")
    root = world_root / RESEARCH_DIRECTORY
    source = root / "economy_quantity_lab/economy.py"
    fixture = root / "economy_quantity_lab/fixture.json"
    if not source.is_file() or not fixture.is_file():
        raise ValueError("WWO research snapshot absent: use research/economy-lab-migration-20261014, without changing another active working tree")
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=world_root, text=True).strip()
    dirty = subprocess.run(["git", "diff", "--quiet", "HEAD", "--", str(RESEARCH_DIRECTORY)], cwd=world_root, check=False)
    if dirty.returncode:
        raise ValueError("Historical research snapshot has uncommitted changes; this adapter will not invoke an uncommitted version")
    module_name = "wwo_external_quantity_" + commit[:16]
    spec = importlib.util.spec_from_file_location(module_name, source)
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return world_root, root, module, commit


def default_scenario(goods):
    return {
        "schemaVersion": "wwo-sandbox/scenario/v1", "name": "WWO historical quantity research · external",
        "domain": "economy", "adapterId": "private.wwo.quantity.v1", "seed": 42, "maxTicks": 30, "boundary": "quantity-flow",
        "dependencies": {"supply": "finite", "transport": "bounded", "funding": "normal", "path": "direct", "resupply": "on-demand"},
        "params": {"demand": 10, "capacity": 100, "leadTicks": 2},
        "expectations": {"rules": [
            {"id": "delivery", "label": "By tick 3 actual terminal delivery > 0", "target": "metric", "key": "fulfilled", "operator": "gte", "value": 1, "byTick": 3},
            *[{"id": good, "label": f"{good} residual always 0", "target": "invariant", "key": good, "operator": "eq", "value": 0, "byTick": "always"} for good in goods],
        ], "observation": "Only historical quantity flow. Wallet, price discovery and current uncommitted algorithms are not supplied."},
    }


class QuantitySession:
    def __init__(self, scenario, provider):
        self.scenario = deepcopy(scenario)
        if scenario["boundary"] != "quantity-flow" or scenario["dependencies"]["supply"] != "finite" or scenario["dependencies"]["transport"] != "bounded":
            raise ValueError("The tested historical boundary includes inventory and transport; idealizing these would bypass it")
        params = scenario["params"]
        for key, minimum, maximum in [("demand", 0, 500), ("capacity", 0, 10000), ("leadTicks", 1, 100)]:
            if type(params.get(key)) is not int or not minimum <= params[key] <= maximum:
                raise ValueError(f"invalid parameter {key}")
        config = json.loads((provider.root / "economy_quantity_lab/fixture.json").read_text())
        config["days"] = scenario["maxTicks"]
        config["daily_terminal_demand"] = params["demand"]
        config["routes"]["A_B"]["capacity"] = params["capacity"]
        config["routes"]["A_B"]["lead_time"] = params["leadTicks"]
        self.sim = provider.model.Simulation(config, "baseline")
        self.row = {}
        self.events = []
        self.stall = 0

    def snapshot(self):
        sim = self.sim
        residuals = sim.check_accounts()
        metrics = {
            "fulfilled": sim.cumulative["terminal_delivered"], "unmet": sim.backlog,
            "inventory": sum(sum(stock.values()) for stock in sim.stock.values()),
            "inTransit": sum(order.in_transit for order in sim.orders.values()),
            "goodsResidual": max(map(abs, residuals.values())), "stallTicks": self.stall,
            **{key: value for key, value in self.row.items() if type(value) in (int, float)},
        }
        return {
            "tick": sim.day, "metrics": metrics,
            "stages": [
                {"id": "quantity", "label": "External quantity step", "status": "success" if sim.day else "pending", "detail": "Original WWO-owned research Simulation.step(); no replacement settlement"},
                {"id": "wallet", "label": "Wallet / pricing", "status": "not-implemented", "detail": "Not owned by this historical model; observables are absent"},
            ],
            "events": [{"tick": event["day"], "stage": event["event"], "status": "success", "message": f"{event['event']}: {event['route']}, quantity {event['quantity']}", "entityId": str(event["order_id"])} for event in self.events],
            "entities": [{"id": site, "label": site, "x": index * 4 + 2, "y": 3, "stock": sum(stock.values())} for index, (site, stock) in enumerate(sim.stock.items())],
            "orders": [{"id": str(order.id), "quantity": order.quantity, "pending": order.pending_dispatch, "inTransit": order.in_transit, "delivered": order.delivered, "lost": 0, "status": "pending" if order.pending_dispatch else "transit" if order.in_transit else "delivered"} for order in list(sim.orders.values())[-30:]],
            "invariants": residuals, "injections": {}, "done": sim.day >= self.scenario["maxTicks"],
            "completion": {"status": "pending", "condition": "Evaluate independent quantity-flow expectations", "reason": "External historical quantity only; native economy and fifteen-algorithm research need separate providers"},
            "blockedReason": "No terminal delivery; inspect real production/inventory/transport metrics" if self.stall else "",
        }

    def step(self):
        before = len(self.sim.events)
        self.row = self.sim.step()
        self.events = self.sim.events[before:]
        self.stall = self.stall + 1 if self.row["terminal_delivery"] == 0 else 0
        return self.snapshot()


class QuantityProvider:
    def __init__(self):
        self.world_root, self.root, self.model, commit = load_model()
        self.metadata = {
            "protocolVersion": "wwo-sandbox/adapter/v1", "id": "private.wwo.quantity.v1", "name": "PRIVATE · WWO historical quantity research",
            "domain": "economy", "kind": "private", "version": "historical-2026-10-07",
            "sourceRef": f"WWO {commit}; original Lab {SOURCE_COMMIT}; deterministic model has no RNG",
            "parameters": [{"key": "demand", "label": "Terminal demand", "min": 0, "max": 500, "step": 1}, {"key": "capacity", "label": "A_B actual capacity", "min": 0, "max": 10000, "step": 1}, {"key": "leadTicks", "label": "A_B actual lead time", "min": 1, "max": 100, "step": 1}],
            "boundaries": [{"id": "quantity-flow", "label": "Historical quantity flow", "internal": "External original inventory, recipes, procurement, FIFO, transport and delivery", "external": "Caller supplies finite demand and sequential tick; funding is not owned"}],
            "defaultScenario": default_scenario(self.model.GOODS),
        }

    def create(self, scenario):
        return QuantitySession(scenario, self)


def get_adapters():
    return {"private.wwo.quantity.v1": QuantityProvider()}
