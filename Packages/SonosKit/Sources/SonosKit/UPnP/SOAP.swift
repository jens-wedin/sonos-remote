import Foundation

/// Just enough SOAP for Sonos RenderingControl. No general XML parser: the responses are tiny and flat.
enum SOAP {
    static let serviceURN = "urn:schemas-upnp-org:service:RenderingControl:1"
    static let controlPath = "/MediaRenderer/RenderingControl/Control"

    static func envelope(action: String, arguments: [(name: String, value: String)]) -> String {
        let args = arguments.map { "<\($0.name)>\(escape($0.value))</\($0.name)>" }.joined()
        return #"<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:\#(action) xmlns:u="\#(serviceURN)">\#(args)</u:\#(action)></s:Body></s:Envelope>"#
    }

    static func escape(_ value: String) -> String {
        var out = ""
        for character in value {
            switch character {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            default: out.append(character)
            }
        }
        return out
    }

    /// Text between `<name>` and `</name>`, or nil.
    static func value(named name: String, in xml: String) -> String? {
        guard let open = xml.range(of: "<\(name)>"),
              let close = xml.range(of: "</\(name)>", range: open.upperBound..<xml.endIndex) else { return nil }
        return String(xml[open.upperBound..<close.lowerBound])
    }

    static func faultCode(in xml: String) -> Int? {
        guard xml.contains("<s:Fault>") else { return nil }
        return value(named: "errorCode", in: xml).flatMap { Int($0) }
    }
}
