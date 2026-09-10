import importlib.util
from pathlib import Path
import json
import unittest
spec=importlib.util.spec_from_file_location('watch',Path(__file__).with_name('completion-watch.py'))
watch=importlib.util.module_from_spec(spec);spec.loader.exec_module(watch)
class Tests(unittest.TestCase):
    def test_counts_match_native_precedence_and_redact(self):
        snapshot={'rows':[{'title':'secret','id':'secret','unread':True} for _ in range(5)]+[
            {'busy':True,'unread':True}, {'lastTurn':{'failed':True},'unread':True},
            {'ask':{'id':'secret'},'busy':True}], 'sidebarSyncedAt':123,'token':'secret'}
        result=watch.counts(snapshot)
        self.assertEqual(result,{'doing':1,'done':5,'error':1,'decision':1,'sidebarFresh':True})
        self.assertNotIn('secret',json.dumps(result))
    def test_expired_mirror_recorded_separately(self):
        self.assertEqual(watch.counts({'rows':[]})['sidebarFresh'],False)
if __name__=='__main__':unittest.main()
