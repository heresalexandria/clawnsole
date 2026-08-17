import 'package:intl/intl.dart';

import '../core/pricing.dart';

String formatCredits(double value) => NumberFormat.decimalPatternDigits(
  decimalDigits: value % 1 == 0 ? 0 : 1,
).format(value);

String formatCreditRange(double minimum, double maximum) => minimum == maximum
    ? formatCredits(minimum)
    : '${formatCredits(minimum)}–${formatCredits(maximum)}';

String formatUsd(double credits) =>
    NumberFormat.simpleCurrency(name: 'USD').format(creditsToUsd(credits));

String formatUsdRange(double minimum, double maximum) => minimum == maximum
    ? formatUsd(minimum)
    : '${formatUsd(minimum)}–${formatUsd(maximum)}';

String formatUsdAmount(double value) =>
    NumberFormat.simpleCurrency(name: 'USD').format(value);

String formatUsdAmountRange(double minimum, double maximum) =>
    minimum == maximum
    ? formatUsdAmount(minimum)
    : '${formatUsdAmount(minimum)}–${formatUsdAmount(maximum)}';

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(bytes > 10240 ? 0 : 1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
}

String relativeTime(DateTime value) {
  final difference = DateTime.now().difference(value.toLocal());
  if (difference.inSeconds < 60) return 'Just now';
  if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
  if (difference.inHours < 24) return '${difference.inHours}h ago';
  return DateFormat('MMM d').format(value.toLocal());
}

String formatTimestamp(DateTime value) =>
    DateFormat('MMM d, y · h:mm:ss a').format(value.toLocal());
