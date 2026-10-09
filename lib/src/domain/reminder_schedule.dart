enum FinanceReminderType { emi, money, subscription }

class ReminderPlanSettings {
  const ReminderPlanSettings({
    this.enabled = false,
    this.hour = 9,
    this.minute = 0,
    this.leadDays = const {3, 1, 0},
    this.overdueNudge = true,
    this.emis = true,
    this.money = true,
    this.subscriptions = true,
  });

  final bool enabled;
  final int hour, minute;
  final Set<int> leadDays;
  final bool overdueNudge, emis, money, subscriptions;

  bool allows(FinanceReminderType type) => switch (type) {
    FinanceReminderType.emi => emis,
    FinanceReminderType.money => money,
    FinanceReminderType.subscription => subscriptions,
  };

  ReminderPlanSettings copyWith({
    bool? enabled,
    int? hour,
    int? minute,
    Set<int>? leadDays,
    bool? overdueNudge,
    bool? emis,
    bool? money,
    bool? subscriptions,
  }) => ReminderPlanSettings(
    enabled: enabled ?? this.enabled,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
    leadDays: leadDays ?? this.leadDays,
    overdueNudge: overdueNudge ?? this.overdueNudge,
    emis: emis ?? this.emis,
    money: money ?? this.money,
    subscriptions: subscriptions ?? this.subscriptions,
  );
}

class ReminderTarget {
  const ReminderTarget({
    required this.type,
    required this.entityId,
    required this.name,
    required this.dueDate,
    required this.amountPaise,
    this.installmentNumber,
    this.trial = false,
  });

  final FinanceReminderType type;
  final int entityId;
  final String name;
  final DateTime dueDate;
  final int amountPaise;
  final int? installmentNumber;
  final bool trial;
}

class PlannedReminder {
  const PlannedReminder(this.target, this.when, this.leadDays, this.id);
  final ReminderTarget target;
  final DateTime when;
  final int leadDays;
  final int id;
}

int stableReminderId(ReminderTarget target, int leadDays) {
  final day = target.dueDate;
  final key =
      '${target.type.name}:${target.entityId}:${target.installmentNumber ?? 0}:'
      '${day.year}-${day.month}-${day.day}:${target.trial}:$leadDays';
  var hash = 2166136261;
  for (final unit in key.codeUnits) {
    hash = ((hash ^ unit) * 16777619) & 0xffffffff;
  }
  return 1100000000 + hash % 500000000;
}

List<PlannedReminder> buildReminderPlan(
  Iterable<ReminderTarget> targets,
  ReminderPlanSettings settings,
  DateTime now, {
  int windowDays = 60,
}) {
  if (!settings.enabled) return const [];
  final through = now.add(Duration(days: windowDays));
  final result = <PlannedReminder>[];
  for (final target in targets) {
    if (!settings.allows(target.type)) continue;
    final leads = target.trial
        ? const <int>{2}
        : target.type == FinanceReminderType.subscription
        ? settings.leadDays.intersection(const {3, 1})
        : settings.leadDays;
    for (final lead in leads) {
      final when = DateTime(
        target.dueDate.year,
        target.dueDate.month,
        target.dueDate.day - lead,
        settings.hour,
        settings.minute,
      );
      if (when.isAfter(now) && !when.isAfter(through)) {
        result.add(
          PlannedReminder(target, when, lead, stableReminderId(target, lead)),
        );
      }
    }
    if (!target.trial &&
        target.type != FinanceReminderType.subscription &&
        settings.overdueNudge) {
      final when = DateTime(
        target.dueDate.year,
        target.dueDate.month,
        target.dueDate.day + 1,
        settings.hour,
        settings.minute,
      );
      if (when.isAfter(now) && !when.isAfter(through)) {
        result.add(
          PlannedReminder(target, when, -1, stableReminderId(target, -1)),
        );
      }
    }
  }
  result.sort((a, b) => a.when.compareTo(b.when));
  return result;
}
