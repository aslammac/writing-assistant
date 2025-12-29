import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';
import 'grammar_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  runApp(const WritingAssistantApp());
}

class WritingAssistantApp extends StatefulWidget {
  const WritingAssistantApp({super.key});

  @override
  State<WritingAssistantApp> createState() => _WritingAssistantAppState();
}

class _WritingAssistantAppState extends State<WritingAssistantApp> {
  static const platform = MethodChannel(
    'com.example.writing_assistant/accessibility',
  );
  final SystemTray _systemTray = SystemTray();
  final Menu _menu = Menu();
  final GrammarService _grammarService = GrammarService();

  bool _isTrusted = false;
  bool _isEnabled = true; // Assistant disabled by default
  bool _isInjecting = false; // Guard to prevent feedback loops
  String? _suggestion;
  Offset _cursorPos = Offset.zero;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _initSystemTray();
    _checkPermissions();
    _setupMethodChannel();

    // Configure window manager for the floating UI
    windowManager.setAsFrameless();
    windowManager.setHasShadow(true);
    windowManager.setAlwaysOnTop(true);
    windowManager.setSkipTaskbar(true);
    windowManager.hide();
  }

  Future<void> _initSystemTray() async {
    // Note: You should have an icon in macos/Runner/Assets.xcassets/AppIcon.appiconset or similar.
    // For now, we use a placeholder path or try to load a default if available.
    String path = Platform.isMacOS
        ? 'assets/app_icon.png'
        : 'assets/app_icon.ico';

    await _systemTray.initSystemTray(
      title: "Writing Assistant",
      iconPath: path,
    );
    await _menu.buildFrom([
      MenuItemCheckbox(
        label: 'Enable Assistant',
        checked: _isEnabled,
        onClicked: (menuItem) async {
          final newValue = !menuItem.checked;
          print(
            "DEBUG: Toggle assistant clicked. Current: ${menuItem.checked}, Setting to: $newValue",
          );
          await menuItem.setCheck(newValue);
          setState(() {
            _isEnabled = newValue;
          });
        },
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: 'Check Permissions',
        onClicked: (menuItem) => _checkPermissions(),
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: 'Quit',
        onClicked: (menuItem) {
          print("DEBUG: Quit clicked");
          exit(0);
        },
      ),
    ]);

    await _systemTray.setContextMenu(_menu);

    // Handle tray events (like clicks) explicitly to ensure the menu shows up on macOS
    _systemTray.registerSystemTrayEventHandler((eventName) {
      if (eventName == kSystemTrayEventClick ||
          eventName == kSystemTrayEventRightClick) {
        _systemTray.popUpContextMenu();
      }
    });
  }

  Future<void> _checkPermissions() async {
    final bool trusted = await platform.invokeMethod('checkPermissions');
    setState(() {
      _isTrusted = trusted;
    });
    if (!trusted) {
      // Show setup window if not trusted
      await windowManager.setSize(const Size(400, 300));
      await windowManager.center();
      await windowManager.show();
    } else {
      await windowManager.hide();
    }
  }

  void _setupMethodChannel() {
    platform.setMethodCallHandler((call) async {
      if (call.method == "onTextChange") {
        if (!_isEnabled) {
          // print("DEBUG: Assistant disabled, ignoring text change");
          return;
        }
        if (_isInjecting) {
          print("DEBUG: Currently injecting, ignoring text change");
          return;
        }

        final Map<dynamic, dynamic> data = call.arguments;
        final String text = data['text'];
        final double x = data['x'];
        final double y = data['y'];
        final double h = data['height'];

        print(
          "DEBUG: Received text change: '${text.length > 20 ? text.substring(0, 20) + "..." : text}' at ($x, $y)",
        );

        // Debounce API calls
        if (_debounce?.isActive ?? false) _debounce?.cancel();
        _debounce = Timer(
          const Duration(milliseconds: 800),
          () => _processText(text, Offset(x, y + h)),
        );
      }
    });
  }

  Future<void> _processText(String text, Offset position) async {
    print(
      "DEBUG: Processing text: '${text.length > 20 ? text.substring(0, 20) + "..." : text}' at $position",
    );
    if (text.isEmpty) {
      await windowManager.hide();
      return;
    }

    final suggestion = await _grammarService.fixGrammar(text);
    print(
      "DEBUG: Grammar service returned: ${suggestion != null ? "'${suggestion.length > 20 ? suggestion.substring(0, 20) + "..." : suggestion}'" : "null"}",
    );
    print("DEBUG: Suggestion different from text: ${suggestion != text}");

    if (suggestion != null && suggestion != text) {
      setState(() {
        _suggestion = suggestion;
        _cursorPos = position;
      });
      print("DEBUG: Calling _showOverlay with suggestion: $suggestion");
      await _showOverlay();
    } else {
      print("DEBUG: No suggestion or same as original, hiding window");
      await windowManager.hide();
    }
  }

  Future<void> _showOverlay() async {
    print("DEBUG: _showOverlay called at position: $_cursorPos");
    await windowManager.setSize(const Size(250, 80));
    await windowManager.setPosition(_cursorPos);
    // Use native method to show without activating
    try {
      await platform.invokeMethod('showWindowWithoutActivating');
      print("DEBUG: Native showWindowWithoutActivating called");
    } catch (e) {
      print(
        "DEBUG: Failed to call native show, falling back to window_manager: $e",
      );
      await windowManager.show();
    }
  }

  Future<void> _applyFix() async {
    if (_suggestion != null && !_isInjecting) {
      setState(() {
        _isInjecting = true;
      });

      await platform.invokeMethod('injectText', {'text': _suggestion});
      await windowManager.hide();

      setState(() {
        _suggestion = null;
      });

      // Stay in "injecting" state for a bit to ignore the AX notifications
      // triggered by our own injection.
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          setState(() {
            _isInjecting = false;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.transparent,
      ),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: _isTrusted ? _buildFloatingUI() : _buildSetupScreen(),
      ),
    );
  }

  Widget _buildSetupScreen() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.accessibility_new,
            size: 48,
            color: Colors.blueAccent,
          ),
          const SizedBox(height: 16),
          const Text(
            "Accessibility Access Required",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 8),
          const Text(
            "This app needs permission to see what you type and suggest corrections.",
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => platform.invokeMethod('openPrivacySettings'),
            child: const Text("Open System Settings"),
          ),
          TextButton(
            onPressed: _checkPermissions,
            child: const Text("I've granted permission"),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingUI() {
    return Center(
      child: Container(
        width: 240,
        height: 70,
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: Colors.blueAccent.withOpacity(0.5),
            width: 1.5,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.auto_fix_high, color: Colors.blueAccent, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "Grammar Suggestion",
                    style: TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                  Text(
                    _suggestion ?? "Thinking...",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.check, color: Colors.greenAccent),
              onPressed: _applyFix,
            ),
          ],
        ),
      ),
    );
  }
}
