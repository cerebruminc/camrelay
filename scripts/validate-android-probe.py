#!/usr/bin/env python3
"""Check Android camera frames with the independent Camera2 probe."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import time


PROJECT = Path(__file__).resolve().parents[1]
APP_ID = "org.camrelay.androidprobe"


def stop_group(process):
    # Each command has its own process group, including an Emulator it launches.
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    process.wait()


class Validation:
    def __init__(self, avd):
        self.avd = avd
        default_sdk = Path.home() / ("Android/Sdk" if sys.platform == "linux" else "Library/Android/sdk")
        self.sdk = Path(os.environ.get("ANDROID_SDK_ROOT") or os.environ.get("ANDROID_HOME") or default_sdk)
        self.adb = self.sdk / "platform-tools/adb"
        self.cli = PROJECT / ".build/debug/camrelay"
        self.apk = PROJECT / ".build/android-probe/CamRelayAndroidProbe.apk"
        avd_home = Path(os.environ.get("ANDROID_AVD_HOME") or
                        str(Path(os.environ.get("ANDROID_USER_HOME") or Path.home() / ".android") / "avd"))
        ini = (avd_home / f"{avd}.ini").read_text()
        directory = next(line[5:] for line in ini.splitlines() if line.startswith("path="))
        self.environment_file = Path(directory) / "environment.ini"
        self.original_environment = self.environment_snapshot()
        for path in (self.adb, self.cli, self.apk, PROJECT / ".build/fixtures/checkerboard.png",
                     PROJECT / ".build/fixtures/colors.mp4"):
            if not path.is_file():
                raise RuntimeError(f"Required validation artifact is missing: {path}")
        parent = PROJECT / ".build/validation"
        parent.mkdir(parents=True, exist_ok=True)
        self.logs = Path(tempfile.mkdtemp(prefix="android-probe.", dir=parent))
        self.session = f"android-probe-{os.getpid()}"
        self.serial = None
        self.emulator = None
        self.relay = None
        self.started = False

    def environment_snapshot(self):
        if not self.environment_file.exists():
            return None
        return (hashlib.sha256(self.environment_file.read_bytes()).hexdigest(),
                self.environment_file.stat().st_mode & 0o777)

    def step(self, message):
        print(f"{time.strftime('%H:%M:%S')} {message}", flush=True)

    def run(self, arguments, check=True, emulator=False):
        command = list(map(str, arguments))
        with (self.logs / "commands.log").open("a") as log:
            log.write(f"Start: {' '.join(command)}\n")
        process = subprocess.Popen(command, cwd=PROJECT, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, text=True, start_new_session=True)
        if emulator:
            self.emulator = process
        try:
            output, _ = process.communicate()
        except BaseException:
            stop_group(process)
            output, _ = process.communicate()
            with (self.logs / "commands.log").open("a") as log:
                log.write(f"Interrupted: {' '.join(command)}\n{output}\n")
            raise
        with (self.logs / "commands.log").open("a") as log:
            log.write(f"{' '.join(command)} (exit {process.returncode})\n{output}\n")
        if check and process.returncode:
            raise RuntimeError(f"Command failed: {' '.join(command)}\n{output[-3000:]}")
        return subprocess.CompletedProcess(command, process.returncode, output)

    def control(self, *arguments, check=True):
        return self.run([self.cli, *arguments, "--session", self.session], check=check)

    def device(self, *arguments, **options):
        return self.run([self.adb, "-s", self.serial, *arguments], **options)

    def report(self):
        output = self.device("exec-out", "run-as", APP_ID, "cat", "files/status.json", check=False)
        try:
            report = json.loads(output.stdout)
        except json.JSONDecodeError:
            return {}
        if report.get("error"):
            raise RuntimeError(f"Camera2 probe failed: {report['error']}")
        with (self.logs / "frames.jsonl").open("a") as log:
            log.write(json.dumps(report) + "\n")
        return report

    def await_report(self, lens, predicate):
        while True:
            last = self.report()
            if last.get("lens") == lens and predicate(last):
                return last
            time.sleep(0.2)

    def open_camera(self, lens):
        self.device("shell", "am", "start", "-W", "-n", f"{APP_ID}/.MainActivity", "--es", "lens", lens)
        return self.await_report(lens, lambda report: report.get("frames", 0) >= 3)

    def await_relay(self):
        while True:
            if self.relay.poll() is not None:
                raise RuntimeError(f"Relay exited during startup:\n{(self.logs / 'relay.log').read_text()[-3000:]}")
            output = self.run([self.cli, "status", "--json", "--session", self.session], check=False)
            if not output.returncode:
                ready = json.loads(output.stdout)
                if not ready.get("error") and ready["status"]["selected"] == "pattern":
                    return ready
            time.sleep(0.2)

    def image_frames(self, lens):
        return self.await_report(lens, lambda report:
                                 "W" in report.get("samples", "") and "K" in report.get("samples", ""))

    def video_frames(self, lens):
        transitions = ""
        previous_frames = 0
        previous_timestamp = 0
        while True:
            report = self.report()
            samples = report.get("samples", "")
            frames = report.get("frames", 0)
            if report.get("lens") == lens and frames > previous_frames and len(samples) == 25:
                timestamp = report["timestampNs"]
                if timestamp <= previous_timestamp:
                    raise RuntimeError("Camera frame timestamps did not increase")
                previous_frames, previous_timestamp = frames, timestamp
                color = samples[12]
                if color in "RGB" and (not transitions or color != transitions[-1]):
                    transitions += color
                if any(cycle in transitions for cycle in ("RGBR", "GBRG", "BRGB")):
                    return
            time.sleep(0.2)

    def validate(self):
        self.step("Start the dedicated AVD")
        started = self.run([self.cli, "emulator", "start", "--platform", "android", "--avd", self.avd],
                           emulator=True)
        self.started = True
        match = re.search(r"emulator-\d+", started.stdout)
        if not match:
            raise RuntimeError(f"Emulator startup did not report its serial: {started.stdout}")
        self.serial = match.group()
        self.step("Install the native Camera2 probe and check both cameras are available")
        self.device("install", "-r", self.apk)
        self.device("shell", "pm", "grant", APP_ID, "android.permission.CAMERA")
        self.device("shell", "input", "keyevent", "KEYCODE_WAKEUP")
        self.device("shell", "wm", "dismiss-keyguard")
        self.open_camera("back")
        self.open_camera("front")
        self.step("Start the image/video relay")
        with (self.logs / "relay.log").open("w") as log:
            self.relay = subprocess.Popen([
                str(self.cli), "run", "--platform", "android", "--avd", self.avd,
                "--session", self.session, "--no-interactive",
                "--fixture", "pattern=.build/fixtures/checkerboard.png",
                "--fixture", "colors=.build/fixtures/colors.mp4", "--initial", "pattern",
            ], cwd=PROJECT, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        ready = self.await_relay()
        if ready["status"]["simulatorID"] != self.serial:
            raise RuntimeError("The relay attached to a different AVD")
        self.step("Check front and back camera image pixels")
        front = self.open_camera("front")
        self.image_frames("front")
        app_pid = self.device("shell", "pidof", APP_ID).stdout.strip()
        back = self.open_camera("back")
        self.image_frames("back")
        if not app_pid or front["cameraID"] == back["cameraID"]:
            raise RuntimeError("The probe did not discover separate front and back cameras")
        self.step("Switch to video and check changing pixels and looping on both cameras")
        self.control("select", "colors", "--json")
        self.video_frames("back")
        self.open_camera("front")
        self.video_frames("front")
        self.step("Switch back to the image without restarting the app")
        self.control("select", "pattern", "--json")
        self.image_frames("front")
        before = json.loads(self.control("status", "--json").stdout)["status"]
        rejected = self.control("select", "missing", "--json", check=False)
        after = json.loads(self.control("status", "--json").stdout)["status"]
        if not rejected.returncode or after["selected"] != "pattern" or after["generation"] != before["generation"]:
            raise RuntimeError("A failed fixture change did not preserve the current selection")
        self.step("Stop the relay and check app/AVD continuity and unchanged configuration")
        self.control("stop")
        self.relay.wait()
        if self.relay.returncode:
            raise RuntimeError(f"Relay exited with status {self.relay.returncode}")
        if (self.device("get-state").stdout.strip() != "device" or
                self.device("shell", "pidof", APP_ID).stdout.strip() != app_pid):
            raise RuntimeError("Relay shutdown stopped the AVD or restarted the app")
        if self.environment_snapshot() != self.original_environment:
            raise RuntimeError("Validation changed the AVD environment.ini")
        self.step("Shut down the dedicated AVD")
        self.collect_logcat()
        self.run([self.cli, "emulator", "stop", "--platform", "android", "--avd", self.avd])
        self.started = False
        if self.device("get-state", check=False).returncode == 0:
            raise RuntimeError("The dedicated AVD remained available after emulator shutdown")
        self.step("PASS: Android image/video frames, looping, camera/fixture switching, failure preservation, and cleanup")

    def collect_logcat(self):
        try:
            output = self.device("exec-out", "logcat", "-d", "-s", "CamRelayAndroidProbe", "CameraService", check=False)
            (self.logs / "logcat.log").write_text(output.stdout)
        except RuntimeError as error:
            self.step(f"Could not collect logcat: {error}")

    def cleanup(self):
        if self.serial and self.started:
            self.collect_logcat()
        if self.relay:
            stop_group(self.relay)
        if self.started:
            try:
                self.run([self.cli, "emulator", "stop", "--platform", "android", "--avd", self.avd])
            except RuntimeError as error:
                self.step(f"AVD shutdown failed; trying adb and its owned process group: {error}")
                if self.serial:
                    self.device("emu", "kill", check=False)
        if self.emulator:
            stop_group(self.emulator)
        self.step(f"Validation artifacts: {self.logs}")


if __name__ == "__main__":
    def interrupted(signum, _frame):
        raise SystemExit(128 + signum)

    signal.signal(signal.SIGINT, interrupted)
    signal.signal(signal.SIGTERM, interrupted)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("avd", help="Dedicated, stopped AVD; validation shuts it down afterward")
    validation = None
    try:
        validation = Validation(parser.parse_args().avd)
        validation.validate()
    except (RuntimeError, OSError, ValueError) as error:
        print(f"FAIL: {error}", file=sys.stderr, flush=True)
        sys.exit(1)
    finally:
        if validation:
            validation.cleanup()
