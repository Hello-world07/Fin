import 'dart:async';
import 'dart:math' as math;

import 'package:intl/intl.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../core/privacy_reveal.dart';
import 'emi_visual_data.dart';

class AmountText extends StatefulWidget {
  const AmountText(
    this.paise, {
    super.key,
    this.style,
    this.maxLines,
    this.compact = false,
  });

  final int paise;
  final TextStyle? style;
  final int? maxLines;
  final bool compact;

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
    child: ValueListenableBuilder<AmountFormatter>(
      valueListenable: activeAmountFormatter,
      builder: (context, _, _) => Text(
        _revealed
            ? (widget.compact
                  ? formatCompactMoneyUnmasked(widget.paise)
                  : formatMoneyUnmasked(widget.paise))
            : (widget.compact && !privacyAmountsHidden
                  ? formatCompactMoneyUnmasked(widget.paise)
                  : formatMoney(widget.paise)),
        style: (widget.style ?? Theme.of(context).textTheme.bodyMedium)
            ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
        maxLines: widget.maxLines,
        overflow: widget.maxLines == null ? null : TextOverflow.ellipsis,
      ),
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
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.square(
            dimension: size,
            child: TweenAnimationBuilder<double>(
              tween: Tween(
                begin: progress > 0 ? 0.02 : 0,
                end: progress.clamp(0, 1),
              ),
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 400),
              builder: (context, value, _) => CircularProgressIndicator(
                value: value,
                strokeWidth: strokeWidth,
                strokeCap: StrokeCap.round,
                backgroundColor:
                    backgroundColor ?? AppTheme.colorsOf(context).outline,
              ),
            ),
          ),
          ?child,
        ],
      ),
    );
  }
}

class FinanceSegmentedBar extends StatelessWidget {
  const FinanceSegmentedBar({
    super.key,
    required this.values,
    required this.colors,
    this.height = 14,
  });

  final List<int> values;
  final List<Color> colors;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 120,
    height: height,
    child: RepaintBoundary(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.02, end: 1),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 400),
        builder: (context, grow, _) => CustomPaint(
          painter: _FinanceSegmentedBarPainter(
            values: values,
            colors: colors,
            track: AppTheme.colorsOf(context).outline,
            grow: grow,
          ),
        ),
      ),
    ),
  );
}

class _FinanceSegmentedBarPainter extends CustomPainter {
  const _FinanceSegmentedBarPainter({
    required this.values,
    required this.colors,
    required this.track,
    required this.grow,
  });

  final List<int> values;
  final List<Color> colors;
  final Color track;
  final double grow;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final shape = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );
    canvas.drawRRect(shape, Paint()..color = track);
    final total = values.fold<int>(
      0,
      (sum, value) => sum + value.clamp(0, 1 << 60),
    );
    if (total <= 0) return;
    canvas.save();
    canvas.clipRRect(shape);
    var x = 0.0;
    for (
      var index = 0;
      index < values.length && index < colors.length;
      index++
    ) {
      final width = size.width * values[index].clamp(0, total) / total * grow;
      canvas.drawRect(
        Rect.fromLTWH(x, 0, width, size.height),
        Paint()..color = colors[index],
      );
      x += width;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FinanceSegmentedBarPainter old) =>
      grow != old.grow ||
      track != old.track ||
      !listEquals(values, old.values) ||
      !listEquals(colors, old.colors);
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
    return SizedBox(
      width: 120,
      child: Row(
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
      ),
    );
  }
}

class RingSegment {
  const RingSegment({
    required this.label,
    required this.paid,
    required this.total,
    required this.color,
  });
  final String label;
  final int paid;
  final int total;
  final Color color;
}

class SegmentedRing extends StatefulWidget {
  const SegmentedRing({
    super.key,
    required this.segments,
    required this.center,
    this.size = 112,
    this.trackColor,
    this.proportional = false,
  });
  final List<RingSegment> segments;
  final Widget center;
  final double size;
  final Color? trackColor;
  final bool proportional;

  @override
  State<SegmentedRing> createState() => _SegmentedRingState();
}

class _SegmentedRingState extends State<SegmentedRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _grow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  )..forward();
  String? _selected;

  @override
  void dispose() {
    _grow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final segments = widget.segments.isEmpty
        ? [
            RingSegment(
              label: 'No items',
              paid: 0,
              total: 1,
              color: Theme.of(context).colorScheme.primary,
            ),
          ]
        : widget.segments;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTapDown: (details) {
            final center = Offset(widget.size / 2, widget.size / 2);
            final delta = details.localPosition - center;
            final angle =
                (math.atan2(delta.dy, delta.dx) + math.pi / 2 + math.pi * 2) %
                (math.pi * 2);
            final weights = [
              for (final part in segments)
                widget.proportional ? part.total.clamp(0, 1 << 60) : 1,
            ];
            final totalWeight = weights.fold<int>(
              0,
              (sum, weight) => sum + weight,
            );
            var position = 0.0;
            var index = segments.length - 1;
            for (var i = 0; i < segments.length; i++) {
              position +=
                  math.pi *
                  2 *
                  (totalWeight == 0
                      ? 1 / segments.length
                      : weights[i] / totalWeight);
              if (angle < position) {
                index = i;
                break;
              }
            }
            setState(() => _selected = segments[index].label);
          },
          child: Tooltip(
            message: _selected ?? 'Tap a segment for its name and progress',
            child: SizedBox.square(
              dimension: widget.size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: _grow,
                      builder: (context, _) => CustomPaint(
                        size: Size.square(widget.size),
                        painter: _SegmentedRingPainter(
                          segments,
                          widget.trackColor ??
                              AppTheme.colorsOf(context).outline,
                          MediaQuery.disableAnimationsOf(context)
                              ? 1
                              : _grow.value,
                          widget.proportional,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(22),
                    child: Center(child: widget.center),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_selected != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _selected!,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
      ],
    );
  }
}

class _SegmentedRingPainter extends CustomPainter {
  const _SegmentedRingPainter(
    this.segments,
    this.track,
    this.grow,
    this.proportional,
  );
  final List<RingSegment> segments;
  final Color track;
  final double grow;
  final bool proportional;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final weights = [
      for (final part in segments)
        proportional ? part.total.clamp(0, 1 << 60) : 1,
    ];
    final totalWeight = weights.fold<int>(0, (sum, weight) => sum + weight);
    var cursor = -math.pi / 2;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < segments.length; i++) {
      final arc =
          math.pi *
          2 *
          (totalWeight == 0 ? 1 / segments.length : weights[i] / totalWeight);
      final gap = math.min(0.08, arc * 0.12);
      final start = cursor + gap / 2;
      final sweep = arc - gap;
      cursor += arc;
      canvas.drawArc(rect.deflate(8), start, sweep, false, base..color = track);
      final part = segments[i];
      final fraction = part.total <= 0
          ? 0.0
          : (part.paid / part.total).clamp(0.0, 1.0);
      if (fraction > 0) {
        canvas.drawArc(
          rect.deflate(8),
          start,
          sweep * fraction * grow,
          false,
          base..color = part.color,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SegmentedRingPainter old) =>
      old.track != track ||
      old.grow != grow ||
      old.proportional != proportional ||
      old.segments.length != segments.length ||
      Iterable<int>.generate(segments.length).any(
        (i) =>
            old.segments[i].label != segments[i].label ||
            old.segments[i].paid != segments[i].paid ||
            old.segments[i].total != segments[i].total ||
            old.segments[i].color != segments[i].color,
      );
}

class ReliefSteps extends StatelessWidget {
  const ReliefSteps({
    super.key,
    required this.data,
    this.foregroundColor,
    this.homeStyle = false,
  });
  final EmiVisualData data;
  final Color? foregroundColor;
  final bool homeStyle;

  @override
  Widget build(BuildContext context) {
    if (data.reliefs.isEmpty) return const SizedBox.shrink();
    final grouped = <DateTime, int>{};
    final counts = <DateTime, int>{};
    for (final relief in data.reliefs) {
      grouped.update(
        relief.month,
        (amount) => amount + relief.amountPaise,
        ifAbsent: () => relief.amountPaise,
      );
      counts.update(relief.month, (count) => count + 1, ifAbsent: () => 1);
    }
    final steps = grouped.entries.take(3).toList();
    final after = (data.currentLoadPaise - steps.first.value).clamp(0, 1 << 60);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final step in steps)
              Tooltip(
                message:
                    'Monthly EMI load falls by ${formatMoney(step.value)} after ${DateFormat('MMM yyyy').format(step.key)}',
                child: ActionChip(
                  side: BorderSide.none,
                  backgroundColor: homeStyle
                      ? AppTheme.colorsOf(context).emi.withValues(alpha: 0.10)
                      : null,
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Monthly EMI load falls by ${formatMoney(step.value)} after ${DateFormat('MMM yyyy').format(step.key)}',
                      ),
                    ),
                  ),
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${DateFormat('MMM').format(step.key)}: ',
                        style: homeStyle
                            ? TextStyle(color: AppTheme.colorsOf(context).emi)
                            : null,
                      ),
                      AmountText(
                        step.value,
                        style: homeStyle
                            ? TextStyle(
                                color: AppTheme.colorsOf(context).emi,
                                fontWeight: FontWeight.w700,
                              )
                            : null,
                      ),
                      if (homeStyle)
                        Text(
                          counts[step.key] == 1 ? ' EMI ends' : ' EMIs end',
                          style: TextStyle(
                            color: AppTheme.colorsOf(context).emi,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 5),
        Wrap(
          spacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Monthly load:', style: TextStyle(color: foregroundColor)),
            AmountText(
              data.currentLoadPaise,
              style: TextStyle(color: foregroundColor),
            ),
            Text('→', style: TextStyle(color: foregroundColor)),
            AmountText(after, style: TextStyle(color: foregroundColor)),
          ],
        ),
      ],
    );
  }
}

class MonthGrid extends StatelessWidget {
  const MonthGrid({super.key, required this.months});
  final List<EmiMonthLoad> months;

  @override
  Widget build(BuildContext context) {
    final max = months.fold<int>(
      0,
      (value, month) => math.max(value, month.amountPaise),
    );
    final base = AppTheme.colorsOf(context).emi;
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) => Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final month in months.take(12))
              SizedBox(
                width: (constraints.maxWidth - 24) / 4,
                child: Tooltip(
                  message:
                      '${DateFormat('MMM yyyy').format(month.month)}: ${month.parts.isEmpty ? 'No EMI due' : month.parts.map((part) => '${part.$1} ${formatMoney(part.$2)}').join(' + ')}',
                  child: InkWell(
                    onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '${DateFormat('MMM').format(month.month)}: ${month.parts.isEmpty ? 'No EMI due' : month.parts.map((part) => '${part.$1} ${formatMoney(part.$2)}').join(' + ')}',
                        ),
                      ),
                    ),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(minHeight: 74),
                      decoration: BoxDecoration(
                        color: base.withValues(
                          alpha:
                              0.06 +
                              (max == 0 ? 0 : month.amountPaise / max * 0.18),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat('MMM').format(month.month),
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: AmountText(
                              month.amountPaise,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          if (month.dropped)
                            Icon(
                              Icons.south,
                              size: 14,
                              color: Theme.of(context).colorScheme.primary,
                              semanticLabel: 'Monthly load drops',
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class CollectItem {
  const CollectItem({
    required this.name,
    required this.amountPaise,
    this.dueDate,
    this.onTap,
  });
  final String name;
  final int amountPaise;
  final DateTime? dueDate;
  final VoidCallback? onTap;
}

class CollectChips extends StatelessWidget {
  const CollectChips({super.key, required this.items});
  final List<CollectItem> items;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 64,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: math.min(items.length, 4),
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (context, index) {
        final item = items[index];
        final days = item.dueDate == null
            ? null
            : DateUtils.dateOnly(
                item.dueDate!,
              ).difference(DateUtils.dateOnly(DateTime.now())).inDays;
        return Tooltip(
          message:
              '${item.name}: ${formatMoney(item.amountPaise)}${days == null ? ', no due date' : ', due ${days < 0 ? '${-days} days overdue' : 'in $days days'}'}',
          child: ActionChip(
            onPressed: item.onTap ?? () {},
            avatar: CircleAvatar(
              child: Text(item.name.isEmpty ? '?' : item.name[0].toUpperCase()),
            ),
            label: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AmountText(item.amountPaise),
                    Text(
                      days == null
                          ? ' · No due'
                          : ' · ${days < 0 ? '${-days}d overdue' : '${days}d'}',
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
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
