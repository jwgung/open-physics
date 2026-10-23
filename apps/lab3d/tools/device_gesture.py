"""Plays a one- or two-finger touch gesture on an Android device through a virtual HID
multi-touch screen, so camera gestures can be checked on real hardware without a hand.
`adb shell input` only has single-pointer swipes and SELinux blocks writing to the real
touchscreen node, so this registers a 2-contact HID digitizer with Android's `hid` shell command
(uhid; the kernel's hid-multitouch driver turns it into a direct-touch input device) and streams
reports through it.

Usage (app in front; the app is landscape only):
  python3 -I apps/lab3d/tools/device_gesture.py orbit|pinch|pinch-fixed|pan|one-finger|drag-cancel
  python3 -I apps/lab3d/tools/device_gesture.py tap --at X,Y
Coordinates are landscape screen pixels (SM-P200 1920x1200, origin top-left as the app is shown).
The HID screen reports in the device's natural (portrait) orientation, so each point is turned
by the current display rotation (`dumpsys input` SurfaceOrientation) before it is sent.
"""
import argparse
import os
import json
import math
import re
import subprocess
import tempfile

VIRTUAL_NAME = "Open Physics test touch"   # the HID screen registered below
NATURAL = (1200, 1920)   # SM-P200 natural (portrait) panel size in pixels
STEPS = 24
FRAME_MS = 16

# name -> one waypoint list per finger (equal counts; segments get equal time). The 3D view is the
# whole landscape screen with the sidebar closed (Task 2d); the gestures stay clear of the title
# bar, key cards (top-left) and action buttons (bottom-right).
GESTURES = {
    "orbit": [[(660, 650), (960, 650)], [(960, 650), (1260, 650)]],                   # move together
    "pinch": [[(880, 650), (580, 650)], [(1040, 650), (1340, 650)]],                  # spread -> zoom in
    "pinch-fixed": [[(880, 650), (580, 650)], [(1040, 650), (1040, 650)]],            # finger 1 held still, only 0 moves -> zoom in
    "pan": [[(920, 560), (880, 560), (880, 840)], [(1000, 560), (1040, 560), (1040, 840)]],  # small spread, then move
    "one-finger": [[(700, 700), (1200, 700)]],                                         # empty-view drag
    # Task 2b: drag the incline box (default start, front view, 20 deg) down the incline and land a
    # second finger halfway: the drag is cancelled and the box goes back to its start.
    "drag-cancel": [[(1296, 350), (1120, 415), (960, 475)], [(500, 900), (500, 900), (500, 900)]],
}
# Fraction of the gesture after which each finger touches down (default: from the start).
STARTS = {"drag-cancel": [0.0, 0.5]}


def parse_rotation(text: str) -> int:
    """Quarter turns (0-3) of the built-in touchscreen from `dumpsys input` text.

    Each input device has its own `SurfaceOrientation:` line under its touch mapper, so the value is
    read from the device blocks ("Device N: name") of touch screens, not the first line anywhere
    (a second display, the virtual screen this script registers on an earlier run, a stylus). The
    block of this script's own virtual device is skipped. Exits with an error when no touch screen
    block shows an orientation, or when several disagree: a silent 0 would send every point
    to the wrong place on a rotated screen.
    """
    blocks = re.split(r"(?m)^\s*Device -?\d+:", text)[1:]
    found = set()
    for block in blocks:
        if VIRTUAL_NAME in block.splitlines()[0]:
            continue
        if "Touch Input Mapper" not in block and "touchscreen" not in block.lower():
            continue
        found.update(int(m) for m in re.findall(r"SurfaceOrientation:\s*(\d)", block))
    if not found:
        raise SystemExit("device_gesture: no touch screen with a SurfaceOrientation in `dumpsys input` "
                         "(is a device connected and awake, and is the screen on?)")
    if len(found) > 1:
        raise SystemExit(f"device_gesture: touch screens disagree on SurfaceOrientation ({sorted(found)}); "
                         "cannot tell which one the app is shown on")
    return found.pop()


def rotation() -> int:
    """Current display rotation in quarter turns (0-3) from `dumpsys input`."""
    text = subprocess.run(["adb", "shell", "dumpsys input"], check=True, capture_output=True, text=True).stdout
    return parse_rotation(text)


def to_natural(point, quarter_turns):
    """Shown (rotated) screen pixels -> the natural-orientation pixels the HID screen reports."""
    x, y = point
    w, h = NATURAL
    if quarter_turns == 1:
        return w - 1 - y, x
    if quarter_turns == 2:
        return w - 1 - x, h - 1 - y
    if quarter_turns == 3:
        return y, h - 1 - x
    return x, y


FINGER = [
    0x05, 0x0D, 0x09, 0x22, 0xA1, 0x02,                    # Digitizer: Finger, logical collection
    0x09, 0x42, 0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95, 0x01, 0x81, 0x02,  # Tip Switch (1 bit)
    0x95, 0x07, 0x81, 0x03,                                # 7 bit padding
    0x09, 0x51, 0x25, 0x7F, 0x75, 0x08, 0x95, 0x01, 0x81, 0x02,  # Contact Identifier
    0x05, 0x01, 0x26, 0xFF, 0x7F, 0x75, 0x10, 0x95, 0x01,  # Generic Desktop, 0..32767, 16 bit
    0x09, 0x30, 0x81, 0x02, 0x09, 0x31, 0x81, 0x02,        # X, Y
    0xC0,
]
DESCRIPTOR = [0x05, 0x0D, 0x09, 0x04, 0xA1, 0x01, 0x85, 0x01] + FINGER + FINGER + [
    0x05, 0x0D, 0x09, 0x54, 0x25, 0x7F, 0x75, 0x08, 0x95, 0x01, 0x81, 0x02,  # Contact Count
    0xC0,
]


def report(contacts):
    """contacts: list of (touching, id, x_px, y_px) for both slots."""
    data = [0x01]
    for touching, contact_id, x, y in contacts:
        sx = round(x / (NATURAL[0] - 1) * 32767)
        sy = round(y / (NATURAL[1] - 1) * 32767)
        data += [1 if touching else 0, contact_id, sx & 0xFF, sx >> 8, sy & 0xFF, sy >> 8]
    data.append(sum(1 for c in contacts if c[0]))
    return data


def point_at(waypoints, t):
    """Position at time t (0..1) along equal-time segments."""
    segments = len(waypoints) - 1
    index = min(int(t * segments), segments - 1)
    local = t * segments - index
    (x0, y0), (x1, y1) = waypoints[index], waypoints[index + 1]
    return x0 + (x1 - x0) * local, y0 + (y1 - y0) * local


def commands(paths, starts, quarter_turns):
    lines = [{"id": 1, "command": "register", "name": VIRTUAL_NAME, "vid": 0x18D1, "pid": 0x7A01,
              "bus": "usb", "descriptor": DESCRIPTOR}, {"id": 1, "command": "delay", "duration": 1500}]
    for step in range(STEPS + 1):
        t = step / STEPS
        contacts = []
        for slot in range(2):
            if slot < len(paths) and t >= starts[slot]:
                contacts.append((True, slot, *to_natural(point_at(paths[slot], t), quarter_turns)))
            else:
                contacts.append((False, slot, 0, 0))
        lines.append({"id": 1, "command": "report", "report": report(contacts)})
        lines.append({"id": 1, "command": "delay", "duration": FRAME_MS})
    end = [(False, slot, *to_natural(paths[min(slot, len(paths) - 1)][-1], quarter_turns)) for slot in range(2)]
    lines.append({"id": 1, "command": "report", "report": report(end)})
    lines.append({"id": 1, "command": "delay", "duration": 300})
    return lines


def parse_tap_point(parser: argparse.ArgumentParser, text: str | None) -> tuple[float, float]:
    """tap --at X,Y: required, two finite numbers inside the landscape screen (SM-P200 1920x1200)."""
    if not text:
        parser.error("tap needs --at X,Y")
    pieces = text.split(",")
    try:
        x, y = (float(v) for v in pieces)
    except ValueError:
        parser.error(f"--at must be two numbers X,Y (got {text!r})")
    if not (math.isfinite(x) and math.isfinite(y)):
        parser.error("--at must be finite numbers")
    width, height = NATURAL[1], NATURAL[0]
    if not (0 <= x < width and 0 <= y < height):
        parser.error(f"--at {x:g},{y:g} is outside the {width}x{height} landscape screen")
    return x, y


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("gesture", choices=sorted(GESTURES) + ["tap"])
    parser.add_argument("--at", help="tap: X,Y in landscape screen pixels")
    args = parser.parse_args()
    if args.gesture == "tap":
        x, y = parse_tap_point(parser, args.at)
        paths, starts = [[(x, y), (x, y)]], [0.0, 0.0]
    else:
        paths, starts = GESTURES[args.gesture], STARTS.get(args.gesture, [0.0, 0.0])
    script = "\n".join(json.dumps(line) for line in commands(paths, starts, rotation())) + "\n"
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as handle:
        handle.write(script)
        local = handle.name
    try:
        remote = "/data/local/tmp/opgesture.json"
        subprocess.run(["adb", "push", "-q", local, remote], check=True)
        subprocess.run(["adb", "shell", f"hid {remote}"], check=True)
    finally:
        os.unlink(local)


if __name__ == "__main__":
    main()
