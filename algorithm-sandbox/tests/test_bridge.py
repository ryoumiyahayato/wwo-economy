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

    def test_external_origin_is_not_permitted_to_invoke_private_code(self):
        with self.assertRaises(urllib.error.HTTPError) as error:self.post('/api/v1/sessions',{},origin='https://external.example')
        self.assertEqual(error.exception.code,403)


if __name__=='__main__':unittest.main()
