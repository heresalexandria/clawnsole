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

String formatElapsedDuration(Duration value) {
  final totalSeconds = value.inSeconds.clamp(0, 24 * 60 * 60 * 365);
  final hours = totalSeconds ~/ 3600;
  final minutes = totalSeconds.remainder(3600) ~/ 60;
  final seconds = totalSeconds.remainder(60);
  if (hours > 0) return '${hours}h ${minutes}m ${seconds}s';
  if (minutes > 0) return '${minutes}m ${seconds}s';
  return '${seconds}s';
}

String formatMediaDuration(double seconds) {
  if (!seconds.isFinite || seconds < 0) return 'Unknown';
  final tenths = (seconds * 10).round();
  final hours = tenths ~/ 36000;
  final minutes = tenths.remainder(36000) ~/ 600;
  final wholeSeconds = tenths.remainder(600) ~/ 10;
  final decimal = tenths.remainder(10);
  final secondLabel = wholeSeconds.toString().padLeft(2, '0');
  final fraction = decimal == 0 ? '' : '.$decimal';
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$secondLabel$fraction';
  }
  if (minutes > 0) return '$minutes:$secondLabel$fraction';
  return '$wholeSeconds$fraction s';
}
