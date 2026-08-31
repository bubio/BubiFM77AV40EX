# Repository Guidelines

## Project Structure & Module Organization

The repository is currently in its planning stage. `docs/BluePrint.md` is the authoritative requirements document and must not be edited. As implementation begins, use the planned Flutter layout:

- `lib/app/`: startup, navigation, and dependency injection
- `lib/features/`: vertical features such as sessions, media, debugger, and settings
- `lib/emulator/`: emulator APIs and shared domain models
- `lib/platform/`: FFI, WebAssembly, textures, SoLoud, and persistence adapters
- `lib/shared/`: genuinely reusable widgets and utilities
- `test/`: tests mirroring the paths under `lib/`

Keep dependencies directed from `app` to features and platform implementations, and from features/platform to the emulator API. Do not modify the upstream eFM77AV40EX emulation core.

## Build, Test, and Development Commands

Flutter must be run through FVM. Once `pubspec.yaml` is added, use:

```sh
fvm flutter pub get       # resolve dependencies
fvm flutter run -d macos  # run the primary development target
fvm flutter analyze       # run static analysis
fvm flutter test          # run the complete test suite
fvm dart format .         # format Dart sources and tests
```

Keep local and CI build steps equivalent. Add a documented script if packaging or native-core compilation becomes multi-step.

## Coding Style & Naming Conventions

Follow standard Dart formatting (two-space indentation) and analyzer rules. Use `lower_snake_case.dart` for files, `UpperCamelCase` for types, and `lowerCamelCase` for members and providers. Co-locate a feature's state, controller, and Riverpod providers; avoid ceremonial UseCase, Repository, or Event layers. Do not route high-frequency video, PCM, or input data through Riverpod.

## Testing Guidelines

Use `flutter_test`; name files `*_test.dart` and mirror production paths (for example, `test/features/session/session_controller_test.dart`). Add focused unit tests for emulator boundaries and state transitions, plus widget tests for user-visible behavior. Run analysis, formatting, and all tests before submitting changes.

## Commit & Pull Request Guidelines

No Git history is available yet, so use concise imperative subjects such as `Add session lifecycle controller`. Keep commits focused. Do not commit or push unless explicitly instructed. Pull requests should explain behavior and architecture impact, list verification commands, link relevant issues, and include screenshots for UI changes. Never commit BIOS files, commercial game images, credentials, or machine-specific paths.

## Project Constraints

Target macOS first, then Linux, Windows, Android, and iOS. Do not introduce SDL. Support Japanese and English UI text, follow native platform conventions, and use semantic versioning. Place future private development documentation under the planned `docs/dev/` submodule rather than in `README.md`.
