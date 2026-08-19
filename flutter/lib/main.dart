import 'package:flutter/material.dart';

import 'app/clawnsole_app.dart';
import 'app/text_context_menu.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureTextContextMenus();
  runApp(const ClawnsoleApp());
}
