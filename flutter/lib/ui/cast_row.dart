import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/app_theme.dart';
import '../core/models.dart';
import 'characters_dialog.dart';
import 'hardware.dart';
import 'media_thumbnail.dart';

/// One cast member's media, resolved wherever it lives: an attached draft
/// first, then the saved library card of the same name, then a ghost when the
/// name no longer names anything.
class CharacterReferenceThumb extends StatelessWidget {
  const CharacterReferenceThumb({
    required this.controller,
    required this.referenceName,
    super.key,
    this.size = 26,
  });

  final AppController controller;
  final String referenceName;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: context.colors.surfaceContainer,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: context.colors.outlineVariant),
    ),
    child: _preview(context),
  );

  Widget _preview(BuildContext context) {
    final draft = controller.form.references
        .where(
          (item) =>
              item.kind != MediaReferenceKind.audio &&
              controller.referencePromptName(item) == referenceName,
        )
        .firstOrNull;
    if (draft != null) {
      return MediaThumbnail(
        gateway: controller.gateway,
        kind: draft.kind,
        bytes: draft.asset?.bytes,
        mimeType: draft.asset?.mimeType,
        localPath: draft.asset?.path,
        reference: draft.asset?.retained ?? draft.retained,
        thumbnailReference: draft.thumbnailAsset ?? draft.asset?.thumbnailAsset,
        thumbnailBytes: draft.thumbnailBytes ?? draft.asset?.thumbnailBytes,
        source: draft.source,
        semanticsLabel: '$referenceName preview',
      );
    }
    final saved = controller.savedReferences
        .where(
          (item) =>
              !item.hidden &&
              item.kind != MediaReferenceKind.audio &&
              item.name == referenceName,
        )
        .firstOrNull;
    if (saved == null) {
      return Icon(
        Icons.person_outline_rounded,
        size: size * .58,
        color: context.colors.onSurfaceVariant,
      );
    }
    final isVideo = saved.kind == MediaReferenceKind.video;
    return MediaThumbnail(
      gateway: controller.gateway,
      kind: saved.kind,
      bytes: isVideo ? null : controller.cachedAssetBytes(saved.asset),
      reference: saved.asset,
      thumbnailReference: saved.thumbnailAsset,
      thumbnailBytes: isVideo
          ? controller.cachedAssetBytes(saved.thumbnailAsset)
          : null,
      semanticsLabel: '$referenceName preview',
    );
  }
}

/// The casting strip above the guidance/settings pair: who is in this
/// direction, what they look like, and one tap to recast them. It is the only
/// place the casting block is visible while writing — the prompt itself never
/// holds it.
///
/// Hidden entirely until at least one character holds a reference, so a fresh
/// composer keeps the heading through Generate above the fold.
class CastRow extends StatelessWidget {
  const CastRow({required this.controller, super.key});

  final AppController controller;

  static const double _thumb = 26;
  static const int _visibleThumbs = 3;

  /// Whether this composer has a cast worth a row of its own. The caller owns
  /// the gap above the guidance block, so it asks before laying one out.
  static bool visibleFor(AppController controller) =>
      controller.selectedModel.supportsCharacterReferences &&
      controller.form.characterMappings.values.any(
        (references) => references.isNotEmpty,
      );

  @override
  Widget build(BuildContext context) {
    if (!visibleFor(controller)) return const SizedBox.shrink();
    final names =
        controller.form.characterMappings.entries
            .where((entry) => entry.value.isNotEmpty)
            .map((entry) => entry.key)
            .toList()
          ..sort();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Icon(Icons.groups_2_rounded, size: 16, color: context.tokens.brass),
        const SizedBox(width: 8),
        Text(
          'CAST',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.3,
            fontWeight: FontWeight.w700,
            color: context.colors.onSurface.withValues(alpha: .82),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              for (final name in names)
                _CastChip(controller: controller, name: name),
              _AddCastAction(controller: controller),
            ],
          ),
        ),
      ],
    );
  }
}

class _CastChip extends StatelessWidget {
  const _CastChip({required this.controller, required this.name});

  final AppController controller;
  final String name;

  Future<void> _edit(BuildContext context) => showCharacterMappingEditor(
    context,
    controller,
    character: controller.castScriptName(name),
  );

  @override
  Widget build(BuildContext context) {
    final references = controller.form.characterMappings[name] ?? const [];
    final shown = references.take(CastRow._visibleThumbs).toList();
    final extra = references.length - shown.length;
    return MergeSemantics(
      child: Semantics(
        container: true,
        button: true,
        label: 'Edit $name casting',
        child: HardwareTouchTarget(
          onTap: () => unawaited(_edit(context)),
          child: InkWell(
            key: ValueKey<String>('cast-chip-$name'),
            onTap: () => unawaited(_edit(context)),
            borderRadius: BorderRadius.circular(10),
            child: ExcludeSemantics(
              child: Container(
                padding: const EdgeInsets.fromLTRB(4, 4, 9, 4),
                decoration: BoxDecoration(
                  color: context.colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.colors.outlineVariant),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    SizedBox(
                      height: CastRow._thumb,
                      // Overlapping thumbs read as one cast card rather than a
                      // row of unrelated media.
                      width:
                          CastRow._thumb +
                          (shown.length - 1 + (extra > 0 ? 1 : 0)) *
                              (CastRow._thumb * .62),
                      child: Stack(
                        children: <Widget>[
                          for (var index = 0; index < shown.length; index += 1)
                            Positioned(
                              left: index * CastRow._thumb * .62,
                              child: CharacterReferenceThumb(
                                controller: controller,
                                referenceName: shown[index],
                              ),
                            ),
                          if (extra > 0)
                            Positioned(
                              left: shown.length * CastRow._thumb * .62,
                              child: Container(
                                width: CastRow._thumb,
                                height: CastRow._thumb,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: context.colors.surfaceContainer,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: context.colors.outlineVariant,
                                  ),
                                ),
                                child: Text(
                                  '+$extra',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: context.colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: context.colors.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AddCastAction extends StatelessWidget {
  const _AddCastAction({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    key: const ValueKey<String>('cast-add-character'),
    onPressed: () => unawaited(
      showCharacterMappingEditor(context, controller, character: ''),
    ),
    style: TextButton.styleFrom(
      foregroundColor: context.colors.secondary,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
    ),
    icon: const Icon(Icons.person_add_alt, size: 15),
    label: const Text('Add character'),
  );
}
