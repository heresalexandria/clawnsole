// Isolated rendering workload: no controller, library, credentials, or gateway.
// Build with `flutter build web --target tool/renderer_soak.dart` and open
// `?style=broadcastStatic&cards=12` or `?style=cyclone&cards=12`.
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/ui/generation_loading_placeholder.dart';
import 'package:flutter/material.dart';

void main() {
  final query = Uri.base.queryParameters;
  final style = query['style'] == 'cyclone'
      ? GenerationPlaceholderStyle.cyclone
      : GenerationPlaceholderStyle.broadcastStatic;
  final count = (int.tryParse(query['cards'] ?? '') ?? 12).clamp(1, 12);
  final now = DateTime.now().toUtc();
  runApp(
    MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: GridView.count(
          crossAxisCount: 3,
          childAspectRatio: 16 / 9,
          padding: const EdgeInsets.all(8),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: <Widget>[
            for (var index = 0; index < count; index++)
              GenerationLoadingPlaceholder(
                style: style,
                item: Generation(
                  localId: 'soak-$index',
                  status: 'Pending',
                  prompt: 'Synthetic renderer workload.',
                  mode: VideoMode.t2v,
                  config: const GenerationConfig(
                    aspectRatio: '16:9',
                    duration: 8,
                    resolution: 'hd',
                    generateAudio: true,
                    safetyTolerance: 2,
                    draft: false,
                  ),
                  createdAt: now,
                  updatedAt: now,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
