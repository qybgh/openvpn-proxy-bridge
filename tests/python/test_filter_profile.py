import importlib.util
import pathlib
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "filter_profile", ROOT / "tools" / "filter_profile.py"
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class FilterProfileTests(unittest.TestCase):
    def test_replaces_managed_directives_and_preserves_inline_blocks(self):
        source = (ROOT / "tests" / "fixtures" / "sample.profile").read_text()
        result = MODULE.transform_profile(source, "/private/auth.txt")

        self.assertIn("remote vpn.example.test 1194", result)
        self.assertIn("placeholder-certificate-data", result)
        self.assertNotIn("auth-user-pass old-auth.txt", result)
        self.assertNotIn("socks-proxy 127.0.0.1 9999", result)
        self.assertIn('auth-user-pass "/private/auth.txt"', result)
        self.assertIn("auth-retry none", result)
        self.assertIn("auth-nocache", result)
        self.assertNotIn("server-poll-timeout", result)

    def test_cli_writes_mode_600_target(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            source = root / "source.ovpn"
            target = root / "base.ovpn"
            auth = root / "auth.txt"
            source.write_text("client\nproto udp\n")
            old_argv = MODULE.sys.argv
            MODULE.sys.argv = ["filter_profile.py", str(source), str(target), str(auth)]
            try:
                self.assertEqual(MODULE.main(), 0)
            finally:
                MODULE.sys.argv = old_argv
            self.assertTrue(target.exists())
            self.assertEqual(target.stat().st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()
