import 'package:flutter/widgets.dart';

/// Run the current Create form — bound to ⌘/Ctrl+Enter app-wide so a prompt
/// can be submitted without leaving the keyboard.
class GenerateIntent extends Intent {
  const GenerateIntent();
}

/// Open the Settings section — bound to ⌘/Ctrl+, following desktop
/// convention; the Electron menu item sends the same request.
class OpenSettingsIntent extends Intent {
  const OpenSettingsIntent();
}

/// Move keyboard focus into the prompt field — bound to ⌘/Ctrl+K.
class FocusPromptIntent extends Intent {
  const FocusPromptIntent();
}
