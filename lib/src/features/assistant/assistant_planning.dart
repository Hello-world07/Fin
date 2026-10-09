import 'dart:math' as math;

import '../../domain/enums.dart';
import '../../domain/subscription_schedule.dart';

enum WhatIfKind { extraEmi, closeEmi, pauseSubscription }

class WhatIfRequest {
  const WhatIfRequest(this.kind, this.target, {this.amountPaise, this.months});
  final WhatIfKind kind;
  final String target;
  final int? amountPaise;
  final int? months;
}

WhatIfRequest? parseWhatIf(String question) {
  final q = question.toLowerCase().trim();
  final extra = RegExp(
    r'^(?:(?:what if|if)\s+)?(?:i\s+)?(?:pay|prepay)\s+([\d,]+)\s+(?:extra|more)(?:\s+(?:now|on|towards|to))?\s*(.*)$',
  ).firstMatch(q);
  if (extra != null) {
    final amount = int.tryParse(extra.group(1)!.replaceAll(',', ''));
    if (amount == null || amount <= 0) return null;
    return WhatIfRequest(
      WhatIfKind.extraEmi,
      extra.group(2)!.trim(),
      amountPaise: amount * 100,
    );
  }
  final alternate = RegExp(
    r'^(?:(?:what if|if)\s+)?(?:i\s+)?(?:pay\s+now\s+extra|prepay|pay\s+extra)\s+([\d,]+)(?:\s+(?:on|towards|to))?\s*(.*)$',
  ).firstMatch(q);
  if (alternate != null) {
    final amount = int.tryParse(alternate.group(1)!.replaceAll(',', ''));
    if (amount == null || amount <= 0) return null;
    return WhatIfRequest(
      WhatIfKind.extraEmi,
      alternate.group(2)!.trim(),
      amountPaise: amount * 100,
    );
  }
  final close = RegExp(
    r'(?:what if |if )?i?\s*close\s+(.+?)(?:\s+(?:loan|emi))?\s+now$',
  ).firstMatch(q);
  if (close != null) {
    return WhatIfRequest(WhatIfKind.closeEmi, close.group(1)!.trim());
  }
  final pause = RegExp(
    r'(?:what if |if )?i?\s*pause\s+(.+?)\s+for\s+(\d+)\s+months?$',
  ).firstMatch(q);
  if (pause != null) {
    final months = int.tryParse(pause.group(2)!);
    if (months == null || months < 1 || months > 120) return null;
    return WhatIfRequest(
      WhatIfKind.pauseSubscription,
      pause.group(1)!.trim(),
      months: months,
    );
  }
  return null;
}

class EmiWhatIf {
  const EmiWhatIf({
    required this.monthsSaved,
    required this.newDebtFreeDate,
    this.interestSavedPaise,
  });
  final int monthsSaved;
  final DateTime newDebtFreeDate;
  final int? interestSavedPaise;
}

EmiWhatIf calculateEmiWhatIf({
  required int remainingPaise,
  required int installmentPaise,
  required List<DateTime> unpaidDueDates,
  required int extraPaise,
  double? annualRate,
  required DateTime today,
}) {
  if (installmentPaise <= 0 || unpaidDueDates.isEmpty) {
    return EmiWhatIf(monthsSaved: 0, newDebtFreeDate: today);
  }
  final dates = unpaidDueDates.toList()..sort();
  if (extraPaise >= remainingPaise) {
    return EmiWhatIf(
      monthsSaved: dates.length,
      newDebtFreeDate: today,
      interestSavedPaise: annualRate == null
          ? null
          : math.max(
              0,
              remainingPaise -
                  _principalPresentValue(
                    installmentPaise,
                    dates.length,
                    annualRate,
                  ).round(),
            ),
    );
  }
  final balance = math.max(0, remainingPaise - extraPaise);
  var newCount = (balance / installmentPaise).ceil().clamp(1, dates.length);
  int? interestSaved;
  if (annualRate != null && annualRate > 0) {
    final rate = annualRate / 1200;
    final principal = _principalPresentValue(
      installmentPaise,
      dates.length,
      annualRate,
    );
    var debt = math.max(0.0, principal - extraPaise);
    var paid = 0.0;
    newCount = 0;
    while (debt > 0.5 && newCount < dates.length) {
      debt *= 1 + rate;
      final payment = math.min(debt, installmentPaise.toDouble());
      debt -= payment;
      paid += payment;
      newCount++;
    }
    interestSaved = math.max(0, remainingPaise - extraPaise - paid.round());
  } else if (annualRate == 0) {
    interestSaved = 0;
  }
  return EmiWhatIf(
    monthsSaved: dates.length - newCount,
    newDebtFreeDate: dates[newCount - 1],
    interestSavedPaise: interestSaved,
  );
}

double _principalPresentValue(int payment, int periods, double annualRate) {
  final rate = annualRate / 1200;
  if (rate == 0) return (payment * periods).toDouble();
  return payment * (1 - math.pow(1 + rate, -periods)) / rate;
}

class ChatReminderRequest {
  const ChatReminderRequest(this.target, this.when, this.isSubscription);
  final String target;
  final DateTime when;
  final bool isSubscription;
}

ChatReminderRequest? parseChatReminder(
  String question,
  DateTime now, {
  DateTime? renewalDate,
}) {
  final q = question.toLowerCase().trim();
  final before = RegExp(
    r'^remind me (\d+) days? before (.+?) renews$',
  ).firstMatch(q);
  if (before != null && renewalDate != null) {
    final days = int.parse(before.group(1)!);
    final when = DateTime(
      renewalDate.year,
      renewalDate.month,
      renewalDate.day,
      9,
    ).subtract(Duration(days: days));
    return when.isAfter(now)
        ? ChatReminderRequest(before.group(2)!.trim(), when, true)
        : null;
  }
  final weekday = RegExp(
    r'^remind me to pay (.+?) on (monday|tuesday|wednesday|thursday|friday|saturday|sunday)$',
  ).firstMatch(q);
  if (weekday == null) return null;
  const days = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];
  final targetDay = days.indexOf(weekday.group(2)!) + 1;
  var offset = (targetDay - now.weekday + 7) % 7;
  if (offset == 0 && now.hour >= 9) offset = 7;
  final when = DateTime(now.year, now.month, now.day + offset, 9);
  return ChatReminderRequest(weekday.group(1)!.trim(), when, false);
}

DateTime subscriptionPauseEnd(
  DateTime nextBilling,
  PaymentFrequency frequency,
  DateTime now,
  int months,
) {
  final next = nextSubscriptionBillingDate(nextBilling, frequency, now);
  return DateTime(next.year, next.month + months, next.day);
}
