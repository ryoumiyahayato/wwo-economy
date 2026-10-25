"""One actual Gen23 native personal chain, through the new workbench adapter."""
from copy import deepcopy
import json
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'experiments/algorithm-workbench/external'))
import gen23_economy


def main(destination):
    provider=gen23_economy.Provider()
    scenario=deepcopy(provider.metadata['defaultScenario'])
    scenario['params']['stepMinutes']=1440
    session=provider.create(scenario)
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
        result={'status':'PASS','adapter':provider.metadata['id'],'candidate_sha':provider.metadata['sourceRef'],
            'evidence':evidence,'payments':[r for r in session.state['ledger']['transactions'] if r['from_account_id'] in [a['account_id'] for a in session.state['personal']['accounts']] or r['to_account_id'] in [a['account_id'] for a in session.state['personal']['accounts']]],
            'boundary':'UI gets research observation separately; personal commands still use original permissions and received offers'}
        Path(destination).write_text(json.dumps(result,ensure_ascii=False,indent=2))
    finally:
        session.close()


if __name__=='__main__':
    main(sys.argv[1])
