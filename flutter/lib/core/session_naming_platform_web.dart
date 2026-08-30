import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('clawnsole')
external JSObject? get _shell;

Future<String?> generatePlatformSessionName(String source) async {
  final shell = _shell;
  if (shell == null || !shell.has('generateSessionName')) return null;
  try {
    final value = await shell
        .callMethod<JSPromise<JSAny?>>('generateSessionName'.toJS, source.toJS)
        .toDart;
    final dart = value.dartify();
    return dart is String && dart.trim().isNotEmpty ? dart : null;
  } on Object {
    return null;
  }
}
