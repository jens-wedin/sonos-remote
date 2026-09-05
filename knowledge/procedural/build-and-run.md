# Build and run

Xcode 26 is installed but `xcode-select` points at the Command Line Tools. Export this in every shell:

    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

## Package

    cd Packages/SonosKit
    swift test                       # all tests
    swift test --filter ReducerTests # one suite
    swift run sonosctl list          # against the real speakers (Terminal needs Local Network permission)

## App

    xcodegen generate                # writes SonosRemote.xcodeproj (git-ignored)
    xcodebuild -project SonosRemote.xcodeproj -scheme SonosRemote -configuration Debug -derivedDataPath .build/xcode build 2>&1 | tail -3
    open .build/xcode/Build/Products/Debug/SonosRemote.app
    xcodebuild test -project SonosRemote.xcodeproj -scheme SonosRemote -destination 'platform=macOS' -derivedDataPath .build/xcode 2>&1 | tail -5

Quit a running copy before launching a new build: `pkill -x SonosRemote`.
