import importlib.util
import pathlib
import unittest
from unittest import mock


ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "resolve_remotes", ROOT / "tools" / "resolve_remotes.py"
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ResolveRemotesTests(unittest.TestCase):
    @mock.patch.object(MODULE.socket, "getaddrinfo")
    def test_expands_hostname_to_unique_ipv4_remote_lines(self, getaddrinfo):
        getaddrinfo.return_value = [
            (None, None, None, None, ("203.0.113.10", 1194)),
            (None, None, None, None, ("203.0.113.20", 1194)),
            (None, None, None, None, ("203.0.113.10", 1194)),
        ]
        result, remote_count = MODULE.transform_profile(
            "client\nremote vpn.example.test 1194 udp4\nserver-poll-timeout 120\nverb 3\n"
        )
        self.assertIn("remote 203.0.113.10 1194 udp4", result)
        self.assertIn("remote 203.0.113.20 1194 udp4", result)
        self.assertEqual(result.count("remote 203.0.113.10"), 1)
        self.assertIn("verb 3", result)
        self.assertNotIn("server-poll-timeout 120", result)
        self.assertEqual(result.count("server-poll-timeout 5"), 1)
        self.assertEqual(remote_count, 2)

    def test_preserves_literal_ipv4_remote(self):
        result, remote_count = MODULE.transform_profile("remote 203.0.113.10 1194\n")
        self.assertEqual(
            result, "remote 203.0.113.10 1194\nserver-poll-timeout 5\n"
        )
        self.assertEqual(remote_count, 1)

    @mock.patch.object(MODULE.socket, "getaddrinfo", side_effect=OSError)
    def test_preserves_hostname_when_resolution_fails(self, _getaddrinfo):
        line = "remote vpn.example.test 1194"
        result, remote_count = MODULE.transform_profile(line + "\n")
        self.assertEqual(result, line + "\nserver-poll-timeout 5\n")
        self.assertEqual(remote_count, 1)

    @mock.patch.object(MODULE.socket, "getaddrinfo")
    def test_uses_global_port_and_proto_when_remote_omits_them(self, getaddrinfo):
        getaddrinfo.return_value = [(None, None, None, None, ("203.0.113.30", 443))]
        result, remote_count = MODULE.transform_profile(
            "client\nproto tcp-client\nrport 443\nremote vpn.example.test\n"
        )
        self.assertIn("remote 203.0.113.30 443 tcp-client", result)
        self.assertEqual(remote_count, 1)
        self.assertEqual(getaddrinfo.call_args.kwargs["type"], MODULE.socket.SOCK_STREAM)

    @mock.patch.object(MODULE.socket, "getaddrinfo")
    def test_defaults_omitted_remote_port_to_1194(self, getaddrinfo):
        getaddrinfo.return_value = [(None, None, None, None, ("203.0.113.40", 1194))]
        result, _ = MODULE.transform_profile("remote vpn.example.test\n")
        self.assertIn("remote 203.0.113.40 1194", result)

    @mock.patch.object(MODULE.socket, "getaddrinfo")
    @mock.patch.object(MODULE.socket, "getservbyname", return_value=8443)
    def test_service_name_port_uses_the_remote_protocol(
        self, getservbyname, getaddrinfo
    ):
        getaddrinfo.return_value = [(None, None, None, None, ("203.0.113.50", 8443))]
        result, _ = MODULE.transform_profile(
            "remote vpn.example.test custom-service tcp-client\n"
        )
        getservbyname.assert_called_once_with("custom-service", "tcp")
        self.assertIn("remote 203.0.113.50 8443 tcp-client", result)


if __name__ == "__main__":
    unittest.main()
