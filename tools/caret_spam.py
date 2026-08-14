#!/usr/bin/env python3
"""Hold the German ^ key (physical grave / left of 1) to spam:
Space press-release, then right-click, until the key is released.

Runs indefinitely until Ctrl+C.
"""

from __future__ import annotations

import select
import sys
import threading
import time

from evdev import InputDevice, ecodes, list_devices
from pynput.keyboard import Controller as KeyController
from pynput.keyboard import Key
from pynput.mouse import Button
from pynput.mouse import Controller as MouseController

# German keyboard: ^ / ° key left of 1 (Linux KEY_GRAVE)
TRIGGER_CODE = ecodes.KEY_GRAVE
DELAY_S = 0.05  # ~50ms between Space+right-click cycles

holding = False
running = True
kb = KeyController()
ms = MouseController()


def find_keyboards() -> list[InputDevice]:
    devices: list[InputDevice] = []
    for path in list_devices():
        try:
            dev = InputDevice(path)
        except OSError:
            continue
        keys = dev.capabilities().get(ecodes.EV_KEY, [])
        if TRIGGER_CODE in keys and ecodes.KEY_A in keys:
            devices.append(dev)
    return devices


def listen_loop(devices: list[InputDevice]) -> None:
    global holding, running
    while running:
        ready, _, _ = select.select(devices, [], [], 0.25)
        for dev in ready:
            try:
                for event in dev.read():
                    if event.type != ecodes.EV_KEY or event.code != TRIGGER_CODE:
                        continue
                    # 1=press, 2=repeat, 0=release
                    holding = event.value != 0
            except OSError as exc:
                print(f"device lost ({dev.path}): {exc}", flush=True)
                running = False
                return


def spam_loop() -> None:
    while running:
        if holding:
            kb.press(Key.space)
            kb.release(Key.space)
            ms.click(Button.right, 1)
            if DELAY_S > 0:
                time.sleep(DELAY_S)
        else:
            time.sleep(0.001)


def main() -> None:
    global running
    devices = find_keyboards()
    if not devices:
        print("No keyboard with KEY_GRAVE found. Are you in the 'input' group?", flush=True)
        sys.exit(1)

    print("caret_spam running (Ctrl+C to quit)", flush=True)
    print("Hold German ^ (grave / left of 1) → Space + right-click until release", flush=True)
    for dev in devices:
        print(f"  listening: {dev.name} ({dev.path})", flush=True)

    listener = threading.Thread(target=listen_loop, args=(devices,), daemon=True)
    spammer = threading.Thread(target=spam_loop, daemon=True)
    listener.start()
    spammer.start()

    try:
        while running and listener.is_alive():
            time.sleep(0.5)
    except KeyboardInterrupt:
        pass
    finally:
        running = False
        print("stopped.", flush=True)


if __name__ == "__main__":
    main()
