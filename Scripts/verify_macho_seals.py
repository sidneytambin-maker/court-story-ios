"""Check signed content hashes, independently of platform trust evaluation."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import struct
import zipfile


def slices(data):
    magic = data[:4]
    if magic in (b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"):
        count = struct.unpack_from(">I", data, 4)[0]
        wide = magic[-1] == 0xBF
        size = 32 if wide else 20
        for i in range(count):
            start, length = struct.unpack_from(">QQ" if wide else ">II", data, 8 + i * size + 8)
            yield data[start:start + length]
    else:
        yield data


def signature_blobs(data):
    if data[:4] not in (b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe"):
        raise ValueError("Unsupported Mach-O header")
    ncmds = struct.unpack_from("<I", data, 16)[0]
    cursor = 32 if data[0] == 0xCF else 28
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", data, cursor)
        if cmd == 0x1D:
            offset, length = struct.unpack_from("<II", data, cursor + 8)
            signature = data[offset:offset + length]
            magic, length, count = struct.unpack_from(">III", signature)
            if magic != 0xFADE0CC0:
                raise ValueError("Missing embedded signature SuperBlob")
            blobs = {}
            for i in range(count):
                slot, offset = struct.unpack_from(">II", signature, 12 + 8 * i)
                blob_length = struct.unpack_from(">I", signature, offset + 4)[0]
                blobs[slot] = signature[offset:offset + blob_length]
            return blobs
        if size < 8:
            raise ValueError("Malformed load command")
        cursor += size
    raise ValueError("Executable has no code signature")


def check_bundle(archive, prefix):
    info_data = archive.read(prefix + "Info.plist")
    info = plistlib.loads(info_data)
    resources_data = archive.read(prefix + "_CodeSignature/CodeResources")
    resources = plistlib.loads(resources_data)
    failures = []
    pages_checked = 0
    for arch, data in enumerate(slices(archive.read(prefix + info["CFBundleExecutable"]))):
        blobs = signature_blobs(data)
        if 5 not in blobs or 7 not in blobs:
            failures.append(f"slice {arch}: missing XML or DER entitlements")
        if 5 in blobs:
            entitlements = plistlib.loads(blobs[5][8:])
            app_id = entitlements.get("application-identifier", "")
            if not app_id.endswith("." + info["CFBundleIdentifier"]):
                failures.append(f"slice {arch}: executable entitlement does not match bundle")
        for slot, cd in blobs.items():
            if slot != 0 and not 0x1000 <= slot <= 0x1005:
                continue
            hash_offset, _, nspecial, ncode, limit = struct.unpack_from(">IIIII", cd, 16)
            hash_size, hash_type, _, page_bits = struct.unpack_from("BBBB", cd, 36)
            algorithm = {1: "sha1", 2: "sha256", 3: "sha256", 4: "sha384"}.get(hash_type)
            if algorithm is None:
                failures.append(f"slice {arch}: unsupported code hash algorithm")
                continue
            digest = lambda value: hashlib.new(algorithm, value).digest()[:hash_size]
            special = {1: info_data, 3: resources_data}
            special.update({key: blobs[key] for key in (2, 5, 7) if key in blobs})
            for key, value in special.items():
                expected = cd[hash_offset - key * hash_size:hash_offset - (key - 1) * hash_size]
                if key > nspecial or digest(value) != expected:
                    failures.append(f"slice {arch}: signed slot {key} hash mismatch")
            page_size = 1 << page_bits if page_bits else limit
            for page in range(ncode):
                content = data[page * page_size:min((page + 1) * page_size, limit)]
                expected = cd[hash_offset + page * hash_size:hash_offset + (page + 1) * hash_size]
                if digest(content) != expected:
                    failures.append(f"slice {arch}: executable page {page} hash mismatch")
                pages_checked += 1
    for name, entry in resources.get("files2", {}).items():
        if not isinstance(entry, dict):
            continue
        if "hash2" in entry:
            try:
                content = archive.read(prefix + name)
                if hashlib.sha256(content).digest() != entry["hash2"]:
                    failures.append(f"resource hash mismatch: {name}")
            except KeyError:
                if not entry.get("optional"):
                    failures.append(f"missing resource: {name}")
    return {"bundle": prefix, "code_pages_checked": pages_checked, "failures": failures}


def verify(ipa):
    with zipfile.ZipFile(ipa) as archive:
        prefixes = [name.removesuffix("Info.plist") for name in archive.namelist()
                    if name.endswith(".app/Info.plist")]
        return [check_bundle(archive, prefix) for prefix in prefixes]


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("ipa", type=Path)
    args = parser.parse_args()
    reports = verify(args.ipa)
    print(json.dumps(reports, indent=2))
    raise SystemExit(1 if not reports or any(r["failures"] for r in reports) else 0)
