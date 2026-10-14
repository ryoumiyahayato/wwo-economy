import os
from pathlib import Path
import unittest
from unittest.mock import patch

import wwo_quantity


@unittest.skipUnless(os.environ.get("WWO_REPO_PATH"), "requires a separate WWO checkout")
class ExternalQuantityTests(unittest.TestCase):
    def test_real_external_calls_progress_without_mutating_source_or_fixture(self):
        provider = wwo_quantity.QuantityProvider()
        paths = [provider.root / "economy_quantity_lab/economy.py", provider.root / "economy_quantity_lab/fixture.json"]
        before = [p.read_bytes() for p in paths]
        self.assertFalse(provider.root.is_relative_to(wwo_quantity.SANDBOX_ROOT))
        session = provider.create(provider.metadata["defaultScenario"])
        self.assertEqual(session.snapshot()["tick"], 0)
        for expected_tick in (1, 2, 3):
            snapshot = session.step()
            self.assertEqual(snapshot["tick"], expected_tick)
            self.assertTrue(all(v == 0 for v in snapshot["invariants"].values()))
        self.assertGreater(snapshot["metrics"]["fulfilled"], 0)
        self.assertNotIn("buyerCash", snapshot["metrics"])
        self.assertEqual(before, [p.read_bytes() for p in paths])

    def test_model_inside_sandbox_is_rejected(self):
        with patch.dict(os.environ, {"WWO_REPO_PATH": str(wwo_quantity.SANDBOX_ROOT)}):
            with self.assertRaisesRegex(ValueError, "outside"):
                wwo_quantity.load_model()


if __name__ == "__main__":
    unittest.main()
