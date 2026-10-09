import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;

import '../../core/app_theme.dart';
import '../../core/formatters.dart';
import 'assistant_visuals.dart';

class AssistantVisualWidget extends StatelessWidget {
  const AssistantVisualWidget({required this.part, super.key});
  final AssistantVisualPart part;

  @override
  Widget build(BuildContext context) {
    if (part.data.isEmpty &&
        part.kind != AssistantVisualKind.bigNumber &&
        part.kind != AssistantVisualKind.scoreRing) {
      return _VisualFrame(
        title: part.title,
        child: const Text('Nothing to chart yet.'),
      );
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, animation, _) =>
          _VisualFrame(title: part.title, child: _content(context, animation)),
    );
  }

  Widget _content(BuildContext context, double animation) {
    switch (part.kind) {
      case AssistantVisualKind.bigNumber:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hideMoneyInText(part.bigValue ?? '—'),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (part.subtitle != null) Text(hideMoneyInText(part.subtitle!)),
          ],
        );
      case AssistantVisualKind.donut:
      case AssistantVisualKind.scoreRing:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 86,
                  height: 86,
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _DonutPainter(
                        values: part.kind == AssistantVisualKind.scoreRing
                            ? [part.score ?? 0, 100 - (part.score ?? 0)]
                            : part.data.map((item) => item.value).toList(),
                        colors: part.kind == AssistantVisualKind.scoreRing
                            ? [
                                Theme.of(context).colorScheme.primary,
                                Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                              ]
                            : _palette(context),
                        track: AppTheme.colorsOf(context).outline,
                        animation: animation,
                      ),
                      child: Center(
                        child: Text(
                          part.kind == AssistantVisualKind.scoreRing
                              ? '${(part.score ?? 0).round()}'
                              : hideMoneyInText(part.bigValue ?? ''),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: _Legend(data: part.data)),
              ],
            ),
            if (part.subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                hideMoneyInText(part.subtitle!),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ],
        );
      case AssistantVisualKind.stackedBar:
        return Column(
          children: [
            SizedBox(
              height: 14,
              width: double.infinity,
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _StackedBarPainter(
                    values: part.data.map((item) => item.value).toList(),
                    colors: _palette(context),
                    track: AppTheme.colorsOf(context).outline,
                    animation: animation,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 9),
            _Legend(data: part.data),
          ],
        );
      case AssistantVisualKind.horizontalBars:
      case AssistantVisualKind.progressRows:
        final maximum = part.data.fold<double>(
          0,
          (value, item) => math.max(value, item.value),
        );
        return Column(
          children: [
            for (var index = 0; index < part.data.length; index++)
              _ProgressDatum(
                datum: part.data[index],
                progress: part.kind == AssistantVisualKind.progressRows
                    ? part.data[index].value * animation
                    : maximum == 0
                    ? 0
                    : part.data[index].value / maximum * animation,
                color: _palette(context)[index % _palette(context).length],
              ),
          ],
        );
      case AssistantVisualKind.weeklyBars:
        return SizedBox(
          height: 118,
          width: double.infinity,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _WeeklyBarsPainter(
                data: part.data,
                animation: animation,
                normal: Theme.of(context).colorScheme.primary,
                overdue: Theme.of(context).colorScheme.error,
                label: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      case AssistantVisualKind.timeline:
        return Column(
          children: [
            for (var index = 0; index < part.data.length; index++)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: part.data[index].isOverdue
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      if (index != part.data.length - 1)
                        Container(
                          width: 2,
                          height: 35,
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Row(
                        children: [
                          Expanded(child: Text(part.data[index].label)),
                          Text(
                            hideMoneyInText(
                              part.data[index].displayValue ?? '',
                            ),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
          ],
        );
    }
  }
}

class _VisualFrame extends StatelessWidget {
  const _VisualFrame({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 9),
      child,
    ],
  );
}

class _Legend extends StatelessWidget {
  const _Legend({required this.data});
  final List<AssistantVisualDatum> data;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var index = 0; index < data.length; index++)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _palette(context)[index % _palette(context).length],
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(data[index].label),
                    if (data[index].detail != null)
                      Text(
                        hideMoneyInText(data[index].detail!),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                  ],
                ),
              ),
              Text(hideMoneyInText(data[index].displayValue ?? '')),
            ],
          ),
        ),
    ],
  );
}

class _ProgressDatum extends StatelessWidget {
  const _ProgressDatum({
    required this.datum,
    required this.progress,
    required this.color,
  });
  final AssistantVisualDatum datum;
  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(datum.label)),
            Text(hideMoneyInText(datum.displayValue ?? '')),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: progress.clamp(0, 1),
          minHeight: 6,
          color: color,
          backgroundColor: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(3),
        ),
        if (datum.detail != null)
          Text(
            hideMoneyInText(datum.detail!),
            style: Theme.of(context).textTheme.labelSmall,
          ),
      ],
    ),
  );
}

List<Color> _palette(BuildContext context) => [
  Theme.of(context).colorScheme.primary,
  AppTheme.colorsOf(context).emi,
  AppTheme.colorsOf(context).subscriptions,
  AppTheme.colorsOf(context).pay,
  AppTheme.colorsOf(context).receive,
];

class _DonutPainter extends CustomPainter {
  const _DonutPainter({
    required this.values,
    required this.colors,
    required this.track,
    required this.animation,
  });
  final List<double> values;
  final List<Color> colors;
  final Color track;
  final double animation;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(
      0,
      (sum, item) => sum + math.max(0, item),
    );
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.butt;
    paint.color = track;
    canvas.drawArc(rect.deflate(7), 0, math.pi * 2, false, paint);
    if (total <= 0) return;
    var start = -math.pi / 2;
    for (var index = 0; index < values.length; index++) {
      final sweep = math.pi * 2 * values[index] / total * animation;
      paint.color = colors[index % colors.length];
      canvas.drawArc(rect.deflate(7), start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.animation != animation ||
      oldDelegate.track != track ||
      !listEquals(oldDelegate.values, values) ||
      !listEquals(oldDelegate.colors, colors);
}

class _StackedBarPainter extends CustomPainter {
  const _StackedBarPainter({
    required this.values,
    required this.colors,
    required this.track,
    required this.animation,
  });
  final List<double> values;
  final List<Color> colors;
  final Color track;
  final double animation;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(
      0,
      (sum, item) => sum + math.max(0, item),
    );
    final background = Paint()..color = track;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(7)),
      background,
    );
    if (total <= 0) return;
    var left = 0.0;
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(7)),
    );
    for (var index = 0; index < values.length; index++) {
      final width = size.width * values[index] / total * animation;
      canvas.drawRect(
        Rect.fromLTWH(left, 0, width, size.height),
        Paint()..color = colors[index % colors.length],
      );
      left += width;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _StackedBarPainter oldDelegate) =>
      oldDelegate.animation != animation ||
      oldDelegate.track != track ||
      !listEquals(oldDelegate.values, values) ||
      !listEquals(oldDelegate.colors, colors);
}

class _WeeklyBarsPainter extends CustomPainter {
  const _WeeklyBarsPainter({
    required this.data,
    required this.animation,
    required this.normal,
    required this.overdue,
    required this.label,
  });
  final List<AssistantVisualDatum> data;
  final double animation;
  final Color normal;
  final Color overdue;
  final Color label;

  @override
  void paint(Canvas canvas, Size size) {
    final maximum = data.fold<double>(
      0,
      (value, item) => math.max(value, item.value),
    );
    final slot = size.width / data.length;
    final textStyle = TextStyle(color: label, fontSize: 10);
    for (var index = 0; index < data.length; index++) {
      final ratio = maximum == 0 ? 0.0 : data[index].value / maximum;
      final height = ratio * 82 * animation;
      final rect = Rect.fromLTWH(
        index * slot + slot * 0.22,
        88 - height,
        slot * 0.56,
        height,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        Paint()..color = data[index].isOverdue ? overdue : normal,
      );
      final painter = TextPainter(
        text: TextSpan(text: data[index].label, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: slot);
      painter.paint(
        canvas,
        Offset(index * slot + (slot - painter.width) / 2, 98),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WeeklyBarsPainter oldDelegate) =>
      oldDelegate.animation != animation ||
      oldDelegate.normal != normal ||
      oldDelegate.overdue != overdue ||
      oldDelegate.label != label ||
      !_sameData(oldDelegate.data, data);

  bool _sameData(List<AssistantVisualDatum> a, List<AssistantVisualDatum> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index].label != b[index].label ||
          a[index].value != b[index].value ||
          a[index].isOverdue != b[index].isOverdue) {
        return false;
      }
    }
    return true;
  }
}
