enum EmiStatus { active, dueSoon, overdue, completed, paused }

enum MoneyDirection { given, borrowed }

enum MoneyStatus { active, dueSoon, overdue, settled, paused }

enum SubscriptionStatus { active, paused, cancelled, inactive }

enum PaymentFrequency { once, weekly, monthly, quarterly, yearly }

enum ActivityType {
  emiCreated,
  emiEdited,
  emiPaymentRecorded,
  emiPaidEarly,
  emiCompleted,
  emiDeleted,
  moneyGiven,
  moneyBorrowed,
  moneyRepayment,
  moneyEdited,
  moneyDeleted,
  subscriptionCreated,
  subscriptionChanged,
  subscriptionDeleted,
}

enum ReminderStatus { upcoming, dueToday, overdue, completed }

extension EnumLabel on Enum {
  String get label {
    final words = name.replaceAllMapped(
      RegExp(r'([A-Z])'),
      (match) => ' ${match.group(1)}',
    );
    return words[0].toUpperCase() + words.substring(1);
  }
}
