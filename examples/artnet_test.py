#!/usr/bin/env python3
"""Test MusicBeam's Art-Net effect and colour control by sending ArtDMX frames.

Enable the "Art-Net (DMX)" toggle in MusicBeam first, then:

    python3 artnet_test.py 3                  select effect 3
    python3 artnet_test.py 0                  blackout / no effect
    python3 artnet_test.py 3 red              effect 3 in red
    python3 artnet_test.py 3 f00 00f          effect 3, main red, secondary blue
    python3 artnet_test.py demo               cycle through all effects, then blackout
    python3 artnet_test.py 3 --host 10.0.0.2  send to another machine

Colours are hex (``f00``, ``ff0000``, ``#ff0000``) or one of the names in
COLORS. Black means "not set": the effect keeps using its own hue controls.
"""
import argparse
import socket
import sys
import time

EFFECT_COUNT = 11  # effect indices 0..10, 0 = Blackout
BLACK = (0, 0, 0)
COLORS = {
    "black": BLACK,
    "red": (255, 0, 0),
    "green": (0, 255, 0),
    "blue": (0, 0, 255),
    "cyan": (0, 255, 255),
    "magenta": (255, 0, 255),
    "yellow": (255, 255, 0),
    "orange": (255, 128, 0),
    "white": (255, 255, 255),
}


def color(text):
    """Parse a colour name or hex string into an (r, g, b) triple."""
    if text.lower() in COLORS:
        return COLORS[text.lower()]
    digits = text.lstrip("#")
    if len(digits) == 3:  # shorthand, f80 -> ff8800
        digits = "".join(d * 2 for d in digits)
    if len(digits) != 6:
        raise argparse.ArgumentTypeError(f"not a colour: {text}")
    try:
        return tuple(int(digits[i:i + 2], 16) for i in (0, 2, 4))
    except ValueError:
        raise argparse.ArgumentTypeError(f"not a colour: {text}")


def send(effect, main, secondary, host):
    channels = bytes([effect]) + bytes(main) + bytes(secondary)
    packet = bytearray(b"Art-Net\x00")
    packet += (0x5000).to_bytes(2, "little")        # OpCode: ArtDMX
    packet += (14).to_bytes(2, "big")               # protocol version
    packet += bytes([0, 0])                         # sequence, physical
    packet += bytes([0, 0])                         # universe 0
    packet += len(channels).to_bytes(2, "big")      # DMX channel count
    packet += channels                              # 1 = effect, 2-4 main RGB, 5-7 secondary RGB
    socket.socket(socket.AF_INET, socket.SOCK_DGRAM).sendto(packet, (host, 6454))
    print(f"sent effect index {effect}, main {main}, secondary {secondary} to {host}")


parser = argparse.ArgumentParser(
    description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
)
parser.add_argument("effect", help="effect index 0..%d, or 'demo'" % (EFFECT_COUNT - 1))
parser.add_argument("main", nargs="?", type=color, default=BLACK, help="main colour")
parser.add_argument("secondary", nargs="?", type=color, default=BLACK, help="secondary colour")
parser.add_argument("--host", default="127.0.0.1", help="target address (default: %(default)s)")
args = parser.parse_args()

if args.effect == "demo":
    for effect in list(range(EFFECT_COUNT)) + [0]:
        send(effect, args.main, args.secondary, args.host)
        time.sleep(2)
else:
    try:
        effect = int(args.effect)
    except ValueError:
        sys.exit(f"not an effect index: {args.effect}")
    send(effect, args.main, args.secondary, args.host)
