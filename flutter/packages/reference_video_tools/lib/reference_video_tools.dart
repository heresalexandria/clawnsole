import 'package:flutter/services.dart';

class ReferenceVideoToolInvocation {
  const ReferenceVideoToolInvocation({
    required this.exitCode,
    required this.output,
  });

  final int exitCode;
  final String output;
}

class ReferenceVideoTools {
  const ReferenceVideoTools._();

  static const MethodChannel _channel = MethodChannel(
    'ai.clawnsole/reference_video_tools',
  );

  static Future<ReferenceVideoToolInvocation> execute(
    List<String> arguments, {
    required bool probe,
  }) async {
    final response = await _channel.invokeMapMethod<String, Object?>(
      'execute',
      <String, Object?>{'arguments': arguments, 'probe': probe},
    );
    return ReferenceVideoToolInvocation(
      exitCode: (response?['exitCode'] as num?)?.toInt() ?? -1,
      output: response?['output']?.toString() ?? '',
    );
  }
}
