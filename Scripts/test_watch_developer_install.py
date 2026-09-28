import io
from pathlib import Path
import plistlib
import struct
from types import SimpleNamespace
import unittest
from unittest.mock import AsyncMock, patch
import zipfile

from watch_developer_install import connect, developer_stream


def local_records(data):
    records = []
    offset = 0
    while data[offset:offset + 4] == b"PK\x03\x04":
        fields = struct.unpack_from("<IHHHHHIIIHH", data, offset)
        _, _, flags, method, _, _, _, size, original, name_length, extra_length = fields
        if flags & 8 or method != 0 or size != original:
            raise AssertionError("Conduit requires stored records without data descriptors")
        name = data[offset + 30:offset + 30 + name_length].decode()
        start = offset + 30 + name_length + extra_length
        records.append((name, data[start:start + size]))
        offset = start + size
    if data[offset:] != b"PK\x01\x02":
        raise AssertionError("Conduit stream must end with only the central-directory marker")
    return records


class WatchDeveloperStreamTests(unittest.TestCase):
    def package(self):
        payload = io.BytesIO()
        with zipfile.ZipFile(payload, "w", zipfile.ZIP_DEFLATED) as archive:
            archive.writestr("Payload/Example.app/Info.plist", b"example plist")
            archive.writestr("Payload/Example.app/_CodeSignature/CodeResources", b"sealed resources")
            archive.writestr("Payload/Example.app/Example", bytes(range(256)))
        return payload.getvalue()

    def testMetadataPrecedesAppAndCountsAllRecords(self):
        records = local_records(developer_stream(self.package()))
        self.assertEqual(records[0][0], "META-INF/")
        self.assertEqual(records[1][0], "META-INF/com.apple.ZipMetadata.plist")
        metadata = plistlib.loads(records[1][1])
        self.assertEqual(metadata["RecordCount"], len(records))
        self.assertEqual(metadata["TotalUncompressedBytes"], sum(len(value) for _, value in records[2:]))

    def testTransferPreservesEverySignedByte(self):
        package = self.package()
        records = dict(local_records(developer_stream(package)))
        with zipfile.ZipFile(io.BytesIO(package)) as original:
            for name in original.namelist():
                self.assertEqual(original.read(name), records[name])

    def testMissingDirectoryEntriesAreCreatedBeforeChildren(self):
        names = [name for name, _ in local_records(developer_stream(self.package()))]
        for parent, child in (("Payload/", "Payload/Example.app/"),
                              ("Payload/Example.app/_CodeSignature/", "Payload/Example.app/_CodeSignature/CodeResources")):
            self.assertLess(names.index(parent), names.index(child))


class WatchPairingTests(unittest.IsolatedAsyncioTestCase):
    async def run_connection(self, results, pair_error=None):
        watch = SimpleNamespace(identifier="127.0.0.1", all_values={}, get_value=AsyncMock(),
            validate_pairing=AsyncMock(side_effect=results), pair=AsyncMock(side_effect=pair_error))
        self.watch = watch
        phone = SimpleNamespace(host_id="fixture-host", identifier="fixture-phone")
        companion = SimpleNamespace(start_forwarding_service_port=AsyncMock(return_value=12345))
        with patch.object(Path, "read_text", return_value='{"udid":"fixture-watch"}'), \
             patch("watch_developer_install.create_using_usbmux", AsyncMock(return_value=phone)), \
             patch("watch_developer_install.CompanionProxyService", return_value=companion), \
             patch("watch_developer_install.ServiceConnection.create_using_usbmux", AsyncMock()), \
             patch("watch_developer_install.create_pairing_records_cache_folder", return_value=Path(".")), \
             patch("watch_developer_install.WatchClient", return_value=watch):
            return await connect(Path("fixture"))

    async def testSavedPairingDoesNotRequestNewTrust(self):
        watch, _ = await self.run_connection([True])
        self.assertEqual(watch.identifier, "fixture-watch")
        watch.pair.assert_not_awaited()
        self.assertEqual(watch.validate_pairing.await_count, 1)

    async def testMissingPairingIsValidatedAfterDeviceApproval(self):
        watch, _ = await self.run_connection([False, True])
        watch.pair.assert_awaited_once_with(timeout=10)
        self.assertEqual(watch.validate_pairing.await_count, 2)

    async def testInvalidNewPairingStopsConnection(self):
        with self.assertRaisesRegex(RuntimeError, "could not be validated"):
            await self.run_connection([False, False])

    async def testPairingFailureIsNotIgnored(self):
        with self.assertRaisesRegex(RuntimeError, "Device approval pending"):
            await self.run_connection([False], RuntimeError("Device approval pending"))
        self.assertEqual(self.watch.validate_pairing.await_count, 1)


if __name__ == "__main__":
    unittest.main()
