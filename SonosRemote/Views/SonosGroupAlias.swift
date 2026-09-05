import SonosKit

/// SonosKit exports a namespace enum literally named `SonosKit` (see `SonosKit.swift`). That
/// declaration shadows the module name for qualified lookup, so `SonosKit.Group` fails to
/// typecheck in any file that also `import SwiftUI` (whose own `Group` view type collides with
/// the bare, unqualified name `Group`). This file has no SwiftUI import, so the reference below
/// is unambiguous and gives the view files an unambiguous alias to use instead.
typealias SonosGroup = Group
