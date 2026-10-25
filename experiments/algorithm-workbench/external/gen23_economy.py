"""Gen23 candidate adapter. Old formal v1 source/version checks remain intact.

The overlay manifest binds this separate adapter to an exact candidate Git SHA
and every restored/overlaid source hash. No save or replacement economy is used.
"""
from copy import deepcopy
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

import formal_economy

ID = 'private.wwo.gen23-economy.v2'
DEPENDENCIES = {'supply':'finite','transport':'bounded','funding':'finite','path':'direct','resupply':'finite'}


def source():
    value = os.environ.get('WWO_GEN23_REPO_PATH')
    expected = os.environ.get('WWO_GEN23_COMMIT','')
    if not value or not re.fullmatch(r'[a-f0-9]{40}',expected):
        raise ValueError('Gen23 requires WWO_GEN23_REPO_PATH and exact WWO_GEN23_COMMIT; no demo fallback')
    root = Path(value).resolve(strict=True)
    manifest = json.loads((root/'cloud_candidate.json').read_text())
    if manifest['candidate_sha'] != expected or manifest['base_release'] != 'economy-gen23-closeout-20261024':
        raise ValueError('Gen23 candidate provenance mismatch')
    required = {'project.godot','scripts/world/economy_r1_slice.gd','scripts/world/global_commodity_reference.gd'}
    if not isinstance(manifest.get('files'),dict) or not required.issubset(manifest['files']):
        raise ValueError('Incomplete Gen23 candidate source manifest')
    for name,digest in manifest['files'].items():
        path = (root/name).resolve(strict=True)
        if not path.is_relative_to(root) or hashlib.sha256(path.read_bytes()).hexdigest()!=digest:
            raise ValueError(f'Gen23 source hash mismatch: {name}')
    engine = os.environ['WWO_GODOT_BIN']
    version = subprocess.check_output([engine,'--headless','--version'],text=True,stderr=subprocess.PIPE).strip()
    if not version.startswith('4.6.3.stable.official.'):
        raise ValueError(f'Gen23 requires real Godot 4.6.3: {version}')
    return root,expected


class Provider:
    def __init__(self):
        try:
            _,commit = source()
            unavailable = ''
        except Exception as error:
            commit = os.environ.get('WWO_GEN23_COMMIT','UNVERIFIED')
            unavailable = str(error)
        scenario = {'schemaVersion':'wwo-sandbox/scenario/v1','name':'Gen23 · isolated native person',
            'domain':'economy','adapterId':ID,'seed':23,'maxTicks':24,'boundary':'formal-native',
            'dependencies':deepcopy(DEPENDENCIES),'params':{'stepMinutes':720},
            'initialConditions':{'configuration':'EconomyDevelopmentConfig.formal_limited'},
            'expectations':{'rules':[],'observation':'Native development world, no archived player save; no guaranteed success'}}
        self.metadata = {'protocolVersion':'wwo-sandbox/adapter/v1','id':ID,'name':'PRIVATE · Gen23 native person v2',
            'domain':'economy','kind':'private','version':'gen23-native-v2+'+commit,'sourceRef':commit,
            'unavailableReason':unavailable,'supportsCommands':True,'lockedDependencies':deepcopy(DEPENDENCIES),
            'defaultScenario':scenario,'scenarios':[scenario],
            'parameters':[{'key':'stepMinutes','label':'原时钟分钟','min':60,'max':1440,'step':60}],
            'metrics':[{'key':'cash','label':'本人Ledger余额'},{'key':'inventory','label':'本人实物库存'}],
            'seedNote':'Gen23 exact candidate SHA; seed is an observation label, not a new RNG',
            'boundaries':[{'id':'formal-native','label':'Gen23原宿主','internal':'WorldState/GameClock/StockLots/Ledger/LivelihoodAction',
                'external':'Research truth is separate from legally received personal offers; finite development configuration, not historical evidence'}]}

    def create(self,scenario):
        root,commit = source()
        if scenario.get('dependencies') != DEPENDENCIES:
            raise ValueError('Gen23 dependencies remain owned by native Formal host')
        return formal_economy.Session(scenario,dict(os.environ),source_root=root,adapter_id=ID,source_commit=commit)


def get_adapters():
    provider = Provider()
    return {ID:provider}
