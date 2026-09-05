import Foundation

public enum UPnPError: Error, Hashable, Sendable {
    case fault(code: Int)
    case http(status: Int)
    case missingValue(String)
}

/// EQ over UPnP RenderingControl on port 1400. Everything here is per player, not per group.
public struct UPnPClient: Sendable {
    public static let port = 1400

    private let transport: any Transport

    public init(transport: any Transport) {
        self.transport = transport
    }

    public func bass(address: String) async throws -> Int {
        try await intValue("CurrentBass", action: "GetBass", arguments: [("InstanceID", "0")], address: address)
    }

    public func setBass(_ value: Int, address: String) async throws {
        _ = try await call(action: "SetBass", arguments: [("InstanceID", "0"), ("DesiredBass", String(value))], address: address)
    }

    public func treble(address: String) async throws -> Int {
        try await intValue("CurrentTreble", action: "GetTreble", arguments: [("InstanceID", "0")], address: address)
    }

    public func setTreble(_ value: Int, address: String) async throws {
        _ = try await call(action: "SetTreble", arguments: [("InstanceID", "0"), ("DesiredTreble", String(value))], address: address)
    }

    public func loudness(address: String) async throws -> Bool {
        try await intValue("CurrentLoudness", action: "GetLoudness", arguments: [("InstanceID", "0"), ("Channel", "Master")], address: address) == 1
    }

    public func setLoudness(_ on: Bool, address: String) async throws {
        _ = try await call(action: "SetLoudness", arguments: [("InstanceID", "0"), ("Channel", "Master"), ("DesiredLoudness", on ? "1" : "0")], address: address)
    }

    /// nil when the player answers fault 402 (EQ type not supported on this model).
    public func eq(type: String, address: String) async throws -> Int? {
        do {
            return try await intValue("CurrentValue", action: "GetEQ", arguments: [("InstanceID", "0"), ("EQType", type)], address: address)
        } catch UPnPError.fault(code: 402) {
            return nil
        }
    }

    public func setEQ(type: String, value: Int, address: String) async throws {
        _ = try await call(action: "SetEQ", arguments: [("InstanceID", "0"), ("EQType", type), ("DesiredValue", String(value))], address: address)
    }

    /// A sub is attached when the crossover frequency is non-zero (Amp with a wired sub reports 99).
    public func hasSub(address: String) async throws -> Bool {
        (try await eq(type: "SubCrossover", address: address) ?? 0) > 0
    }

    public func eqSettings(address: String, hasSub: Bool) async throws -> EQSettings {
        let bass = try await bass(address: address)
        let treble = try await treble(address: address)
        let loudness = try await loudness(address: address)
        let subGain = hasSub ? try await eq(type: "SubGain", address: address) : nil
        return EQSettings(bass: bass, treble: treble, loudness: loudness, subGain: subGain)
    }

    public func apply(_ eq: EQSettings, address: String) async throws {
        try await setBass(eq.bass, address: address)
        try await setTreble(eq.treble, address: address)
        try await setLoudness(eq.loudness, address: address)
        if let subGain = eq.subGain {
            try await setEQ(type: "SubGain", value: subGain, address: address)
        }
    }

    // MARK: Plumbing

    private func intValue(_ name: String, action: String, arguments: [(name: String, value: String)], address: String) async throws -> Int {
        let xml = try await call(action: action, arguments: arguments, address: address)
        guard let text = SOAP.value(named: name, in: xml), let value = Int(text) else {
            throw UPnPError.missingValue(name)
        }
        return value
    }

    private func call(action: String, arguments: [(name: String, value: String)], address: String) async throws -> String {
        guard let url = URL(string: "http://\(address):\(Self.port)\(SOAP.controlPath)") else {
            preconditionFailure("Bad UPnP URL for \(address)")
        }
        let request = APIRequest(
            method: "POST",
            url: url,
            headers: [
                "Content-Type": "text/xml; charset=\"utf-8\"",
                "SOAPACTION": "\"\(SOAP.serviceURN)#\(action)\"",
            ],
            body: Data(SOAP.envelope(action: action, arguments: arguments).utf8)
        )
        let response = try await transport.send(request)
        let xml = String(decoding: response.body, as: UTF8.self)
        guard (200..<300).contains(response.status) else {
            if let code = SOAP.faultCode(in: xml) { throw UPnPError.fault(code: code) }
            throw UPnPError.http(status: response.status)
        }
        return xml
    }
}
