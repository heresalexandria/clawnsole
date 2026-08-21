import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/app_controller.dart';
import '../app/app_theme.dart';
import '../core/models.dart';
import '../core/pricing.dart';
import '../core/provider_catalog.dart';
import 'common_widgets.dart';

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
  final Map<String, String> _results = <String, String>{};
  final TextEditingController _search = TextEditingController();
  String _pricingProvider = 'all';
  bool _createReadyOnly = false;

  @override
  void dispose() {
    for (final controller in _keys.values) {
      controller.dispose();
    }
    _search.dispose();
    super.dispose();
  }

  Future<void> _verifyOrSave(String providerId, {required bool save}) async {
    final candidate = _keys[providerId]!.text;
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
      if (save) _keys[providerId]!.clear();
      _results[providerId] =
          account?.balanceLabel ??
          (account?.balance == null
              ? 'Connected'
              : account!.currency == 'credits'
              ? '${_number(account.balance!)} credits available'
              : '\$${account.balance!.toStringAsFixed(2)} available');
    } on Object catch (error) {
      _results[providerId] = error.toString();
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
                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: widget.controller.providers
                      .map(
                        (provider) => SizedBox(
                          width: width,
                          child: _ProviderCard(
                            provider: provider,
                            controller: widget.controller,
                            keyController: _keys[provider.id]!,
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
              },
            ),
            const SizedBox(height: 24),
            _PricingTable(
              controller: widget.controller,
              providerId: _pricingProvider,
              searchController: _search,
              createReadyOnly: _createReadyOnly,
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
  final String? result;
  final VoidCallback onToggleKey;
  final Future<void> Function() onVerify;
  final Future<void> Function() onSave;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final connected = controller.hasApiKeyFor(provider.id);
    final selected = controller.selectedProviderId == provider.id;
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
                  provider.shortName.characters.first,
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
                          ? 'Ready on this device'
                          : connected
                          ? _connectedProviderLabel(controller)
                          : 'Key required',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: connected
                            ? context.colors.primary
                            : context.colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected) const Icon(Icons.check_circle_rounded, size: 19),
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
              child: const Row(
                children: <Widget>[
                  Icon(Icons.lock_rounded, size: 17),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Ready without a key when Apple Intelligence image creation is enabled on this device.',
                      style: TextStyle(fontSize: 11.5),
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
                labelText: '${provider.shortName} API key',
                hintText: connected
                    ? 'Connected — paste a replacement'
                    : 'Paste key',
                suffixIcon: IconButton(
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
              Text(
                result!,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color:
                      result!.contains('rejected') ||
                          result!.contains('Exception') ||
                          result!.contains('invalid')
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
              if (provider.consoleUrl.isNotEmpty)
                _ExternalLink('Console', provider.consoleUrl),
              _ExternalLink('Docs', provider.docsUrl),
              if (provider.pricingUrl.isNotEmpty)
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

class _PricingTable extends StatelessWidget {
  const _PricingTable({
    required this.controller,
    required this.providerId,
    required this.searchController,
    required this.createReadyOnly,
    required this.onProviderChanged,
    required this.onSearchChanged,
    required this.onCreateReadyChanged,
  });

  final AppController controller;
  final String providerId;
  final TextEditingController searchController;
  final bool createReadyOnly;
  final ValueChanged<String> onProviderChanged;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<bool> onCreateReadyChanged;

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
            .toList()
          ..sort((left, right) {
            final canonical = left.canonicalId.compareTo(right.canonicalId);
            if (canonical != 0) return canonical;
            final provider = providerById(
              left.provider,
            ).name.compareTo(providerById(right.provider).name);
            if (provider != 0) return provider;
            return left.label.compareTo(right.label);
          });
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
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 46,
                dataRowMinHeight: 52,
                dataRowMaxHeight: 64,
                columns: const <DataColumn>[
                  DataColumn(label: Text('Provider')),
                  DataColumn(label: Text('Model')),
                  DataColumn(label: Text('Canonical model')),
                  DataColumn(label: Text('Modes')),
                  DataColumn(numeric: true, label: Text('10 sec')),
                  DataColumn(numeric: true, label: Text('15 sec')),
                  DataColumn(numeric: true, label: Text('20 sec')),
                  DataColumn(numeric: true, label: Text('30 sec')),
                  DataColumn(numeric: true, label: Text('10 sec + refs')),
                  DataColumn(numeric: true, label: Text('Observed')),
                  DataColumn(numeric: true, label: Text('vs quote')),
                ],
                rows: models.map((model) {
                  final observation = routeCostObservation(
                    model,
                    controller.generations,
                  );
                  return DataRow(
                    cells: <DataCell>[
                      DataCell(Text(providerById(model.provider).shortName)),
                      DataCell(
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
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                model.createReady
                                    ? 'Create-ready · ${model.source}'
                                    : model.source,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: context.colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      DataCell(Text(model.canonicalId)),
                      DataCell(
                        Text(
                          model.modes.isEmpty
                              ? 'Video'
                              : model.modes
                                    .map((mode) => mode.shortLabel)
                                    .join(' · '),
                        ),
                      ),
                      for (final seconds in const <int>[10, 15, 20, 30])
                        DataCell(
                          Text(
                            model.pricingUnit == 'per-megapixel-second'
                                ? seconds == 10
                                      ? '${_usd(model.usdPerSecond)}/MP·s'
                                      : '—'
                                : model.hasPriceFor(seconds)
                                ? _usd(model.priceFor(seconds))
                                : '—',
                          ),
                        ),
                      DataCell(
                        Text(
                          model.referenceUsdPerSecond == null ||
                                  !model.hasPriceFor(10)
                              ? '—'
                              : _usd(model.priceFor(10, withReferences: true)),
                        ),
                      ),
                      DataCell(
                        Text(
                          observation == null
                              ? '—'
                              : '${_usd(observation.realizedUsd)} · ${observation.sampleCount}×',
                        ),
                      ),
                      DataCell(
                        Text(
                          observation?.variancePercent == null
                              ? '—'
                              : '${observation!.variancePercent! >= 0 ? '+' : ''}${observation.variancePercent!.toStringAsFixed(1)}%',
                        ),
                      ),
                    ],
                  );
                }).toList(),
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
  });

  final AppController controller;
  final String providerId;
  final TextEditingController searchController;
  final bool createReadyOnly;
  final int modelCount;
  final ValueChanged<String> onProviderChanged;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<bool> onCreateReadyChanged;

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
                    label: Text(item.shortName),
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

String _usd(double value) => '\$${value.toStringAsFixed(value < 1 ? 2 : 2)}';

String _number(double value) =>
    value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1);
