import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/app_controller.dart';
import '../app/app_theme.dart';
import '../core/models.dart';
import '../core/pricing.dart';
import '../core/provider_catalog.dart';
import 'common_widgets.dart';
import 'hardware.dart';

class ProvidersScreen extends StatefulWidget {
  const ProvidersScreen({required this.controller, super.key});

  final AppController controller;

  @override
  State<ProvidersScreen> createState() => _ProvidersScreenState();
}

class _ProvidersScreenState extends State<ProvidersScreen> {
  final Map<String, TextEditingController> _keys =
      <String, TextEditingController>{
        for (final provider in videoProviders)
          provider.id: TextEditingController(),
      };
  final Set<String> _visibleKeys = <String>{};
  final Set<String> _busyProviders = <String>{};
  final Map<String, _ProviderKeyResult> _results =
      <String, _ProviderKeyResult>{};
  final TextEditingController _search = TextEditingController();
  final ScrollController _costTableScroll = ScrollController();
  String _pricingProvider = 'all';
  bool _createReadyOnly = false;
  CostDeskColumn? _costSortColumn;
  bool _costSortAscending = true;

  TextEditingController _keyController(String providerId) =>
      _keys.putIfAbsent(providerId, TextEditingController.new);

  @override
  void dispose() {
    for (final controller in _keys.values) {
      controller.dispose();
    }
    _search.dispose();
    _costTableScroll.dispose();
    super.dispose();
  }

  Future<void> _verifyOrSave(String providerId, {required bool save}) async {
    final candidate = _keyController(providerId).text;
    if (candidate.trim().isEmpty &&
        !widget.controller.hasApiKeyFor(providerId)) {
      widget.controller.showNotice('Paste an API key first.');
      return;
    }
    setState(() {
      _busyProviders.add(providerId);
      _results.remove(providerId);
    });
    try {
      final account = save
          ? await (() async {
              await widget.controller.saveProviderKey(providerId, candidate);
              await widget.controller.refreshProviderModels(providerId);
              return widget.controller.providerAccounts[providerId];
            })()
          : await widget.controller.verifyProviderKey(providerId, candidate);
      if (save) _keyController(providerId).clear();
      _results[providerId] = _ProviderKeyResult(
        account?.balanceLabel ??
            (account?.balance == null
                ? 'Connected'
                : account!.currency == 'credits'
                ? '${_number(account.balance!)} credits available'
                : '\$${account.balance!.toStringAsFixed(2)} available'),
        // Providers without a balance endpoint answer with a "check the
        // console" label; render that as a working link, not inert text.
        opensConsole: account?.balance == null && account?.balanceLabel != null,
      );
    } on Object catch (error) {
      _results[providerId] = _ProviderKeyResult(error.toString());
    } finally {
      if (mounted) setState(() => _busyProviders.remove(providerId));
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 620 ? 16 : 28),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1380),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Eyebrow('Provider desk', icon: Icons.hub_rounded),
            const SizedBox(height: 10),
            Text('Providers.', style: Theme.of(context).textTheme.displayLarge),
            const SizedBox(height: 10),
            Text(
              _providerSecurityDescription(widget.controller),
              style: TextStyle(color: context.colors.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth >= 980
                    ? (constraints.maxWidth - 32) / 3
                    : constraints.maxWidth >= 620
                    ? (constraints.maxWidth - 16) / 2
                    : constraints.maxWidth;
                Widget cards(List<VideoProviderDefinition> providers) => Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: providers
                      .map(
                        (provider) => SizedBox(
                          width: width,
                          child: _ProviderCard(
                            provider: provider,
                            controller: widget.controller,
                            keyController: _keyController(provider.id),
                            keyVisible: _visibleKeys.contains(provider.id),
                            busy: _busyProviders.contains(provider.id),
                            result: _results[provider.id],
                            onToggleKey: () => setState(() {
                              _visibleKeys.contains(provider.id)
                                  ? _visibleKeys.remove(provider.id)
                                  : _visibleKeys.add(provider.id);
                            }),
                            onVerify: () =>
                                _verifyOrSave(provider.id, save: false),
                            onSave: () =>
                                _verifyOrSave(provider.id, save: true),
                            onRemove: () => unawaited(
                              widget.controller.removeProviderKey(provider.id),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                );
                // Starred providers lead the desk under their own label; the
                // rest keep catalog order beneath.
                final favorites = widget.controller.favoriteProviders;
                final others = widget.controller.providers
                    .where(
                      (provider) =>
                          !widget.controller.isFavoriteProvider(provider.id),
                    )
                    .toList();
                if (favorites.isEmpty) return cards(others);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const Eyebrow('Favorites', icon: Icons.star_rounded),
                    const SizedBox(height: 10),
                    cards(favorites),
                    if (others.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 22),
                      const Eyebrow('Other providers'),
                      const SizedBox(height: 10),
                      cards(others),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            _PricingTable(
              controller: widget.controller,
              providerId: _pricingProvider,
              searchController: _search,
              createReadyOnly: _createReadyOnly,
              columns: CostDeskColumn.visibleFor(
                widget.controller.costDeskColumns,
              ),
              sortColumn: _costSortColumn,
              sortAscending: _costSortAscending,
              tableScroll: _costTableScroll,
              onProviderChanged: (value) => setState(() {
                _pricingProvider = value;
                _createReadyOnly = value == 'atlas';
                if (value != 'all') {
                  unawaited(widget.controller.refreshProviderModels(value));
                }
              }),
              onSearchChanged: (_) => setState(() {}),
              onCreateReadyChanged: (value) =>
                  setState(() => _createReadyOnly = value),
              onSortChanged: (column, ascending) => setState(() {
                _costSortColumn = column;
                _costSortAscending = ascending;
              }),
              onColumnsChanged: () => setState(() {}),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    required this.provider,
    required this.controller,
    required this.keyController,
    required this.keyVisible,
    required this.busy,
    required this.onToggleKey,
    required this.onVerify,
    required this.onSave,
    required this.onRemove,
    this.result,
  });

  final VideoProviderDefinition provider;
  final AppController controller;
  final TextEditingController keyController;
  final bool keyVisible;
  final bool busy;
  final _ProviderKeyResult? result;
  final VoidCallback onToggleKey;
  final Future<void> Function() onVerify;
  final Future<void> Function() onSave;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final connected = controller.hasApiKeyFor(provider.id);
    final selected = controller.selectedProviderId == provider.id;
    final favorite = controller.isFavoriteProvider(provider.id);
    return SurfaceCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              CircleAvatar(
                backgroundColor: selected
                    ? context.colors.primary
                    : context.colors.secondaryContainer,
                child: Text(
                  provider.name.characters.first,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: selected
                        ? context.colors.onPrimary
                        : context.colors.onSecondaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      provider.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      !provider.requiresApiKey
                          ? (controller.localGenerationAvailable
                                ? 'Ready on this device'
                                : 'Needs iOS 18.4 and Apple Intelligence')
                          : connected
                          ? _connectedProviderLabel(controller)
                          : 'Key required',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color:
                            connected ||
                                (!provider.requiresApiKey &&
                                    controller.localGenerationAvailable)
                            ? context.colors.primary
                            : context.colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected) const Icon(Icons.check_circle_rounded, size: 19),
              IconButton(
                key: ValueKey('provider-card-star-${provider.id}'),
                tooltip: favorite
                    ? 'Remove from favorites'
                    : 'Add to favorites',
                onPressed: () =>
                    unawaited(controller.toggleFavoriteProvider(provider.id)),
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  favorite ? Icons.star_rounded : Icons.star_border_rounded,
                  color: favorite ? context.tokens.brass : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            provider.description,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: context.colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: selected
                ? null
                : () => unawaited(controller.selectProvider(provider.id)),
            icon: const Icon(Icons.movie_creation_outlined, size: 16),
            label: Text(selected ? 'Selected for Create' : 'Use in Create'),
          ),
          const SizedBox(height: 12),
          if (!provider.requiresApiKey) ...<Widget>[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.colors.primaryContainer,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.lock_rounded, size: 17),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      controller.localGenerationAvailable
                          ? 'Ready without a key: Apple Intelligence image creation is enabled on this device.'
                          : 'Needs an iPhone or iPad with iOS 18.4 or later and Apple Intelligence image creation turned on in Settings.',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...<Widget>[
            TextField(
              controller: keyController,
              obscureText: !keyVisible,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (_) {},
              decoration: InputDecoration(
                labelText: '${provider.name} API key',
                hintText: connected
                    ? 'Connected — paste a replacement'
                    : 'Paste key',
                suffixIcon: IconButton(
                  tooltip: keyVisible
                      ? 'Hide ${provider.name} API key'
                      : 'Show ${provider.name} API key',
                  onPressed: onToggleKey,
                  icon: Icon(
                    keyVisible
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                  ),
                ),
              ),
            ),
            if (result != null) ...<Widget>[
              const SizedBox(height: 8),
              if (result!.opensConsole && provider.consoleUrl.isNotEmpty)
                _ExternalLink(
                  result!.message.replaceFirst(RegExp(r'\s*↗\s*$'), ''),
                  provider.consoleUrl,
                )
              else
                Text(
                  result!.message,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color:
                        result!.message.contains('rejected') ||
                            result!.message.contains('Exception') ||
                            result!.message.contains('invalid')
                        ? context.colors.error
                        : context.colors.primary,
                  ),
                ),
            ],
            const SizedBox(height: 11),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: <Widget>[
                FilledButton(
                  onPressed: busy ? null : () => unawaited(onSave()),
                  child: busy
                      ? const SizedBox.square(
                          dimension: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(connected ? 'Replace key' : 'Verify & save'),
                ),
                TextButton(
                  onPressed: busy ? null : () => unawaited(onVerify()),
                  child: const Text('Test'),
                ),
                if (connected)
                  TextButton(
                    onPressed: onRemove,
                    child: Text(
                      'Remove',
                      style: TextStyle(color: context.colors.error),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 9),
          Wrap(
            spacing: 12,
            children: <Widget>[
              // A keyless on-device provider has no console to sign in to
              // and nothing to price; only its documentation applies.
              if (provider.consoleUrl.isNotEmpty && !provider.isLocal)
                _ExternalLink('Console', provider.consoleUrl),
              _ExternalLink('Docs', provider.docsUrl),
              if (provider.pricingUrl.isNotEmpty && !provider.isLocal)
                _ExternalLink('Pricing', provider.pricingUrl),
            ],
          ),
        ],
      ),
    );
  }
}

String _providerSecurityDescription(
  AppController controller,
) => switch (controller.settingsVaultStatus.state) {
  SettingsVaultState.ready || SettingsVaultState.syncing =>
    'Choose where Clawnsole renders. Provider keys stay in secure storage and sync through your encrypted Google Drive vault.',
  SettingsVaultState.pending =>
    'Choose where Clawnsole renders. Provider keys are secure on this device; encrypted Drive sync is pending.',
  SettingsVaultState.locked =>
    'Choose where Clawnsole renders. Local provider keys remain available; unlock encrypted settings sync in Settings to receive changes from other devices.',
  SettingsVaultState.setupRequired =>
    'Choose where Clawnsole renders. Provider keys stay in secure storage; encrypted cross-device sync can be set up in Settings.',
  _ =>
    'Choose where Clawnsole renders, keep credentials secure on this device, and compare a generation before you spend.',
};

String _connectedProviderLabel(AppController controller) =>
    switch (controller.settingsVaultStatus.state) {
      SettingsVaultState.ready ||
      SettingsVaultState.syncing => 'Connected · encrypted sync on',
      SettingsVaultState.pending => 'Connected · sync pending',
      SettingsVaultState.locked => 'Connected here · vault locked',
      _ => 'Connected securely on this device',
    };

class _ProviderKeyResult {
  const _ProviderKeyResult(this.message, {this.opensConsole = false});

  final String message;
  final bool opensConsole;
}

class _ExternalLink extends StatelessWidget {
  const _ExternalLink(this.label, this.url);

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => unawaited(launchUrl(Uri.parse(url))),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        '$label ↗',
        style: TextStyle(
          color: context.colors.primary,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

/// Identity, labeling, and sorting behavior for one cost-desk column. The
/// declaration order is the default display order, and [id] is the stable
/// string persisted in [AppPreferences.costDeskColumns].
enum CostDeskColumn {
  provider(
    id: 'provider',
    label: 'Provider',
    tooltip: 'Which provider serves this route',
  ),
  model(
    id: 'model',
    label: 'Model',
    tooltip: 'Display name and pricing source for this route',
  ),
  canonical(
    id: 'canonical',
    label: 'Canonical model',
    tooltip: 'Canonical identity shared by equivalent routes across providers',
  ),
  providerModel(
    id: 'providerModel',
    label: 'Provider model',
    tooltip: 'The provider’s own route id, exactly as the API expects it',
  ),
  modes(
    id: 'modes',
    label: 'Modes',
    tooltip: 'Generation modes this route supports',
  ),
  sec10(
    id: 'sec10',
    label: '10 sec',
    numeric: true,
    tooltip: 'Estimated cost of a 10-second clip',
  ),
  sec15(
    id: 'sec15',
    label: '15 sec',
    numeric: true,
    tooltip: 'Estimated cost of a 15-second clip',
  ),
  sec20(
    id: 'sec20',
    label: '20 sec',
    numeric: true,
    tooltip: 'Estimated cost of a 20-second clip',
  ),
  sec30(
    id: 'sec30',
    label: '30 sec',
    numeric: true,
    tooltip: 'Estimated cost of a 30-second clip',
  ),
  refs10(
    id: 'refs10',
    label: '10 sec + refs',
    numeric: true,
    tooltip: 'Estimated 10-second cost at the provider’s reference rate',
  ),
  observed(
    id: 'observed',
    label: 'Observed',
    numeric: true,
    tooltip: 'Median realized cost from saved generations',
  ),
  vsQuote(
    id: 'vsQuote',
    label: 'vs quote',
    numeric: true,
    tooltip: 'Observed cost versus the quoted price',
  );

  const CostDeskColumn({
    required this.id,
    required this.label,
    required this.tooltip,
    this.numeric = false,
  });

  final String id;
  final String label;
  final String tooltip;
  final bool numeric;

  static CostDeskColumn? byId(String id) {
    for (final column in values) {
      if (column.id == id) return column;
    }
    return null;
  }

  /// Visible columns for a persisted preference: null keeps every column in
  /// the default order, unknown ids are ignored, and ids missing from the
  /// list stay hidden. The provider column always stays visible so rows keep
  /// an anchor.
  static List<CostDeskColumn> visibleFor(List<String>? ids) {
    if (ids == null) return List<CostDeskColumn>.of(values);
    final visible = <CostDeskColumn>[];
    for (final id in ids) {
      final column = byId(id);
      if (column != null && !visible.contains(column)) visible.add(column);
    }
    if (!visible.contains(provider)) visible.insert(0, provider);
    return visible;
  }
}

class _PricingTable extends StatelessWidget {
  const _PricingTable({
    required this.controller,
    required this.providerId,
    required this.searchController,
    required this.createReadyOnly,
    required this.columns,
    required this.sortColumn,
    required this.sortAscending,
    required this.tableScroll,
    required this.onProviderChanged,
    required this.onSearchChanged,
    required this.onCreateReadyChanged,
    required this.onSortChanged,
    required this.onColumnsChanged,
  });

  final AppController controller;
  final String providerId;
  final TextEditingController searchController;
  final bool createReadyOnly;
  final List<CostDeskColumn> columns;
  final CostDeskColumn? sortColumn;
  final bool sortAscending;
  final ScrollController tableScroll;
  final ValueChanged<String> onProviderChanged;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<bool> onCreateReadyChanged;
  final void Function(CostDeskColumn column, bool ascending) onSortChanged;
  final VoidCallback onColumnsChanged;

  static int _defaultCompare(
    ProviderModelPrice left,
    ProviderModelPrice right,
  ) {
    final canonical = left.canonicalId.compareTo(right.canonicalId);
    if (canonical != 0) return canonical;
    final provider = providerById(
      left.provider,
    ).name.compareTo(providerById(right.provider).name);
    if (provider != 0) return provider;
    return left.label.compareTo(right.label);
  }

  static String _modesLabel(ProviderModelPrice model) => model.modes.isEmpty
      ? 'Video'
      : model.modes.map((mode) => mode.shortLabel).join(' · ');

  /// The comparable clip price a seconds column renders, or null when the
  /// route has no price for that duration (frame- and megapixel-based routes
  /// quote a different unit, so they compare as unpriced).
  static double? _clipPrice(ProviderModelPrice model, int seconds) =>
      model.pricingUnit != 'per-second' || !model.hasPriceFor(seconds)
      ? null
      : model.priceFor(seconds);

  static double? _referencePrice(ProviderModelPrice model) =>
      model.referenceUsdPerSecond == null || !model.hasPriceFor(10)
      ? null
      : model.priceFor(10, withReferences: true);

  static double? _numericSortValue(
    CostDeskColumn column,
    ProviderModelPrice model,
    RouteCostObservation? observation,
  ) => switch (column) {
    CostDeskColumn.sec10 => _clipPrice(model, 10),
    CostDeskColumn.sec15 => _clipPrice(model, 15),
    CostDeskColumn.sec20 => _clipPrice(model, 20),
    CostDeskColumn.sec30 => _clipPrice(model, 30),
    CostDeskColumn.refs10 => _referencePrice(model),
    CostDeskColumn.observed => observation?.realizedUsd,
    CostDeskColumn.vsQuote => observation?.variancePercent,
    _ => null,
  };

  static String _textSortValue(
    CostDeskColumn column,
    ProviderModelPrice model,
  ) => switch (column) {
    CostDeskColumn.provider => providerById(model.provider).name,
    CostDeskColumn.model => model.label,
    CostDeskColumn.canonical => model.canonicalId,
    CostDeskColumn.providerModel => model.model,
    CostDeskColumn.modes => _modesLabel(model),
    _ => '',
  };

  /// Sorts by the chosen column, keeping rows without a value last in both
  /// directions and falling back to the canonical ordering to break ties.
  void _sortModels(
    List<ProviderModelPrice> models,
    Map<ProviderModelPrice, RouteCostObservation?> observations,
  ) {
    final column = sortColumn;
    if (column == null || !columns.contains(column)) {
      models.sort(_defaultCompare);
      return;
    }
    final sign = sortAscending ? 1 : -1;
    models.sort((left, right) {
      int compared;
      if (column.numeric) {
        final leftValue = _numericSortValue(column, left, observations[left]);
        final rightValue = _numericSortValue(
          column,
          right,
          observations[right],
        );
        if (leftValue == null || rightValue == null) {
          if (leftValue == null && rightValue == null) {
            return _defaultCompare(left, right);
          }
          return leftValue == null ? 1 : -1;
        }
        compared = leftValue.compareTo(rightValue) * sign;
      } else {
        compared =
            _textSortValue(column, left).toLowerCase().compareTo(
              _textSortValue(column, right).toLowerCase(),
            ) *
            sign;
      }
      return compared == 0 ? _defaultCompare(left, right) : compared;
    });
  }

  DataCell _secondsCell(ProviderModelPrice model, int seconds) => DataCell(
    Text(
      model.pricingUnit == 'per-megapixel-second'
          ? seconds == 10
                ? '${_usd(model.usdPerSecond)}/MP·s'
                : '—'
          : model.pricingUnit == 'per-frame'
          ? seconds == 10
                ? '${_usd(model.usdPerSecond)}/frame'
                : '—'
          : model.hasPriceFor(seconds)
          ? _usd(model.priceFor(seconds))
          : '—',
    ),
  );

  DataCell _cell(
    BuildContext context,
    CostDeskColumn column,
    ProviderModelPrice model,
    RouteCostObservation? observation,
  ) => switch (column) {
    CostDeskColumn.provider => DataCell(
      Text(providerById(model.provider).name),
    ),
    CostDeskColumn.model => DataCell(
      SizedBox(
        width: 285,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              model.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Tooltip(
              message: model.source,
              child: Text(
                model.createReady
                    ? 'Create-ready · ${model.source}'
                    : model.source,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    CostDeskColumn.canonical => DataCell(Text(model.canonicalId)),
    CostDeskColumn.providerModel => DataCell(
      Tooltip(
        message: model.model,
        child: SizedBox(
          width: 220,
          child: Text(
            model.model,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11.5,
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    ),
    CostDeskColumn.modes => DataCell(Text(_modesLabel(model))),
    CostDeskColumn.sec10 => _secondsCell(model, 10),
    CostDeskColumn.sec15 => _secondsCell(model, 15),
    CostDeskColumn.sec20 => _secondsCell(model, 20),
    CostDeskColumn.sec30 => _secondsCell(model, 30),
    CostDeskColumn.refs10 => DataCell(
      Text(
        _referencePrice(model) == null
            ? '—'
            : _usd(model.priceFor(10, withReferences: true)),
      ),
    ),
    CostDeskColumn.observed => DataCell(
      Text(
        observation == null
            ? '—'
            : '${_usd(observation.realizedUsd)} · ${observation.sampleCount}×',
      ),
    ),
    CostDeskColumn.vsQuote => DataCell(
      Text(
        observation?.variancePercent == null
            ? '—'
            : '${observation!.variancePercent! >= 0 ? '+' : ''}${observation.variancePercent!.toStringAsFixed(1)}%',
      ),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final query = searchController.text.trim().toLowerCase();
    final models =
        (providerId == 'all'
                ? controller.providers.expand(
                    (provider) =>
                        controller.providerPrices[provider.id] ??
                        const <ProviderModelPrice>[],
                  )
                : controller.providerPrices[providerId] ??
                      const <ProviderModelPrice>[])
            .where(
              (model) =>
                  (!createReadyOnly || model.createReady) &&
                  (query.isEmpty ||
                      model.label.toLowerCase().contains(query) ||
                      model.model.toLowerCase().contains(query) ||
                      model.canonicalId.toLowerCase().contains(query) ||
                      providerById(
                        model.provider,
                      ).name.toLowerCase().contains(query)),
            )
            .toList();
    final observations = <ProviderModelPrice, RouteCostObservation?>{
      for (final model in models)
        model: routeCostObservation(model, controller.generations),
    };
    _sortModels(models, observations);
    final pricingDescription = providerId == 'all'
        ? 'Canonical model identities align equivalent routes across providers. Quotes remain route-specific; observed costs use saved generations.'
        : '${providerById(providerId).pricingSource}. Estimates are USD and references use the provider’s reference rate when it differs.';
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Cost desk',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  pricingDescription,
                  style: TextStyle(
                    color: context.colors.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 14),
                _PricingFilters(
                  controller: controller,
                  providerId: providerId,
                  searchController: searchController,
                  createReadyOnly: createReadyOnly,
                  modelCount: models.length,
                  onProviderChanged: onProviderChanged,
                  onSearchChanged: onSearchChanged,
                  onCreateReadyChanged: onCreateReadyChanged,
                  onColumnsChanged: onColumnsChanged,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: context.colors.outlineVariant),
          if (models.isEmpty)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Text('No models match this view.'),
            )
          else
            // The horizontal scroller carries its own always-visible scrollbar
            // and accepts mouse drags, so desktop testers can always reach the
            // rightmost columns; the clip keeps rows inside the card's
            // rounded corners.
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(16),
              ),
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  scrollbars: false,
                  dragDevices: <PointerDeviceKind>{
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.stylus,
                    PointerDeviceKind.trackpad,
                  },
                ),
                child: Scrollbar(
                  controller: tableScroll,
                  thumbVisibility: true,
                  trackVisibility: true,
                  child: SingleChildScrollView(
                    controller: tableScroll,
                    scrollDirection: Axis.horizontal,
                    primary: false,
                    padding: const EdgeInsets.only(bottom: 12),
                    child: DataTable(
                      headingRowHeight: 46,
                      dataRowMinHeight: 52,
                      dataRowMaxHeight: 64,
                      sortColumnIndex:
                          sortColumn == null || !columns.contains(sortColumn)
                          ? null
                          : columns.indexOf(sortColumn!),
                      sortAscending: sortAscending,
                      columns: <DataColumn>[
                        for (final column in columns)
                          DataColumn(
                            label: Text(column.label),
                            tooltip: column.tooltip,
                            numeric: column.numeric,
                            onSort: (index, ascending) =>
                                onSortChanged(columns[index], ascending),
                          ),
                      ],
                      rows: <DataRow>[
                        for (final model in models)
                          DataRow(
                            cells: <DataCell>[
                              for (final column in columns)
                                _cell(
                                  context,
                                  column,
                                  model,
                                  observations[model],
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PricingFilters extends StatelessWidget {
  const _PricingFilters({
    required this.controller,
    required this.providerId,
    required this.searchController,
    required this.createReadyOnly,
    required this.modelCount,
    required this.onProviderChanged,
    required this.onSearchChanged,
    required this.onCreateReadyChanged,
    required this.onColumnsChanged,
  });

  final AppController controller;
  final String providerId;
  final TextEditingController searchController;
  final bool createReadyOnly;
  final int modelCount;
  final ValueChanged<String> onProviderChanged;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<bool> onCreateReadyChanged;
  final VoidCallback onColumnsChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final providerPicker = SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SegmentedButton<String>(
          segments: <ButtonSegment<String>>[
            const ButtonSegment<String>(value: 'all', label: Text('Compare')),
            ...controller.providers
                .where((item) => item.requiresApiKey)
                .map(
                  (item) => ButtonSegment<String>(
                    value: item.id,
                    label: Text(item.name),
                  ),
                ),
          ],
          selected: <String>{providerId},
          onSelectionChanged: (value) => onProviderChanged(value.single),
        ),
      );
      final search = TextField(
        key: const ValueKey('provider-cost-search'),
        controller: searchController,
        onChanged: onSearchChanged,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search_rounded, size: 18),
          hintText: 'Search models',
          isDense: true,
        ),
      );
      final options = Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          FilterChip(
            label: const Text('Create-ready'),
            selected: createReadyOnly,
            onSelected: onCreateReadyChanged,
          ),
          _CostDeskColumnsButton(
            controller: controller,
            onChanged: onColumnsChanged,
          ),
          Text('$modelCount models'),
        ],
      );

      if (constraints.maxWidth >= 760) {
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            providerPicker,
            SizedBox(width: 280, child: search),
            options,
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          providerPicker,
          const SizedBox(height: 10),
          search,
          const SizedBox(height: 8),
          options,
        ],
      );
    },
  );
}

/// One "Columns" console key that opens an anchored panel for showing,
/// hiding, and reordering cost-desk columns. Changes persist through the
/// controller's preferences; the provider column always stays visible so
/// every row keeps its anchor.
class _CostDeskColumnsButton extends StatefulWidget {
  const _CostDeskColumnsButton({
    required this.controller,
    required this.onChanged,
  });

  final AppController controller;
  final VoidCallback onChanged;

  @override
  State<_CostDeskColumnsButton> createState() => _CostDeskColumnsButtonState();
}

class _CostDeskColumnsButtonState extends State<_CostDeskColumnsButton> {
  final MenuController _menu = MenuController();

  List<CostDeskColumn> get _visible =>
      CostDeskColumn.visibleFor(widget.controller.costDeskColumns);

  int get _activeCount {
    final visible = _visible;
    final hidden = CostDeskColumn.values.length - visible.length;
    final reordered = !listEquals(
      visible,
      CostDeskColumn.values.where(visible.contains).toList(),
    );
    return hidden + (reordered ? 1 : 0);
  }

  void _commit(List<CostDeskColumn> visible) {
    unawaited(
      widget.controller.setCostDeskColumns(
        listEquals(visible, CostDeskColumn.values)
            ? null
            : visible.map((column) => column.id).toList(),
      ),
    );
    widget.onChanged();
  }

  void _toggle(CostDeskColumn column) {
    final visible = List<CostDeskColumn>.of(_visible);
    if (visible.contains(column)) {
      if (column == CostDeskColumn.provider) return;
      visible.remove(column);
    } else {
      visible.add(column);
    }
    _commit(visible);
  }

  void _move(CostDeskColumn column, int delta) {
    final visible = List<CostDeskColumn>.of(_visible);
    final index = visible.indexOf(column);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= visible.length) return;
    visible
      ..removeAt(index)
      ..insert(target, column);
    _commit(visible);
  }

  Widget _columnRow(
    BuildContext context,
    CostDeskColumn column,
    List<CostDeskColumn> visible,
  ) {
    final shown = visible.contains(column);
    final index = visible.indexOf(column);
    return Row(
      children: <Widget>[
        Checkbox(
          key: ValueKey('cost-desk-column-toggle-${column.id}'),
          value: shown,
          visualDensity: VisualDensity.compact,
          onChanged: column == CostDeskColumn.provider
              ? null
              : (_) => _toggle(column),
        ),
        Expanded(
          child: Text(
            column.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          key: ValueKey('cost-desk-column-up-${column.id}'),
          onPressed: shown && index > 0 ? () => _move(column, -1) : null,
          icon: const Icon(Icons.arrow_upward_rounded, size: 16),
          visualDensity: VisualDensity.compact,
          tooltip: 'Move up',
        ),
        IconButton(
          key: ValueKey('cost-desk-column-down-${column.id}'),
          onPressed: shown && index < visible.length - 1
              ? () => _move(column, 1)
              : null,
          icon: const Icon(Icons.arrow_downward_rounded, size: 16),
          visualDensity: VisualDensity.compact,
          tooltip: 'Move down',
        ),
      ],
    );
  }

  Widget _panel(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final visible = _visible;
      final ordered = <CostDeskColumn>[
        ...visible,
        ...CostDeskColumn.values.where((column) => !visible.contains(column)),
      ];
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 316, maxHeight: 420),
        child: SingleChildScrollView(
          primary: false,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (_activeCount > 0) ...<Widget>[
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    key: const ValueKey('cost-desk-columns-reset'),
                    onPressed: () {
                      unawaited(widget.controller.setCostDeskColumns(null));
                      widget.onChanged();
                    },
                    icon: const Icon(Icons.restart_alt_rounded, size: 16),
                    label: const Text('Reset columns'),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              for (final column in ordered)
                _columnRow(context, column, visible),
            ],
          ),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final active = _activeCount;
    final foreground = active > 0
        ? context.colors.onPrimary
        : context.colors.onSurface;
    return MenuAnchor(
      controller: _menu,
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll<Color>(context.colors.surface),
        elevation: const WidgetStatePropertyAll<double>(10),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: context.colors.outlineVariant),
          ),
        ),
      ),
      menuChildren: <Widget>[_panel(context)],
      builder: (context, menu, _) => Tooltip(
        message: 'Show, hide, and reorder cost-desk columns',
        child: InkWell(
          key: const ValueKey('cost-desk-columns'),
          borderRadius: BorderRadius.circular(10),
          onTap: () => menu.isOpen ? menu.close() : menu.open(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: consoleKeyDecoration(
              context,
              selected: active > 0,
              radius: 10,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.view_week_rounded, size: 15, color: foreground),
                const SizedBox(width: 6),
                Text(
                  'Columns',
                  style: TextStyle(
                    color: foreground,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (active > 0) ...<Widget>[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5.5,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: context.colors.onPrimary.withValues(alpha: .2),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$active',
                      style: TextStyle(
                        color: context.colors.onPrimary,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _usd(double value) => '\$${value.toStringAsFixed(value < 1 ? 2 : 2)}';

String _number(double value) =>
    value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1);
