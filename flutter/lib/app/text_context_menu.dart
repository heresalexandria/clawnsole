import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Uses Flutter's adaptive text menus where a browser menu is unavailable.
///
/// Electron does not provide Chromium's browser context menu by default. The
/// Flutter web engine otherwise suppresses its own text menu in favor of that
/// missing browser menu, so editable fields receive no secondary-click action.
Future<void> configureTextContextMenus() async {
  if (kIsWeb) await BrowserContextMenu.disableContextMenu();
}
