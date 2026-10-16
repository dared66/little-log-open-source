import importlib.util
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).with_name('export_nara_to_little_log.py')
spec = importlib.util.spec_from_file_location('nara_export_script', SCRIPT)
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)

class FakeClient:
    def get_children(self):
        return {'a': {'name':'Lila'}, 'b': {'name':'Another baby'}}
    def get_data(self):
        return {'one': {'childKey':'a','type':'DIAPER'}, 'two': {'childKey':'b','type':'DIAPER'}}

class HistoryBridgeTest(unittest.TestCase):
    def test_child_filter_and_ambiguity(self):
        value=bridge.select_export(FakeClient(),'lila')
        self.assertEqual(list(value['tracks']),['one'])
        self.assertEqual(value['profile']['name'],'Lila')
        with self.assertRaises(ValueError): bridge.select_export(FakeClient(),'unknown')

    def test_read_only_client_and_no_preference_write(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder); (path/'scripts').mkdir(); (path/'scripts/nara_client.py').touch()
            def connected_client(**kwargs):
                self.assertNotIn('allow_writes', kwargs)
                self.assertEqual(kwargs['timezone_name'],'America/Los_Angeles')
                class Context:
                    def __enter__(self): return FakeClient()
                    def __exit__(self,*args): return False
                return Context()
            with patch.object(bridge,'PREFS',path/'no-preferences.json'):
                with patch.dict(sys.modules,{'nara_client':types.SimpleNamespace(connected_client=connected_client)}):
                    result=bridge.fetch('Lila',path,'America/Los_Angeles')
            self.assertEqual(list(result['tracks']),['one'])
            self.assertFalse((path/'no-preferences.json').exists())

if __name__=='__main__': unittest.main()
