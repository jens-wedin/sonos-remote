import Foundation
import Testing
@testable import SonosRemote

@Suite struct AcknowledgementsTests {
    @Test func sparklesLicenseShipsInsideTheApp() throws {
        let url = try #require(Bundle.main.url(forResource: "Acknowledgements", withExtension: "txt"), "Acknowledgements.txt must be a bundle resource")
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("Sparkle"))
        #expect(text.contains("Permission is hereby granted, free of charge"))
    }
}
