"""Reject the simulator signing defect that prevents Google sign-in."""
import plistlib
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch

import ios_simulator_dev


class SimulatorKeychainSigningTest(unittest.TestCase):
    def verify(self, entitlements):
        payload = plistlib.dumps(entitlements)
        # A minimal arm64 executable with Xcode's simulated entitlement section.
        header = struct.pack('<8I', 0xfeedfacf, 0x100000c, 0, 2, 1, 152, 0, 0)
        segment = struct.pack('<II16sQQQQIIII', 0x19, 152, b'__TEXT', 0, 0, 0, 0, 0, 0, 1, 0)
        section = struct.pack('<16s16sQQIIIIIIII', b'__entitlements', b'__TEXT',
                              0, len(payload), 184, 0, 0, 0, 0, 0, 0, 0)
        with tempfile.TemporaryDirectory() as directory, patch.object(ios_simulator_dev, 'run'):
            app = Path(directory)
            (app / 'Runner').write_bytes(header + segment + section + payload)
            ios_simulator_dev.verify_keychain_signing(app)

    def test_signed_app_with_its_own_keychain_group_is_accepted(self):
        identity = 'TESTTEAM01.' + ios_simulator_dev.BUNDLE_ID
        self.verify({'application-identifier': identity,
                     'keychain-access-groups': [identity]})

    def test_missing_identity_or_group_is_rejected(self):
        identity = 'TESTTEAM01.' + ios_simulator_dev.BUNDLE_ID
        for entitlements in [{}, {'application-identifier': identity},
                             {'application-identifier': identity,
                              'keychain-access-groups': ['TESTTEAM01.other']},
                             {'application-identifier': 'TESTTEAM01.other',
                              'keychain-access-groups': ['TESTTEAM01.other']}]:
            with self.subTest(entitlements=entitlements), self.assertRaisesRegex(RuntimeError, 'Keychain'):
                self.verify(entitlements)

    def test_linker_signature_without_entitlements_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(ios_simulator_dev, 'run'), \
                self.assertRaisesRegex(RuntimeError, 'Keychain'):
            app = Path(directory)
            (app / 'Runner').write_bytes(struct.pack('<8I', 0xfeedfacf, 0x100000c, 0, 2, 0, 0, 0, 0))
            ios_simulator_dev.verify_keychain_signing(app)


if __name__ == '__main__':
    unittest.main()
