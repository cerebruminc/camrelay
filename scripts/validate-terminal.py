#!/usr/bin/env python3
"""Exercise terminal controls and restoration using a dedicated pseudo-terminal."""
import json
import os
from pathlib import Path
import pty
import signal
import subprocess
import termios
import time


ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / ".build/debug/camrelay"


def await_state(session, predicate):
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        response = subprocess.run(
            [BINARY, "status", "--session", session, "--json"],
            capture_output=True, text=True, timeout=3,
        )
        if response.returncode == 0:
            state = json.loads(response.stdout)["status"]
            if predicate(state):
                return state
        time.sleep(0.02)
    raise AssertionError("Timed out waiting for terminal playback state")


def check(stop):
    session = f"terminal-{os.getpid()}-{stop}"
    master, slave = pty.openpty()
    original = termios.tcgetattr(slave)
    process = subprocess.Popen(
        [BINARY, "run", "--session", session,
         "--fixture", "first=.build/fixtures/red.png",
         "--fixture", "second=.build/fixtures/colors.mp4"],
        cwd=ROOT, stdin=slave, stdout=slave, stderr=slave,
        start_new_session=True,
    )
    try:
        state = await_state(session, lambda value: value["selected"] == "first")
        for key, expected, paused in [
            (b"2", "second", False), (b"b", "first", False),
            (b"n", "second", False), (b"r", "second", False),
            (b" ", "second", True), (b" ", "second", False),
            (b"1", "first", False),
        ]:
            generation = state["generation"]
            os.write(master, key)
            state = await_state(session, lambda value:
                value["generation"] > generation and value["selected"] == expected
                and value["paused"] == paused)
        if stop == "q":
            os.write(master, b"q")
        else:
            process.send_signal(getattr(signal, f"SIG{stop}"))
        assert process.wait(timeout=10) == 0
        restored = termios.tcgetattr(slave)
        # macOS sets PENDIN when canonical input is restored. It is a transient
        # driver flag for retyping pending input, not a changed terminal setting.
        pending = getattr(termios, "PENDIN", 0)
        original[3] &= ~pending
        restored[3] &= ~pending
        assert restored == original, "Terminal settings were not restored"
        response = subprocess.run(
            [BINARY, "status", "--session", session], capture_output=True, timeout=3,
        )
        assert response.returncode != 0, "Control endpoint remained active"
        print(f"PASS: terminal selection, navigation, replay, pause/play, and {stop} restoration")
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=10)
        os.close(master)
        os.close(slave)


if __name__ == "__main__":
    for stop_method in ["q", "INT", "TERM"]:
        check(stop_method)
