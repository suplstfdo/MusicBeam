# Controlling MusicBeam via Art-Net

MusicBeam listens for **ArtDMX** packets on **UDP port 6454**, **universe 0**, and reads
the first 7 DMX channels. Listening is opt-in: the **Art-Net (DMX)** toggle in the
MusicBeam UI must be on, otherwise packets are ignored.

## Channel map

| Channel | Value  | Meaning                                  |
|---------|--------|------------------------------------------|
| 1       | 0..10  | Effect index (see table below)           |
| 2       | 0..255 | Main colour — red                        |
| 3       | 0..255 | Main colour — green                      |
| 4       | 0..255 | Main colour — blue                       |
| 5       | 0..255 | Secondary colour — red                   |
| 6       | 0..255 | Secondary colour — green                 |
| 7       | 0..255 | Secondary colour — blue                  |

## Effects

| Index | Effect     | Uses main | Uses secondary |
|-------|------------|-----------|----------------|
| 0     | Blackout   | –         | –              |
| 1     | Strobe     | yes       | yes            |
| 2     | Scanner    | yes       | yes            |
| 3     | Moonflower | yes       | yes            |
| 4     | RGB Spot   | yes       | yes            |
| 5     | Derby      | yes       | yes            |
| 6     | Snowstorm  | yes       | no             |
| 7     | LaserBurst | yes       | yes            |
| 8     | Polygon    | yes       | yes            |
| 9     | Spinner    | yes       | yes            |
| 10    | Raindrops  | yes       | yes            |

## Semantics

- **Channel 1 is edge-triggered.** The effect is only switched when the value *changes*.
  Repeating the same value does nothing, so the user can still pick effects in the UI
  without the sender fighting them. To force a re-select, change the value.
  Values above 10 are ignored.
- **Colours are level-triggered** and applied on every frame while set.
- **Black means "not set".** If all three channels of a colour are 0, that colour is
  not applied: the main colour falls back to the effect's own hue controls, the
  secondary colour falls back to the main colour. Sending only a main colour therefore
  tints the whole effect; sending no colour leaves the look completely untouched.
  A colour can never black out an effect — use effect index 0 for that.
- **Brightness and saturation are carried through.** `(128, 0, 0)` renders the effect
  dim red, `(255, 128, 128)` renders it washed-out red. Fades and pulses an effect
  performs on its own are scaled by this brightness, not replaced by it.
- **State persists.** MusicBeam has no timeout; the last received values stay active
  until new ones arrive or the toggle is switched off. Channels missing from a short
  frame keep their previous value.
- There is no feedback, discovery, or ArtPoll support — send and forget.

## Packet format

A minimal ArtDMX packet is 18 header bytes followed by the channel data:

| Offset | Size | Value                                                     |
|--------|------|-----------------------------------------------------------|
| 0      | 8    | `"Art-Net\0"`                                             |
| 8      | 2    | OpCode `0x5000`, **little-endian** → bytes `00 50`        |
| 10     | 2    | Protocol version `14`, **big-endian** → bytes `00 0E`     |
| 12     | 2    | Sequence, Physical — both `0` is fine                     |
| 14     | 2    | Universe `0` → bytes `00 00`                              |
| 16     | 2    | Channel count, **big-endian** (`8`)                       |
| 18     | n    | Channel data, channel 1 first                             |

Send **8 channels** (the 7 used ones plus one zero pad): the Art-Net spec requires an
even count. MusicBeam derives the channel count from the actual UDP payload size, so
the payload must really contain those bytes.

## Example

```python
import socket

def send(effect, main=(0, 0, 0), secondary=(0, 0, 0), host="127.0.0.1"):
    channels = bytes([effect]) + bytes(main) + bytes(secondary) + b"\x00"
    packet = (
        b"Art-Net\x00"
        + (0x5000).to_bytes(2, "little")     # OpCode: ArtDMX
        + (14).to_bytes(2, "big")            # protocol version
        + bytes([0, 0])                      # sequence, physical
        + bytes([0, 0])                      # universe 0
        + len(channels).to_bytes(2, "big")   # channel count
        + channels
    )
    socket.socket(socket.AF_INET, socket.SOCK_DGRAM).sendto(packet, (host, 6454))

send(3, main=(255, 0, 0), secondary=(0, 0, 255))  # Moonflower, red and blue
send(0)                                           # blackout
```

Recommended sending pattern: emit a packet whenever a value changes, plus a refresh
every few hundred milliseconds so a MusicBeam instance that started late or missed a
UDP packet catches up. Remember that a repeated channel 1 value will not re-trigger
the effect switch, so refreshing is safe.
