import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from tools import fetch_skia


class SkiaBinaryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.root = self.directory / "cache" / "windows-x64"

    def package(self, *, vulkan=True, traversal=False):
        archive = self.directory / "release.zip"
        with zipfile.ZipFile(archive, "w") as package:
            for name in fetch_skia.REQUIRED_LIBRARIES:
                package.writestr(f"out/Release-x64/{name}.lib", b"archive-fixture")
            package.writestr("out/Release-x64/defines.cmake",
                             "-DSK_GANESH -DSK_GL -DSKIA_IMPLEMENTATION=1 "
                             "-DSK_USE_INTERNAL_VULKAN_HEADERS " + ("-DSK_VULKAN" if vulkan else ""))
            for name in ("include/core/SkCanvas.h", "modules/svg/include/SkSVGDOM.h",
                         "src/gpu/vk/vulkanmemoryallocator/VulkanMemoryAllocatorPriv.h"):
                package.writestr(name, "// fixture")
            if traversal:
                package.writestr("../escaped.txt", "should not be extracted")
        return archive

    def metadata(self, archive):
        return dict(tag="test-release", platform="windows", arch="x64",
                    url="https://github.com/HumbleUI/SkiaBuild/releases/download/test/package.zip",
                    digest="sha256:" + hashlib.sha256(archive.read_bytes()).hexdigest(), asset="package.zip")

    def downloader(self, archive):
        def copy(_url, destination, **_kwargs):
            destination.write_bytes(archive.read_bytes())
        return patch.object(fetch_skia, "curl", side_effect=copy)

    def test_matching_headers_libraries_and_consumer_flags(self):
        archive = self.package()
        metadata = self.metadata(archive)
        with self.downloader(archive):
            fetch_skia.download(self.root, metadata)
        config = (self.root / "skia.cmake").read_text()
        self.assertIn(self.root.resolve().as_posix(), config)
        self.assertIn("SK_GANESH;SK_GL;SK_VULKAN", config)
        self.assertNotIn("SKIA_IMPLEMENTATION", config)
        self.assertNotIn("SK_USE_INTERNAL_VULKAN_HEADERS", config)
        self.assertIn('set(KINE_SKIA_AUTO_DOWNLOAD "OFF"', config)
        self.assertEqual(json.loads((self.root / "release.json").read_text()), metadata)

    def test_cache_hit_does_not_download_again(self):
        archive = self.package()
        metadata = self.metadata(archive)
        with self.downloader(archive):
            fetch_skia.download(self.root, metadata)
        with patch.object(fetch_skia, "curl") as curl:
            fetch_skia.download(self.root, metadata)
            curl.assert_not_called()

    def test_replacement_removes_files_from_the_old_release(self):
        archive = self.package()
        metadata = self.metadata(archive)
        with self.downloader(archive):
            fetch_skia.download(self.root, metadata)
            (self.root / "stale.lib").write_bytes(b"old")
            fetch_skia.download(self.root, dict(metadata, tag="new-release"))
        self.assertFalse((self.root / "stale.lib").exists())

    def test_checksum_failure_preserves_existing_cache(self):
        archive = self.package()
        self.root.mkdir(parents=True)
        (self.root / "existing").write_text("keep")
        metadata = dict(self.metadata(archive), digest="sha256:" + "0" * 64)
        with self.downloader(archive), self.assertRaisesRegex(RuntimeError, "checksum"):
            fetch_skia.download(self.root, metadata)
        self.assertTrue((self.root / "existing").is_file())

    def test_install_failure_restores_existing_cache(self):
        archive = self.package()
        self.root.mkdir(parents=True)
        (self.root / "existing").write_text("keep")

        def rename(source, destination):
            if source.name == "package":
                raise OSError("cannot install the extracted package")
            source.rename(destination)

        with self.downloader(archive), patch.object(fetch_skia, "rename_directory", side_effect=rename):
            with self.assertRaisesRegex(OSError, "cannot install"):
                fetch_skia.download(self.root, self.metadata(archive))
        self.assertEqual((self.root / "existing").read_text(), "keep")

    def test_windows_temporary_file_lock_is_retried(self):
        error = PermissionError("sharing violation")
        error.winerror = 32
        with patch.object(Path, "rename", side_effect=[error, None]) as rename:
            with patch.object(fetch_skia.os, "name", "nt"), patch.object(fetch_skia.time, "sleep") as sleep:
                fetch_skia.rename_directory(self.root, self.directory / "destination")
        self.assertEqual(rename.call_count, 2)
        sleep.assert_called_once_with(0.05)

    def test_rejects_non_vulkan_package(self):
        archive = self.package(vulkan=False)
        with self.downloader(archive), self.assertRaisesRegex(RuntimeError, "Ganesh/Vulkan"):
            fetch_skia.download(self.root, self.metadata(archive))
        self.assertFalse(self.root.exists())

    def test_rejects_archive_path_traversal(self):
        archive = self.package(traversal=True)
        with self.downloader(archive), self.assertRaisesRegex(RuntimeError, "Invalid archive entry"):
            fetch_skia.download(self.root, self.metadata(archive))
        self.assertFalse(self.root.exists())

    def test_latest_resolution_selects_exact_target_and_requires_digest(self):
        release = dict(tag_name="m143", assets=[dict(name="Skia-m143-linux-Release-arm64.zip",
                       browser_download_url="https://github.com/example/package.zip", digest="sha256:" + "a" * 64)])
        def api(_url, destination, **_kwargs):
            destination.write_text(json.dumps(release))
        with patch.object(fetch_skia, "curl", side_effect=api):
            metadata = fetch_skia.resolve("linux", "arm64", "latest")
            self.assertEqual(metadata["arch"], "arm64")
            with self.assertRaisesRegex(RuntimeError, "no unique"):
                fetch_skia.resolve("linux", "x64", "latest")
            del release["assets"][0]["digest"]
            with self.assertRaisesRegex(RuntimeError, "SHA-256"):
                fetch_skia.resolve("linux", "arm64", "latest")


if __name__ == "__main__":
    unittest.main()
