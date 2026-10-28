# Qara (קָרָא) — Outreach Caller ID

A mobile application that helps church evangelism teams identify known contacts when they call back, without requiring every person to be manually saved in the user's personal phone address book. Named after the Hebrew word *Qara* (קָרָא) — "to call, summon, or proclaim".

## The Problem

Evangelism teams collect contact details from people they meet during outreach. When a team member later calls someone and that person returns the call, the incoming number appears as unknown — because it was recorded in notes or spreadsheets, not saved as a phone contact. The team member must scramble to search through their lists while the phone is ringing.

## Feature 1: Evangelism Contact Caller Identification

The core capability of Qara is **instant caller identification for evangelism contacts**.

**Core capabilities:**
- Maintain a searchable collection of evangelism contacts (name, phone, location, notes, follow-up history).
- Identify known contacts during incoming calls using OS-level caller identification APIs:
  - **Android:** Native `CallScreeningService` with custom floating overlay card ("✝ QARA • OUTREACH CONTACT").
  - **iOS:** Native `CallKit` `CXCallDirectoryProvider` with App Group pre-indexing (`Qara Caller ID: [Name] • [Location]`).
- Search contacts by name, phone number (local or international), or location.
- Import existing contact lists from CSV, Excel (.xlsx), or raw text from Apple Notes / Google Keep / WhatsApp.
- Single-tap phone dialing via native phone dialer.

**What this app does NOT do:** AI chatbots, church management, attendance, donations, VoIP, or replace the phone's native dialer.

## Current Status

| Milestone | Description | Status |
|-----------|-------------|--------|
| 0 | Feasibility assessment & project foundation | **Complete** |
| 1 | Technical foundation | **Complete** |
| 2 | Prove real caller identification architecture | **Complete** |
| 3 | Contact data model & management | **Complete** |
| 4 | Integrate contacts with caller ID | **Complete** |
| 5 | Import existing lists (CSV, Excel, Notes) | **Complete** |
| 6 | Polished mobile UX & Status Banners | **Complete** |
| 7 | Release readiness & iOS CallKit Extension | **Complete** |
| 8 | Call Centers (Projects & Gems campaign workspaces) | **Complete** |

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

Caller identification requires native platform code on both Android and iOS:

### Android Implementation
- **Mechanism:** `android.telecom.CallScreeningService` (`EvangelismCallScreeningService.kt`)
- **Query Strategy:** Directly queries the local SQLite database (`qara.db`) in <10ms upon incoming call broadcast without launching Flutter engine.
- **Overlay:** Draws a high-priority system floating card via `WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY` displaying:
  `✝ QARA • OUTREACH CONTACT`
  `[Name] • [Location]`
  `[Notes snippet]`

### iOS Implementation
- **Mechanism:** Apple CallKit `CXCallDirectoryProvider` (`CallDirectoryHandler.swift`)
- **App Group Container:** `group.com.mode.qara` shares `contacts_directory.json` between Flutter Runner and the extension.
- **Query Strategy:** Numbers are pre-indexed as strictly ascending `Int64` E.164 values. Apple's system dialer renders:
  `Qara Caller ID: [Name] • [Location]`
- **Sync Pipeline:** Every time contacts are loaded, created, imported, edited, or deleted in SQLite, Flutter invokes `CallerIdService.syncContactsToCallDirectory()`. The native host writes the App Group directory and prompts `CXCallDirectoryManager.reloadExtension()`.
- **Enabling on iPhone:** Navigate to `Settings ➔ Phone ➔ Call Blocking & Identification ➔ Qara` (toggle ON).

## Project Structure

```
qara/
├── lib/                      # Flutter/Dart cross-platform code
│   ├── main.dart             # App entry point (loads Call Centers Hub)
│   ├── database/
│   │   └── app_database.dart # Local SQLite database (qara.db v2 with Call Centers)
│   ├── models/
│   │   ├── call_center.dart  # Call Center campaign workspace model
│   │   ├── contact.dart      # Contact data model (with callCenterId)
│   │   └── interaction.dart  # Follow-up interaction model
│   ├── screens/
│   │   ├── call_centers_screen.dart        # Projects/Gems Hub & onboarding welcome state
│   │   ├── call_center_detail_screen.dart # Inside a Call Center (newest-on-top ordering)
│   │   ├── import_modal.dart              # CSV, Excel, Notes importer scoped to center
│   │   └── contact_detail_modal.dart      # Profile and follow-up interaction logger
│   ├── services/
│   │   ├── caller_id_service.dart    # Platform channel bridge
│   │   ├── contact_importer.dart     # CSV, Excel, plain text parser
│   │   └── phone_dialer_service.dart # Phone dialer launcher
│   └── utils/
│       └── phone_number_normalizer.dart # Ghana & E.164 normalization
├── android/                  # Android native project (Kotlin CallScreeningService)
├── ios/                      # iOS native project
│   ├── Runner/               # Flutter main host app (AppDelegate.swift)
│   └── CallDirectoryExtension/ # Swift CallKit extension (CallDirectoryHandler.swift)
├── test/                     # Automated unit and widget tests (39 tests)
│   ├── caller_id_service_test.dart
│   ├── contact_importer_test.dart
│   ├── database_test.dart
│   ├── models_test.dart
│   ├── phone_dialer_service_test.dart
│   ├── phone_number_normalizer_test.dart
│   └── widget_test.dart
└── pubspec.yaml              # Flutter dependencies
```

## Known Blockers

1. **No physical devices available right now** — Incoming-call caller ID cannot be simulated on software emulators; a physical Android phone or iPhone is required to verify real cellular calls in Milestone 2.

## License

Private project. Not open source.
