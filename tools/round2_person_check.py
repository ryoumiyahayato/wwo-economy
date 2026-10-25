"""One actual Gen23 native personal chain, through the new workbench adapter."""
from copy import deepcopy
import json
from pathlib import Path
import sys
import threading
import urllib.request
import urllib.error
import importlib.util

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'experiments/algorithm-workbench/external'))
import gen23_economy


def main(destination):
    spec=importlib.util.spec_from_file_location('native_bridge',ROOT/'experiments/algorithm-workbench/bridge/server.py')
    bridge=importlib.util.module_from_spec(spec);spec.loader.exec_module(bridge)
    providers=bridge.load_adapters(str(ROOT/'experiments/algorithm-workbench/external/gen23_economy.py'))
    provider=providers[gen23_economy.ID]
    scenario=deepcopy(provider.metadata['defaultScenario'])
    scenario['params']['stepMinutes']=1440
    server=bridge.BridgeServer(('127.0.0.1',0),providers,ROOT/'.local/algorithm-workbench/dist')
    thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
    url=f'http://127.0.0.1:{server.server_port}'
    def post(path,body):
        request=urllib.request.Request(url+path,data=json.dumps(body).encode(),headers={'Content-Type':'application/json'})
        try:
            with urllib.request.urlopen(request,timeout=60) as response:return json.load(response)
        except urllib.error.HTTPError as error:
            raise RuntimeError(f'Native bridge HTTP {error.code}: {error.read().decode()}') from error
    created=post('/api/v1/sessions',{'adapterId':gen23_economy.ID,'scenario':scenario})
    session_id=created['sessionId']
    native=server.sessions[session_id]['session']
    class Client:
        @property
        def state(self):return native.state
        @property
        def observed(self):return native.observed
        def command(self,request):
            return post(f'/api/v1/sessions/{session_id}/command',{'expectedTick':native.tick,'command':request})
        def step(self):
            return post(f'/api/v1/sessions/{session_id}/step',{'expectedTick':native.tick})
        def close(self):
            post(f'/api/v1/sessions/{session_id}/close',{})
    session=Client()
    evidence=[]
    def record(label,receipt=None):
        state=session.state
        p=state['personal']
        evidence.append({'label':label,'person':state['playerId'],'minute':state['minute'],
            'cash':p['cash'],'reserved':p['reserved'],'inventory':p['inventory'],
            'travel':p.get('travel'),'employment':p.get('employment'),'receipt':receipt,
            'orders':p.get('orders',[]),'changes':session.observed})
    def command(key,kind,**payload):
        result=session.command({'id':'round2:'+key,'op':'livelihood','parameters':{'kind':kind,'payload':payload}})
        record(kind,result['receipt'])
        assert result['receipt']['accepted'],result['receipt']
        return result
    try:
        record('initial')
        session.step();record('received-local-information')
        command('apply','apply',job_id='job:development_workshop')
        command('work','work',hours=2)
        before_income=sum(session.state['personal'].get('income_by_currency',{}).values())
        for _ in range(4):session.step()
        record('actual-wage-paid')
        assert sum(session.state['personal']['income_by_currency'].values())>before_income
        offer=next(o for o in session.state['personal']['offers'] if o['good']=='soap' and o['quantity']>0)
        payload=dict(quote_id=offer['quote_id'],seller=offer['seller'],seller_site=offer['seller_site'],good='soap',quantity=1,max_price=offer['price'],denomination=offer['denomination'],need_category='household')
        command('buy','buy',**payload)
        before=deepcopy(session.state)
        command('buy','buy',**payload)
        assert session.state==before,'Idempotent native action replay changed the world'
        command('away','travel',destination_place_id='place:lyon')
        for _ in range(6):
            session.step()
            cargo=[s for o in session.state['personal']['orders'] for s in o['shipments'] if s['stage']=='AWAITING_RECIPIENT']
            if cargo:break
        assert cargo,'Original cargo did not reach custody'
        command('return','travel',destination_place_id='place:paris')
        session.step()
        command('collect','collect',shipment_id=cargo[0]['id'])
        record('delivered-and-owned')
        assert session.state['personal']['inventory'].get('soap',0)>0
        command('consume','consume',commodity_id='native:soap',quantity=1,need_category='household',source='manual')
        assert any(r['kind']=='native_consume' and r.get('source')=='manual' for r in session.state['living'])
        result={'status':'PASS','transport':'ACTUAL_LOOPBACK_WORKBENCH_HTTP_BRIDGE_TO_NATIVE_GODOT','adapter':provider.metadata['id'],'candidate_sha':provider.metadata['sourceRef'],
            'evidence':evidence,'payments':[r for r in session.state['ledger']['transactions'] if r['from_account_id'] in [a['account_id'] for a in session.state['personal']['accounts']] or r['to_account_id'] in [a['account_id'] for a in session.state['personal']['accounts']]],
            'boundary':'UI gets research observation separately; personal commands still use original permissions and received offers'}
        Path(destination).write_text(json.dumps(result,ensure_ascii=False,indent=2))
    finally:
        session.close()
        server.shutdown();server.server_close();thread.join(timeout=3)


if __name__=='__main__':
    main(sys.argv[1])
