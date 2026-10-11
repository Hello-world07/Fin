import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/database.dart';
import '../../data/repositories.dart';
import '../../domain/enums.dart';
import '../../domain/subscription_schedule.dart';

final homeOverviewProvider = Provider<HomeOverview?>((ref) {
  final emis = ref.watch(emiDetailsProvider).valueOrNull;
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

class HomeOverview {
  const HomeOverview({
    required this.today,
    required this.emis,
    required this.money,
    required this.subscriptions,
    required this.dues,
    required this.weeks,
    required this.toCollect,
    required this.toPay,
    required this.emiRemaining,
    required this.debtFreeDate,
  });

  final DateTime today;
  final List<EmiDetail> emis;
  final List<MoneyRecordDetail> money;
  final List<Subscription> subscriptions;
  final List<HomeDue> dues;
  final List<HomeWeek> weeks;
  final int toCollect, toPay, emiRemaining;
  final DateTime? debtFreeDate;

  int get balance => toCollect - toPay;
  int get totalDebt => toPay + emiRemaining;
  List<HomeDue> get next30 => dues
      .where(
        (e) =>
            !e.incoming &&
            !e.date.isBefore(today) &&
            e.date.isBefore(today.add(const Duration(days: 30))),
      )
      .toList();
  HomeDue? get nextToPay => dues.where((e) => !e.incoming).firstOrNull;

  static HomeOverview build(
    List<EmiDetail> allEmis,
    List<MoneyRecordDetail> money,
    List<Subscription> subscriptions,
    DateTime now,
  ) {
    final today = DateTime(now.year, now.month, now.day);
    final end = today.add(const Duration(days: 35));
    final emis = allEmis.where((e) => e.nextUnpaidInstallment != null).toList();
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
      for (final installment in detail.installments) {
        if (installment.isPaid) continue;
        final day = DateTime(
          installment.dueDate.year,
          installment.dueDate.month,
          installment.dueDate.day,
        );
        if (last == null || day.isAfter(last)) last = day;
        dues.add(
          HomeDue(
            'emi',
            detail.emi.id,
            detail.emi.name,
            detail.amountForInstallment(installment.number),
            day,
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
        end.subtract(const Duration(days: 1)),
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
    return HomeOverview(
      today: today,
      emis: emis,
      money: money,
      subscriptions: subscriptions,
      dues: dues,
      weeks: weeks,
      toCollect: collect,
      toPay: pay,
      emiRemaining: remaining,
      debtFreeDate: last,
    );
  }
}
