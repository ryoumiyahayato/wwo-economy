import importlib.util
import json
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('bridge_server', ROOT/'bridge/server.py')
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class BridgeTests(unittest.TestCase):
    def setUp(self):
        providers = bridge.load_adapters(str(ROOT/'bridge/example_adapter.py'))
        self.server = bridge.BridgeServer(('127.0.0.1',0), providers, ROOT/'dist')
        self.thread = threading.Thread(target=self.server.serve_forever,daemon=True)
        self.thread.start()
        self.url = f'http://127.0.0.1:{self.server.server_port}'
        self.metadata = next(iter(providers.values())).metadata

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

    def post(self,path,body,origin=None):
        headers={'Content-Type':'application/json'}
        if origin: headers['Origin']=origin
        request=urllib.request.Request(self.url+path,data=json.dumps(body).encode(),headers=headers)
        with urllib.request.urlopen(request) as r:return json.load(r)

    def test_actual_plugin_transition_and_duplicate_rejection(self):
        created=self.post('/api/v1/sessions',{'adapterId':self.metadata['id'],'scenario':self.metadata['defaultScenario']})
        session=created['sessionId'];self.assertEqual(created['snapshot']['tick'],0)
        result=self.post(f'/api/v1/sessions/{session}/step',{'expectedTick':0})
        self.assertEqual(result['snapshot']['metrics']['counter'],1)
        with self.assertRaises(urllib.error.HTTPError) as error:self.post(f'/api/v1/sessions/{session}/step',{'expectedTick':0})
        self.assertEqual(error.exception.code,409)
        result=self.post(f'/api/v1/sessions/{session}/step',{'expectedTick':1})
        self.assertEqual(result['snapshot']['metrics']['counter'],2)
        self.post(f'/api/v1/sessions/{session}/close',{})

    def test_unknown_adapter_has_no_fallback(self):
        with self.assertRaises(urllib.error.HTTPError) as error:self.post('/api/v1/sessions',{'adapterId':'not-connected','scenario':{}})
        self.assertEqual(error.exception.code,404)

    def test_failed_step_retains_last_snapshot_and_idempotent_close_allows_reset(self):
        created=self.post('/api/v1/sessions',{'adapterId':self.metadata['id'],'scenario':self.metadata['defaultScenario']})
        sid=created['sessionId']
        def fail():raise RuntimeError('original synthetic failure after call; must recreate')
        self.server.sessions[sid]['session'].step=fail
        with self.assertRaises(urllib.error.HTTPError) as error:self.post(f'/api/v1/sessions/{sid}/step',{'expectedTick':0})
        self.assertEqual(error.exception.code,400)
        self.assertNotIn(sid,self.server.sessions)
        self.assertEqual(created['snapshot']['tick'],0)
        self.assertTrue(self.post(f'/api/v1/sessions/{sid}/close',{})['closed'])
        reset=self.post('/api/v1/sessions',{'adapterId':self.metadata['id'],'scenario':self.metadata['defaultScenario']})
        self.assertEqual(reset['snapshot']['tick'],0)


    def test_pending_keeps_committed_tick_and_resumes_same_target(self):
        provider=self.server.adapters[self.metadata['id']]
        original_create=provider.create
        class PendingSession:
            def __init__(self,scenario):self.original=original_create(scenario);self.pending=True
            def snapshot(self):return self.original.snapshot()
            def step(self):
                if self.pending:
                    self.pending=False
                    return {'kind':'pending','committedTick':0,'reason':'original synthetic continuation fixture'}
                return self.original.step()
        provider.create=lambda scenario:PendingSession(scenario)
        created=self.post('/api/v1/sessions',{'adapterId':self.metadata['id'],'scenario':self.metadata['defaultScenario']})
        sid=created['sessionId']
        pending=self.post(f'/api/v1/sessions/{sid}/step',{'expectedTick':0})
        self.assertEqual(pending['pending']['committedTick'],0)
        self.assertNotIn('snapshot',pending)
        self.assertEqual(self.server.sessions[sid]['tick'],0)
        complete=self.post(f'/api/v1/sessions/{sid}/step',{'expectedTick':0})
        self.assertEqual(complete['snapshot']['tick'],1)

    def test_external_origin_is_not_permitted_to_invoke_private_code(self):
        with self.assertRaises(urllib.error.HTTPError) as error:self.post('/api/v1/sessions',{},origin='https://external.example')
        self.assertEqual(error.exception.code,403)


if __name__=='__main__':unittest.main()
