from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from bridge import SessionLogger


class SessionLoggerTests(unittest.TestCase):
    def test_recent_events_keep_ids_and_support_incremental_queries(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            logger = SessionLogger(Path(temp_dir) / "sessions")
            info = logger.start_session("test")
            try:
                logger.log_event("bridge", "first", {"value": 1})
                logger.log_event("game", "second", {"value": 2})

                first_batch = logger.recent_events_since(0)
                self.assertEqual(
                    [event["event"] for event in first_batch],
                    ["session_started", "first", "second"],
                )
                self.assertEqual(
                    [event["event_id"] for event in first_batch],
                    [1, 2, 3],
                )

                second_batch = logger.recent_events_since(2)
                self.assertEqual(len(second_batch), 1)
                self.assertEqual(second_batch[0]["event_id"], 3)
                self.assertEqual(second_batch[0]["stream"], "game")

                logger.end_session(info["test_session_id"], "finished")
                next_info = logger.start_session("next")
                self.assertEqual(next_info["test_session_id"], 2)
                next_events = logger.recent_events_since(0)
                self.assertEqual(len(next_events), 1)
                self.assertEqual(next_events[0]["event"], "session_started")
                self.assertEqual(next_events[0]["session_id"], 2)
                self.assertEqual(next_events[0]["event_id"], 5)
            finally:
                logger.close()

    def test_keeps_current_and_two_previous_sessions(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir) / "sessions"
            logger = SessionLogger(root, keep_sessions=3)
            started_ids = []
            for index in range(4):
                info = logger.start_session(
                    "test",
                    {"index": index},
                )
                started_ids.append(info["test_session_id"])
                logger.log_event(
                    "game",
                    "game_received",
                    {"index": index},
                )
                result = logger.end_session(
                    info["test_session_id"],
                    "test_finished",
                )
                self.assertTrue(result["ok"])

            session_dirs = sorted(
                path
                for path in root.iterdir()
                if path.is_dir() and path.name.startswith("session_")
            )
            retained_ids = [
                int(path.name.split("_")[1])
                for path in session_dirs
            ]
            self.assertEqual(started_ids, [1, 2, 3, 4])
            self.assertEqual(retained_ids, [2, 3, 4])
            self.assertFalse(
                any(path.name.startswith("session_0001_") for path in root.iterdir())
            )

            latest = (root / "latest_session.txt").read_text(
                encoding="utf-8"
            ).strip()
            self.assertEqual(Path(latest).name, session_dirs[-1].name)
            game_events = (
                session_dirs[-1] / "game.jsonl"
            ).read_text(encoding="utf-8").splitlines()
            self.assertEqual(
                json.loads(game_events[0])["event"],
                "game_received",
            )
            metadata = json.loads(
                (session_dirs[-1] / "session.json").read_text(
                    encoding="utf-8"
                )
            )
            self.assertEqual(metadata["end_reason"], "test_finished")


if __name__ == "__main__":
    unittest.main()
