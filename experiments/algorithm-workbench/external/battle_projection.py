"""Pure, versioned observation mapping. No simulation or damage calculations."""
from copy import deepcopy
import math

SCHEMA = 'wwo-battle/frame/v1'


def project_research(source, tick, previous=None):
    entities = []
    for uid, item in source['units'].items():
        raw = item['raw']; xy = item['xy']; spatial = raw.get('spatial', {})
        if not spatial: continue  # Sparse/off-map area units have no local coordinate claim.
        entity = {'id': uid, 'label': uid, 'kind': 'unit', 'team': raw['side'], 'x': xy[0], 'y': xy[1],
                  'state': raw.get('state', raw.get('action','UNKNOWN')), 'personnel': raw.get('effective'), 'ammo': raw.get('ammunition'),
                  'ammoSpent': raw.get('ammo_spent'), 'casualties': raw.get('casualties'),
                  'sourcePath': '/units/' + uid, 'raw': deepcopy(item)}
        if isinstance(spatial.get('bearing_degrees'), (int,float)):
            entity['heading'] = spatial['bearing_degrees']; entity['headingBasis'] = 'source bearing_degrees'
        entities.append(entity)
    for pid, raw in source['people'].items():
        uid = raw['unit_ref']; xy = raw['xy']
        entities.append({'id':pid, 'label':pid, 'kind':'person', 'team':source['units'].get(uid,{}).get('raw',{}).get('side','unknown'),
                         'x':xy[0], 'y':xy[1], 'state':raw.get('life_state','UNKNOWN'), 'health':raw.get('health'),
                         'unitId':uid, 'weapon':deepcopy(raw.get('weapon',{})), 'sourcePath':'/people/'+pid, 'raw':deepcopy(raw)})
    old = {e['id']:e for e in (previous or {}).get('entities',[])}
    for e in entities:
        before = old.get(e['id'])
        if before and (before['x'] != e['x'] or before['y'] != e['y']):
            e['movement'] = {'from':[before['x'],before['y']], 'to':[e['x'],e['y']], 'fromTick':previous['tick'], 'toTick':tick}
            # Movement direction is observable; it is NOT a weapon/body orientation.
            e['motionHeading'] = math.degrees(math.atan2(e['y']-before['y'],e['x']-before['x']))
    events = []
    for raw in source['events']['records']:
        events.append({'id':str(raw['event_id']), 'tick':tick, 'kind':raw['kind'],
                       'effectiveTime':raw['effective_time'], 'actorId':raw.get('actor_ref'),
                       'targetId':raw.get('subject_ref'), 'causeIds':raw.get('cause_refs',[]), 'raw':deepcopy(raw)})
    return {'schemaVersion':SCHEMA, 'tick':tick, 'time':source['time'], 'view':'DEBUG_TRUTH',
            'sourceCommit':'04ab3cc9ffb2233fa0ab5290e0ec0a952f229630', 'entities':entities, 'events':events,
            'dropped':source['events']['dropped'], 'nodes':deepcopy(source['nodes']),
            'scope':source['scope'], 'unlocatedUnits':[uid for uid,item in source['units'].items() if not item['raw'].get('spatial')], 'gaps':['逐发射击/弹道/逐发命中事件未接入；原模型按区间结算',
            '未上报身体朝向时只画移动方向，静止朝向未知', '远方稀疏组未展开；此研究真值不进入人物知识'],
            'source':deepcopy(source)}


def visible_entities(person):
    body = person['personal']; entities = []
    if isinstance(body.get('xy'),list) and len(body['xy'])==2:
        entities.append({'id':person['person_id'],'label':person['person_id'],'granularity':'person',
                         'x':body['xy'][0],'y':body['xy'][1],'state':body.get('life_state',body.get('state','UNKNOWN'))})
    latest = {}
    for claim in person.get('reports',{}).get('entries',[]):
        xy = claim.get('claimed_value',{}).get('xy'); uid = claim.get('subject_ref')
        if not isinstance(xy,list) or len(xy)!=2 or uid == person['person_id'] or claim.get('reliability',0)<=0: continue
        if uid not in latest or (claim['observed_at'],claim['received_at'])>(latest[uid]['observed_at'],latest[uid]['received_at']):latest[uid]=claim
    for uid,c in latest.items():
        v=c['claimed_value']
        entities.append({'id':uid,'label':uid,'granularity':'person' if c['subject_kind']=='person' else 'formation',
                         'x':v['xy'][0],'y':v['xy'][1], 'state':v.get('life_state',v.get('condition',v.get('state','OBSERVED'))),
                         'observedAt':c['observed_at'],'receivedAt':c['received_at'],'reportId':c['entry_id'], 'factKind':c['fact_kind']})
    return entities
