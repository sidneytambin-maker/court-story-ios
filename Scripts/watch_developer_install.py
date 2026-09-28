import argparse
import asyncio
import io
import json
from pathlib import Path
import plistlib
import zipfile

from verify_macho_seals import check_bundle

from pymobiledevice3.lockdown import TcpLockdownClient, create_using_usbmux
from pymobiledevice3.pair_records import create_pairing_records_cache_folder
from pymobiledevice3.service_connection import ServiceConnection
from pymobiledevice3.services.companion import CompanionProxyService
from pymobiledevice3.services.installation_proxy import InstallationProxyService
from pymobiledevice3.services.syslog import SyslogService


class WatchClient(TcpLockdownClient):
    async def create_service_connection(self, port):
        forwarded = await self.companion.start_forwarding_service_port(
            port, options={"GizmoUDID": self.watch_identifier, "PreferWifi": True}
        )
        return await ServiceConnection.create_using_usbmux(
            self.phone.identifier, forwarded, connection_type="USB"
        )


async def connect(repo):
    metadata = json.loads((repo / "work/signing-assets/watch/bundle.json").read_text(encoding="utf-8-sig"))
    phone = await create_using_usbmux()
    companion = CompanionProxyService(phone)
    port = await companion.start_forwarding_service_port(
        62078, options={"GizmoUDID": metadata["udid"], "PreferWifi": True}
    )
    service = await ServiceConnection.create_using_usbmux(phone.identifier, port, connection_type="USB")
    watch = WatchClient(
        service, phone.host_id, "127.0.0.1", pair_record=None,
        pairing_records_cache_folder=create_pairing_records_cache_folder(),
        port=62078, keep_alive=False, identifier=metadata["udid"],
    )
    watch.phone = phone
    watch.companion = companion
    watch.watch_identifier = metadata["udid"]
    # TcpLockdownClient overwrites identifier with hostname; isolate each device's trust cache.
    watch.identifier = metadata["udid"]
    await watch.get_value()
    watch.all_values.setdefault("WiFiAddress", "")
    # Validate saved trust before asking the device to approve a new pairing.
    if not await asyncio.wait_for(watch.validate_pairing(), 20):
        await asyncio.wait_for(watch.pair(timeout=10), 20)
        if not await asyncio.wait_for(watch.validate_pairing(), 20):
            raise RuntimeError("Watch pairing could not be validated")
    return watch, metadata


def watch_package(ipa):
    output = io.BytesIO()
    with zipfile.ZipFile(ipa) as source, zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as target:
        infos = [name for name in source.namelist() if "/Watch/" in name and name.endswith(".app/Info.plist")]
        if len(infos) != 1:
            raise ValueError("Expected exactly one Watch companion")
        prefix = infos[0].removesuffix("Info.plist")
        report = check_bundle(source, prefix)
        if report["failures"]:
            raise ValueError("Watch signature content checks failed: " + "; ".join(report["failures"]))
        app_name = prefix.rstrip("/").rsplit("/", 1)[1]
        for entry in source.infolist():
            if entry.filename.startswith(prefix):
                content = source.read(entry)
                entry.filename = "Payload/" + app_name + "/" + entry.filename[len(prefix):]
                target.writestr(entry, content)
    return output.getvalue()


def developer_stream(payload):
    # The conduit consumes stored ZIP local records followed by the central-directory marker.
    # Protocol reference: danielpaulus/go-ios, ios/zipconduit (MIT).
    with zipfile.ZipFile(io.BytesIO(payload)) as package:
        entries = {item.filename: package.read(item) for item in package.infolist()}
    for name in list(entries):
        parts = name.rstrip("/").split("/")
        for depth in range(1, len(parts)):
            entries.setdefault("/".join(parts[:depth]) + "/", b"")
    metadata = plistlib.dumps({
        "StandardDirectoryPerms": 16877, "StandardFilePerms": -32348,
        "RecordCount": len(entries) + 2,
        "TotalUncompressedBytes": sum(map(len, entries.values())), "Version": 2,
    })
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", zipfile.ZIP_STORED) as stream:
        records = [("META-INF/", b""), ("META-INF/com.apple.ZipMetadata.plist", metadata)]
        records.extend(sorted(entries.items()))
        for name, content in records:
            info = zipfile.ZipInfo(name)
            info.extra = bytes.fromhex("55540D0007F3A2EC60F6A2EC60F3A2EC6075780B000104F50100000414000000")
            stream.writestr(info, content)
        end = stream.start_dir
    return output.getvalue()[:end] + b"PK\x01\x02"


async def run(args):
    watch, metadata = await connect(args.repo)

    def emit(value):
        line = json.dumps(value, default=str) if not isinstance(value, str) else value
        for private in (metadata["udid"], metadata["bundle_id"]):
            line = line.replace(private, "[Watch]")
        print(line, flush=True)

    if args.mode == "log":
        async with SyslogService(watch) as service:
            emit("Watch log connected")
            async with asyncio.timeout(args.seconds):
                async for raw in service.watch():
                    line = raw.decode("utf-8", "replace") if isinstance(raw, bytes) else str(raw)
                    if any(term in line.lower() for term in ("tennistracker", "installd", "installation_proxy", "amfid", "installcoordination")):
                        emit(line)
        return

    if args.mode == "status":
        async with InstallationProxyService(watch) as installer:
            apps = await installer.get_apps(application_type="Any")
            found = [a for key, a in apps.items() if key == metadata["bundle_id"]]
            emit({"watch_application_registered": bool(found), "app": [
                {key: a.get(key) for key in ("CFBundleDisplayName", "CFBundleVersion", "ApplicationType", "ProfileValidated", "IsPlaceholder")}
                for a in found
            ]})
        return

    payload = watch_package(args.ipa)
    if args.mode == "install":
        service = await watch.start_lockdown_service("com.apple.streaming_zip_conduit")
        try:
            await service.send_plist({
                "InstallTransferredDirectory": 1, "UserInitiatedTransfer": 0,
                "MediaSubdir": "PublicStaging/TennisTrackerWatch-developer.ipa",
                "InstallOptionsDictionary": {
                    "InstallDeltaTypeKey": "InstallDeltaTypeSparseIPAFiles",
                    "DisableDeltaTransfer": 1, "IsUserInitiated": 1,
                    "PreferWifi": 1, "PackageType": "Developer",
                    "AllowInstallLocalProvisioned": True,
                },
            })
            data = developer_stream(payload)
            emit({"developer_stream_bytes": len(data)})
            await service.sendall(data)
            while True:
                reply = await service.recv_plist()
                emit(reply)
                progress = (reply or {}).get("InstallProgressDict", {})
                if not reply or reply.get("Error") or progress.get("Error"):
                    raise RuntimeError("Developer streaming install failed; see response above")
                if reply.get("Status") == "DataComplete":
                    emit("Developer streaming installation completed")
                    break
        finally:
            await service.close()
        return


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("status", "log", "install"))
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--ipa", type=Path)
    parser.add_argument("--seconds", type=int, default=120)
    args = parser.parse_args()
    if args.mode == "install" and args.ipa is None:
        parser.error("--ipa is required for installation")

    async def bounded():
        try:
            async with asyncio.timeout(args.seconds + 30):
                await run(args)
        except TimeoutError:
            if args.mode != "log":
                raise SystemExit("Device operation timed out before completion")
            print("Log capture completed", flush=True)

    asyncio.run(bounded())
