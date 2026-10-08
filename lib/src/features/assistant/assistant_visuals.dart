import 'dart:math' as math;

enum AssistantVisualKind {
  bigNumber,
  donut,
  stackedBar,
  horizontalBars,
  progressRows,
  weeklyBars,
  timeline,
  scoreRing,
}

class AssistantVisualDatum {
  const AssistantVisualDatum({
    required this.label,
    required this.value,
    this.displayValue,
    this.detail,
    this.date,
    this.isOverdue = false,
  });

  final String label;
  final double value;
  final String? displayValue;
  final String? detail;
  final DateTime? date;
  final bool isOverdue;
}

class AssistantVisualPart {
  const AssistantVisualPart({
    required this.kind,
    required this.title,
    this.bigValue,
    this.subtitle,
    this.data = const [],
    this.score,
  });

  final AssistantVisualKind kind;
  final String title;
  final String? bigValue;
  final String? subtitle;
  final List<AssistantVisualDatum> data;
  final double? score;
}

class AssistantDatedAmount {
  const AssistantDatedAmount(
    this.date,
    this.amountPaise, {
    this.overdue = false,
  });
  final DateTime date;
  final int amountPaise;
  final bool overdue;
}

List<AssistantVisualDatum> buildWeeklyChartData(
  Iterable<AssistantDatedAmount> items,
  DateTime now,
) {
  final today = DateTime(now.year, now.month, now.day);
  final values = List<int>.filled(5, 0);
  final overdue = List<int>.filled(5, 0);
  for (final item in items) {
    final day = DateTime(item.date.year, item.date.month, item.date.day);
    final difference = day.difference(today).inDays;
    final index = difference < 0 ? 0 : math.min(4, difference ~/ 7);
    values[index] += item.amountPaise;
    if (item.overdue || difference < 0) overdue[index] += item.amountPaise;
  }
  return List.generate(5, (index) {
    final start = index == 0 ? 0 : index * 7;
    final end = index == 4 ? 30 : math.min(30, start + 6);
    return AssistantVisualDatum(
      label: index == 0 ? 'Now' : '$start-$end d',
      value: values[index].toDouble(),
      detail: overdue[index] == 0 ? null : 'overdue:${overdue[index]}',
      isOverdue: overdue[index] > 0,
    );
  });
}

class AssistantHealthInput {
  const AssistantHealthInput({
    required this.emiShare,
    required this.overdueCount,
    required this.undatedLentShare,
    required this.subscriptionShare,
  });

  final double emiShare;
  final int overdueCount;
  final double undatedLentShare;
  final double subscriptionShare;
}

class AssistantHealthScore {
  const AssistantHealthScore(this.score, this.factors);
  final int score;
  final List<AssistantVisualDatum> factors;
}

AssistantHealthScore calculateAssistantHealthScore(AssistantHealthInput input) {
  final emiPenalty = input.emiShare <= 0.4
      ? 0
      : ((input.emiShare - 0.4) / 0.6 * 30).clamp(0, 30).round();
  final overduePenalty = math.min(30, input.overdueCount * 10);
  final undatedPenalty = (input.undatedLentShare.clamp(0, 1) * 20).round();
  final subscriptionPenalty = input.subscriptionShare <= 0.2
      ? 0
      : ((input.subscriptionShare - 0.2) / 0.8 * 20).clamp(0, 20).round();
  final score =
      (100 - emiPenalty - overduePenalty - undatedPenalty - subscriptionPenalty)
          .clamp(0, 100);
  return AssistantHealthScore(score, [
    AssistantVisualDatum(
      label: 'EMI share',
      value: input.emiShare,
      displayValue: '${(input.emiShare * 100).round()}%',
      detail: input.emiShare > 0.4
          ? 'Above the 40% watch level'
          : 'Within the 40% watch level',
    ),
    AssistantVisualDatum(
      label: 'Overdue items',
      value: input.overdueCount.toDouble(),
      displayValue: '${input.overdueCount}',
      detail: input.overdueCount == 0 ? 'None overdue' : 'Needs attention',
    ),
    AssistantVisualDatum(
      label: 'Lent without a due date',
      value: input.undatedLentShare,
      displayValue: '${(input.undatedLentShare * 100).round()}%',
      detail: 'Share of outstanding money given',
    ),
    AssistantVisualDatum(
      label: 'Subscription share',
      value: input.subscriptionShare,
      displayValue: '${(input.subscriptionShare * 100).round()}%',
      detail: 'Share of monthly outflow',
    ),
  ]);
}
