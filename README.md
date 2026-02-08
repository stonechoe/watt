# watt

A macOS CLI utility that displays real-time power consumption of your MacBook, broken down by source (charger vs battery).

## Requirements

- macOS 12.0+
- Apple Silicon Mac (uses little-endian SMC float decoding)
- Swift 5.9+

## Build

```
swift build -c release
```

The binary is at `.build/release/watt`.

## Install

```
cp .build/release/watt /usr/local/bin/
```

## Usage

```
watt            # one-shot display
watt -w         # watch mode (1s refresh)
watt -w 0.5     # watch mode (custom interval)
```

No sudo required.

Output is color-coded when writing to a terminal, and automatically plain when piped or redirected. Set `NO_COLOR=1` to force plain output.

### Example output

**On battery:**

```
System    9.49 W
  Charger  0.00 W
  Battery  9.49 W

████████████████░░░░ 79%  Discharging · 4h 17m remaining
```

**On charger, charging:**

```
System   11.6 W
  Charger  11.6 W
  Battery  0.00 W

██████████████░░░░░░ 72%  Charging at 45.5 W · 1h 12m to full
60W adapter · delivering 57.1 W
```

**On charger, not charging (e.g. optimized charging hold at 80%):**

```
System   11.6 W
  Charger  11.6 W
  Battery  0.00 W

████████████████░░░░ 80%  Not charging
60W adapter · delivering 11.6 W
```

**Heavy load, battery supplementing charger:**

```
System   58.3 W
  Charger  48.3 W
  Battery  10.0 W

█████████████░░░░░░░ 65%  Supplementing charger at 10.0 W
60W adapter · delivering 48.3 W
```

## How it works

The tool reads from two data sources, both via IOKit (no sudo needed):

1. **SMC (System Management Controller)** -- reads the `PSTR` key for real-time platform power consumption in watts. This is the same hardware sensor data that `powermetrics` uses.

2. **AppleSmartBattery IOKit service** -- reads battery voltage, current, charge percentage, charging state, time estimates, and adapter details.

The power source breakdown is derived from the battery current direction:

| Battery current | Meaning | From Charger | From Battery |
|---|---|---|---|
| Negative | Discharging | 0 (or partial if charger connected) | System power |
| Zero | Idle | System power | 0 |
| Positive | Charging | System power | 0 |

When the charger is connected, total charger delivery = system power + battery charging power.

## Limitations

- Built for Apple Silicon Macs. Intel Macs use big-endian SMC float encoding and would need the byte order flipped.
- The `PSTR` SMC key measures SoC/platform power. Peripheral power (e.g. external USB devices drawing bus power) may not be fully captured.
- Time remaining estimates come from the battery gauge IC and can fluctuate with workload changes.
