import Testing
@testable import SonosKit

@Suite struct SOAPTests {
    @Test func envelopeWrapsActionAndArguments() {
        let xml = SOAP.envelope(action: "SetBass", arguments: [("InstanceID", "0"), ("DesiredBass", "-3")])
        #expect(xml.hasPrefix(#"<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>"#))
        #expect(xml.contains(#"<u:SetBass xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1"><InstanceID>0</InstanceID><DesiredBass>-3</DesiredBass></u:SetBass>"#))
        #expect(xml.hasSuffix("</s:Body></s:Envelope>"))
    }

    @Test func argumentsAreEscaped() {
        #expect(SOAP.escape("a<b&c>\"d'") == "a&lt;b&amp;c&gt;&quot;d&apos;")
    }

    @Test func extractsValuesFromFixtures() {
        #expect(SOAP.value(named: "CurrentBass", in: Fixtures.string("soap_GetBass.xml")) == "-3")
        #expect(SOAP.value(named: "CurrentValue", in: Fixtures.string("soap_GetEQ_SubGain.xml")) == "-2")
        #expect(SOAP.value(named: "CurrentLoudness", in: Fixtures.string("soap_GetLoudness.xml")) == "1")
        #expect(SOAP.value(named: "CurrentBass", in: Fixtures.string("soap_SetBass.xml")) == nil)
    }

    @Test func extractsFaultCode() {
        #expect(SOAP.faultCode(in: Fixtures.string("soap_fault.xml")) == 402)
        #expect(SOAP.faultCode(in: Fixtures.string("soap_GetBass.xml")) == nil)
    }
}
