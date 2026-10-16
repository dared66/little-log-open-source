"""Phone detection accepts the current devicectl schema, without contacting a phone."""
import json
from pathlib import Path
import unittest
from unittest.mock import patch

import ios_phone_dev


class PhoneDetectionTest(unittest.TestCase):
    def check(self, devices):
        def list_devices(*command, **kwargs):
            Path(command[-1]).write_text(json.dumps({'result': {'devices': devices}}))
        with patch.object(ios_phone_dev, 'run', side_effect=list_devices):
            return ios_phone_dev.phone_connected('test-phone')

    def device(self, udid='test-phone', pairing='paired', boot='booted'):
        return {'hardwareProperties': {'udid': udid},
                'connectionProperties': {'pairingState': pairing},
                'deviceProperties': {'bootState': boot}}

    def test_current_schema_finds_paired_booted_phone(self):
        self.assertTrue(self.check([self.device()]))

    def test_other_unpaired_or_shutdown_phone_is_not_ready(self):
        for device in [self.device(udid='other'), self.device(pairing='unpaired'),
                       self.device(boot='shutdown')]:
            self.assertFalse(self.check([device]))

    def test_missing_or_incomplete_listing_is_not_ready(self):
        self.assertFalse(self.check([]))
        self.assertFalse(self.check([{}]))


if __name__ == '__main__':
    unittest.main()
