#!/usr/bin/env python3
"""Exercise the packaged helper's pipe protocol without accessing iCloud."""

import json
import os
import stat
from pathlib import Path
import selectors
import subprocess
import sys
import tempfile
import time
import unittest


EXECUTABLE = Path(sys.argv.pop(1)).resolve() if len(sys.argv) > 1 else None


class HostProtocolTests(unittest.TestCase):
    def assert_private_lock_only(self, directory):
        root = Path(directory)
        self.assertEqual(sorted(p.name for p in root.iterdir()), [".host.lock"])
        self.assertEqual(stat.S_IMODE(root.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE((root / ".host.lock").stat().st_mode), 0o600)

    def test_persistent_pipe_replies_without_waiting_for_eof(self):
        with tempfile.TemporaryDirectory(prefix="clawnsole-icloud-persistent-") as directory:
            process = subprocess.Popen(
                [str(EXECUTABLE), "--journal-dir", directory],
                stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, text=True,
            )
            try:
                with selectors.DefaultSelector() as selector:
                    selector.register(process.stdout, selectors.EVENT_READ)
                    for request_id in ["first", "second"]:
                        process.stdin.write(json.dumps({
                            "id": request_id, "method": "unknown", "arguments": {},
                        }) + "\n")
                        process.stdin.flush()
                        self.assertTrue(selector.select(timeout=5),
                                        "Helper must reply while stdin remains open")
                        response = json.loads(process.stdout.readline())
                        self.assertEqual(response["id"], request_id)
                        self.assertEqual(response["result"]["error"]["code"], "unsupportedMethod")
                    self.assertIsNone(process.poll())
                    process.stdin.close()
                    self.assertEqual(process.wait(timeout=5), 0)
                self.assert_private_lock_only(directory)
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait(timeout=5)
                for stream in [process.stdin, process.stdout, process.stderr]:
                    stream.close()

    def run_host(self, requests):
        with tempfile.TemporaryDirectory(prefix="clawnsole-icloud-protocol-") as directory:
            completed = subprocess.run(
                [str(EXECUTABLE), "--journal-dir", directory],
                input=requests,
                text=True,
                capture_output=True,
                timeout=15,
            )
            # All exercised operations are malformed/unsupported or cancellation
            # requests: they must not discover an account or create leases.
            # The private process-lock file is created before reading requests.
            self.assert_private_lock_only(directory)
            return completed, [json.loads(line) for line in completed.stdout.splitlines()]

    def test_journal_is_exclusive_and_crash_releases_lock(self):
        with tempfile.TemporaryDirectory(prefix="clawnsole-icloud-exclusive-") as directory:
            request = json.dumps({"id": "check", "method": "unknown", "arguments": {}}) + "\n"
            first = subprocess.Popen(
                [str(EXECUTABLE), "--journal-dir", directory],
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            )
            try:
                first.stdin.write(request)
                first.stdin.flush()
                with selectors.DefaultSelector() as selector:
                    selector.register(first.stdout, selectors.EVENT_READ)
                    self.assertTrue(selector.select(timeout=5))
                    self.assertEqual(json.loads(first.stdout.readline())["id"], "check")
                second = subprocess.run(
                    [str(EXECUTABLE), "--journal-dir", directory],
                    input=request, capture_output=True, text=True, timeout=5,
                )
                self.assertEqual(second.returncode, 75)
                self.assertEqual(second.stdout, "")
                self.assertNotIn(directory, second.stderr)
                self.assertIsNone(first.poll())
                first.kill()
                first.wait(timeout=5)
                recovered = subprocess.run(
                    [str(EXECUTABLE), "--journal-dir", directory],
                    input=request, capture_output=True, text=True, timeout=5,
                )
                self.assertEqual(recovered.returncode, 0)
                self.assertEqual(json.loads(recovered.stdout)["id"], "check")
                self.assert_private_lock_only(directory)
            finally:
                if first.poll() is None:
                    first.kill()
                    first.wait(timeout=5)
                for stream in [first.stdin, first.stdout, first.stderr]:
                    stream.close()

    def test_eof_bounds_a_blocked_request_and_releases_journal(self):
        # Compile the actual process entry point against a deliberately blocked
        # service. This exercises crash/EOF lifetime without touching iCloud or
        # adding a delay/debug endpoint to the shipped helper.
        with tempfile.TemporaryDirectory(prefix="clawnsole-icloud-eof-") as directory:
            root = Path(directory)
            stub = root / "BlockedService.swift"
            stub.write_text("""import Foundation
actor ICloudReferenceHosting {
  enum Configuration { case userDrive }
  init(configuration: Configuration, journalDirectory: URL) {}
  func handle(method: String, arguments: [String: Any]) async -> [String: Any] {
    try? await Task.sleep(nanoseconds: 20_000_000_000)
    return ["ok": true]
  }
}
""")
            binary = root / "blocked-helper"
            subprocess.run([
                "xcrun", "swiftc", "-swift-version", "5", "-parse-as-library",
                str(Path(__file__).with_name("ICloudReferenceHostMain.swift")),
                str(stub), "-o", str(binary),
            ], check=True, capture_output=True, timeout=30)
            journal = root / "journal"
            began = time.monotonic()
            completed = subprocess.run(
                [str(binary), "--journal-dir", str(journal)],
                input=json.dumps({"id": "blocked", "method": "wait", "arguments": {}}) + "\n",
                text=True, capture_output=True, timeout=12,
            )
            self.assertEqual(completed.returncode, 75)
            self.assertGreaterEqual(time.monotonic() - began, 4.5)
            self.assertEqual(completed.stdout, "")
            recovered = subprocess.run(
                [str(EXECUTABLE), "--journal-dir", str(journal)],
                input=json.dumps({"id": "after", "method": "unknown", "arguments": {}}) + "\n",
                text=True, capture_output=True, timeout=5,
            )
            self.assertEqual(recovered.returncode, 0)
            self.assertEqual(json.loads(recovered.stdout)["id"], "after")
            self.assert_private_lock_only(journal)

    def test_symlink_and_hardlinked_lock_paths_are_rejected(self):
        with tempfile.TemporaryDirectory(prefix="clawnsole-icloud-unsafe-lock-") as directory:
            root = Path(directory)
            actual = root / "real"
            actual.mkdir()
            alias = root / "alias"
            alias.symlink_to(actual, target_is_directory=True)
            refused = subprocess.run([str(EXECUTABLE), "--journal-dir", str(alias)],
                                     input="", capture_output=True, text=True, timeout=5)
            self.assertEqual(refused.returncode, 75)
            self.assertEqual(list(actual.iterdir()), [])
            foreign = root / "foreign"
            foreign.write_text("must remain unchanged")
            foreign.chmod(0o644)
            lock = actual / ".host.lock"
            for kind in ["symlink", "hardlink"]:
                if kind == "symlink":
                    lock.symlink_to(foreign)
                else:
                    os.link(foreign, lock)
                refused = subprocess.run([str(EXECUTABLE), "--journal-dir", str(actual)],
                                         input="", capture_output=True, text=True, timeout=5)
                self.assertEqual(refused.returncode, 75)
                self.assertEqual(foreign.read_text(), "must remain unchanged")
                self.assertEqual(stat.S_IMODE(foreign.stat().st_mode), 0o644)
                lock.unlink()

    def test_concurrent_requests_are_correlated_and_drained_on_eof(self):
        sentinel = "private-request-value-must-not-be-logged"
        requests = [
            {"id": str(index), "method": "unknown", "arguments": {"sourcePath": sentinel}}
            for index in range(40)
        ]
        completed, responses = self.run_host(
            "".join(json.dumps(request) + "\n" for request in requests)
        )
        self.assertEqual(completed.returncode, 0)
        self.assertEqual(len(responses), len(requests))
        self.assertEqual({response["id"] for response in responses}, {request["id"] for request in requests})
        self.assertNotIn(sentinel, completed.stdout + completed.stderr)
        for response in responses:
            self.assertFalse(response["result"]["ok"])
            self.assertEqual(response["result"]["error"]["code"], "unsupportedMethod")

    def test_malformed_frame_does_not_break_the_next_request(self):
        request = {"id": "valid", "method": "cancel", "arguments": {"leaseId": "7a19451d-1ad7-44a7-a68c-c129057572af"}}
        completed, responses = self.run_host("not-json\n" + json.dumps(request) + "\n")
        self.assertEqual(completed.returncode, 0)
        by_id = {response["id"]: response for response in responses}
        self.assertEqual(by_id[None]["error"]["code"], "invalid")
        self.assertTrue(by_id["valid"]["result"]["ok"])
        self.assertFalse(by_id["valid"]["result"]["cancellationRequested"])
        self.assertNotIn("not-json", completed.stdout + completed.stderr)

    def test_oversized_unterminated_frame_is_rejected(self):
        completed, responses = self.run_host("x" * 70_000)
        self.assertEqual(completed.returncode, 65)
        self.assertEqual(responses[0]["error"]["code"], "invalid")
        self.assertLess(len(completed.stdout), 256)

    def test_partial_frame_at_eof_is_rejected(self):
        completed, responses = self.run_host('{"id":"partial"')
        self.assertEqual(completed.returncode, 65)
        self.assertEqual(responses[0]["error"]["code"], "invalid")


if __name__ == "__main__":
    if EXECUTABLE is None or not EXECUTABLE.is_file():
        raise SystemExit("Pass the built clawnsole_icloud_host executable.")
    unittest.main()
