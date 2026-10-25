"""Provenance guards only; the engine call is mocked, never run locally."""
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'experiments/algorithm-workbench/external'))
import gen23_economy as adapter
import formal_economy


class Gen23Guards(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.root=Path(self.temp.name)
        self.sha='a'*40
        files={}
        for name in ['project.godot','scripts/world/economy_r1_slice.gd','scripts/world/global_commodity_reference.gd']:
            path=self.root/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_text('guard fixture only')
            files[name]=hashlib.sha256(path.read_bytes()).hexdigest()
        self.manifest={'candidate_sha':self.sha,'base_release':'economy-gen23-closeout-20261024','files':files}
        self.save()
        self.environment=patch.dict(os.environ,{'WWO_GEN23_REPO_PATH':str(self.root),'WWO_GEN23_COMMIT':self.sha,'WWO_GODOT_BIN':'mock-engine'})
        self.environment.start()
        self.engine=patch.object(adapter.subprocess,'check_output',return_value='4.6.3.stable.official.example\n')
        self.engine.start()

    def save(self):
        (self.root/'cloud_candidate.json').write_text(json.dumps(self.manifest))

    def tearDown(self):
        self.engine.stop();self.environment.stop();self.temp.cleanup()

    def test_exact_source_is_admitted_and_old_pin_is_retained(self):
        self.assertEqual(adapter.source(),(self.root,self.sha))
        self.assertEqual(formal_economy.COMMIT,'b5bfcdd870da5d2b54f8a27e2abbfb9d511c502d')

    def test_changed_source_is_rejected(self):
        (self.root/'project.godot').write_text('changed')
        with self.assertRaisesRegex(ValueError,'hash mismatch'):adapter.source()

    def test_other_candidate_sha_is_rejected(self):
        self.manifest['candidate_sha']='b'*40;self.save()
        with self.assertRaisesRegex(ValueError,'provenance mismatch'):adapter.source()

    def test_empty_manifest_is_rejected(self):
        self.manifest['files']={};self.save()
        with self.assertRaisesRegex(ValueError,'Incomplete'):adapter.source()

    def test_another_engine_version_is_rejected(self):
        with patch.object(adapter.subprocess,'check_output',return_value='4.5.stable.official.other'):
            with self.assertRaisesRegex(ValueError,'requires real Godot 4.6.3'):adapter.source()

    def test_missing_environment_is_unavailable_without_fallback(self):
        with patch.dict(os.environ,{},clear=True):
            provider=adapter.Provider()
            self.assertIn('no demo fallback',provider.metadata['unavailableReason'])


if __name__=='__main__':unittest.main()
