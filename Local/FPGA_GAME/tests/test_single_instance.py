from __future__ import annotations

import os
import unittest
import uuid

import bridge


@unittest.skipUnless(os.name == "nt", "Windows named mutex test")
class SingleInstanceTests(unittest.TestCase):
    def test_second_guard_is_rejected_and_released(self) -> None:
        name = rf"Local\SoulRiderBridgeTest.{uuid.uuid4().hex}"
        first = bridge.SingleInstanceGuard(name)
        second = bridge.SingleInstanceGuard(name)
        first.acquire()
        try:
            with self.assertRaises(bridge.AlreadyRunningError):
                second.acquire()
        finally:
            second.release()
            first.release()

        replacement = bridge.SingleInstanceGuard(name)
        replacement.acquire()
        replacement.release()


if __name__ == "__main__":
    unittest.main()
