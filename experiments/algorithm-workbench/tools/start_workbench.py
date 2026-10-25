"""Local launcher: validates external checkouts, then runs the loopback bridge."""
import argparse
import importlib.util
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]


def run(args, **kwargs):
    return subprocess.run([str(a) for a in args], check=True, **kwargs)


def executable(value):
    result = shutil.which(value)
    if not result:
        raise ValueError(f"Executable not found: {value}")
    return str(Path(result).resolve())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--military-repo', required=True, type=Path)
    parser.add_argument('--economy-repo', required=True, type=Path)
    parser.add_argument('--godot', default='godot')
    parser.add_argument('--adapter', type=Path, default=ROOT / 'external/wwo_current.py')
    parser.add_argument('--port', type=int, default=8787)
    parser.add_argument('--check-only', action='store_true')
    parser.add_argument('--skip-install', action='store_true', help='Reuse an existing npm ci installation')
    args = parser.parse_args()
    if sys.version_info < (3, 12):
        raise ValueError('Python 3.12 or newer is required')
    if not 1024 <= args.port <= 65535:
        raise ValueError('Port must be 1024..65535')
    godot, node, npm = executable(args.godot), executable('node'), executable('npm')
    executable('git')
    version = subprocess.check_output([node, '--version'], text=True).strip()
    match = re.fullmatch(r'v(\d+)\.(\d+)\.(\d+)', version)
    if not match or (int(match[1]), int(match[2])) < (22, 12):
        raise ValueError(f'Node >=22.12 required; found {version}')
    for path in [args.military_repo, args.economy_repo]:
        if not path.is_dir():
            raise ValueError(f'External checkout does not exist: {path}')
    if not args.adapter.is_file():
        raise ValueError(f'Adapter entry does not exist: {args.adapter}')
    os.environ.update(WWO_MILITARY_REPO_PATH=str(args.military_repo.resolve()),
                      WWO_ECONOMY_REPO_PATH=str(args.economy_repo.resolve()),
                      WWO_FORMAL_REPO_PATH=str(args.economy_repo.resolve()),
                      WWO_GODOT_BIN=godot, SANDBOX_ADAPTER_PATH=str(args.adapter.resolve()),
                      PYTHONUTF8='1', PYTHONDONTWRITEBYTECODE='1')
    for variable, folder in [('XDG_DATA_HOME','data'), ('XDG_CONFIG_HOME','config'), ('XDG_CACHE_HOME','cache')]:
        target = REPO / '.local/algorithm-workbench/godot' / folder
        target.mkdir(parents=True, exist_ok=True)
        os.environ[variable] = str(target)
    spec = importlib.util.spec_from_file_location('workbench_bridge', ROOT / 'bridge/server.py')
    bridge = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(bridge)
    adapters = bridge.load_adapters(str(args.adapter.resolve()))
    unavailable = []
    for provider in adapters.values():
        metadata = provider.metadata
        print(f'{metadata["id"]}: {metadata.get("sourceRef", metadata["version"])}', flush=True)
        if metadata.get('unavailableReason'):
            unavailable.append(f'{metadata["id"]}: {metadata["unavailableReason"]}')
    if unavailable:
        raise ValueError('\n'.join(unavailable) + '\nNo checkout or source file was changed. Use compatible separate checkouts or an explicitly updated adapter.')
    print(f'Compatibility checks passed. Python {sys.version.split()[0]}, Node {version}, Godot {subprocess.check_output([godot, "--version"], text=True).strip()}', flush=True)
    if args.check_only:
        return
    if not args.skip_install:
        run([npm, 'ci'], cwd=ROOT)
    run([npm, 'run', 'build'], cwd=ROOT)
    # Godot regenerates import/class caches and may add .uid/.import metadata.
    # It does not edit domain source or automatically commit generated files.
    run([godot, '--headless', '--editor', '--path', args.economy_repo.resolve(), '--import'])
    print(f'Open http://127.0.0.1:{args.port} ; Ctrl+C stops the bridge and its sessions.', flush=True)
    try:
        run([sys.executable, '-B', ROOT / 'bridge/server.py', '--port', args.port], cwd=ROOT)
    except KeyboardInterrupt:
        pass


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as exc:
        print(f'Startup stopped: {exc}', file=sys.stderr)
        sys.exit(1)
