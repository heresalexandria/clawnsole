import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_controller.dart';
import '../app/app_theme.dart';
import '../core/api_transcript.dart';
import '../core/models.dart';
import '../core/provider_catalog.dart';
import 'busy_button.dart';
import 'common_widgets.dart';
import 'motion_isolate.dart';

/// Opens the film's API transcript: every provider request Clawnsole made
/// for it on this device, with the payloads it sent and the answers it got.
///
/// This is a troubleshooting surface, so it says what it kept and what it
/// replaced rather than pretending to be the wire. Escape closes it.
Future<void> showApiRequestsModal(
  BuildContext context, {
  required AppController controller,
  required Generation item,
}) => showDialog<void>(
  context: context,
  builder: (dialogContext) =>
      _ApiRequestsModal(controller: controller, item: item),
);

/// Below this width the modal is a page, not a dialog — the film modal's
/// threshold, so both surfaces break at the same place.
const double _pageWidth = 700;
const double _maxDialogWidth = 1040;

/// How tall one body block grows before it scrolls on its own.
const double _bodyMaxHeight = 280;

class _ApiRequestsModal extends StatefulWidget {
  const _ApiRequestsModal({required this.controller, required this.item});

  final AppController controller;
  final Generation item;

  @override
  State<_ApiRequestsModal> createState() => _ApiRequestsModalState();
}

class _ApiRequestsModalState extends State<_ApiRequestsModal> {
  final Set<int> _expanded = <int>{};
  List<ApiRequestRecord>? _records;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final records = await widget.controller.apiRequestsFor(widget.item);
    if (!mounted) return;
    setState(() => _records = records);
  }

  Future<void> _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    widget.controller.showNotice('$what copied to the clipboard.');
  }

  Future<void> _copyAll() => _copy(
    renderTranscript(_records ?? const <ApiRequestRecord>[], film: widget.item),
    'API transcript',
  );

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    if (size.width < _pageWidth) {
      return Dialog.fullscreen(
        backgroundColor: context.colors.surface,
        child: SafeArea(child: _body(context)),
      );
    }
    const inset = 24.0;
    return Dialog(
      insetPadding: const EdgeInsets.all(inset),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: size.height - inset * 2),
        child: SizedBox(
          width: math.min(_maxDialogWidth, size.width - inset * 2),
          child: _body(context),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final records = _records;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _header(context, records),
        Divider(height: 1, thickness: 1, color: context.colors.outlineVariant),
        Flexible(
          child: records == null
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                    key: ValueKey('api-requests-loading'),
                    child: BusySpinner(),
                  ),
                )
              : records.isEmpty
              ? _empty(context)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
                  itemCount: records.length,
                  separatorBuilder: (context, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) =>
                      _row(context, records[index]),
                ),
        ),
        if (records != null && records.isNotEmpty) _footer(context),
      ],
    );
  }

  /// Where the transcript lives and what it deliberately leaves out. Said
  /// on the surface itself, so a pasted transcript is never mistaken for
  /// the complete wire traffic of a whole account.
  Widget _footer(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: context.colors.surfaceContainerLow,
      border: Border(top: BorderSide(color: context.colors.outlineVariant)),
    ),
    padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
    child: Text(
      'Recorded on this device only — transcripts are never synced to '
      'Drive. Credentials are redacted, and uploaded media and base64 '
      'payloads are replaced by size placeholders.',
      key: const ValueKey('api-requests-footnote'),
      style: TextStyle(
        fontSize: 10.5,
        height: 1.45,
        color: context.colors.onSurfaceVariant,
      ),
    ),
  );

  Widget _header(BuildContext context, List<ApiRequestRecord>? records) {
    final item = widget.item;
    final subtitle =
        '${item.localId} · ${providerNameForHistory(item.provider)} · '
        '${item.model}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 10, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text(
                  'API requests',
                  key: ValueKey('api-requests-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (records != null && records.isNotEmpty)
            BusyTextButton.icon(
              key: const ValueKey('api-requests-copy-all'),
              onPressed: _copyAll,
              icon: const Icon(Icons.copy_all_rounded, size: 16),
              label: const Text('Copy all'),
            ),
          IconButton(
            key: const ValueKey('api-requests-close'),
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          Icons.receipt_long_rounded,
          size: 28,
          color: context.colors.onSurfaceVariant,
        ),
        const SizedBox(height: 12),
        Text(
          'No API requests were recorded for this film on this device. '
          'Requests are kept on the device that made them; films made '
          'before this build have none.',
          key: const ValueKey('api-requests-empty'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.5,
            color: context.colors.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );

  Widget _row(BuildContext context, ApiRequestRecord record) {
    final open = _expanded.contains(record.sequence);
    return Container(
      key: ValueKey<String>('api-request-${record.sequence}'),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            key: ValueKey<String>('api-request-toggle-${record.sequence}'),
            onTap: () => setState(() {
              if (!_expanded.remove(record.sequence)) {
                _expanded.add(record.sequence);
              }
            }),
            // The row is the disclosure control: say so, and say which way
            // it will go, so a screen reader is not left with a bare group.
            child: Semantics(
              button: true,
              expanded: open,
              hint: open ? 'Hide details' : 'Show details',
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                child: Row(
                  children: <Widget>[
                    Expanded(child: _summary(context, record)),
                    const SizedBox(width: 6),
                    BusyIconButton(
                      key: ValueKey<String>(
                        'api-request-copy-${record.sequence}',
                      ),
                      tooltip: 'Copy this request',
                      onPressed: () => _copy(
                        record.toTranscriptText(),
                        'Request #${record.sequence}',
                      ),
                      icon: const Icon(Icons.copy_rounded, size: 16),
                    ),
                    MotionIsolate(
                      width: 18,
                      height: 18,
                      child: AnimatedRotation(
                        turns: open ? .5 : 0,
                        duration: const Duration(milliseconds: 160),
                        child: Icon(
                          Icons.expand_more_rounded,
                          size: 18,
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const _TranscriptEyebrow('Request'),
                  _Field(label: 'URL', value: record.url),
                  _Headers(headers: record.requestHeaders),
                  _Block(
                    value: record.requestBody,
                    truncatedBytes: record.requestTruncatedBytes,
                  ),
                  const SizedBox(height: 14),
                  const _TranscriptEyebrow('Response'),
                  if (record.error != null)
                    _Field(label: 'Transport error', value: record.error!)
                  else ...<Widget>[
                    _Field(
                      label: 'Status',
                      value:
                          '${record.statusCode ?? '—'} · '
                          '${record.durationMs} ms',
                    ),
                    _Headers(headers: record.responseHeaders),
                    _Block(
                      value: record.responseBody,
                      truncatedBytes: record.responseTruncatedBytes,
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _summary(BuildContext context, ApiRequestRecord record) {
    final time = record.at.toLocal();
    String pad(int value) => value.toString().padLeft(2, '0');
    final clock = '${pad(time.hour)}:${pad(time.minute)}:${pad(time.second)}';
    final failed = !record.succeeded;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text.rich(
          TextSpan(
            children: <InlineSpan>[
              TextSpan(
                text: '#${record.sequence}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              TextSpan(text: ' · $clock · ${record.method} '),
              TextSpan(
                text: record.shortUrl,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              TextSpan(
                text: ' · ${record.statusLabel}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: failed ? context.colors.error : null,
                ),
              ),
              TextSpan(text: ' · ${record.durationMs} ms'),
            ],
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 2),
        Text(
          '${record.purpose.name} · ${providerNameForHistory(record.provider)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10.5,
            letterSpacing: .4,
            fontWeight: FontWeight.w600,
            color: context.colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _TranscriptEyebrow extends StatelessWidget {
  const _TranscriptEyebrow(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 8),
    child: Eyebrow(label),
  );
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            color: context.colors.onSurfaceVariant,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        SelectableText(
          value,
          style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace'),
        ),
      ],
    ),
  );
}

class _Headers extends StatelessWidget {
  const _Headers({required this.headers});

  final Map<String, String> headers;

  @override
  Widget build(BuildContext context) {
    if (headers.isEmpty) return const SizedBox.shrink();
    final names = headers.keys.toList()..sort();
    return _Field(
      label: 'Headers',
      value: <String>[
        for (final name in names) '$name: ${headers[name]}',
      ].join('\n'),
    );
  }
}

/// A payload: selectable, monospace, and scrolling inside its own box so a
/// long body never stretches the modal.
class _Block extends StatelessWidget {
  const _Block({required this.value, this.truncatedBytes});

  final String? value;
  final int? truncatedBytes;

  @override
  Widget build(BuildContext context) {
    final body = value?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Body',
          style: TextStyle(
            color: context.colors.onSurfaceVariant,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: _bodyMaxHeight),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: context.colors.surfaceContainer,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: context.colors.outlineVariant),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              body.isEmpty ? '(none)' : body,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                height: 1.45,
              ),
            ),
          ),
        ),
        if (truncatedBytes != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Truncated · ${formatTranscriptBytes(truncatedBytes!)} '
              'more was not kept.',
              style: TextStyle(
                fontSize: 10.5,
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}
