# ✍️ Writing Assistant

A lightweight **macOS menu bar app** built with Flutter that watches what you type system-wide and offers real-time grammar correction through a non-intrusive floating overlay.

---

## ✨ Features

- **System-wide grammar monitoring** — uses macOS Accessibility APIs to observe text in any app
- **Floating suggestion overlay** — a frameless, always-on-top popup appears near your cursor with a corrected version of your text
- **One-click fix** — tap the ✓ button to instantly replace the selected text with the corrected version
- **Menu bar icon** — lives quietly in the macOS menu bar with a toggle to enable/disable the assistant
- **Debounced processing** — waits 800 ms after you stop typing before calling the grammar API, avoiding unnecessary requests
- **Anti-feedback-loop guard** — ignores Accessibility events triggered by its own text injection

---

## 🏗️ Architecture

```
writing-assistant/
├── lib/
│   ├── main.dart            # App entry point, UI, system tray, window management
│   └── grammar_service.dart # HTTP client for the grammar correction API
├── macos/                   # macOS-specific native code (Accessibility, text injection)
├── assets/
│   └── app_icon.png         # Menu bar icon
└── pubspec.yaml
```

### How it works

1. A native macOS plugin (via `MethodChannel`) monitors the focused text field using the **Accessibility API**.
2. On each text change, the Flutter side debounces and sends the text to a local **grammar correction API** at `http://localhost:8000/fix`.
3. If a correction is found, a small frameless window floats near the cursor showing the suggestion.
4. Accepting the suggestion uses the Accessibility API to **inject the corrected text** back into the source app.

---

## 📦 Dependencies

| Package | Purpose |
|---|---|
| [`system_tray`](https://pub.dev/packages/system_tray) | Menu bar icon and context menu |
| [`window_manager`](https://pub.dev/packages/window_manager) | Frameless, always-on-top floating window |
| [`http`](https://pub.dev/packages/http) | HTTP requests to the grammar API |

---

## 🚀 Getting Started

### Prerequisites

- **Flutter SDK** ≥ 3.4.0
- **macOS** (this app is macOS-only)
- A running **grammar correction API** server at `http://localhost:8000`

### Setup

```bash
# Install dependencies
flutter pub get

# Run in debug mode
flutter run -d macos

# Build a release app
flutter build macos
```

### Grammar API

The app expects a local HTTP server at `http://localhost:8000/fix` that accepts POST requests:

**Request**
```json
POST /fix
Content-Type: application/json

{ "text": "I has a apple" }
```

**Response**
```json
{ "output": "I have an apple" }
```

You can back this with any grammar model — a simple FastAPI/Flask server wrapping a language model works well.

---

## 🔐 Permissions

On first launch, the app will request **Accessibility access** in System Settings. This is required to:
- Read text from the currently focused input field
- Inject corrected text back into any app

To grant permission: **System Settings → Privacy & Security → Accessibility → enable Writing Assistant**

---

## 🛠️ SDK Compatibility Notes

The project targets **Dart ≥ 3.4.0** (Flutter 3.22+). If you see version-solving errors, ensure your `pubspec.yaml` has:

```yaml
environment:
  sdk: ^3.4.0
```

And use `window_manager: ^0.3.9` — versions 0.4+ require Dart 3.7+.
