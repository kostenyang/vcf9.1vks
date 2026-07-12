import copy
import unittest

try:
    from airgap.airgap_tool import plan, validate
except ModuleNotFoundError:  # also support `cd airgap && python -m unittest`
    from airgap_tool import plan, validate


VALID = {
    "depot_fqdn": "depot.rtolab.local",
    "work_dir": "/srv/vks-airgap",
    "tcp_endpoints": [{"host": "depot.rtolab.local", "port": 443}],
    "bundles": [{
        "name": "vks-standard-packages",
        "source": "projects.packages.broadcom.com/vsphere/supervisor/vks-standard-packages/3.6.0/x:3.6.0",
    }],
}


class ValidationTests(unittest.TestCase):
    def test_valid_config(self):
        self.assertEqual([], validate(copy.deepcopy(VALID)))

    def test_rejects_credentials_at_any_depth(self):
        config = copy.deepcopy(VALID)
        config["registry"] = {"password": "do-not-store-this"}
        self.assertIn("credentials are forbidden", " ".join(validate(config)))

    def test_rejects_ip_as_depot_fqdn(self):
        config = copy.deepcopy(VALID)
        config["depot_fqdn"] = "192.0.2.10"
        self.assertIn("depot_fqdn", " ".join(validate(config)))

    def test_upload_plan_targets_depot(self):
        command = plan(copy.deepcopy(VALID), "upload")[0]
        self.assertIn("upload", command)
        self.assertIn("-t 'depot.rtolab.local'", command)
        self.assertIn("--work-dir '/srv/vks-airgap'", command)

    def test_download_plan_does_not_target_depot(self):
        command = plan(copy.deepcopy(VALID), "download")[0]
        self.assertNotIn(" -t ", command)


if __name__ == "__main__":
    unittest.main()
