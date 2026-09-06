import 'package:flutter/material.dart';

import '../app/app_theme.dart';

/// A compact readout of the whole submitted prompt, including added direction.
class PromptCharacterCounter extends StatelessWidget {
  const PromptCharacterCounter({
    required this.used,
    required this.limit,
    required this.modelLabel,
    required this.isProviderLimit,
    super.key,
  }) : assert(used >= 0),
       assert(limit > 0);

  final int used;
  final int limit;
  final String modelLabel;
  final bool isProviderLimit;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fraction = (used / limit).clamp(0.0, 1.0);
    final color = switch (fraction) {
      >= .95 => colors.error,
      >= .8 => dark ? Colors.orange.shade300 : Colors.orange.shade800,
      _ => dark ? const Color(0xFF90B876) : ClawnsoleColors.signalGreen,
    };
    final remaining = limit - used;
    final allowance = remaining < 0
        ? '${-remaining} characters over the limit'
        : '$remaining characters remaining';
    final limitDescription = isProviderLimit
        ? '$modelLabel accepts up to $limit characters'
        : '$limit-character editor limit; $modelLabel has not published a limit';
    final description = '$used of $limit characters used; $allowance';

    return Tooltip(
      message: '$description. $limitDescription.',
      excludeFromSemantics: true,
      child: Semantics(
        container: true,
        label: 'Prompt character budget',
        value: description,
        hint: limitDescription,
        child: ExcludeSemantics(
          child: Padding(
            key: const ValueKey('prompt-character-limit'),
            padding: const EdgeInsets.only(right: 4),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 64),
              child: Stack(
                alignment: AlignmentDirectional.topEnd,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '$used / $limit',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: SizedBox(
                        height: 3,
                        child: ColoredBox(
                          color: dark
                              ? const Color(0xFF555555)
                              : const Color(0xFFD1D1D1),
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: FractionallySizedBox(
                              key: const ValueKey('prompt-character-progress'),
                              widthFactor: fraction,
                              heightFactor: 1,
                              child: ColoredBox(color: color),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
