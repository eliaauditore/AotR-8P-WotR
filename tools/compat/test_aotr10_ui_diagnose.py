import json
import os
from pathlib import Path
import struct
import tempfile
import unittest
import zipfile
from aotr10_ui_diagnose import collect, discover, parse_big_entries, sha256


def bigf(entries):
    # BIGF / BIG4 standard header, big-endian metadata, null-terminated names
    header_size = 16 + sum(8 + len(n.encode('latin1')) + 1 for n, b in entries)
    size = header_size + sum(len(b) for n, b in entries)
    out = bytearray(b'BIGF' + struct.pack('<I', size) + struct.pack('>II', len(entries), header_size))
    cursor = header_size
    for name, data in entries:
        out += struct.pack('>II', cursor, len(data)) + name.encode('latin1') + b'\0'
        cursor += len(data)
    for _, b in entries:
        out += b
    return bytes(out)


class ScanTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.inst = self.root / 'AgeoftheRing' / 'aotr'
        self.inst.mkdir(parents=True)

    def test_big_parser(self):
        p = self.inst / 'MpGameSetup.big'
        p.write_bytes(bigf([('MpGameSetup.apt', b'ABC'), ('irrelevant.ini', b'X')]))
        result = parse_big_entries(p)
        self.assertEqual(result['format'], 'BIGF')
        self.assertEqual(result['warnings'], [])
        self.assertEqual(result['declared_size'], p.stat().st_size)
        self.assertEqual(result['member_count'], 2)
        self.assertEqual(result['entries'][0]['name'], 'MpGameSetup.apt')
        self.assertEqual(result['entries'][0]['size'], 3)
        self.assertEqual(len(result['entries']), 1)

    def test_non_big_format(self):
        p = self.inst / 'MpGameSetup.big'
        p.write_bytes(b'not-a-big')
        self.assertEqual(parse_big_entries(p)['format'], 'unknown')

    def test_corrupt_big_count(self):
        p = self.inst / 'MpGameSetup.big'
        p.write_bytes(b'BIGF' + struct.pack('<I', 16) + struct.pack('>II', 1000000, 16))
        self.assertIn('Unplausible', parse_big_entries(p)['warnings'][0])

    def test_truncated_big_table(self):
        p = self.inst / 'MpGameSetup.big'
        p.write_bytes(b'BIGF' + struct.pack('<I', 20) + struct.pack('>II', 1, 20) + b'\x00'*4)
        self.assertIn('Incomplete', parse_big_entries(p)['warnings'][0])

    def test_wrong_size_warning(self):
        p = self.inst / 'MpGameSetup.big'
        data = bytearray(bigf([('MpGameSetup.apt', b'A')]))
        data[4:8] = (12).to_bytes(4, 'little')
        p.write_bytes(data)
        self.assertTrue(parse_big_entries(p)['warnings'])

    def test_detects_asset_and_skips_unrelated(self):
        (self.inst / 'MpGameSetup.big').write_bytes(b'test')
        (self.inst / 'something_else.big').write_bytes(b'test')
        found, dirs, truncated, containers = discover([self.root])
        self.assertEqual(len(found), 1)
        self.assertEqual(found[0].name, 'MpGameSetup.big')
        self.assertFalse(truncated)

    def test_ignores_steamapps(self):
        d = self.root / 'steamapps'
        d.mkdir()
        (d / 'MpGameSetup.big').write_bytes(b'x')
        self.assertEqual(discover([self.root])[0], [])

    def test_no_symlink_recursion(self):
        try:
            (self.root / 'loop').symlink_to(self.root, target_is_directory=True)
        except (OSError, NotImplementedError):
            self.skipTest('symlinks unavailable')
        (self.inst / 'MpGameSetup.big').write_bytes(b'test')
        found, count, _, _ = discover([self.root])
        self.assertEqual(len(found), 1)
        self.assertLess(count, 10)

    def test_collect_zip_hash_and_no_writes(self):
        p = self.inst / 'LanStrategic.big'
        raw = bigf([('LanStrategic.apt', b'game-ui')])
        p.write_bytes(raw)
        out = self.root / 'out.zip'
        before = (p.stat().st_mtime_ns, sha256(p.read_bytes()))
        r = collect([self.root], out)
        self.assertEqual(len(r['assets']), 1)
        with zipfile.ZipFile(out) as z:
            self.assertIsNone(z.testzip())
            rep = json.loads(z.read('REPORT.json'))
            self.assertEqual(rep['assets'][0]['sha256'], sha256(raw))
            self.assertEqual(z.read(rep['assets'][0]['copy']), raw)
        self.assertEqual(before, (p.stat().st_mtime_ns, sha256(p.read_bytes())))

    def test_larger_asset_not_copied(self):
        p = self.inst / 'MpGameSetup.big'
        p.write_bytes(b'Z' * (8*1024*1024 + 1))
        out = self.root / 'out.zip'
        r = collect([self.root], out)
        self.assertEqual(r['assets'][0]['copy'], 'skipped_size_limit')
        self.assertEqual(r['included_asset_bytes'], 0)

    def test_embedded_target_in_generic_big_is_extracted(self):
        p = self.inst / 'aotr_ui_bundle.big'
        raw = bigf([('data\\apt\\MpGameSetup.apt', b'UPPER-PANEL'),
                    ('textures/image.tga', b'IGNORE')])
        p.write_bytes(raw)
        out = self.root / 'out.zip'
        r = collect([self.root], out)
        self.assertEqual(len(r['assets']), 1)
        with zipfile.ZipFile(out) as z:
            rep = json.loads(z.read('REPORT.json'))
            nested = rep['assets'][0]['embedded_ui']
            self.assertEqual(len(nested), 1)
            self.assertEqual(z.read(nested[0]['copy']), b'UPPER-PANEL')

    def test_empty_scan_still_has_report(self):
        out = self.root / 'out.zip'
        r = collect([self.root], out)
        self.assertIn('No matching', r['warnings'][0])
        with zipfile.ZipFile(out) as z:
            self.assertIn('REPORT.json', z.namelist())


if __name__ == '__main__':
    unittest.main(verbosity=2)
