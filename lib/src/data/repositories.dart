import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../core/formatters.dart';
import '../domain/due_status.dart';
import '../domain/emi_math.dart';
import '../domain/emi_payment_rules.dart' show dateOnly;
import '../domain/enums.dart';
import '../domain/money_math.dart';
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

class FinanceRepository {
  FinanceRepository(this.db);

  static const _archivedEmiPrefix = 'emi.archived.';
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

    Future<void> emit() async {
      if (controller.isClosed) return;
      final archivedIds = await _archivedEmiIds();
      final emis = (await db.select(db.emis).get()).where(
        (emi) => !archivedIds.contains(emi.id),
      );
      final details = <EmiDetail>[];
      for (final emi in emis) {
        details.add(await emiDetail(emi.id));
      }
      details.sort((a, b) {
        final aDue = a.nextUnpaidInstallment?.dueDate ?? a.emi.nextDueDate;
        final bDue = b.nextUnpaidInstallment?.dueDate ?? b.emi.nextDueDate;
        return aDue.compareTo(bDue);
      });
      if (!controller.isClosed) controller.add(details);
    }

    controller = StreamController<List<EmiDetail>>(
      onListen: () {
        emit();
        for (final stream in [
          db.select(db.emis).watch().map((_) {}),
          db.select(db.settings).watch().map((_) {}),
        ]) {
          subscriptions.add(stream.listen((_) => emit()));
        }
      },
      onCancel: () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      },
    );
    return controller.stream;
  }

  Future<Set<int>> _archivedEmiIds() async {
    final rows = await (db.select(
      db.settings,
    )..where((setting) => setting.key.like('$_archivedEmiPrefix%'))).get();
    final ids = <int>{};
    for (final row in rows) {
      if (row.value != 'true') continue;
      final id = int.tryParse(row.key.substring(_archivedEmiPrefix.length));
      if (id != null) ids.add(id);
    }
    return ids;
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

    Future<void> emit() async {
      if (controller.isClosed) return;
      final records = await db.select(db.moneyRecords).get();
      final details = <MoneyRecordDetail>[];
      for (final record in records) {
        details.add(await moneyDetail(record.id));
      }
      details.sort((a, b) {
        final aDate = a.record.dueDate ?? a.record.recordDate;
        final bDate = b.record.dueDate ?? b.record.recordDate;
        return aDate.compareTo(bDate);
      });
      if (!controller.isClosed) controller.add(details);
    }

    controller = StreamController<List<MoneyRecordDetail>>(
      onListen: () {
        emit();
        for (final stream in [
          db.select(db.moneyRecords).watch().map((_) {}),
          db.select(db.moneyRepayments).watch().map((_) {}),
        ]) {
          subscriptions.add(stream.listen((_) => emit()));
        }
      },
      onCancel: () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
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

  Stream<List<Subscription>> watchSubscriptions() => (db.select(
    db.subscriptions,
  )..orderBy([(t) => OrderingTerm(expression: t.nextBillingDate)])).watch();

  Future<Subscription?> subscription(int id) => (db.select(
    db.subscriptions,
  )..where((item) => item.id.equals(id))).getSingleOrNull();

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

    Future<void> emit() async {
      if (!controller.isClosed) {
        controller.add(await reminders(attentionOnly: attentionOnly));
      }
    }

    controller = StreamController<List<ReminderItem>>(
      onListen: () {
        emit();
        for (final stream in [
          db.select(db.emis).watch().map((_) {}),
          db.select(db.emiPayments).watch().map((_) {}),
          db.select(db.moneyRecords).watch().map((_) {}),
          db.select(db.moneyRepayments).watch().map((_) {}),
          db.select(db.subscriptions).watch().map((_) {}),
        ]) {
          subscriptions.add(stream.listen((_) => emit()));
        }
      },
      onCancel: () async {
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

    Future<void> emit() async {
      if (!controller.isClosed) controller.add(await _loadDashboard());
    }

    controller = StreamController<DashboardSummary>(
      onListen: () {
        emit();
        for (final stream in [
          db.select(db.emis).watch().map((_) {}),
          db.select(db.emiPayments).watch().map((_) {}),
          db.select(db.moneyRecords).watch().map((_) {}),
          db.select(db.moneyRepayments).watch().map((_) {}),
          db.select(db.subscriptions).watch().map((_) {}),
        ]) {
          subscriptions.add(stream.listen((_) => emit()));
        }
      },
      onCancel: () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      },
    );
    return controller.stream;
  }

  Future<DashboardSummary> _loadDashboard() async {
    final archivedIds = await _archivedEmiIds();
    final emis = (await db.select(db.emis).get())
        .where((emi) => !archivedIds.contains(emi.id))
        .toList();
    final emiDetails = <EmiDetail>[];
    for (final emi in emis) {
      emiDetails.add(await emiDetail(emi.id));
    }
    final records = await moneyDetails();
    final subscriptions = await db.select(db.subscriptions).get();
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
        .where((sub) => _isDueThrough(sub.nextBillingDate, subscriptionHorizon))
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
    final records = await db.select(db.moneyRecords).get();
    final details = <MoneyRecordDetail>[];
    for (final record in records) {
      details.add(await moneyDetail(record.id));
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
    return db.transaction(() async {
      final id = await db.into(db.emis).insertOnConflictUpdate(normalized);
      final saved = await emiDetail(id);
      await _logActivity(
        type: isEdit ? ActivityType.emiEdited : ActivityType.emiCreated,
        title: isEdit ? 'EMI Edited' : 'EMI Added',
        description:
            '${saved.emi.name} · ${formatMoney(saved.scheduledInstallmentPaise)} × ${saved.emi.tenureMonths}',
        entityType: 'emi',
        entityId: id,
      );
      return id;
    });
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
  }

  Future<bool> markEmiPaid(
    int emiId, {
    required DateTime expectedDueDate,
    int? expectedInstallmentNumber,
    bool paidEarly = false,
  }) async {
    return db.transaction(() async {
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
            '${emi.name} · ${formatMoney(paymentAmount)} · installment $installment',
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
    return db.transaction(() async {
      final id = await db.into(db.moneyRecords).insertOnConflictUpdate(item);
      final saved = await (db.select(
        db.moneyRecords,
      )..where((record) => record.id.equals(id))).getSingle();
      await _logActivity(
        type: isEdit
            ? ActivityType.moneyEdited
            : saved.direction == MoneyDirection.given
            ? ActivityType.moneyGiven
            : ActivityType.moneyBorrowed,
        title: isEdit
            ? 'Money Record Edited'
            : saved.direction == MoneyDirection.given
            ? 'Money Given'
            : 'Money Borrowed',
        description:
            '${displayName(saved.personName)} · ${formatMoney(saved.amountPaise)}',
        entityType: 'money',
        entityId: id,
      );
      return id;
    });
  }

  Future<void> deleteMoneyRecord(int id) async {
    final existing = await (db.select(
      db.moneyRecords,
    )..where((item) => item.id.equals(id))).getSingleOrNull();
    if (existing == null) return;
    await db.transaction(() async {
      await _logActivity(
        type: ActivityType.moneyDeleted,
        title: 'Money Record Deleted',
        description: existing.personName,
        entityType: 'money',
        entityId: id,
      );
      await (db.delete(
        db.moneyRecords,
      )..where((item) => item.id.equals(id))).go();
    });
  }

  Future<void> addRepayment(
    int moneyRecordId,
    int amountPaise,
    String? notes,
    DateTime? paidOn,
  ) async {
    if (amountPaise <= 0) {
      throw const FormatException('Enter an amount greater than zero');
    }
    await db.transaction(() async {
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
      await db
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
        title: 'Repayment Recorded',
        description:
            '${displayName(record.personName)} · ${formatMoney(amountPaise)}',
        entityType: 'money',
        entityId: moneyRecordId,
      );
    });
    await moneyDetail(moneyRecordId);
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
    return db.transaction(() async {
      final id = await db.into(db.subscriptions).insertOnConflictUpdate(item);
      final saved = await subscription(id);
      await _logActivity(
        type: isEdit
            ? ActivityType.subscriptionChanged
            : ActivityType.subscriptionCreated,
        title: isEdit ? 'Subscription Changed' : 'Subscription Added',
        description: saved == null
            ? 'Subscription'
            : '${displayName(saved.name)} · ${formatMoney(saved.amountPaise)}',
        entityType: 'subscription',
        entityId: id,
      );
      return id;
    });
  }

  Future<void> deleteSubscription(int id) async {
    await db.transaction(() async {
      final existing = await (db.select(
        db.subscriptions,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (existing == null) return;
      await _logActivity(
        type: ActivityType.subscriptionDeleted,
        title: 'Subscription Deleted',
        description:
            '${displayName(existing.name)} · ${formatMoney(existing.amountPaise)}',
        entityType: 'subscription',
        entityId: id,
      );
      await (db.delete(db.subscriptions)..where((t) => t.id.equals(id))).go();
    });
  }

  Future<void> setSubscriptionStatus(int id, SubscriptionStatus status) async {
    await db.transaction(() async {
      final existing = await subscription(id);
      if (existing == null) return;
      await (db.update(db.subscriptions)..where((t) => t.id.equals(id))).write(
        SubscriptionsCompanion(
          status: Value(status),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _logActivity(
        type: ActivityType.subscriptionChanged,
        title: 'Subscription Changed',
        description:
            '${displayName(existing.name)} · ${formatMoney(existing.amountPaise)} · ${status.label}',
        entityType: 'subscription',
        entityId: id,
      );
    });
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
      await (db.delete(
        db.settings,
      )..where((setting) => setting.key.like('$_archivedEmiPrefix%'))).go();
    });
  }

  Future<List<ReminderItem>> reminders({bool attentionOnly = true}) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final items = <ReminderItem>[];
    final archivedIds = await _archivedEmiIds();
    final emis = (await db.select(db.emis).get()).where(
      (emi) => !archivedIds.contains(emi.id),
    );
    for (final emi in emis) {
      final detail = await emiDetail(emi.id);
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

    final subscriptions = await db.select(db.subscriptions).get();
    for (final sub in subscriptions) {
      items.add(
        ReminderItem(
          title: displayName(sub.name),
          subtitle: sub.status == SubscriptionStatus.active
              ? relativeDueText(sub.nextBillingDate, today)
              : sub.status.label,
          dueAt: sub.nextBillingDate,
          status: sub.status == SubscriptionStatus.active
              ? reminderStatusFor(sub.nextBillingDate, today)
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

  String _pdfMoney(int paise) => formatMoney(paise).replaceFirst('₹', 'INR ');
}
