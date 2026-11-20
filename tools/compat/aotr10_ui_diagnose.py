#!/usr/bin/env python3
"""Read-only AotR 10 / 8P War of the Ring UI asset collector (no game modification)."""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import pathlib
import re
import stat
import struct
import sys
try:
    import winreg
except ImportError:  # allow offline unit tests on non-Windows hosts
    winreg = None
import zipfile

ARCHIVE_NAMES = {
    'mpgamesetup.big', 'onlinestrategic.big', 'lanstrategic.big',
    'onlineopenplay.big', 'lanopenplay.big', 'lanlobby.big',
    '!!!wotr_8p_ui_test.big', 'payload_ui.big',
}
ASSET_NAMES = {
    'mpgamesetup.apt', 'mpgamesetup.const',
    'onlinestrategic.apt', 'onlinestrategic.const',
    'lanstrategic.apt', 'lanstrategic.const',
}
SKIP = {'$recycle.bin', 'system volume information', 'windows', 'windowsapps',
        'steamapps', 'epic games', 'node_modules', '.git', 'appdata', 'onedrive',
        'saved games', 'bepinex', 'unrealprojects', 'downloads'}
LIMIT_ASSET = 8 * 1024 * 1024
LIMIT_TOTAL = 48 * 1024 * 1024
LIMIT_DIRECTORIES = 30000


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def is_safe_directory(path: pathlib.Path) -> bool:
    try:
        st = path.lstat()
        return stat.S_ISDIR(st.st_mode) and not (st.st_file_attributes & 0x400)
    except (OSError, AttributeError):
        return path.is_dir() and not path.is_symlink()


def installed_roots() -> list[pathlib.Path]:
    roots = []
    user = pathlib.Path.home()
    roots += [
        user / 'Pfad D' / 'Games', user / 'Pfad D' / 'RotWK',
        user / 'Pfad D' / 'BFME Workshop',
        pathlib.Path('C:/AgeoftheRing'), pathlib.Path('C:/Games/AotR'),
        pathlib.Path('C:/Games/AgeoftheRing'), pathlib.Path('D:/Games/AotR'),
        pathlib.Path('D:/Games/AotR/AgeoftheRing'),
        pathlib.Path('C:/Program Files (x86)/Age of the Ring'),
        pathlib.Path(os.environ.get('LOCALAPPDATA', str(user / 'AppData' / 'Local'))) / 'AotR 8P WotR Mod',
    ]
    for drive in 'CDE':
        top = pathlib.Path(f'{drive}:/')
        try:
            roots += [p for p in top.iterdir() if p.is_dir() and
                      re.search(r'age.?of.?the.?ring|aotr|bfme|rotwk', p.name, re.I)]
        except OSError:
            pass
    # Windows uninstall entries provide a stronger hint than guessed folder names.
    for hive in ((winreg.HKEY_CURRENT_USER, winreg.HKEY_LOCAL_MACHINE) if winreg else ()):
        for key in (r'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                    r'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'):
            try:
                with winreg.OpenKey(hive, key) as base:
                    for index in range(winreg.QueryInfoKey(base)[0]):
                        try:
                            with winreg.OpenKey(base, winreg.EnumKey(base, index)) as sub:
                                display = str(winreg.QueryValueEx(sub, 'DisplayName')[0])
                                if 'age of the ring' in display.lower():
                                    location = str(winreg.QueryValueEx(sub, 'InstallLocation')[0])
                                    roots.append(pathlib.Path(location))
                        except (OSError, ValueError):
                            pass
            except OSError:
                pass
    seen, result = set(), []
    for root in roots:
        key = str(root).lower().rstrip('\\/')
        if key not in seen and is_safe_directory(root):
            seen.add(key)
            result.append(root)
    return result


def discover(roots: list[pathlib.Path]):
    found, visited, containers = [], 0, []
    for root in roots:
        for current, dirs, files in os.walk(root, topdown=True, followlinks=False):
            visited += 1
            if visited > LIMIT_DIRECTORIES:
                return found, visited, True, containers
            rel = pathlib.Path(current).relative_to(root)
            if len(rel.parts) > 9:
                dirs[:] = []
                continue
            dirs[:] = [d for d in dirs if d.lower() not in SKIP and
                       is_safe_directory(pathlib.Path(current) / d)]
            for filename in files:
                if filename.lower().endswith('.big') and filename.lower() not in ARCHIVE_NAMES and len(containers) < 1000:
                    candidate = pathlib.Path(current) / filename
                    if not candidate.is_symlink() and candidate.is_file():
                        containers.append(candidate)
                if filename.lower() in ARCHIVE_NAMES | ASSET_NAMES:
                    item = pathlib.Path(current) / filename
                    if not item.is_symlink() and item.is_file():
                        found.append(item)
    unique = {str(p).casefold(): p for p in found}
    return sorted(unique.values(), key=lambda p: str(p).lower()), visited, False, containers


def parse_big_entries(path: pathlib.Path):
    """Inventory EA BIGF/BIG4 entries, rejecting out-of-range offsets and sizes."""
    result = {'format': 'unknown', 'entries': [], 'warnings': []}
    with path.open('rb') as stream:
        size = path.stat().st_size
        head = stream.read(16)
        if len(head) < 16 or head[:4] not in (b'BIGF', b'BIG4'):
            return result
        result['format'] = head[:4].decode('ascii')
        declared_size, count, header_size = struct.unpack('>III', head[4:16])
        result.update(declared_size=declared_size, member_count=count, header_size=header_size)
        if count > 100000 or header_size > size or header_size > 16 * 1024 * 1024:
            result['warnings'].append('Unplausible header/count; no members parsed')
            return result
        if declared_size != size:
            result['warnings'].append('Archive length differs from declared BIG size')
        table = stream.read(max(0, header_size - 16))
        pos = 0
        for _ in range(count):
            if pos + 8 > len(table):
                result['warnings'].append('Incomplete BIG table')
                break
            offset, length = struct.unpack_from('>II', table, pos)
            pos += 8
            end = table.find(b'\0', pos)
            if end < pos:
                result['warnings'].append('Missing BIG member terminator')
                break
            name = table[pos:end].decode('latin-1', errors='replace')
            pos = end + 1
            if offset + length > size:
                result['warnings'].append('Member out of range: ' + name[:100])
                continue
            if any(token in name.lower() for token in
                   ('mpgamesetup', 'strategic', 'openplay', 'wotr', 'playermatrix')):
                result['entries'].append({'name': name, 'offset': offset, 'size': length})
    return result


def collect(roots: list[pathlib.Path], destination: pathlib.Path) -> dict:
    found, dirs, truncated, possible_containers = discover(roots)
    report = {
        'tool': 'AOTR10-LOBBY-UI-DIAGNOSE-v1',
        'read_only': True, 'roots': list(map(str, roots)),
        'directories_visited': dirs, 'scan_truncated': truncated,
        'assets': [], 'warnings': [], 'probed_other_bigs': 0,
        'note': 'Private diagnostic. Game assets are NOT intended for public GitHub.',
    }
    # AotR can embed these UI APTs in otherwise named BIG archives. Probe only
    # BIG directory tables, and preserve relevant small APT/CONST members.
    nested_sources = {}
    for path in possible_containers:
        try:
            if path.stat().st_size > 1024 * 1024 * 1024:
                continue
            inv = parse_big_entries(path)
            report['probed_other_bigs'] += 1
            matches = [v for v in inv['entries'] if any(needle in v['name'].lower()
                       for needle in ('mpgamesetup.', 'onlinestrategic.', 'lanstrategic.'))
                       and v['name'].lower().endswith(('.apt', '.const'))]
            if matches:
                nested_sources[str(path).lower()] = matches
                found.append(path)
        except OSError:
            continue
    found = sorted(set(found), key=lambda p: str(p).lower())
    if not found:
        report['warnings'].append('No matching archives found: specify --root GAME_INSTALL_DIRECTORY')
    total = 0
    destination.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(destination, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for i, path in enumerate(found):
            try:
                size = path.stat().st_size
                entry = {'source': str(path), 'bytes': size}
                report['assets'].append(entry)
                if path.suffix.lower() == '.big':
                    entry['big'] = parse_big_entries(path)
                    if str(path).lower() in nested_sources:
                        entry['embedded_ui'] = []
                        with path.open('rb') as infile:
                            for j, member in enumerate(nested_sources[str(path).lower()]):
                                if member['size'] > LIMIT_ASSET or total + member['size'] > LIMIT_TOTAL:
                                    continue
                                infile.seek(member['offset'])
                                payload = infile.read(member['size'])
                                if len(payload) != member['size']:
                                    continue
                                internal_name = pathlib.PureWindowsPath(member['name']).name
                                arcname = f'extracted_apt/{i:03d}_{j:02d}_{internal_name}'
                                z.writestr(arcname, payload)
                                entry['embedded_ui'].append({'name': member['name'], 'sha256': sha256(payload), 'copy': arcname})
                                total += len(payload)
                if size > LIMIT_ASSET or total + size > LIMIT_TOTAL:
                    entry['copy'] = 'skipped_size_limit'
                    continue
                data = path.read_bytes()
                if len(data) != size:
                    entry['copy'] = 'skipped_changed_during_scan'
                    continue
                entry['sha256'] = sha256(data)
                arcname = f'ui_assets/{i:03d}_{path.name}'
                z.writestr(arcname, data)
                entry['copy'] = arcname
                total += size
            except OSError as exc:
                report['warnings'].append(f'{path}: {exc.__class__.__name__}')
        report['included_asset_bytes'] = total
        z.writestr('REPORT.json', json.dumps(report, ensure_ascii=False, indent=2))
        z.writestr('HINWEIS.txt', 'Nur private Fehleranalyse. Keine Spieldateien im öffentlichen GitHub-Repository hochladen.\n')
    # Validate ZIP CRCs and report presence before announcing success.
    with zipfile.ZipFile(destination) as z:
        assert z.testzip() is None
        assert 'REPORT.json' in z.namelist()
    return report


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--root', action='append', help='AotR game install folder (repeatable)')
    ap.add_argument('--output', help='Exact output ZIP path; default Downloads')
    args = ap.parse_args()
    if os.name != 'nt':
        print('This diagnostic is for a Windows AotR installation.', file=sys.stderr)
        return 2
    roots = [pathlib.Path(p) for p in args.root] if args.root else installed_roots()
    roots = [p for p in roots if is_safe_directory(p)]
    if not roots:
        print('No readable AotR roots found; use --root C:\\path\\AgeoftheRing', file=sys.stderr)
        return 2
    timestamp = dt.datetime.now().strftime('%Y%m%d-%H%M%S')
    default_dir = pathlib.Path.home() / 'Downloads'
    output = pathlib.Path(args.output) if args.output else default_dir / f'AOTR10-UI-Diagnose-{timestamp}.zip'
    report = collect(roots, output)
    print(f'[BERICHT] {output}')
    print(f'[FUNDSTUECKE] {len(report["assets"])} | {report["included_asset_bytes"] / 1048576:.1f} MiB verpackt')
    print('[SCHREIBZUGRIFFE] Keine Spieldateien/Launcher geaendert.')
    for warning in report['warnings']:
        print('[HINWEIS]', warning)
    return 0 if report['assets'] else 3


if __name__ == '__main__':
    raise SystemExit(main())
