import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/pricing.dart';
import 'package:flutter_test/flutter_test.dart';

Generation record(
  String id, {
  String status = 'Ready',
  double? before,
  double? actual,
  double? quote,
  String? source = 'provider-reported',
  int duration = 5,
}) => Generation.fromJson({
  'localId': id,
  'provider': 'atlas',
  'model': 'audit-model',
  'billingUnit': 'usd',
  'status': status,
  'prompt': 'Synthetic accounting fixture',
  'mode': 't2v',
  'config': {'duration': duration},
  'createdAt': '2026-09-05T00:00:00Z',
  'updatedAt': '2026-09-05T00:00:00Z',
  if (before != null) 'creditsBefore': before,
  if (actual != null) ...{'cost': actual, 'realizedCostUsd': actual},
  if (source != null) 'realizedCostSource': source,
  if (quote != null) ...{'quotedCostUsdMin': quote, 'quotedCostUsdMax': quote},
});

void main() {
  const route = ProviderModelPrice(
    provider: 'atlas',
    model: 'audit-model',
    label: 'Audit route',
    usdPerSecond: 1,
    modes: [VideoMode.t2v],
  );
  test('adapter quotes remain unconfirmed when returned with a receipt', () {
    final resolved = resolveProviderCost(record('quoted'), {
      'cost': 2,
      'cost_source': providerQuoteCostSource,
    }, terminal: true);
    expect(resolved.usd, 2);
    expect(resolved.source, providerQuoteCostSource);
    final value = record(
      'quoted',
      actual: resolved.usd,
      quote: 2,
      source: resolved.source,
    );
    expect(countsTowardSpend(value), isFalse);
    expect(routeCostObservation(route, [value]), isNull);
    final settled = resolveProviderCost(value, {
      'actual_cost': 1.75,
    }, terminal: true);
    expect(settled.usd, 1.75);
    expect(settled.source, terminalReportedCostSource);
  });
  test('account spend is never attributed to overlapping individual jobs', () {
    for (final after in [70.0, 100.0, 130.0]) {
      for (final before in [100.0, 90.0]) {
        final resolved = resolveProviderCost(
          record('$before', status: 'Pending', before: before, source: null),
          {},
          balanceAfter: after,
          terminal: true,
        );
        expect(resolved.providerUnits, isNull);
        expect(resolved.usd, isNull);
        expect(resolved.source, isNull);
      }
    }
  });
  test(
    'legacy balance observations retain their amount but never count as spend',
    () {
      for (final source in [
        'balance-delta',
        terminalBalanceDeltaCostSource,
        accountBalanceObservationCostSource,
      ]) {
        for (final status in ['Ready', 'Error', 'Pending']) {
          final old = record(
            'legacy',
            actual: 30,
            source: source,
            status: status,
          );
          final decoded = Generation.fromJson(old.toJson());
          expect(recordedRealizedCostUsd(decoded), 30);
          expect(countsTowardSpend(decoded), isFalse);
          expect(routeCostObservation(route, [decoded]), isNull);
          final resolved = resolveProviderCost(decoded, {}, terminal: true);
          expect(resolved.usd, 30);
          expect(resolved.source, accountBalanceObservationCostSource);
        }
      }
    },
  );
  test(
    'fresh task-specific cost overrides previous account inference, including zero refunds',
    () {
      final old = record(
        'legacy',
        actual: 30,
        source: terminalBalanceDeltaCostSource,
      );
      for (final actual in [10.0, 0.0]) {
        final resolved = resolveProviderCost(
          old,
          {'actual_cost': actual},
          balanceAfter: 70,
          terminal: true,
        );
        expect(resolved.usd, actual);
        expect(resolved.source, terminalReportedCostSource);
      }
    },
  );
  test('route variance uses settled matched pairs only', () {
    final observation = routeCostObservation(route, [
      record('ready', actual: 1, quote: 1),
      record('pending', status: 'Pending', quote: 100),
      record('failed', status: 'Error', actual: 100, quote: 100),
      record('unquoted', actual: 500),
      record('account', actual: 1000, quote: 1, source: 'balance-delta'),
    ]);
    expect(observation?.sampleCount, 1);
    expect(observation?.pairedSampleCount, 1);
    expect(observation?.variancePercent, 0);
    expect(observation?.realizedUsd, 1);
    expect(observation?.quotedUsd, 1);
  });
  test(
    'variance summarizes per-film ratios across differently priced durations',
    () {
      final observation = routeCostObservation(route, [
        record('short', actual: 1, quote: 1, duration: 5),
        record('long', actual: 90, quote: 100, duration: 50),
        record('medium', actual: 20, quote: 10, duration: 10),
      ]);
      // Ratios are 0%, -10%, +100%; their median is 0%, not a ratio of medians.
      expect(observation?.variancePercent, 0);
      expect(observation?.pairedSampleCount, 3);
    },
  );
  test('deterministic published prices are estimates, not settled charges', () {
    final value = record(
      'fixed',
      actual: 2,
      quote: 2,
      source: 'deterministic-route-price',
    );
    expect(countsTowardSpend(value), isFalse);
    expect(routeCostObservation(route, [value]), isNull);
  });
}
