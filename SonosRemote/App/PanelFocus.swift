/// Panel-level keyboard focus targets. The play/pause button is where the first keypress lands
/// on the main screen; on any other screen (which has no play/pause button) the Back button is
/// the fallback so default focus always has somewhere to land.
enum PanelFocus: Hashable {
    case playPause
    case back
}
