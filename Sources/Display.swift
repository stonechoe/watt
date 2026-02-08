import Foundation

// MARK: - Color Support

private let colorEnabled: Bool = {
    if ProcessInfo.processInfo.environment["NO_COLOR"] != nil { return false }
    return isatty(STDOUT_FILENO) != 0
}()

private func ansi(_ code: String) -> String {
    colorEnabled ? "\u{1B}[\(code)m" : ""
}

private let reset = ansi("0")

private func bold(_ s: String) -> String {
    "\(ansi("1"))\(s)\(reset)"
}

private func dim(_ s: String) -> String {
    "\(ansi("2"))\(s)\(reset)"
}

private func colored(_ s: String, _ code: String) -> String {
    "\(ansi(code))\(s)\(reset)"
}

// MARK: - Formatting

func formatWatts(_ w: Double) -> String {
    if abs(w) >= 10 {
        return String(format: "%.1f W", w)
    } else {
        return String(format: "%.2f W", w)
    }
}

func formatTime(_ minutes: Int) -> String {
    if minutes <= 0 || minutes >= 65535 { return "--" }
    let h = minutes / 60
    let m = minutes % 60
    if h > 0 {
        return "\(h)h \(m)m"
    }
    return "\(m)m"
}

// MARK: - Battery Bar

private func batteryColor(_ percent: Int) -> String {
    if percent > 50 { return "32" }      // green
    if percent > 20 { return "33" }      // yellow
    return "31"                           // red
}

private func batteryBar(percent: Int) -> String {
    let width = 20
    let filled = max(0, min(width, percent * width / 100))
    let empty = width - filled
    let bar = String(repeating: "\u{2588}", count: filled)
            + String(repeating: "\u{2591}", count: empty)
    let code = batteryColor(percent)
    return colored(bar, code)
}

// MARK: - PowerSnapshot

struct PowerSnapshot {
    var systemW: Double
    var fromCharger: Double
    var fromBattery: Double

    var batteryPercent: Int
    var isCharging: Bool
    var isDischarging: Bool
    var fullyCharged: Bool
    var externalConnected: Bool

    var batteryChargingW: Double
    var batteryDischargingW: Double
    var chargerTotalOutput: Double

    var adapterWatts: Int
    var timeToFull: Int
    var timeToEmpty: Int
}

// MARK: - Render

func render(_ s: PowerSnapshot) {
    // Power values — right-align watt strings to keep columns tidy
    let sysStr = formatWatts(s.systemW)
    let chgStr = formatWatts(s.fromCharger)
    let batStr = formatWatts(s.fromBattery)

    let maxLen = max(sysStr.count, chgStr.count, batStr.count)

    func padW(_ v: String) -> String {
        String(repeating: " ", count: maxLen - v.count) + v
    }

    print("\(dim("System"))   \(bold(padW(sysStr)))")
    print("  \(dim("Charger"))  \(bold(padW(chgStr)))")
    print("  \(dim("Battery"))  \(bold(padW(batStr)))")

    print()

    // Battery bar + status line
    let bar = batteryBar(percent: s.batteryPercent)
    let pct = colored("\(s.batteryPercent)%", batteryColor(s.batteryPercent))

    var status = "\(bar) \(pct)"

    if s.externalConnected {
        if s.isCharging {
            let time = formatTime(s.timeToFull)
            status += "  \(dim("Charging at")) \(bold(formatWatts(s.batteryChargingW)))"
            if time != "--" {
                status += " \(dim("\u{00B7} \(time) to full"))"
            }
        } else if s.isDischarging {
            status += "  \(dim("Supplementing charger at")) \(bold(formatWatts(s.batteryDischargingW)))"
        } else if s.fullyCharged {
            status += "  \(dim("Fully charged"))"
        } else {
            status += "  \(dim("Not charging"))"
        }
    } else {
        let time = formatTime(s.timeToEmpty)
        status += "  \(dim("Discharging"))"
        if time != "--" {
            status += " \(dim("\u{00B7} \(time) remaining"))"
        }
    }

    print(status)

    // Charger info line
    if s.externalConnected {
        let adapter = "\(s.adapterWatts)W adapter"
        let delivering = "delivering \(formatWatts(s.chargerTotalOutput))"
        print("\(dim(adapter)) \(dim("\u{00B7}")) \(dim(delivering))")
    }
}
