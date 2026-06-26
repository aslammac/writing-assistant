# Writing Assistant - Grammarly alternative

A **macOS system-wide grammar correction assistant** built with Flutter. It silently monitors text input across any application using macOS Accessibility APIs, sends text to a local grammar-checking backend, and presents inline suggestions through a sleek floating overlay — all accessible from the system tray.

---

## ✨ Features

- **System-Wide Text Monitoring** — Listens for text changes in any focused text field across macOS apps via the Accessibility API (`AXObserver`).
- **Real-Time Grammar Suggestions** — Debounced text processing sends content to a local grammar service and displays corrections instantly.
- **Floating Overlay UI** — A frameless, always-on-top, non-activating popup appears near the cursor with one-click fix application.
- **One-Click Fix Injection** — Applies corrections directly into the focused text field using `AXUIElementSetAttributeValue`, with keyboard simulation as a fallback.
- **System Tray Integration** — Toggle the assistant on/off, check permissions, or quit — all from the macOS menu bar.
- **Accessibility Permission Management** — Guides users through granting Accessibility access with a setup screen and deep-links to System Settings.

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────┐
│                    macOS System                      │
│                                                     │
│  ┌───────────┐    AX Notifications    ┌───────────┐ │
│  │  Any App  │ ───────────────────▶   │  Native   │ │
│  │ Text Field│                        │  Swift    │ │
│  └───────────┘    Text Injection      │  Plugin   │ │
│       ▲        ◀─────────────────── │(AppDelegate)│ │
│       │                               └─────┬─────┘ │
│       │                                     │       │
│       │                          MethodChannel       │
│       │                                     │       │
│       │                               ┌─────▼─────┐ │
│       │                               │  Flutter   │ │
│       │                               │    UI      │ │
│       │                               │ (main.dart)│ │
│       │                               └─────┬─────┘ │
│       │                                     │       │
│       │                              HTTP POST      │
│       │                                     │       │
│       │                               ┌─────▼─────┐ │
│       │                               │  Grammar   │ │
│       │                               │  Backend   │ │
│       │                               │ :8000/fix  │ │
│       └───────────────────────────────└───────────┘ │
└─────────────────────────────────────────────────────┘
```

| Layer | Technology | Responsibility |
|---|---|---|
| **Native Plugin** | Swift / AppKit / Accessibility | AXObserver setup, text change detection, text injection, window management |
| **Flutter UI** | Dart / Flutter (macOS) | Floating suggestion overlay, setup screen, system tray, debounce logic |
| **Grammar Service** | HTTP client (`package:http`) | Sends text to backend API and parses corrected output |
| **Backend** | External service on `localhost:8000` | Grammar correction endpoint (`POST /fix`) |

---

## 📋 Prerequisites

- **macOS** 12.0+ (Monterey or later recommended)
- **Flutter** SDK ≥ 3.10.4
- **Xcode** 14+ with macOS development tools
- **CocoaPods** — `sudo gem install cocoapods`
- **Grammar Backend** — A server running on `http://localhost:8000` with a `POST /fix` endpoint  
  - **Request:** `{ "text": "your text here" }`  
  - **Response:** `{ "output": "corrected text here" }`

---

## 🚀 Getting Started

### 1. Clone the Repository

```bash
git clone <repository-url>
cd writing-assistant
```

### 2. Install Dependencies

```bash
flutter pub get
cd macos && pod install && cd ..
```

### 3. Start the Grammar Backend

Ensure your grammar correction API is running on port `8000`. The app expects:

```
POST http://localhost:8000/fix
Content-Type: application/json

{ "text": "teh quick brown fox" }
→ { "output": "the quick brown fox" }
```

### 4. Run the App

```bash
flutter run -d macos
```

### 5. Grant Accessibility Permissions

On first launch, the app will display a setup screen prompting you to grant Accessibility access:

1. Click **"Open System Settings"** → navigates to **Privacy & Security → Accessibility**.
2. Toggle on the **Writing Assistant** app.
3. Return to the app and click **"I've granted permission"**.

> **Note:** macOS requires a restart of the app after toggling Accessibility permissions for the first time.

---

## 💡 Usage

| Action | How |
|---|---|
| **Enable/Disable** | Click the system tray icon → toggle **"Enable Assistant"** |
| **Accept a suggestion** | Click the ✅ button on the floating overlay |
| **Dismiss a suggestion** | Keep typing — the overlay auto-hides when text changes or no correction is needed |
| **Quit** | System tray icon → **"Quit"** |

The assistant uses an **800ms debounce**, so it waits for you to pause typing before checking grammar.

---

## 📁 Project Structure

```
writing-assistant/
├── lib/
│   ├── main.dart              # App entry point, UI, system tray, window management
│   └── grammar_service.dart   # HTTP client for the grammar correction backend
├── macos/
│   └── Runner/
│       ├── AppDelegate.swift  # Native Accessibility plugin (AXObserver, text injection)
│       ├── MainFlutterWindow.swift
│       └── Info.plist
├── assets/
│   └── app_icon.png           # System tray and app icon
├── pubspec.yaml               # Flutter dependencies & asset declarations
└── analysis_options.yaml      # Dart lint rules
```

---

## 📦 Key Dependencies

| Package | Version | Purpose |
|---|---|---|
| [`system_tray`](https://pub.dev/packages/system_tray) | ^2.0.3 | macOS/Windows system tray integration |
| [`window_manager`](https://pub.dev/packages/window_manager) | ^0.5.1 | Frameless window, always-on-top, position control |
| [`http`](https://pub.dev/packages/http) | ^1.6.0 | HTTP client for grammar API calls |

---

## ⚙️ Configuration

| Setting | Location | Default |
|---|---|---|
| Grammar API URL | `lib/grammar_service.dart` | `http://localhost:8000/fix` |
| Debounce delay | `lib/main.dart` | 800ms |
| Overlay size | `lib/main.dart` | 250 × 80 px |
| Method channel | `lib/main.dart` + `AppDelegate.swift` | `com.example.writing_assistant/accessibility` |

---

## 🛠️ Development

### Building for Release

```bash
flutter build macos --release
```

The compiled app will be located at:
```
build/macos/Build/Products/Release/writing_assistant.app
```

### Running Tests

```bash
flutter test
```

### Debugging Tips

- The app prints extensive `DEBUG:` logs to the console — run via terminal to see them.
- If suggestions don't appear, verify:
  1. Accessibility permission is granted.
  2. The grammar backend is running and reachable.
  3. The assistant is enabled in the system tray.
- Use `AXIsProcessTrusted()` output in logs to confirm permission status.

---

## 🔒 Permissions & Privacy

This app requires **macOS Accessibility access** to function. It uses these capabilities:

- **Read** the text content of the currently focused text field.
- **Write** corrected text back into the focused text field.
- **Observe** application focus changes to track the active input.

> The app communicates **only** with `localhost`. No data is sent to any external server.

---

## 📄 License

This project is private and not published to pub.dev.
