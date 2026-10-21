import importlib.util
import json
import pathlib
import tempfile
import unittest
from unittest import mock

SPEC=importlib.util.spec_from_file_location("sign_candidate_r78",pathlib.Path(__file__).with_name("sign-candidate-r78.py"))
MODULE=importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)
SHA="432d73c562417538997c88f5b859391186c5561e"
RUN="39542066613"
STABLE={"app_key":"chatgpt-web","version":"0.7.11","build":"13"}
SIGNED={"status":"SIGNED","ok":True,"id":"a1111111-b222-c333-d444-e55555555555","channel":"candidate",
        "promoted":False,"source_sha":SHA,"run_id":RUN,"version":"0.7.15","build":"17",
        "bundle_id":"com.masakacj.chatgptweb","ipa_url":MODULE.BASE+"/ipa/a1111111-b222-c333-d444-e55555555555.ipa",
        "manifest_url":MODULE.BASE+"/manifest/a1111111-b222-c333-d444-e55555555555.plist"}
class SigningRetries(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory()
  self.addCleanup(self.temp.cleanup)
  self.patchers=[
   mock.patch.object(MODULE,"DIST",pathlib.Path(self.temp.name)),
   mock.patch.object(MODULE,"IPA",pathlib.Path(self.temp.name)/"candidate-unsigned.ipa"),
   mock.patch.object(MODULE,"RUN",RUN),mock.patch.object(MODULE,"SHA",SHA),
   mock.patch.object(MODULE,"REPO","masakacj/chatgpt-web"),
   mock.patch.object(MODULE,"TOKEN","not-real-signing-token"),
   mock.patch.object(MODULE.time,"sleep")]
  for p in self.patchers:p.start();self.addCleanup(p.stop)
  MODULE.IPA.write_bytes(b"x"*12000)
 def run_with(self,responses):
  calls=[]
  def fake(url,*,data=None,headers=None,timeout=25):
   calls.append(("POST" if data is not None else "GET",url))
   if not responses:raise AssertionError("unexpected HTTP")
   return responses.pop(0)
  with mock.patch.object(MODULE,"request",side_effect=fake):
   MODULE.main()
  return calls
 def test_already_signed_does_not_post_again(self):
  calls=self.run_with([(200,json.dumps(STABLE)),(200,json.dumps(SIGNED)),(200,json.dumps(STABLE))])
  self.assertFalse(any(method=="POST" for method,_ in calls))
  self.assertEqual(json.loads((MODULE.DIST/"candidate-sign-result.json").read_text())["id"],SIGNED["id"])
 def test_502_response_with_successful_server_commit_is_not_retried(self):
  calls=self.run_with([(200,json.dumps(STABLE)),(404,'{"status":"NOT_FOUND"}'),
                       (502,'Bad Gateway'),(200,json.dumps(SIGNED)),
                       (200,json.dumps(STABLE))])
  self.assertEqual(sum(m=="POST" for m,_ in calls),1)
 def test_unknown_status_never_starts_duplicate_upload(self):
  with mock.patch.object(MODULE,"request",side_effect=[
    (200,json.dumps(STABLE)),(0,"ConnectionResetError")]):
   with self.assertRaises(MODULE.SignFailure) as cm:MODULE.main()
   self.assertEqual(cm.exception.category,"SIGNING_STATUS_UNAVAILABLE")
 def test_auth_error_never_retries(self):
  calls=[]
  def fake(url,*,data=None,headers=None,timeout=25):
   calls.append(data is not None)
   return [(200,json.dumps(STABLE)),(404,'{"status":"NOT_FOUND"}'),
           (403,'{"error":"untrusted candidate signing workflow"}')][len(calls)-1]
  with mock.patch.object(MODULE,"request",side_effect=fake):
   with self.assertRaises(MODULE.SignFailure) as cm:MODULE.main()
   self.assertEqual(cm.exception.category,"SIGNING_AUTH_OR_POLICY")
  self.assertEqual(calls.count(True),1)
if __name__=="__main__":unittest.main()
