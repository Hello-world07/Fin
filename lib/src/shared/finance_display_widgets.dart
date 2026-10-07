import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';

class AmountText extends StatelessWidget {
  const AmountText(this.paise, {super.key, this.style, this.maxLines});

  final int paise;
  final TextStyle? style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) => Text(
    formatMoney(paise),
    style: (style ?? Theme.of(context).textTheme.bodyMedium)?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
    maxLines: maxLines,
    overflow: maxLines == null ? null : TextOverflow.ellipsis,
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

class MiniProgressRing extends StatelessWidget {
  const MiniProgressRing({
    super.key,
    required this.progress,
    this.size = 40,
    this.strokeWidth = 4,
    this.backgroundColor,
    this.child,
  });

  final double progress;
  final double size;
  final double strokeWidth;
  final Color? backgroundColor;
  final Widget? child;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Stack(
      alignment: Alignment.center,
      children: [
        SizedBox.square(
          dimension: size,
          child: CircularProgressIndicator(
            value: progress.clamp(0, 1),
            strokeWidth: strokeWidth,
            backgroundColor: backgroundColor,
          ),
        ),
        ?child,
      ],
    ),
  );
}

class SegmentedProgressStrip extends StatelessWidget {
  const SegmentedProgressStrip({
    super.key,
    required this.installments,
    required this.paidInstallments,
  });

  final int installments;
  final int paidInstallments;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (var index = 0; index < installments; index++) ...[
          if (index > 0) const SizedBox(width: 3),
          Expanded(
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: index < paidInstallments
                    ? colors.primary
                    : colors.outlineVariant,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.detail});

  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
      if (detail != null) ...[
        const SizedBox(height: 2),
        Text(
          detail!,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).brightness == Brightness.light
                ? AppTheme.mutedText
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ],
  );
}
