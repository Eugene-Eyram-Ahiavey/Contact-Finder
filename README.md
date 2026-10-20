# Evangelism Caller ID

A mobile application that helps church evangelism teams identify known contacts when they call back, without requiring every person to be manually saved in the user's personal phone address book.

## The Problem

Evangelism teams collect contact details from people they meet during outreach. When a team member later calls someone and that person returns the call, the incoming number appears as unknown — because it was recorded in notes or spreadsheets, not saved as a phone contact. The team member must scramble to search through their lists while the phone is ringing.

## Feature 1: Evangelism Contact Caller Identification

The first (and currently only) feature is **caller identification for evangelism contacts**.

**Core capabilities:**
- Maintain a searchable collection of evangelism contacts (name, phone, location, notes, follow-up history).
- Identify known contacts during incoming calls using OS-level caller identification APIs.
- Search contacts by name, phone number, or location.
- Import existing contact lists from CSV/Excel.

**What this app does NOT do:** AI chatbots, church management, attendance, donations, VoIP, or replace the phone's native dialer.

## Current Status

| Milestone | Description | Status |
|-----------|-------------|--------|
| 0 | Feasibility assessment & project foundation | **Complete** |
| 1 | Technical foundation | **Complete** |
| 2 | Prove real caller identification | **Next** (Requires physical device) |
| 3 | Contact data model & management | Not started |
| 4 | Integrate contacts with caller ID | Not started |
| 5 | Import existing lists | Not started |
| 6 | Polished mobile UX | Not started |
| 7 | Release readiness | Not started |

## Development Setup

### Prerequisites

- **Flutter** 3.47.7+ (stable channel)
- **Dart** 3.13.5+
- **Android SDK** 36 (API level 36) with build-tools 36.0.0
- **Xcode** 26.5+ with CocoaPods 1.16.2
- **Android Studio** (for Android emulator and SDK management)
- Physical Android and iOS devices (required for caller ID testing — emulators cannot receive real phone calls)

### Environment Setup

1. Clone this repository.
2. Run `flutter pub get` to install dependencies.
3. Ensure `flutter doctor` reports no errors for Android and iOS toolchains.

**Known issue:** `adb` may not be on your PATH even if Android SDK is installed. See [docs/FEASIBILITY.md](docs/FEASIBILITY.md) for the fix.

### Running the App

```bash
# Check environment
flutter doctor -v

# Run on connected Android device
flutter run -d <device-id>

# Run on connected iOS device
flutter run -d <device-id>

# List connected devices
flutter devices
```

### Running Tests

```bash
flutter test
flutter analyze
```

## Architecture Overview

See [docs/FEASIBILITY.md](docs/FEASIBILITY.md) for the technical feasibility assessment and proposed architecture.

**Key architectural decision:** Caller identification requires native platform code on both Android and iOS. The Flutter app handles the UI and contact data management. Native Kotlin (Android) and Swift (iOS) code handles OS-level caller ID integration via Flutter platform channels.

## Project Structure

```
evangelism_caller_id/
├── lib/                      # Flutter/Dart application code
│   ├── main.dart             # App entry point
│   └── services/
│       └── caller_id_service.dart # Platform channel bridge
├── android/                  # Android native project
│   └── app/src/main/kotlin/  # Native Kotlin code (CallScreeningService, MainActivity)
├── ios/                      # iOS native project
│   └── Runner/               # Native Swift code (AppDelegate)
├── test/                     # Flutter widget and unit tests
│   ├── caller_id_service_test.dart
│   └── widget_test.dart
├── docs/                     # Project documentation
│   └── FEASIBILITY.md        # Platform feasibility assessment
└── pubspec.yaml              # Flutter dependencies
```

## Known Blockers

1. **No physical devices available right now** — Incoming-call caller ID cannot be simulated on software emulators; a physical Android phone or iPhone is required to verify real cellular calls in Milestone 2.

## License

Private project. Not open source.
