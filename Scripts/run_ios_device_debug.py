#!/usr/bin/env python3

import argparse
import json
import signal
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path


DEFAULT_SCHEME = "iOS"
DEFAULT_PROJECT = "eisonAI.xcodeproj"
DEFAULT_BUNDLE_ID = "com.qoli.eisonAI"
DEFAULT_PROCESS_NAME = "eisonAI"
DEFAULT_OUTPUT_ROOT = Path("logs/ios_device_runs")
DEFAULT_LOG_SECONDS = 30
DEFAULT_LAUNCH_LOG_GRACE_SECONDS = 3


def parse_args():
    project_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(
        description="Build, install, launch, and collect logs for eisonAI on a physical iPhone."
    )
    parser.add_argument(
        "--device",
        help="Device name, UDID, identifier, serial number, or ECID. Defaults to the only connected iPhone.",
    )
    parser.add_argument(
        "--scheme",
        default=DEFAULT_SCHEME,
        help=f"Xcode scheme to build (default: {DEFAULT_SCHEME}).",
    )
    parser.add_argument(
        "--project",
        default=str(project_root / DEFAULT_PROJECT),
        help=f"Xcode project path (default: {DEFAULT_PROJECT}).",
    )
    parser.add_argument(
        "--bundle-id",
        default=DEFAULT_BUNDLE_ID,
        help=f"Bundle identifier to launch (default: {DEFAULT_BUNDLE_ID}).",
    )
    parser.add_argument(
        "--payload-url",
        help="Optional deeplink or payload URL passed to the app during launch.",
    )
    parser.add_argument(
        "--process-name",
        default=DEFAULT_PROCESS_NAME,
        help=f"Process name filter for syslog (default: {DEFAULT_PROCESS_NAME}).",
    )
    parser.add_argument(
        "--output-root",
        default=str(project_root / DEFAULT_OUTPUT_ROOT),
        help="Directory root for build and log artifacts.",
    )
    parser.add_argument(
        "--log-seconds",
        type=int,
        default=DEFAULT_LOG_SECONDS,
        help=(
            f"Seconds to keep collecting app logs after launch (default: {DEFAULT_LOG_SECONDS}). "
            "Use 0 to capture launch logs only."
        ),
    )
    parser.add_argument(
        "--stay-attached",
        action="store_true",
        help="Keep streaming app logs until interrupted.",
    )
    parser.add_argument(
        "--skip-build",
        action="store_true",
        help="Skip xcodebuild and reuse an existing .app from --app-path or the newest one under --output-root.",
    )
    parser.add_argument(
        "--app-path",
        help="Path to an existing .app bundle. Useful together with --skip-build.",
    )
    parser.add_argument(
        "--skip-install",
        action="store_true",
        help="Skip app installation and only launch/log.",
    )
    parser.add_argument(
        "--echo-logs",
        action="store_true",
        help="Mirror device log lines to stdout while writing them to file.",
    )
    parser.add_argument(
        "--list-devices",
        action="store_true",
        help="List connected iPhones and exit.",
    )
    return parser.parse_args()


def shutil_which(name):
    from shutil import which

    return which(name)


def ensure_tool(name):
    if shutil_which(name) is None:
        raise SystemExit(f"[ERROR] Required tool not found in PATH: {name}")


def timestamp_slug():
    return time.strftime("%Y%m%d-%H%M%S")


def ensure_dir(path):
    path.mkdir(parents=True, exist_ok=True)


def run_paths(output_root, slug):
    run_root = output_root / slug
    return {
        "run_root": run_root,
        "build_log": run_root / "build.log",
        "install_json": run_root / "install.json",
        "install_log": run_root / "install.log",
        "launch_json": run_root / "launch.json",
        "launch_log": run_root / "launch.log",
        "launch_payload": run_root / "launch_payload.json",
        "device_log": run_root / "device.log",
        "metadata": run_root / "run_metadata.json",
        "derived_data": run_root / "DerivedData",
    }


def run_logged(command, log_path, cwd):
    print(f"[RUN] {' '.join(command)}")
    with log_path.open("w", encoding="utf-8") as log_file:
        process = subprocess.Popen(
            command,
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        assert process.stdout is not None
        for line in process.stdout:
            sys.stdout.write(line)
            log_file.write(line)
        return_code = process.wait()
    if return_code != 0:
        raise RuntimeError(f"Command failed with exit code {return_code}: {' '.join(command)}")


def load_devices():
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as handle:
        json_path = Path(handle.name)
    try:
        command = ["xcrun", "devicectl", "list", "devices", "--json-output", str(json_path)]
        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode != 0:
            raise RuntimeError(result.stderr.strip() or result.stdout.strip() or "devicectl list devices failed")
        payload = json.loads(json_path.read_text(encoding="utf-8"))
        return payload.get("result", {}).get("devices", [])
    finally:
        json_path.unlink(missing_ok=True)


def normalize_device(device):
    connection = device.get("connectionProperties", {})
    details = device.get("deviceProperties", {})
    hardware = device.get("hardwareProperties", {})
    return {
        "name": details.get("name", ""),
        "identifier": device.get("identifier", ""),
        "udid": hardware.get("udid", ""),
        "ecid": str(hardware.get("ecid", "")),
        "serialNumber": hardware.get("serialNumber", ""),
        "deviceType": hardware.get("deviceType", ""),
        "marketingName": hardware.get("marketingName", ""),
        "platform": hardware.get("platform", ""),
        "osVersion": details.get("osVersionNumber", ""),
        "developerModeStatus": details.get("developerModeStatus", ""),
        "ddiServicesAvailable": details.get("ddiServicesAvailable", False),
        "pairingState": connection.get("pairingState", ""),
        "transportType": connection.get("transportType", ""),
        "tunnelState": connection.get("tunnelState", ""),
    }


def device_is_eligible(entry):
    if entry["deviceType"] not in {"iPhone", "iPad"}:
        return False
    if entry["pairingState"] != "paired":
        return False
    if entry["developerModeStatus"] != "enabled":
        return False
    return True


def connected_ios_devices():
    devices = []
    for device in load_devices():
        entry = normalize_device(device)
        if device_is_eligible(entry):
            devices.append(entry)
    return devices


def all_ios_devices():
    devices = []
    for device in load_devices():
        entry = normalize_device(device)
        if entry["deviceType"] in {"iPhone", "iPad"}:
            devices.append(entry)
    return devices


def format_device_error(prefix, devices):
    lines = [f"[ERROR] {prefix}", "Connected iPhone/iPad devices:"]
    for device in devices:
        lines.append(
            "  - "
            f"{device['name']} | {device['marketingName']} | iOS {device['osVersion']} | "
            f"developerMode={device['developerModeStatus']} | pairing={device['pairingState']} | "
            f"transport={device['transportType'] or 'unknown'} | tunnel={device['tunnelState'] or 'n/a'} | "
            f"ddi={device['ddiServicesAvailable']} | {device['udid']}"
        )
    return "\n".join(lines)


def select_device(selector):
    devices = connected_ios_devices()
    if selector:
        selector_lower = selector.lower()
        matches = [
            device
            for device in devices
            if selector_lower in {
                device["name"].lower(),
                device["identifier"].lower(),
                device["udid"].lower(),
                device["serialNumber"].lower(),
                device["ecid"].lower(),
            }
            or selector_lower in device["name"].lower()
            or selector_lower in device["udid"].lower()
        ]
        if len(matches) == 1:
            return matches[0]
        if not matches:
            raise SystemExit(f"[ERROR] No connected iPhone/iPad matched: {selector}")
        raise SystemExit(format_device_error("Multiple connected iPhone/iPad devices matched the selector.", matches))

    if len(devices) == 1:
        return devices[0]
    if not devices:
        ios_devices = all_ios_devices()
        if ios_devices:
            raise SystemExit(format_device_error("No eligible iPhone/iPad device was found.", ios_devices))
        raise SystemExit("[ERROR] No connected iPhone/iPad with Developer Mode enabled was found.")
    raise SystemExit(format_device_error("Multiple connected iPhone/iPad devices found. Pass --device.", devices))


def list_devices_and_exit():
    devices = all_ios_devices()
    if not devices:
        print("[INFO] No connected iPhone/iPad devices with Developer Mode enabled were found.")
        return
    for device in devices:
        print(
            f"{device['name']} | {device['marketingName']} | iOS {device['osVersion']} | "
            f"developerMode={device['developerModeStatus']} | pairing={device['pairingState']} | "
            f"transport={device['transportType'] or 'unknown'} | tunnel={device['tunnelState'] or 'n/a'} | "
            f"ddi={device['ddiServicesAvailable']} | {device['udid']}"
        )


def build_app(args, paths, device_udid):
    derived_data = paths["derived_data"]
    build_log = paths["build_log"]
    command = [
        "xcodebuild",
        "-project",
        args.project,
        "-scheme",
        args.scheme,
        "-destination",
        f"id={device_udid}",
        "-derivedDataPath",
        str(derived_data),
        "build",
    ]
    run_logged(command, build_log, cwd=Path(args.project).resolve().parent)
    apps = sorted((derived_data / "Build" / "Products").glob("*-iphoneos/*.app"))
    if len(apps) != 1:
        raise RuntimeError(
            f"Expected exactly one built .app, found {len(apps)} in {derived_data / 'Build' / 'Products'}"
        )
    return apps[0]


def locate_existing_app(app_path, output_root):
    if app_path:
        candidate = Path(app_path).expanduser().resolve()
        if candidate.suffix != ".app" or not candidate.exists():
            raise RuntimeError(f"Existing app bundle not found: {candidate}")
        return candidate

    apps = list(Path(output_root).expanduser().resolve().glob("*/DerivedData/Build/Products/*-iphoneos/*.app"))
    if not apps:
        raise RuntimeError("Could not find an existing .app under the output root.")
    return max(apps, key=lambda path: path.stat().st_mtime)


def devicectl_json(command, json_path, log_path, cwd):
    full_command = command + ["--json-output", str(json_path), "--log-output", str(log_path)]
    result = subprocess.run(full_command, cwd=cwd, capture_output=True, text=True)
    if result.returncode != 0:
        message = result.stderr.strip() or result.stdout.strip() or "devicectl command failed"
        raise RuntimeError(message)
    return json.loads(json_path.read_text(encoding="utf-8"))


def install_app(device, app_path, paths, cwd):
    return devicectl_json(
        [
            "xcrun",
            "devicectl",
            "device",
            "install",
            "app",
            "--device",
            device["udid"],
            str(app_path),
        ],
        paths["install_json"],
        paths["install_log"],
        cwd,
    )


def launch_app(args, device, paths, cwd):
    command = [
        "xcrun",
        "devicectl",
        "device",
        "process",
        "launch",
        "--device",
        device["udid"],
        "--terminate-existing",
    ]
    if args.payload_url:
        command.extend(["--payload-url", args.payload_url])
    command.append(args.bundle_id)
    return devicectl_json(
        command,
        paths["launch_json"],
        paths["launch_log"],
        cwd,
    )


def record_metadata(paths, args, device, app_path):
    metadata = {
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "device": device,
        "scheme": args.scheme,
        "project": str(Path(args.project).resolve()),
        "bundleID": args.bundle_id,
        "payloadURL": args.payload_url,
        "processName": args.process_name,
        "appPath": str(app_path) if app_path else None,
    }
    paths["metadata"].write_text(json.dumps(metadata, indent=2, ensure_ascii=False), encoding="utf-8")


def stream_device_logs(args, device, paths):
    log_path = paths["device_log"]
    log_path.write_text("", encoding="utf-8")
    command = ["idevicesyslog"]
    if device.get("transportType") == "localNetwork":
        command.append("--network")
    command.extend(
        [
            "--udid",
            device["udid"],
            "--process",
            args.process_name,
        ]
    )
    print(f"[INFO] Capturing device logs to {log_path}")
    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    stop_event = threading.Event()

    def forward():
        assert process.stdout is not None
        with log_path.open("w", encoding="utf-8") as log_file:
            log_file.write(
                f"# device={device['name']} udid={device['udid']} process={args.process_name} started_at={time.strftime('%Y-%m-%dT%H:%M:%S%z')}\n"
            )
            log_file.flush()
            for line in process.stdout:
                log_file.write(line)
                log_file.flush()
                if args.echo_logs:
                    sys.stdout.write(line)
                    sys.stdout.flush()
                if stop_event.is_set():
                    break

    thread = threading.Thread(target=forward, daemon=True)
    thread.start()
    return process, thread, stop_event


def stop_log_stream(process, thread, stop_event):
    stop_event.set()
    if process.poll() is None:
        process.send_signal(signal.SIGINT)
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
    thread.join(timeout=5)


def main():
    ensure_tool("xcodebuild")
    ensure_tool("xcrun")
    ensure_tool("idevicesyslog")

    args = parse_args()
    if args.list_devices:
        list_devices_and_exit()
        return

    device = select_device(args.device)
    project_dir = Path(args.project).resolve().parent
    output_root = Path(args.output_root).expanduser().resolve()
    ensure_dir(output_root)
    run_slug = timestamp_slug()
    paths = run_paths(output_root, run_slug)
    ensure_dir(paths["run_root"])

    print(
        f"[INFO] Device: {device['name']} | {device['marketingName']} | iOS {device['osVersion']} | {device['udid']}"
    )
    print(f"[INFO] Run root: {paths['run_root']}")

    if args.skip_build:
        if args.skip_install and not args.app_path:
            app_path = None
        else:
            app_path = locate_existing_app(args.app_path, args.output_root)
    else:
        app_path = build_app(args, paths, device["udid"])

    record_metadata(paths, args, device, app_path)

    if not args.skip_install:
        install_app(device, app_path, paths, project_dir)

    log_process = None
    log_thread = None
    stop_event = None
    try:
        log_process, log_thread, stop_event = stream_device_logs(args, device, paths)
        time.sleep(1)

        launch_payload = launch_app(args, device, paths, project_dir)
        paths["launch_payload"].write_text(
            json.dumps(launch_payload, indent=2, ensure_ascii=False),
            encoding="utf-8",
        )

        if args.stay_attached:
            print("[INFO] Streaming logs. Press Ctrl-C to stop.")
            while True:
                time.sleep(1)
        else:
            capture_seconds = max(args.log_seconds, DEFAULT_LAUNCH_LOG_GRACE_SECONDS)
            time.sleep(capture_seconds)
    except KeyboardInterrupt:
        print("\n[INFO] Stopping log capture.")
    finally:
        if log_process is not None and log_thread is not None and stop_event is not None:
            stop_log_stream(log_process, log_thread, stop_event)

    print(f"[DONE] Artifacts written to {paths['run_root']}")
    print(f"[DONE] Device log: {paths['device_log']}")


if __name__ == "__main__":
    main()
