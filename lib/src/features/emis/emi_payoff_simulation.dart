import 'dart:math' as math;

import '../../data/repositories.dart';

class EmiPlanMonth {
  const EmiPlanMonth(this.month, this.scheduledPaise, this.paidPaise);

  final DateTime month;
  final int scheduledPaise;
  final int paidPaise;
  int get extraPaise => math.max(0, paidPaise - scheduledPaise);
}

class EmiPayoffPlan {
  const EmiPayoffPlan({
    required this.originalEnd,
    required this.plannedEnd,
    required this.totalPaidPaise,
    required this.interestSavedPaise,
    required this.monthsSooner,
    required this.ordered,
    required this.targetId,
    required this.hasRates,
    required this.months,
  });

  final DateTime originalEnd;
  final DateTime plannedEnd;
  final int totalPaidPaise;
  final int interestSavedPaise;
  final int monthsSooner;
  final List<EmiDetail> ordered;
  final int? targetId;
  final bool hasRates;
  final List<EmiPlanMonth> months;
  int get averageExtraPaise => months.isEmpty
      ? 0
      : months.fold<int>(0, (sum, month) => sum + month.extraPaise) ~/
            months.length;
  EmiPlanMonth? get peakExtraMonth => months.isEmpty
      ? null
      : months.reduce((a, b) => a.extraPaise >= b.extraPaise ? a : b);
}

EmiPayoffPlan simulateEmiPayoff({
  required List<EmiDetail> items,
  required DateTime today,
  required int extraPerMonthPaise,
  required bool reuseFreedPayments,
}) {
  final month = DateTime(today.year, today.month);
  final active = items
      .where((item) => item.nextUnpaidInstallment != null)
      .toList();
  final hasRates = active.any((item) => (item.emi.interestRate ?? 0) > 0);
  final ordered = [...active]
    ..sort((a, b) {
      if (hasRates) {
        final byRate = (b.emi.interestRate ?? 0).compareTo(
          a.emi.interestRate ?? 0,
        );
        if (byRate != 0) return byRate;
      }
      return a.remainingBalancePaise.compareTo(b.remainingBalancePaise);
    });
  final dueById = <int, Map<DateTime, int>>{};
  final balances = <int, double>{};
  var originalEnd = month;
  var originalTotal = 0;
  for (final detail in ordered) {
    final dues = <DateTime, int>{};
    for (final installment in detail.installments.where(
      (item) => !item.isPaid,
    )) {
      final date = installment.dueDate;
      final dueMonth = DateTime(date.year, date.month);
      if (date.isAfter(originalEnd)) originalEnd = date;
      final key = dueMonth.isBefore(month) ? month : dueMonth;
      dues[key] =
          (dues[key] ?? 0) + detail.amountForInstallment(installment.number);
    }
    dueById[detail.emi.id] = dues;
    originalTotal += detail.remainingBalancePaise;
    final monthlyRate = (detail.emi.interestRate ?? 0) / 1200;
    if (monthlyRate == 0) {
      balances[detail.emi.id] = detail.remainingBalancePaise.toDouble();
    } else {
      balances[detail.emi.id] = dues.entries.fold<double>(0, (sum, entry) {
        final monthsAway = math.max(
          1,
          (entry.key.year - month.year) * 12 +
              entry.key.month -
              month.month +
              1,
        );
        return sum + entry.value / math.pow(1 + monthlyRate, monthsAway);
      });
    }
  }
  final firstDueTotal = dueById.values.fold<int>(
    0,
    (sum, dues) => sum + (dues[month] ?? 0),
  );
  final target = ordered.where((detail) {
    final thisMonth = dueById[detail.emi.id]?[month] ?? 0;
    return detail.remainingBalancePaise > thisMonth;
  }).firstOrNull;
  var totalPaid = 0.0;
  var plannedEnd = originalEnd;
  final months = <EmiPlanMonth>[];
  for (var step = 0; step < 600; step++) {
    final current = DateTime(month.year, month.month + step);
    final dueTotal = ordered.fold<int>(
      0,
      (sum, item) => sum + (dueById[item.emi.id]?[current] ?? 0),
    );
    var budget =
        (reuseFreedPayments ? math.max(firstDueTotal, dueTotal) : dueTotal) +
        extraPerMonthPaise;
    var paidThisMonth = 0.0;
    for (final detail in ordered) {
      final id = detail.emi.id;
      final rate = (detail.emi.interestRate ?? 0) / 1200;
      balances[id] = balances[id]! * (1 + rate);
    }
    for (final detail in ordered) {
      final id = detail.emi.id;
      final scheduled = dueById[id]?[current] ?? 0;
      final paid = math.min(
        balances[id]!,
        math.min(scheduled, budget).toDouble(),
      );
      balances[id] = math.max(0, balances[id]! - paid);
      budget -= paid.round();
      totalPaid += paid;
      paidThisMonth += paid;
    }
    if (budget > 0) {
      for (final detail in ordered) {
        final id = detail.emi.id;
        final paid = math.min(balances[id]!, budget.toDouble());
        balances[id] = math.max(0, balances[id]! - paid);
        budget -= paid.round();
        totalPaid += paid;
        paidThisMonth += paid;
        if (budget <= 0) break;
      }
    }
    months.add(EmiPlanMonth(current, dueTotal, paidThisMonth.round()));
    if (balances.values.every((value) => value <= 1)) {
      plannedEnd = current;
      break;
    }
  }
  final monthsSooner = math.max(
    0,
    (originalEnd.year - plannedEnd.year) * 12 +
        originalEnd.month -
        plannedEnd.month,
  );
  return EmiPayoffPlan(
    originalEnd: originalEnd,
    plannedEnd: plannedEnd,
    totalPaidPaise: totalPaid.round(),
    interestSavedPaise: math.max(0, originalTotal - totalPaid.round()),
    monthsSooner: monthsSooner,
    ordered: ordered,
    targetId: target?.emi.id,
    hasRates: hasRates,
    months: months,
  );
}
