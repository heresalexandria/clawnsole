import 'package:flutter/services.dart';

const MethodChannel _channel = MethodChannel('ai.clawnsole/session_naming');

Future<String?> generatePlatformSessionName(String source) async {
  try {
    return await _channel.invokeMethod<String>('generate', <String, Object?>{
      'source': source,
    });
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}
