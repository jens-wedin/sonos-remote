import Foundation

enum Screen: Hashable, CaseIterable {
    case main, favorites, sound, group, settings

    /// Uppercase header title; `main` uses the wordmark label instead.
    var title: String {
        switch self {
        case .main: "SONOS"
        case .favorites: "FAVORITES"
        case .sound: "SOUND"
        case .group: "GROUP"
        case .settings: "SETTINGS"
        }
    }

    var accessibilityName: String {
        switch self {
        case .main: "Main"
        case .favorites: "Favorites"
        case .sound: "Sound"
        case .group: "Group"
        case .settings: "Settings"
        }
    }

    /// The header icons, in order. `group` is reached from the rooms header, not the icons.
    static let iconScreens: [Screen] = [.favorites, .sound, .settings]

    var systemImage: String {
        switch self {
        case .main: "hifispeaker.2"
        case .favorites: "heart"
        case .sound: "slider.horizontal.3"
        case .group: "link"
        case .settings: "gearshape"
        }
    }
}
