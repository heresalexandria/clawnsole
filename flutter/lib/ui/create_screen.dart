import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/app_controller.dart';
import '../app/app_theme.dart';
import '../core/models.dart';
import '../core/provider_catalog.dart';
import 'common_widgets.dart';
import 'claw_mark.dart';
import 'formatters.dart';

class CreateScreen extends StatelessWidget {
  const CreateScreen({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final split = constraints.maxWidth >= 1160;
      return SingleChildScrollView(
        padding: EdgeInsets.all(constraints.maxWidth < 620 ? 16 : 28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _CreateHeading(controller: controller),
                const SizedBox(height: 24),
                if (split)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        flex: 7,
                        child: _Composer(controller: controller),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        flex: 4,
                        child: _RecentWork(controller: controller),
                      ),
                    ],
                  )
                else ...<Widget>[
                  _Composer(controller: controller),
                  const SizedBox(height: 20),
                  _RecentWork(controller: controller),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _CreateHeading extends StatelessWidget {
  const _CreateHeading({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 22,
    runSpacing: 16,
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: <Widget>[
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 650),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Eyebrow('Video studio', icon: Icons.auto_awesome_rounded),
            const SizedBox(height: 10),
            Text(
              'Make it move.',
              style: Theme.of(context).textTheme.displayLarge,
            ),
            const SizedBox(height: 10),
            const Text(
              'Direct one continuous moment, pin the important frames, and let Clawnsole mind the render.',
            ),
          ],
        ),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
        decoration: BoxDecoration(
          color: ClawnsoleColors.rail,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircleAvatar(
              radius: 15,
              backgroundColor: ClawnsoleColors.cobalt,
              child: Text(
                'BFL',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'SELECTED PROVIDER',
                  style: TextStyle(
                    color: Color(0xFFA8B9FF),
                    fontSize: 7,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Black Forest Labs',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Model · FLUX 3 latest',
                  style: TextStyle(color: Colors.white60, fontSize: 9),
                ),
              ],
            ),
          ],
        ),
      ),
    ],
  );
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Generation mode',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 9),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: bflProvider.modes.map((mode) {
                  final selected = controller.form.mode == mode;
                  return ChoiceChip(
                    label: Text(mode.shortLabel),
                    avatar: Icon(
                      _modeIcon(mode),
                      size: 16,
                      color: selected
                          ? context.colors.onPrimary
                          : context.colors.primary,
                    ),
                    selected: selected,
                    onSelected: (_) =>
                        controller.updateForm((form) => form.mode = mode),
                    selectedColor: context.colors.primary,
                    backgroundColor: context.colors.surfaceContainerLow,
                    checkmarkColor: context.colors.onPrimary,
                    labelStyle: TextStyle(
                      color: selected
                          ? context.colors.onPrimary
                          : context.colors.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                    side: BorderSide(
                      color: selected
                          ? context.colors.primary
                          : context.colors.outlineVariant,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (controller.form.mode != VideoMode.draftEnhance) ...<Widget>[
                const _FieldLabel('Direction', icon: Icons.edit_note_rounded),
                const SizedBox(height: 8),
                TextFormField(
                  key: const ValueKey('generation-prompt'),
                  initialValue: controller.form.prompt,
                  minLines: 5,
                  maxLines: 9,
                  maxLength: 50000,
                  onChanged: (value) =>
                      controller.updateForm((form) => form.prompt = value),
                  decoration: const InputDecoration(
                    hintText:
                        'A single continuous shot… describe movement, framing, sound, and what must stay consistent.',
                    counterText: '',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 18),
              ],
              if (controller.form.mode == VideoMode.i2v)
                _KeyframeEditor(controller: controller),
              if (controller.form.mode == VideoMode.v2v)
                _SourceEditor(
                  title: 'Starting video',
                  description:
                      'Upload a clip or paste a hosted provider-compatible URL.',
                  icon: Icons.movie_filter_rounded,
                  asset: controller.form.videoAsset,
                  url: controller.form.videoUrl,
                  onPick: controller.pickVideo,
                  onUrl: (value) =>
                      controller.updateForm((form) => form.videoUrl = value),
                  onClear: () => controller.updateForm((form) {
                    form.videoAsset = null;
                    form.videoUrl = '';
                  }),
                ),
              if (controller.form.mode == VideoMode.draftEnhance)
                _SourceEditor(
                  title: 'FLUX 3 draft cache',
                  description:
                      'Choose a draft cache bundle or use a retained cache URL.',
                  icon: Icons.auto_fix_high_rounded,
                  asset: controller.form.draftAsset,
                  url: controller.form.draftUrl,
                  onPick: controller.pickDraft,
                  onUrl: (value) =>
                      controller.updateForm((form) => form.draftUrl = value),
                  onClear: () => controller.updateForm((form) {
                    form.draftAsset = null;
                    form.draftUrl = '';
                  }),
                ),
              if (controller.form.mode != VideoMode.t2v)
                const SizedBox(height: 18),
              _SettingsGrid(controller: controller),
              const SizedBox(height: 18),
              _CostPreview(controller: controller),
              const SizedBox(height: 18),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Row(
                      children: <Widget>[
                        if (controller.hasApiKey)
                          ClawMark(size: 20, color: context.colors.primary)
                        else
                          Icon(
                            Icons.key_off_rounded,
                            color: context.colors.primary,
                            size: 20,
                          ),
                        const SizedBox(width: 9),
                        Flexible(
                          child: Text(
                            controller.hasApiKey
                                ? 'Ready when you are'
                                : 'API key needed',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: controller.submitting
                        ? null
                        : () => unawaited(controller.submit()),
                    icon: controller.submitting
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.play_arrow_rounded),
                    label: const Text('Generate video'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

IconData _modeIcon(VideoMode mode) => switch (mode) {
  VideoMode.t2v => Icons.text_fields_rounded,
  VideoMode.i2v => Icons.photo_library_rounded,
  VideoMode.v2v => Icons.video_file_rounded,
  VideoMode.draftEnhance => Icons.auto_fix_high_rounded,
};

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label, {required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Icon(icon, size: 17, color: context.colors.primary),
      const SizedBox(width: 7),
      Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
      ),
    ],
  );
}

class _KeyframeEditor extends StatelessWidget {
  const _KeyframeEditor({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Row(
        children: <Widget>[
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _FieldLabel('Keyframes', icon: Icons.collections_rounded),
                SizedBox(height: 3),
                Text(
                  '1–10 images · first and last frames are pinned',
                  style: TextStyle(fontSize: 9),
                ),
              ],
            ),
          ),
          FilterChip(
            label: const Text('Exact timing'),
            selected: controller.form.exactTiming,
            onSelected: (value) =>
                controller.updateForm((form) => form.exactTiming = value),
          ),
        ],
      ),
      const SizedBox(height: 10),
      if (controller.form.keyframes.isNotEmpty)
        Wrap(
          spacing: 9,
          runSpacing: 9,
          children: controller.form.keyframes.asMap().entries.map((entry) {
            final index = entry.key;
            final frame = entry.value;
            return Container(
              width: 154,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: context.colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.colors.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Stack(
                    children: <Widget>[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          height: 80,
                          width: double.infinity,
                          child: frame.asset != null
                              ? Image.memory(
                                  frame.asset!.bytes,
                                  fit: BoxFit.cover,
                                )
                              : Uri.tryParse(frame.source)?.scheme == 'https'
                              ? Image.network(
                                  frame.source,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Container(
                                    color: ClawnsoleColors.rail,
                                    child: const Icon(
                                      Icons.link_rounded,
                                      color: ClawnsoleColors.railMuted,
                                    ),
                                  ),
                                )
                              : Container(
                                  color: ClawnsoleColors.rail,
                                  child: const Icon(
                                    Icons.link_rounded,
                                    color: ClawnsoleColors.railMuted,
                                  ),
                                ),
                        ),
                      ),
                      Positioned(
                        top: 3,
                        right: 3,
                        child: IconButton.filledTonal(
                          constraints: const BoxConstraints.tightFor(
                            width: 27,
                            height: 27,
                          ),
                          padding: EdgeInsets.zero,
                          onPressed: () => controller.removeFrame(frame.id),
                          icon: const Icon(Icons.close_rounded, size: 14),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    index == 0
                        ? 'Start'
                        : index == controller.form.keyframes.length - 1
                        ? 'Last'
                        : 'Frame ${index + 1}',
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (frame.asset == null) ...<Widget>[
                    const SizedBox(height: 5),
                    TextFormField(
                      key: ValueKey('frame-url-${frame.id}'),
                      initialValue: frame.source,
                      onChanged: (value) =>
                          controller.updateFrame(frame.id, source: value),
                      decoration: const InputDecoration(
                        hintText: 'https://…',
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                      ),
                      style: const TextStyle(fontSize: 9),
                    ),
                  ],
                  if (controller.form.exactTiming) ...<Widget>[
                    const SizedBox(height: 5),
                    TextFormField(
                      key: ValueKey('frame-time-${frame.id}'),
                      initialValue: frame.seconds.toString(),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (value) => controller.updateFrame(
                        frame.id,
                        seconds: double.tryParse(value) ?? frame.seconds,
                      ),
                      decoration: const InputDecoration(
                        suffixText: 'sec',
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                      ),
                      style: const TextStyle(fontSize: 9),
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
        ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          OutlinedButton.icon(
            onPressed:
                controller.form.keyframes.length >= bflProvider.maxKeyframes
                ? null
                : controller.addImageFiles,
            icon: const Icon(Icons.add_photo_alternate_rounded, size: 17),
            label: const Text('Add images'),
          ),
          OutlinedButton.icon(
            onPressed:
                controller.form.keyframes.length >= bflProvider.maxKeyframes
                ? null
                : controller.addUrlFrame,
            icon: const Icon(Icons.add_link_rounded, size: 17),
            label: const Text('Add image URL'),
          ),
        ],
      ),
    ],
  );
}

class _SourceEditor extends StatelessWidget {
  const _SourceEditor({
    required this.title,
    required this.description,
    required this.icon,
    required this.asset,
    required this.url,
    required this.onPick,
    required this.onUrl,
    required this.onClear,
  });

  final String title;
  final String description;
  final IconData icon;
  final PickedAsset? asset;
  final String url;
  final Future<void> Function() onPick;
  final ValueChanged<String> onUrl;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: context.colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: context.colors.outlineVariant),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(icon, color: context.colors.primary),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  Text(description, style: const TextStyle(fontSize: 9)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (asset != null)
          ListTile(
            tileColor: context.colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
            leading: const Icon(Icons.insert_drive_file_rounded),
            title: Text(
              asset!.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(formatBytes(asset!.bytes.length)),
            trailing: IconButton(
              onPressed: onClear,
              icon: const Icon(Icons.close_rounded),
            ),
          )
        else
          Wrap(
            spacing: 9,
            runSpacing: 9,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: () => unawaited(onPick()),
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text('Choose file'),
              ),
              const Text('or', style: TextStyle(fontSize: 10)),
              SizedBox(
                width: 290,
                child: TextFormField(
                  key: ValueKey('$title-url'),
                  initialValue: url,
                  onChanged: onUrl,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.link_rounded, size: 17),
                    hintText: 'Paste a hosted URL',
                  ),
                ),
              ),
            ],
          ),
      ],
    ),
  );
}

class _SettingsGrid extends StatelessWidget {
  const _SettingsGrid({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth > 610;
      final first = <Widget>[
        const _FieldLabel('Frame', icon: Icons.crop_rounded),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey(controller.form.aspectRatio),
          initialValue: controller.form.aspectRatio,
          items: bflProvider.aspectRatios
              .map(
                (ratio) => DropdownMenuItem(value: ratio, child: Text(ratio)),
              )
              .toList(),
          onChanged: controller.form.mode == VideoMode.draftEnhance
              ? null
              : (value) {
                  if (value != null) {
                    controller.updateForm((form) => form.aspectRatio = value);
                  }
                },
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            const Expanded(
              child: _FieldLabel('Duration', icon: Icons.timelapse_rounded),
            ),
            FilterChip(
              label: const Text('Auto'),
              selected: controller.form.autoDuration,
              onSelected: controller.form.mode == VideoMode.draftEnhance
                  ? null
                  : (value) => controller.updateForm(
                      (form) => form.autoDuration = value,
                    ),
            ),
          ],
        ),
        Slider(
          min: bflProvider.minDuration.toDouble(),
          max: bflProvider.maxDuration.toDouble(),
          divisions: bflProvider.maxDuration - bflProvider.minDuration,
          label: '${controller.form.durationSeconds}s',
          value: controller.form.durationSeconds.toDouble(),
          onChanged:
              controller.form.autoDuration ||
                  controller.form.mode == VideoMode.draftEnhance
              ? null
              : (value) => controller.updateForm(
                  (form) => form.durationSeconds = value.round(),
                ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            const Text('5 sec', style: TextStyle(fontSize: 9)),
            Text(
              controller.form.autoDuration
                  ? 'Provider chooses'
                  : '${controller.form.durationSeconds} sec',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
            ),
            const Text('20 sec', style: TextStyle(fontSize: 9)),
          ],
        ),
      ];
      final second = <Widget>[
        const _FieldLabel('Finish', icon: Icons.high_quality_rounded),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: _ResolutionButton(
                label: 'HD',
                detail: 'Fast native render',
                active: controller.form.resolution == 'hd',
                onTap: () =>
                    controller.updateForm((form) => form.resolution = 'hd'),
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: _ResolutionButton(
                label: 'Full HD',
                detail: 'Upsampled finish',
                active: controller.form.resolution == 'fhd',
                enabled: !controller.form.draft,
                onTap: () =>
                    controller.updateForm((form) => form.resolution = 'fhd'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (controller.form.mode != VideoMode.draftEnhance) ...<Widget>[
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Synchronized audio',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
            ),
            subtitle: const Text(
              'Dialogue, ambience, and sound',
              style: TextStyle(fontSize: 9),
            ),
            value: controller.form.generateAudio,
            onChanged: (value) =>
                controller.updateForm((form) => form.generateAudio = value),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Fast draft',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
            ),
            subtitle: const Text(
              'HD preview now, enhance later',
              style: TextStyle(fontSize: 9),
            ),
            value: controller.form.draft,
            onChanged: (value) =>
                controller.updateForm((form) => form.draft = value),
          ),
        ],
        Row(
          children: <Widget>[
            const Expanded(
              child: _FieldLabel(
                'Safety tolerance',
                icon: Icons.shield_outlined,
              ),
            ),
            Text(
              '${controller.form.safetyTolerance} / 4',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
            ),
          ],
        ),
        Slider(
          min: 0,
          max: 4,
          divisions: 4,
          value: controller.form.safetyTolerance.toDouble(),
          onChanged: (value) => controller.updateForm(
            (form) => form.safetyTolerance = value.round(),
          ),
        ),
      ];
      if (!columns) {
        return Column(
          children: <Widget>[...first, const SizedBox(height: 20), ...second],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: first,
            ),
          ),
          const SizedBox(width: 22),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: second,
            ),
          ),
        ],
      );
    },
  );
}

class _ResolutionButton extends StatelessWidget {
  const _ResolutionButton({
    required this.label,
    required this.detail,
    required this.active,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final String detail;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: enabled ? 1 : .42,
    child: InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(11),
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: active
              ? context.colors.primary
              : context.colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: active
                ? context.colors.primary
                : context.colors.outlineVariant,
          ),
        ),
        child: Column(
          children: <Widget>[
            Text(
              label,
              style: TextStyle(
                color: active
                    ? context.colors.onPrimary
                    : context.colors.onSurface,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              detail,
              style: TextStyle(
                color: active
                    ? context.colors.onPrimary.withValues(alpha: .72)
                    : context.colors.onSurfaceVariant,
                fontSize: 8,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CostPreview extends StatelessWidget {
  const _CostPreview({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final estimate = controller.currentEstimate;
    final afterMin = controller.credits == null
        ? null
        : (controller.credits! - estimate.maximum)
              .clamp(0, double.infinity)
              .toDouble();
    final afterMax = controller.credits == null
        ? null
        : (controller.credits! - estimate.minimum)
              .clamp(0, double.infinity)
              .toDouble();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ClawnsoleColors.rail,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: 20,
            runSpacing: 10,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const CircleAvatar(
                    radius: 19,
                    backgroundColor: ClawnsoleColors.cobalt,
                    child: Icon(
                      Icons.toll_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'ESTIMATED PROVIDER CHARGE',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 8,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '${formatCreditRange(estimate.minimum, estimate.maximum)} credits',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Text(
                formatUsdRange(estimate.minimum, estimate.maximum),
                style: const TextStyle(
                  color: Color(0xFFA8B9FF),
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          const Divider(color: Colors.white12),
          Row(
            children: <Widget>[
              Expanded(
                child: _BalanceLine(
                  label: 'Available now',
                  value: controller.credits == null
                      ? (controller.hasApiKey ? 'Checking…' : 'Add API key')
                      : '${formatCredits(controller.credits!)} credits',
                ),
              ),
              Expanded(
                child: _BalanceLine(
                  label: 'Estimated after',
                  value: afterMin == null || afterMax == null
                      ? '—'
                      : '${formatCreditRange(afterMin, afterMax)} credits',
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Text(
                '${controller.form.draft ? 'Drafts use the selected provider’s HD draft tier. ' : ''}'
                '${estimate.basis == 'provider-history' ? 'Calibrated from this provider’s exact charges.' : 'Based on the selected provider’s published per-second rate.'} '
                'The exact charge replaces this estimate on submit.',
                style: const TextStyle(color: Colors.white60, fontSize: 9),
              ),
              TextButton(
                onPressed: () =>
                    unawaited(launchUrl(Uri.parse(bflProvider.pricingUrl))),
                child: const Text(
                  'Rate card ↗',
                  style: TextStyle(color: Color(0xFFA8B9FF), fontSize: 9),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BalanceLine extends StatelessWidget {
  const _BalanceLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 8)),
      const SizedBox(height: 2),
      Text(
        value,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    ],
  );
}

class _RecentWork extends StatelessWidget {
  const _RecentWork({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Eyebrow('On the branch'),
                const SizedBox(height: 5),
                Text(
                  'Recent work',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => unawaited(controller.navigate(AppSection.library)),
            child: const Text('View library'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (controller.generations.isEmpty)
        SurfaceCard(
          child: Column(
            children: <Widget>[
              ClawMark(size: 42, color: context.colors.primary),
              const SizedBox(height: 12),
              Text(
                'A quiet branch.',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 5),
              const Text(
                'Your generations will gather here with live progress and playback.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        )
      else
        ...controller.generations
            .take(5)
            .map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: ActivityCard(controller: controller, item: item),
              ),
            ),
      const SizedBox(height: 4),
      SurfaceCard(
        color: context.colors.surfaceContainer,
        padding: const EdgeInsets.all(13),
        child: Wrap(
          spacing: 18,
          runSpacing: 8,
          children: <Widget>[
            _Summary('${controller.generations.length}', 'kept locally'),
            _Summary('${controller.readyCount}', 'complete'),
            _Summary('${controller.workingCount}', 'moving'),
            _Summary(formatCredits(controller.spentCredits), 'credits spent'),
          ],
        ),
      ),
    ],
  );
}

class _Summary extends StatelessWidget {
  const _Summary(this.value, this.label);

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Text(
        value,
        style: TextStyle(
          fontWeight: FontWeight.w900,
          color: context.colors.primary,
        ),
      ),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 9)),
    ],
  );
}
