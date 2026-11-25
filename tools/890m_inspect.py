#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
"""Offline, bounded VFCT/AtomBIOS/EDID inspection. No GPU/device access.

Layout references and supported revisions: docs/890M-TRACE.md, step 01.
Unknown tables/extension blocks are recorded, never executed.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys


class ParseError(ValueError):
    pass


def require(ok, message):
    if not ok:
        raise ParseError(message)


def region(data, offset, size, label):
    require(offset >= 0 and size >= 0 and offset + size <= len(data),
            f"{label}: truncated/out-of-bounds at {offset:#x}, length {size}")
    return data[offset:offset + size]


def u16(data, offset):
    return int.from_bytes(region(data, offset, 2, "u16"), "little")


def u32(data, offset):
    return int.from_bytes(region(data, offset, 4, "u32"), "little")


def digest(data):
    return hashlib.sha256(data).hexdigest()


def vfct_images(data):
    require(region(data, 0, 4, "VFCT signature") == b"VFCT", "not a VFCT table")
    length = u32(data, 4)
    require(length == len(data) and length >= 76, "VFCT declared length mismatch")
    require(sum(data) % 256 == 0, "VFCT ACPI checksum mismatch")
    offset, lib_offset = u32(data, 52), u32(data, 56)
    require(76 <= offset < length, "VFCT VBIOS offset invalid")
    require(lib_offset == 0 or offset < lib_offset <= length, "VFCT Lib1 offset invalid")
    end = lib_offset or length
    images = []
    while offset < end:
        header = region(data[:end], offset, 28, "VFCT image header")
        bus, device, function, vendor, product, ssvid, ssid, revision, size = struct.unpack(
            "<IIIHHHHII", header)
        require(bus <= 255 and device <= 31 and function <= 7, "VFCT invalid PCI BDF")
        offset += 28
        image = region(data[:end], offset, size, "VFCT image")
        images.append({"bus": bus, "device": device, "function": function,
                       "vendor": vendor, "product": product, "ssvid": ssvid,
                       "ssid": ssid, "revision": revision, "offset": offset,
                       "length": size, "sha256": digest(image), "image": image})
        offset += size
    return images


def select_vfct(images, vendor, product, bdf=None, subsystem=None):
    matches = [i for i in images if i["length"] and
               (i["vendor"], i["product"]) == (vendor, product)]
    if subsystem:
        matches = [i for i in matches if (i["ssvid"], i["ssid"]) == subsystem]
    if bdf:
        matches = [i for i in matches if (i["bus"], i["device"], i["function"]) == bdf]
    require(len(matches) == 1, f"VFCT selection requires exactly one match, found {len(matches)}")
    return matches[0]


def atom_bios(data):
    require(region(data, 0, 2, "ROM signature") == b"\x55\xaa", "invalid ROM signature")
    size = region(data, 2, 1, "ROM size")[0] * 512
    require(size >= 512, "zero ROM image size")
    image = region(data, 0, size, "ROM image")
    require(sum(image) % 256 == 0, "ROM checksum mismatch")

    def table(offset, label):
        require(offset != 0, f"{label}: missing table")
        header = region(image, offset, 4, label)
        length, fmt, rev = struct.unpack("<HBB", header)
        require(length >= 4, f"{label}: invalid table size")
        return region(image, offset, length, label), fmt, rev

    header_offset = u16(image, 0x48)
    header, _, _ = table(header_offset, "ATOM header")
    require(len(header) >= 34 and header[4:8] == b"ATOM", "unsupported ATOM header")
    master_offset = u16(header, 32)
    master, fmt, rev = table(master_offset, "master data")
    require(fmt == 2 and (len(master) - 4) % 2 == 0, "unsupported master data layout")
    tables, raw = [], {}
    for index in range((len(master) - 4) // 2):
        offset = u16(master, 4 + index * 2)
        if not offset:
            continue
        body, fmt, rev = table(offset, f"data table {index}")
        tables.append({"index": index, "offset": offset, "length": len(body),
                       "format": fmt, "content": rev})
        raw[index] = (body, fmt, rev)
    paths = []
    if 22 in raw:
        body, fmt, rev = raw[22]
        require(fmt == 1 and rev in (4, 5), "unsupported displayobjectinfo revision")
        count = region(body, 6, 1, "display path count")[0]
        region(body, 8, count * 16, "display paths")
        for index in range(count):
            p = body[8 + index * 16:24 + index * 16]
            obj, record, encoder = u16(p, 0), u16(p, 2), u16(p, 4)
            kind = {0x13: "DisplayPort", 0x14: "eDP", 0x17: "USB-C",
                    0x0c: "HDMI", 0x0e: "LVDS"}.get(obj & 255, "unknown")
            if (obj >> 12) & 7 != 3:
                kind = "unknown"
            records = []
            if record:
                require(8 + count * 16 <= record < len(body), "display record offset invalid")
                cursor = record
                while cursor < len(body):
                    typ, length = region(body, cursor, 2, "display record header")
                    if typ in (0, 255):
                        break
                    require(length >= 2, "invalid display record length")
                    payload = region(body, cursor, length, "display record")
                    item = {"type": typ, "length": length}
                    if typ in (1, 2):
                        require(length >= 4, "short I2C/HPD record")
                        item["data"] = list(payload[2:4])
                    records.append(item)
                    cursor += length
                else:
                    raise ParseError("unterminated display record chain")
            paths.append({"index": index, "object_id": obj, "connector": kind,
                          "encoder_id": encoder, "device_tag": u16(p, 12), "records": records})
    firmware = None
    if 4 in raw:
        body, fmt, rev = raw[4]
        if fmt == 3 and rev == 4:
            firmware = {"revision": u32(body, 4), "boot_sclk_khz": u32(body, 8) * 10,
                        "boot_mclk_khz": u32(body, 12) * 10, "capabilities": u32(body, 16)}
    return {"image_length": size, "input_length": len(data), "sha256": digest(data),
            "checksum_valid": True, "tables": tables, "firmwareinfo": firmware,
            "display_paths": paths,
            "ip_discovery": "not inspected; acquire separately, not required for AtomBIOS parsing"}


def timing(clock, ha, hb, hf, hs, va, vb, vf, vs, hp, vp, source, preferred, interlaced=False):
    require(clock > 0 and ha > 0 and va > 0 and hb >= hf + hs and vb >= vf + vs
            and hs > 0 and vs > 0, f"{source}: invalid timing geometry")
    return {"source": source, "preferred": preferred, "pixel_clock_khz": clock,
            "hactive": ha, "hblank": hb, "hfront": hf, "hsync": hs,
            "hback": hb - hf - hs, "htotal": ha + hb, "hsync_positive": hp,
            "vactive": va, "vblank": vb, "vfront": vf, "vsync": vs,
            "vback": vb - vf - vs, "vtotal": va + vb, "vsync_positive": vp,
            "interlaced": interlaced,
            "refresh_hz": clock * 1000 / ((ha + hb) * (va + vb))}


def edid_dtd(d, preferred):
    require(len(d) == 18, "short EDID DTD")
    clock = u16(d, 0) * 10
    if not clock:
        return None
    require(d[17] & 0x18 == 0x18, "unsupported non-digital-separate-sync DTD")
    require(not d[17] & 0x80, "interlaced DTD is outside this tool's scope")
    return timing(clock, d[2] | (d[4] >> 4) << 8, d[3] | (d[4] & 15) << 8,
                  d[8] | (d[11] >> 6) << 8, d[9] | ((d[11] >> 4) & 3) << 8,
                  d[5] | (d[7] >> 4) << 8, d[6] | (d[7] & 15) << 8,
                  (d[10] >> 4) | ((d[11] >> 2) & 3) << 4,
                  (d[10] & 15) | (d[11] & 3) << 4,
                  bool(d[17] & 2), bool(d[17] & 4), "EDID DTD", preferred)


def displayid_type7(d):
    require(len(d) == 20, "short DisplayID type-7 timing")
    require(not d[3] & 0x10, "interlaced DisplayID timing is outside scope")
    return timing(int.from_bytes(d[:3], "little") + 1,
                  u16(d, 4) + 1, u16(d, 6) + 1, (u16(d, 8) & 0x7fff) + 1,
                  u16(d, 10) + 1, u16(d, 12) + 1, u16(d, 14) + 1,
                  (u16(d, 16) & 0x7fff) + 1, u16(d, 18) + 1,
                  bool(u16(d, 8) & 0x8000), bool(u16(d, 16) & 0x8000),
                  "DisplayID type-7", bool(d[3] & 0x80))


def edid(data):
    require(region(data, 0, 8, "EDID header") == b"\x00\xff\xff\xff\xff\xff\xff\x00",
            "invalid EDID signature")
    base = region(data, 0, 128, "EDID base")
    require(base[18:20] == b"\x01\x04", "only EDID 1.4 supported")
    require(len(data) == (base[126] + 1) * 128, "EDID extension count/length mismatch")
    for offset in range(0, len(data), 128):
        require(sum(data[offset:offset + 128]) % 256 == 0,
                f"EDID checksum mismatch in block {offset // 128}")
    manufacturer = int.from_bytes(base[8:10], "big")
    name, modes, extensions = None, [], []
    for offset in range(54, 126, 18):
        d = base[offset:offset + 18]
        t = edid_dtd(d, offset == 54 and bool(base[24] & 2))
        if t:
            modes.append(t)
        elif d[:5] == b"\x00\x00\x00\xfc\x00":
            name = d[5:18].decode("ascii", errors="replace").strip(" \n\x00")
    for offset in range(128, len(data), 128):
        ext = data[offset:offset + 128]
        entry = {"block": offset // 128, "tag": ext[0], "decoded": False}
        if ext[0] == 0x70:
            require(ext[1] == 0x20, "only DisplayID 2.0 supported")
            end = 5 + ext[2]
            require(end < 127, "DisplayID payload overruns EDID block")
            require(sum(ext[1:end + 1]) % 256 == 0, "DisplayID section checksum mismatch")
            require(ext[4] == 0, "DisplayID continuation sections not supported")
            cursor, blocks = 5, []
            while cursor < end:
                # DisplayID permits zero padding after the final data block.
                if not any(ext[cursor:end]):
                    break
                tag, revision, length = region(ext[:end], cursor, 3, "DisplayID data block header")
                payload = region(ext[:end], cursor + 3, length, "DisplayID data block")
                blocks.append({"tag": tag, "revision": revision, "length": length,
                               "decoded": tag == 0x22})
                if tag == 0x22:
                    require(revision == 0 and length > 0 and length % 20 == 0,
                            "unsupported DisplayID type-7 block layout")
                    modes.extend(displayid_type7(payload[i:i + 20]) for i in range(0, length, 20))
                cursor += 3 + length
            entry.update(decoded=True, data_blocks=blocks)
        extensions.append(entry)
    return {"sha256": digest(data), "length": len(data), "checksum_valid": True,
            "manufacturer": "".join(chr(64 + ((manufacturer >> s) & 31)) for s in (10, 5, 0)),
            "product": u16(base, 10), "name": name, "timings": modes, "extensions": extensions}


def pci_bdf(value):
    try:
        fields = value.split(":")
        require(len(fields) in (2, 3), "invalid BDF")
        if len(fields) == 3:
            require(int(fields[0], 16) == 0, "VFCT has no PCI domain field; only domain 0000 supported")
        bus, devfn = fields[-2:]
        device, function = devfn.split(".")
        bdf = (int(bus, 16), int(device, 16), int(function, 16))
        require(0 <= bdf[0] <= 255 and 0 <= bdf[1] <= 31 and 0 <= bdf[2] <= 7, "invalid BDF")
        return bdf
    except (ValueError, ParseError) as error:
        raise argparse.ArgumentTypeError(str(error)) from error


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--vfct", type=Path)
    p.add_argument("--vbios", type=Path)
    p.add_argument("--edid", type=Path)
    p.add_argument("--vendor", type=lambda s: int(s, 16), default=0x1002)
    p.add_argument("--device", type=lambda s: int(s, 16), default=0x150e)
    p.add_argument("--bdf", type=pci_bdf)
    p.add_argument("--extract-vbios", type=Path)
    args = p.parse_args()
    if not any((args.vfct, args.vbios, args.edid)):
        p.error("provide --vfct, --vbios and/or --edid")
    if args.extract_vbios and not args.vfct:
        p.error("--extract-vbios requires --vfct")
    result = {"schema": 1, "tool": "890m_inspect", "offline": True}
    try:
        selected = None
        if args.vfct:
            data = args.vfct.read_bytes()
            images = vfct_images(data)
            selected = select_vfct(images, args.vendor, args.device, args.bdf)
            result["vfct"] = {"sha256": digest(data), "images": [
                {k: v for k, v in i.items() if k != "image"} for i in images],
                "selected_offset": selected["offset"]}
            result["atom"] = atom_bios(selected["image"])
        if args.vbios:
            data = args.vbios.read_bytes()
            result["atom"] = atom_bios(data)
            if selected:
                require(selected["image"] == data, "VFCT image differs from debugfs VBIOS")
                result["vfct"]["matches_vbios"] = True
        if args.edid:
            result["edid"] = edid(args.edid.read_bytes())
        # Extract only after every validation succeeds. Never overwrite a fixture.
        if args.extract_vbios:
            with args.extract_vbios.open("xb") as f:
                f.write(selected["image"])
    except (OSError, ParseError) as error:
        print(f"890m_inspect: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
