# EnglishBuddy

EnglishBuddy is an original iPhone app for offline English speaking practice, inspired by the direct-call interaction model popularized by apps like CallAnnie while using its own product identity, visuals, and implementation.

## Current shape

- Native iPhone app built with `SwiftUI`
- `AVFoundation + Speech` for on-device voice capture, speech recognition, and playback
- Local long-term memory stored in `Application Support`
- `LiteRT-LM` bridge in Objective-C++ / C++ for device inference
- `Gemma 4 E2B` bundled into the app package as the built-in base model
- Chat and Tutor call modes with local feedback after each conversation

## Product behavior

- The bundled base model is validated automatically during launch.
- The app is designed to open straight into a call-first home screen.
- Microphone and speech permissions are requested only when the first call begins.
- History and settings remain available, but the primary experience is the live call flow.

## Generate the project

```sh
xcodegen generate
```

## Local build notes

This machine needed an iOS platform download before `xcodebuild` could find a simulator destination:

```sh
xcodebuild -downloadPlatform iOS
```

After that, use an Apple Silicon simulator target or a generic device build:

```sh
xcodebuild -project EnglishBuddy.xcodeproj -scheme EnglishBuddy -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

For simulator builds, the vendored LiteRT runtime currently ships an `arm64` simulator slice only, so the project excludes `x86_64` for `EnglishBuddy` automatically. Use a concrete Apple Silicon simulator destination, for example:

```sh
xcodebuild -project EnglishBuddy.xcodeproj -scheme EnglishBuddy -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16 Pro' CODE_SIGNING_ALLOWED=NO build
```

Tests also need a concrete simulator destination:

```sh
xcodebuild -project EnglishBuddy.xcodeproj -scheme EnglishBuddy -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16 Pro' CODE_SIGNING_ALLOWED=NO test
```

## Repository layout

- `EnglishBuddy/App`: app bootstrap and root state
- `EnglishBuddy/Core`: models, storage, orchestration, speech, inference wrapper, model readiness
- `EnglishBuddy/Features`: SwiftUI screens and the coach avatar
- `EnglishBuddy/Bridge`: Objective-C++ / C++ bridge to LiteRT-LM
- `EnglishBuddyTests`: unit tests for storage, feedback logic, orchestration, and model readiness
