#!/usr/bin/env python3
"""Bounded infrastructure checks; never run the global market simulation entrypoint."""
from __future__ import annotations

import argparse
import ast
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import re
import resource
import shutil
import signal
import subprocess
import sys
import tarfile
import tempfile
import time
import zipfile
import base64
import zlib

REPOSITORY = "ryoumiyahayato/wwo-economy"
RELEASE = "economy-gen23-closeout-20261024"
SOURCE_SHA256 = "ae499943bd4a79c27086003d0b3b24b3acd030b50a508fb50c5557fa9d80102a"
INDEX_SHA256 = "e5acd5af8324d1fd5a16cbb3309b1e4391356efb1612b35ef79ecc528d89cc58"
SOURCE_PATHS = ["project.godot", "export_presets.cfg", "scripts", "merchant", "shaders", ".godot/global_script_class_cache.cfg"]
ROOT = Path(__file__).resolve().parents[1]
WORKBENCH = ROOT / "experiments/algorithm-workbench"
SMALL_LIMIT = 16 * 1024 * 1024


class Unverified(RuntimeError):
    """A prerequisite is missing; this is not a successful check."""


def clean(text):
    # gh can include signed redirect URLs in errors; retain only non-query URLs.
    return re.sub(r'''(https?://[^\s?"']+)\?[^\s"']+''', r'\1?[redacted]', text)


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def notice_evidence(name, detail):
    """Bounded receipts; full data stays in the human-readable Actions summary."""
    if name=='365-day global scenarios' and isinstance(detail,dict):
        baseline=detail['runs'][0]
        selected={'united_states_1900':'wheat','country_fra':'wheat','german_empire':'coal','british_isles_1900':'wheat'}
        runs=[]
        for run in detail['runs']:
            markets={}
            for region,good in selected.items():
                deltas=[(m['day'],m['markets'][region][good]['price']-b['markets'][region][good]['price']) for m,b in zip(run['marks'],baseline['marks'])]
                end=run['marks'][-1]['markets'][region][good]
                markets[region]={'good':good,'price_day365':round(end['price'],5),'cover_day365':round(end['cover'],5),'unmet_day365':round(end['unmet'],5),'max_sample_price_delta':round(max(deltas,key=lambda p:abs(p[1]))[1],5),'first_sample_effect_day':next((day for day,delta in deltas if abs(delta)>1e-5),None),'price_samples':[round(m['markets'][region][good]['price'],4) for m in run['marks']]}
            runs.append({'scenario':run['scenario'],'regions':run['regions'],'goods':run['goods'],'edges':run['edges'],'simulation_us':run['simulation_us'],'typed_state_bytes':run['typed_state_bytes'],'restore_reference':run['restore_reference'],'markets':markets})
        return {'status':'PASS','sample_days':[m['day'] for m in baseline['marks']],'scope':detail['scope'],'runs':runs}
    if name in {'coupled-fresh','coupled-reasons'} and isinstance(detail,dict):
        return {**{k:v for k,v in detail.items() if k!='conditions'},'conditions':[
            {**{k:v for k,v in c.items() if k not in {'begin','end'}},
             'begin':{k:v for k,v in c['begin'].items() if k!='costs'},
             'end':{k:v for k,v in c['end'].items() if k!='costs'}} for c in detail['conditions']]}
    if name=='grain-followup' and isinstance(detail,dict):
        for case in detail['cases']:
            for mark in case['marks']:
                mark.get('cell',{}).pop('history',None)
        return detail
    if name=='Gen23 person native chain' and isinstance(detail,dict):
        return {**{k:v for k,v in detail.items() if k!='evidence'},'evidence':[{k:v for k,v in row.items() if k not in ['changes','orders','travel','employment']} for row in detail['evidence']]}
    return detail


def safe_relative(name):
    path = PurePosixPath(name)
    if path.is_absolute() or ".." in path.parts or "\\" in name:
        raise ValueError(f"Unsafe archive path: {name}")
    return path


def extract_tar(archive, destination):
    with tarfile.open(archive) as bundle:
        members = bundle.getmembers()
        for member in members:
            safe_relative(member.name)
            if not (member.isfile() or member.isdir()):
                raise ValueError(f"Unsupported archive member: {member.name}")
        needed = sum(member.size for member in members)
        if shutil.disk_usage(destination).free < needed + 1024**3:
            raise RuntimeError(f"Insufficient disk space for {archive.name}: {needed} extracted bytes")
        bundle.extractall(destination, members=members, filter="data")


def index_paths(text):
    """Read explicit paths, never infer restoration coverage from basenames."""
    values = []
    try:
        data = json.loads(text)
    except ValueError:
        for line in text.splitlines():
            line = re.sub(r"^[0-9a-fA-F]{64}\s+\*?", "", line.strip())
            if line and not line.startswith("#"):
                values.append(line.strip('"'))
    else:
        def visit(value):
            if isinstance(value, str):
                values.append(value)
            elif isinstance(value, list):
                for item in value:
                    visit(item)
            elif isinstance(value, dict):
                for key, item in value.items():
                    # Some manifests key records by the full relative filename.
                    if "/" in key:
                        values.append(key)
                    visit(item)
        visit(data)
    paths = set()
    for value in values:
        value = value.replace("\\", "/").removeprefix("res://")
        if "baseline23/" in value:
            value = value.split("baseline23/", 1)[1]
        value = value.removeprefix("./")
        if value.startswith(("assets/", "data/", "shared/", "scripts/", "merchant/", "shaders/", ".godot/")):
            safe_relative(value)
            paths.add(value)
    return paths


class Check:
    def __init__(self, mode, output):
        self.mode = mode
        self.output = output.resolve()
        # A fresh directory prevents stale reports from masquerading as this run.
        self.output.mkdir(parents=True, exist_ok=False)
        self.started = time.monotonic()
        self.rows = []
        self.temp = tempfile.TemporaryDirectory(prefix="wwo-economy-check-")
        self.scratch = Path(self.temp.name)
        self.release = None
        self.assets = {}
        self.downloaded = {}
        self.index = set()
        self.metadata = {
            "started_at_utc": datetime.now(timezone.utc).isoformat(),
            "repository": REPOSITORY,
            "ref": os.environ.get("GITHUB_REF", subprocess.check_output(["git", "branch", "--show-current"], cwd=ROOT, text=True).strip()),
            "sha": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
            "mode": mode,
            "workflow": os.environ.get("GITHUB_WORKFLOW", "local reproduction (not GitHub Actions)"),
            "run_url": (f"https://github.com/{REPOSITORY}/actions/runs/{os.environ['GITHUB_RUN_ID']}" if os.environ.get("GITHUB_RUN_ID") else None),
            "runner": {"os": platform.platform(), "python": platform.python_version(), "cpu_count": os.cpu_count(), "initial_free_disk_bytes": shutil.disk_usage(self.scratch).free, "image": os.environ.get("ImageVersion")},
            "release": RELEASE,
        }

    def command(self, args, label, cwd=ROOT, timeout=180, credentials=False, env=None):
        process_env = dict(os.environ)
        if not credentials:
            for key in list(process_env):
                if key in {"GH_TOKEN", "GITHUB_TOKEN", "SANDBOX_ADAPTER_PATH"} or key.startswith("WWO_"):
                    process_env.pop(key)
        process_env["PYTHONDONTWRITEBYTECODE"] = "1"
        if env:
            process_env.update(env)
        process = subprocess.Popen(args, cwd=cwd, env=process_env, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, text=True, start_new_session=True)
        try:
            output, _ = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            output, _ = process.communicate()
            (self.output / f"{label}.log").write_text(clean(output)[-240000:] + "\nTIMEOUT\n")
            raise RuntimeError(f"{label} exceeded {timeout}s; its process group was stopped")
        (self.output / f"{label}.log").write_text(clean(output)[-240000:])
        if process.returncode:
            raise RuntimeError(f"{label} exited {process.returncode}: {clean(output)[-2000:]}")
        return output

    def check(self, name, function):
        began = time.monotonic()
        try:
            detail = function()
            status = "PASS"
        except Unverified as error:
            status, detail = "UNVERIFIED", str(error)
        except Exception as error:
            status, detail = "FAILED", f"{type(error).__name__}: {error}"
        self.rows.append({"check": name, "status": status, "seconds": round(time.monotonic()-began, 3), "detail": detail})
        print(f"{status}: {name}: {str(detail)[:700]}", flush=True)
        proof_names={'coupled-reasons','grain-followup','Verified resource restore, Godot import and bounded scene load','365-day global scenarios','coupled-fresh','industry','trade','ui','Gen23 person native chain'}
        if self.mode in {"round2-full","grain-followup"} and name in proof_names:
            row={**self.rows[-1],'detail':notice_evidence(name,detail)}
            payload = {"encoding":"zlib+base64","payload":base64.b64encode(zlib.compress(json.dumps(row,ensure_ascii=False).encode())).decode()}
            notice = json.dumps(payload).replace('%','%25').replace('\r','%0D').replace('\n','%0A')
            # GitHub annotations truncate messages at 4096 bytes. At most two
            # chunks per economic stage, keeping this job below the ten notices.
            if len(notice)>3900:
                raw=payload['payload'];parts=[raw[i:i+3400] for i in range(0,len(raw),3400)]
                for index,part in enumerate(parts):
                    print('::notice title=WWO round2::'+json.dumps({'encoding':'chunk','check':name,'index':index,'count':len(parts),'payload':part}),flush=True)
                return
            print(f"::notice title=WWO round2::{notice}", flush=True)

    def source(self):
        assert sys.version_info >= (3,12), "Python >=3.12 is required"
        if os.environ.get("GITHUB_ACTIONS") == "true":
            assert os.environ["GITHUB_REPOSITORY"] == REPOSITORY
            assert os.environ["GITHUB_REF"] == "refs/heads/sandbox/main"
            assert self.metadata["sha"] == os.environ["GITHUB_SHA"]
        required = ["README.md", "AGENTS.md", "project.godot", "scripts/world/global_commodity_reference.gd", "merchant/run_global_market.gd", "merchant/global_market_scenario.json", "experiments/algorithm-workbench/package-lock.json", "experiments/individual-person-sandbox/README.md"]
        for name in required:
            assert (ROOT/name).is_file(), f"Required file missing: {name}"
        project = (ROOT/"project.godot").read_text()
        assert re.search(r'config/build_sequence=23\b', project), "Expected Gen23 project"
        assert 'merchant-global-commodity-20261023' in project
        self.command(["git", "diff", "HEAD", "--exit-code", "--", *SOURCE_PATHS, str(WORKBENCH.relative_to(ROOT))], "tracked-diff")
        return {"required_files": required, "build_sequence": 23, "scope": "source provenance only; no Godot, benchmark or saves executed"}

    def release_inventory(self):
        try:
            raw = self.command(["gh", "api", f"repos/{REPOSITORY}/releases/tags/{RELEASE}"], "release-api", credentials=True, timeout=45)
        except Exception as error:
            raise Unverified(f"Cannot inspect private Release: {error}") from error
        # Raw API payload is not an artifact: it can include download URLs.
        (self.output/"release-api.log").unlink()
        self.release = json.loads(raw)
        assert self.release["tag_name"] == RELEASE
        for asset in self.release["assets"]:
            name = asset["name"]
            assert PurePosixPath(name).name == name and "\\" not in name
            assert name not in self.assets, f"Duplicate Release asset: {name}"
            self.assets[name] = asset
        inventory = [{key: a.get(key) for key in ("id", "name", "size", "digest")} for a in self.assets.values()]
        (self.output/"release-inventory.json").write_text(json.dumps(inventory, indent=2))
        assert "01-source23.tar.gz" in self.assets
        assert any(re.fullmatch(r"02-resources23-.+\.tar\.gz", name) for name in self.assets)
        assert "RESTORE.md" in self.assets
        restore = self.download("RESTORE.md", small=True).read_text()
        assert restore.strip(), "Empty RESTORE.md"
        return {"assets": len(inventory), "total_release_bytes": sum(a["size"] for a in inventory), "restore_instructions_read": True, "large_downloads": False}

    def download(self, name, small=False):
        if name in self.downloaded:
            return self.downloaded[name]
        asset = self.assets[name]
        if small and asset["size"] > SMALL_LIMIT:
            raise Unverified(f"Metadata exceeds quick-mode limit: {name}")
        destination = self.scratch/name
        # Stream asset output directly to disk; never print auth/redirect headers.
        with destination.open("wb") as stream:
            result = subprocess.run(["gh", "api", f"repos/{REPOSITORY}/releases/assets/{asset['id']}", "-H", "Accept: application/octet-stream"], stdout=stream, stderr=subprocess.PIPE, timeout=900 if not small else 60)
        if result.returncode:
            raise RuntimeError(f"Release asset download failed: {name}: {clean(result.stderr.decode())[:1200]}")
        assert destination.stat().st_size == asset["size"], f"Incomplete download: {name}"
        digest = asset.get("digest")
        if digest:
            assert digest.startswith("sha256:")
            assert sha256(destination) == digest[7:], f"SHA256 mismatch: {name}"
        self.downloaded[name] = destination
        return destination

    def restore_index(self):
        if not self.release:
            raise Unverified("Private Release metadata unavailable; restoration index not checked")
        # RESTORE.md identifies this small index archive, not the multi-GB resources.
        name = "07-restore-index.tar.gz"
        if name not in self.assets:
            raise Unverified(f"Required restoration index missing: {name}")
        archive = self.download(name, small=True)
        assert sha256(archive) == INDEX_SHA256, "Archived restoration index SHA256 mismatch"
        with tarfile.open(archive) as bundle:
            member = bundle.getmember("archive-index/CONTENTS.json")
            assert member.isfile() and member.size <= 128*1024*1024, "Unexpected restoration index size/type"
            records = json.load(bundle.extractfile(member))
        assert isinstance(records,list)
        # Exclude historical projects and save metadata; only this baseline can cover a reference.
        baseline = [row["path"] for row in records if isinstance(row,dict) and str(row.get("path","")).startswith("baseline23/")]
        assert len(baseline) == 23379, "Frozen Gen23 index record count differs from restore evidence"
        self.index = index_paths(json.dumps(baseline))
        return {"index_asset": name, "sha256": INDEX_SHA256, "index_compressed_bytes": archive.stat().st_size, "all_archive_records":len(records), "baseline_records":len(baseline), "indexed_paths": len(self.index), "large_archives_downloaded": False}

    def references(self):
        references = {}
        dynamic = set()
        for name in subprocess.check_output(["git", "ls-files", "-z", "--", *SOURCE_PATHS], cwd=ROOT).decode().split("\0"):
            if not name or Path(name).suffix not in {".godot", ".cfg", ".gd", ".tscn", ".gdshader", ".gdshaderinc"}:
                continue
            for value in re.findall(r'''res://([^\s"'\)]+)''', (ROOT/name).read_text()):
                if value.endswith("/") or re.search(r"[%{}*]", value):
                    dynamic.add(value)
                    continue
                references.setdefault(value, []).append(name)
        rows = [{"path": path, "source_files": sorted(set(sources)), "coverage": "checkout" if (ROOT/path).is_file() else "release-index" if path in self.index else "UNVERIFIED" if not self.index else "MISSING"} for path, sources in sorted(references.items())]
        (self.output/"resource-references.json").write_text(json.dumps({"static": rows, "dynamic_unverified": sorted(dynamic)}, indent=2))
        missing = [r["path"] for r in rows if r["coverage"] in {"MISSING", "UNVERIFIED"}]
        if missing:
            if not self.index:
                raise Unverified(f"{len(missing)} of {len(rows)} static references require the unavailable restoration index; see resource-references.json")
            raise RuntimeError(f"{len(missing)} static references absent from checkout and Release index: {missing[:12]}")
        return {"static_references": len(rows), "dynamic_unverified": len(dynamic), "scope": "file coverage only, not engine import"}

    def python_syntax(self):
        paths = sorted(WORKBENCH.rglob("*.py"))
        paths = [p for p in paths if not set(p.parts) & {"node_modules", ".local", ".venv"}]
        for path in paths:
            ast.parse(path.read_text(), filename=str(path.relative_to(ROOT)))
        return {"files": len(paths), "method": "ast.parse, no imports or bytecode files"}

    def infrastructure_tests(self):
        output = self.command([sys.executable, "-B", "-m", "unittest", "discover", "-s", "tools", "-p", "test_*.py", "-v"], "infrastructure-tests")
        match = re.search(r"Ran (\d+) tests?", output)
        assert match and int(match[1]) > 0, "No infrastructure guard tests executed"
        return {"tests": int(match[1]), "scope": "infrastructure only; no model, engine, network or saved world"}

    def python_tests(self):
        output = self.command([sys.executable, "-B", "-m", "unittest", "discover", "-s", "tests", "-p", "test_*.py", "-v"], "python-bridge-tests", cwd=WORKBENCH)
        match = re.search(r"Ran (\d+) tests?", output)
        assert match and int(match[1]) > 0, "No Python tests executed"
        # Only the existing pure observation tests: no external integration suites.
        pure = self.command([sys.executable, "-B", "-m", "unittest", "test_formal_economy.ObservationTests", "test_wwo_current.MissingSourceTests", "-v"], "python-observation-tests", cwd=WORKBENCH/"external")
        match_pure = re.search(r"Ran (\d+) tests?", pure)
        assert match_pure and int(match_pure[1]) > 0
        return {"bridge_tests": int(match[1]), "pure_observation_tests": int(match_pure[1]), "external_Godot_integration": "UNVERIFIED; intentionally not collected", "skips": 0}

    def node_tests(self):
        output = self.command(["npm", "test"], "node-tests", cwd=WORKBENCH)
        counts = {key: int(value) for key,value in re.findall(r"(?:# |ℹ )?(tests|pass|fail|skipped|cancelled|todo) (\d+)", output)}
        assert counts.get("tests", 0) > 0, "No Node tests executed"
        assert counts.get("fail") == 0 and counts.get("pass",0) > 0
        return counts

    def verified_archive(self, name):
        asset = self.assets[name]
        expected = (asset.get("digest") or "").removeprefix("sha256:")
        if asset.get("digest"):
            assert asset["digest"].startswith("sha256:"), f"Unsupported digest algorithm: {name}"
        if name == "01-source23.tar.gz":
            if expected:
                assert expected == SOURCE_SHA256, "Release source digest differs from archived promotion evidence"
            expected = SOURCE_SHA256
        if not re.fullmatch(r"[a-fA-F0-9]{64}", expected):
            for metadata_name, path in self.downloaded.items():
                if re.search(r"sha256|checksums|manifest", metadata_name, re.I):
                    match = re.search(r"(?m)^([a-fA-F0-9]{64})\s+\*?(?:\./)?" + re.escape(name) + r"\s*$", path.read_text())
                    if match:
                        expected = match[1].lower()
                        break
        if not re.fullmatch(r"[a-fA-F0-9]{64}", expected):
            raise Unverified(f"No authoritative SHA256 for {name}; refusing archive download")
        path = self.download(name)
        assert sha256(path) == expected.lower(), f"SHA256 mismatch: {name}"
        return path

    def godot_import(self):
        if not self.release or any(row["status"] != "PASS" for row in self.rows):
            raise Unverified("Source provenance, Release inventory, restoration index and static references must pass before any large download")
        archives = ["01-source23.tar.gz"] + sorted(name for name in self.assets if re.fullmatch(r"02-resources23-.+\.tar\.gz", name))
        assert len(archives) > 1
        total = sum(self.assets[name]["size"] for name in archives)
        if shutil.disk_usage(self.scratch).free < total + 2*1024**3:
            raise RuntimeError(f"Insufficient disk for {total} compressed bytes plus import reserve")
        stage = self.scratch/"restored"
        stage.mkdir()
        # Every archive's SHA is checked before any extraction/use. Never select 03-saves.
        verified = [(name, self.verified_archive(name)) for name in archives]
        for name, archive in verified:
            extract_tar(archive, stage)
            archive.unlink()
        projects = list(stage.rglob("project.godot"))
        assert len(projects) == 1, f"Expected one restored project, found {len(projects)}; inspect actual archive layout"
        project = projects[0].parent
        for directory in ("assets", "data", "shared"):
            assert (project/directory).is_dir(), f"Resource volume layout did not restore {directory}"
        overlay = []
        if self.mode == 'grain-followup':
            for relative in subprocess.check_output(['git','ls-files','-z','--',*SOURCE_PATHS],cwd=ROOT).decode().split('\0'):
                if relative:
                    (project/relative).parent.mkdir(parents=True,exist_ok=True)
                    shutil.copy2(ROOT/relative,project/relative)
        else:
            for relative in subprocess.check_output(["git", "ls-files", "-z", "--", *SOURCE_PATHS], cwd=ROOT).decode().split("\0"):
                if relative:
                    old = sha256(project/relative) if (project/relative).is_file() else None
                    new = sha256(ROOT/relative)
                    if old != new:
                        overlay.append({"path":relative,"baseline_sha256":old,"candidate_sha256":new})
                    (project/relative).parent.mkdir(parents=True,exist_ok=True)
                    shutil.copy2(ROOT/relative,project/relative)
            manifest = {"candidate_sha": self.metadata['sha'], "base_release":RELEASE, "overlay":overlay,
                        "files":{p:sha256(project/p) for p in subprocess.check_output(['git','ls-files','-z','--',*SOURCE_PATHS],cwd=ROOT).decode().split('\0') if p and not p.startswith('.godot/')}}
            (project/'cloud_candidate.json').write_text(json.dumps(manifest))
            (self.output/'candidate-overlay.json').write_text(json.dumps({k:v for k,v in manifest.items() if k!='files'},indent=2))
        # Remove all restored engine caches for an actual clean import. Keep the verified archives immutable.
        if (project/'.godot').exists(): shutil.rmtree(project/'.godot')
        engine = self.install_godot()
        env = {key: str(self.scratch/f"xdg-{kind}") for key,kind in [("XDG_DATA_HOME","data"),("XDG_CONFIG_HOME","config"),("XDG_CACHE_HOME","cache")]}
        for value in env.values():
            Path(value).mkdir()
        version = self.command([str(engine), "--headless", "--version"], "godot-version", env=env).strip()
        assert version.startswith("4.6.3.stable.official."), f"Wrong Godot version: {version}"
        self.project,self.engine,self.engine_env = project,engine,env
        imported = self.command([str(engine), "--headless", "--editor", "--path", str(project), "--import"], "godot-import", timeout=900, env=env)
        assert not re.search(r"(?m)(?:SCRIPT ERROR:|ERROR:|Parse Error:)", imported), "Godot import logged errors; inspect godot-import.log"
        # Engine boots and loads the actual main scene without instantiating gameplay.
        # No WorldState, GameClock, save loading, player commands or time advancement.
        probe = project/"cloud_load_probe.gd"
        assert not probe.exists()
        probe.write_text('extends SceneTree\nfunc _initialize() -> void:\n\tvar scene = load("res://merchant/main.tscn")\n\tif not scene is PackedScene:\n\t\tpush_error("Main scene could not load")\n\t\tquit(1)\n\t\treturn\n\tprint("ECONOMY_CLOUD_SCENE_LOAD_PASS")\n\tquit(0)\n')
        loaded = self.command([str(engine), "--headless", "--path", str(project), "--script", str(probe)], "godot-scene-load", timeout=60, env=env)
        assert "ECONOMY_CLOUD_SCENE_LOAD_PASS" in loaded and not re.search(r"SCRIPT ERROR:|ERROR:", loaded)
        return {"engine": version, "archives": archives, "compressed_bytes": total, "import": "PASS", "no_cache_import":True,"candidate_overlay":overlay, "main_scene_resource_load": "PASS", "saved_world": "NOT_READ"}

    def round2_godot(self, mode, timeout=300):
        if not hasattr(self,'project'): raise Unverified('Godot restore/import prerequisite failed')
        destination=self.output/(mode+'.json')
        script='merchant/run_global_market.gd' if mode=='benchmark50' else 'merchant/round2_check.gd'
        arguments=[str(self.engine),'--headless','--path',str(self.project),'--script',str(self.project/script),'--',mode,str(destination)]
        output=self.command(arguments,mode,timeout=timeout,env=self.engine_env)
        assert not re.search(r'SCRIPT ERROR:|ERROR:|Assertion failed',output),f'{mode} logged engine errors'
        assert destination.is_file(),f'{mode} did not produce evidence'
        result=json.loads(destination.read_text())
        if mode=='benchmark50':
            compact=[]
            for run in result['runs']:
                assert (run['regions'],run['goods'],run['edges'])==(50,16,120)
                marks=[]
                for mark in run['marks']:
                    marks.append({'day':mark['day'],'markets':{region:{good:values[good] for good in ['wheat','coal','steel']} for region,values in mark['values'].items() if region in ['country_fra','united_states_1900','german_empire','british_isles_1900']}})
                compact.append({**{k:v for k,v in run.items() if k!='marks'},'marks':marks})
            result={'status':'PASS','scope':result['summary']['scope'],'runs':compact}
            destination.write_text(json.dumps(result))
        else:
            assert result.get('status')=='PASS',str(result)
        return result

    def round2_reasons(self):
        if not hasattr(self,'project'): raise Unverified('Godot restore/import prerequisite failed')
        path=self.project/'scripts/world/global_commodity_reference.gd'
        current=path.read_bytes()
        try:
            raw=self.command(['gh','api',f'repos/{REPOSITORY}/contents/scripts/world/global_commodity_reference.gd?ref=16e26896c68ccb788265dd5d7bc5f96bcf4b2dde'],'round2-reference-source',credentials=True)
            path.write_bytes(base64.b64decode(json.loads(raw)['content']))
            result=self.round2_godot('coupled-reasons',240)
            result['replay_scope']='IMMUTABLE_ROUND2_REFERENCE_AND_SAME_NATIVE_RULES_WITH_CURRENT_DECISION_FIELDS; FRESH_DAY24_NOT_PLAYER_SAVE'
            return result
        finally:
            path.write_bytes(current)

    def round2_person(self):
        if not hasattr(self,'project'): raise Unverified('Godot restore/import prerequisite failed')
        destination=self.output/'person.json'
        env={**self.engine_env,'WWO_GEN23_REPO_PATH':str(self.project),'WWO_GEN23_COMMIT':self.metadata['sha'],'WWO_GODOT_BIN':str(self.engine)}
        self.command([sys.executable,'-B','tools/round2_person_check.py',str(destination)],'person',timeout=180,env=env)
        result=json.loads(destination.read_text())
        assert result['status']=='PASS'
        return result

    def install_godot(self):
        # Official fixed-version release and its published checksum, never a fallback.
        repo = "godotengine/godot-builds"
        metadata = json.loads(self.command(["gh", "api", f"repos/{repo}/releases/tags/4.6.3-stable"], "godot-official-api", credentials=True, timeout=45))
        (self.output/"godot-official-api.log").unlink()
        assets = {item["name"]:item for item in metadata["assets"]}
        name = "Godot_v4.6.3-stable_linux.x86_64.zip"
        assert name in assets and "SHA512-SUMS.txt" in assets
        files = {}
        for selected in ("SHA512-SUMS.txt", name):
            path = self.scratch/selected
            with path.open("wb") as stream:
                result = subprocess.run(["gh", "api", f"repos/{repo}/releases/assets/{assets[selected]['id']}", "-H", "Accept: application/octet-stream"], stdout=stream, stderr=subprocess.PIPE, timeout=180)
            assert result.returncode == 0, f"Official Godot download failed: {selected}"
            assert path.stat().st_size == assets[selected]["size"]
            files[selected] = path
        match = re.search(r"(?m)^([a-fA-F0-9]{128})\s+\*?"+re.escape(name)+r"\s*$", files["SHA512-SUMS.txt"].read_text())
        assert match, "Official Godot SHA512 entry missing"
        digest = hashlib.sha512(files[name].read_bytes()).hexdigest()
        assert digest == match[1].lower(), "Godot artifact checksum mismatch"
        with zipfile.ZipFile(files[name]) as archive:
            members = archive.namelist()
            assert members == [name.removesuffix(".zip")], "Unexpected Godot archive layout"
            archive.extractall(self.scratch)
        engine = self.scratch/name.removesuffix(".zip")
        engine.chmod(0o755)
        return engine

    def finish(self):
        usage = resource.getrusage(resource.RUSAGE_CHILDREN)
        status = "PASS" if self.rows and all(row["status"] == "PASS" for row in self.rows) else "FAILED"
        limits = ["Protected original saves not read or advanced; historical comparison input differs from fresh test world.","Headless layout is not mobile GPU performance or human playability; integrated feedback may remain partial."] if self.mode=='round2-full' else ["Gen23 mechanisms, macro simulations, deliveries, old PRIVATE compatibility and gameplay not validated by quick or scene loading."]
        if self.mode=='grain-followup':
            limits=['Only finite grain/wheat phases executed; no annual scenarios, steel, UI, person bridge or full regression.', 'Native kg and finite macro replacement block are development assumptions, not representative national statistics.', 'Both worlds adopt real received indices; only the declared French wheat supply event differs. Neutral100 and opposite-arm indices are detached calculations through the unchanged quote function.', 'Known Artifact quota: no upload/retry/deletion. stale_base configuration persistence remains unresolved unless independently confirmed.']
        result = {**self.metadata, "status": status, "checks": self.rows, "elapsed_seconds": round(time.monotonic()-self.started,3), "resources": {"child_user_cpu_seconds": usage.ru_utime, "child_system_cpu_seconds": usage.ru_stime, "max_child_rss_kib": usage.ru_maxrss, "scope": "Linux child-process rusage, not billing or total runner peak", "final_free_disk_bytes": shutil.disk_usage(self.scratch).free}, "unverified": limits}
        (self.output/"report.json").write_text(json.dumps(result, indent=2, ensure_ascii=False))
        lines = [f"# WWO Economy Cloud Check — {status}", "", f"Repository: `{REPOSITORY}` · ref: `{result['ref']}`", f"SHA: `{result['sha']}` · mode: `{self.mode}`", f"Workflow: {result['workflow']}", f"Run: {result['run_url'] or 'LOCAL ONLY — no GitHub run URL'}", f"Runner: {platform.platform()} · Python {platform.python_version()}", "", "| Check | Result | Seconds |", "|---|---|---:|"]
        lines += [f"| {row['check']} | {row['status']} | {row['seconds']} |" for row in self.rows]
        lines += ["", f"Elapsed: {result['elapsed_seconds']}s. Child CPU: {usage.ru_utime+usage.ru_stime:.2f}s; maximum child RSS: {usage.ru_maxrss} KiB (not total runner memory/billing).", "", "Details and key errors:"]
        for row in self.rows:
            limit=110000 if self.mode in {'round2-full','grain-followup'} else 3000
            lines.append(f"- **{row['status']} {row['check']}**: {json.dumps(row['detail'], ensure_ascii=False)[:limit]}")
        lines += ["", *limits, "No automatic follow-up run. Never upload protected saves, full archives or runtime caches."]
        (self.output/"summary.md").write_text("\n".join(lines)+"\n")
        if self.mode in {'round2-full','grain-followup'}:
            print('::notice title=WWO round2::'+json.dumps({'check':'runtime-resources','status':status,'detail':{'elapsed_seconds':result['elapsed_seconds'],'resources':result['resources'],'python':platform.python_version(),'runner':platform.platform()}}),flush=True)
        self.temp.cleanup()
        return 0 if status == "PASS" else 1

    def run(self):
        self.check("HEAD and Gen23 source provenance", self.source)
        if self.mode != "grain-followup":
            self.check("Infrastructure safety guards", self.infrastructure_tests)
        self.check("Release inventory and RESTORE.md (small metadata only)", self.release_inventory)
        self.check("Known restoration file index", self.restore_index)
        self.check("Static project resource references", self.references)
        if self.mode == "quick":
            self.check("Node/npm versions", lambda: self.command(["node", "--version"], "node-version").strip()+" / npm "+self.command(["npm", "--version"], "npm-version").strip())
            self.check("npm ci (unchanged lockfile)", lambda: self.command(["npm", "ci", "--no-audit", "--no-fund", "--cache", str(self.scratch/"npm-cache")], "npm-ci", cwd=WORKBENCH, timeout=240)[-2000:])
            self.check("TypeScript and production build", lambda: self.command(["npm", "run", "build"], "build", cwd=WORKBENCH, timeout=180)[-3000:])
            self.check("Existing Node.js tests", self.node_tests)
            self.check("Python syntax without execution", self.python_syntax)
            self.check("Existing bridge and pure economy observation tests", self.python_tests)
        else:
            self.check("Verified resource restore, Godot import and bounded scene load", self.godot_import)
        if self.mode=='grain-followup':
            self.check('grain-followup',lambda:self.round2_godot('grain-followup',480))
        if self.mode=='round2-full':
            self.check('365-day global scenarios',lambda:self.round2_godot('benchmark50',300))
            for mode in ['coupled-fresh','industry','trade','ui']:
                self.check(mode,lambda mode=mode:self.round2_godot(mode,480))
            self.check('Gen23 person native chain',self.round2_person)
            self.check('Workbench production build',lambda:self.command(['npm','ci','--no-audit','--no-fund'], 'round2-npm-ci',cwd=WORKBENCH,timeout=180)+self.command(['npm','run','build'],'round2-build',cwd=WORKBENCH,timeout=180))
        self.check("Tracked source and lockfile unchanged", lambda: self.command(["git", "diff", "HEAD", "--exit-code", "--", *SOURCE_PATHS, str(WORKBENCH.relative_to(ROOT))], "final-tracked-diff") or "Unchanged")
        return self.finish()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=["quick", "godot-import", "round2-full", "grain-followup"], default="quick")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    return Check(args.mode, args.output).run()


if __name__ == "__main__":
    sys.exit(main())
