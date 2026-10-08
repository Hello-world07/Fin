import '../../domain/enums.dart';
import 'assistant_math.dart';

enum AssistantFormKind { emi, moneyGiven, moneyBorrowed, subscription }

class AssistantFormDraft {
  const AssistantFormDraft({
    required this.kind,
    this.amountPaise,
    this.name,
    this.tenureMonths,
    this.frequency,
    this.dueDate,
  });
  final AssistantFormKind kind;
  final int? amountPaise;
  final String? name;
  final int? tenureMonths;
  final PaymentFrequency? frequency;
  final DateTime? dueDate;

  AssistantFormDraft withAmount(int amount) => AssistantFormDraft(
    kind: kind,
    amountPaise: amount,
    name: name,
    tenureMonths: tenureMonths,
    frequency: frequency,
    dueDate: dueDate,
  );
}

class AssistantCommand {
  const AssistantCommand(this.draft, {this.ambiguousMoney = false});
  final AssistantFormDraft draft;
  final bool ambiguousMoney;
}

final _amountPattern = RegExp(
  r'(?:₹\s*|rs\.?\s*)?([0-9][0-9,]*(?:\.[0-9]+)?\s*(?:lakhs?|crores?|cr|k|l)?)',
  caseSensitive: false,
);

int? parseAssistantAmountPaise(String text) {
  final match = _amountPattern.firstMatch(text);
  if (match == null) return null;
  try {
    final amount = parseAssistantNumber(match.group(1)!.replaceAll(' ', ''));
    return amount > 0 ? (amount * 100).round() : null;
  } on FormatException {
    return null;
  }
}

DateTime? parseAssistantDueDate(String text, DateTime now) {
  final q = text.toLowerCase();
  final today = DateTime(now.year, now.month, now.day);
  if (q.contains('tomorrow')) return today.add(const Duration(days: 1));
  if (q.contains('today')) return today;
  final weekday = RegExp(
    r'next\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)',
  ).firstMatch(q);
  if (weekday != null) {
    const names = [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday',
    ];
    final target = names.indexOf(weekday.group(1)!) + 1;
    final days = (target - today.weekday + 7) % 7;
    return today.add(Duration(days: days == 0 ? 7 : days));
  }
  final named = RegExp(
    r'\b(\d{1,2})\s+(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)(?:\s+(\d{4}))?\b',
  ).firstMatch(q);
  if (named == null) return null;
  const months = [
    'jan',
    'feb',
    'mar',
    'apr',
    'may',
    'jun',
    'jul',
    'aug',
    'sep',
    'oct',
    'nov',
    'dec',
  ];
  final month = months.indexOf(named.group(2)!.substring(0, 3)) + 1;
  final day = int.parse(named.group(1)!);
  var year = int.tryParse(named.group(3) ?? '') ?? today.year;
  var result = DateTime(year, month, day);
  if (result.day != day || result.month != month) return null;
  if (named.group(3) == null && result.isBefore(today)) {
    year++;
    result = DateTime(year, month, day);
  }
  return result;
}

AssistantCommand? parseAssistantCommand(String question, DateTime now) {
  final q = question.trim();
  final lower = q.toLowerCase();
  final isGiven = RegExp(r'\b(?:i gave|gave|lent)\b').hasMatch(lower);
  final isBorrowed = RegExp(r'\b(?:i borrowed|borrowed)\b').hasMatch(lower);
  final isSubscription = RegExp(
    r'\b(?:add|create|new)\s+subscription\b',
  ).hasMatch(lower);
  final isEmi = RegExp(
    r'\b(?:add|create|new)\b.*\bemi\b|\bemi\s+[0-9]|^[0-9][0-9,]*(?:\.[0-9]+)?\s*(?:k|lakh|cr)?\s+add\s+to\s+emi\b',
  ).hasMatch(lower);
  final isMoney = RegExp(r'\b(?:add|create|new)\b.*\bmoney\b').hasMatch(lower);
  if (!isGiven && !isBorrowed && !isSubscription && !isEmi && !isMoney) {
    return null;
  }

  final amountMatch = _amountPattern.firstMatch(q);
  final amount = amountMatch == null
      ? null
      : parseAssistantAmountPaise(amountMatch.group(0)!);
  final frequency = lower.contains('quarterly')
      ? PaymentFrequency.quarterly
      : lower.contains('weekly')
      ? PaymentFrequency.weekly
      : lower.contains('yearly') || lower.contains('annual')
      ? PaymentFrequency.yearly
      : lower.contains('monthly')
      ? PaymentFrequency.monthly
      : null;
  final tenure = RegExp(
    r'\bfor\s+(\d{1,3})\s+(months?|years?)\b',
  ).firstMatch(lower);
  final count = tenure == null
      ? null
      : int.parse(tenure.group(1)!) *
            (tenure.group(2)!.startsWith('year') ? 12 : 1);
  String? name;
  if (isGiven || isBorrowed) {
    final beforeAmount = RegExp(
      r'\b(?:i gave|gave|lent|i borrowed|borrowed)\s+([a-z][a-z ]*?)\s+(?:₹\s*|rs\.?\s*)?\d',
      caseSensitive: false,
    ).firstMatch(q);
    final afterAmount = RegExp(
      r'\b(?:to|from)\s+([a-z][a-z ]+?)(?=\s+(?:tomorrow|today|next|on|due)\b|$)',
      caseSensitive: false,
    ).firstMatch(q);
    name = (beforeAmount?.group(1) ?? afterAmount?.group(1))?.trim();
  } else if (isSubscription && amountMatch != null) {
    final prefix = q
        .substring(0, amountMatch.start)
        .replaceFirst(
          RegExp(
            r'^\s*(?:add|create|new)\s+subscription\s*',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
    if (prefix.isNotEmpty) name = prefix;
  }
  final kind = isSubscription
      ? AssistantFormKind.subscription
      : isEmi
      ? AssistantFormKind.emi
      : isBorrowed
      ? AssistantFormKind.moneyBorrowed
      : AssistantFormKind.moneyGiven;
  return AssistantCommand(
    AssistantFormDraft(
      kind: kind,
      amountPaise: amount,
      name: name,
      tenureMonths: count,
      frequency: frequency,
      dueDate: parseAssistantDueDate(q, now),
    ),
    ambiguousMoney: isMoney && !isGiven && !isBorrowed,
  );
}
