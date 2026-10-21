"""Plays a one- or two-finger touch gesture on an Android device through a virtual HID
multi-touch screen, so camera gestures can be checked on real hardware without a hand.
`adb shell input` only has single-pointer swipes and SELinux blocks writing to the real
touchscreen node, so this registers a 2-contact HID digitizer with Android's `hid` shell command
(uhid; the kernel's hid-multitouch driver turns it into a direct-touch input device) and streams
reports through it.

Usage (device in portrait, app in front):
  python3 -I apps/lab3d/tools/device_gesture.py orbit|pinch|pan|one-finger
Coordinates are screen pixels in the device's natural (portrait) orientation (SM-P200 1200x1920).
"""
import argparse
import os
import json
import subprocess
import tempfile

SCREEN = (1200, 1920)
STEPS = 24
FRAME_MS = 16

# name -> one waypoint list per finger (equal counts; segments get equal time). The 3D view is
# the top ~45% of the portrait screen on SM-P200.
GESTURES = {
    "orbit": [[(450, 560), (750, 560)], [(750, 560), (1050, 560)]],                   # move together
    "pinch": [[(520, 560), (220, 560)], [(680, 560), (980, 560)]],                    # spread -> zoom in
    "pan": [[(560, 480), (520, 480), (520, 760)], [(640, 480), (680, 480), (680, 760)]],  # small spread, then move
    "one-finger": [[(400, 600), (900, 600)]],                                          # empty-view drag
}

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
        sx = round(x / (SCREEN[0] - 1) * 32767)
        sy = round(y / (SCREEN[1] - 1) * 32767)
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


def commands(paths):
    lines = [{"id": 1, "command": "register", "name": "Open Physics test touch", "vid": 0x18D1, "pid": 0x7A01,
              "bus": "usb", "descriptor": DESCRIPTOR}, {"id": 1, "command": "delay", "duration": 1500}]
    for step in range(STEPS + 1):
        t = step / STEPS
        contacts = []
        for slot in range(2):
            if slot < len(paths):
                contacts.append((True, slot, *point_at(paths[slot], t)))
            else:
                contacts.append((False, slot, 0, 0))
        lines.append({"id": 1, "command": "report", "report": report(contacts)})
        lines.append({"id": 1, "command": "delay", "duration": FRAME_MS})
    end = [(False, slot, *paths[min(slot, len(paths) - 1)][-1]) for slot in range(2)]
    lines.append({"id": 1, "command": "report", "report": report(end)})
    lines.append({"id": 1, "command": "delay", "duration": 300})
    return lines


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("gesture", choices=sorted(GESTURES))
    args = parser.parse_args()
    script = "\n".join(json.dumps(line) for line in commands(GESTURES[args.gesture])) + "\n"
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
