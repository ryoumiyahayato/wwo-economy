"""Original formal Godot economy transport and observation; no settlement rules."""
from copy import deepcopy
import json
import os
from pathlib import Path
import queue
import subprocess
import threading

ID = "private.wwo.formal-economy.v1"
COMMIT = "b5bfcdd870da5d2b54f8a27e2abbfb9d511c502d"
ENTRY = "scripts/world/economy_r1_slice.gd"


def source():
    root = Path(os.environ.get("WWO_FORMAL_REPO_PATH", "")).resolve()
    if not os.environ.get("WWO_FORMAL_REPO_PATH") or not (root / ENTRY).is_file():
        raise ValueError("缺少 WWO_FORMAL_REPO_PATH；正式经济不回退研究样例")
    actual = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
    if actual != COMMIT:
        raise ValueError(f"正式经济源版本不匹配：需要 {COMMIT}，实际 {actual}")
    if subprocess.run(["git", "diff", "--quiet", "HEAD", "--", "scripts", "data", "project.godot"], cwd=root).returncode:
        raise ValueError("正式世界源码有未提交修改")
    engine = os.environ.get("WWO_GODOT_BIN", "godot")
    if not subprocess.check_output([engine, "--version"], text=True).startswith("4.6.3."):
        raise ValueError("正式经济入口要求 Godot 4.6.3")
    return root


def changes(before, state, revision):
    """Observe native records, retaining their IDs. Snapshot deltas are labeled as such."""
    if before is None:
        return []
    result = []
    old = before["native"]
    now = state["native"]
    def add(kind, record_id, raw, prior=None, **fields):
        result.append(dict(id=f"observed:{revision}:{kind}:{raw.get('id', record_id)}", nativeRecordId=record_id,
                           kind=kind, minute=state["minute"], raw=raw, before=prior, **fields))
    old_lots = old["stock_lots"]["portions"]
    for key, lot in now["stock_lots"]["portions"].items():
        prior = old_lots.get(key)
        if prior is None and lot["source_id"].startswith("production:") and not lot["parent_portion_id"]:
            add("production", lot["source_id"], lot, quantity=lot["quantity"], good=lot["good"],
                owner=lot["owner"], site=lot["custodian"], sourcePath=f"native.stock_lots.portions.{key}")
        used = lot["consumed"] - (prior["consumed"] if prior else 0)
        if used:
            add("material_used" if lot["location"].startswith("SITE|") else "consumed", key, lot, prior,
                quantity=used, good=lot["good"], owner=lot["owner"], site=lot["custodian"],
                sourcePath=f"native.stock_lots.portions.{key}")
    transaction_ids = {r["transaction_id"] for r in before["ledger"]["transactions"]}
    for row in state["ledger"]["transactions"]:
        if row["transaction_id"] not in transaction_ids:
            add("payment", row["transaction_id"], row, quantity=row["amount"],
                sourcePath="ledger.transactions")
    for key, row in now["orders"].items():
        if row != old["orders"].get(key):
            add("order", key, row, old["orders"].get(key), sourcePath=f"native.orders.{key}")
    for key, row in now.get("shipments", {}).items():
        if row != old.get("shipments", {}).get(key):
            add("cargo", key, row, old.get("shipments", {}).get(key), sourcePath=f"native.shipments.{key}")
    for key, row in now.get("wages", {}).items():
        if row != old.get("wages", {}).get(key) and row["worker"] == state.get("playerId"):
            add("wage", key, row, old.get("wages", {}).get(key), owner=row["worker"], sourcePath=f"native.wages.{key}")
    for key, row in now.get("work_records", {}).items():
        if key not in old.get("work_records", {}):
            add("work", key, row, quantity=row["hours"], owner=row["actor"], sourcePath=f"native.work_records.{key}")
    for key, row in now.get("commands", {}).items():
        if key not in old.get("commands", {}) and row.get("envelope", {}).get("actor") == state.get("playerId"):
            add("action", key, row, owner=state["playerId"], sourcePath=f"native.commands.{key}")
    travel = state.get("personal", {}).get("travel", {})
    previous_travel = before.get("personal", {}).get("travel", {})
    if travel and travel != previous_travel:
        add("journey", travel["id"], travel, previous_travel, owner=state["playerId"], sourcePath="personal.travel")
    return result


class Session:
    def __init__(self, scenario, env):
        if scenario.get("adapterId") != ID or scenario.get("domain") != "economy" or scenario.get("initialConditions") not in [{"configuration": c} for c in ["EconomyDevelopmentConfig.formal_limited", "EconomyDevelopmentConfig.formal_liquidity_request"]]:
            raise ValueError("正式经济支持原 formal_limited / formal_liquidity_request 配置")
        params = scenario.get("params", {})
        if set(params) != {"stepMinutes"} or type(params["stepMinutes"]) is not int or not 60 <= params["stepMinutes"] <= 1440 or type(scenario.get("maxTicks")) is not int or not 1 <= scenario["maxTicks"] <= 60:
            raise ValueError("stepMinutes 需60–1440整数，maxTicks 需1–60整数")
        self.step_minutes = params["stepMinutes"]
        self.tick = 0
        self.max_ticks = scenario["maxTicks"]
        self.revision = 0
        self.state = None
        self.responses = queue.Queue()
        self.diagnostics = []
        self.proc = subprocess.Popen([os.environ.get("WWO_GODOT_BIN", "godot"), "--headless",
            "--path", str(source()), "--script", str(Path(__file__).with_name("formal_economy_host.gd")), "--", json.dumps(scenario["initialConditions"])],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8", env=env)
        def read():
            try:
                for line in self.proc.stdout:
                    if line.startswith("WWO_NATIVE "):
                        self.responses.put(json.loads(line[len("WWO_NATIVE "):]))
                    else:
                        self.diagnostics = (self.diagnostics + [line.rstrip()])[-12:]
            finally:
                self.responses.put({"error": "正式经济进程退出: " + " / ".join(self.diagnostics)})
        self.reader = threading.Thread(target=read, daemon=True)
        self.reader.start()
        try: self._adopt(self._receive())
        except BaseException:
            self.close()
            raise

    def _receive(self):
        try: response = self.responses.get(timeout=45)
        except queue.Empty: raise RuntimeError("正式世界响应超时: " + " / ".join(self.diagnostics))
        if "error" in response: raise RuntimeError(response["error"])
        return response

    def _adopt(self, response):
        old = self.state
        self.state = response["state"]
        self.observed = changes(old, self.state, self.revision)
        self.previous = {"personal": old["personal"], "stock": old["native"]["stock"], "ledger": old["ledger"]} if old else None

    def _call(self, op, **fields):
        self.proc.stdin.write(json.dumps({"op": op, **fields}, ensure_ascii=False) + "\n")
        self.proc.stdin.flush()
        response = self._receive()
        self.revision += 1
        self._adopt(response)
        return response.get("result", {})

    def snapshot(self):
        s = self.state
        p, n = s["personal"], s["native"]
        return deepcopy({"tick": self.tick, "metrics": {"cash": p["cash"], "reservedCash": p["reserved"],
            "inventory": sum(p["inventory"].values()), "minute": s["minute"]},
            "stages": [{"id": "formal", "label": "原正式经济", "status": "success", "detail": "原 GameClock / SimulationStep / EconomyR1Slice"}],
            "events": [{"id": c["id"], "tick": self.tick, "stage": c["kind"], "status": "blocked" if c["kind"] == "action" and not c["raw"]["result"].get("accepted") else "success", "message": json.dumps(c, ensure_ascii=False)} for c in self.observed],
            "entities": [], "orders": [], "invariants": {}, "injections": {},
            "observations": {"nativeEconomy": {"schemaVersion": "wwo-native-economy/frame/v1", "sourceCommit": COMMIT,
                "revision": self.revision, "stepMinutes": self.step_minutes, **s, "previous": self.previous, "changes": self.observed}},
            "done": self.tick >= self.max_ticks, "completion": {"status": "pending", "condition": "原开发配置", "reason": "界面运行不代表算法正确性"}, "blockedReason": ""})

    def step(self):
        self._call("step", minutes=self.step_minutes)
        self.tick += 1
        return self.snapshot()

    def command(self, request):
        if not isinstance(request, dict) or not isinstance(request.get("parameters"), dict) or not isinstance(request.get("id"), str):
            raise ValueError("个人操作需要 id 和 parameters")
        result = self._call("command", request=request)
        return {"snapshot": self.snapshot(), "receipt": {"id": request["id"], "accepted": bool(result.get("accepted")),
            "status": "accepted" if result.get("accepted") else "rejected", "reason": str(result.get("reason", "")), "source": result}}

    def close(self):
        if self.proc.poll() is None:
            try:
                self.proc.stdin.write('{"op":"close"}\n'); self.proc.stdin.flush(); self.proc.wait(timeout=3)
            except (OSError, subprocess.TimeoutExpired):
                self.proc.terminate()
                try: self.proc.wait(timeout=3)
                except subprocess.TimeoutExpired: self.proc.kill(); self.proc.wait()
        self.reader.join(timeout=1)
        self.proc.stdin.close(); self.proc.stdout.close()


class Provider:
    def __init__(self, prototype, env):
        self.env = env
        self.metadata = deepcopy(prototype)
        try: source(); unavailable = ""
        except Exception as exc: unavailable = str(exc)
        scenario = deepcopy(prototype["defaultScenario"])
        scenario.update(adapterId=ID, name="正式个人生活 · 多经营点原配置", maxTicks=24, boundary="formal-native", params={"stepMinutes": 720},
                        initialConditions={"configuration": "EconomyDevelopmentConfig.formal_limited"}, expectations={"rules": [], "observation": "原正式宿主；开发配置假设，不是历史事实"})
        liquidity = deepcopy(scenario)
        liquidity.update(name="正式经济 · Liquidity 区域原配置", initialConditions={"configuration": "EconomyDevelopmentConfig.formal_liquidity_request"})
        self.metadata.update(id=ID, name="PRIVATE · 正式个人经济 R2", version="native-frame-v1+"+COMMIT,
            sourceRef=COMMIT+"; "+ENTRY, supportsCommands=True, unavailableReason=unavailable,
            defaultScenario=scenario, scenarios=[scenario, liquidity], parameters=[{"key":"stepMinutes", "label":"每步原时钟分钟", "min":60, "max":1440, "step":60}], metrics=[{"key": "cash", "label": "本人账户余额"}, {"key": "reservedCash", "label": "本人已预留"}, {"key": "inventory", "label": "本人持有数量（异品种合计）"}],
            seedNote="原正式开发配置；种子仅作为沙盒记录，不改变原算法随机性",
            boundaries=[{"id": "formal-native", "label": "正式原宿主", "internal": "原 GameClock、Ledger、EconomyR1Slice、LivelihoodAction", "external": "研究真值供评阅；个人操作仍经原当前玩家/存活/领域权限。开发企业与配方非历史事实；无厂房精确坐标。"}])

    def create(self, scenario):
        if self.metadata["unavailableReason"]: raise ValueError(self.metadata["unavailableReason"])
        if scenario.get("dependencies") != self.metadata["lockedDependencies"]:
            raise ValueError("正式经济依赖由原宿主拥有")
        return Session(scenario, self.env())
