"""Loopback-only v1 bridge. User-selected private plugins stay outside this repository.

Plugin contract: get_adapters() -> {id: provider}; provider.metadata (JSON dict),
provider.create(scenario) -> session; session.snapshot(), step(), optional close().
The bridge translates protocol messages; it never computes algorithm outcomes.
"""
from __future__ import annotations
import argparse
import importlib.util
import json
import os
import secrets
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import urlsplit

PROTOCOL = "wwo-sandbox/adapter/v1"
MAX_BODY = 5_000_000
SESSION_TTL = 1800


def finite_json(value):
    # Reject NaN / Infinity before a snapshot can silently become null in a browser.
    return json.dumps(value, ensure_ascii=False, allow_nan=False).encode("utf-8")


def load_adapters(path):
    if not path:
        return {}
    source = Path(path).expanduser().resolve(strict=True)
    spec = importlib.util.spec_from_file_location("sandbox_user_adapter", source)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    providers = module.get_adapters()
    for adapter_id, provider in providers.items():
        metadata = provider.metadata
        if metadata.get("protocolVersion") != PROTOCOL or metadata.get("id") != adapter_id:
            raise ValueError("adapter metadata must use matching id and protocol v1")
        finite_json(metadata)
    return providers


class BridgeServer(HTTPServer):
    def __init__(self, address, adapters, web_root):
        super().__init__(address, Handler)
        self.adapters = adapters
        self.sessions = {}
        self.web_root = Path(web_root).resolve()

    def prune(self):
        now = time.monotonic()
        for session_id, entry in list(self.sessions.items()):
            if now - entry["touched"] > SESSION_TTL:
                self.close_session(session_id)

    def close_session(self, session_id):
        entry = self.sessions.pop(session_id, None)
        if entry and hasattr(entry["session"], "close"):
            entry["session"].close()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        # Log endpoint/status only; never log scenarios, credentials or private state.
        print("bridge", self.command, urlsplit(self.path).path, flush=True)

    def check_origin(self):
        host = self.headers.get("Host", "")
        allowed_hosts = {f"127.0.0.1:{self.server.server_port}", f"localhost:{self.server.server_port}"}
        if host not in allowed_hosts:
            raise PermissionError("loopback Host required")
        origin = self.headers.get("Origin")
        if origin and origin not in {"http://127.0.0.1:5173", "http://localhost:5173", *("http://" + h for h in allowed_hosts)}:
            raise PermissionError("same local workspace Origin required")

    def respond(self, status, data):
        payload = finite_json(data)
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        try:
            self.check_origin()
            if self.path == "/api/v1/adapters":
                return self.respond(200, {"protocolVersion": PROTOCOL, "adapters": [p.metadata for p in self.server.adapters.values()]})
            if self.path.startswith("/api/"):
                return self.respond(404, {"error": "unknown API endpoint"})
            path = urlsplit(self.path).path
            candidate = (self.server.web_root / path.lstrip("/")).resolve()
            if not candidate.is_relative_to(self.server.web_root):
                return self.respond(404, {"error": "not found"})
            if not candidate.is_file():
                candidate = self.server.web_root / "index.html"
            if not candidate.is_file():
                return self.respond(404, {"error": "Run npm run build or use the Vite dev server"})
            mime = {".html": "text/html; charset=utf-8", ".js": "text/javascript", ".css": "text/css", ".svg": "image/svg+xml"}.get(candidate.suffix, "application/octet-stream")
            payload = candidate.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", mime)
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        except PermissionError as exc:
            self.respond(403, {"error": str(exc)})
        except Exception as exc:
            self.respond(400, {"error": str(exc)})

    def do_POST(self):
        try:
            self.check_origin()
            if self.headers.get("Content-Type", "").split(";")[0] != "application/json":
                return self.respond(415, {"error": "application/json required"})
            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0 or length > MAX_BODY:
                return self.respond(413, {"error": "request size limit"})
            def invalid_constant(value):
                raise ValueError(f"non-finite JSON constant: {value}")
            body = json.loads(self.rfile.read(length), parse_constant=invalid_constant)
            self.server.prune()
            if self.path == "/api/v1/sessions":
                if len(self.server.sessions) >= 32:
                    return self.respond(429, {"error": "32 local sessions maximum"})
                provider = self.server.adapters.get(body.get("adapterId"))
                if not provider:
                    return self.respond(404, {"error": "adapter not registered; no demo fallback"})
                scenario = body.get("scenario", {})
                if scenario.get("schemaVersion") != "wwo-sandbox/scenario/v1" or scenario.get("adapterId") != provider.metadata["id"]:
                    return self.respond(400, {"error": "scenario version or adapter mismatch"})
                session = provider.create(scenario)
                try:
                    snapshot = session.snapshot()
                    finite_json(snapshot)
                    if snapshot.get("tick") != 0:
                        raise ValueError("initial snapshot must have tick 0")
                except Exception:
                    if hasattr(session, "close"):
                        session.close()
                    raise
                session_id = secrets.token_urlsafe(24)
                self.server.sessions[session_id] = {"session": session, "tick": 0, "touched": time.monotonic(), "maxTicks": scenario["maxTicks"], "snapshot": snapshot}
                return self.respond(201, {"sessionId": session_id, "snapshot": snapshot})
            parts = self.path.strip("/").split("/")
            if len(parts) != 5 or parts[:3] != ["api", "v1", "sessions"]:
                return self.respond(404, {"error": "unknown endpoint"})
            entry = self.server.sessions.get(parts[3])
            if not entry:
                return self.respond(404, {"error": "session absent or expired; reset to recreate"})
            entry["touched"] = time.monotonic()
            if parts[4] == "close":
                self.server.close_session(parts[3])
                return self.respond(200, {"closed": True})
            if parts[4] != "step":
                return self.respond(404, {"error": "unknown action"})
            if type(body.get("expectedTick")) is not int or body["expectedTick"] != entry["tick"]:
                return self.respond(409, {"error": "stale or duplicate step; state was not advanced"})
            if entry["snapshot"].get("done") or entry["tick"] >= entry["maxTicks"]:
                return self.respond(409, {"error": "run complete; reset before stepping"})
            try:
                snapshot = entry["session"].step()
                finite_json(snapshot)
                if snapshot.get("kind") == "pending":
                    if snapshot.get("committedTick") != entry["tick"] or not isinstance(snapshot.get("reason"), str) or not snapshot["reason"].strip():
                        raise ValueError("PENDING must preserve committed tick and provide reason")
                    return self.respond(200, {"pending": snapshot})
                if snapshot.get("tick") != entry["tick"] + 1:
                    raise ValueError("adapter must advance exactly one tick")
                entry["tick"] = snapshot["tick"]
                entry["snapshot"] = snapshot
                return self.respond(200, {"snapshot": snapshot})
            except Exception:
                # A failed plugin call may have mutated private state. Drop the session;
                # retrying would otherwise silently double-apply a transaction.
                self.server.close_session(parts[3])
                raise
        except PermissionError as exc:
            self.respond(403, {"error": str(exc)})
        except Exception as exc:
            self.respond(400, {"error": str(exc)})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8787)
    experiment_root = Path(__file__).resolve().parents[1]
    output_root = experiment_root.parent.parent if experiment_root.parent.name == "experiments" else experiment_root
    parser.add_argument("--web-root", default=str(output_root / ".local/algorithm-workbench/dist"))
    args = parser.parse_args()
    adapters = load_adapters(os.environ.get("SANDBOX_ADAPTER_PATH"))
    server = BridgeServer(("127.0.0.1", args.port), adapters, args.web_root)
    print(f"Local sandbox http://127.0.0.1:{args.port} | {len(adapters)} registered adapter(s)", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        for session_id in list(server.sessions):
            server.close_session(session_id)
        server.server_close()


if __name__ == "__main__":
    main()
