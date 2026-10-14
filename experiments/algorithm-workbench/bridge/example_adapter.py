"""Original synthetic counter: demonstrates the bridge protocol, not an economy algorithm."""
from copy import deepcopy

SCENARIO = {
    "schemaVersion": "wwo-sandbox/scenario/v1", "name": "Bridge protocol demo",
    "domain": "economy", "adapterId": "demo.bridge.counter.v1", "seed": 42,
    "maxTicks": 5, "boundary": "protocol",
    "dependencies": {"supply": "on-demand", "transport": "instant", "funding": "normal", "path": "direct", "resupply": "on-demand"},
    "params": {"increment": 1},
    "expectations": {"rules": [{"id": "counter", "label": "Counter reaches 1 at tick 1", "target": "metric", "key": "counter", "operator": "eq", "value": 1, "byTick": 1}], "observation": "Protocol-only fixture; no market behavior is claimed."},
}


class CounterSession:
    def __init__(self, scenario):
        self.scenario = deepcopy(scenario)
        if type(scenario["params"].get("increment")) is not int or not 0 <= scenario["params"]["increment"] <= 10:
            raise ValueError("increment must be 0–10 integer")
        self.tick = 0

    def snapshot(self):
        return {"tick": self.tick, "metrics": {"counter": self.tick * self.scenario["params"]["increment"]},
                "stages": [{"id": "protocol", "label": "Counter", "status": "success", "detail": "Synthetic protocol fixture only"}],
                "events": [{"tick": self.tick, "stage": "protocol", "status": "success", "message": "Original counter step"}] if self.tick else [],
                "entities": [], "orders": [], "invariants": {}, "injections": {}, "done": self.tick >= self.scenario["maxTicks"],
                "completion": {"status": "pending", "condition": "Protocol fixture only", "reason": "Evaluate independent expectations"}, "blockedReason": ""}

    def step(self):
        self.tick += 1
        return self.snapshot()


class CounterProvider:
    metadata = {
        "protocolVersion": "wwo-sandbox/adapter/v1", "id": "demo.bridge.counter.v1", "name": "Demo · bridge counter",
        "domain": "economy", "kind": "demo", "version": "1.0.0", "sourceRef": "original synthetic counter, no WWO source",
        "parameters": [{"key": "increment", "label": "Counter increment", "min": 0, "max": 10, "step": 1}],
        "boundaries": [{"id": "protocol", "label": "Bridge protocol", "internal": "Synthetic counter transition", "external": "No external services"}],
        "defaultScenario": SCENARIO,
    }

    def create(self, scenario):
        return CounterSession(scenario)


def get_adapters():
    return {"demo.bridge.counter.v1": CounterProvider()}
