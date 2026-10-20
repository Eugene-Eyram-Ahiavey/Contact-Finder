# Technical Feasibility Assessment — Caller Identification

**Date:** 2026-10-20
**Milestone:** 0 — Understand the project and validate feasibility
**Status:** In progress — research complete, awaiting physical device validation

---

## 1. Executive Summary

Caller identification for evangelism contacts is **technically feasible on both Android and iOS**, but the two platforms offer fundamentally different capabilities and constraints.

| Capability | Android | iOS |
|-----------|---------|-----|
| Real-time caller identification | ✅ Yes | ✅ Yes |
| Custom overlay during call | ✅ Yes (with permissions) | ❌ No |
| Display caller name on incoming call screen | ✅ Via overlay or notification | ✅ Via native call screen label |
| Display rich details (notes, location, history) | ✅ Via overlay | ❌ Label only (short string) |
| Requires native code | ✅ Kotlin | ✅ Swift |
| Works without saving to phone contacts | ✅ Yes | ✅ Yes |
| Requires user opt-in | ✅ Role grant | ✅ Enable extension in Settings |
| Works from emulator | ❌ No | ❌ No |

**Recommendation:** Start the proof of concept on **Android** first. Android's `CallScreeningService` provides a richer, more controllable experience and is faster to iterate on. iOS's Call Directory Extension should follow once the core data model is validated.

---

## 2. Android: CallScreeningService

### 2.1 How It Works

Android provides the `CallScreeningService` API (Android 10+, API 29+). A third-party app can register as the system's **call screening app** and receive callbacks for every incoming call.

**Official documentation:** [developer.android.com — CallScreeningService](https://developer.android.com/reference/android/telecom/CallScreeningService)

**Mechanism:**

1. The app registers a service extending `CallScreeningService` in the Android manifest.
2. The user grants the app the `ROLE_CALL_SCREENING` role via `RoleManager`. Only **one app at a time** can hold this role.
3. When an incoming call arrives, Android binds to the service and calls `onScreenCall(callDetails)`.
4. The service receives the caller's phone number via `callDetails.handle.schemeSpecificPart`.
5. The service looks up the number against the local evangelism contact database.
6. If a match is found, the app displays the caller's identity using one of these approaches:
   - **System overlay** (`SYSTEM_ALERT_WINDOW` permission) — a floating window on top of the incoming call screen.
   - **High-priority notification with fullscreen intent** — a heads-up notification that can show caller details.
7. The service responds to the call with `respondToCall()` (allowing or blocking it).

### 2.2 Permissions Required

| Permission | Purpose | Grant method |
|-----------|---------|-------------|
| `BIND_SCREENING_SERVICE` | Allow Android Telecom to bind to the service | Manifest declaration |
| `ROLE_CALL_SCREENING` | Designate as the call screening app | User prompt via RoleManager |
| `SYSTEM_ALERT_WINDOW` | Display overlay on incoming call screen | User grant in Settings (may be auto-granted with screening role on Android 11+) |
| `FOREGROUND_SERVICE` | Keep overlay service alive during the call | Manifest declaration |

**No `READ_CALL_LOG` or `READ_CONTACTS` permission is needed.** This is a significant advantage — the app only needs its own local database.

### 2.3 What We Can Display

- **Full control:** The overlay or notification can show any information we want — name, location, notes, interaction history, last contact date.
- **Timing constraint:** `respondToCall()` must be called within ~5 seconds. Database lookups must be fast (local SQLite queries will be well within this).
- **Design flexibility:** The overlay can be styled as we choose.

### 2.4 Limitations and Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Only one app can hold `ROLE_CALL_SCREENING` at a time | Medium | Users who rely on another call-screening app (e.g., Google Phone's spam filter) would need to switch. Document this clearly. |
| OEM-specific battery restrictions may kill background services | Medium | Guide users through battery optimization exemptions. Test on Samsung, Xiaomi, etc. |
| Overlay permission may require manual Settings navigation | Low | Provide clear setup instructions. Some versions auto-grant with the screening role. |
| Numbers with restricted/unknown caller-ID presentation are not provided | Low | These calls would remain unidentified, which is the correct behavior. |
| Requires Android 10+ (API 29+) | Low | Android 10 is from 2019; coverage is very high in 2026. |

### 2.5 Verified Facts vs. Assumptions

| Claim | Status |
|-------|--------|
| `CallScreeningService` receives the phone number for incoming calls | ✅ Verified (official API documentation) |
| `RoleManager.ROLE_CALL_SCREENING` limits to one app | ✅ Verified (official documentation) |
| Overlay can display during incoming call | ✅ Verified (official documentation, widely used by Truecaller etc.) |
| `respondToCall()` must be fast (~5 seconds) | ✅ Verified (documented constraint) |
| Local SQLite lookup is fast enough | ⚠️ Assumption — needs testing with realistic dataset size |
| Overlay works on all OEM skins (Samsung, Xiaomi, etc.) | ⚠️ Assumption — needs device testing |
| Our specific overlay design renders correctly over the call screen | ⚠️ Assumption — needs device testing |

---

## 3. iOS: CallKit Call Directory Extension

### 3.1 How It Works

Apple provides the **Call Directory Extension** via the CallKit framework. This is the **only supported mechanism** for third-party caller identification on iOS.

**Official documentation:** [developer.apple.com — CXCallDirectoryProvider](https://developer.apple.com/documentation/callkit/cxcalldirectoryprovider)

**Mechanism:**

1. The app includes a **Call Directory Extension** — a separate extension target in the Xcode project.
2. The extension pre-loads phone number → label mappings into iOS's internal directory.
3. Numbers must be provided as `Int64` values in **E.164 format** (country code + digits, no formatting).
4. Numbers must be added in **strictly ascending numerical order**.
5. The user must manually enable the extension in **Settings → Phone → Call Blocking & Identification**.
6. When an incoming call arrives, iOS checks its pre-loaded directory. If a match is found, it displays the label string on the native incoming call screen.
7. The extension supports **incremental updates** — only changed entries need to be reloaded.

### 3.2 Data Sharing Between App and Extension

The main app and the Call Directory Extension are **separate processes** with separate sandboxes. They share data via:

- **App Groups** — a shared container that both the app and extension can read/write.
- The app writes contact data to a shared database (e.g., SQLite or a file in the App Group container).
- When the extension is triggered (by `CXCallDirectoryManager.reloadExtension()`), it reads from the shared database and loads entries into the system directory.

### 3.3 What We Can Display

- **Label only:** A single text string (e.g., "John - Evangelism Contact"). This appears below or next to the phone number on the native iOS incoming call screen.
- **No rich data:** We cannot show location, notes, interaction history, or custom UI on the incoming call screen.
- **Post-call access:** After identifying the caller, the user can open our app to see full details. iOS does not provide a mechanism to launch our app directly from the incoming call screen.

### 3.4 Permissions and Setup Required

| Requirement | Details |
|-----------|---------|
| Call Directory Extension target | Must be added in Xcode as a separate extension |
| App Group | Shared container for data between app and extension |
| User enablement | User must go to Settings → Phone → Call Blocking & Identification and toggle on the extension |
| No runtime permission prompt | Unlike Android, there is no in-app permission dialog. The user enables it in Settings. |

### 3.5 Limitations and Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Label is a short string only — no rich details | High (compared to Android) | Make the label informative (e.g., "John D. - Tema"). Full details available in-app after the call. |
| User must manually enable the extension in Settings | Medium | Provide clear setup instructions. The app can check if the extension is enabled via `CXCallDirectoryManager.getEnabledStatusForExtension()`. |
| Numbers must be sorted ascending and in E.164 Int64 format | Medium | Phone number normalization must be robust. Build and test this carefully. |
| Extension runs in a separate process with limited memory | Medium | Large contact lists (thousands) may need efficient loading. Test with realistic sizes. |
| Extension can only be triggered to reload, not queried in real-time | Low | Reload the extension after any contact create/update/delete. This is the intended pattern. |
| No way to launch the app directly from the call screen | Low | User opens the app manually after the call to see full details. |
| Incremental updates require tracking what changed | Low | Maintain a "last synced" timestamp or change tracking in the shared database. |

### 3.6 Verified Facts vs. Assumptions

| Claim | Status |
|-------|--------|
| Call Directory Extension is the only supported caller ID mechanism | ✅ Verified (Apple documentation) |
| Only a text label can be displayed | ✅ Verified (API: `addIdentificationEntry(withNextSequentialPhoneNumber:label:)`) |
| Numbers must be E.164 Int64 in ascending order | ✅ Verified (Apple documentation) |
| App Group container enables data sharing | ✅ Verified (standard iOS extension pattern) |
| User must enable the extension in Settings | ✅ Verified (Apple documentation) |
| Extension memory limits handle thousands of contacts | ⚠️ Assumption — needs testing with realistic dataset |
| Label renders visually well on the incoming call screen | ⚠️ Assumption — needs device testing |
| Incremental reloads work reliably after contact changes | ⚠️ Assumption — needs device testing |

---

## 4. Architecture: What Belongs Where

### 4.1 Flutter Layer (shared, cross-platform)

| Component | Description |
|-----------|-------------|
| Contact data model | Dart classes for contacts, interactions, phone numbers |
| Local database | SQLite via `sqflite` or similar — contacts, interaction history |
| Contact management UI | Create, view, edit, search, import contacts |
| Phone number normalization | Parse, normalize, validate phone numbers (using a library like `phone_numbers_parser`) |
| Platform channel interface | Method channel to trigger native caller ID sync |

### 4.2 Native Android Layer (Kotlin)

| Component | Description |
|-----------|-------------|
| `CallScreeningService` subclass | Receives `onScreenCall()` callbacks, looks up numbers |
| Local database reader | Reads from the app's database to match incoming numbers |
| Overlay/notification service | Displays caller identity on the incoming call screen |
| `RoleManager` integration | Requests the call screening role from the user |
| Platform channel handler | Receives sync commands from Flutter |

### 4.3 Native iOS Layer (Swift)

| Component | Description |
|-----------|-------------|
| Call Directory Extension | `CXCallDirectoryProvider` subclass that loads phone→label mappings |
| App Group shared storage | Database or file in shared container |
| Data sync service | Copies/updates contact data from the main app DB to the shared container |
| Extension reload trigger | Calls `CXCallDirectoryManager.reloadExtension()` after data changes |
| Platform channel handler | Receives sync commands from Flutter |

### 4.4 Data Flow

```
┌─────────────────────────────────────────┐
│                 Flutter                  │
│  ┌─────────────┐    ┌────────────────┐  │
│  │ Contact UI  │───▶│  Local SQLite  │  │
│  └─────────────┘    └───────┬────────┘  │
│                             │            │
│                    ┌────────▼────────┐   │
│                    │ Platform Channel│   │
│                    └───────┬────────┘   │
└────────────────────────────┼────────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
    ┌─────────▼──────┐  ┌───▼────────────┐
    │    Android      │  │      iOS        │
    │                 │  │                 │
    │ CallScreening   │  │ Call Directory  │
    │ Service reads   │  │ Extension reads │
    │ from app DB     │  │ from App Group  │
    │                 │  │ shared DB       │
    │ Shows overlay   │  │ Provides label  │
    │ or notification │  │ to iOS system   │
    └─────────────────┘  └─────────────────┘
```

---

## 5. Phone Number Normalization

Both platforms require reliable phone number matching. This is critical because:

- Ghanaian phone numbers may have leading zeros (e.g., `0244123456`).
- Numbers may or may not include the country code (`+233244123456` vs `0244123456`).
- iOS requires E.164 format as `Int64` (e.g., `233244123456`).
- Android provides the number as dialed, which may vary.

**Approach:**
- Store all numbers as strings to preserve formatting.
- Normalize to E.164 for matching and for the iOS extension.
- Use a phone number parsing library (e.g., `phone_numbers_parser` for Dart) with Ghana (`GH`, country code `+233`) as the default region.
- Match by comparing normalized forms, not raw input.

**This normalization logic must be testable without a device.** Unit tests should cover:
- `0244123456` → `+233244123456`
- `+233244123456` → `+233244123456`
- `233244123456` → `+233244123456`
- Numbers with spaces, dashes, parentheses
- Invalid numbers (too short, too long, non-numeric)

---

## 6. What Must Be Tested on Physical Devices

These items **cannot** be verified on emulators or through code analysis alone:

| Test | Platform | Why physical device is required |
|------|----------|-------------------------------|
| `onScreenCall()` fires for real incoming call | Android | Emulator cannot receive real cellular calls |
| Overlay displays correctly over call screen | Android | Requires real call UI to verify rendering |
| `ROLE_CALL_SCREENING` grant flow works | Android | Role dialog is system-level |
| Call Directory Extension label appears | iOS | Requires real incoming call on physical device |
| Extension enable/disable in Settings | iOS | Settings UI is device-only |
| Battery optimization impact on service | Android | OEM-specific, device-only |
| Performance with realistic contact list size | Both | Memory and timing constraints are device-dependent |

---

## 7. Proposed Proof of Concept (Milestone 2)

The smallest experiment that can prove caller identification works:

### Android PoC

1. Create a Kotlin `CallScreeningService` with a hardcoded list of 3–5 test phone numbers and names.
2. Register the service in the Android manifest.
3. Implement the `RoleManager` role request.
4. On `onScreenCall()`, match the incoming number against the hardcoded list.
5. If matched, display the caller's name via a high-priority notification (simpler than an overlay for the first test).
6. Install on a physical Android device.
7. Call the device from one of the test numbers.
8. **Success criteria:** The notification shows the correct name. An unregistered number produces no notification.

### iOS PoC

1. Add a Call Directory Extension target to the Xcode project.
2. Hardcode 3–5 test phone number → label entries in `beginRequest(with:)`.
3. Build and install on a physical iPhone.
4. Enable the extension in Settings → Phone → Call Blocking & Identification.
5. Call the device from one of the test numbers.
6. **Success criteria:** The label appears on the native incoming call screen. An unregistered number shows no label.

**Neither PoC requires a database, UI, or contact management.** They test only the OS-level integration.

---

## 8. Highest-Risk Assumptions

1. **Android OEM compatibility** — Samsung, Xiaomi, and other manufacturers may interfere with background services or overlays. Must test on real hardware.
2. **iOS Call Directory Extension memory limits** — Apple limits extension memory. With a large contact list (e.g., 10,000+), the extension could be terminated. Must test with realistic sizes.
3. **Phone number normalization for Ghana** — Ghanaian number formats must be handled correctly. Must validate with real local numbers.
4. **User willingness to grant permissions** — Both platforms require explicit user action (Android: role grant; iOS: Settings toggle). The app must guide users clearly.
5. **Conflict with existing call screening apps** — On Android, only one app can hold the screening role. If the user already uses a spam filter app, they must choose.

---

## 9. Part C: `adb` Not on PATH — Diagnosis and Fix

### Finding

`adb` is installed at `/Users/kobe/Library/Android/sdk/platform-tools/adb` but the directory is not included in the shell's `PATH` environment variable. The `ANDROID_HOME` and `ANDROID_SDK_ROOT` variables are also not set.

Flutter finds the SDK by checking the default macOS location (`~/Library/Android/sdk`), which is why `flutter doctor` passes while `adb` is not available as a standalone terminal command.

### Recommended Fix

Add the following lines to `~/.zshrc`:

```bash
# Android SDK
export ANDROID_HOME="$HOME/Library/Android/sdk"
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/tools:$ANDROID_HOME/tools/bin:$ANDROID_HOME/emulator:$PATH"
```

Then reload the shell:

```bash
source ~/.zshrc
```

After this, `adb`, `emulator`, and other SDK tools will be available directly in the terminal.

**I have not made this change.** It modifies your shell configuration. Apply it when you are ready.

---

## 10. Milestone 0 — Completion Status

| Criterion | Status |
|-----------|--------|
| Workspace inspected and reported | ✅ Complete |
| Flutter project exists with Android and iOS targets | ✅ Complete |
| Development tools confirmed | ✅ Complete |
| Android caller ID feasibility assessed | ✅ Complete (device testing pending) |
| iOS caller ID feasibility assessed | ✅ Complete (device testing pending) |
| Permissions and native integrations identified | ✅ Complete |
| Proof of concept proposed | ✅ Complete |
| Architecture and risks explained | ✅ Complete |
| Approved by project owner | ⏳ Awaiting review |
