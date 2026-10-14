"""External WWO calls only: no economy/war settlement implementation lives here.

Each session has a separate Python worker. Military state stays in the original
Godot process; economy state stays in the original ProgrammeWorld instance.
"""
from copy import deepcopy
import importlib.util
import json
import os
from pathlib import Path
import queue
import subprocess
import sys
import threading

ROOT = Path(__file__).resolve().parents[3]
SOURCES = {
    "economy": ("WWO_ECONOMY_REPO_PATH", "b5bfcdd870da5d2b54f8a27e2abbfb9d511c502d",
                "research/economy/fifteen-algorithms/economy_quantity_lab/algorithm_completion/world.py"),
    "military": ("WWO_MILITARY_REPO_PATH", "04ab3cc9ffb2233fa0ab5290e0ec0a952f229630",
                 "experiments/war_resolver/interactive_observer/client.py"),
}
FINITE = {"supply": "finite", "transport": "bounded", "funding": "finite", "path": "direct", "resupply": "finite"}
IDS = {"economy": "private.wwo.programme.v1", "military": "private.wwo.military.v5"}


def runtime_environment():
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
    for name, folder in [("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")]:
        path = ROOT / ".local/algorithm-workbench/godot" / folder
        path.mkdir(parents=True, exist_ok=True)
        env[name] = str(path)
    return env


def source_path(domain):
    variable, expected, relative = SOURCES[domain]
    value = os.environ.get(variable)
    if not value:
        raise ValueError(f"缺少 {variable}：请指向外部 WWO 检出，不会回退 demo")
    path = Path(value).expanduser().resolve(strict=True)
    if path == ROOT or path.is_relative_to(ROOT):
        raise ValueError("真实 WWO 源码必须在沙盒仓库之外")
    if not (path / relative).is_file():
        raise ValueError(f"该路径缺少真实入口 {relative}")
    actual = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=path, text=True).strip()
    if actual != expected:
        raise ValueError(f"WWO 源版本不匹配：需要 {expected}，实际 {actual}")
    scope = "research/economy/fifteen-algorithms" if domain == "economy" else "experiments/war_resolver"
    if subprocess.run(["git", "diff", "--quiet", "HEAD", "--", scope], cwd=path).returncode:
        raise ValueError("真实入口有未提交修改；请使用单独的已提交源检出")
    return path


def default_scenario(domain):
    rules = ([{"id": "consume", "label": "第3日累计食物满足量至少18", "target": "metric", "key": "fulfilled", "operator": "gte", "value": 18, "byTick": 3}, {"id": "unmet", "label": "第3日未满足量为0", "target": "metric", "key": "unmet", "operator": "eq", "value": 0, "byTick": 3}]
             if domain == "economy" else [{"id": "move", "label": "原人物实际向前移动", "target": "entity", "subjectId": "squad", "key": "x", "operator": "gte", "value": .001, "byTick": 1}])
    return {"schemaVersion": "wwo-sandbox/scenario/v1", "name": "真实研究经济 · J1_normal" if domain == "economy" else "真实军事 v5 · A3/squad",
            "domain": domain, "adapterId": IDS[domain], "seed": 42 if domain == "economy" else 71,
            "maxTicks": 6, "boundary": "programme" if domain == "economy" else "person-visible",
            "dependencies": deepcopy(FINITE), "params": {} if domain == "economy" else {"stepSeconds": 30, "quota": 31},
            "initialConditions": {"fixture": "J1_normal"} if domain == "economy" else {"scene": "A3", "actor": "squad", "commands": ["intent sandbox_move node_unit_000 advance B AB"]},
            "expectations": {"rules": rules, "observation": "独立预期是实验输入。调用外部原实现，不用适配器完成成交/移动；未上报值保持缺失。"}}


class WorkerSession:
    def __init__(self, domain, scenario):
        source_path(domain)
        if scenario.get("adapterId") != IDS[domain] or scenario.get("domain") != domain:
            raise ValueError("真实适配器与场景不匹配")
        if scenario.get("dependencies") != FINITE:
            raise ValueError("本闭环的资金/库存/运输/路径/补给由真实代码拥有；未实现外部替身，不能理想化覆盖")
        if type(scenario.get("maxTicks")) is not int or not 1 <= scenario["maxTicks"] <= 1000 or type(scenario.get("seed")) is not int or not 0 <= scenario["seed"] <= 4294967295:
            raise ValueError("maxTicks 需要1–1000整数；seed需要0–4294967295整数")
        expected_params = set() if domain == "economy" else {"stepSeconds", "quota"}
        if not isinstance(scenario.get("params"), dict) or set(scenario["params"]) != expected_params:
            raise ValueError("当前真实入口参数仅支持 " + ("stepSeconds/quota" if domain == "military" else "空 params；研究配置请放初始条件 case"))
        self.responses = queue.Queue()
        env = runtime_environment()
        self.proc = subprocess.Popen([sys.executable, "-B", str(Path(__file__).resolve()), "--worker", domain],
                                     stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                     text=True, env=env, cwd=ROOT)
        self.stderr = []
        def read():
            try:
                for line in self.proc.stdout:
                    self.responses.put(json.loads(line))
            except Exception as exc:
                self.responses.put({"error": str(exc)})
            finally:
                self.responses.put({"error": "真实工作进程已退出"})
        def diagnostics():
            for line in self.proc.stderr:
                self.stderr = (self.stderr + [line.rstrip()])[-8:]
        self.reader = threading.Thread(target=read, daemon=True); self.reader.start()
        self.diagnostics = threading.Thread(target=diagnostics, daemon=True); self.diagnostics.start()
        try:
            self.current = self.call("create", scenario=scenario)
        except Exception:
            self.close(); raise

    def call(self, op, **data):
        if self.proc.poll() is not None:
            raise RuntimeError("真实工作进程已退出；请重置")
        self.proc.stdin.write(json.dumps({"op": op, **data}, ensure_ascii=False, allow_nan=False) + "\n"); self.proc.stdin.flush()
        try:
            response = self.responses.get(timeout=18)
        except queue.Empty:
            raise RuntimeError("真实算法响应超时；保留最后有效状态，请重置")
        if "error" in response:
            raise RuntimeError(response["error"])
        return response if op == "command" else response["snapshot"]

    def snapshot(self):
        return deepcopy(self.current)

    def step(self):
        response = self.call("step")
        if response.get("kind") != "pending":
            self.current = response
        return response
    def command(self, request):
        response = self.call("command", request=request)
        self.current = response["snapshot"]
        return response

    def close(self):
        if self.proc.poll() is None:
            try:
                self.proc.stdin.write('{"op":"close"}\n'); self.proc.stdin.flush()
                self.proc.wait(timeout=3)
            except (OSError, subprocess.TimeoutExpired):
                self.proc.terminate()
                try: self.proc.wait(timeout=3)
                except subprocess.TimeoutExpired: self.proc.kill(); self.proc.wait()
        self.reader.join(timeout=1); self.diagnostics.join(timeout=1)
        for stream in [self.proc.stdin, self.proc.stdout, self.proc.stderr]:
            if stream: stream.close()


class Provider:
    def __init__(self, domain):
        self.domain = domain
        normal = default_scenario(domain); mismatch = deepcopy(normal)
        if domain == "economy":
            mismatch["name"] = "真实经济故意不符 · J3_shortage"
            mismatch["initialConditions"]["fixture"] = "J3_shortage"
        else:
            mismatch["name"] = "真实军事故意不符 · 未发移动意图"
            mismatch["initialConditions"]["commands"] = []
        interactive = deepcopy(normal)
        if domain == "military":
            interactive["name"] = "行动场景 · 等待玩家下令"
            interactive["initialConditions"]["commands"] = []
        try:
            source_path(domain); unavailable = ""
            if domain == "military":
                engine = os.environ.get("WWO_GODOT_BIN", "/usr/local/bin/godot")
                version = subprocess.check_output([engine, "--version"], text=True, stderr=subprocess.PIPE, env=runtime_environment()).strip()
                if not version.startswith("4.6.3."): raise ValueError("军事入口要求 Godot 4.6.3")
        except Exception as exc:
            unavailable = str(exc)
        self.metadata = {"protocolVersion": "wwo-sandbox/adapter/v1", "id": IDS[domain], "name": "PRIVATE · ProgrammeWorld" if domain == "economy" else "PRIVATE · military v5 person view",
                         "domain": domain, "kind": "private", "version": "scene-calls-v2+"+SOURCES[domain][1],
                         "supportsCommands": domain == "military",
                         "sourceRef": ("未载入；要求 " if unavailable else "外部 WWO ") + SOURCES[domain][1] + "; " + SOURCES[domain][2],
                         "unavailableReason": unavailable,
                         "seedNote": "此研究经济未暴露 RNG；种子作为实验记录，不宣称改变算法随机性" if domain == "economy" else "固定种子传给原 Godot 世界；每次复现启动独立实例",
                         "lockedDependencies": deepcopy(FINITE),
                         "parameters": [] if domain == "economy" else [{"key": "stepSeconds", "label": "每步游戏秒", "min": 1, "max": 300, "step": 1}, {"key": "quota", "label": "原有界配额（0/1/7/31）", "min": 0, "max": 31, "step": 1}],
                         "metrics": ([{"key": "fulfilled", "label": "累计食物满足量"}, {"key": "unmet", "label": "本日未满足量"}, {"key": "cashTotal", "label": "账户余额合计（未换算）"}, {"key": "inTransit", "label": "实际在途数量"}] if domain == "economy" else [{"key": "elapsedSeconds", "label": "已提交游戏秒"}, {"key": "position", "label": "本人实际 x（km）"}, {"key": "health", "label": "本人健康份额"}, {"key": "acceptedCommands", "label": "原域接受的命令数"}]),
                         "boundaries": [{"id": normal["boundary"], "label": "真实研究日循环" if domain == "economy" else "原人物可见闭环", "internal": "原代码结算；适配器只传入初始条件、调用时间入口和读取已提交观测", "external": "未注入替身；所选闭环依赖保持源约束。军事仅显示本人/已收到报告，未知值不补造。"}],
                         "defaultScenario": interactive if domain == "military" else normal, "scenarios": [interactive, normal, mismatch] if domain == "military" else [normal, mismatch]}

    def create(self, scenario):
        if self.metadata["unavailableReason"]: raise ValueError(self.metadata["unavailableReason"])
        return WorkerSession(self.domain, scenario)


def get_adapters():
    return {IDS[domain]: Provider(domain) for domain in SOURCES}


class EconomyCalls:
    def __init__(self, scenario):
        path = source_path("economy") / Path(SOURCES["economy"][2]).parent
        sys.path.insert(0, str(path))
        from world import ProgrammeWorld
        from programme_fixtures import scenario as source_fixture
        self.input = deepcopy(scenario); initial = scenario.get("initialConditions")
        if not isinstance(initial, dict) or set(initial) not in [{"fixture"}, {"case"}]:
            raise ValueError("经济初始条件需要 fixture 或 case，且只能选一种")
        if "case" in initial:
            if not isinstance(initial["case"], dict): raise ValueError("case 必须为完整研究配置对象")
            case = deepcopy(initial["case"]); case["days"] = scenario["maxTicks"]
        else:
            if initial["fixture"] not in ["J1_normal", "J3_shortage"]:
                raise ValueError("最小 fixture 只支持 J1_normal / J3_shortage；其他配置用 case 显式输入")
            case = source_fixture(initial["fixture"], days=scenario["maxTicks"])
        self.world = ProgrammeWorld(case); self.events = []; self.last_needs = None

    def step(self):
        before = len(self.world.trace)
        row = self.world.step(); self.last_needs = row["needs"]; self.events = self.world.trace[before:]
        return self.snapshot()

    def snapshot(self):
        w = self.world; raw = w.snapshot()
        metrics = {"fulfilled": sum(n["consumed"] for n in w.need_history), "cashTotal": sum(a["balance"] for a in raw["cash"].values()),
                   "reservedCash": sum(a["reserved"] for a in raw["cash"].values()), "inventory": sum(sum(v.values()) for v in raw["stock"].values()),
                   "inTransit": sum(s["quantity"] for o in raw["orders"].values() for s in o["shipments"].values()), "orderCount": len(raw["orders"])}
        if self.last_needs is not None: metrics["unmet"] = sum(n["unmet"] for n in self.last_needs.values())
        events = [{"id": str(e["seq"]), "tick": w.day, "stage": e["event"], "status": "success", "message": json.dumps({k:v for k,v in e.items() if k not in ["state", "fixture"]}, ensure_ascii=False, default=str),
                   **({"entityId": str(e["order_id"])} if "order_id" in e else {"entityId": str(e["actor"])} if "actor" in e else {})} for e in self.events]
        return {"tick": w.day, "metrics": metrics, "stages": [{"id": "programme", "label": "原 ProgrammeWorld.step", "status": "success" if w.day else "pending", "detail": "源时钟一日一调用；资金/库存/生产/采购/消费均由原代码执行"}],
                "events": events, "entities": [], "orders": [{"id": oid, "quantity": o["quantity"], "pending": o["pending"], "inTransit": sum(s["quantity"] for s in o["shipments"].values()), "delivered": o["delivered"], "cancelled": o["cancelled"]} for oid,o in raw["orders"].items()],
                "observations": {"timeUnit": "research day", "needs": self.last_needs, **raw}, "invariants": w.check_accounts(), "injections": {},
                "done": w.day >= self.input["maxTicks"], "completion": {"status": "pending", "condition": "独立预期判定", "reason": "真实十五算法研究日循环；不代表正式 GDScript 全面验证"},
                "blockedReason": "真实本日需求未满足；查看源 needs / stock / cash 和事件" if metrics.get("unmet", 0) else ""}

    def close(self): pass


class MilitaryCalls:
    def __init__(self, scenario):
        root = source_path("military"); initial = scenario.get("initialConditions")
        if not isinstance(initial, dict) or set(initial) != {"scene", "actor", "commands"}:
            raise ValueError("军事初始条件必须明确 scene、actor、commands")
        if initial["scene"] != "A3" or initial["actor"] != "squad":
            raise ValueError("当前最小入口只接通 A3/squad；其他角色尚未验证")
        commands = initial["commands"]
        if not isinstance(commands, list) or len(commands) > 8 or any(not isinstance(c,str) or not c.startswith("intent ") for c in commands):
            raise ValueError("commands 为最多8条原 intent 命令；不能用输入绕过时间或改写状态")
        params = scenario["params"]
        if type(params.get("stepSeconds")) is not int or not 1 <= params["stepSeconds"] <= 300 or type(params.get("quota")) is not int or params.get("quota") not in [0,1,7,31]:
            raise ValueError("每步秒数需要1–300整数，有界配额只能是0/1/7/31")
        if scenario["maxTicks"] * params["stepSeconds"] > 86400: raise ValueError("原客户端总游戏秒上限86400")
        spec = importlib.util.spec_from_file_location("wwo_original_client", root / SOURCES["military"][2]); module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        self.connection = module.Connection.__new__(module.Connection)
        try:
            self.connection.__init__(scene=initial["scene"], actor=initial["actor"], seed=scenario["seed"], session="sandbox_session", quota=params["quota"], godot=os.environ.get("WWO_GODOT_BIN", "/usr/local/bin/godot"), root=root)
        except Exception as exc:
            details = " | ".join(getattr(self.connection, "raw_diagnostics", [])[-6:])
            raise RuntimeError(f"原 Godot 客户端启动失败：{exc}；{details}")
        self.input = deepcopy(scenario); self.tick = 0; self.pending = False; self.seen = set()
        for command in commands:
            response = self.connection.text(command)
            if not response.get("ok"): self.connection.close(); raise ValueError("原命令拒绝：" + str(response.get("error")))
        self.person = self.connection.send("look")["person"]

    def step(self):
        c = self.connection
        response = c.send("resume", {"calls": 64}) if self.pending else c.send("advance", {"seconds": self.input["params"]["stepSeconds"]})
        if not response.get("ok"): raise RuntimeError("原推进失败：" + str(response.get("error", response.get("status"))))
        self.pending = bool(c.last_program.get("pending"))
        if self.pending:
            return {"kind": "pending", "committedTick": self.tick, "reason": f"原 Godot 有界结算未完成；保留已提交 {self.person['time']} 秒，继续同一目标"}
        self.person = c.send("look")["person"]
        expected = (self.tick + 1) * self.input["params"]["stepSeconds"]
        if abs(self.person["time"] - expected) > 1e-8: raise RuntimeError("原时钟未完成请求目标；不能伪造步进")
        self.tick += 1
        return self.snapshot()
    def command(self, request):
        if not isinstance(request,dict) or set(request)!={"id","target","intent","node","path"} or request.get("intent") not in ["advance","hold","withdraw","cancel"]:
            raise ValueError("仅接通原 intent 的前进/驻守/撤回/取消")
        response=self.connection.send("intent",request)
        if not self.pending:
            self.person=self.connection.send("look")["person"]
        receipt=response.get("receipt",{})
        return {"receipt":{"id":request["id"],"accepted":receipt.get("accepted") is True,"status":receipt.get("status",response.get("status","PROGRAM_REJECTED")),"reason":receipt.get("reason",response.get("error","")),"source":response},"snapshot":self.snapshot()}

    def snapshot(self):
        p = self.person; body = p["personal"]; metrics = {"elapsedSeconds": p["time"], "acceptedCommands": sum(r.get("accepted") is True for r in p["own_receipts"])}
        entities = []
        if isinstance(body.get("xy"), list) and len(body["xy"]) == 2:
            metrics["position"] = body["xy"][0]
            entities = [{"id": p["person_id"], "label": p["person_id"], "granularity": "person", "x": body["xy"][0], "y": body["xy"][1], "state": body.get("life_state", body.get("state", "UNKNOWN"))}]
        if isinstance(body.get("health"), (int,float)): metrics["health"] = body["health"]
        if isinstance(body.get("weapon", {}).get("spent"), (int,float)): metrics["shots"] = body["weapon"]["spent"]
        events = []
        for record in p["events"]["records"]:
            cursor = record["cursor"]
            if cursor in self.seen: continue
            self.seen.add(cursor)
            status = "blocked" if record.get("accepted") is False else "pending" if record.get("status") in ["PENDING", "ISSUED_WAITING", "REQUEST_RECEIVED", "DECISION_SCHEDULED"] or record["kind"] == "person_input" else "success"
            events.append({"tick": self.tick, "id": f"visible_{cursor}", "stage": record["kind"], "status": status, "entityId": record.get("actor_ref", record.get("holder_ref", p["person_id"])), "message": json.dumps(record, ensure_ascii=False)})
        # Only the original person-visible result is retained; no hidden-world export.
        return {"tick": self.tick, "metrics": metrics, "stages": [{"id": "original-client", "label": "原 Godot 人物客户端", "status": "success", "detail": f"已提交 {p['time']} 游戏秒；原意图/送达/动作规则未替换"}],
                "events": events, "entities": entities, "orders": [], "observations": {"coordinateUnit": "km in original abstract road world; no geographic projection declared", "person": p},
                "invariants": {}, "injections": {}, "done": self.tick >= self.input["maxTicks"], "completion": {"status": "pending", "condition": "检查独立预期及本人已知事实", "reason": "真实 v5 最小人物入口；未上报精确弹药和全军伤亡保持缺失"},
                "blockedReason": ""}

    def close(self): self.connection.close()


def worker(domain):
    instance = None
    try:
        for line in sys.stdin:
            try:
                request = json.loads(line)
                if request["op"] == "close": break
                if request["op"] == "create":
                    instance = (EconomyCalls if domain == "economy" else MilitaryCalls)(request["scenario"])
                    snapshot = instance.snapshot()
                elif request["op"] == "step" and instance is not None: snapshot = instance.step()
                elif request["op"] == "command" and isinstance(instance,MilitaryCalls):
                    print(json.dumps(instance.command(request["request"]),ensure_ascii=False,allow_nan=False),flush=True)
                    continue
                else: raise ValueError("无效真实调用序列")
                print(json.dumps({"snapshot": snapshot}, ensure_ascii=False, allow_nan=False), flush=True)
            except Exception as exc:
                print(json.dumps({"error": f"{type(exc).__name__}: {exc}"}, ensure_ascii=False), flush=True)
                break
    finally:
        if instance is not None: instance.close()


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--worker" and sys.argv[2] in SOURCES:
        worker(sys.argv[2])
