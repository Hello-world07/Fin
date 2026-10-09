import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../core/formatters.dart';
import '../core/notifications.dart';
import '../domain/reminder_schedule.dart';
import '../domain/due_status.dart';
import '../domain/emi_math.dart';
import '../domain/emi_payment_rules.dart' show dateOnly;
import '../domain/enums.dart';
import '../domain/money_math.dart';
import '../domain/subscription_schedule.dart';
import 'database.dart';

const dashboardPaymentHorizon = Duration(days: 7);
const dashboardSubscriptionHorizon = Duration(days: 14);

class DashboardSummary {
  const DashboardSummary({
    required this.needToPayPaise,
    required this.comingToMePaise,
    required this.activeEmis,
    required this.upcomingPayments,
    required this.upcomingSubscriptions,
    required this.monthlyOutflowPaise,
    required this.monthlyEmisPaise,
    required this.monthlySubscriptionsPaise,
    required this.monthlyMoneyToPayPaise,
  });

  final int needToPayPaise;
  final int comingToMePaise;
  final int activeEmis;
  final int upcomingPayments;
  final int upcomingSubscriptions;
  final int monthlyOutflowPaise;
  final int monthlyEmisPaise;
  final int monthlySubscriptionsPaise;
  final int monthlyMoneyToPayPaise;

  @override
  bool operator ==(Object other) =>
      other is DashboardSummary &&
      other.needToPayPaise == needToPayPaise &&
      other.comingToMePaise == comingToMePaise &&
      other.activeEmis == activeEmis &&
      other.upcomingPayments == upcomingPayments &&
      other.upcomingSubscriptions == upcomingSubscriptions &&
      other.monthlyOutflowPaise == monthlyOutflowPaise &&
      other.monthlyEmisPaise == monthlyEmisPaise &&
      other.monthlySubscriptionsPaise == monthlySubscriptionsPaise &&
      other.monthlyMoneyToPayPaise == monthlyMoneyToPayPaise;

  @override
  int get hashCode => Object.hash(
    needToPayPaise,
    comingToMePaise,
    activeEmis,
    upcomingPayments,
    upcomingSubscriptions,
    monthlyOutflowPaise,
    monthlyEmisPaise,
    monthlySubscriptionsPaise,
    monthlyMoneyToPayPaise,
  );
}

class MoneyRecordDetail {
  const MoneyRecordDetail({
    required this.record,
    required this.repayments,
    required this.summary,
  });

  final MoneyRecord record;
  final List<MoneyRepayment> repayments;
  final RepaymentSummary summary;
}

class EmiDetail {
  const EmiDetail({required this.emi, required this.payments});

  final Emi emi;
  final List<EmiPayment> payments;

  EmiSchedule get schedule => calculateEmiSchedule(
    principalPaise: emi.principalPaise,
    installmentPaise: emi.emiAmountPaise,
    tenure: emi.tenureMonths,
    annualInterestRate: emi.interestRate,
    paidInstallmentAmounts: [
      ...List<int>.generate(
        emi.initialPaidInstallments,
        (index) => _scheduledAmount(index + 1),
      ),
      ...payments.map((item) => item.amountPaise),
    ],
  );

  List<EmiInstallment> get installments => buildEmiInstallments(
    startDate: emi.startDate,
    tenure: emi.tenureMonths,
    frequency: emi.frequency,
    alreadyPaidCount: emi.initialPaidInstallments,
    paidInstallmentNumbers:
        payments.map((payment) => payment.installmentNumber).toSet()..addAll(
          Iterable<int>.generate(
            emi.initialPaidInstallments,
            (index) => index + 1,
          ),
        ),
  );

  EmiInstallment? get nextUnpaidInstallment {
    for (final installment in installments) {
      if (!installment.isPaid) return installment;
    }
    return null;
  }

  int get paidInstallments => emi.initialPaidInstallments + payments.length;
  int get remainingInstallments =>
      (emi.tenureMonths - paidInstallments).clamp(0, emi.tenureMonths);
  int get paidPaise => schedule.paidPaise;
  int get remainingBalancePaise => schedule.remainingBalancePaise;
  int get scheduledInstallmentPaise => emi.emiAmountPaise;
  int _scheduledAmount(int number) {
    if (number == emi.tenureMonths) {
      final total = emi.interestRate == null || emi.interestRate == 0
          ? emi.principalPaise
          : emi.emiAmountPaise * emi.tenureMonths;
      return (total - emi.emiAmountPaise * (emi.tenureMonths - 1)).clamp(
        0,
        total,
      );
    }
    return emi.emiAmountPaise;
  }

  int amountForInstallment(int number) {
    if (number < 1 || number > emi.tenureMonths) return 0;
    return _scheduledAmount(number);
  }

  int get totalRepaymentPaise => schedule.totalRepaymentPaise;
  double get progress => schedule.progress;
}

class ReminderItem {
  const ReminderItem({
    required this.title,
    required this.subtitle,
    required this.dueAt,
    required this.status,
    required this.entityType,
    required this.entityId,
    required this.amountPaise,
    this.installmentNumber,
    this.isNextInstallment = false,
  });

  final String title;
  final String subtitle;
  final DateTime dueAt;
  final ReminderStatus status;
  final String entityType;
  final int entityId;
  final int amountPaise;
  final int? installmentNumber;
  final bool isNextInstallment;
}

class SubscriptionExtra {
  const SubscriptionExtra({
    this.trialEndsOn,
    this.pauseUntil,
    this.cancelAt,
    this.cancellationReason,
    this.essential = false,
    this.reviewed = false,
    this.priceHistory = const [],
  });

  final DateTime? trialEndsOn;
  final DateTime? pauseUntil;
  final DateTime? cancelAt;
  final String? cancellationReason;
  final bool essential;
  final bool reviewed;
  final List<SubscriptionPriceChange> priceHistory;

  SubscriptionExtra copyWith({
    DateTime? trialEndsOn,
    DateTime? pauseUntil,
    DateTime? cancelAt,
    String? cancellationReason,
    bool? essential,
    bool? reviewed,
    List<SubscriptionPriceChange>? priceHistory,
    bool clearTrialEndsOn = false,
    bool clearPauseUntil = false,
    bool clearCancelAt = false,
  }) => SubscriptionExtra(
    trialEndsOn: clearTrialEndsOn ? null : trialEndsOn ?? this.trialEndsOn,
    pauseUntil: clearPauseUntil ? null : pauseUntil ?? this.pauseUntil,
    cancelAt: clearCancelAt ? null : cancelAt ?? this.cancelAt,
    cancellationReason: cancellationReason ?? this.cancellationReason,
    essential: essential ?? this.essential,
    reviewed: reviewed ?? this.reviewed,
    priceHistory: priceHistory ?? this.priceHistory,
  );

  factory SubscriptionExtra.fromJson(String source) {
    try {
      final data = jsonDecode(source) as Map<String, dynamic>;
      DateTime? date(String key) => DateTime.tryParse('${data[key] ?? ''}');
      return SubscriptionExtra(
        trialEndsOn: date('trialEndsOn'),
        pauseUntil: date('pauseUntil'),
        cancelAt: date('cancelAt'),
        cancellationReason: data['cancellationReason'] as String?,
        essential: data['essential'] == true,
        reviewed: data['reviewed'] == true,
        priceHistory: (data['priceHistory'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(SubscriptionPriceChange.fromJson)
            .whereType<SubscriptionPriceChange>()
            .toList(),
      );
    } catch (_) {
      return const SubscriptionExtra();
    }
  }

  String toJson() => jsonEncode({
    'trialEndsOn': trialEndsOn?.toIso8601String(),
    'pauseUntil': pauseUntil?.toIso8601String(),
    'cancelAt': cancelAt?.toIso8601String(),
    'cancellationReason': cancellationReason,
    'essential': essential,
    'reviewed': reviewed,
    'priceHistory': priceHistory.map((change) => change.toJson()).toList(),
  });
}

class SubscriptionPriceChange {
  const SubscriptionPriceChange({
    required this.fromPaise,
    required this.toPaise,
    required this.at,
  });
  final int fromPaise;
  final int toPaise;
  final DateTime at;

  static SubscriptionPriceChange? fromJson(Map<String, dynamic> data) {
    final from = data['from'];
    final to = data['to'];
    final at = DateTime.tryParse('${data['at'] ?? ''}');
    if (from is! int || to is! int || at == null) return null;
    return SubscriptionPriceChange(fromPaise: from, toPaise: to, at: at);
  }

  Map<String, dynamic> toJson() => {
    'from': fromPaise,
    'to': toPaise,
    'at': at.toIso8601String(),
  };
}

class FinanceRepository {
  FinanceRepository(this.db);

  static const _archivedEmiPrefix = 'emi.archived.';
  static const _archivedMoneyPrefix = 'money.archived.';
  static const _archivedSubscriptionPrefix = 'subscription.archived.';
  static const _subscriptionExtraPrefix = 'subscription.extra.';
  final LocalReminderService _localReminders = LocalReminderService();
  Future<void> _reminderQueue = Future<void>.value();
  bool _legacyRemindersCleared = false;

  Future<ReminderPlanSettings> reminderSettings() async {
    final rows = await (db.select(
      db.settings,
    )..where((row) => row.key.like('reminders.%'))).get();
    final values = {for (final row in rows) row.key: row.value};
    final time = (values['reminders.time'] ?? '09:00').split(':');
    final leads = (values['reminders.leads'] ?? '3,1,0')
        .split(',')
        .map(int.tryParse)
        .whereType<int>()
        .toSet();
    return ReminderPlanSettings(
      enabled: values['reminders.enabled'] == 'true',
      hour: int.tryParse(time.first) ?? 9,
      minute: time.length > 1 ? int.tryParse(time[1]) ?? 0 : 0,
      leadDays: leads,
      overdueNudge: values['reminders.overdue'] != 'false',
      emis: values['reminders.emis'] != 'false',
      money: values['reminders.money'] != 'false',
      subscriptions: values['reminders.subscriptions'] != 'false',
    );
  }

  Future<void> saveReminderSettings(ReminderPlanSettings settings) async {
    final values = <String, String>{
      'reminders.enabled': settings.enabled.toString(),
      'reminders.time':
          '${settings.hour.toString().padLeft(2, '0')}:${settings.minute.toString().padLeft(2, '0')}',
      'reminders.leads': (settings.leadDays.toList()..sort()).join(','),
      'reminders.overdue': settings.overdueNudge.toString(),
      'reminders.emis': settings.emis.toString(),
      'reminders.money': settings.money.toString(),
      'reminders.subscriptions': settings.subscriptions.toString(),
    };
    await db.transaction(() async {
      for (final entry in values.entries) {
        await db
            .into(db.settings)
            .insertOnConflictUpdate(
              SettingsCompanion.insert(key: entry.key, value: entry.value),
            );
      }
    });
    await refreshLocalReminders();
  }

  Future<void> refreshLocalReminders() {
    final task = _reminderQueue.then((_) => _rebuildLocalReminders());
    _reminderQueue = task.catchError((Object error, StackTrace stack) {
      debugPrint('Reminder scheduling failed: $error');
      debugPrintStack(stackTrace: stack);
    });
    return task;
  }

  void _queueReminderRefresh() {
    unawaited(
      refreshLocalReminders().catchError((Object error, StackTrace stack) {}),
    );
  }

  Future<void> _rebuildLocalReminders() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (!_legacyRemindersCleared) {
      await _localReminders.clearLegacySubscriptionReminders();
      _legacyRemindersCleared = true;
    }
    final settings = await reminderSettings();
    final now = DateTime.now();
    final targets = <ReminderTarget>[];
    var threeDays = true;
    var oneDay = true;
    if (settings.enabled) {
      for (final detail in await _visibleEmiDetails()) {
        if (detail.emi.status != EmiStatus.active) continue;
        for (final installment in detail.installments) {
          if (installment.isPaid) continue;
          targets.add(
            ReminderTarget(
              type: FinanceReminderType.emi,
              entityId: detail.emi.id,
              name: detail.emi.name,
              dueDate: installment.dueDate,
              amountPaise: detail.amountForInstallment(installment.number),
              installmentNumber: installment.number,
            ),
          );
        }
      }
      for (final detail in await moneyDetails()) {
        if (detail.summary.remainingAmountPaise <= 0 ||
            detail.record.dueDate == null) {
          continue;
        }
        targets.add(
          ReminderTarget(
            type: FinanceReminderType.money,
            entityId: detail.record.id,
            name: detail.record.personName,
            dueDate: detail.record.dueDate!,
            amountPaise: detail.summary.remainingAmountPaise,
          ),
        );
      }
      final extras = await subscriptionExtras();
      (threeDays, oneDay) = await subscriptionReminderDays();
      for (final item in await _visibleSubscriptions()) {
        if (item.status != SubscriptionStatus.active) continue;
        for (final due in subscriptionOccurrences(
          item.nextBillingDate,
          item.frequency,
          now,
          now.add(const Duration(days: 63)),
        )) {
          targets.add(
            ReminderTarget(
              type: FinanceReminderType.subscription,
              entityId: item.id,
              name: item.name,
              dueDate: due,
              amountPaise: item.amountPaise,
            ),
          );
        }
        final trial = extras[item.id]?.trialEndsOn;
        if (trial != null) {
          targets.add(
            ReminderTarget(
              type: FinanceReminderType.subscription,
              entityId: item.id,
              name: item.name,
              dueDate: trial,
              amountPaise: item.amountPaise,
              trial: true,
            ),
          );
        }
      }
    }
    final privacy =
        await (db.select(db.settings)..where(
              (row) => row.key.isIn(['privacy.mode', 'privacy.hideOnOpen']),
            ))
            .get();
    final hideAmounts = privacy.any((row) => row.value == 'true');
    final plan = buildReminderPlan(targets, settings, now)
        .where(
          (event) =>
              event.target.type != FinanceReminderType.subscription ||
              event.target.trial ||
              ((event.leadDays == 3 && threeDays) ||
                  (event.leadDays == 1 && oneDay)),
        )
        .toList();
    await _localReminders.replaceManaged(plan.map((event) => event.id));
    for (final event in plan) {
      final target = event.target;
      final dueText = formatDate(target.dueDate);
      final verb = switch (target.type) {
        FinanceReminderType.emi => 'EMI',
        FinanceReminderType.money => 'Money',
        FinanceReminderType.subscription => 'Subscription',
      };
      final title = target.trial
          ? '${target.name} trial ends soon'
          : event.leadDays < 0
          ? '$verb overdue: ${target.name}'
          : '$verb due: ${target.name}';
      final body =
          '${target.name} · ${target.trial ? 'Trial ends' : 'Due'} $dueText'
          '${hideAmounts ? '' : ' · ${formatMoneyUnmasked(target.amountPaise)}'}';
      await _localReminders.scheduleReminder(
        id: event.id,
        title: title,
        body: body,
        when: event.when,
        type: target.type,
        payload: LocalReminderService.payloadFor(target),
      );
    }
  }

  Future<void> scheduleAssistantReminder({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  }) => _localReminders.scheduleReminder(
    id: id,
    title: title,
    body: body,
    when: when,
  );

  Future<void> cancelAssistantReminder(int id) =>
      _localReminders.cancelReminder(id);

  static const _dailyBriefId = 1999999999;

  Future<({bool enabled, int hour, int minute})> dailyBriefSettings() async {
    final rows =
        await (db.select(db.settings)..where(
              (row) => row.key.isIn([
                'assistant.dailyBrief.enabled',
                'assistant.dailyBrief.time',
              ]),
            ))
            .get();
    final values = {for (final row in rows) row.key: row.value};
    final parts = (values['assistant.dailyBrief.time'] ?? '08:00').split(':');
    return (
      enabled: values['assistant.dailyBrief.enabled'] == 'true',
      hour: int.tryParse(parts.first) ?? 8,
      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );
  }

  Future<void> setDailyBrief({
    required bool enabled,
    required int hour,
    required int minute,
  }) async {
    await db
        .into(db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: 'assistant.dailyBrief.enabled',
            value: enabled.toString(),
          ),
        );
    await db
        .into(db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: 'assistant.dailyBrief.time',
            value:
                '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
          ),
        );
    await refreshDailyBrief();
  }

  Future<void> refreshDailyBrief() async {
    final setting = await dailyBriefSettings();
    await _localReminders.cancelReminder(_dailyBriefId);
    if (!setting.enabled) return;
    final now = DateTime.now();
    var next = DateTime(
      now.year,
      now.month,
      now.day,
      setting.hour,
      setting.minute,
    );
    if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
    final through = DateTime(now.year, now.month, now.day + 7);
    final due = (await reminders(attentionOnly: false))
        .where(
          (item) =>
              !dateOnly(item.dueAt).isBefore(dateOnly(now)) &&
              !dateOnly(item.dueAt).isAfter(through),
        )
        .toList();
    final amount = due.fold<int>(0, (sum, item) => sum + item.amountPaise);
    final privacy =
        await (db.select(db.settings)..where(
              (row) => row.key.isIn(['privacy.mode', 'privacy.hideOnOpen']),
            ))
            .get();
    final hideAmounts = privacy.any((row) => row.value == 'true');
    await _localReminders.scheduleReminder(
      id: _dailyBriefId,
      title: 'FinKeep morning brief',
      body:
          '${due.length} payments due this week${hideAmounts ? '' : ', ${formatMoneyUnmasked(amount)}'}.',
      when: next,
      repeatDaily: true,
    );
  }

  bool _subscriptionRemindersPrimed = false;
  final AppDatabase db;

  Stream<List<Emi>> watchEmis() =>
      db.select(db.emis).watch().asyncMap((emis) async {
        final archivedIds = await _archivedEmiIds();
        return emis.where((emi) => !archivedIds.contains(emi.id)).toList()
          ..sort((a, b) => a.nextDueDate.compareTo(b.nextDueDate));
      });

  Stream<List<EmiDetail>> watchEmiDetails() {
    late final StreamController<List<EmiDetail>> controller;
    final subscriptions = <StreamSubscription<void>>[];
    Timer? pending;
    var generation = 0;

    Future<void> emit() async {
      if (controller.isClosed) return;
      final request = ++generation;
      final details = await _visibleEmiDetails();
      details.sort((a, b) {
        final aDue = a.nextUnpaidInstallment?.dueDate ?? a.emi.nextDueDate;
        final bDue = b.nextUnpaidInstallment?.dueDate ?? b.emi.nextDueDate;
        return aDue.compareTo(bDue);
      });
      if (!controller.isClosed && request == generation) {
        controller.add(details);
      }
    }

    void scheduleEmit() {
      pending?.cancel();
      pending = Timer(const Duration(milliseconds: 24), emit);
    }

    controller = StreamController<List<EmiDetail>>(
      onListen: () {
        for (final stream in [
          db.select(db.emis).watch().map((_) {}),
          db.select(db.emiPayments).watch().map((_) {}),
          db.select(db.settings).watch().map((_) {}),
        ]) {
          subscriptions.add(stream.listen((_) => scheduleEmit()));
        }
      },
      onCancel: () {
        pending?.cancel();
        generation++;
        for (final subscription in subscriptions) {
          unawaited(subscription.cancel());
        }
      },
    );
    return controller.stream;
  }

  Future<List<EmiDetail>> _visibleEmiDetails() async {
    final archivedIds = await _archivedEmiIds();
    final emis = (await db.select(db.emis).get()).where(
      (emi) => !archivedIds.contains(emi.id),
    );
    final paymentsByEmi = <int, List<EmiPayment>>{};
    for (final payment in await db.select(db.emiPayments).get()) {
      paymentsByEmi.putIfAbsent(payment.emiId, () => []).add(payment);
    }
    return [
      for (final emi in emis)
        EmiDetail(emi: emi, payments: paymentsByEmi[emi.id] ?? const []),
    ];
  }

  Future<Set<int>> _archivedIds(String prefix) async {
    final rows = await (db.select(
      db.settings,
    )..where((setting) => setting.key.like('$prefix%'))).get();
    final ids = <int>{};
    for (final row in rows) {
      if (row.value != 'true') continue;
      final id = int.tryParse(row.key.substring(prefix.length));
      if (id != null) ids.add(id);
    }
    return ids;
  }

  Future<Set<int>> _archivedEmiIds() => _archivedIds(_archivedEmiPrefix);
  Future<Set<int>> _archivedMoneyIds() => _archivedIds(_archivedMoneyPrefix);
  Future<Set<int>> _archivedSubscriptionIds() =>
      _archivedIds(_archivedSubscriptionPrefix);

  Future<List<Subscription>> _visibleSubscriptions() async {
    final archivedIds = await _archivedSubscriptionIds();
    return (await db.select(db.subscriptions).get())
        .where((item) => !archivedIds.contains(item.id))
        .toList()
      ..sort((a, b) => a.nextBillingDate.compareTo(b.nextBillingDate));
  }

  Future<bool> _isEmiArchived(int id) async =>
      (await (db.select(db.settings)..where(
                (setting) => setting.key.equals('$_archivedEmiPrefix$id'),
              ))
              .getSingleOrNull())
          ?.value ==
      'true';

  Stream<List<MoneyRecordDetail>> watchMoneyRecords() {
    late final StreamController<List<MoneyRecordDetail>> controller;
    final subscriptions = <StreamSubscription<void>>[];
    Timer? pending;
    var generation = 0;

    Future<void> emit() async {
      if (controller.isClosed) return;
      final request = ++generation;
      final details = await moneyDetails();
      details.sort((a, b) {
        final aDate = a.record.dueDate ?? a.record.recordDate;
        final bDate = b.record.dueDate ?? b.record.recordDate;
        return aDate.compareTo(bDate);
      });
      if (!controller.isClosed && request == generation) {
        controller.add(details);
      }
    }

    void scheduleEmit() {
      pending?.cancel();
      pending = Timer(const Duration(milliseconds: 24), emit);
    }

    controller = StreamController<List<MoneyRecordDetail>>(
      onListen: () {
        for (final stream in [
          db.select(db.moneyRecords).watch().map((_) {}),
          db.select(db.moneyRepayments).watch().map((_) {}),
          db.select(db.settings).watch().map((_) {}),
        ]) {
          subscriptions.add(stream.listen((_) => scheduleEmit()));
        }
      },
      onCancel: () {
        pending?.cancel();
        generation++;
        for (final subscription in subscriptions) {
          unawaited(subscription.cancel());
        }
      },
    );
    return controller.stream;
  }

  Stream<MoneyRecordDetail?> watchMoneyDetail(int id) =>
      watchMoneyRecords().map((records) {
        for (final detail in records) {
          if (detail.record.id == id) return detail;
        }
        return null;
      });

  Stream<List<Subscription>> watchSubscriptions() =>
      db.select(db.subscriptions).watch().asyncMap((items) async {
        await refreshSubscriptionTransitions();
        items = await db.select(db.subscriptions).get();
        final archivedIds = await _archivedSubscriptionIds();
        return items.where((item) => !archivedIds.contains(item.id)).toList()
          ..sort((a, b) => a.nextBillingDate.compareTo(b.nextBillingDate));
      });

  Future<void> primeSubscriptionNotifications() async {
    if (_subscriptionRemindersPrimed) return;
    _subscriptionRemindersPrimed = true;
    try {
      await refreshLocalReminders();
    } catch (_) {
      _subscriptionRemindersPrimed = false;
      rethrow;
    }
  }

  Future<Subscription?> subscription(int id) async {
    if ((await _archivedSubscriptionIds()).contains(id)) return null;
    return (db.select(
      db.subscriptions,
    )..where((item) => item.id.equals(id))).getSingleOrNull();
  }

  Future<Map<int, SubscriptionExtra>> subscriptionExtras() async {
    final rows = await (db.select(
      db.settings,
    )..where((row) => row.key.like('$_subscriptionExtraPrefix%'))).get();
    final extras = <int, SubscriptionExtra>{};
    for (final row in rows) {
      final id = int.tryParse(
        row.key.substring(_subscriptionExtraPrefix.length),
      );
      if (id != null) extras[id] = SubscriptionExtra.fromJson(row.value);
    }
    return extras;
  }

  Future<SubscriptionExtra> subscriptionExtra(int id) async =>
      (await subscriptionExtras())[id] ?? const SubscriptionExtra();

  Future<void> saveSubscriptionExtra(int id, SubscriptionExtra extra) async {
    await db
        .into(db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: '$_subscriptionExtraPrefix$id',
            value: extra.toJson(),
          ),
        );
    unawaited(_syncSubscriptionNotifications(id));
  }

  Future<void> pauseSubscription(int id, {DateTime? until}) async {
    await setSubscriptionStatus(id, SubscriptionStatus.paused);
    final extra = await subscriptionExtra(id);
    await saveSubscriptionExtra(
      id,
      extra.copyWith(pauseUntil: until, clearPauseUntil: until == null),
    );
  }

  Future<void> resumeSubscription(int id) async {
    await setSubscriptionStatus(id, SubscriptionStatus.active);
    final extra = await subscriptionExtra(id);
    await saveSubscriptionExtra(
      id,
      extra.copyWith(clearPauseUntil: true, clearCancelAt: true),
    );
  }

  Future<void> cancelSubscription(
    int id, {
    required bool atCycleEnd,
    String? reason,
  }) async {
    final item = await subscription(id);
    if (item == null) return;
    final extra = await subscriptionExtra(id);
    if (atCycleEnd) {
      await saveSubscriptionExtra(
        id,
        extra.copyWith(
          cancelAt: nextSubscriptionBillingDate(
            item.nextBillingDate,
            item.frequency,
            DateTime.now(),
          ),
          cancellationReason: reason,
        ),
      );
    } else {
      await setSubscriptionStatus(id, SubscriptionStatus.cancelled);
      await saveSubscriptionExtra(
        id,
        extra.copyWith(cancellationReason: reason, clearCancelAt: true),
      );
    }
  }

  Future<void> refreshSubscriptionTransitions({DateTime? now}) async {
    final today = dateOnly(now ?? DateTime.now());
    final extras = await subscriptionExtras();
    for (final entry in extras.entries) {
      final item = await subscription(entry.key);
      if (item == null) continue;
      final extra = entry.value;
      if (extra.cancelAt != null &&
          !dateOnly(extra.cancelAt!).isAfter(today) &&
          item.status != SubscriptionStatus.cancelled) {
        await setSubscriptionStatus(item.id, SubscriptionStatus.cancelled);
        await saveSubscriptionExtra(
          item.id,
          extra.copyWith(clearCancelAt: true),
        );
      } else if (extra.pauseUntil != null &&
          !dateOnly(extra.pauseUntil!).isAfter(today) &&
          item.status == SubscriptionStatus.paused) {
        await setSubscriptionStatus(item.id, SubscriptionStatus.active);
        await saveSubscriptionExtra(
          item.id,
          extra.copyWith(clearPauseUntil: true),
        );
      }
    }
  }

  Future<(bool, bool)> subscriptionReminderDays() async {
    final rows =
        await (db.select(db.settings)..where(
              (row) => row.key.isIn([
                'subscription.reminder.3',
                'subscription.reminder.1',
              ]),
            ))
            .get();
    final values = {for (final row in rows) row.key: row.value};
    return (
      values['subscription.reminder.3'] != 'false',
      values['subscription.reminder.1'] != 'false',
    );
  }

  Future<void> setSubscriptionReminderDays({
    required bool threeDays,
    required bool oneDay,
  }) async {
    for (final entry in {
      'subscription.reminder.3': threeDays,
      'subscription.reminder.1': oneDay,
    }.entries) {
      await db
          .into(db.settings)
          .insertOnConflictUpdate(
            SettingsCompanion.insert(
              key: entry.key,
              value: entry.value.toString(),
            ),
          );
    }
    _queueReminderRefresh();
  }

  Future<void> _syncSubscriptionNotifications(int id) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      for (var slot = 0; slot < 4; slot++) {
        await _localReminders.cancelReminder(1000000 + id * 10 + slot);
      }
      await refreshLocalReminders();
    } catch (error, stackTrace) {
      debugPrint('Subscription reminder scheduling failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Stream<List<PaymentMethod>> watchPaymentMethods() => (db.select(
    db.paymentMethods,
  )..where((t) => t.isArchived.equals(false))).watch();

  Stream<List<ActivityLog>> watchActivity({int? limit}) {
    final query = db.select(db.activityLogs)
      ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]);
    if (limit != null) query.limit(limit);
    return query.watch();
  }

  Stream<List<ReminderItem>> watchReminders({bool attentionOnly = true}) {
    late final StreamController<List<ReminderItem>> controller;
    final subscriptions = <StreamSubscription<void>>[];
    Timer? pending;
    var generation = 0;

    Future<void> emit() async {
      if (controller.isClosed) return;
      final request = ++generation;
      final items = await reminders(attentionOnly: attentionOnly);
      if (!controller.isClosed && request == generation) controller.add(items);
    }

    void scheduleEmit() {
      pending?.cancel();
      pending = Timer(const Duration(milliseconds: 24), emit);
    }

    controller = StreamController<List<ReminderItem>>(
      onListen: () {
        for (final stream in [
          db.select(db.emis).watch().map((_) {}),
          db.select(db.emiPayments).watch().map((_) {}),
          db.select(db.moneyRecords).watch().map((_) {}),
          db.select(db.moneyRepayments).watch().map((_) {}),
          db.select(db.subscriptions).watch().map((_) {}),
          db.select(db.settings).watch().map((_) {}),
        ]) {
          subscriptions.add(stream.listen((_) => scheduleEmit()));
        }
      },
      onCancel: () async {
        pending?.cancel();
        generation++;
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      },
    );
    return controller.stream;
  }

  Stream<DashboardSummary> watchDashboard() {
    late final StreamController<DashboardSummary> controller;
    final subscriptions = <StreamSubscription<void>>[];
    Timer? pending;
    var generation = 0;

    Future<void> emit() async {
      if (controller.isClosed) return;
      final request = ++generation;
      final summary = await _loadDashboard();
      if (!controller.isClosed && request == generation) {
        controller.add(summary);
      }
    }

    void scheduleEmit() {
      pending?.cancel();
      pending = Timer(const Duration(milliseconds: 24), emit);
    }

    controller = StreamController<DashboardSummary>(
      onListen: () {
        for (final stream in [
          db.select(db.emis).watch().map((_) {}),
          db.select(db.emiPayments).watch().map((_) {}),
          db.select(db.moneyRecords).watch().map((_) {}),
          db.select(db.moneyRepayments).watch().map((_) {}),
          db.select(db.subscriptions).watch().map((_) {}),
          db.select(db.settings).watch().map((_) {}),
        ]) {
          subscriptions.add(stream.listen((_) => scheduleEmit()));
        }
      },
      onCancel: () async {
        pending?.cancel();
        generation++;
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      },
    );
    return controller.stream.distinct();
  }

  Future<DashboardSummary> _loadDashboard() async {
    final emiDetails = await _visibleEmiDetails();
    final records = await moneyDetails();
    final subscriptions = await _visibleSubscriptions();
    final today = dateOnly(DateTime.now());
    final attentionHorizon = today.add(dashboardPaymentHorizon);
    final subscriptionHorizon = today.add(dashboardSubscriptionHorizon);

    final borrowedRemaining = records
        .where((item) => item.record.direction == MoneyDirection.borrowed)
        .fold<int>(0, (sum, item) => sum + item.summary.remainingAmountPaise);
    final givenRemaining = records
        .where((item) => item.record.direction == MoneyDirection.given)
        .fold<int>(0, (sum, item) => sum + item.summary.remainingAmountPaise);
    final activeEmis = emiDetails
        .map((detail) => detail.emi)
        .where(
          (emi) =>
              emi.status != EmiStatus.completed &&
              emi.status != EmiStatus.paused,
        )
        .length;
    final upcomingEmis = emiDetails.where((detail) {
      if (detail.emi.status == EmiStatus.completed ||
          detail.emi.status == EmiStatus.paused) {
        return false;
      }
      final due = detail.nextUnpaidInstallment?.dueDate;
      return due != null && _isDueThrough(due, attentionHorizon);
    }).length;
    final upcomingLoans = records
        .where(
          (item) =>
              item.summary.remainingAmountPaise > 0 &&
              item.record.status != MoneyStatus.paused &&
              item.record.dueDate != null &&
              _isDueThrough(item.record.dueDate!, attentionHorizon),
        )
        .length;
    final upcomingSubscriptions = subscriptions
        .where((sub) => sub.status == SubscriptionStatus.active)
        .where(
          (sub) => _isDueThrough(
            nextSubscriptionBillingDate(
              sub.nextBillingDate,
              sub.frequency,
              today,
            ),
            subscriptionHorizon,
          ),
        )
        .length;
    final monthlyEmis = emiDetails
        .where(
          (detail) =>
              detail.emi.status != EmiStatus.completed &&
              detail.emi.status != EmiStatus.paused,
        )
        .fold<int>(
          0,
          (sum, detail) =>
              sum +
              monthlyEquivalentPaise(
                detail.scheduledInstallmentPaise,
                detail.emi.frequency,
              ),
        );
    final monthlySubs = subscriptions
        .where((sub) => sub.status == SubscriptionStatus.active)
        .fold<int>(
          0,
          (sum, sub) =>
              sum + monthlyEquivalentPaise(sub.amountPaise, sub.frequency),
        );
    final monthlyMoneyToPay = records
        .where(
          (item) =>
              item.record.direction == MoneyDirection.borrowed &&
              item.summary.remainingAmountPaise > 0 &&
              item.record.status != MoneyStatus.paused &&
              item.record.dueDate != null &&
              _isDueThrough(
                item.record.dueDate!,
                today.add(const Duration(days: 30)),
              ),
        )
        .fold<int>(0, (sum, item) => sum + item.summary.remainingAmountPaise);

    return DashboardSummary(
      // The dashboard balance mirrors the Money screen; recurring commitments
      // are reported separately as monthly outflow.
      needToPayPaise: borrowedRemaining,
      comingToMePaise: givenRemaining,
      activeEmis: activeEmis,
      upcomingPayments: upcomingEmis + upcomingLoans,
      upcomingSubscriptions: upcomingSubscriptions,
      monthlyOutflowPaise: monthlyEmis + monthlySubs + monthlyMoneyToPay,
      monthlyEmisPaise: monthlyEmis,
      monthlySubscriptionsPaise: monthlySubs,
      monthlyMoneyToPayPaise: monthlyMoneyToPay,
    );
  }

  Future<List<MoneyRecordDetail>> moneyDetails() async {
    final archivedIds = await _archivedMoneyIds();
    final records = (await db.select(db.moneyRecords).get()).where(
      (record) => !archivedIds.contains(record.id),
    );
    final repaymentsByRecord = <int, List<MoneyRepayment>>{};
    for (final repayment in await db.select(db.moneyRepayments).get()) {
      repaymentsByRecord
          .putIfAbsent(repayment.moneyRecordId, () => [])
          .add(repayment);
    }
    final details = <MoneyRecordDetail>[];
    for (final record in records) {
      final repayments =
          repaymentsByRecord[record.id] ?? const <MoneyRepayment>[];
      final summary = calculateRepaymentSummary(
        originalAmountPaise: record.amountPaise,
        repaymentAmountsPaise: repayments.map((item) => item.amountPaise),
        activeStatus: record.status == MoneyStatus.settled
            ? MoneyStatus.active
            : record.status,
      );
      if (summary.status != record.status) {
        await (db.update(
          db.moneyRecords,
        )..where((t) => t.id.equals(record.id))).write(
          MoneyRecordsCompanion(
            status: Value(summary.status),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
      details.add(
        MoneyRecordDetail(
          record: record,
          repayments: repayments,
          summary: summary,
        ),
      );
    }
    return details;
  }

  Future<MoneyRecordDetail> moneyDetail(int id) async {
    final record = await (db.select(
      db.moneyRecords,
    )..where((t) => t.id.equals(id))).getSingle();
    final repayments = await (db.select(
      db.moneyRepayments,
    )..where((t) => t.moneyRecordId.equals(id))).get();
    final summary = calculateRepaymentSummary(
      originalAmountPaise: record.amountPaise,
      repaymentAmountsPaise: repayments.map((item) => item.amountPaise),
      activeStatus: record.status == MoneyStatus.settled
          ? MoneyStatus.active
          : record.status,
    );
    if (summary.status != record.status) {
      await (db.update(db.moneyRecords)..where((t) => t.id.equals(id))).write(
        MoneyRecordsCompanion(
          status: Value(summary.status),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
    return MoneyRecordDetail(
      record: record,
      repayments: repayments,
      summary: summary,
    );
  }

  Future<EmiDetail> emiDetail(int id) async {
    final emi = await (db.select(
      db.emis,
    )..where((t) => t.id.equals(id))).getSingle();
    final payments = await (db.select(
      db.emiPayments,
    )..where((t) => t.emiId.equals(id))).get();
    return EmiDetail(emi: emi, payments: payments);
  }

  Future<int> saveEmi(EmisCompanion item) async {
    final isEdit = item.id.present;
    final normalized = await _validatedEmiCompanion(item);
    final id = await db.transaction(() async {
      if (!isEdit) return db.into(db.emis).insert(normalized);
      await (db.update(
        db.emis,
      )..where((row) => row.id.equals(item.id.value))).write(normalized);
      return item.id.value;
    });
    final saved = await emiDetail(id);
    await _logActivitySafely(
      type: isEdit ? ActivityType.emiEdited : ActivityType.emiCreated,
      title: isEdit ? 'EMI Edited' : 'EMI Added',
      description:
          '${saved.emi.name} · ${formatMoneyUnmasked(saved.scheduledInstallmentPaise)} × ${saved.emi.tenureMonths}',
      entityType: 'emi',
      entityId: id,
    );
    _queueReminderRefresh();
    return id;
  }

  Future<EmisCompanion> _validatedEmiCompanion(EmisCompanion item) async {
    Emi? existing;
    if (item.id.present) {
      existing = await (db.select(
        db.emis,
      )..where((t) => t.id.equals(item.id.value))).getSingleOrNull();
    }
    final principal = item.principalPaise.present
        ? item.principalPaise.value
        : existing?.principalPaise ?? 0;
    final installment = item.emiAmountPaise.present
        ? item.emiAmountPaise.value
        : existing?.emiAmountPaise ?? 0;
    final tenure = item.tenureMonths.present
        ? item.tenureMonths.value
        : existing?.tenureMonths ?? 0;
    final interest = item.interestRate.present
        ? item.interestRate.value
        : existing?.interestRate;
    final initialPaid = item.initialPaidInstallments.present
        ? item.initialPaidInstallments.value
        : existing?.initialPaidInstallments ?? 0;
    if (initialPaid < 0 || initialPaid > tenure) {
      throw const FormatException(
        'Already-paid installments must be between zero and the tenure.',
      );
    }
    final total = interest == null || interest == 0
        ? principal
        : installment * tenure;
    final schedule = calculateEmiSchedule(
      principalPaise: principal,
      installmentPaise: installment,
      tenure: tenure,
      annualInterestRate: interest,
      paidInstallmentAmounts: List<int>.generate(
        initialPaid.clamp(0, tenure),
        (index) => index + 1 == tenure
            ? (total - installment * (tenure - 1)).clamp(0, total)
            : installment,
      ),
    );
    if (!schedule.isConsistent) {
      throw FormatException(
        schedule.validationMessage ?? 'Invalid EMI details',
      );
    }
    if (existing != null) {
      final priorPayments = await (db.select(
        db.emiPayments,
      )..where((payment) => payment.emiId.equals(existing!.id))).get();
      final paidTotal = priorPayments.fold<int>(
        0,
        (sum, payment) => sum + payment.amountPaise,
      );
      final requestedStart = item.startDate.present
          ? item.startDate.value
          : existing.startDate;
      final scheduleChanged =
          principal != existing.principalPaise ||
          installment != existing.emiAmountPaise ||
          tenure != existing.tenureMonths ||
          interest != existing.interestRate ||
          requestedStart.year != existing.startDate.year ||
          requestedStart.month != existing.startDate.month ||
          requestedStart.day != existing.startDate.day ||
          (item.frequency.present &&
              item.frequency.value != existing.frequency);
      if ((priorPayments.isNotEmpty || existing.initialPaidInstallments > 0) &&
          scheduleChanged) {
        throw const FormatException(
          'EMI schedule cannot be changed after an installment is paid. Remove or reverse paid installments first.',
        );
      }
      if ((priorPayments.isNotEmpty || existing.initialPaidInstallments > 0) &&
          initialPaid != existing.initialPaidInstallments) {
        throw const FormatException(
          'Already-paid EMI count cannot be changed after payment history exists.',
        );
      }
      if (schedule.paidPaise + paidTotal > schedule.totalRepaymentPaise ||
          priorPayments.any(
            (payment) => payment.installmentNumber <= initialPaid,
          ) ||
          priorPayments.any((payment) => payment.installmentNumber > tenure)) {
        throw const FormatException(
          'EMI terms cannot make the remaining balance negative or remove paid installments.',
        );
      }
    }
    final startDate = item.startDate.present
        ? item.startDate.value
        : existing!.startDate;
    final frequency = item.frequency.present
        ? item.frequency.value
        : existing!.frequency;
    final paidNumbers = <int>{};
    if (existing != null) {
      paidNumbers.addAll(
        (await (db.select(
          db.emiPayments,
        )..where((payment) => payment.emiId.equals(existing!.id))).get()).map(
          (payment) => payment.installmentNumber,
        ),
      );
    }
    paidNumbers.addAll(
      Iterable<int>.generate(initialPaid, (index) => index + 1),
    );
    final next = buildEmiInstallments(
      startDate: startDate,
      tenure: tenure,
      frequency: frequency,
      paidInstallmentNumbers: paidNumbers,
      alreadyPaidCount: initialPaid,
    ).where((installment) => !installment.isPaid);
    final nextDueDate = next.isEmpty
        ? (item.nextDueDate.present
              ? item.nextDueDate
              : Value(existing!.nextDueDate))
        : Value(next.first.dueDate);
    return item.copyWith(nextDueDate: nextDueDate);
  }

  Future<void> deleteEmi(int id) async {
    final existing = await (db.select(
      db.emis,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (existing == null || await _isEmiArchived(id)) return;
    await db.transaction(() async {
      await db
          .into(db.settings)
          .insertOnConflictUpdate(
            SettingsCompanion.insert(
              key: '$_archivedEmiPrefix$id',
              value: 'true',
            ),
          );
      await (db.update(db.emis)..where((t) => t.id.equals(id))).write(
        EmisCompanion(updatedAt: Value(DateTime.now())),
      );
      await _logActivity(
        type: ActivityType.emiDeleted,
        title: 'EMI Deleted',
        description: existing.name,
        entityType: 'emi',
        entityId: id,
      );
    });
    _queueReminderRefresh();
  }

  Future<void> restoreEmi(int id) async {
    await (db.delete(
      db.settings,
    )..where((setting) => setting.key.equals('$_archivedEmiPrefix$id'))).go();
    _queueReminderRefresh();
  }

  Future<bool> markEmiPaid(
    int emiId, {
    required DateTime expectedDueDate,
    int? expectedInstallmentNumber,
    bool paidEarly = false,
  }) async {
    final changed = await db.transaction(() async {
      final emi = await (db.select(
        db.emis,
      )..where((t) => t.id.equals(emiId))).getSingleOrNull();
      if (emi == null ||
          emi.status == EmiStatus.completed ||
          emi.status == EmiStatus.paused ||
          await _isEmiArchived(emiId)) {
        return false;
      }

      final existingPayments = await (db.select(
        db.emiPayments,
      )..where((t) => t.emiId.equals(emiId))).get();
      final paidNumbers =
          existingPayments.map((payment) => payment.installmentNumber).toSet()
            ..addAll(
              Iterable<int>.generate(
                emi.initialPaidInstallments,
                (index) => index + 1,
              ),
            );
      final installments = buildEmiInstallments(
        startDate: emi.startDate,
        tenure: emi.tenureMonths,
        frequency: emi.frequency,
        paidInstallmentNumbers: paidNumbers,
        alreadyPaidCount: emi.initialPaidInstallments,
      );
      EmiInstallment? nextInstallment;
      for (final item in installments) {
        if (!item.isPaid) {
          nextInstallment = item;
          break;
        }
      }
      if (nextInstallment == null ||
          dateOnly(nextInstallment.dueDate) != dateOnly(expectedDueDate) ||
          (expectedInstallmentNumber != null &&
              nextInstallment.number != expectedInstallmentNumber)) {
        return false;
      }

      if (existingPayments.length + emi.initialPaidInstallments >=
          emi.tenureMonths) {
        await (db.update(db.emis)..where((t) => t.id.equals(emiId))).write(
          EmisCompanion(
            status: const Value(EmiStatus.completed),
            updatedAt: Value(DateTime.now()),
          ),
        );
        return false;
      }

      final installment = nextInstallment.number;
      final schedule = calculateEmiSchedule(
        principalPaise: emi.principalPaise,
        installmentPaise: emi.emiAmountPaise,
        tenure: emi.tenureMonths,
        annualInterestRate: emi.interestRate,
        paidInstallmentAmounts: [
          ...List<int>.generate(
            emi.initialPaidInstallments,
            (index) => EmiDetail(
              emi: emi,
              payments: const [],
            ).amountForInstallment(index + 1),
          ),
          ...existingPayments.map((item) => item.amountPaise),
        ],
      );
      final paymentAmount = EmiDetail(
        emi: emi,
        payments: existingPayments,
      ).amountForInstallment(installment);
      if (!schedule.isConsistent ||
          paymentAmount <= 0 ||
          paymentAmount > schedule.remainingBalancePaise) {
        return false;
      }
      final rowId = await db
          .into(db.emiPayments)
          .insert(
            EmiPaymentsCompanion.insert(
              emiId: emi.id,
              amountPaise: paymentAmount,
              paidOn: DateTime.now(),
              installmentNumber: installment,
              paidEarly: Value(paidEarly),
            ),
            mode: InsertMode.insertOrIgnore,
          );
      if (rowId == 0) return false;

      final completed = paidNumbers.length + 1 >= emi.tenureMonths;
      DateTime? nextDueDate;
      if (!completed) {
        for (final item in installments) {
          if (!item.isPaid && item.number != installment) {
            nextDueDate = item.dueDate;
            break;
          }
        }
      }
      await (db.update(db.emis)..where((t) => t.id.equals(emi.id))).write(
        EmisCompanion(
          status: Value(completed ? EmiStatus.completed : EmiStatus.active),
          nextDueDate: nextDueDate == null
              ? const Value.absent()
              : Value(nextDueDate),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _logActivity(
        type: paidEarly
            ? ActivityType.emiPaidEarly
            : ActivityType.emiPaymentRecorded,
        title: paidEarly ? 'EMI Paid Early' : 'EMI Paid',
        description:
            '${emi.name} · ${formatMoneyUnmasked(paymentAmount)} · installment $installment',
        entityType: 'emi',
        entityId: emi.id,
      );
      if (completed) {
        await _logActivity(
          type: ActivityType.emiCompleted,
          title: 'EMI Completed',
          description: emi.name,
          entityType: 'emi',
          entityId: emi.id,
        );
      }
      return true;
    });
    if (changed) _queueReminderRefresh();
    return changed;
  }

  Future<bool> revertEmiPayment(int emiId, int paymentId) async {
    final changed = await db.transaction(() async {
      final emi = await (db.select(
        db.emis,
      )..where((t) => t.id.equals(emiId))).getSingleOrNull();
      final payment =
          await (db.select(db.emiPayments)
                ..where((t) => t.id.equals(paymentId) & t.emiId.equals(emiId)))
              .getSingleOrNull();
      if (emi == null || payment == null || await _isEmiArchived(emiId)) {
        return false;
      }
      await (db.delete(
        db.emiPayments,
      )..where((t) => t.id.equals(paymentId))).go();
      final remainingPayments = await (db.select(
        db.emiPayments,
      )..where((t) => t.emiId.equals(emiId))).get();
      final paidNumbers =
          remainingPayments.map((item) => item.installmentNumber).toSet()
            ..addAll(
              Iterable<int>.generate(
                emi.initialPaidInstallments,
                (index) => index + 1,
              ),
            );
      final schedule = buildEmiInstallments(
        startDate: emi.startDate,
        tenure: emi.tenureMonths,
        frequency: emi.frequency,
        paidInstallmentNumbers: paidNumbers,
        alreadyPaidCount: emi.initialPaidInstallments,
      );
      final next = schedule.where((item) => !item.isPaid).firstOrNull;
      await (db.update(db.emis)..where((t) => t.id.equals(emiId))).write(
        EmisCompanion(
          status: Value(next == null ? EmiStatus.completed : EmiStatus.active),
          nextDueDate: next == null
              ? const Value.absent()
              : Value(next.dueDate),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _logActivity(
        type: ActivityType.emiEdited,
        title: 'EMI Payment Reverted',
        description: '${emi.name} · installment ${payment.installmentNumber}',
        entityType: 'emi',
        entityId: emiId,
      );
      return true;
    });
    if (changed) _queueReminderRefresh();
    return changed;
  }

  Future<int> saveMoneyRecord(MoneyRecordsCompanion item) async {
    final isEdit = item.id.present;
    if (isEdit) {
      final existing = await (db.select(
        db.moneyRecords,
      )..where((record) => record.id.equals(item.id.value))).getSingleOrNull();
      if (existing != null) {
        if (item.direction.present &&
            item.direction.value != existing.direction) {
          throw const FormatException(
            'Direction cannot be changed on an existing record. Create a new record instead.',
          );
        }
        final repayments =
            await (db.select(db.moneyRepayments)..where(
                  (repayment) => repayment.moneyRecordId.equals(item.id.value),
                ))
                .get();
        final repaidPaise = repayments.fold<int>(
          0,
          (sum, repayment) => sum + repayment.amountPaise,
        );
        final updatedAmount = item.amountPaise.present
            ? item.amountPaise.value
            : existing.amountPaise;
        if (updatedAmount < repaidPaise) {
          throw FormatException(
            'Amount cannot be less than the ${formatMoney(repaidPaise)} already repaid',
          );
        }
      }
    }
    final requestedAmount = item.amountPaise.present
        ? item.amountPaise.value
        : (isEdit
              ? (await (db.select(db.moneyRecords)
                          ..where((record) => record.id.equals(item.id.value)))
                        .getSingle())
                    .amountPaise
              : 0);
    if (requestedAmount <= 0) {
      throw const FormatException('Amount must be greater than zero.');
    }
    final id = await db.transaction(() async {
      if (!isEdit) return db.into(db.moneyRecords).insert(item);
      await (db.update(
        db.moneyRecords,
      )..where((record) => record.id.equals(item.id.value))).write(item);
      return item.id.value;
    });
    final saved = await (db.select(
      db.moneyRecords,
    )..where((record) => record.id.equals(id))).getSingle();
    await _logActivitySafely(
      type: isEdit
          ? ActivityType.moneyEdited
          : saved.direction == MoneyDirection.given
          ? ActivityType.moneyGiven
          : ActivityType.moneyBorrowed,
      title: isEdit
          ? 'Updated ${displayName(saved.personName)}\'s record'
          : saved.direction == MoneyDirection.given
          ? 'You gave ${displayName(saved.personName)} ${formatMoneyUnmasked(saved.amountPaise)}'
          : 'You borrowed ${formatMoneyUnmasked(saved.amountPaise)} from ${displayName(saved.personName)}',
      description: saved.notes,
      entityType: 'money',
      entityId: id,
    );
    _queueReminderRefresh();
    return id;
  }

  Future<void> deleteMoneyRecord(int id) async {
    final existing = await (db.select(
      db.moneyRecords,
    )..where((item) => item.id.equals(id))).getSingleOrNull();
    if (existing == null || (await _archivedMoneyIds()).contains(id)) return;
    await db.transaction(() async {
      await db
          .into(db.settings)
          .insertOnConflictUpdate(
            SettingsCompanion.insert(
              key: '$_archivedMoneyPrefix$id',
              value: 'true',
            ),
          );
      await _logActivity(
        type: ActivityType.moneyDeleted,
        title: 'Deleted ${displayName(existing.personName)}\'s record',
        description: null,
        entityType: 'money',
        entityId: id,
      );
    });
    _queueReminderRefresh();
  }

  Future<void> restoreMoneyRecord(int id) async {
    await (db.delete(
      db.settings,
    )..where((setting) => setting.key.equals('$_archivedMoneyPrefix$id'))).go();
    _queueReminderRefresh();
  }

  Future<void> updateMoneyDueDate(int id, DateTime dueDate) async {
    await setMoneyDueDate(id, dueDate, activityVerb: 'Extended');
  }

  Future<void> setMoneyDueDate(
    int id,
    DateTime? dueDate, {
    String activityVerb = 'Changed',
  }) async {
    await db.transaction(() async {
      final record = await (db.select(
        db.moneyRecords,
      )..where((item) => item.id.equals(id))).getSingleOrNull();
      if (record == null) throw StateError('Money record no longer exists');
      await (db.update(
        db.moneyRecords,
      )..where((item) => item.id.equals(id))).write(
        MoneyRecordsCompanion(
          dueDate: Value(dueDate),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _logActivity(
        type: ActivityType.moneyEdited,
        title: dueDate == null
            ? 'Removed ${displayName(record.personName)}\'s due date'
            : '$activityVerb ${displayName(record.personName)}\'s due date',
        description: dueDate == null
            ? 'No due date'
            : 'Now due ${formatDate(dueDate)}',
        entityType: 'money',
        entityId: id,
      );
    });
    _queueReminderRefresh();
  }

  Future<int> addRepayment(
    int moneyRecordId,
    int amountPaise,
    String? notes,
    DateTime? paidOn,
  ) async {
    if (amountPaise <= 0) {
      throw const FormatException('Enter an amount greater than zero');
    }
    final repaymentId = await db.transaction(() async {
      final record = await (db.select(
        db.moneyRecords,
      )..where((item) => item.id.equals(moneyRecordId))).getSingleOrNull();
      if (record == null) throw StateError('Money record no longer exists');
      final existing = await (db.select(
        db.moneyRepayments,
      )..where((item) => item.moneyRecordId.equals(moneyRecordId))).get();
      final outstanding =
          record.amountPaise -
          existing.fold<int>(0, (sum, item) => sum + item.amountPaise);
      if (amountPaise > outstanding) {
        throw FormatException(
          'Repayment cannot exceed the remaining ${formatMoney(outstanding)}',
        );
      }
      final id = await db
          .into(db.moneyRepayments)
          .insert(
            MoneyRepaymentsCompanion.insert(
              moneyRecordId: moneyRecordId,
              amountPaise: amountPaise,
              paidOn: paidOn ?? DateTime.now(),
              notes: Value(notes),
            ),
          );
      await _logActivity(
        type: ActivityType.moneyRepayment,
        title: record.direction == MoneyDirection.given
            ? '${displayName(record.personName)} repaid ${formatMoneyUnmasked(amountPaise)}'
            : 'You repaid ${formatMoneyUnmasked(amountPaise)} to ${displayName(record.personName)}',
        description: notes,
        entityType: 'money',
        entityId: moneyRecordId,
      );
      return id;
    });
    await moneyDetail(moneyRecordId);
    _queueReminderRefresh();
    return repaymentId;
  }

  Future<bool> revertMoneyRepayment(int recordId, int repaymentId) async {
    final changed = await db.transaction(() async {
      final record = await (db.select(
        db.moneyRecords,
      )..where((item) => item.id.equals(recordId))).getSingleOrNull();
      final repayment =
          await (db.select(db.moneyRepayments)..where(
                (item) =>
                    item.id.equals(repaymentId) &
                    item.moneyRecordId.equals(recordId),
              ))
              .getSingleOrNull();
      if (record == null || repayment == null) return false;
      await (db.delete(
        db.moneyRepayments,
      )..where((item) => item.id.equals(repaymentId))).go();
      await _logActivity(
        type: ActivityType.moneyEdited,
        title: 'Undid repayment for ${displayName(record.personName)}',
        description: formatMoneyUnmasked(repayment.amountPaise),
        entityType: 'money',
        entityId: recordId,
      );
      return true;
    });
    if (changed) _queueReminderRefresh();
    return changed;
  }

  Future<int> saveSubscription(SubscriptionsCompanion item) async {
    final isEdit = item.id.present;
    final existing = isEdit ? await subscription(item.id.value) : null;
    final amount = item.amountPaise.present
        ? item.amountPaise.value
        : existing?.amountPaise ?? 0;
    if (amount <= 0) {
      throw const FormatException(
        'Subscription amount must be greater than zero.',
      );
    }
    final name = item.name.present ? item.name.value : existing?.name ?? '';
    final frequency = item.frequency.present
        ? item.frequency.value
        : existing?.frequency;
    final due = item.nextBillingDate.present
        ? item.nextBillingDate.value
        : existing?.nextBillingDate;
    final status = item.status.present ? item.status.value : existing?.status;
    final category = item.category.present
        ? item.category.value
        : existing?.category;
    final notes = item.notes.present ? item.notes.value : existing?.notes;
    final paymentMethodId = item.paymentMethodId.present
        ? item.paymentMethodId.value
        : existing?.paymentMethodId;
    if (existing != null &&
        name == existing.name &&
        amount == existing.amountPaise &&
        frequency == existing.frequency &&
        due == existing.nextBillingDate &&
        status == existing.status &&
        category == existing.category &&
        notes == existing.notes &&
        paymentMethodId == existing.paymentMethodId) {
      return existing.id;
    }
    final id = await db.transaction(() async {
      final id = existing == null
          ? await db.into(db.subscriptions).insert(item)
          : existing.id;
      if (existing != null) {
        await (db.update(
          db.subscriptions,
        )..where((row) => row.id.equals(id))).write(item);
      }
      return id;
    });
    final saved = await subscription(id);
    final title = existing == null
        ? '${displayName(name)} added'
        : status != existing.status
        ? '${displayName(name)} ${status == SubscriptionStatus.paused
              ? 'paused'
              : status == SubscriptionStatus.active
              ? 'resumed'
              : status!.label.toLowerCase()}'
        : amount != existing.amountPaise
        ? '${displayName(name)} price changed to ${formatMoneyUnmasked(amount)}'
        : due != existing.nextBillingDate
        ? '${displayName(name)} billing date changed to ${formatDate(due!)}'
        : '${displayName(name)} updated';
    await _logActivitySafely(
      type: isEdit
          ? ActivityType.subscriptionChanged
          : ActivityType.subscriptionCreated,
      title: title,
      description: saved == null
          ? 'Subscription'
          : '${displayName(saved.name)} · ${formatMoneyUnmasked(saved.amountPaise)}',
      entityType: 'subscription',
      entityId: id,
    );
    if (existing != null && existing.amountPaise != amount) {
      final extra = await subscriptionExtra(id);
      await saveSubscriptionExtra(
        id,
        extra.copyWith(
          priceHistory: [
            ...extra.priceHistory,
            SubscriptionPriceChange(
              fromPaise: existing.amountPaise,
              toPaise: amount,
              at: DateTime.now(),
            ),
          ],
        ),
      );
    } else {
      unawaited(_syncSubscriptionNotifications(id));
    }
    return id;
  }

  Future<void> deleteSubscription(int id) async {
    await db.transaction(() async {
      final existing = await (db.select(
        db.subscriptions,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (existing == null || (await _archivedSubscriptionIds()).contains(id)) {
        return;
      }
      await db
          .into(db.settings)
          .insertOnConflictUpdate(
            SettingsCompanion.insert(
              key: '$_archivedSubscriptionPrefix$id',
              value: 'true',
            ),
          );
      await (db.update(db.subscriptions)..where((item) => item.id.equals(id)))
          .write(SubscriptionsCompanion(updatedAt: Value(DateTime.now())));
      await _logActivity(
        type: ActivityType.subscriptionDeleted,
        title: '${displayName(existing.name)} deleted',
        description:
            '${displayName(existing.name)} · ${formatMoneyUnmasked(existing.amountPaise)}',
        entityType: 'subscription',
        entityId: id,
      );
    });
    unawaited(_syncSubscriptionNotifications(id));
  }

  Future<void> setSubscriptionStatus(int id, SubscriptionStatus status) async {
    await db.transaction(() async {
      final existing = await subscription(id);
      if (existing == null) return;
      if (existing.status == status) return;
      await (db.update(db.subscriptions)..where((t) => t.id.equals(id))).write(
        SubscriptionsCompanion(
          status: Value(status),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _logActivity(
        type: ActivityType.subscriptionChanged,
        title:
            '${displayName(existing.name)} ${status == SubscriptionStatus.paused
                ? 'paused'
                : status == SubscriptionStatus.active
                ? 'resumed'
                : status.label.toLowerCase()}',
        description:
            '${displayName(existing.name)} · ${formatMoneyUnmasked(existing.amountPaise)} · ${status.label}',
        entityType: 'subscription',
        entityId: id,
      );
    });
    unawaited(_syncSubscriptionNotifications(id));
  }

  Future<void> restoreSubscription(Subscription item) async {
    await db.transaction(() async {
      await db.into(db.subscriptions).insertOnConflictUpdate(item);
      await (db.delete(db.settings)..where(
            (setting) =>
                setting.key.equals('$_archivedSubscriptionPrefix${item.id}'),
          ))
          .go();
      await _logActivity(
        type: ActivityType.subscriptionCreated,
        title: '${displayName(item.name)} restored',
        description: formatMoneyUnmasked(item.amountPaise),
        entityType: 'subscription',
        entityId: item.id,
      );
    });
    unawaited(_syncSubscriptionNotifications(item.id));
  }

  Future<void> restoreSubscriptionById(int id) async {
    final item = await (db.select(
      db.subscriptions,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (item != null) await restoreSubscription(item);
  }

  Future<int> addPaymentMethod(String label, String kind) => db
      .into(db.paymentMethods)
      .insert(PaymentMethodsCompanion.insert(label: label, kind: Value(kind)));

  Future<void> clearAllData() async {
    await db.transaction(() async {
      await db.delete(db.emiPayments).go();
      await db.delete(db.moneyRepayments).go();
      await db.delete(db.emis).go();
      await db.delete(db.moneyRecords).go();
      await db.delete(db.subscriptions).go();
      await db.delete(db.activityLogs).go();
      await (db.delete(db.settings)..where(
            (setting) =>
                setting.key.like('$_archivedEmiPrefix%') |
                setting.key.like('$_archivedMoneyPrefix%') |
                setting.key.like('$_archivedSubscriptionPrefix%'),
          ))
          .go();
    });
  }

  Future<List<ReminderItem>> reminders({bool attentionOnly = true}) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final items = <ReminderItem>[];
    for (final detail in await _visibleEmiDetails()) {
      final emi = detail.emi;
      final isPaused = emi.status == EmiStatus.paused;
      final unpaid = detail.installments.where((item) => !item.isPaid);
      for (final installment in unpaid) {
        final isNext =
            installment.number == detail.nextUnpaidInstallment?.number;
        items.add(
          ReminderItem(
            title: displayName(emi.name),
            subtitle: isPaused
                ? 'Paused'
                : '${relativeDueText(installment.dueDate, today)} · installment ${installment.number}',
            dueAt: installment.dueDate,
            status: emi.status == EmiStatus.completed || isPaused
                ? ReminderStatus.completed
                : reminderStatusFor(installment.dueDate, today),
            entityType: 'emi',
            entityId: emi.id,
            amountPaise: detail.amountForInstallment(installment.number),
            installmentNumber: installment.number,
            isNextInstallment: isNext,
          ),
        );
      }
      if (unpaid.isEmpty) {
        items.add(
          ReminderItem(
            title: emi.name,
            subtitle: 'Completed',
            dueAt: emi.nextDueDate,
            status: ReminderStatus.completed,
            entityType: 'emi',
            entityId: emi.id,
            amountPaise: 0,
          ),
        );
      }
    }

    for (final detail in await moneyDetails()) {
      final due = detail.record.dueDate;
      if (due == null) continue;
      final isInactive =
          detail.summary.remainingAmountPaise == 0 ||
          detail.record.status == MoneyStatus.paused;
      items.add(
        ReminderItem(
          title: detail.record.direction == MoneyDirection.given
              ? '${displayName(detail.record.personName)} owes me'
              : 'I owe ${displayName(detail.record.personName)}',
          subtitle: detail.summary.remainingAmountPaise == 0
              ? 'Paid/Completed'
              : detail.record.status == MoneyStatus.paused
              ? 'Paused'
              : relativeDueText(due, today),
          dueAt: due,
          status: isInactive
              ? ReminderStatus.completed
              : reminderStatusFor(due, today),
          entityType: 'money',
          entityId: detail.record.id,
          amountPaise: detail.summary.remainingAmountPaise,
        ),
      );
    }

    final subscriptions = await _visibleSubscriptions();
    for (final sub in subscriptions) {
      final billingDate = nextSubscriptionBillingDate(
        sub.nextBillingDate,
        sub.frequency,
        today,
      );
      items.add(
        ReminderItem(
          title: displayName(sub.name),
          subtitle: sub.status == SubscriptionStatus.active
              ? relativeDueText(billingDate, today)
              : sub.status.label,
          dueAt: billingDate,
          status: sub.status == SubscriptionStatus.active
              ? reminderStatusFor(billingDate, today)
              : ReminderStatus.completed,
          entityType: 'subscription',
          entityId: sub.id,
          amountPaise: sub.amountPaise,
        ),
      );
    }
    items.sort((a, b) => a.dueAt.compareTo(b.dueAt));
    if (!attentionOnly) return items;
    final attentionThrough = today.add(dashboardPaymentHorizon);
    return items
        .where(
          (item) =>
              item.status != ReminderStatus.completed &&
              !dateOnly(item.dueAt).isAfter(attentionThrough),
        )
        .toList();
  }

  Future<void> _logActivity({
    required ActivityType type,
    required String title,
    required String? description,
    required String entityType,
    required int entityId,
  }) {
    return db
        .into(db.activityLogs)
        .insert(
          ActivityLogsCompanion.insert(
            type: type,
            title: title,
            description: Value(description),
            entityType: Value(entityType),
            entityId: Value(entityId),
            occurredAt: Value(DateTime.now()),
          ),
        );
  }

  Future<void> _logActivitySafely({
    required ActivityType type,
    required String title,
    required String? description,
    required String entityType,
    required int entityId,
  }) async {
    try {
      await _logActivity(
        type: type,
        title: title,
        description: description,
        entityType: entityType,
        entityId: entityId,
      );
    } catch (error, stackTrace) {
      debugPrint('Activity log write failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  bool _isDueThrough(DateTime date, DateTime horizon) =>
      !dateOnly(date).isAfter(dateOnly(horizon));
}

class PdfExportService {
  PdfExportService(this.db);

  final AppDatabase db;

  Future<File> exportPdf() async {
    final repo = FinanceRepository(db);
    final summary = await repo._loadDashboard();
    final emiDetails = await repo.watchEmiDetails().first;
    final emis = await db.select(db.emis).get();
    final emiPayments = await db.select(db.emiPayments).get();
    final money = await repo.moneyDetails();
    final subscriptions = await db.select(db.subscriptions).get();
    final paymentMethods = await db.select(db.paymentMethods).get();
    final activity =
        await (db.select(db.activityLogs)
              ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)])
              ..limit(20))
            .get();

    final document = pw.Document(title: 'FinKeep export');
    document.addPage(
      pw.MultiPage(
        pageTheme: const pw.PageTheme(margin: pw.EdgeInsets.all(28)),
        build: (context) => [
          pw.Text(
            'FinKeep Financial Export',
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text('Exported ${formatDateTime(DateTime.now())}'),
          pw.SizedBox(height: 18),
          _pdfSection('Important totals'),
          _pdfTable([
            ['Money I need to pay', _pdfMoney(summary.needToPayPaise)],
            ['Money coming to me', _pdfMoney(summary.comingToMePaise)],
            ['Monthly outflow', _pdfMoney(summary.monthlyOutflowPaise)],
            ['Monthly EMI equivalent', _pdfMoney(summary.monthlyEmisPaise)],
            [
              'Money due within 30 days',
              _pdfMoney(summary.monthlyMoneyToPayPaise),
            ],
            [
              'Monthly subscription equivalent',
              _pdfMoney(summary.monthlySubscriptionsPaise),
            ],
            ['Active EMIs', summary.activeEmis.toString()],
            ['Upcoming payments', summary.upcomingPayments.toString()],
          ]),
          _pdfSection('EMI / loan summary'),
          _pdfTable([
            ['Name', 'Amount', 'Due', 'Status'],
            for (final emi in emis)
              [
                emi.name,
                _pdfMoney(emi.emiAmountPaise),
                formatDate(emi.nextDueDate),
                emi.status.label,
              ],
          ]),
          _pdfSection('EMI payment history'),
          _pdfTable([
            ['EMI', 'Installment', 'Amount', 'Paid at'],
            for (final payment in emiPayments)
              [
                emis
                        .where((emi) => emi.id == payment.emiId)
                        .map((emi) => emi.name)
                        .firstOrNull ??
                    'Deleted EMI',
                '#${payment.installmentNumber}',
                _pdfMoney(payment.amountPaise),
                formatDateTime(payment.paidOn),
              ],
          ]),
          _pdfSection('EMI installment schedule'),
          _pdfTable([
            ['EMI', 'Installment', 'Amount', 'Due date', 'Status'],
            for (final detail in emiDetails)
              for (final installment in detail.installments)
                [
                  detail.emi.name,
                  '#${installment.number}',
                  _pdfMoney(detail.amountForInstallment(installment.number)),
                  formatDate(installment.dueDate),
                  installment.isPaid ? 'Paid' : 'Upcoming',
                ],
          ]),
          _pdfSection('Money given'),
          _pdfTable([
            ['Person', 'Original', 'Repaid', 'Remaining'],
            for (final item in money.where(
              (item) => item.record.direction == MoneyDirection.given,
            ))
              [
                item.record.personName,
                _pdfMoney(item.record.amountPaise),
                _pdfMoney(item.summary.repaidAmountPaise),
                _pdfMoney(item.summary.remainingAmountPaise),
              ],
          ]),
          _pdfSection('Money borrowed'),
          _pdfTable([
            ['Person', 'Original', 'Paid', 'Remaining'],
            for (final item in money.where(
              (item) => item.record.direction == MoneyDirection.borrowed,
            ))
              [
                item.record.personName,
                _pdfMoney(item.record.amountPaise),
                _pdfMoney(item.summary.repaidAmountPaise),
                _pdfMoney(item.summary.remainingAmountPaise),
              ],
          ]),
          _pdfSection('Repayment history'),
          _pdfTable([
            ['Person', 'Amount', 'Paid at'],
            for (final item in money)
              for (final repayment in item.repayments)
                [
                  item.record.personName,
                  _pdfMoney(repayment.amountPaise),
                  formatDateTime(repayment.paidOn),
                ],
          ]),
          _pdfSection('Subscriptions'),
          _pdfTable([
            [
              'Name',
              'Amount',
              'Frequency',
              'Monthly equivalent',
              'Next billing',
              'Status',
            ],
            for (final sub in subscriptions)
              [
                sub.name,
                _pdfMoney(sub.amountPaise),
                sub.frequency.label,
                _pdfMoney(
                  monthlyEquivalentPaise(sub.amountPaise, sub.frequency),
                ),
                formatDate(sub.nextBillingDate),
                sub.status.label,
              ],
          ]),
          _pdfSection('Payment methods'),
          _pdfTable([
            ['Label', 'Type'],
            for (final method in paymentMethods) [method.label, method.kind],
          ]),
          _pdfSection('Recent activity'),
          _pdfTable([
            ['Activity', 'When', 'Details'],
            for (final event in activity)
              [
                event.title,
                formatDateTime(event.occurredAt),
                event.description ?? '',
              ],
          ]),
        ],
      ),
    );

    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}/finkeep-export-${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
    await file.writeAsBytes(await document.save());
    return file;
  }

  Future<void> shareExport() async {
    final file = await exportPdf();
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: 'FinKeep PDF export'),
    );
  }

  pw.Widget _pdfSection(String title) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 18, bottom: 8),
    child: pw.Text(
      title,
      style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
    ),
  );

  pw.Widget _pdfTable(List<List<String>> rows) {
    if (rows.length <= 1) return pw.Text('No records');
    return pw.TableHelper.fromTextArray(
      cellAlignment: pw.Alignment.centerLeft,
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellPadding: const pw.EdgeInsets.all(5),
      data: rows,
    );
  }

  String _pdfMoney(int paise) =>
      formatMoneyUnmasked(paise).replaceFirst('₹', 'INR ');
}
