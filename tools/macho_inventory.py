"""Minimal execution-free inventory for thin 64-bit Mach-O executables.

This is an original parser for reproducible evidence collection on non-macOS
hosts. It intentionally reports only directly decoded header, load-command, and
symbol-table facts. It does not validate code signatures or decompile code.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import struct
import uuid


LC_SEGMENT_64 = 0x19
LC_SYMTAB = 0x2
LC_LOAD_DYLIB = 0xC
LC_ID_DYLIB = 0xD
LC_LOAD_WEAK_DYLIB = 0x80000018
LC_REEXPORT_DYLIB = 0x8000001F
LC_LOAD_UPWARD_DYLIB = 0x80000023
LC_UUID = 0x1B
LC_CODE_SIGNATURE = 0x1D
LC_VERSION_MIN_MACOSX = 0x24
LC_MAIN = 0x80000028
LC_RPATH = 0x8000001C
LC_BUILD_VERSION = 0x32


CPU_TYPES = {
    0x01000007: "x86_64",
    0x0100000C: "arm64",
}
FILE_TYPES = {2: "executable", 6: "dylib", 8: "bundle"}
PLATFORMS = {1: "macOS", 2: "iOS", 3: "tvOS", 4: "watchOS", 6: "macCatalyst"}
DYLIB_COMMANDS = {
    LC_LOAD_DYLIB: "load",
    LC_LOAD_WEAK_DYLIB: "weak-load",
    LC_REEXPORT_DYLIB: "reexport",
    LC_LOAD_UPWARD_DYLIB: "upward-load",
    LC_ID_DYLIB: "identity",
}

SIGNATURE_MAGICS = {
    0xFADE0CC0: "embedded-signature",
    0xFADE0C02: "code-directory",
    0xFADE0C01: "requirements",
    0xFADE7171: "entitlements",
    0xFADE0B01: "cms-wrapper",
}
SIGNATURE_SLOTS = {
    0: "code-directory",
    2: "requirements",
    5: "entitlements",
    0x10000: "cms-signature",
}
CODE_SIGN_FLAGS = {
    0x00000001: "valid",
    0x00000002: "adhoc",
    0x00000100: "hard",
    0x00000200: "kill",
    0x00001000: "restrict",
    0x00010000: "runtime",
    0x00020000: "linker-signed",
}


def version(value: int) -> str:
    return f"{value >> 16}.{(value >> 8) & 0xFF}.{value & 0xFF}"


def c_string(blob: bytes, offset: int, limit: int) -> str:
    if offset < 0 or offset >= limit:
        return ""
    end = blob.find(b"\0", offset, limit)
    if end < 0:
        end = limit
    return blob[offset:end].decode("utf-8", errors="replace")


def parse_code_signature(data: bytes, offset: int, size: int) -> dict:
    end = offset + size
    if offset < 0 or size < 12 or end > len(data):
        return {"file_offset": offset, "size": size, "status": "invalid-range"}
    magic, length, count = struct.unpack_from(">III", data, offset)
    result = {
        "file_offset": offset,
        "size": size,
        "magic": f"0x{magic:08x}",
        "kind": SIGNATURE_MAGICS.get(magic, "unknown"),
        "declared_length": length,
        "slots": [],
    }
    if magic != 0xFADE0CC0 or length > size or 12 + count * 8 > length:
        return result
    for index in range(count):
        slot_type, relative = struct.unpack_from(">II", data, offset + 12 + index * 8)
        blob_offset = offset + relative
        if blob_offset + 8 > offset + length:
            result["slots"].append({"type": slot_type, "status": "invalid-offset"})
            continue
        blob_magic, blob_length = struct.unpack_from(">II", data, blob_offset)
        slot = {
            "type": slot_type,
            "name": SIGNATURE_SLOTS.get(slot_type, f"slot-{slot_type:#x}"),
            "magic": f"0x{blob_magic:08x}",
            "kind": SIGNATURE_MAGICS.get(blob_magic, "unknown"),
            "length": blob_length,
        }
        if blob_magic == 0xFADE0C02 and blob_length >= 44 and blob_offset + blob_length <= end:
            _, _, cd_version, flags, _, identifier_offset, _, code_slots, code_limit = struct.unpack_from(
                ">IIIIIIIII", data, blob_offset
            )
            hash_size, hash_type, platform, page_size = struct.unpack_from(">BBBB", data, blob_offset + 36)
            slot.update({
                "version": f"0x{cd_version:x}",
                "flags": f"0x{flags:x}",
                "flag_names": [name for bit, name in CODE_SIGN_FLAGS.items() if flags & bit],
                "identifier": c_string(data, blob_offset + identifier_offset, blob_offset + blob_length),
                "code_slots": code_slots,
                "code_limit": code_limit,
                "hash_size": hash_size,
                "hash_type": hash_type,
                "platform": platform,
                "page_size_log2": page_size,
                "cdhash_sha256_20": hashlib.sha256(data[blob_offset : blob_offset + blob_length]).hexdigest()[:40],
            })
        result["slots"].append(slot)
    result["has_cms_signature"] = any(slot.get("name") == "cms-signature" for slot in result["slots"])
    return result


def parse(path: Path) -> dict:
    data = path.read_bytes()
    if len(data) < 32:
        raise ValueError("file is shorter than a Mach-O 64 header")
    magic = data[:4]
    if magic == bytes.fromhex("cffaedfe"):
        endian = "<"
        byte_order = "little"
    elif magic == bytes.fromhex("feedfacf"):
        endian = ">"
        byte_order = "big"
    else:
        raise ValueError(f"unsupported or non-thin-64 Mach-O magic {magic.hex()}")

    header = struct.unpack_from(endian + "IiiIIIII", data, 0)
    _, cpu_type, cpu_subtype, file_type, ncmds, sizeofcmds, flags, _ = header
    command_offset = 32
    command_end = command_offset + sizeofcmds
    if command_end > len(data):
        raise ValueError("load-command region exceeds file")

    result = {
        "path": str(path),
        "sha256": hashlib.sha256(data).hexdigest(),
        "size": len(data),
        "byte_order": byte_order,
        "architecture": CPU_TYPES.get(cpu_type & 0xFFFFFFFF, f"cpu-{cpu_type & 0xFFFFFFFF:#x}"),
        "cpu_subtype": cpu_subtype & 0xFFFFFFFF,
        "file_type": FILE_TYPES.get(file_type, str(file_type)),
        "command_count": ncmds,
        "load_commands_size": sizeofcmds,
        "flags": f"0x{flags:08x}",
        "uuid": None,
        "entry_file_offset": None,
        "minimum_os": None,
        "sdk": None,
        "platform": None,
        "dependencies": [],
        "rpaths": [],
        "segments": [],
        "code_signature": None,
        "symbol_table": None,
        "imports": [],
        "exports": [],
    }

    symtab = None
    for index in range(ncmds):
        if command_offset + 8 > command_end:
            raise ValueError(f"load command {index} header exceeds command region")
        command, size = struct.unpack_from(endian + "II", data, command_offset)
        if size < 8 or command_offset + size > command_end:
            raise ValueError(f"load command {index} has invalid size {size}")

        if command in DYLIB_COMMANDS and size >= 24:
            name_offset, timestamp, current, compatibility = struct.unpack_from(
                endian + "IIII", data, command_offset + 8
            )
            result["dependencies"].append({
                "kind": DYLIB_COMMANDS[command],
                "path": c_string(data, command_offset + name_offset, command_offset + size),
                "current_version": version(current),
                "compatibility_version": version(compatibility),
                "timestamp": timestamp,
            })
        elif command == LC_RPATH and size >= 12:
            (path_offset,) = struct.unpack_from(endian + "I", data, command_offset + 8)
            result["rpaths"].append(c_string(data, command_offset + path_offset, command_offset + size))
        elif command == LC_UUID and size >= 24:
            result["uuid"] = str(uuid.UUID(bytes=data[command_offset + 8 : command_offset + 24]))
        elif command == LC_MAIN and size >= 24:
            entry, _stack = struct.unpack_from(endian + "QQ", data, command_offset + 8)
            result["entry_file_offset"] = entry
        elif command == LC_VERSION_MIN_MACOSX and size >= 16:
            minimum, sdk = struct.unpack_from(endian + "II", data, command_offset + 8)
            result["platform"] = "macOS"
            result["minimum_os"] = version(minimum)
            result["sdk"] = version(sdk)
        elif command == LC_BUILD_VERSION and size >= 24:
            platform, minimum, sdk, tool_count = struct.unpack_from(
                endian + "IIII", data, command_offset + 8
            )
            result["platform"] = PLATFORMS.get(platform, str(platform))
            result["minimum_os"] = version(minimum)
            result["sdk"] = version(sdk)
            result["build_tool_count"] = tool_count
        elif command == LC_CODE_SIGNATURE and size >= 16:
            offset, length = struct.unpack_from(endian + "II", data, command_offset + 8)
            result["code_signature"] = parse_code_signature(data, offset, length)
        elif command == LC_SYMTAB and size >= 24:
            symtab = struct.unpack_from(endian + "IIII", data, command_offset + 8)
            result["symbol_table"] = {
                "file_offset": symtab[0],
                "count": symtab[1],
                "string_table_offset": symtab[2],
                "string_table_size": symtab[3],
            }
        elif command == LC_SEGMENT_64 and size >= 72:
            segment_name = data[command_offset + 8 : command_offset + 24].split(b"\0", 1)[0].decode("ascii", "replace")
            vmaddr, vmsize, fileoff, filesize, maxprot, initprot, section_count, segment_flags = struct.unpack_from(
                endian + "QQQQIIII", data, command_offset + 24
            )
            result["segments"].append({
                "name": segment_name,
                "vm_address": f"0x{vmaddr:x}",
                "vm_size": vmsize,
                "file_offset": fileoff,
                "file_size": filesize,
                "maximum_protection": maxprot,
                "initial_protection": initprot,
                "section_count": section_count,
                "flags": f"0x{segment_flags:x}",
            })
        command_offset += size

    if symtab is not None:
        symoff, symbol_count, stroff, strsize = symtab
        if symoff + symbol_count * 16 <= len(data) and stroff + strsize <= len(data):
            imports: list[str] = []
            exports: list[str] = []
            for index in range(symbol_count):
                strx, symbol_type, section, description, value = struct.unpack_from(
                    endian + "IBBHQ", data, symoff + index * 16
                )
                if strx == 0 or strx >= strsize:
                    continue
                name = c_string(data, stroff + strx, stroff + strsize)
                kind = symbol_type & 0x0E
                external = bool(symbol_type & 0x01)
                if external and kind == 0 and value == 0:
                    imports.append(name)
                elif external and kind != 0 and section != 0:
                    exports.append(name)
            result["imports"] = sorted(set(imports))
            result["exports"] = sorted(set(exports))

    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="+", type=Path)
    args = parser.parse_args()
    print(json.dumps([parse(path.resolve()) for path in args.paths], indent=2))


if __name__ == "__main__":
    main()
