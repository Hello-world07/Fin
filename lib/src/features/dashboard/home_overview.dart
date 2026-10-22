import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/database.dart';
import '../../data/repositories.dart';
import '../../domain/enums.dart';
import '../../domain/subscription_schedule.dart';

final homeOverviewProvider = Provider<HomeOverview?>((ref) {
  final emis = ref.watch(allEmiDetailsProvider).valueOrNull;
  final money = ref.watch(moneyRecordsProvider).valueOrNull;
  final subscriptions = ref.watch(subscriptionsProvider).valueOrNull;
  if (emis == null || money == null || subscriptions == null) return null;
  return HomeOverview.build(emis, money, subscriptions, DateTime.now());
});

class HomeDue {
  const HomeDue(
    this.type,
    this.id,
    this.name,
    this.amount,
    this.date, {
    this.incoming = false,
  });
  final String type;
  final int id;
  final String name;
  final int amount;
  final DateTime date;
  final bool incoming;
}

class HomeWeek {
  const HomeWeek(this.start, this.items);
  final DateTime start;
  final List<HomeDue> items;
  int get incoming =>
      items.where((e) => e.incoming).fold(0, (n, e) => n + e.amount);
  int get outgoing =>
      items.where((e) => !e.incoming).fold(0, (n, e) => n + e.amount);
}

class HomeMonth {
  const HomeMonth(this.start, this.items);
  final DateTime start;
  final List<HomeDue> items;
  int get incoming => items
      .where((item) => item.incoming)
      .fold(0, (sum, item) => sum + item.amount);
  int get outgoing => items
      .where((item) => !item.incoming)
      .fold(0, (sum, item) => sum + item.amount);
}

class HomeOverview {
  const HomeOverview({
    required this.today,
    required this.emis,
    required this.friendEmis,
    required this.money,
    required this.subscriptions,
    required this.dues,
    required this.weeks,
    required this.months,
    required this.toCollect,
    required this.toPay,
    required this.emiRemaining,
    required this.friendRemaining,
    required this.friendPaid,
    required this.friendTotal,
    required this.debtFreeDate,
  });

  final DateTime today;
  final List<EmiDetail> emis;
  final List<EmiDetail> friendEmis;
  final List<MoneyRecordDetail> money;
  final List<Subscription> subscriptions;
  final List<HomeDue> dues;
  final List<HomeWeek> weeks;
  final List<HomeMonth> months;
  final int toCollect, toPay, emiRemaining, friendRemaining;
  final int friendPaid, friendTotal;
  final DateTime? debtFreeDate;

  int get totalDebt => toPay + emiRemaining;
  int get personalDueThisMonth =>
      scheduledPersonalEmiAmountInMonth(emis, today);
  int get personalOverdue => overdueDues
      .where((item) => item.type == 'emi')
      .fold(0, (sum, item) => sum + item.amount);
  int get friendOverdue => overdueDues
      .where((item) => item.type == 'friendEmi')
      .fold(0, (sum, item) => sum + item.amount);
  int get windowIncoming => weeks.fold(0, (sum, week) => sum + week.incoming);
  int get windowOutgoing => weeks.fold(0, (sum, week) => sum + week.outgoing);
  List<HomeDue> get windowDues => [for (final week in weeks) ...week.items];
  List<HomeDue> get overdueDues =>
      dues.where((due) => due.date.isBefore(today)).toList();
  int get overdueAmount => overdueDues.fold(0, (sum, due) => sum + due.amount);
  HomeDue? get heaviestDueDay {
    final amounts = <DateTime, int>{};
    final windowEnd = today.add(const Duration(days: 35));
    for (final due in dues.where(
      (due) =>
          !due.incoming &&
          !due.date.isBefore(today) &&
          due.date.isBefore(windowEnd),
    )) {
      amounts.update(
        due.date,
        (value) => value + due.amount,
        ifAbsent: () => due.amount,
      );
    }
    if (amounts.isEmpty) return null;
    final date = amounts.keys.reduce((a, b) {
      final comparison = amounts[a]!.compareTo(amounts[b]!);
      return comparison > 0 || (comparison == 0 && a.isBefore(b)) ? a : b;
    });
    return dues.firstWhere((due) => !due.incoming && due.date == date);
  }

  int get heaviestDueDayAmount => heaviestDueDay == null
      ? 0
      : dues
            .where((due) => !due.incoming && due.date == heaviestDueDay!.date)
            .fold(0, (sum, due) => sum + due.amount);
  List<HomeDue> get nextFiveWeeks => dues
      .where(
        (e) =>
            !e.incoming &&
            !e.date.isBefore(today) &&
            e.date.isBefore(today.add(const Duration(days: 35))),
      )
      .toList();
  List<HomeDue> get next30Outgoing => dues
      .where(
        (item) =>
            !item.incoming &&
            !item.date.isBefore(today) &&
            item.date.isBefore(today.add(const Duration(days: 30))),
      )
      .toList();
  int get next30OutgoingTotal =>
      next30Outgoing.fold<int>(0, (sum, item) => sum + item.amount);
  HomeDue? get nextToPay => windowDues.where((e) => !e.incoming).firstOrNull;

  static HomeOverview build(
    List<EmiDetail> allEmis,
    List<MoneyRecordDetail> money,
    List<Subscription> subscriptions,
    DateTime now,
  ) {
    final today = DateTime(now.year, now.month, now.day);
    final end = today.add(const Duration(days: 35));
    final monthEnd = DateTime(today.year, today.month + 6, 1);
    final emis = allEmis
        .where(
          (e) =>
              e.category == EmiCategory.personal &&
              e.nextUnpaidInstallment != null,
        )
        .toList();
    final friendEmis = allEmis
        .where(
          (e) =>
              e.category == EmiCategory.givenToFriends &&
              e.nextUnpaidInstallment != null,
        )
        .toList();
    final dues = <HomeDue>[];
    var collect = 0, pay = 0, remaining = 0;
    DateTime? last;
    for (final detail in money) {
      final amount = detail.summary.remainingAmountPaise;
      if (amount <= 0) continue;
      final incoming = detail.record.direction == MoneyDirection.given;
      if (incoming) {
        collect += amount;
      } else {
        pay += amount;
      }
      final due = detail.record.dueDate;
      if (due != null) {
        final day = DateTime(due.year, due.month, due.day);
        dues.add(
          HomeDue(
            'money',
            detail.record.id,
            detail.record.personName,
            amount,
            day,
            incoming: incoming,
          ),
        );
      }
    }
    for (final detail in emis) {
      remaining += detail.remainingBalancePaise;
      if (detail.emi.status == EmiStatus.paused) continue;
      for (final installment in detail.installments) {
        if (installment.isPaid) continue;
        final amount = detail.unpaidAmountForInstallment(installment.number);
        if (amount <= 0) continue;
        final day = DateTime(
          installment.dueDate.year,
          installment.dueDate.month,
          installment.dueDate.day,
        );
        if (last == null || day.isAfter(last)) last = day;
        dues.add(HomeDue('emi', detail.emi.id, detail.emi.name, amount, day));
      }
    }
    final friendRemaining = friendEmis.fold<int>(
      0,
      (sum, detail) => sum + detail.remainingBalancePaise,
    );
    final allFriendEmis = allEmis.where(
      (item) => item.category == EmiCategory.givenToFriends,
    );
    final friendPaid = allFriendEmis.fold<int>(
      0,
      (sum, detail) => sum + detail.paidPaise,
    );
    final friendTotal = allFriendEmis.fold<int>(
      0,
      (sum, detail) => sum + detail.totalRepaymentPaise,
    );
    for (final detail in friendEmis) {
      if (detail.emi.status == EmiStatus.paused) continue;
      for (final installment in detail.installments) {
        if (installment.isPaid) continue;
        final amount = detail.unpaidAmountForInstallment(installment.number);
        if (amount <= 0) continue;
        final day = DateTime(
          installment.dueDate.year,
          installment.dueDate.month,
          installment.dueDate.day,
        );
        dues.add(
          HomeDue(
            'friendEmi',
            detail.emi.id,
            detail.emi.name,
            amount,
            day,
            incoming: true,
          ),
        );
      }
    }
    for (final sub in subscriptions) {
      if (sub.status != SubscriptionStatus.active) continue;
      final occurrences = subscriptionOccurrences(
        sub.nextBillingDate,
        sub.frequency,
        today,
        monthEnd.subtract(const Duration(days: 1)),
      );
      if (occurrences.isEmpty) {
        occurrences.add(
          nextSubscriptionBillingDate(
            sub.nextBillingDate,
            sub.frequency,
            today,
          ),
        );
      }
      for (final date in occurrences) {
        dues.add(
          HomeDue('subscription', sub.id, sub.name, sub.amountPaise, date),
        );
      }
    }
    dues.sort((a, b) => a.date.compareTo(b.date));
    final weeks = List.generate(5, (index) {
      final start = today.add(Duration(days: 7 * index));
      final finish = start.add(const Duration(days: 7));
      return HomeWeek(
        start,
        dues
            .where((e) => !e.date.isBefore(start) && e.date.isBefore(finish))
            .toList(),
      );
    });
    final months = List.generate(6, (index) {
      final start = DateTime(today.year, today.month + index, 1);
      final finish = DateTime(today.year, today.month + index + 1, 1);
      return HomeMonth(
        start,
        dues
            .where(
              (item) =>
                  !item.date.isBefore(today) &&
                  !item.date.isBefore(start) &&
                  item.date.isBefore(finish),
            )
            .toList(),
      );
    });
    assert(
      collect ==
          money
              .where(
                (detail) => detail.record.direction == MoneyDirection.given,
              )
              .fold<int>(
                0,
                (sum, detail) => sum + detail.summary.remainingAmountPaise,
              ),
    );
    assert(
      pay ==
          money
              .where(
                (detail) => detail.record.direction == MoneyDirection.borrowed,
              )
              .fold<int>(
                0,
                (sum, detail) => sum + detail.summary.remainingAmountPaise,
              ),
    );
    assert(
      remaining ==
          emis.fold<int>(
            0,
            (sum, detail) => sum + detail.remainingBalancePaise,
          ),
    );
    assert(
      pay + remaining ==
          money
                  .where(
                    (detail) =>
                        detail.record.direction == MoneyDirection.borrowed,
                  )
                  .fold<int>(
                    0,
                    (sum, detail) => sum + detail.summary.remainingAmountPaise,
                  ) +
              emis.fold<int>(
                0,
                (sum, detail) => sum + detail.remainingBalancePaise,
              ),
    );
    assert(
      weeks.fold<int>(0, (sum, week) => sum + week.incoming) ==
          dues
              .where(
                (due) =>
                    due.incoming &&
                    !due.date.isBefore(today) &&
                    due.date.isBefore(end),
              )
              .fold<int>(0, (sum, due) => sum + due.amount),
    );
    assert(
      weeks.fold<int>(0, (sum, week) => sum + week.outgoing) ==
          dues
              .where(
                (due) =>
                    !due.incoming &&
                    !due.date.isBefore(today) &&
                    due.date.isBefore(end),
              )
              .fold<int>(0, (sum, due) => sum + due.amount),
    );
    return HomeOverview(
      today: today,
      emis: emis,
      friendEmis: friendEmis,
      money: money,
      subscriptions: subscriptions,
      dues: dues,
      weeks: weeks,
      months: months,
      toCollect: collect,
      toPay: pay,
      emiRemaining: remaining,
      friendRemaining: friendRemaining,
      friendPaid: friendPaid,
      friendTotal: friendTotal,
      debtFreeDate: last,
    );
  }
}
