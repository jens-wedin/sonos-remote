import Foundation
import Testing
@testable import SonosKit

@Suite struct UPnPClientTests {
    let transport = FakeTransport()
    var client: UPnPClient { UPnPClient(transport: transport) }

    @Test func getBassPostsSoapToPort1400AndParsesValue() async throws {
        transport.respond(whenPathContains: "RenderingControl", body: Fixtures.data("soap_GetBass.xml"))
        let bass = try await client.bass(address: "192.168.1.105")
        #expect(bass == -3)
        let request = try #require(transport.requests.first)
        #expect(request.method == "POST")
        #expect(request.url.absoluteString == "http://192.168.1.105:1400/MediaRenderer/RenderingControl/Control")
        #expect(request.headers["SOAPACTION"] == "\"urn:schemas-upnp-org:service:RenderingControl:1#GetBass\"")
        #expect(request.headers["Content-Type"] == "text/xml; charset=\"utf-8\"")
        let body = String(decoding: try #require(request.body), as: UTF8.self)
        #expect(body.contains("<u:GetBass "))
        #expect(body.contains("<InstanceID>0</InstanceID>"))
    }

    @Test func settersSendDesiredValues() async throws {
        transport.respond(whenPathContains: "RenderingControl", body: Fixtures.data("soap_SetBass.xml"))
        try await client.setBass(4, address: "192.168.1.105")
        try await client.setTreble(-2, address: "192.168.1.105")
        try await client.setLoudness(false, address: "192.168.1.105")
        try await client.setEQ(type: "SubGain", value: 3, address: "192.168.1.105")
        let bodies = transport.requests.map { String(decoding: $0.body ?? Data(), as: UTF8.self) }
        #expect(bodies[0].contains("<DesiredBass>4</DesiredBass>"))
        #expect(bodies[1].contains("<DesiredTreble>-2</DesiredTreble>"))
        #expect(bodies[2].contains("<Channel>Master</Channel><DesiredLoudness>0</DesiredLoudness>"))
        #expect(bodies[3].contains("<EQType>SubGain</EQType><DesiredValue>3</DesiredValue>"))
    }

    @Test func faultBecomesTypedErrorAndEqTreats402AsUnavailable() async throws {
        transport.respond(whenPathContains: "RenderingControl", status: 500, body: Fixtures.data("soap_fault.xml"))
        await #expect(throws: UPnPError.fault(code: 402)) {
            _ = try await client.bass(address: "192.168.1.105")
        }
        let value = try await client.eq(type: "NightMode", address: "192.168.1.105")
        #expect(value == nil)
    }

    @Test func hasSubUsesCrossover() async throws {
        transport.respond(whenPathContains: "RenderingControl", body: Data(SOAP.envelope(action: "GetEQResponse", arguments: [("CurrentValue", "99")]).utf8))
        #expect(try await client.hasSub(address: "192.168.1.105"))
        transport.respond(whenPathContains: "RenderingControl", body: Data(SOAP.envelope(action: "GetEQResponse", arguments: [("CurrentValue", "0")]).utf8))
        #expect(!(try await client.hasSub(address: "192.168.1.28")))
        let body = String(decoding: transport.requests[0].body ?? Data(), as: UTF8.self)
        #expect(body.contains("<EQType>SubCrossover</EQType>"))
    }

    @Test func eqSettingsReadsEverythingAndSkipsSubWithoutOne() async throws {
        transport.respond(whenPathContains: "RenderingControl", sequence: [
            StubResponse(body: Fixtures.data("soap_GetBass.xml")),
            StubResponse(body: Data(SOAP.envelope(action: "GetTrebleResponse", arguments: [("CurrentTreble", "2")]).utf8)),
            StubResponse(body: Fixtures.data("soap_GetLoudness.xml")),
            StubResponse(body: Fixtures.data("soap_GetEQ_SubGain.xml")),
        ])
        let withSub = try await client.eqSettings(address: "192.168.1.105", hasSub: true)
        #expect(withSub == EQSettings(bass: -3, treble: 2, loudness: true, subGain: -2))
        #expect(transport.requests.count == 4)

        let other = FakeTransport()
        other.respond(whenPathContains: "RenderingControl", sequence: [
            StubResponse(body: Fixtures.data("soap_GetBass.xml")),
            StubResponse(body: Data(SOAP.envelope(action: "GetTrebleResponse", arguments: [("CurrentTreble", "0")]).utf8)),
            StubResponse(body: Fixtures.data("soap_GetLoudness.xml")),
        ])
        let noSub = try await UPnPClient(transport: other).eqSettings(address: "192.168.1.28", hasSub: false)
        #expect(noSub.subGain == nil)
        #expect(other.requests.count == 3)
    }

    @Test func applyWritesOnlyWhatExists() async throws {
        transport.respond(whenPathContains: "RenderingControl", body: Fixtures.data("soap_SetBass.xml"))
        try await client.apply(EQSettings(bass: 1, treble: 2, loudness: true, subGain: nil), address: "192.168.1.28")
        #expect(transport.requests.count == 3)
        try await client.apply(EQSettings(bass: 1, treble: 2, loudness: true, subGain: -5), address: "192.168.1.105")
        #expect(transport.requests.count == 7)
    }
}
