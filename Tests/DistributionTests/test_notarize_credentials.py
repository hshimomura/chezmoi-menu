import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[2] / "scripts" / "notarize-app.py"
SPEC = importlib.util.spec_from_file_location("notarize_app", SCRIPT)
NOTARY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(NOTARY)


class CredentialLoadingTests(unittest.TestCase):
    def test_only_asc_variables_are_loaded_without_executing_env(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            key = root / "test key.p8"
            key.write_text("unit-test-placeholder")
            marker = root / "must-not-exist"
            env = root / ".env"
            env.write_text(
                "export ASC_KEY_ID='EXAMPLEKEY1'\n"
                "ASC_ISSUER_ID=example-issuer # comment\n"
                f'ASC_KEY_FILEPATH="{key}"\n'
                f'UNRELATED=$(touch "{marker}")\n'
                "GH_TOKEN=not-an-asc-value\n"
            )
            with patch.dict(os.environ, {}, clear=True):
                values = NOTARY.credentials(env)
            self.assertEqual(set(values), NOTARY.NAMES)
            self.assertEqual(values["ASC_KEY_FILEPATH"], str(key))
            self.assertFalse(marker.exists())

    def test_file_overrides_stale_environment_values(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            key = root / "test.p8"
            key.write_text("unit-test-placeholder")
            env = root / ".env"
            env.write_text(f"ASC_KEY_ID=current\nASC_KEY_FILEPATH='{key}'\n")
            with patch.dict(os.environ, {"ASC_KEY_ID": "stale"}, clear=True):
                values = NOTARY.credentials(env)
            self.assertEqual(values["ASC_KEY_ID"], "current")
            self.assertNotIn("ASC_ISSUER_ID", values)

    def test_bad_configuration_does_not_echo_value(self):
        with tempfile.TemporaryDirectory() as directory:
            env = Path(directory) / ".env"
            env.write_text('ASC_KEY_ID="PRIVATE-EXAMPLE-VALUE\n')
            with patch.dict(os.environ, {}, clear=True):
                with self.assertRaises(RuntimeError) as error:
                    NOTARY.credentials(env)
            self.assertNotIn("PRIVATE-EXAMPLE-VALUE", str(error.exception))


if __name__ == "__main__":
    unittest.main()
