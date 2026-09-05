import Testing
@testable import SonosRemote

@Suite struct SmokeTests {
    @Test @MainActor func panelControllerToggles() {
        let panel = PanelController()
        #expect(!panel.isPresented)
        panel.toggle()
        #expect(panel.isPresented)
        panel.close()
        #expect(!panel.isPresented)
    }
}
