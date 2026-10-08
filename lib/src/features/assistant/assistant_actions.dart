import 'assistant_commands.dart' show parseAssistantAmountPaise;

enum AssistantMutationKind {
  cancelSubscription,
  pauseSubscription,
  resumeSubscription,
  deleteSubscription,
  changeSubscriptionAmount,
  deleteEmi,
  markEmiPaid,
  closeEmi,
  deleteMoney,
  addMoneyRepayment,
  extendMoneyDueDate,
  settleMoney,
}

enum AssistantEntityType { subscription, emi, money }

class AssistantActionCommand {
  const AssistantActionCommand({
    required this.kind,
    required this.entityType,
    this.targetText,
    this.amountPaise,
    this.extendDays,
    this.pauseMonths,
    this.installmentMonth,
    this.paidEarly = false,
  });

  final AssistantMutationKind kind;
  final AssistantEntityType entityType;
  final String? targetText;
  final int? amountPaise;
  final int? extendDays;
  final int? pauseMonths;
  final int? installmentMonth;
  final bool paidEarly;
}

class AssistantPendingMutation {
  const AssistantPendingMutation({
    required this.id,
    required this.kind,
    required this.entityType,
    required this.entityId,
    required this.entityName,
    required this.confirmationTitle,
    required this.confirmationEffect,
    this.amountPaise,
    this.oldAmountPaise,
    this.extendDays,
    this.pauseMonths,
    this.expectedDueDate,
    this.expectedInstallmentNumber,
    this.paidEarly = false,
  });

  final String id;
  final AssistantMutationKind kind;
  final AssistantEntityType entityType;
  final int entityId;
  final String entityName;
  final String confirmationTitle;
  final String confirmationEffect;
  final int? amountPaise;
  final int? oldAmountPaise;
  final int? extendDays;
  final int? pauseMonths;
  final DateTime? expectedDueDate;
  final int? expectedInstallmentNumber;
  final bool paidEarly;
}

class AssistantUndoMutation {
  const AssistantUndoMutation({
    required this.kind,
    required this.entityType,
    required this.entityId,
    required this.entityName,
    this.value,
    this.date,
    this.relatedId,
    this.expiresAt,
    this.restore = false,
  });

  final AssistantMutationKind kind;
  final AssistantEntityType entityType;
  final int entityId;
  final String entityName;
  final Object? value;
  final DateTime? date;
  final int? relatedId;
  final DateTime? expiresAt;
  final bool restore;
}

String normalizeActionText(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String? _quotedTarget(String source) {
  final match = RegExp(r'''["']([^"']+)["']''').firstMatch(source);
  return match?.group(1)?.trim();
}

String? _cleanTarget(String input, Iterable<String> words) {
  var value = normalizeActionText(input);
  for (final word in words) {
    value = value.replaceAll(RegExp('\\b${RegExp.escape(word)}\\b'), ' ');
  }
  value = value
      .replaceAll(RegExp(r'\b\d+(?:[.,]\d+)?(?:k|l|lakh|cr)?\b'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return value.isEmpty ? null : value;
}

int? _monthNumber(String value) {
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
  final normalized = normalizeActionText(value);
  for (var index = 0; index < months.length; index++) {
    final month = months[index];
    if (normalized.contains(month) ||
        normalized
            .split(' ')
            .any((word) => word.length >= 3 && month.startsWith(word))) {
      return index + 1;
    }
  }
  return null;
}

AssistantActionCommand? parseAssistantActionCommand(String input) {
  final q = normalizeActionText(input)
      .replaceAll(RegExp(r'\bpuase\b'), 'pause')
      .replaceAll(RegExp(r'\bcanel\b'), 'cancel')
      .replaceAll(RegExp(r'\bdelet\b'), 'delete')
      .replaceAll(RegExp(r'\bresme\b'), 'resume')
      .replaceAll(RegExp(r'\bsetled\b'), 'settled');
  final quoted = _quotedTarget(input);
  bool has(String pattern) => RegExp(pattern).hasMatch(q);
  String? target(Iterable<String> words) => quoted ?? _cleanTarget(q, words);

  if (has(r'\b(cancel|stop)\b') && has(r'\b(subscription|sub)\b')) {
    return AssistantActionCommand(
      kind: AssistantMutationKind.cancelSubscription,
      entityType: AssistantEntityType.subscription,
      targetText: target(['cancel', 'stop', 'my', 'subscription', 'sub']),
    );
  }
  if (has(r'\b(cancel|stop)\b')) {
    return AssistantActionCommand(
      kind: AssistantMutationKind.cancelSubscription,
      entityType: AssistantEntityType.subscription,
      targetText: target(['cancel', 'stop', 'my']),
    );
  }
  if (has(r'\bpause\b')) {
    final duration = RegExp(r'(\d+)\s*months?').firstMatch(q);
    return AssistantActionCommand(
      kind: AssistantMutationKind.pauseSubscription,
      entityType: AssistantEntityType.subscription,
      targetText: target([
        'pause',
        'my',
        'subscription',
        'sub',
        'for',
        'month',
        'months',
      ]),
      pauseMonths: duration == null ? null : int.parse(duration.group(1)!),
    );
  }
  if (has(r'\b(resume|restart)\b') &&
      (has(r'\b(subscription|sub)\b') || !has(r'\bemi\b'))) {
    return AssistantActionCommand(
      kind: AssistantMutationKind.resumeSubscription,
      entityType: AssistantEntityType.subscription,
      targetText: target(['resume', 'restart', 'my', 'subscription', 'sub']),
    );
  }
  if (has(r'\b(change|set|update)\b') &&
      has(r'\b(subscription|wifi|netflix|price|cost|to)\b')) {
    final amount = parseAssistantAmountPaise(input);
    return AssistantActionCommand(
      kind: AssistantMutationKind.changeSubscriptionAmount,
      entityType: AssistantEntityType.subscription,
      targetText: target([
        'change',
        'set',
        'update',
        'subscription',
        'price',
        'cost',
        'to',
        'rs',
        'rupees',
      ]),
      amountPaise: amount,
    );
  }
  if (has(r'\bdelete\b') && has(r'\b(emi|loan)\b')) {
    return AssistantActionCommand(
      kind: AssistantMutationKind.deleteEmi,
      entityType: AssistantEntityType.emi,
      targetText: target(['delete', 'remove', 'my', 'emi', 'loan']),
    );
  }
  if (has(r'\b(close|settle)\b') && has(r'\b(emi|loan)\b')) {
    return AssistantActionCommand(
      kind: AssistantMutationKind.closeEmi,
      entityType: AssistantEntityType.emi,
      targetText: target(['close', 'settle', 'my', 'emi', 'loan']),
    );
  }
  if (has(r'\bclose\b')) {
    return AssistantActionCommand(
      kind: AssistantMutationKind.closeEmi,
      entityType: AssistantEntityType.emi,
      targetText: target(['close', 'my']),
    );
  }
  if (has(r'\bmark\b') && has(r'\b(paid|pay)\b')) {
    return AssistantActionCommand(
      kind: AssistantMutationKind.markEmiPaid,
      entityType: AssistantEntityType.emi,
      targetText: target([
        'mark',
        'paid',
        'pay',
        'emi',
        'installment',
        'instalment',
        'early',
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
      ]),
      installmentMonth: _monthNumber(q),
      paidEarly: has(r'\bearly\b'),
    );
  }
  if (has(r'\bdelete\b') && has(r'\b(money|record|udhar)\b')) {
    return AssistantActionCommand(
      kind: AssistantMutationKind.deleteMoney,
      entityType: AssistantEntityType.money,
      targetText: target([
        'delete',
        'remove',
        'money',
        'record',
        'udhar',
        'my',
      ]),
    );
  }
  if (has(r'\bextend\b') && has(r'\b(due|date)\b')) {
    final days = RegExp(r'(\d+)\s*days?').firstMatch(q);
    return AssistantActionCommand(
      kind: AssistantMutationKind.extendMoneyDueDate,
      entityType: AssistantEntityType.money,
      targetText: target([
        'extend',
        'due',
        'date',
        'by',
        'day',
        'days',
        'money',
        'record',
      ]),
      extendDays: days == null ? null : int.parse(days.group(1)!),
    );
  }
  if (has(r'\b(settled|settle fully|mark settled)\b')) {
    return AssistantActionCommand(
      kind: AssistantMutationKind.settleMoney,
      entityType: AssistantEntityType.money,
      targetText: target([
        'mark',
        'settled',
        'settle',
        'fully',
        'money',
        'record',
      ]),
    );
  }
  if (has(r'\b(paid|gave back|returned|repaid)\b')) {
    final amount = parseAssistantAmountPaise(input);
    if (amount != null) {
      return AssistantActionCommand(
        kind: AssistantMutationKind.addMoneyRepayment,
        entityType: AssistantEntityType.money,
        targetText: target([
          'paid',
          'gave',
          'back',
          'returned',
          'repaid',
          'money',
          'rs',
          'rupees',
        ]),
        amountPaise: amount,
      );
    }
  }
  if (has(r'\bdelete\b') && has(r'\b(subscription|sub)\b')) {
    return AssistantActionCommand(
      kind: AssistantMutationKind.deleteSubscription,
      entityType: AssistantEntityType.subscription,
      targetText: target(['delete', 'remove', 'my', 'subscription', 'sub']),
    );
  }
  if (has(r'\bdelete\b')) {
    return AssistantActionCommand(
      kind: AssistantMutationKind.deleteSubscription,
      entityType: AssistantEntityType.subscription,
      targetText: target(['delete', 'remove', 'my']),
    );
  }
  return null;
}

class AssistantEntityCandidate<T> {
  const AssistantEntityCandidate(this.name, this.value);
  final String name;
  final T value;
}

class AssistantEntityResolution<T> {
  const AssistantEntityResolution({
    this.match,
    this.ambiguous = const [],
    this.suggestions = const [],
  });
  final AssistantEntityCandidate<T>? match;
  final List<AssistantEntityCandidate<T>> ambiguous;
  final List<AssistantEntityCandidate<T>> suggestions;
}

int _editDistance(String a, String b) {
  if (a == b) return 0;
  var previous = List<int>.generate(b.length + 1, (index) => index);
  for (var i = 0; i < a.length; i++) {
    final current = <int>[i + 1];
    for (var j = 0; j < b.length; j++) {
      current.add(
        [
          current[j] + 1,
          previous[j + 1] + 1,
          previous[j] + (a[i] == b[j] ? 0 : 1),
        ].reduce((left, right) => left < right ? left : right),
      );
    }
    previous = current;
  }
  return previous.last;
}

AssistantEntityResolution<T> resolveAssistantEntity<T>(
  String? query,
  Iterable<AssistantEntityCandidate<T>> values,
) {
  final candidates = values.toList();
  if (candidates.isEmpty) return const AssistantEntityResolution();
  final q = normalizeActionText(query ?? '');
  if (q.isEmpty || q == 'it' || q == 'that' || q == 'that one') {
    return candidates.length == 1
        ? AssistantEntityResolution(match: candidates.first)
        : AssistantEntityResolution(ambiguous: candidates);
  }
  final exact = candidates
      .where((item) => normalizeActionText(item.name) == q)
      .toList();
  if (exact.length == 1) return AssistantEntityResolution(match: exact.first);
  final contains = candidates.where((item) {
    final name = normalizeActionText(item.name);
    return name.contains(q) || q.contains(name);
  }).toList();
  if (contains.length == 1) {
    return AssistantEntityResolution(match: contains.first);
  }
  if (contains.length > 1) {
    return AssistantEntityResolution(ambiguous: contains);
  }
  final ranked =
      candidates
          .map(
            (item) => (item, _editDistance(q, normalizeActionText(item.name))),
          )
          .toList()
        ..sort((a, b) => a.$2.compareTo(b.$2));
  final threshold = q.length <= 4 ? 1 : (q.length / 3).ceil();
  final best = ranked.where((item) => item.$2 <= threshold).toList();
  if (best.length == 1 || (best.length > 1 && best.first.$2 < best[1].$2)) {
    return AssistantEntityResolution(match: best.first.$1);
  }
  if (best.length > 1) {
    return AssistantEntityResolution(
      ambiguous: best.map((item) => item.$1).toList(),
    );
  }
  return AssistantEntityResolution(
    suggestions: ranked.take(3).map((item) => item.$1).toList(),
  );
}
