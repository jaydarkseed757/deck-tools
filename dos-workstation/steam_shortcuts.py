#!/usr/bin/env python3
"""
steam_shortcuts.py — manage Steam non-Steam game shortcuts (shortcuts.vdf)

Commands:
  add    --name <title> --exe <path> --startdir <dir>
  list
  remove --name <name>
"""

import argparse
import binascii
import glob
import os
import struct
import sys


# ── Binary VDF serializers ────────────────────────────────────────────────────

def _s(key, val=''):
    """String field: type(01) + key\x00 + val\x00"""
    return b'\x01' + key.encode() + b'\x00' + str(val).encode('utf-8', errors='replace') + b'\x00'


def _i(key, val=0):
    """Uint32 field: type(02) + key\x00 + 4-byte LE"""
    return b'\x02' + key.encode() + b'\x00' + struct.pack('<I', int(val) & 0xffffffff)


def _o(key, body=b''):
    """Named object: type(00) + key\x00 + body + \x08"""
    return b'\x00' + key.encode() + b'\x00' + body + b'\x08'


def compute_appid(exe, name):
    """CRC32-based appid used by Steam for non-Steam shortcuts."""
    crc = binascii.crc32((exe + name).encode('utf-8')) | 0x80000000
    return crc & 0xffffffff


def make_entry(idx, name, exe, startdir):
    """Serialize one shortcut entry as binary VDF bytes."""
    appid = compute_appid(exe, name)
    body = (
        _i('appid',               appid) +
        _s('AppName',             name) +
        _s('Exe',                 exe) +
        _s('StartDir',            startdir) +
        _s('icon') +
        _s('ShortcutPath') +
        _s('LaunchOptions') +
        _i('IsHidden',            0) +
        _i('AllowDesktopConfig',  1) +
        _i('AllowOverlay',        1) +
        _i('openvr',              0) +
        _i('Devkit',              0) +
        _s('DevkitGameID') +
        _i('DevkitOverrideAppID', 0) +
        _i('LastPlayTime',        0) +
        _s('FlatpakAppID') +
        _o('tags')
    )
    return _o(str(idx), body)


def build_file(entry_blobs):
    """Wrap entry blobs in the shortcuts.vdf container."""
    return b'\x00shortcuts\x00' + b''.join(entry_blobs) + b'\x08\x08'


# ── Raw VDF splitter ──────────────────────────────────────────────────────────

def _skip_cstr(data, pos):
    """Skip a null-terminated string; return position after the null byte."""
    while data[pos] != 0:
        pos += 1
    return pos + 1


def split_raw_entries(data):
    """
    Split shortcuts.vdf bytes into individual raw entry blobs.
    Preserves each blob byte-for-byte so existing entries are never corrupted.
    Returns a list of bytes objects, one per shortcut.
    """
    pos = 0
    # Skip \x00shortcuts\x00 header
    if pos < len(data) and data[pos] == 0x00:
        pos += 1
        pos = _skip_cstr(data, pos)

    entries = []
    while pos < len(data):
        if data[pos] == 0x08:
            break
        if data[pos] != 0x00:
            break

        start = pos
        pos += 1                       # consume \x00 (object-open type)
        pos = _skip_cstr(data, pos)    # consume index key ("0", "1", …)

        # Scan fields at this depth until the entry-closing \x08
        depth = 0
        while pos < len(data):
            b = data[pos]
            pos += 1
            if b == 0x08:
                if depth == 0:
                    break          # this \x08 closes the entry
                depth -= 1
            elif b == 0x00:        # sub-object open
                pos = _skip_cstr(data, pos)   # consume sub-key
                depth += 1
            elif b == 0x01:        # string field
                pos = _skip_cstr(data, pos)   # key
                pos = _skip_cstr(data, pos)   # value
            elif b == 0x02:        # uint32 field
                pos = _skip_cstr(data, pos)   # key
                pos += 4

        entries.append(data[start:pos])

    return entries


def _field_value(blob, field_name):
    """
    Extract a string field value from a raw entry blob.
    Field encoding: \x01 + field_name\x00 + value\x00  (case-insensitive key match)
    """
    marker = b'\x01' + field_name.encode() + b'\x00'
    lower_blob = blob.lower()
    lower_marker = marker.lower()
    idx = lower_blob.find(lower_marker)
    if idx == -1:
        return ''
    start = idx + len(marker)
    end = blob.index(b'\x00', start)
    return blob[start:end].decode('utf-8', errors='replace')


def get_appname(blob):
    return _field_value(blob, 'AppName')


def get_exe(blob):
    return _field_value(blob, 'Exe')


# ── File discovery ────────────────────────────────────────────────────────────

def find_shortcuts_vdf():
    """Return path to shortcuts.vdf, or None if not found."""
    patterns = [
        os.path.expanduser('~/.steam/steam/userdata/*/config/shortcuts.vdf'),
        os.path.expanduser('~/.steam/root/userdata/*/config/shortcuts.vdf'),
        os.path.expanduser('~/.local/share/Steam/userdata/*/config/shortcuts.vdf'),
    ]
    for pat in patterns:
        matches = sorted(glob.glob(pat))
        if matches:
            return matches[0]
    return None


def find_config_dir():
    """Return a Steam userdata config dir to create shortcuts.vdf in."""
    patterns = [
        os.path.expanduser('~/.steam/steam/userdata/*/config/'),
        os.path.expanduser('~/.steam/root/userdata/*/config/'),
        os.path.expanduser('~/.local/share/Steam/userdata/*/config/'),
    ]
    for pat in patterns:
        matches = sorted(glob.glob(pat))
        if matches:
            return matches[0]
    return None


def load_entries(path):
    if not os.path.exists(path):
        return []
    with open(path, 'rb') as f:
        data = f.read()
    return split_raw_entries(data) if data else []


def save_entries(path, entry_blobs):
    tmp = path + '.tmp'
    with open(tmp, 'wb') as f:
        f.write(build_file(entry_blobs))
    os.replace(tmp, path)


# ── Commands ──────────────────────────────────────────────────────────────────

def cmd_list(args):
    path = find_shortcuts_vdf()
    if not path:
        print('No shortcuts.vdf found.', file=sys.stderr)
        sys.exit(1)
    entries = load_entries(path)
    if not entries:
        print('(no non-Steam shortcuts)')
        return
    for blob in entries:
        print(f'{get_appname(blob)}\t{get_exe(blob)}')


def cmd_add(args):
    path = find_shortcuts_vdf()
    if not path:
        cfg_dir = find_config_dir()
        if not cfg_dir:
            print(
                'Could not find Steam userdata directory.\n'
                'Launch Steam at least once before adding shortcuts.',
                file=sys.stderr,
            )
            sys.exit(1)
        path = os.path.join(cfg_dir, 'shortcuts.vdf')

    entries = load_entries(path)

    # Idempotent: skip if already present
    for blob in entries:
        if get_appname(blob).lower() == args.name.lower():
            print(f"'{args.name}' is already in Steam shortcuts.")
            return

    entries.append(make_entry(len(entries), args.name, args.exe, args.startdir))
    save_entries(path, entries)
    print(f"Added '{args.name}' to Steam shortcuts.")
    print('Restart Steam for the change to appear in your library.')


def cmd_remove(args):
    path = find_shortcuts_vdf()
    if not path:
        print('No shortcuts.vdf found.', file=sys.stderr)
        sys.exit(1)
    entries = load_entries(path)
    before = len(entries)
    # Preserve raw bytes for entries we're keeping — no data loss
    entries = [b for b in entries if get_appname(b).lower() != args.name.lower()]
    if len(entries) == before:
        print(f"'{args.name}' not found in Steam shortcuts.")
        return
    save_entries(path, entries)
    print(f"Removed '{args.name}' from Steam shortcuts.")


# ── Entry point ───────────────────────────────────────────────────────────────

def main():
    p = argparse.ArgumentParser(
        description='Manage Steam non-Steam game shortcuts',
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    sub = p.add_subparsers(dest='cmd', required=True)

    add_p = sub.add_parser('add', help='Add a non-Steam shortcut')
    add_p.add_argument('--name',     required=True, help='Display name in Steam')
    add_p.add_argument('--exe',      required=True, help='Path to launcher script')
    add_p.add_argument('--startdir', required=True, help='Working directory for Steam')

    sub.add_parser('list', help='List all non-Steam shortcuts')

    rm_p = sub.add_parser('remove', help='Remove a non-Steam shortcut by name')
    rm_p.add_argument('--name', required=True, help='AppName of the shortcut to remove')

    args = p.parse_args()
    {'add': cmd_add, 'list': cmd_list, 'remove': cmd_remove}[args.cmd](args)


if __name__ == '__main__':
    main()
