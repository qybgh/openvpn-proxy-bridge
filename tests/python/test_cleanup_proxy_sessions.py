import importlib.util
import json
import pathlib
import tempfile
import unittest
from unittest import mock


ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "cleanup_proxy_sessions", ROOT / "tools" / "cleanup_proxy_sessions.py"
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class CleanupProxySessionsTests(unittest.TestCase):
    @mock.patch.object(MODULE.socket, "getaddrinfo")
    def test_profile_targets_resolves_remote_hosts(self, getaddrinfo):
        getaddrinfo.return_value = [(None, None, None, None, ("203.0.113.10", 1194))]
        targets = MODULE.profile_targets("remote vpn.example.test 1194\n")
        self.assertEqual(targets, {("203.0.113.10", 1194)})

    def test_controller_ports_prefers_proxy_relative_port(self):
        self.assertEqual(MODULE.controller_ports(12450), [12440, 9090, 9097])

    def test_matching_connection_ids_filters_destination_and_port(self):
        payload = {
            "connections": [
                {
                    "id": "match",
                    "metadata": {
                        "destinationIP": "203.0.113.10",
                        "destinationPort": "1194",
                    },
                },
                {
                    "id": "wrong-port",
                    "metadata": {
                        "destinationIP": "203.0.113.10",
                        "destinationPort": "443",
                    },
                },
            ]
        }
        result = MODULE.matching_connection_ids(payload, {("203.0.113.10", 1194)})
        self.assertEqual(result, ["match"])

    @mock.patch.object(MODULE.time, "sleep")
    @mock.patch.object(MODULE.urllib.request, "urlopen")
    def test_cleanup_deletes_matching_session_and_reports_count(self, urlopen, _sleep):
        first = mock.MagicMock()
        first.__enter__.return_value = first
        first.__exit__.return_value = False
        empty = mock.MagicMock()
        empty.__enter__.return_value = empty
        empty.__exit__.return_value = False
        delete = mock.MagicMock()
        delete.read.return_value = b""
        payloads = [
            {
                "connections": [
                    {
                        "id": "session-id",
                        "metadata": {
                            "destinationIP": "203.0.113.10",
                            "destinationPort": "1194",
                        },
                    }
                ]
            },
            {"connections": []},
        ]

        def side_effect(request, timeout=0.8):
            del timeout
            url = request if isinstance(request, str) else request.full_url
            if url.endswith("/connections"):
                response = first if len(payloads) == 2 else empty
                response.read.return_value = json.dumps(payloads.pop(0)).encode()
                return response
            return delete

        urlopen.side_effect = side_effect
        with tempfile.TemporaryDirectory() as directory:
            profile = pathlib.Path(directory) / "profile.ovpn"
            profile.write_text("remote 203.0.113.10 1194\n")
            self.assertEqual(MODULE.cleanup(profile, 12450), 1)


if __name__ == "__main__":
    unittest.main()
