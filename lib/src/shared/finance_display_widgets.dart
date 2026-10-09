import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../core/privacy_reveal.dart';

class AmountText extends StatefulWidget {
  const AmountText(this.paise, {super.key, this.style, this.maxLines});

  final int paise;
  final TextStyle? style;
  final int? maxLines;

  @override
  State<AmountText> createState() => _AmountTextState();
}

class FinanceTonalTile extends StatelessWidget {
  const FinanceTonalTile({
    super.key,
    required this.leading,
    required this.content,
    required this.trailing,
    required this.onTap,
  });

  final Widget leading;
  final Widget content;
  final Widget trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(child: content),
            const SizedBox(width: 8),
            trailing,
          ],
        ),
      ),
    ),
  );
}

class DueListHeader extends StatelessWidget {
  const DueListHeader(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _AmountTextState extends State<AmountText> {
  bool _revealed = false;
  bool _held = false;
  Timer? _peekTimer;

  @override
  void dispose() {
    _peekTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onLongPressStart: (_) async {
      _peekTimer?.cancel();
      _peekTimer = null;
      _held = true;
      final allowed =
          !privacyAmountsHidden ||
          await PrivacyRevealGate.instance.authorize(context);
      if (!mounted || !allowed) return;
      setState(() => _revealed = true);
      if (!_held) {
        _peekTimer?.cancel();
        _peekTimer = Timer(const Duration(seconds: 3), () {
          _peekTimer = null;
          if (mounted) setState(() => _revealed = false);
        });
      }
    },
    onLongPressEnd: (_) {
      _held = false;
      if (mounted && _peekTimer == null) setState(() => _revealed = false);
    },
    child: Text(
      _revealed ? formatMoneyUnmasked(widget.paise) : formatMoney(widget.paise),
      style: (widget.style ?? Theme.of(context).textTheme.bodyMedium)?.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      maxLines: widget.maxLines,
      overflow: widget.maxLines == null ? null : TextOverflow.ellipsis,
    ),
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
            backgroundColor:
                backgroundColor ??
                (Theme.of(context).brightness == Brightness.dark
                    ? AppTheme.colorsOf(context).outline
                    : null),
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
            color: AppTheme.colorsOf(context).secondaryText,
          ),
        ),
      ],
    ],
  );
}
