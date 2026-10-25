"""Infrastructure guard tests only; no model, Godot, network or saved-world execution."""
import io
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import Mock

from economy_cloud_check import Check, Unverified, extract_tar, index_paths, safe_relative


class RestorationGuards(unittest.TestCase):
    def test_json_and_checksum_indices_preserve_full_relative_paths(self):
        data = '{"files":[{"path":"baseline23/assets/map.png"},{"path":"shared/wwo_map/map.gd"}],"merchant/main.tscn":{"size":4}}'
        self.assertEqual(index_paths(data), {"assets/map.png", "shared/wwo_map/map.gd", "merchant/main.tscn"})
        checksum = "a"*64 + "  baseline23/data/world.json\n"
        self.assertEqual(index_paths(checksum), {"data/world.json"})
        self.assertEqual(index_paths('{"path":"map.png"}'), set())

    def test_traversal_and_absolute_archive_paths_are_rejected(self):
        for path in ("../outside", "/etc/hosts", "baseline23/../../outside", "C:\\outside"):
            with self.subTest(path=path), self.assertRaises(ValueError):
                safe_relative(path)

    def test_archive_link_is_rejected_before_any_extraction(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            archive = root/"link.tar.gz"
            with tarfile.open(archive,"w:gz") as bundle:
                regular = tarfile.TarInfo("baseline23/good.txt")
                regular.size = 2
                bundle.addfile(regular,io.BytesIO(b"ok"))
                link = tarfile.TarInfo("baseline23/escape")
                link.type = tarfile.SYMTYPE
                link.linkname = "/etc"
                bundle.addfile(link)
            destination = root/"out"
            destination.mkdir()
            with self.assertRaises(ValueError):
                extract_tar(archive,destination)
            self.assertEqual(list(destination.iterdir()), [])

    def test_normal_archive_preserves_expected_layout(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            archive = root/"normal.tar.gz"
            with tarfile.open(archive,"w:gz") as bundle:
                record = tarfile.TarInfo("baseline23/assets/map.txt")
                record.size = 2
                bundle.addfile(record,io.BytesIO(b"ok"))
            destination = root/"out"
            destination.mkdir()
            extract_tar(archive,destination)
            self.assertEqual((destination/"baseline23/assets/map.txt").read_bytes(),b"ok")

    def test_archive_with_no_authoritative_checksum_is_never_downloaded(self):
        check = Check.__new__(Check)
        check.assets = {"02-resources23-map.tar.gz":{"digest":None}}
        check.downloaded = {}
        check.download = Mock()
        with self.assertRaises(Unverified):
            check.verified_archive("02-resources23-map.tar.gz")
        check.download.assert_not_called()

    def test_corrupt_archive_checksum_cannot_pass(self):
        with tempfile.TemporaryDirectory() as folder:
            archive = Path(folder)/"resources.tar.gz"
            archive.write_bytes(b"corrupted archive")
            check = Check.__new__(Check)
            name = "02-resources23-map.tar.gz"
            check.assets = {name:{"digest":"sha256:"+"a"*64}}
            check.downloaded = {}
            check.download = Mock(return_value=archive)
            with self.assertRaisesRegex(AssertionError,"SHA256 mismatch"):
                check.verified_archive(name)

    def test_failed_prerequisite_prevents_large_mode_downloads(self):
        check = Check.__new__(Check)
        check.release = {"tag_name":"present"}
        check.rows = [{"status":"UNVERIFIED"}]
        check.verified_archive = Mock()
        with self.assertRaises(Unverified):
            check.godot_import()
        check.verified_archive.assert_not_called()


if __name__ == "__main__":
    unittest.main()
