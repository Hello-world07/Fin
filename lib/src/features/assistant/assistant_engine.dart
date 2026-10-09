import 'package:drift/drift.dart';

import '../../core/formatters.dart' hide formatMoney;
import '../../domain/due_status.dart';
import '../../data/database.dart';
import '../../data/repositories.dart';
import '../../domain/emi_math.dart';
import '../../domain/emi_payment_rules.dart' show dateOnly;
import '../../domain/enums.dart';
import '../../domain/money_math.dart';
import '../../domain/subscription_schedule.dart';
import 'assistant_commands.dart';
import 'assistant_actions.dart';
import 'assistant_math.dart';
import 'assistant_visuals.dart';
import 'assistant_planning.dart';
import 'assistant_answer_style.dart';

String formatMoney(int paise) => formatMoneyUnmasked(paise);

abstract class AssistantEngine {
  Future<AssistantReply> ask(String question, ConversationContext ctx);
}

abstract class AssistantActionEngine {
  Future<AssistantReply> confirm(AssistantPendingMutation mutation);
  Future<AssistantReply> undo(AssistantUndoMutation mutation);
}

class ConversationContext {
  const ConversationContext({
    required this.now,
    this.previousQuestions = const [],
    this.lastEntityName,
    this.lastEntityType,
  });
  final DateTime now;
  final List<String> previousQuestions;
  final String? lastEntityName;
  final AssistantEntityType? lastEntityType;
}

enum AssistantDestination { home, emis, money, subscriptions }

enum AssistantChartKind { bar, ring }

class AssistantAction {
  const AssistantAction(this.label, this.destination, {this.formDraft});
  final String label;
  final AssistantDestination destination;
  final AssistantFormDraft? formDraft;
}

class AssistantRow {
  const AssistantRow(this.label, this.value);
  final String label;
  final String value;
}

class AssistantChart {
  const AssistantChart({
    required this.kind,
    required this.fraction,
    required this.label,
  });
  final AssistantChartKind kind;
  final double fraction;
  final String label;
}

class AssistantReply {
  const AssistantReply(
    this.text, {
    this.rows = const [],
    this.chart,
    this.actions = const [],
    this.suggestions = const [],
    this.openForm,
    this.visuals = const [],
    this.confirmation,
    this.undoMutation,
  });
  final String text;
  final List<AssistantRow> rows;
  final AssistantChart? chart;
  final List<AssistantAction> actions;
  final List<String> suggestions;
  final AssistantFormDraft? openForm;
  final List<AssistantVisualPart> visuals;
  final AssistantPendingMutation? confirmation;
  final AssistantUndoMutation? undoMutation;
}

enum AssistantIntent {
  greeting,
  thanks,
  bye,
  identity,
  help,
  analysis,
  nextEmi,
  emiPeriod,
  incoming,
  payRange,
  status,
  owe,
  owedToMe,
  whoOwesMe,
  whomIOwe,
  emi,
  due,
  outflow,
  subscriptions,
  biggestExpense,
  debtFree,
  clearDebts,
  debtFirst,
  personBalance,
  upcoming,
  unknown,
}

class IntentMatch {
  const IntentMatch(this.intent, {this.personName});
  final AssistantIntent intent;
  final String? personName;
}

String normalizeQuestion(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

int _distanceAtMostOne(String a, String b) {
  if ((a.length - b.length).abs() > 1) return 2;
  var i = 0;
  var j = 0;
  var edits = 0;
  while (i < a.length && j < b.length) {
    if (a[i] == b[j]) {
      i++;
      j++;
      continue;
    }
    edits++;
    if (edits > 1) return 2;
    if (a.length > b.length) {
      i++;
    } else if (b.length > a.length) {
      j++;
    } else {
      i++;
      j++;
    }
  }
  return edits + (a.length - i) + (b.length - j);
}

int _score(String normalized, List<String> keywords) {
  final tokens = normalized.split(' ');
  var best = 0;
  for (final keyword in keywords) {
    if (keyword.contains(' ')) {
      if (normalized.contains(keyword)) best = 3;
      continue;
    }
    if (tokens.contains(keyword)) {
      best = best < 2 ? 2 : best;
      continue;
    }
    if (keyword.length >= 4 &&
        tokens.any((token) => _distanceAtMostOne(token, keyword) == 1)) {
      if (best < 1) best = 1;
    }
  }
  return best;
}

IntentMatch matchAssistantIntent(
  String question,
  Iterable<String> personNames,
) {
  final q = normalizeQuestion(question);
  if (q.isEmpty) return const IntentMatch(AssistantIntent.unknown);
  if (RegExp(
    r'^(hi|hello|hey|namaste|good morning|good afternoon|good evening)(\b|$)',
  ).hasMatch(q)) {
    return const IntentMatch(AssistantIntent.greeting);
  }
  if (RegExp(r'^(thanks|thank you|thx)(\b|$)').hasMatch(q)) {
    return const IntentMatch(AssistantIntent.thanks);
  }
  if (RegExp(r'^(bye|goodbye|see you)(\b|$)').hasMatch(q)) {
    return const IntentMatch(AssistantIntent.bye);
  }
  if (q.contains('who are you') || q.contains('what can you do')) {
    return const IntentMatch(AssistantIntent.identity);
  }
  if (q == 'help' || q.contains('help me')) {
    return const IntentMatch(AssistantIntent.help);
  }
  if (_score(q, ['analyze', 'analyse', 'analysis', 'portfolio', 'suggestion']) >
          0 ||
      q.contains('vishleshan') ||
      q.contains('analyse chey')) {
    return const IntentMatch(AssistantIntent.analysis);
  }
  for (final name in personNames) {
    final normalizedName = normalizeQuestion(name);
    if (normalizedName.isNotEmpty && ' $q '.contains(' $normalizedName ')) {
      return IntentMatch(AssistantIntent.personBalance, personName: name);
    }
  }
  bool has(List<String> terms) => _score(q, terms) > 0;
  if (has(['emi']) &&
      has(['next', 'when', 'date', 'kab', 'eppudu']) &&
      !has(['amount', 'total'])) {
    return const IntentMatch(AssistantIntent.nextEmi);
  }
  if (has(['emi']) &&
      (has(['next month', 'this month', 'this year', 'year']) ||
          q.contains('emi amount'))) {
    return const IntentMatch(AssistantIntent.emiPeriod);
  }
  if (has([
        'come to me',
        'coming to me',
        'will receive',
        'receivable',
        'ravali',
      ]) &&
      has(['month', 'this month'])) {
    return const IntentMatch(AssistantIntent.incoming);
  }
  if (has(['need to pay', 'have to pay', 'must pay']) &&
      (has(['month', 'days', 'week']) ||
          RegExp(r'next \d+ days').hasMatch(q))) {
    return const IntentMatch(AssistantIntent.payRange);
  }
  if (has(['which debt', 'clear first', 'pay first', 'priority', 'pehle'])) {
    return const IntentMatch(AssistantIntent.debtFirst);
  }
  if (has([
    'debt free',
    'debt-free',
    'free of debt',
    'kab free',
    'debt khatam',
  ])) {
    return const IntentMatch(AssistantIntent.debtFree);
  }
  if (has([
    'clear all',
    'pay off all',
    'total debt',
    'all debts',
    'debt left',
    'saara udhar',
  ])) {
    return const IntentMatch(AssistantIntent.clearDebts);
  }
  if (has(['upcoming', 'next 5', 'next five', 'five payments'])) {
    return const IntentMatch(AssistantIntent.upcoming);
  }
  if ((has([
            'due',
            'this week',
            'this month',
            'next month',
            'today',
            'tomorrow',
            'kab',
            'eppudu',
          ]) ||
          RegExp(r'next \d{1,3} days?|by \d').hasMatch(q)) &&
      !has(['debt free'])) {
    return const IntentMatch(AssistantIntent.due);
  }
  if (has(['biggest', 'largest', 'most expensive', 'sabse zyada'])) {
    return const IntentMatch(AssistantIntent.biggestExpense);
  }
  if (has(['subscription', 'subscriptions', 'subs', 'recurring'])) {
    return const IntentMatch(AssistantIntent.subscriptions);
  }
  if (has(['emi', 'installment', 'installments', 'loan'])) {
    return const IntentMatch(AssistantIntent.emi);
  }
  if (has([
    'who owes me',
    'who owes',
    'who should pay me',
    'kisne dena',
    'kisse lena',
  ])) {
    return const IntentMatch(AssistantIntent.whoOwesMe);
  }
  if (has(['whom i owe', 'who do i owe', 'who i owe', 'kisko dena'])) {
    return const IntentMatch(AssistantIntent.whomIOwe);
  }
  if (has([
    'owed to me',
    'to receive',
    'get back',
    'kitna lena',
    'udhar diya',
    'ravali',
  ])) {
    return const IntentMatch(AssistantIntent.owedToMe);
  }
  if (has(['udhar']) && has(['diya', 'diye'])) {
    return const IntentMatch(AssistantIntent.owedToMe);
  }
  if (has(['i owe', 'to pay', 'kitna dena', 'udhar liya', 'baki udhar'])) {
    return const IntentMatch(AssistantIntent.owe);
  }
  if (has(['udhar']) && has(['baki', 'kitna', 'liya'])) {
    return const IntentMatch(AssistantIntent.owe);
  }
  if (has([
    'outflow',
    'monthly expense',
    'monthly spending',
    'per month',
    'mahina',
  ])) {
    return const IntentMatch(AssistantIntent.outflow);
  }
  if (has([
    'status',
    'net',
    'overview',
    'financial',
    'situation',
    'haal',
    'undi',
    'ela',
  ])) {
    return const IntentMatch(AssistantIntent.status);
  }
  return const IntentMatch(AssistantIntent.unknown);
}

class AssistantDateRange {
  const AssistantDateRange(this.start, this.end, this.label);
  final DateTime start;
  final DateTime end;
  final String label;
}

DateTime? _calendarDate(int year, int month, int day) {
  final date = DateTime(year, month, day);
  return date.year == year && date.month == month && date.day == day
      ? date
      : null;
}

AssistantDateRange parseAssistantDateRange(String question, DateTime now) {
  final q = normalizeQuestion(question);
  final today = dateOnly(now);
  if (q.contains('tomorrow')) {
    final date = today.add(const Duration(days: 1));
    return AssistantDateRange(date, date, 'tomorrow');
  }
  if (q.contains('today')) return AssistantDateRange(today, today, 'today');
  if (q.contains('next month')) {
    return AssistantDateRange(
      DateTime(today.year, today.month + 1),
      DateTime(today.year, today.month + 2, 0),
      'next month',
    );
  }
  if (q.contains('this month')) {
    return AssistantDateRange(
      today,
      DateTime(today.year, today.month + 1, 0),
      'this month',
    );
  }
  if (q.contains('this week')) {
    return AssistantDateRange(
      today,
      today.add(Duration(days: DateTime.sunday - today.weekday)),
      'this week',
    );
  }
  if (q.contains('next week')) {
    final start = today.add(
      Duration(days: DateTime.monday - today.weekday + 7),
    );
    return AssistantDateRange(
      start,
      start.add(const Duration(days: 6)),
      'next week',
    );
  }
  final nextDays = RegExp(r'next (\d{1,3}) days?').firstMatch(q);
  if (nextDays != null) {
    final count = int.parse(nextDays.group(1)!).clamp(1, 365);
    return AssistantDateRange(
      today,
      today.add(Duration(days: count)),
      'the next $count days',
    );
  }
  final iso = RegExp(r'by (\d{4}) (\d{1,2}) (\d{1,2})').firstMatch(q);
  if (iso != null) {
    final date = _calendarDate(
      int.parse(iso.group(1)!),
      int.parse(iso.group(2)!),
      int.parse(iso.group(3)!),
    );
    if (date != null) {
      return AssistantDateRange(today, date, 'by ${formatDate(date)}');
    }
  }
  final numeric = RegExp(r'by (\d{1,2}) (\d{1,2}) (\d{4})').firstMatch(q);
  if (numeric != null) {
    final date = _calendarDate(
      int.parse(numeric.group(3)!),
      int.parse(numeric.group(2)!),
      int.parse(numeric.group(1)!),
    );
    if (date != null) {
      return AssistantDateRange(today, date, 'by ${formatDate(date)}');
    }
  }
  final named = RegExp(r'by (\d{1,2}) ([a-z]+)(?: (\d{4}))?').firstMatch(q);
  if (named != null) {
    final day = int.parse(named.group(1)!);
    final monthText = named.group(2)!;
    final year = int.tryParse(named.group(3) ?? '') ?? today.year;
    const months = [
      'january',
      'february',
      'march',
      'april',
      'may',
      'june',
      'july',
      'august',
      'september',
      'october',
      'november',
      'december',
    ];
    final monthIndex = months.indexWhere(
      (name) => monthText.length >= 3 && name.startsWith(monthText),
    );
    if (monthIndex >= 0) {
      final date = _calendarDate(year, monthIndex + 1, day);
      if (date != null) {
        return AssistantDateRange(today, date, 'by ${formatDate(date)}');
      }
    }
  }
  return AssistantDateRange(
    today,
    today.add(const Duration(days: 7)),
    'the next 7 days',
  );
}

class AssistantDueItem {
  const AssistantDueItem(
    this.label,
    this.amountPaise,
    this.dueDate,
    this.destination,
  );
  final String label;
  final int amountPaise;
  final DateTime dueDate;
  final AssistantDestination destination;
}

class FinanceFacts {
  const FinanceFacts({
    required this.emis,
    required this.money,
    required this.subscriptions,
    required this.now,
  });
  final List<EmiDetail> emis;
  final List<MoneyRecordDetail> money;
  final List<Subscription> subscriptions;
  final DateTime now;

  Iterable<EmiDetail> get activeEmis => emis.where(
    (item) =>
        item.emi.status != EmiStatus.completed &&
        item.emi.status != EmiStatus.paused &&
        item.nextUnpaidInstallment != null,
  );
  Iterable<MoneyRecordDetail> get given => money.where(
    (item) =>
        item.record.direction == MoneyDirection.given &&
        item.summary.remainingAmountPaise > 0,
  );
  Iterable<MoneyRecordDetail> get borrowed => money.where(
    (item) =>
        item.record.direction == MoneyDirection.borrowed &&
        item.summary.remainingAmountPaise > 0,
  );
  Iterable<Subscription> get activeSubscriptions =>
      subscriptions.where((item) => item.status == SubscriptionStatus.active);

  int get toReceivePaise =>
      given.fold(0, (sum, item) => sum + item.summary.remainingAmountPaise);
  int get borrowedPaise =>
      borrowed.fold(0, (sum, item) => sum + item.summary.remainingAmountPaise);
  int get emiRemainingPaise =>
      activeEmis.fold(0, (sum, item) => sum + item.remainingBalancePaise);
  int get totalDebtPaise => borrowedPaise + emiRemainingPaise;
  int get netPositionPaise => toReceivePaise - borrowedPaise;
  int get monthlyEmiPaise => activeEmis.fold(
    0,
    (sum, item) =>
        sum +
        monthlyEquivalentPaise(
          item.scheduledInstallmentPaise,
          item.emi.frequency,
        ),
  );
  int get monthlySubscriptionsPaise => activeSubscriptions.fold(
    0,
    (sum, item) =>
        sum + monthlyEquivalentPaise(item.amountPaise, item.frequency),
  );
  int get yearlySubscriptionsPaise => activeSubscriptions.fold(
    0,
    (sum, item) =>
        sum +
        switch (item.frequency) {
          PaymentFrequency.once => 0,
          PaymentFrequency.weekly => item.amountPaise * 52,
          PaymentFrequency.monthly => item.amountPaise * 12,
          PaymentFrequency.quarterly => item.amountPaise * 4,
          PaymentFrequency.yearly => item.amountPaise,
        },
  );
  int get upcomingBorrowedPaise => borrowed
      .where((item) {
        if (item.record.status == MoneyStatus.paused) return false;
        final due = item.record.dueDate;
        return due != null &&
            !dateOnly(due).isAfter(dateOnly(now).add(const Duration(days: 30)));
      })
      .fold(0, (sum, item) => sum + item.summary.remainingAmountPaise);
  int get monthlyOutflowPaise =>
      monthlyEmiPaise + monthlySubscriptionsPaise + upcomingBorrowedPaise;

  EmiDetail? get nextEmi {
    final items = activeEmis.toList()
      ..sort(
        (a, b) => a.nextUnpaidInstallment!.dueDate.compareTo(
          b.nextUnpaidInstallment!.dueDate,
        ),
      );
    return items.firstOrNull;
  }

  int emiDueInRange(DateTime start, DateTime end) =>
      activeEmis.fold(0, (sum, emi) {
        var total = sum;
        for (final installment in emi.installments) {
          final day = dateOnly(installment.dueDate);
          if (!installment.isPaid &&
              !day.isBefore(dateOnly(start)) &&
              !day.isAfter(dateOnly(end))) {
            total += emi.amountForInstallment(installment.number);
          }
        }
        return total;
      });

  DateTime? get debtFreeDate {
    if (borrowed.any((item) => item.record.dueDate == null)) return null;
    final dates = <DateTime>[
      for (final item in activeEmis) item.installments.last.dueDate,
      for (final item in borrowed) item.record.dueDate!,
    ];
    if (dates.isEmpty) return dateOnly(now);
    dates.sort();
    return dates.last;
  }

  List<AssistantDueItem> dueItemsThrough(DateTime end) {
    final result = <AssistantDueItem>[];
    final lastDay = dateOnly(end);
    final today = dateOnly(now);
    for (final emi in activeEmis) {
      for (final installment in emi.installments) {
        if (!installment.isPaid &&
            !dateOnly(installment.dueDate).isAfter(lastDay)) {
          result.add(
            AssistantDueItem(
              emi.emi.name,
              emi.amountForInstallment(installment.number),
              installment.dueDate,
              AssistantDestination.emis,
            ),
          );
        }
      }
    }
    for (final item in borrowed) {
      if (item.record.status == MoneyStatus.paused) continue;
      final due = item.record.dueDate;
      if (due != null && !dateOnly(due).isAfter(lastDay)) {
        result.add(
          AssistantDueItem(
            item.record.personName,
            item.summary.remainingAmountPaise,
            due,
            AssistantDestination.money,
          ),
        );
      }
    }
    for (final sub in activeSubscriptions) {
      final first = nextSubscriptionBillingDate(
        sub.nextBillingDate,
        sub.frequency,
        today,
      );
      if (sub.frequency == PaymentFrequency.once) {
        if (!dateOnly(first).isAfter(lastDay)) {
          result.add(
            AssistantDueItem(
              sub.name,
              sub.amountPaise,
              first,
              AssistantDestination.subscriptions,
            ),
          );
        }
        continue;
      }
      for (var period = 1; period < 10000; period++) {
        final date = emiInstallmentDueDate(
          sub.nextBillingDate,
          period,
          sub.frequency,
        );
        if (dateOnly(date).isAfter(lastDay)) break;
        if (dateOnly(date).isBefore(dateOnly(first))) continue;
        result.add(
          AssistantDueItem(
            sub.name,
            sub.amountPaise,
            date,
            AssistantDestination.subscriptions,
          ),
        );
      }
    }
    result.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return result;
  }

  int totalDueInRange(
    DateTime start,
    DateTime end, {
    bool includeOverdue = false,
  }) => dueItemsInRange(
    start,
    end,
    includeOverdue: includeOverdue,
  ).fold(0, (sum, item) => sum + item.amountPaise);

  List<AssistantDueItem> dueItemsInRange(
    DateTime start,
    DateTime end, {
    bool includeOverdue = false,
  }) {
    final firstDay = dateOnly(start);
    final today = dateOnly(now);
    return dueItemsThrough(end).where((item) {
      final day = dateOnly(item.dueDate);
      return !day.isBefore(firstDay) || (includeOverdue && day.isBefore(today));
    }).toList();
  }
}

// Replace this provider's engine with an LLM implementation later; the UI uses only AssistantEngine.
class LocalAssistantEngine implements AssistantEngine, AssistantActionEngine {
  LocalAssistantEngine(this.repository);
  final FinanceRepository repository;
  final AssistantAnswerStyle _answerStyle = AssistantAnswerStyle();

  AssistantReply _polish(
    AssistantIntent intent,
    String question,
    FinanceFacts facts,
    AssistantReply reply,
  ) {
    final insights = <String>[];
    final next = facts.dueItemsThrough(
      dateOnly(facts.now).add(const Duration(days: 365)),
    );
    if (next.isNotEmpty) {
      insights.add(
        '${next.first.label} is due ${formatDate(next.first.dueDate)} for ${formatMoney(next.first.amountPaise)}.',
      );
    }
    final biggest = facts.activeEmis.toList()
      ..sort(
        (a, b) => b.remainingBalancePaise.compareTo(a.remainingBalancePaise),
      );
    if (biggest.isNotEmpty) {
      insights.add(
        '${biggest.first.emi.name} has ${formatMoney(biggest.first.remainingBalancePaise)} in scheduled payments left.',
      );
    }
    final owed = facts.given.toList()
      ..sort(
        (a, b) => b.summary.remainingAmountPaise.compareTo(
          a.summary.remainingAmountPaise,
        ),
      );
    if (owed.isNotEmpty) {
      insights.add(
        '${owed.first.record.personName} owes you ${formatMoney(owed.first.summary.remainingAmountPaise)}.',
      );
    }
    final renewing = facts.activeSubscriptions.toList()
      ..sort(
        (a, b) =>
            nextSubscriptionBillingDate(
              a.nextBillingDate,
              a.frequency,
              facts.now,
            ).compareTo(
              nextSubscriptionBillingDate(
                b.nextBillingDate,
                b.frequency,
                facts.now,
              ),
            ),
      );
    if (renewing.isNotEmpty) {
      final first = renewing.first;
      final date = nextSubscriptionBillingDate(
        first.nextBillingDate,
        first.frequency,
        facts.now,
      );
      insights.add(
        '${first.name} renews ${formatDate(date)} for ${formatMoney(first.amountPaise)}.',
      );
    }
    return _answerStyle.apply(
      intent,
      question,
      reply,
      facts.now,
      insights: insights,
    );
  }

  List<AssistantVisualPart> _dueVisuals(
    List<AssistantDueItem> due,
    DateTime now,
  ) {
    if (due.isEmpty) return const [];
    return [
      AssistantVisualPart(
        kind: AssistantVisualKind.timeline,
        title: 'Due timeline',
        data: [
          for (final item in due.take(12))
            AssistantVisualDatum(
              label: '${item.label} · ${formatDate(item.dueDate)}',
              value: item.amountPaise.toDouble(),
              displayValue: formatMoney(item.amountPaise),
              date: item.dueDate,
              isOverdue: dateOnly(item.dueDate).isBefore(dateOnly(now)),
            ),
        ],
      ),
      AssistantVisualPart(
        kind: AssistantVisualKind.weeklyBars,
        title: 'Due by week',
        data: buildWeeklyChartData(
          due.map(
            (item) => AssistantDatedAmount(
              item.dueDate,
              item.amountPaise,
              overdue: dateOnly(item.dueDate).isBefore(dateOnly(now)),
            ),
          ),
          now,
        ),
      ),
    ];
  }

  @override
  Future<AssistantReply> ask(String question, ConversationContext ctx) async {
    final normalized = normalizeQuestion(question);
    final emiCalculation = RegExp(
      r'emi for\s+([0-9.,]+\s*(?:k|lakh|lakhs|cr|crore|crores)?)\s+at\s+([0-9]+(?:\.[0-9]+)?)%?\s+for\s+(\d+)\s+(years?|months?)',
      caseSensitive: false,
    ).firstMatch(question);
    if (emiCalculation != null) {
      try {
        final principal = parseAssistantNumber(
          emiCalculation.group(1)!.replaceAll(' ', ''),
        );
        final rate = double.parse(emiCalculation.group(2)!);
        final count = int.parse(emiCalculation.group(3)!);
        final months =
            count *
            (emiCalculation.group(4)!.toLowerCase().startsWith('year')
                ? 12
                : 1);
        final emi = calculateAssistantEmiPaise(principal, rate, months);
        return AssistantReply(
          'Estimated monthly EMI: ${formatAssistantResult(emi / 100)}. This is an estimate; your lender may round differently.',
          rows: [
            AssistantRow('Total scheduled', formatMoney(emi * months)),
            AssistantRow(
              'Estimated interest',
              formatMoney(emi * months - (principal * 100).round()),
            ),
          ],
          actions: _amountActions(emi),
        );
      } on FormatException catch (error) {
        return AssistantReply(error.message);
      }
    }
    final interest = RegExp(
      r'simple interest\s+([0-9.,]+\s*(?:k|lakh|lakhs|cr|crore|crores)?)\s+at\s+([0-9]+(?:\.[0-9]+)?)%?\s+for\s+(\d+(?:\.[0-9]+)?)\s+years?',
      caseSensitive: false,
    ).firstMatch(question);
    if (interest != null) {
      try {
        final principal = parseAssistantNumber(
          interest.group(1)!.replaceAll(' ', ''),
        );
        final rate = double.parse(interest.group(2)!);
        final years = double.parse(interest.group(3)!);
        final result = principal * rate * years / 100;
        return AssistantReply(
          'Simple interest: ${formatAssistantResult(result)}.',
          rows: [
            AssistantRow('Principal', formatMoney((principal * 100).round())),
            AssistantRow(
              'Total with interest',
              formatMoney(((principal + result) * 100).round()),
            ),
          ],
          actions: _amountActions((result * 100).round()),
        );
      } on FormatException catch (error) {
        return AssistantReply(error.message);
      }
    }
    final expression = assistantMathExpression(question);
    if (expression != null) {
      try {
        final result = evaluateAssistantMath(expression);
        return AssistantReply(
          'Result: ${formatAssistantResult(result)}',
          actions: _amountActions((result * 100).round()),
        );
      } on FormatException catch (error) {
        return AssistantReply(
          '${error.message} Try an expression like 15% of 8000.',
        );
      }
    }

    final facts = FinanceFacts(
      emis: await repository.watchEmiDetails().first,
      money: await repository.moneyDetails(),
      subscriptions: await repository.watchSubscriptions().first,
      now: ctx.now,
    );
    final whatIf = parseWhatIf(question);
    if (whatIf != null) return _whatIfReply(whatIf, facts);
    if (normalized == 'today' || normalized == 'daily brief') {
      final today = dateOnly(ctx.now);
      final items = facts
          .dueItemsThrough(today)
          .where((item) => !dateOnly(item.dueDate).isBefore(today))
          .toList();
      final total = items.fold<int>(0, (sum, item) => sum + item.amountPaise);
      return AssistantReply(
        items.isEmpty
            ? 'Nothing due today.'
            : '${items.length} payment${items.length == 1 ? '' : 's'} due today, ${formatMoney(total)}.',
        rows: [
          for (final item in items)
            AssistantRow(item.label, formatMoney(item.amountPaise)),
        ],
        suggestions: const ["What's due this week?", 'My financial status'],
      );
    }
    final reminderReply = _prepareReminder(question, facts, ctx);
    if (reminderReply != null) return reminderReply;
    var actionCommand = parseAssistantActionCommand(question);
    if (actionCommand != null &&
        const {'it', 'that', 'that one'}.contains(actionCommand.targetText) &&
        ctx.lastEntityType != null &&
        actionCommand.kind == AssistantMutationKind.deleteSubscription) {
      actionCommand = AssistantActionCommand(
        kind: switch (ctx.lastEntityType!) {
          AssistantEntityType.emi => AssistantMutationKind.deleteEmi,
          AssistantEntityType.money => AssistantMutationKind.deleteMoney,
          AssistantEntityType.subscription =>
            AssistantMutationKind.deleteSubscription,
        },
        entityType: ctx.lastEntityType!,
        targetText: actionCommand.targetText,
      );
    }
    if (actionCommand != null) {
      return _prepareMutation(actionCommand, facts, ctx);
    }

    var command = parseAssistantCommand(question, ctx.now);
    if (command == null &&
        ctx.previousQuestions.isNotEmpty &&
        RegExp(r'^[0-9][0-9,.]*(?:k|lakh|cr)?$').hasMatch(normalized)) {
      final prior = parseAssistantCommand(ctx.previousQuestions.last, ctx.now);
      if (prior != null && prior.draft.amountPaise == null) {
        final amount = parseAssistantAmountPaise(question);
        if (amount != null) {
          command = AssistantCommand(
            prior.draft.withAmount(amount),
            ambiguousMoney: prior.ambiguousMoney,
          );
        }
      }
    }
    if (command != null) {
      final draft = command.draft;
      if (draft.amountPaise == null) {
        return const AssistantReply('What amount should I put in the form?');
      }
      if (command.ambiguousMoney) {
        final amount = formatMoney(draft.amountPaise!);
        return AssistantReply(
          'Is this money you gave or borrowed?',
          suggestions: ['I gave $amount', 'I borrowed $amount'],
        );
      }
      final destination = _destinationForDraft(draft.kind);
      final label = switch (draft.kind) {
        AssistantFormKind.emi => 'EMI',
        AssistantFormKind.moneyGiven ||
        AssistantFormKind.moneyBorrowed => 'Money',
        AssistantFormKind.subscription => 'Subscription',
      };
      return AssistantReply(
        'Opening the $label form with ${formatMoney(draft.amountPaise!)}. Check it and tap Save.',
        actions: [
          AssistantAction('Open $label form', destination, formDraft: draft),
        ],
        openForm: draft,
      );
    }

    final names = facts.money.map((item) => item.record.personName).toSet();
    var effectiveQuestion = question;
    if (ctx.previousQuestions.isNotEmpty &&
        RegExp(
          r'^(and )?(next month|this month|what about)',
        ).hasMatch(normalized)) {
      final previous = normalizeQuestion(ctx.previousQuestions.last);
      if (normalized.contains('next month') ||
          normalized.contains('this month') ||
          normalized.contains('next week')) {
        if (previous.contains('need to pay')) {
          effectiveQuestion = 'how much do I need to pay $question';
        } else if (previous.contains('emi')) {
          effectiveQuestion = 'emi amount $question';
        } else if (previous.contains('come to me')) {
          effectiveQuestion = 'how much will come to me $question';
        } else if (previous.contains('due')) {
          effectiveQuestion = 'what is due $question';
        }
      }
    }
    final match = matchAssistantIntent(effectiveQuestion, names);
    const emiAction = AssistantAction('Open EMIs', AssistantDestination.emis);
    const moneyAction = AssistantAction(
      'Open Money',
      AssistantDestination.money,
    );
    const subsAction = AssistantAction(
      'Open subscriptions',
      AssistantDestination.subscriptions,
    );
    switch (match.intent) {
      case AssistantIntent.greeting:
        return AssistantReply(
          'Welcome to FinKeep! I can help you track your EMIs, money given or borrowed and subscriptions, answer questions about your finances, do quick maths, and suggest ways to save.',
          suggestions: _dataSuggestions(facts),
        );
      case AssistantIntent.thanks:
        return const AssistantReply(
          'You’re welcome! Ask FinKeep whenever you need a quick view of your money.',
        );
      case AssistantIntent.bye:
        return const AssistantReply(
          'See you soon. FinKeep will be here when you need it.',
        );
      case AssistantIntent.identity:
        return const AssistantReply(
          'I’m Ask FinKeep, your offline finance assistant. I use only the records on this phone to answer questions, calculate and open forms for you to review.',
        );
      case AssistantIntent.help:
        return const AssistantReply(
          'Try these questions:\nStatus: My financial status\nEMIs: When is my next EMI? or Mark Slice paid\nMoney: Who owes me? or Nivas paid 50\nSubscriptions: Subscriptions per month or Pause Netflix\nMaths: 15% of 8000\nAdd something: I gave Nivas 500\nChanges always show a confirmation before anything is updated.',
          suggestions: [
            'My financial status',
            'Next EMI date',
            'Who owes me?',
            '15% of 8000',
          ],
        );
      case AssistantIntent.analysis:
        return _polish(match.intent, question, facts, _analyzePortfolio(facts));
      case AssistantIntent.nextEmi:
        final next = facts.nextEmi;
        if (next == null) {
          return const AssistantReply(
            'You have no unpaid active EMI installments.',
            actions: [emiAction],
          );
        }
        final installment = next.nextUnpaidInstallment!;
        return AssistantReply(
          '${displayName(next.emi.name)} is next on ${formatDate(installment.dueDate)} (${relativeDueText(installment.dueDate, ctx.now)}).',
          rows: [
            AssistantRow(
              'Installment',
              formatMoney(next.amountForInstallment(installment.number)),
            ),
            AssistantRow('Due date', formatDate(installment.dueDate)),
          ],
          actions: const [emiAction],
        );
      case AssistantIntent.emiPeriod:
        final q = normalizeQuestion(effectiveQuestion);
        final year = q.contains('year');
        final start = year
            ? DateTime(ctx.now.year)
            : q.contains('next month')
            ? DateTime(ctx.now.year, ctx.now.month + 1)
            : DateTime(ctx.now.year, ctx.now.month);
        final end = year
            ? DateTime(ctx.now.year + 1, 1, 0)
            : DateTime(start.year, start.month + 1, 0);
        final total = facts.emiDueInRange(start, end);
        return AssistantReply(
          '${formatMoney(total)} in unpaid EMI installments is scheduled from ${formatDate(start)} to ${formatDate(end)}.',
          rows: [
            for (final emi in facts.activeEmis)
              if (emi.installments.any(
                (item) =>
                    !item.isPaid &&
                    !dateOnly(item.dueDate).isBefore(start) &&
                    !dateOnly(item.dueDate).isAfter(end),
              ))
                AssistantRow(
                  displayName(emi.emi.name),
                  formatMoney(
                    emi.installments
                        .where(
                          (item) =>
                              !item.isPaid &&
                              !dateOnly(item.dueDate).isBefore(start) &&
                              !dateOnly(item.dueDate).isAfter(end),
                        )
                        .fold<int>(
                          0,
                          (sum, item) =>
                              sum + emi.amountForInstallment(item.number),
                        ),
                  ),
                ),
          ],
          actions: const [emiAction],
        );
      case AssistantIntent.incoming:
        final range = parseAssistantDateRange(effectiveQuestion, ctx.now);
        final start = DateTime(range.start.year, range.start.month);
        final end = DateTime(start.year, start.month + 1, 0);
        final dated = facts.given.where((item) {
          final due = item.record.dueDate;
          return due != null &&
              !dateOnly(due).isBefore(start) &&
              !dateOnly(due).isAfter(end);
        }).toList();
        final total = dated.fold<int>(
          0,
          (sum, item) => sum + item.summary.remainingAmountPaise,
        );
        final undated = facts.given
            .where((item) => item.record.dueDate == null)
            .fold<int>(
              0,
              (sum, item) => sum + item.summary.remainingAmountPaise,
            );
        return AssistantReply(
          '${formatMoney(total)} is due to come to you from ${formatDate(start)} to ${formatDate(end)}.',
          rows: [
            for (final item in dated)
              AssistantRow(
                '${displayName(item.record.personName)} · ${formatDate(item.record.dueDate!)}',
                formatMoney(item.summary.remainingAmountPaise),
              ),
            AssistantRow(
              'No due date',
              '${formatMoney(undated)} has no due date',
            ),
          ],
          actions: const [moneyAction],
        );
      case AssistantIntent.payRange:
        final range = parseAssistantDateRange(effectiveQuestion, ctx.now);
        final due = facts.dueItemsInRange(range.start, range.end);
        int subtotal(AssistantDestination destination) => due
            .where((item) => item.destination == destination)
            .fold(0, (sum, item) => sum + item.amountPaise);
        final total = due.fold<int>(0, (sum, item) => sum + item.amountPaise);
        final nextDue = due.isEmpty
            ? facts.dueItemsThrough(
                dateOnly(ctx.now).add(const Duration(days: 365)),
              )
            : const <AssistantDueItem>[];
        return _polish(
          match.intent,
          question,
          facts,
          AssistantReply(
            due.isEmpty
                ? 'Nothing is scheduled from ${formatDate(range.start)} to ${formatDate(range.end)}.${nextDue.isEmpty ? '' : ' Next: ${nextDue.first.label} on ${formatDate(nextDue.first.dueDate)} for ${formatMoney(nextDue.first.amountPaise)}.'}'
                : '${formatMoney(total)} is scheduled to be paid from ${formatDate(range.start)} to ${formatDate(range.end)}.',
            rows: [
              AssistantRow(
                'EMIs',
                formatMoney(subtotal(AssistantDestination.emis)),
              ),
              AssistantRow(
                'Subscriptions',
                formatMoney(subtotal(AssistantDestination.subscriptions)),
              ),
              AssistantRow(
                'Money borrowed',
                formatMoney(subtotal(AssistantDestination.money)),
              ),
              AssistantRow('Total', formatMoney(total)),
            ],
            visuals: _dueVisuals(due, ctx.now),
            actions: const [emiAction, moneyAction, subsAction],
          ),
        );
      case AssistantIntent.status:
        return _polish(
          match.intent,
          question,
          facts,
          AssistantReply(
            'Your Money net position is ${formatMoney(facts.netPositionPaise)}. Scheduled EMI debt is shown separately.',
            rows: [
              AssistantRow('To receive', formatMoney(facts.toReceivePaise)),
              AssistantRow(
                'I owe · Money and EMIs',
                formatMoney(facts.totalDebtPaise),
              ),
              AssistantRow(
                'EMI remaining',
                formatMoney(facts.emiRemainingPaise),
              ),
              AssistantRow(
                'Monthly recurring commitments',
                formatMoney(
                  facts.monthlyEmiPaise + facts.monthlySubscriptionsPaise,
                ),
              ),
            ],
            visuals: facts.toReceivePaise == 0 && facts.totalDebtPaise == 0
                ? const []
                : [
                    AssistantVisualPart(
                      kind: AssistantVisualKind.donut,
                      title: 'To receive vs I owe',
                      bigValue: formatMoney(facts.netPositionPaise),
                      data: [
                        AssistantVisualDatum(
                          label: 'To receive',
                          value: facts.toReceivePaise.toDouble(),
                          displayValue: formatMoney(facts.toReceivePaise),
                        ),
                        AssistantVisualDatum(
                          label: 'I owe',
                          value: facts.totalDebtPaise.toDouble(),
                          displayValue: formatMoney(facts.totalDebtPaise),
                        ),
                      ],
                    ),
                  ],
            actions: const [moneyAction, emiAction],
          ),
        );
      case AssistantIntent.owe:
      case AssistantIntent.clearDebts:
        return _polish(
          match.intent,
          question,
          facts,
          AssistantReply(
            'Tracked debt totals ${formatMoney(facts.totalDebtPaise)}. This includes scheduled EMI payments and borrowed Money balances; an early-settlement quote may differ.',
            rows: [
              AssistantRow(
                'EMI remaining',
                formatMoney(facts.emiRemainingPaise),
              ),
              AssistantRow('Money borrowed', formatMoney(facts.borrowedPaise)),
            ],
            visuals: facts.totalDebtPaise == 0
                ? const []
                : [
                    AssistantVisualPart(
                      kind: AssistantVisualKind.stackedBar,
                      title: 'Debt remaining',
                      bigValue: formatMoney(facts.totalDebtPaise),
                      data: [
                        AssistantVisualDatum(
                          label: 'EMIs',
                          value: facts.emiRemainingPaise.toDouble(),
                          displayValue: formatMoney(facts.emiRemainingPaise),
                        ),
                        AssistantVisualDatum(
                          label: 'Money borrowed',
                          value: facts.borrowedPaise.toDouble(),
                          displayValue: formatMoney(facts.borrowedPaise),
                        ),
                      ],
                    ),
                  ],
            actions: const [emiAction, moneyAction],
          ),
        );
      case AssistantIntent.owedToMe:
        final count = facts.given.length;
        return _polish(
          match.intent,
          question,
          facts,
          AssistantReply(
            'People owe you ${formatMoney(facts.toReceivePaise)} across $count open ${count == 1 ? 'record' : 'records'}.',
            visuals: count == 0
                ? const []
                : [
                    AssistantVisualPart(
                      kind: AssistantVisualKind.horizontalBars,
                      title: 'Outstanding by person',
                      data: [
                        for (final item in facts.given)
                          AssistantVisualDatum(
                            label: displayName(item.record.personName),
                            value: item.summary.remainingAmountPaise.toDouble(),
                            displayValue: formatMoney(
                              item.summary.remainingAmountPaise,
                            ),
                          ),
                      ],
                    ),
                  ],
            actions: const [moneyAction],
          ),
        );
      case AssistantIntent.whoOwesMe:
      case AssistantIntent.whomIOwe:
        final records = match.intent == AssistantIntent.whoOwesMe
            ? facts.given
            : facts.borrowed;
        final grouped = <String, int>{};
        for (final item in records) {
          grouped.update(
            item.record.personName,
            (value) => value + item.summary.remainingAmountPaise,
            ifAbsent: () => item.summary.remainingAmountPaise,
          );
        }
        final rows = grouped.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        return _polish(
          match.intent,
          question,
          facts,
          AssistantReply(
            rows.isEmpty
                ? 'No open balances are recorded.'
                : match.intent == AssistantIntent.whoOwesMe
                ? 'These people owe you:'
                : 'You owe these people:',
            rows: [
              for (final row in rows)
                AssistantRow(displayName(row.key), formatMoney(row.value)),
            ],
            visuals: rows.isEmpty
                ? const []
                : [
                    AssistantVisualPart(
                      kind: AssistantVisualKind.horizontalBars,
                      title: match.intent == AssistantIntent.whoOwesMe
                          ? 'Outstanding by person'
                          : 'Amount owed by person',
                      data: [
                        for (final row in rows)
                          AssistantVisualDatum(
                            label: displayName(row.key),
                            value: row.value.toDouble(),
                            displayValue: formatMoney(row.value),
                          ),
                      ],
                    ),
                  ],
            actions: const [moneyAction],
          ),
        );
      case AssistantIntent.emi:
        final count = facts.activeEmis.length;
        return _polish(
          match.intent,
          question,
          facts,
          AssistantReply(
            count == 0
                ? 'You have no active EMIs.'
                : '$count active ${count == 1 ? 'EMI has' : 'EMIs have'} ${formatMoney(facts.emiRemainingPaise)} left in scheduled payments.',
            rows: [
              AssistantRow(
                'Monthly equivalent',
                formatMoney(facts.monthlyEmiPaise),
              ),
              AssistantRow('Remaining', formatMoney(facts.emiRemainingPaise)),
            ],
            visuals: count == 0
                ? const []
                : [
                    AssistantVisualPart(
                      kind: AssistantVisualKind.progressRows,
                      title:
                          'EMI progress${facts.debtFreeDate == null ? '' : ' · debt-free ${formatDate(facts.debtFreeDate!)}'}',
                      data: [
                        for (final item in facts.activeEmis)
                          AssistantVisualDatum(
                            label: item.emi.name,
                            value: item.progress,
                            displayValue: '${(item.progress * 100).round()}%',
                            detail:
                                '${formatMoney(item.remainingBalancePaise)} remaining',
                          ),
                      ],
                    ),
                  ],
            actions: const [emiAction],
          ),
        );
      case AssistantIntent.due:
        final range = parseAssistantDateRange(question, ctx.now);
        if (normalizeQuestion(question).contains('by ') &&
            range.label == 'the next 7 days') {
          return const AssistantReply(
            'I could not read that date. Try a date like "by 15 Oct 2026".',
            suggestions: [
              'Due this week',
              'Due this month',
              'Next 10 days',
              'Upcoming 5 payments',
            ],
          );
        }
        final due = facts.dueItemsInRange(
          range.start,
          range.end,
          includeOverdue: true,
        );
        final total = due.fold(0, (sum, item) => sum + item.amountPaise);
        final nextDue = due.isEmpty
            ? facts.dueItemsThrough(
                dateOnly(ctx.now).add(const Duration(days: 365)),
              )
            : const <AssistantDueItem>[];
        return _polish(
          match.intent,
          question,
          facts,
          AssistantReply(
            due.isEmpty
                ? 'Nothing tracked is due ${range.label}, including overdue items.${nextDue.isEmpty ? '' : ' Next: ${nextDue.first.label} on ${formatDate(nextDue.first.dueDate)} for ${formatMoney(nextDue.first.amountPaise)}.'}'
                : '${formatMoney(total)} is due ${range.label}, including overdue items.',
            rows: [
              for (final item in due.take(12))
                AssistantRow(
                  '${item.label} · ${formatDate(item.dueDate)}',
                  formatMoney(item.amountPaise),
                ),
            ],
            visuals: _dueVisuals(due, ctx.now),
            actions: const [emiAction, moneyAction, subsAction],
          ),
        );
      case AssistantIntent.outflow:
        return _polish(
          match.intent,
          question,
          facts,
          AssistantReply(
            'Your estimated next-30-day outflow is ${formatMoney(facts.monthlyOutflowPaise)}.',
            rows: [
              AssistantRow(
                'EMIs monthly equivalent',
                formatMoney(facts.monthlyEmiPaise),
              ),
              AssistantRow(
                'Subscriptions monthly equivalent',
                formatMoney(facts.monthlySubscriptionsPaise),
              ),
              AssistantRow(
                'Dated borrowed Money due',
                formatMoney(facts.upcomingBorrowedPaise),
              ),
            ],
            visuals: facts.monthlyOutflowPaise == 0
                ? const []
                : [
                    AssistantVisualPart(
                      kind: AssistantVisualKind.stackedBar,
                      title: 'Monthly outflow split',
                      bigValue: formatMoney(facts.monthlyOutflowPaise),
                      data: [
                        AssistantVisualDatum(
                          label: 'EMIs',
                          value: facts.monthlyEmiPaise.toDouble(),
                          displayValue:
                              '${formatMoney(facts.monthlyEmiPaise)} · ${facts.monthlyOutflowPaise == 0 ? 0 : (facts.monthlyEmiPaise / facts.monthlyOutflowPaise * 100).round()}%',
                        ),
                        AssistantVisualDatum(
                          label: 'Subscriptions',
                          value: facts.monthlySubscriptionsPaise.toDouble(),
                          displayValue:
                              '${formatMoney(facts.monthlySubscriptionsPaise)} · ${facts.monthlyOutflowPaise == 0 ? 0 : (facts.monthlySubscriptionsPaise / facts.monthlyOutflowPaise * 100).round()}%',
                        ),
                        AssistantVisualDatum(
                          label: 'Money due',
                          value: facts.upcomingBorrowedPaise.toDouble(),
                          displayValue:
                              '${formatMoney(facts.upcomingBorrowedPaise)} · ${facts.monthlyOutflowPaise == 0 ? 0 : (facts.upcomingBorrowedPaise / facts.monthlyOutflowPaise * 100).round()}%',
                        ),
                      ],
                    ),
                  ],
            actions: const [emiAction, subsAction],
          ),
        );
      case AssistantIntent.subscriptions:
        final categories = <String, int>{};
        for (final item in facts.activeSubscriptions) {
          categories.update(
            item.category?.trim().isNotEmpty == true
                ? item.category!.trim()
                : 'Other',
            (value) =>
                value +
                monthlyEquivalentPaise(item.amountPaise, item.frequency),
            ifAbsent: () =>
                monthlyEquivalentPaise(item.amountPaise, item.frequency),
          );
        }
        return _polish(
          match.intent,
          question,
          facts,
          AssistantReply(
            '${facts.activeSubscriptions.length} active ${facts.activeSubscriptions.length == 1 ? 'subscription costs' : 'subscriptions cost'} about ${formatMoney(facts.monthlySubscriptionsPaise)} per month.',
            rows: [
              AssistantRow(
                'Yearly equivalent',
                formatMoney(facts.yearlySubscriptionsPaise),
              ),
            ],
            visuals: categories.isEmpty
                ? const []
                : [
                    AssistantVisualPart(
                      kind: AssistantVisualKind.horizontalBars,
                      title: 'Subscriptions by category',
                      data: [
                        for (final entry in categories.entries)
                          AssistantVisualDatum(
                            label: entry.key,
                            value: entry.value.toDouble(),
                            displayValue: formatMoney(entry.value),
                          ),
                      ],
                    ),
                  ],
            actions: const [subsAction],
          ),
        );
      case AssistantIntent.biggestExpense:
        final candidates = facts.dueItemsInRange(
          dateOnly(ctx.now),
          dateOnly(ctx.now).add(const Duration(days: 365)),
          includeOverdue: true,
        )..sort((a, b) => b.amountPaise.compareTo(a.amountPaise));
        return AssistantReply(
          candidates.isEmpty
              ? 'No upcoming outgoing payments are tracked. FinKeep does not track general spending here.'
              : '${candidates.first.label} is your largest tracked payment at ${formatMoney(candidates.first.amountPaise)} on ${formatDate(candidates.first.dueDate)}. FinKeep does not track general spending here.',
          actions: candidates.isEmpty
              ? const []
              : [
                  AssistantAction(
                    candidates.first.destination == AssistantDestination.emis
                        ? 'Open EMIs'
                        : candidates.first.destination ==
                              AssistantDestination.money
                        ? 'Open Money'
                        : 'Open subscriptions',
                    candidates.first.destination,
                  ),
                ],
        );
      case AssistantIntent.debtFree:
        final date = facts.debtFreeDate;
        final totalScheduled = facts.activeEmis.fold<int>(
          0,
          (sum, item) => sum + item.totalRepaymentPaise,
        );
        final paid = facts.activeEmis.fold<int>(
          0,
          (sum, item) => sum + item.paidPaise,
        );
        final months = date == null
            ? null
            : (dateOnly(date).difference(dateOnly(ctx.now)).inDays / 30).ceil();
        return AssistantReply(
          date == null
              ? 'I cannot give a reliable debt-free date because at least one borrowed Money record has no due date.'
              : facts.totalDebtPaise == 0
              ? 'No open EMI or borrowed Money debt is tracked.'
              : 'Your last tracked debt due date is ${formatDate(date)}. This uses EMI schedules and dated borrowed Money; subscriptions are not included.',
          visuals: [
            AssistantVisualPart(
              kind: AssistantVisualKind.scoreRing,
              title: 'Debt payoff progress',
              score: totalScheduled == 0 ? 0 : paid / totalScheduled * 100,
              bigValue: totalScheduled == 0
                  ? '0%'
                  : '${(paid / totalScheduled * 100).round()}%',
              subtitle: months == null
                  ? 'Debt-free date unknown'
                  : months <= 0
                  ? 'Due now'
                  : '$months ${months == 1 ? 'month' : 'months'} to the last tracked due date',
              data: [
                AssistantVisualDatum(
                  label: 'Paid',
                  value: paid.toDouble(),
                  displayValue: formatMoney(paid),
                ),
                AssistantVisualDatum(
                  label: 'Remaining',
                  value: facts.emiRemainingPaise.toDouble(),
                  displayValue: formatMoney(facts.emiRemainingPaise),
                ),
              ],
            ),
          ],
          actions: const [emiAction, moneyAction],
        );
      case AssistantIntent.debtFirst:
        final rated =
            facts.activeEmis
                .where((item) => (item.emi.interestRate ?? 0) > 0)
                .toList()
              ..sort(
                (a, b) => b.emi.interestRate!.compareTo(a.emi.interestRate!),
              );
        if (rated.isNotEmpty) {
          final first = rated.first;
          return AssistantReply(
            '${first.emi.name} ranks first by the highest recorded interest rate (${first.emi.interestRate}% p.a.). Debts without rates cannot be compared by interest.',
            rows: [
              AssistantRow(
                'Scheduled balance',
                formatMoney(first.remainingBalancePaise),
              ),
            ],
            actions: const [emiAction],
          );
        }
        final balances = <(String, int, AssistantDestination)>[
          for (final item in facts.activeEmis)
            (
              item.emi.name,
              item.remainingBalancePaise,
              AssistantDestination.emis,
            ),
          for (final item in facts.borrowed)
            (
              item.record.personName,
              item.summary.remainingAmountPaise,
              AssistantDestination.money,
            ),
        ]..sort((a, b) => a.$2.compareTo(b.$2));
        return AssistantReply(
          balances.isEmpty
              ? 'No open debts are tracked.'
              : '${balances.first.$1} ranks first by smallest balance (${formatMoney(balances.first.$2)}). No positive interest rate is recorded, so I used the smallest-balance rule.',
          actions: balances.isEmpty
              ? const []
              : [
                  AssistantAction(
                    balances.first.$3 == AssistantDestination.emis
                        ? 'Open EMIs'
                        : 'Open Money',
                    balances.first.$3,
                  ),
                ],
        );
      case AssistantIntent.personBalance:
        final person = match.personName!;
        final records = facts.money.where(
          (item) =>
              normalizeQuestion(item.record.personName) ==
              normalizeQuestion(person),
        );
        final owed = records
            .where((item) => item.record.direction == MoneyDirection.given)
            .fold<int>(
              0,
              (sum, item) => sum + item.summary.remainingAmountPaise,
            );
        final owe = records
            .where((item) => item.record.direction == MoneyDirection.borrowed)
            .fold<int>(
              0,
              (sum, item) => sum + item.summary.remainingAmountPaise,
            );
        final asked = normalizeQuestion(question);
        final prior = ctx.previousQuestions.isEmpty
            ? ''
            : normalizeQuestion(ctx.previousQuestions.last);
        final incomingOnly =
            asked.contains('owe me') ||
            (asked.contains('what about') && prior.contains('owe me'));
        final outgoingOnly =
            asked.contains('i owe') ||
            (asked.contains('what about') && prior.contains('i owe'));
        return AssistantReply(
          incomingOnly
              ? '${displayName(person)} owes you ${formatMoney(owed)}.'
              : outgoingOnly
              ? 'You owe ${displayName(person)} ${formatMoney(owe)}.'
              : 'With ${displayName(person)}, the net Money balance is ${formatMoney(owed - owe)}.',
          rows: [
            AssistantRow('They owe you', formatMoney(owed)),
            AssistantRow('You owe them', formatMoney(owe)),
          ],
          actions: const [moneyAction],
        );
      case AssistantIntent.upcoming:
        final due = facts.dueItemsThrough(
          dateOnly(ctx.now).add(const Duration(days: 365)),
        );
        return AssistantReply(
          due.isEmpty
              ? 'No upcoming or overdue payments are tracked.'
              : 'Here are the next ${due.length < 5 ? due.length : 5} tracked payments, overdue first.',
          rows: [
            for (final item in due.take(5))
              AssistantRow(
                '${item.label} · ${formatDate(item.dueDate)}',
                formatMoney(item.amountPaise),
              ),
          ],
          actions: const [emiAction, moneyAction, subsAction],
        );
      case AssistantIntent.unknown:
        return AssistantReply(
          'I may have misunderstood that request. Did you mean one of these?',
          suggestions: _closestSuggestions(question, facts),
        );
    }
  }

  AssistantReply _prepareMutation(
    AssistantActionCommand command,
    FinanceFacts facts,
    ConversationContext context,
  ) {
    final requestedTarget = switch (command.targetText) {
      'it' || 'that' || 'that one' => context.lastEntityName,
      final value => value,
    };
    switch (command.entityType) {
      case AssistantEntityType.subscription:
        final subscriptionPool = switch (command.kind) {
          AssistantMutationKind.cancelSubscription ||
          AssistantMutationKind.pauseSubscription => facts.subscriptions.where(
            (item) => item.status == SubscriptionStatus.active,
          ),
          AssistantMutationKind.resumeSubscription => facts.subscriptions.where(
            (item) => item.status == SubscriptionStatus.paused,
          ),
          _ => facts.subscriptions,
        };
        final resolution = resolveAssistantEntity<Subscription>(
          requestedTarget,
          subscriptionPool.map(
            (item) => AssistantEntityCandidate(item.name, item),
          ),
        );
        if (resolution.match == null) {
          return _resolutionReply(command, resolution);
        }
        final item = resolution.match!.value;
        if (command.kind == AssistantMutationKind.changeSubscriptionAmount &&
            command.amountPaise == null) {
          return AssistantReply(
            'What should ${displayName(item.name)} cost?',
            suggestions: ['Change ${item.name} to 600'],
          );
        }
        final yearly = switch (item.frequency) {
          PaymentFrequency.weekly => item.amountPaise * 52,
          PaymentFrequency.monthly => item.amountPaise * 12,
          PaymentFrequency.quarterly => item.amountPaise * 4,
          PaymentFrequency.yearly => item.amountPaise,
          PaymentFrequency.once => item.amountPaise,
        };
        final title = switch (command.kind) {
          AssistantMutationKind.cancelSubscription =>
            'Cancel ${displayName(item.name)}',
          AssistantMutationKind.pauseSubscription =>
            'Pause ${displayName(item.name)}${command.pauseMonths == null ? '' : ' for ${command.pauseMonths} months'}',
          AssistantMutationKind.resumeSubscription =>
            'Resume ${displayName(item.name)}',
          AssistantMutationKind.deleteSubscription =>
            'Move ${displayName(item.name)} to Deleted',
          AssistantMutationKind.changeSubscriptionAmount =>
            'Change ${displayName(item.name)} to ${formatMoney(command.amountPaise!)}',
          _ => 'Update ${displayName(item.name)}',
        };
        final effect = switch (command.kind) {
          AssistantMutationKind.cancelSubscription =>
            'Reminders will stop. This removes about ${formatMoney(yearly)} from the yearly recurring total.',
          AssistantMutationKind.pauseSubscription
              when command.pauseMonths != null =>
            'The next billing date will move forward ${command.pauseMonths} months; reminders resume from that date.',
          AssistantMutationKind.pauseSubscription =>
            'Reminders and recurring totals will pause until you resume it.',
          AssistantMutationKind.resumeSubscription =>
            'It will return to active recurring totals and reminders.',
          AssistantMutationKind.deleteSubscription =>
            'The record will leave active views and can be restored from Deleted.',
          AssistantMutationKind.changeSubscriptionAmount =>
            'The recurring amount changes from ${formatMoney(item.amountPaise)} to ${formatMoney(command.amountPaise!)}.',
          _ => '',
        };
        return AssistantReply(
          'Please confirm this change.',
          confirmation: AssistantPendingMutation(
            id: '${command.kind.name}:subscription:${item.id}:${context.now.microsecondsSinceEpoch}',
            kind: command.kind,
            entityType: AssistantEntityType.subscription,
            entityId: item.id,
            entityName: item.name,
            confirmationTitle: title,
            confirmationEffect: effect,
            amountPaise: command.amountPaise,
            oldAmountPaise: item.amountPaise,
            pauseMonths: command.pauseMonths,
          ),
        );
      case AssistantEntityType.emi:
        final emiPool = command.kind == AssistantMutationKind.deleteEmi
            ? facts.emis
            : facts.activeEmis;
        final resolution = resolveAssistantEntity<EmiDetail>(
          requestedTarget,
          emiPool.map((item) => AssistantEntityCandidate(item.emi.name, item)),
        );
        if (resolution.match == null) {
          return _resolutionReply(command, resolution);
        }
        final detail = resolution.match!.value;
        final next = detail.nextUnpaidInstallment;
        if ((command.kind == AssistantMutationKind.markEmiPaid ||
                command.kind == AssistantMutationKind.closeEmi) &&
            next == null) {
          return AssistantReply(
            '${displayName(detail.emi.name)} is already completed.',
          );
        }
        if (command.installmentMonth != null &&
            next!.dueDate.month != command.installmentMonth) {
          return AssistantReply(
            'The next unpaid installment for ${displayName(detail.emi.name)} is due ${formatDate(next.dueDate)}. Only the earliest unpaid installment can be marked paid.',
          );
        }
        final title = switch (command.kind) {
          AssistantMutationKind.deleteEmi =>
            'Move ${displayName(detail.emi.name)} to Deleted',
          AssistantMutationKind.closeEmi =>
            'Close ${displayName(detail.emi.name)} EMI',
          _ =>
            'Mark ${displayName(detail.emi.name)} installment ${next!.number} paid${command.paidEarly ? ' early' : ''}',
        };
        final effect = switch (command.kind) {
          AssistantMutationKind.deleteEmi =>
            'The EMI and its installment history will leave active views and can be restored from Deleted.',
          AssistantMutationKind.closeEmi =>
            'All ${detail.remainingInstallments} remaining installments totaling ${formatMoney(detail.remainingBalancePaise)} will be recorded as paid early.',
          _ =>
            '${formatMoney(detail.amountForInstallment(next!.number))} due ${formatDate(next.dueDate)} will be recorded as paid.',
        };
        return AssistantReply(
          'Please confirm this change.',
          confirmation: AssistantPendingMutation(
            id: '${command.kind.name}:emi:${detail.emi.id}:${context.now.microsecondsSinceEpoch}',
            kind: command.kind,
            entityType: AssistantEntityType.emi,
            entityId: detail.emi.id,
            entityName: detail.emi.name,
            confirmationTitle: title,
            confirmationEffect: effect,
            amountPaise: next == null
                ? detail.remainingBalancePaise
                : detail.amountForInstallment(next.number),
            expectedDueDate: next?.dueDate,
            expectedInstallmentNumber: next?.number,
            paidEarly: command.paidEarly,
          ),
        );
      case AssistantEntityType.money:
        final moneyPool = command.kind == AssistantMutationKind.deleteMoney
            ? facts.money
            : facts.money.where(
                (item) => item.summary.remainingAmountPaise > 0,
              );
        final resolution = resolveAssistantEntity<MoneyRecordDetail>(
          requestedTarget,
          moneyPool.map(
            (item) => AssistantEntityCandidate(
              '${item.record.personName} ${item.record.direction == MoneyDirection.given ? 'given' : 'borrowed'}',
              item,
            ),
          ),
        );
        if (resolution.match == null) {
          return _resolutionReply(command, resolution);
        }
        final detail = resolution.match!.value;
        final remaining = detail.summary.remainingAmountPaise;
        if (command.kind == AssistantMutationKind.addMoneyRepayment &&
            command.amountPaise == null) {
          return AssistantReply(
            'How much did ${displayName(detail.record.personName)} repay?',
          );
        }
        if (command.amountPaise != null && command.amountPaise! > remaining) {
          return AssistantReply(
            '${formatMoney(command.amountPaise!)} is more than the remaining ${formatMoney(remaining)} for ${displayName(detail.record.personName)}.',
          );
        }
        if (command.kind == AssistantMutationKind.extendMoneyDueDate &&
            command.extendDays == null) {
          return AssistantReply(
            'How many days should I extend ${displayName(detail.record.personName)}’s due date?',
            suggestions: [
              'Extend ${detail.record.personName} due date by 7 days',
              'Extend ${detail.record.personName} due date by 30 days',
            ],
          );
        }
        final repayment = command.kind == AssistantMutationKind.settleMoney
            ? remaining
            : command.amountPaise;
        final title = switch (command.kind) {
          AssistantMutationKind.deleteMoney =>
            'Move ${displayName(detail.record.personName)}’s record to Deleted',
          AssistantMutationKind.extendMoneyDueDate =>
            'Extend ${displayName(detail.record.personName)}’s due date by ${command.extendDays} days',
          AssistantMutationKind.settleMoney =>
            'Mark ${displayName(detail.record.personName)} settled',
          _ =>
            'Record ${formatMoney(repayment!)} from ${displayName(detail.record.personName)}',
        };
        final effect = switch (command.kind) {
          AssistantMutationKind.deleteMoney =>
            'The record and repayment history will leave active views and can be restored from Deleted.',
          AssistantMutationKind.extendMoneyDueDate =>
            'The due date will move from ${detail.record.dueDate == null ? 'not set' : formatDate(detail.record.dueDate!)} to ${formatDate((detail.record.dueDate ?? context.now).add(Duration(days: command.extendDays!)))}.',
          AssistantMutationKind.settleMoney =>
            '${formatMoney(remaining)} will be recorded as the final repayment.',
          _ =>
            'The outstanding balance will become ${formatMoney(remaining - repayment!)}.',
        };
        return AssistantReply(
          'Please confirm this change.',
          confirmation: AssistantPendingMutation(
            id: '${command.kind.name}:money:${detail.record.id}:${context.now.microsecondsSinceEpoch}',
            kind: command.kind,
            entityType: AssistantEntityType.money,
            entityId: detail.record.id,
            entityName: detail.record.personName,
            confirmationTitle: title,
            confirmationEffect: effect,
            amountPaise: repayment,
            extendDays: command.extendDays,
            expectedDueDate: detail.record.dueDate,
          ),
        );
    }
  }

  AssistantReply _resolutionReply<T>(
    AssistantActionCommand command,
    AssistantEntityResolution<T> resolution,
  ) {
    final verb = _mutationVerb(command.kind);
    if (resolution.ambiguous.isNotEmpty) {
      return AssistantReply(
        'Which one should I $verb?',
        suggestions: [
          for (final item in resolution.ambiguous.take(6))
            _commandSuggestion(command, item.name),
        ],
      );
    }
    return AssistantReply(
      'I could not find that ${command.entityType.name}.',
      suggestions: [
        for (final item in resolution.suggestions)
          _commandSuggestion(command, item.name),
      ],
    );
  }

  AssistantReply _whatIfReply(WhatIfRequest request, FinanceFacts facts) {
    if (request.kind == WhatIfKind.pauseSubscription) {
      final resolution = resolveAssistantEntity<Subscription>(
        request.target,
        facts.activeSubscriptions.map(
          (item) => AssistantEntityCandidate(item.name, item),
        ),
      );
      if (resolution.match == null) {
        final choices = resolution.ambiguous.isNotEmpty
            ? resolution.ambiguous
            : resolution.suggestions;
        return AssistantReply(
          choices.isEmpty
              ? 'No active subscription matches that name.'
              : 'Which subscription did you mean?',
          suggestions: [
            for (final item in choices.take(6))
              'What if I pause ${item.name} for ${request.months} months',
          ],
        );
      }
      final sub = resolution.match!.value;
      final monthly = monthlyEquivalentPaise(sub.amountPaise, sub.frequency);
      final saved = monthly * request.months!;
      final resume = subscriptionPauseEnd(
        sub.nextBillingDate,
        sub.frequency,
        facts.now,
        request.months!,
      );
      return AssistantReply(
        'If ${sub.name} is paused for ${request.months} months, estimated spending falls by ${formatMoney(saved)}. This is a preview; nothing has changed.',
        rows: [
          AssistantRow('Resume around', formatDate(resume)),
          AssistantRow(
            'Monthly outflow during pause',
            '${formatMoney(facts.monthlyOutflowPaise)} to ${formatMoney((facts.monthlyOutflowPaise - monthly).clamp(0, facts.monthlyOutflowPaise))}',
          ),
        ],
        visuals: [
          AssistantVisualPart(
            kind: AssistantVisualKind.horizontalBars,
            title: 'Monthly outflow',
            data: [
              AssistantVisualDatum(
                label: 'Before',
                value: facts.monthlyOutflowPaise.toDouble(),
                displayValue: formatMoney(facts.monthlyOutflowPaise),
              ),
              AssistantVisualDatum(
                label: 'During pause',
                value: (facts.monthlyOutflowPaise - monthly)
                    .clamp(0, facts.monthlyOutflowPaise)
                    .toDouble(),
                displayValue: formatMoney(
                  (facts.monthlyOutflowPaise - monthly).clamp(
                    0,
                    facts.monthlyOutflowPaise,
                  ),
                ),
              ),
            ],
          ),
        ],
        suggestions: [
          'Pause ${sub.name} for ${request.months} months',
          'Subscriptions per month',
        ],
      );
    }
    final resolution = resolveAssistantEntity<EmiDetail>(
      request.target,
      facts.activeEmis.map(
        (item) => AssistantEntityCandidate(item.emi.name, item),
      ),
    );
    if (resolution.match == null) {
      final choices = resolution.ambiguous.isNotEmpty
          ? resolution.ambiguous
          : resolution.suggestions;
      return AssistantReply(
        choices.isEmpty
            ? 'No active EMI matches that name.'
            : 'Which EMI did you mean?',
        suggestions: [
          for (final item in choices.take(6))
            request.kind == WhatIfKind.closeEmi
                ? 'What if I close ${item.name} now'
                : 'What if I pay ${request.amountPaise! ~/ 100} extra on ${item.name}',
        ],
      );
    }
    final emi = resolution.match!.value;
    final dates = [
      for (final item in emi.installments)
        if (!item.isPaid) item.dueDate,
    ];
    final extra = request.kind == WhatIfKind.closeEmi
        ? emi.remainingBalancePaise
        : request.amountPaise!;
    final result = calculateEmiWhatIf(
      remainingPaise: emi.remainingBalancePaise,
      installmentPaise: emi.scheduledInstallmentPaise,
      unpaidDueDates: dates,
      extraPaise: extra,
      annualRate: emi.emi.interestRate,
      today: facts.now,
    );
    final before = dates.last;
    final after = result.newDebtFreeDate;
    final monthly = monthlyEquivalentPaise(
      emi.scheduledInstallmentPaise,
      emi.emi.frequency,
    );
    return AssistantReply(
      'If you ${request.kind == WhatIfKind.closeEmi ? 'close' : 'pay ${formatMoney(extra)} extra on'} ${emi.emi.name}, its estimated final date moves from ${formatDate(before)} to ${formatDate(after)}. This is a preview; nothing has changed.',
      rows: [
        AssistantRow('Installments saved', '${result.monthsSaved}'),
        AssistantRow(
          'Interest saved',
          result.interestSavedPaise == null
              ? 'No rate stored; cannot estimate'
              : formatMoney(result.interestSavedPaise!),
        ),
        AssistantRow(
          'Monthly outflow now',
          formatMoney(facts.monthlyOutflowPaise),
        ),
        AssistantRow(
          'After closure',
          formatMoney(
            (facts.monthlyOutflowPaise - monthly).clamp(
              0,
              facts.monthlyOutflowPaise,
            ),
          ),
        ),
      ],
      visuals: [
        AssistantVisualPart(
          kind: AssistantVisualKind.horizontalBars,
          title: 'Time to EMI-free',
          data: [
            AssistantVisualDatum(
              label: 'Before',
              value: dates.length.toDouble(),
              displayValue: '${dates.length} periods',
            ),
            AssistantVisualDatum(
              label: 'After',
              value: (dates.length - result.monthsSaved).toDouble(),
              displayValue: '${dates.length - result.monthsSaved} periods',
            ),
          ],
        ),
      ],
      suggestions: ['When is my next EMI?', 'Total debt left'],
    );
  }

  AssistantReply? _prepareReminder(
    String question,
    FinanceFacts facts,
    ConversationContext ctx,
  ) {
    final q = question.toLowerCase().trim();
    if (!q.startsWith('remind me ')) return null;
    final renewal = RegExp(
      r'^remind me \d+ days? before (.+?) renews$',
    ).firstMatch(q);
    if (renewal != null) {
      final target = renewal.group(1)!;
      final matches = facts.activeSubscriptions
          .where(
            (item) =>
                normalizeQuestion(item.name).contains(target) ||
                target.contains(normalizeQuestion(item.name)),
          )
          .toList();
      if (matches.length != 1) {
        return AssistantReply(
          matches.isEmpty
              ? 'I could not find that active subscription.'
              : 'Which subscription?',
          suggestions: [
            for (final item in matches.take(3))
              'Remind me 2 days before ${item.name} renews',
          ],
        );
      }
      final sub = matches.single;
      final due = nextSubscriptionBillingDate(
        sub.nextBillingDate,
        sub.frequency,
        ctx.now,
      );
      final parsed = parseChatReminder(question, ctx.now, renewalDate: due);
      if (parsed == null) {
        return const AssistantReply(
          'That reminder time has passed. Try the next renewal.',
        );
      }
      return AssistantReply(
        'Please confirm this reminder.',
        confirmation: AssistantPendingMutation(
          id: 'reminder:${ctx.now.microsecondsSinceEpoch}',
          kind: AssistantMutationKind.scheduleReminder,
          entityType: AssistantEntityType.subscription,
          entityId: sub.id,
          entityName: sub.name,
          confirmationTitle: 'Remind you about ${sub.name}',
          confirmationEffect:
              'A local notification on ${formatDate(parsed.when)} at 9:00 AM.',
          reminderAt: parsed.when,
        ),
      );
    }
    final parsed = parseChatReminder(question, ctx.now);
    if (parsed == null) {
      return const AssistantReply('Try: Remind me to pay Nivas on Friday.');
    }
    final matches = facts.money
        .where(
          (item) =>
              normalizeQuestion(
                item.record.personName,
              ).contains(parsed.target) ||
              parsed.target.contains(normalizeQuestion(item.record.personName)),
        )
        .toList();
    if (matches.length != 1) {
      return AssistantReply(
        matches.isEmpty
            ? 'I could not find that money record.'
            : 'Which record?',
        suggestions: [
          for (final item in matches.take(3))
            'Remind me to pay ${item.record.personName} on Friday',
        ],
      );
    }
    final item = matches.single;
    return AssistantReply(
      'Please confirm this reminder.',
      confirmation: AssistantPendingMutation(
        id: 'reminder:${ctx.now.microsecondsSinceEpoch}',
        kind: AssistantMutationKind.scheduleReminder,
        entityType: AssistantEntityType.money,
        entityId: item.record.id,
        entityName: item.record.personName,
        confirmationTitle: 'Remind you about ${item.record.personName}',
        confirmationEffect:
            'A local notification on ${formatDate(parsed.when)} at 9:00 AM.',
        reminderAt: parsed.when,
      ),
    );
  }

  @override
  Future<AssistantReply> confirm(AssistantPendingMutation mutation) async {
    switch (mutation.kind) {
      case AssistantMutationKind.scheduleReminder:
        final reminderId = DateTime.now().microsecondsSinceEpoch.remainder(
          2000000000,
        );
        await repository.scheduleAssistantReminder(
          id: reminderId,
          title: 'FinKeep reminder',
          body: mutation.entityType == AssistantEntityType.subscription
              ? '${mutation.entityName} renews soon.'
              : 'Follow up about ${mutation.entityName}.',
          when: mutation.reminderAt!,
        );
        return _successReply(
          'Reminder set for ${formatDate(mutation.reminderAt!)}.',
          AssistantUndoMutation(
            kind: mutation.kind,
            entityType: mutation.entityType,
            entityId: mutation.entityId,
            entityName: mutation.entityName,
            relatedId: reminderId,
            expiresAt: DateTime.now().add(const Duration(seconds: 6)),
          ),
        );
      case AssistantMutationKind.cancelSubscription:
      case AssistantMutationKind.pauseSubscription:
      case AssistantMutationKind.resumeSubscription:
      case AssistantMutationKind.changeSubscriptionAmount:
        final item = await repository.subscription(mutation.entityId);
        if (item == null) {
          return const AssistantReply('That subscription no longer exists.');
        }
        if (mutation.kind == AssistantMutationKind.pauseSubscription &&
            mutation.pauseMonths != null) {
          final next = DateTime(
            item.nextBillingDate.year,
            item.nextBillingDate.month + mutation.pauseMonths!,
            item.nextBillingDate.day,
          );
          await repository.saveSubscription(
            SubscriptionsCompanion(
              id: Value(item.id),
              name: Value(item.name),
              amountPaise: Value(item.amountPaise),
              frequency: Value(item.frequency),
              nextBillingDate: Value(next),
              paymentMethodId: Value(item.paymentMethodId),
              category: Value(item.category),
              status: const Value(SubscriptionStatus.active),
              notes: Value(item.notes),
              updatedAt: Value(DateTime.now()),
            ),
          );
          return _successReply(
            '${displayName(item.name)} is paused until ${formatDate(next)}.',
            AssistantUndoMutation(
              kind: mutation.kind,
              entityType: mutation.entityType,
              entityId: item.id,
              entityName: item.name,
              date: item.nextBillingDate,
              expiresAt: DateTime.now().add(const Duration(seconds: 6)),
            ),
          );
        }
        if (mutation.kind == AssistantMutationKind.changeSubscriptionAmount) {
          await repository.saveSubscription(
            SubscriptionsCompanion(
              id: Value(item.id),
              name: Value(item.name),
              amountPaise: Value(mutation.amountPaise!),
              frequency: Value(item.frequency),
              nextBillingDate: Value(item.nextBillingDate),
              paymentMethodId: Value(item.paymentMethodId),
              category: Value(item.category),
              status: Value(item.status),
              notes: Value(item.notes),
              updatedAt: Value(DateTime.now()),
            ),
          );
          return _successReply(
            '${displayName(item.name)} now costs ${formatMoney(mutation.amountPaise!)}.',
            AssistantUndoMutation(
              kind: mutation.kind,
              entityType: mutation.entityType,
              entityId: item.id,
              entityName: item.name,
              value: item.amountPaise,
              expiresAt: DateTime.now().add(const Duration(seconds: 6)),
            ),
          );
        }
        final status = switch (mutation.kind) {
          AssistantMutationKind.cancelSubscription =>
            SubscriptionStatus.cancelled,
          AssistantMutationKind.pauseSubscription => SubscriptionStatus.paused,
          _ => SubscriptionStatus.active,
        };
        await repository.setSubscriptionStatus(item.id, status);
        return _successReply(
          '${displayName(item.name)} ${status.label.toLowerCase()}.',
          AssistantUndoMutation(
            kind: mutation.kind,
            entityType: mutation.entityType,
            entityId: item.id,
            entityName: item.name,
            value: item.status,
            expiresAt: DateTime.now().add(const Duration(seconds: 6)),
          ),
        );
      case AssistantMutationKind.deleteSubscription:
        await repository.deleteSubscription(mutation.entityId);
        return _restoreReply(mutation, 'Subscription moved to Deleted.');
      case AssistantMutationKind.deleteEmi:
        await repository.deleteEmi(mutation.entityId);
        return _restoreReply(mutation, 'EMI moved to Deleted.');
      case AssistantMutationKind.markEmiPaid:
        final before = await repository.emiDetail(mutation.entityId);
        final ok = await repository.markEmiPaid(
          mutation.entityId,
          expectedDueDate: mutation.expectedDueDate!,
          expectedInstallmentNumber: mutation.expectedInstallmentNumber,
          paidEarly: mutation.paidEarly,
        );
        if (!ok) {
          return const AssistantReply(
            'That installment changed before it could be marked paid.',
          );
        }
        final after = await repository.emiDetail(mutation.entityId);
        final priorIds = before.payments.map((item) => item.id).toSet();
        final payment = after.payments
            .where((item) => !priorIds.contains(item.id))
            .firstOrNull;
        return _successReply(
          '${displayName(mutation.entityName)} installment marked paid.',
          AssistantUndoMutation(
            kind: mutation.kind,
            entityType: mutation.entityType,
            entityId: mutation.entityId,
            entityName: mutation.entityName,
            relatedId: payment?.id,
            expiresAt: DateTime.now().add(const Duration(seconds: 6)),
          ),
        );
      case AssistantMutationKind.closeEmi:
        final before = await repository.emiDetail(mutation.entityId);
        while (true) {
          final detail = await repository.emiDetail(mutation.entityId);
          final next = detail.nextUnpaidInstallment;
          if (next == null) break;
          final ok = await repository.markEmiPaid(
            mutation.entityId,
            expectedDueDate: next.dueDate,
            expectedInstallmentNumber: next.number,
            paidEarly: true,
          );
          if (!ok) break;
        }
        final after = await repository.emiDetail(mutation.entityId);
        final priorIds = before.payments.map((item) => item.id).toSet();
        final ids = after.payments
            .where((item) => !priorIds.contains(item.id))
            .map((item) => item.id)
            .toList();
        return _successReply(
          '${displayName(mutation.entityName)} is closed.',
          AssistantUndoMutation(
            kind: mutation.kind,
            entityType: mutation.entityType,
            entityId: mutation.entityId,
            entityName: mutation.entityName,
            value: ids,
            expiresAt: DateTime.now().add(const Duration(seconds: 6)),
          ),
        );
      case AssistantMutationKind.deleteMoney:
        await repository.deleteMoneyRecord(mutation.entityId);
        return _restoreReply(mutation, 'Money record moved to Deleted.');
      case AssistantMutationKind.addMoneyRepayment:
      case AssistantMutationKind.settleMoney:
        final id = await repository.addRepayment(
          mutation.entityId,
          mutation.amountPaise!,
          'Recorded through Ask FinKeep',
          DateTime.now(),
        );
        return _successReply(
          mutation.kind == AssistantMutationKind.settleMoney
              ? '${displayName(mutation.entityName)} is settled.'
              : '${formatMoney(mutation.amountPaise!)} repayment recorded for ${displayName(mutation.entityName)}.',
          AssistantUndoMutation(
            kind: mutation.kind,
            entityType: mutation.entityType,
            entityId: mutation.entityId,
            entityName: mutation.entityName,
            relatedId: id,
            expiresAt: DateTime.now().add(const Duration(seconds: 6)),
          ),
        );
      case AssistantMutationKind.extendMoneyDueDate:
        final detail = await repository.moneyDetail(mutation.entityId);
        final next = (detail.record.dueDate ?? DateTime.now()).add(
          Duration(days: mutation.extendDays!),
        );
        await repository.updateMoneyDueDate(mutation.entityId, next);
        return _successReply(
          '${displayName(mutation.entityName)} is now due ${formatDate(next)}.',
          AssistantUndoMutation(
            kind: mutation.kind,
            entityType: mutation.entityType,
            entityId: mutation.entityId,
            entityName: mutation.entityName,
            date: detail.record.dueDate,
            expiresAt: DateTime.now().add(const Duration(seconds: 6)),
          ),
        );
    }
  }

  @override
  Future<AssistantReply> undo(AssistantUndoMutation mutation) async {
    if (!mutation.restore &&
        mutation.expiresAt != null &&
        DateTime.now().isAfter(mutation.expiresAt!)) {
      return const AssistantReply('The 6-second undo window has ended.');
    }
    switch (mutation.kind) {
      case AssistantMutationKind.scheduleReminder:
        await repository.cancelAssistantReminder(mutation.relatedId!);
        return const AssistantReply('Reminder cancelled.');
      case AssistantMutationKind.deleteSubscription:
        await repository.restoreSubscriptionById(mutation.entityId);
      case AssistantMutationKind.deleteEmi:
        await repository.restoreEmi(mutation.entityId);
      case AssistantMutationKind.deleteMoney:
        await repository.restoreMoneyRecord(mutation.entityId);
      case AssistantMutationKind.markEmiPaid:
        if (mutation.relatedId != null) {
          await repository.revertEmiPayment(
            mutation.entityId,
            mutation.relatedId!,
          );
        }
      case AssistantMutationKind.closeEmi:
        final ids = (mutation.value as List<int>?) ?? const [];
        for (final id in ids.reversed) {
          await repository.revertEmiPayment(mutation.entityId, id);
        }
      case AssistantMutationKind.addMoneyRepayment:
      case AssistantMutationKind.settleMoney:
        if (mutation.relatedId != null) {
          await repository.revertMoneyRepayment(
            mutation.entityId,
            mutation.relatedId!,
          );
        }
      case AssistantMutationKind.extendMoneyDueDate:
        await repository.setMoneyDueDate(mutation.entityId, mutation.date);
      case AssistantMutationKind.changeSubscriptionAmount:
        final item = await repository.subscription(mutation.entityId);
        if (item != null) {
          await repository.saveSubscription(
            SubscriptionsCompanion(
              id: Value(item.id),
              name: Value(item.name),
              amountPaise: Value(mutation.value! as int),
              frequency: Value(item.frequency),
              nextBillingDate: Value(item.nextBillingDate),
              paymentMethodId: Value(item.paymentMethodId),
              category: Value(item.category),
              status: Value(item.status),
              notes: Value(item.notes),
              updatedAt: Value(DateTime.now()),
            ),
          );
        }
      case AssistantMutationKind.pauseSubscription when mutation.date != null:
        final item = await repository.subscription(mutation.entityId);
        if (item != null) {
          await repository.saveSubscription(
            SubscriptionsCompanion(
              id: Value(item.id),
              name: Value(item.name),
              amountPaise: Value(item.amountPaise),
              frequency: Value(item.frequency),
              nextBillingDate: Value(mutation.date!),
              paymentMethodId: Value(item.paymentMethodId),
              category: Value(item.category),
              status: Value(item.status),
              notes: Value(item.notes),
              updatedAt: Value(DateTime.now()),
            ),
          );
        }
      case AssistantMutationKind.cancelSubscription:
      case AssistantMutationKind.pauseSubscription:
      case AssistantMutationKind.resumeSubscription:
        await repository.setSubscriptionStatus(
          mutation.entityId,
          mutation.value! as SubscriptionStatus,
        );
    }
    return AssistantReply(
      '${displayName(mutation.entityName)} restored to its previous state.',
    );
  }
}

AssistantDestination _destinationForDraft(AssistantFormKind kind) =>
    switch (kind) {
      AssistantFormKind.emi => AssistantDestination.emis,
      AssistantFormKind.moneyGiven ||
      AssistantFormKind.moneyBorrowed => AssistantDestination.money,
      AssistantFormKind.subscription => AssistantDestination.subscriptions,
    };

String _mutationVerb(AssistantMutationKind kind) => switch (kind) {
  AssistantMutationKind.scheduleReminder => 'remind',
  AssistantMutationKind.cancelSubscription => 'cancel',
  AssistantMutationKind.pauseSubscription => 'pause',
  AssistantMutationKind.resumeSubscription => 'resume',
  AssistantMutationKind.deleteSubscription ||
  AssistantMutationKind.deleteEmi ||
  AssistantMutationKind.deleteMoney => 'delete',
  AssistantMutationKind.changeSubscriptionAmount => 'change',
  AssistantMutationKind.markEmiPaid => 'mark paid',
  AssistantMutationKind.closeEmi => 'close',
  AssistantMutationKind.addMoneyRepayment => 'record repayment for',
  AssistantMutationKind.extendMoneyDueDate => 'extend',
  AssistantMutationKind.settleMoney => 'settle',
};

String _commandSuggestion(
  AssistantActionCommand command,
  String entityName,
) => switch (command.kind) {
  AssistantMutationKind.scheduleReminder => 'Remind me about $entityName',
  AssistantMutationKind.cancelSubscription => 'Cancel subscription $entityName',
  AssistantMutationKind.pauseSubscription =>
    'Pause $entityName${command.pauseMonths == null ? '' : ' for ${command.pauseMonths} months'}',
  AssistantMutationKind.resumeSubscription => 'Resume $entityName',
  AssistantMutationKind.deleteSubscription => 'Delete subscription $entityName',
  AssistantMutationKind.changeSubscriptionAmount =>
    'Change $entityName to ${formatMoney(command.amountPaise!)}',
  AssistantMutationKind.deleteEmi => 'Delete EMI $entityName',
  AssistantMutationKind.markEmiPaid =>
    'Mark $entityName paid${command.paidEarly ? ' early' : ''}',
  AssistantMutationKind.closeEmi => 'Close EMI $entityName',
  AssistantMutationKind.deleteMoney => 'Delete $entityName money',
  AssistantMutationKind.addMoneyRepayment =>
    '$entityName paid ${formatMoney(command.amountPaise!)}',
  AssistantMutationKind.extendMoneyDueDate =>
    'Extend $entityName due date by ${command.extendDays} days',
  AssistantMutationKind.settleMoney => 'Mark $entityName settled',
};

AssistantReply _successReply(String text, AssistantUndoMutation undo) =>
    AssistantReply(text, undoMutation: undo);

AssistantReply _restoreReply(AssistantPendingMutation mutation, String text) =>
    AssistantReply(
      text,
      undoMutation: AssistantUndoMutation(
        kind: mutation.kind,
        entityType: mutation.entityType,
        entityId: mutation.entityId,
        entityName: mutation.entityName,
        restore: true,
      ),
    );

List<AssistantAction> _amountActions(int amountPaise) {
  if (amountPaise <= 0) return const [];
  return [
    AssistantAction(
      'Add to EMI',
      AssistantDestination.emis,
      formDraft: AssistantFormDraft(
        kind: AssistantFormKind.emi,
        amountPaise: amountPaise,
      ),
    ),
    AssistantAction(
      'Add as money given',
      AssistantDestination.money,
      formDraft: AssistantFormDraft(
        kind: AssistantFormKind.moneyGiven,
        amountPaise: amountPaise,
      ),
    ),
    AssistantAction(
      'Add as money borrowed',
      AssistantDestination.money,
      formDraft: AssistantFormDraft(
        kind: AssistantFormKind.moneyBorrowed,
        amountPaise: amountPaise,
      ),
    ),
    AssistantAction(
      'Add as subscription',
      AssistantDestination.subscriptions,
      formDraft: AssistantFormDraft(
        kind: AssistantFormKind.subscription,
        amountPaise: amountPaise,
      ),
    ),
  ];
}

List<String> _dataSuggestions(FinanceFacts facts) {
  final choices = <String>['My financial status'];
  if (facts.activeEmis.isNotEmpty) choices.add('When is my next EMI?');
  if (facts.given.isNotEmpty) choices.add('Who owes me?');
  if (facts.borrowed.isNotEmpty) choices.add('How much do I owe?');
  if (facts.activeSubscriptions.isNotEmpty) {
    choices.add('Subscriptions per month');
  }
  for (final fallback in [
    "What's due this week?",
    '15% of 8000',
    'Add an EMI',
    'Help',
  ]) {
    if (choices.length >= 4) break;
    choices.add(fallback);
  }
  return choices.take(4).toList();
}

List<String> _closestSuggestions(String question, FinanceFacts facts) {
  final candidates = <String>{
    ..._dataSuggestions(facts),
    'Next EMI date',
    'How much do I need to pay this month?',
    'Who owes me?',
    'Subscriptions per month',
    'Analyze my portfolio',
    'Monthly outflow',
    'Pause a subscription',
    'Mark an EMI paid',
    'Record a repayment',
    'Delete a record',
  }.toList();
  final tokens = normalizeQuestion(
    question,
  ).split(' ').where((token) => token.isNotEmpty).toList();
  int score(String candidate) {
    final words = normalizeQuestion(candidate).split(' ');
    return tokens.fold(
      0,
      (sum, token) =>
          sum +
          (words.contains(token)
              ? 3
              : words.any(
                  (word) =>
                      token.length >= 4 && _distanceAtMostOne(token, word) == 1,
                )
              ? 2
              : 0),
    );
  }

  candidates.sort((a, b) => score(b).compareTo(score(a)));
  return candidates.take(3).toList();
}

AssistantReply _analyzePortfolio(FinanceFacts facts) {
  final outflow = facts.monthlyOutflowPaise;
  final emiShare = outflow == 0 ? 0.0 : facts.monthlyEmiPaise / outflow;
  final subscriptionsShare = outflow == 0
      ? 0.0
      : facts.monthlySubscriptionsPaise / outflow;
  final overdue = facts
      .dueItemsThrough(facts.now)
      .where((item) => dateOnly(item.dueDate).isBefore(dateOnly(facts.now)))
      .toList();
  final undated = facts.given
      .where((item) => item.record.dueDate == null)
      .toList();
  final costly =
      facts.activeSubscriptions
          .where(
            (item) =>
                monthlyEquivalentPaise(item.amountPaise, item.frequency) > 0,
          )
          .toList()
        ..sort(
          (a, b) => monthlyEquivalentPaise(
            b.amountPaise,
            b.frequency,
          ).compareTo(monthlyEquivalentPaise(a.amountPaise, a.frequency)),
        );
  final rated =
      facts.activeEmis
          .where((item) => (item.emi.interestRate ?? 0) > 0)
          .toList()
        ..sort((a, b) => b.emi.interestRate!.compareTo(a.emi.interestRate!));
  final balances = <(String, int)>[
    for (final emi in facts.activeEmis)
      (emi.emi.name, emi.remainingBalancePaise),
    for (final item in facts.borrowed)
      (item.record.personName, item.summary.remainingAmountPaise),
  ]..sort((a, b) => a.$2.compareTo(b.$2));
  final largestCreditor = facts.borrowed.toList()
    ..sort(
      (a, b) => b.summary.remainingAmountPaise.compareTo(
        a.summary.remainingAmountPaise,
      ),
    );
  final largestDebtor = facts.given.toList()
    ..sort(
      (a, b) => b.summary.remainingAmountPaise.compareTo(
        a.summary.remainingAmountPaise,
      ),
    );
  final suggestions = <String>[];
  if (rated.isNotEmpty) {
    suggestions.add(
      '1. Consider ${rated.first.emi.name} first: it has the highest recorded rate (${rated.first.emi.interestRate}% p.a.).',
    );
  } else if (balances.isNotEmpty) {
    suggestions.add(
      '1. Consider ${balances.first.$1} first by the smallest-balance rule (${formatMoney(balances.first.$2)}); no positive EMI interest rate is recorded.',
    );
  }
  if (overdue.isNotEmpty) {
    final item = overdue.first;
    suggestions.add(
      '${suggestions.length + 1}. Follow up on ${item.label}: ${formatMoney(item.amountPaise)} was due ${formatDate(item.dueDate)}.',
    );
  }
  if (undated.isNotEmpty) {
    suggestions.add(
      '${suggestions.length + 1}. Set due dates for ${undated.length} money-given ${undated.length == 1 ? 'record' : 'records'} totaling ${formatMoney(undated.fold<int>(0, (sum, item) => sum + item.summary.remainingAmountPaise))}.',
    );
  }
  if (costly.isNotEmpty) {
    suggestions.add(
      '${suggestions.length + 1}. Check whether ${costly.first.name} is still used; pausing it would avoid about ${formatMoney(monthlyEquivalentPaise(costly.first.amountPaise, costly.first.frequency) * 12)} a year.',
    );
  }
  if (emiShare > 0.4) {
    suggestions.add(
      '${suggestions.length + 1}. EMI payments are ${(emiShare * 100).round()}% of estimated monthly outflow; review the commitment before adding a new EMI.',
    );
  }
  for (final fallback in [
    'Review upcoming due dates in FinKeep this month.',
    'Add due dates when you record money given or borrowed.',
    'Check your recurring commitments before adding a new one.',
  ]) {
    if (suggestions.length >= 3) break;
    suggestions.add('${suggestions.length + 1}. $fallback');
  }
  final debtDate = facts.debtFreeDate;
  final undatedTotal = undated.fold<int>(
    0,
    (sum, item) => sum + item.summary.remainingAmountPaise,
  );
  final health = calculateAssistantHealthScore(
    AssistantHealthInput(
      emiShare: emiShare,
      overdueCount: overdue.length,
      undatedLentShare: facts.toReceivePaise == 0
          ? 0
          : undatedTotal / facts.toReceivePaise,
      subscriptionShare: subscriptionsShare,
    ),
  );
  final nextThirty = facts.dueItemsInRange(
    dateOnly(facts.now),
    dateOnly(facts.now).add(const Duration(days: 30)),
    includeOverdue: true,
  );
  final categories = <String, int>{};
  for (final item in facts.activeSubscriptions) {
    final category = item.category?.trim().isNotEmpty == true
        ? item.category!.trim()
        : 'Other';
    categories.update(
      category,
      (value) =>
          value + monthlyEquivalentPaise(item.amountPaise, item.frequency),
      ifAbsent: () => monthlyEquivalentPaise(item.amountPaise, item.frequency),
    );
  }
  return AssistantReply(
    'FinKeep portfolio review (${formatDate(dateOnly(facts.now))}).\n${suggestions.take(5).join('\n')}\nBased only on data on this phone. Not financial advice.',
    rows: [
      AssistantRow(
        'EMI share of monthly outflow',
        '${(emiShare * 100).round()}%${emiShare > 0.4 ? ' · above 40%' : ''}',
      ),
      AssistantRow(
        'Subscriptions share',
        '${(subscriptionsShare * 100).round()}%',
      ),
      AssistantRow(
        'Overdue payments',
        '${overdue.length} · ${formatMoney(overdue.fold<int>(0, (sum, item) => sum + item.amountPaise))}',
      ),
      if (largestCreditor.isNotEmpty)
        AssistantRow(
          'Biggest creditor',
          '${displayName(largestCreditor.first.record.personName)} · ${formatMoney(largestCreditor.first.summary.remainingAmountPaise)}',
        ),
      if (largestDebtor.isNotEmpty)
        AssistantRow(
          'Biggest debtor',
          '${displayName(largestDebtor.first.record.personName)} · ${formatMoney(largestDebtor.first.summary.remainingAmountPaise)}',
        ),
      if (costly.isNotEmpty)
        AssistantRow(
          'Costliest subscription',
          '${displayName(costly.first.name)} · ${formatMoney(monthlyEquivalentPaise(costly.first.amountPaise, costly.first.frequency))}/month',
        ),
      AssistantRow(
        'Debt-free date',
        debtDate == null
            ? 'Unknown: a debt has no due date'
            : facts.totalDebtPaise == 0
            ? 'No tracked debt'
            : '${formatDate(debtDate)} · ${dateOnly(debtDate).difference(dateOnly(facts.now)).inDays < 0 ? 'past due' : 'in ${dateOnly(debtDate).difference(dateOnly(facts.now)).inDays} days'}',
      ),
    ],
    visuals: [
      AssistantVisualPart(
        kind: AssistantVisualKind.bigNumber,
        title: 'Net position',
        bigValue: formatMoney(facts.netPositionPaise),
        subtitle: 'Money owed to you minus Money you borrowed',
      ),
      if (facts.toReceivePaise > 0 || facts.totalDebtPaise > 0)
        AssistantVisualPart(
          kind: AssistantVisualKind.donut,
          title: 'Coming to me vs I need to pay',
          bigValue: formatMoney(facts.toReceivePaise - facts.totalDebtPaise),
          data: [
            AssistantVisualDatum(
              label: 'Coming to me',
              value: facts.toReceivePaise.toDouble(),
              displayValue: formatMoney(facts.toReceivePaise),
            ),
            AssistantVisualDatum(
              label: 'I need to pay',
              value: facts.totalDebtPaise.toDouble(),
              displayValue: formatMoney(facts.totalDebtPaise),
            ),
          ],
        ),
      if (outflow > 0)
        AssistantVisualPart(
          kind: AssistantVisualKind.stackedBar,
          title: 'Monthly outflow',
          bigValue: formatMoney(outflow),
          data: [
            AssistantVisualDatum(
              label: 'EMIs',
              value: facts.monthlyEmiPaise.toDouble(),
              displayValue: '${(emiShare * 100).round()}%',
            ),
            AssistantVisualDatum(
              label: 'Subscriptions',
              value: facts.monthlySubscriptionsPaise.toDouble(),
              displayValue: '${(subscriptionsShare * 100).round()}%',
            ),
            AssistantVisualDatum(
              label: 'Money due',
              value: facts.upcomingBorrowedPaise.toDouble(),
              displayValue: outflow == 0
                  ? '0%'
                  : '${(facts.upcomingBorrowedPaise / outflow * 100).round()}%',
            ),
          ],
        ),
      if (nextThirty.isNotEmpty)
        AssistantVisualPart(
          kind: AssistantVisualKind.weeklyBars,
          title: 'Next 30 days by week',
          data: buildWeeklyChartData(
            nextThirty.map(
              (item) => AssistantDatedAmount(
                item.dueDate,
                item.amountPaise,
                overdue: dateOnly(item.dueDate).isBefore(dateOnly(facts.now)),
              ),
            ),
            facts.now,
          ),
        ),
      if (facts.activeEmis.isNotEmpty)
        AssistantVisualPart(
          kind: AssistantVisualKind.progressRows,
          title: debtDate == null
              ? 'EMI progress'
              : 'EMI progress · debt-free ${formatDate(debtDate)}',
          data: [
            for (final item in facts.activeEmis)
              AssistantVisualDatum(
                label: displayName(item.emi.name),
                value: item.progress,
                displayValue: '${(item.progress * 100).round()}%',
                detail: '${formatMoney(item.remainingBalancePaise)} remaining',
              ),
          ],
        ),
      if (categories.isNotEmpty)
        AssistantVisualPart(
          kind: AssistantVisualKind.horizontalBars,
          title: 'Subscriptions by category',
          data: [
            for (final entry in categories.entries)
              AssistantVisualDatum(
                label: entry.key,
                value: entry.value.toDouble(),
                displayValue: formatMoney(entry.value),
              ),
          ],
        ),
      AssistantVisualPart(
        kind: AssistantVisualKind.scoreRing,
        title: 'Financial health',
        score: health.score.toDouble(),
        subtitle: 'Calculated from four local-data factors',
        data: health.factors,
      ),
    ],
    actions: const [
      AssistantAction('Open EMIs', AssistantDestination.emis),
      AssistantAction('Open Money', AssistantDestination.money),
      AssistantAction('Open subscriptions', AssistantDestination.subscriptions),
    ],
  );
}
