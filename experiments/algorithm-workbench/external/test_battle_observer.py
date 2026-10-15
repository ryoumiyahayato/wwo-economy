from copy import deepcopy
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest

import wwo_current as w
from battle_projection import visible_entities

class ProjectionTests(unittest.TestCase):
    def test_reports_preserve_observed_age_and_do_not_guess_team(self):
        p={'person_id':'squad','personal':{'xy':[0,0]},'reports':{'entries':[
            {'subject_ref':'enemy','subject_kind':'unit','fact_kind':'ground_contact','reliability':1,'entry_id':'r1','observed_at':5,'received_at':52,'claimed_value':{'xy':[.12,.08],'condition':'OBSERVED'}},
            {'subject_ref':'enemy','subject_kind':'unit','fact_kind':'ground_contact','reliability':1,'entry_id':'old','observed_at':0,'received_at':60,'claimed_value':{'xy':[.1,.1]}}]}}
        e=visible_entities(p)[1]
        self.assertEqual((e['x'],e['observedAt'],e['receivedAt'],e['reportId']),(.12,5,52,'r1'))
        self.assertNotIn('team',e)

@unittest.skipUnless(os.environ.get('WWO_MILITARY_REPO_PATH'),'requires pinned original Godot source')
class OriginalObserverTests(unittest.TestCase):
    def advance(self,s):
        for _ in range(200):
            r=s.step()
            if r.get('kind')!='pending':return r
        self.fail('pending did not finish')

    def test_original_damage_cause_snapshot_idempotence_and_no_source_mutation(self):
        provider=w.get_adapters()[w.OBSERVER_ID];s=provider.create(provider.metadata['defaultScenario'])
        try:
            before=s.snapshot();after=self.advance(s)
            self.assertEqual(s.snapshot(),s.snapshot())
            b=after['observations']['battle'];a=before['observations']['battle']
            self.assertEqual(len(b['entities']),10)
            self.assertEqual({e['team'] for e in b['entities']},{'blue','red'})
            self.assertEqual(len(b['unlocatedUnits']),2)
            event=next(e for e in b['events'] if e['kind']=='personal_injury' and e['actorId']=='squad')
            cause=next(e for e in b['events'] if e['id']==event['causeIds'][0])
            self.assertEqual(cause['kind'],'shared_fire_allocation')
            self.assertEqual(event['raw']['detail']['before_health'],a['source']['people']['squad']['health'])
            self.assertEqual(event['raw']['detail']['after_health'],b['source']['people']['squad']['health'])
            self.assertEqual(event['raw']['event_id'],event['id'])
            self.assertFalse(any(e['kind'] in ['shot','hit'] for e in b['events']))
        finally:s.close()

    def test_observer_read_and_diagnostic_switches_match_uninstrumented_original(self):
        root=w.source_path('military');spec=importlib.util.spec_from_file_location('source_client',root/w.SOURCES['military'][2]);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
        os.environ.update({k:v for k,v in w.runtime_environment().items() if k.startswith('XDG_')})
        with tempfile.TemporaryDirectory() as d:
            original=m.Connection(scene='A3',actor='squad',seed=71,session='sandbox_session',quota=31,root=root,godot='/usr/local/bin/godot',diagnostic=d)
            provider=w.get_adapters()[w.OBSERVER_ID];scene=deepcopy(provider.metadata['defaultScenario']);s=provider.create(scene)
            try:
                request={'id':'move','target':'node_unit_000','intent':'advance','node':'B','path':['AB']}
                original.send('intent',request);s.command(request)
                for _ in range(4):
                    original.send('advance',{'seconds':5});original.pump()
                    after=self.advance(s)
                    self.assertEqual(original.send('look')['person']['personal'],after['observations']['person']['personal'])
                    self.assertEqual(s.snapshot(),after)
                b=after['observations']['battle']
            finally:original.close();s.close()
            raw=json.loads(Path(d,'debug_truth.json').read_text())['formal']
            self.assertEqual(raw['units'],{id:v['raw'] for id,v in b['source']['units'].items()})
            self.assertEqual(raw['totals'],b['source']['totals'])
            self.assertEqual(raw['random_state'],b['source']['randomState'])

    def test_visible_page_fetch_keeps_all_retained_events_and_reports(self):
        scene=w.default_scenario('military');scene['maxTicks']=20
        s=w.MilitaryCalls(scene)
        try:
            for _ in range(4):
                r=self.advance(s)
            self.assertGreater(len(r['observations']['person']['events']['records']),20)
            self.assertEqual(r['observations']['person']['events']['adapter_next_before'],-1)
            self.assertEqual(s.snapshot(),s.snapshot())
        finally:s.close()

if __name__=='__main__':unittest.main()
