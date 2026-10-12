// cornix-hid: Cornix の Vial raw HID (usage page 0xFF60 / usage 0x61) と
// 32 バイトのレポートをやり取りする macOS 用の最小ブリッジ。
//
// 標準入出力の行プロトコル:
//   起動時  -> "READY {json}" または "ERROR <理由>"（終了コード 1）
//   "SEND <64桁hex>" -> "RECV <64桁hex>" または "ERROR <理由>"
//
// 安全のため、送信できるコマンドは下の許可リストに限定する。
// Cornix のファームウェア (RMK 0.8 系) は bootloader 移行や EEPROM リセットを
// ロックなしで実行してしまうため、それらはここで必ず拒否する。
import Foundation
import IOKit.hid

let MSG_LEN = 32
let VENDOR_ID = 0xE118

// 許可するコマンドかどうか。拒否理由を返す（nil なら許可）。
func rejectReason(_ m: [UInt8]) -> String? {
    switch m[0] {
    case 0x01: return nil                               // get_protocol_version
    case 0x02: return [0x01, 0x02, 0x04].contains(m[1]) ? nil : "get_keyboard_value sub \(m[1])"
    case 0x04: return nil                               // dynamic_keymap_get_keycode
    case 0x05:                                          // dynamic_keymap_set_keycode
        let kc = (UInt16(m[4]) << 8) | UInt16(m[5])
        return (0x7C00...0x7C0F).contains(kc) ? "boot 系キーコード 0x\(String(kc, radix: 16))" : nil
    case 0x0C, 0x0D: return nil                         // macro count / buffer size
    case 0x0E, 0x0F:                                    // macro get / set buffer
        return m[3] <= 28 ? nil : "macro buffer size \(m[3]) > 28"
    case 0x11, 0x12: return nil                         // layer count / get keymap buffer
    case 0xFE:
        switch m[1] {
        case 0x00, 0x01, 0x02, 0x03, 0x05, 0x09, 0x0A, 0x0B: return nil
        case 0x04:                                      // set_encoder
            let kc = (UInt16(m[5]) << 8) | UInt16(m[6])
            return (0x7C00...0x7C0F).contains(kc) ? "boot 系キーコード 0x\(String(kc, radix: 16))" : nil
        case 0x0D:                                      // dynamic entry: count / tap dance / combo
            return (0x00...0x04).contains(m[2]) ? nil : "dynamic entry op \(m[2])"
        default: return "vial command 0x\(String(m[1], radix: 16))"
        }
    default: return "via command 0x\(String(m[0], radix: 16))"
    }
}

struct BridgeError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

final class Bridge {
    let dev: IOHIDDevice
    var inbuf = [UInt8](repeating: 0, count: 64)
    var resp: [UInt8]? = nil

    init(dev: IOHIDDevice) {
        self.dev = dev
        IOHIDDeviceScheduleWithRunLoop(dev, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(dev, &inbuf, inbuf.count, { ctx, _, _, _, _, report, len in
            let me = Unmanaged<Bridge>.fromOpaque(ctx!).takeUnretainedValue()
            me.resp = Array(UnsafeBufferPointer(start: report, count: len))
        }, ctx)
    }

    func send(_ msg: [UInt8]) -> Result<[UInt8], BridgeError> {
        // 前のコマンドの遅延応答を捨てる
        CFRunLoopRunInMode(.defaultMode, 0.005, true)
        resp = nil
        var m = msg
        let r = IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, 0, &m, m.count)
        if r != kIOReturnSuccess { return .failure(BridgeError("setReport 0x\(String(UInt32(bitPattern: r), radix: 16))")) }
        let deadline = Date().addingTimeInterval(1.0)
        while resp == nil && Date() < deadline {
            CFRunLoopRunInMode(.defaultMode, 0.01, true)
        }
        guard let out = resp else { return .failure(BridgeError("timeout")) }
        return .success(Array(out.prefix(MSG_LEN)) + [UInt8](repeating: 0, count: max(0, MSG_LEN - out.count)))
    }
}

func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined() }

func parseHex(_ s: String) -> [UInt8]? {
    let chars = Array(s)
    guard chars.count == MSG_LEN * 2 else { return nil }
    var out = [UInt8]()
    for i in stride(from: 0, to: chars.count, by: 2) {
        guard let v = UInt8(String(chars[i...i + 1]), radix: 16) else { return nil }
        out.append(v)
    }
    return out
}

func emit(_ s: String) {
    print(s)
    fflush(stdout)
}

// --self-test: デバイスに触れずに許可リストの判定だけを確認する
if CommandLine.arguments.contains("--self-test") {
    func msg(_ b: [UInt8]) -> [UInt8] { b + [UInt8](repeating: 0, count: MSG_LEN - b.count) }
    let mustReject: [[UInt8]] = [
        [0x06], [0x0A], [0x0B], [0x10], [0x13, 0, 0, 2], [0x03, 0x02], [0x07], [0x09], [0x02, 0x03],
        [0xFE, 0x06], [0xFE, 0x07], [0xFE, 0x08], [0xFE, 0x0C], [0xFE, 0x0D, 0x05], [0xFE, 0x0D, 0x06],
        [0x05, 0, 0, 0, 0x7C, 0x00], [0x05, 0, 0, 0, 0x7C, 0x03], [0xFE, 0x04, 0, 0, 1, 0x7C, 0x01],
        [0x0F, 0, 0, 29],
    ]
    let mustAllow: [[UInt8]] = [
        [0x01], [0x02, 0x04], [0x04, 0, 0, 0], [0x05, 0, 0, 0, 0x00, 0x04], [0x0E, 0, 0, 28], [0x0F, 0, 0, 28],
        [0x11], [0x12, 0, 0, 28], [0xFE, 0x00], [0xFE, 0x02, 0, 0], [0xFE, 0x0B, 7, 0, 200, 0], [0xFE, 0x0D, 0x04, 0],
    ]
    var ok = true
    for m in mustReject where rejectReason(msg(m)) == nil { print("NOT REJECTED: \(m)"); ok = false }
    for m in mustAllow where rejectReason(msg(m)) != nil { print("NOT ALLOWED: \(m)"); ok = false }
    print(ok ? "self-test OK" : "self-test FAILED")
    exit(ok ? 0 : 1)
}

let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(mgr, [
    kIOHIDVendorIDKey: VENDOR_ID,
    kIOHIDPrimaryUsagePageKey: 0xFF60,
    kIOHIDPrimaryUsageKey: 0x61,
] as CFDictionary)
let devices = (IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>) ?? []
guard let dev = devices.first else {
    emit("ERROR Cornix の raw HID が見つかりません（Bluetooth/USB の接続を確認してください）")
    exit(1)
}
let openResult = IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
guard openResult == kIOReturnSuccess else {
    emit("ERROR デバイスを開けません 0x\(String(UInt32(bitPattern: openResult), radix: 16))")
    exit(1)
}

func prop(_ key: String) -> Any { IOHIDDeviceGetProperty(dev, key as CFString) ?? NSNull() }
let info: [String: Any] = [
    "product": prop(kIOHIDProductKey),
    "transport": prop(kIOHIDTransportKey),
    "serial": prop(kIOHIDSerialNumberKey),
    "vendor_id": prop(kIOHIDVendorIDKey),
    "product_id": prop(kIOHIDProductIDKey),
]
let infoJSON = String(data: try! JSONSerialization.data(withJSONObject: info), encoding: .utf8)!
emit("READY \(infoJSON)")

let bridge = Bridge(dev: dev)
while let line = readLine() {
    let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
    guard parts.count == 2, parts[0] == "SEND", let msg = parseHex(parts[1]) else {
        emit("ERROR 不正な行")
        continue
    }
    if let reason = rejectReason(msg) {
        emit("ERROR 拒否: \(reason)")
        continue
    }
    switch bridge.send(msg) {
    case .success(let out): emit("RECV \(hex(out))")
    case .failure(let err): emit("ERROR \(err.message)")
    }
}
IOHIDDeviceClose(dev, IOOptionBits(kIOHIDOptionsTypeNone))
