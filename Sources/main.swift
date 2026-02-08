import Foundation
import IOKit

// MARK: - SMC Interface

private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

private struct SMCKeyData {
    var key: UInt32 = 0
    var vers: SMCVersion = SMCVersion()
    var pLimitData: SMCPLimitData = SMCPLimitData()
    var keyInfo: SMCKeyInfoData = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
        (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

private func fourCharCode(_ str: String) -> UInt32 {
    var result: UInt32 = 0
    for c in str.utf8 { result = (result << 8) | UInt32(c) }
    return result
}

final class SMCReader {
    private var conn: io_connect_t = 0

    init?() {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        let kr = IOServiceOpen(service, mach_task_self_, 0, &conn)
        IOObjectRelease(service)
        guard kr == kIOReturnSuccess else { return nil }
    }

    deinit { IOServiceClose(conn) }

    func readFloat(_ key: String) -> Float? {
        guard let raw = readRawKey(key), raw.size >= 4 else { return nil }
        // Apple Silicon stores flt values in little-endian
        let bits = UInt32(raw.bytes[0])
            | UInt32(raw.bytes[1]) << 8
            | UInt32(raw.bytes[2]) << 16
            | UInt32(raw.bytes[3]) << 24
        return Float(bitPattern: bits)
    }

    private struct RawValue {
        var size: UInt32
        var bytes: [UInt8]
    }

    private func readRawKey(_ keyStr: String) -> RawValue? {
        let key = fourCharCode(keyStr)
        let structSize = MemoryLayout<SMCKeyData>.size

        // Step 1: get key info
        var infoIn = SMCKeyData()
        infoIn.key = key
        infoIn.data8 = 9 // kSMCGetKeyInfo
        var infoOut = SMCKeyData()
        var outSize = structSize
        guard IOConnectCallStructMethod(conn, 2,
            &infoIn, structSize, &infoOut, &outSize) == kIOReturnSuccess
        else { return nil }

        let dataSize = infoOut.keyInfo.dataSize
        guard dataSize > 0 else { return nil }

        // Step 2: read key value
        var readIn = SMCKeyData()
        readIn.key = key
        readIn.keyInfo.dataSize = dataSize
        readIn.data8 = 5 // kSMCReadKey
        var readOut = SMCKeyData()
        outSize = structSize
        guard IOConnectCallStructMethod(conn, 2,
            &readIn, structSize, &readOut, &outSize) == kIOReturnSuccess
        else { return nil }

        var bytes = [UInt8]()
        withUnsafeBytes(of: &readOut.bytes) { ptr in
            for i in 0..<Int(dataSize) { bytes.append(ptr[i]) }
        }
        return RawValue(size: dataSize, bytes: bytes)
    }
}

// MARK: - Battery Info from IOKit

struct BatteryInfo {
    var voltage: Int         // mV
    var amperage: Int        // mA (positive = charging, negative = discharging)
    var isCharging: Bool
    var fullyCharged: Bool
    var externalConnected: Bool
    var currentCapacity: Int // percent
    var adapterWatts: Int    // rated adapter wattage
    var adapterVoltage: Int  // mV
    var adapterCurrent: Int  // mA (negotiated max)
    var timeToFull: Int      // minutes, 65535 = not applicable
    var timeToEmpty: Int     // minutes, 65535 = not applicable
}

func readBatteryInfo() -> BatteryInfo? {
    let service = IOServiceGetMatchingService(
        kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    guard service != 0 else { return nil }
    defer { IOObjectRelease(service) }

    var props: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0)
        == kIOReturnSuccess,
        let dict = props?.takeRetainedValue() as? [String: Any]
    else { return nil }

    func intVal(_ key: String) -> Int { dict[key] as? Int ?? 0 }
    func boolVal(_ key: String) -> Bool { dict[key] as? Bool ?? false }

    var adapterWatts = 0
    var adapterVoltage = 0
    var adapterCurrent = 0
    if let adapter = dict["AdapterDetails"] as? [String: Any] {
        adapterWatts = adapter["Watts"] as? Int ?? 0
        adapterVoltage = adapter["AdapterVoltage"] as? Int ?? 0
        adapterCurrent = adapter["Current"] as? Int ?? 0
    }

    return BatteryInfo(
        voltage: intVal("Voltage"),
        amperage: intVal("Amperage"),
        isCharging: boolVal("IsCharging"),
        fullyCharged: boolVal("FullyCharged"),
        externalConnected: boolVal("ExternalConnected"),
        currentCapacity: intVal("CurrentCapacity"),
        adapterWatts: adapterWatts,
        adapterVoltage: adapterVoltage,
        adapterCurrent: adapterCurrent,
        timeToFull: intVal("AvgTimeToFull"),
        timeToEmpty: intVal("AvgTimeToEmpty")
    )
}

// MARK: - Main

func displayPowerInfo(smc: SMCReader?) {
    guard let battery = readBatteryInfo() else {
        fputs("Error: Could not read battery information.\n", stderr)
        return
    }

    // Read SMC power values
    let systemPower = smc?.readFloat("PSTR").map(Double.init)  // total system/platform power

    // Battery power from IOKit: V(mV) × I(mA) / 1,000,000 = W
    // Positive amperage = charging (battery absorbing power)
    // Negative amperage = discharging (battery providing power)
    let batteryPowerRaw = Double(battery.voltage) * Double(battery.amperage) / 1_000_000.0

    // Determine power flow
    let batteryDischarging = battery.amperage < 0
    let batteryCharging = battery.amperage > 0 && battery.isCharging

    // System power consumption
    let systemW: Double
    if let sp = systemPower, sp > 0 {
        systemW = sp
    } else if batteryDischarging {
        systemW = abs(batteryPowerRaw)
    } else {
        systemW = 0
    }

    // Power source breakdown
    let fromCharger: Double
    let fromBattery: Double

    if battery.externalConnected {
        if batteryDischarging {
            fromBattery = abs(batteryPowerRaw)
            fromCharger = max(0, systemW - fromBattery)
        } else {
            fromCharger = systemW
            fromBattery = 0
        }
    } else {
        fromCharger = 0
        fromBattery = systemW
    }

    let batteryChargingW = batteryCharging ? batteryPowerRaw : 0
    let chargerTotalOutput = battery.externalConnected ? fromCharger + batteryChargingW : 0

    let snapshot = PowerSnapshot(
        systemW: systemW,
        fromCharger: fromCharger,
        fromBattery: fromBattery,
        batteryPercent: battery.currentCapacity,
        isCharging: batteryCharging,
        isDischarging: batteryDischarging,
        fullyCharged: battery.fullyCharged,
        externalConnected: battery.externalConnected,
        batteryChargingW: batteryChargingW,
        batteryDischargingW: abs(batteryPowerRaw),
        chargerTotalOutput: chargerTotalOutput,
        adapterWatts: battery.adapterWatts,
        timeToFull: battery.timeToFull,
        timeToEmpty: battery.timeToEmpty
    )

    render(snapshot)
}

// Parse arguments
var watchInterval: Double? = nil
let args = CommandLine.arguments
var i = 1
while i < args.count {
    if args[i] == "-w" {
        if i + 1 < args.count, let val = Double(args[i + 1]), val > 0 {
            watchInterval = val
            i += 2
        } else {
            watchInterval = 1.0
            i += 1
        }
    } else {
        fputs("Usage: watt [-w [seconds]]\n", stderr)
        exit(1)
    }
}

let smc = SMCReader()

if let interval = watchInterval {
    // Clear screen, then loop with cursor-home to avoid flicker
    print("\u{1B}[2J", terminator: "")
    fflush(stdout)
    while true {
        print("\u{1B}[H", terminator: "")
        fflush(stdout)
        displayPowerInfo(smc: smc)
        // Clear any leftover lines from previous output
        print("\u{1B}[J", terminator: "")
        fflush(stdout)
        Thread.sleep(forTimeInterval: interval)
    }
} else {
    displayPowerInfo(smc: smc)
}
