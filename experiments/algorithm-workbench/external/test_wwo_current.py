from copy import deepcopy
import os
from pathlib import Path
import unittest
from unittest.mock import patch

import wwo_current


def history(provider, scenario, ticks):
    session=provider.create(scenario)
    pending_count=0
    try:
        snapshots=[session.snapshot()]
        for _ in range(ticks):
            for _ in range(100):
                response=session.step()
                if response.get('kind')!='pending':break
                pending_count+=1
                assert session.snapshot()==snapshots[-1], 'PENDING changed committed observation'
            else:raise AssertionError('source still pending after bounded test')
            snapshots.append(response)
        return snapshots,pending_count
    finally:session.close()


class MissingSourceTests(unittest.TestCase):
    def test_unavailable_source_is_declared_and_has_no_demo_fallback(self):
        with patch.dict(os.environ,{},clear=True):
            provider=wwo_current.Provider('economy')
            self.assertIn('WWO_ECONOMY_REPO_PATH',provider.metadata['unavailableReason'])
            with self.assertRaisesRegex(ValueError,'不会回退 demo'):
                provider.create(provider.metadata['defaultScenario'])


@unittest.skipUnless(os.environ.get('WWO_ECONOMY_REPO_PATH'),'requires actual external economy source')
class CurrentEconomyTests(unittest.TestCase):
    def test_actual_day_steps_rerun_and_shortage_counterexample(self):
        provider=wwo_current.Provider('economy');scenario=provider.metadata['defaultScenario']
        first,_=history(provider,scenario,3);second,_=history(provider,scenario,3)
        self.assertEqual(first,second)
        self.assertGreater(first[3]['metrics']['fulfilled'],first[0]['metrics']['fulfilled'])
        self.assertEqual(first[3]['metrics']['cashTotal'],first[0]['metrics']['cashTotal'])
        self.assertTrue(all(v==0 for v in first[3]['invariants'].values()))
        self.assertTrue(all('lost' not in o and 'status' not in o for o in first[3]['orders']))
        bad=provider.metadata['scenarios'][1];self.assertEqual(bad['expectations'],scenario['expectations'])
        shortage,_=history(provider,bad,3)
        self.assertLess(shortage[3]['metrics']['fulfilled'],first[3]['metrics']['fulfilled'])
        self.assertGreater(shortage[3]['metrics']['unmet'],0)

    def test_missing_case_data_and_idealized_target_are_rejected(self):
        provider=wwo_current.Provider('economy');scenario=deepcopy(provider.metadata['defaultScenario'])
        scenario['initialConditions']={'case':{}}
        with self.assertRaisesRegex(RuntimeError,'KeyError'):provider.create(scenario)
        scenario=deepcopy(provider.metadata['defaultScenario']);scenario['dependencies']['funding']='normal'
        with self.assertRaisesRegex(ValueError,'不能理想化覆盖'):provider.create(scenario)


@unittest.skipUnless(os.environ.get('WWO_MILITARY_REPO_PATH'),'requires actual external Godot v5 source')
class CurrentMilitaryTests(unittest.TestCase):
    def test_original_movement_pending_rerun_and_no_command_counterexample(self):
        provider=wwo_current.Provider('military');scenario=provider.metadata['defaultScenario']
        first,pending=history(provider,scenario,2);second,_=history(provider,scenario,2)
        self.assertEqual(first,second);self.assertGreater(pending,0)
        self.assertEqual(first[1]['metrics']['elapsedSeconds'],scenario['params']['stepSeconds'])
        self.assertGreater(first[1]['entities'][0]['x'],first[0]['entities'][0]['x'])
        self.assertEqual(first[1]['entities'][0]['granularity'],'person')
        self.assertNotIn('ammo',first[1]['metrics']);self.assertNotIn('casualties',first[1]['metrics'])
        self.assertEqual(first[1]['observations']['person']['view'],'PERSON_VISIBLE')
        bad=provider.metadata['scenarios'][1];self.assertEqual(bad['expectations'],scenario['expectations'])
        stationary,_=history(provider,bad,1)
        self.assertEqual(stationary[1]['entities'][0]['x'],0)
        self.assertEqual(stationary[1]['metrics']['acceptedCommands'],0)

    def test_invalid_parameters_fail_before_moving_source_state(self):
        provider=wwo_current.Provider('military');scenario=deepcopy(provider.metadata['defaultScenario'])
        scenario['params']['quota']=2
        with self.assertRaisesRegex(RuntimeError,'0/1/7/31'):provider.create(scenario)


if __name__=='__main__':unittest.main()
