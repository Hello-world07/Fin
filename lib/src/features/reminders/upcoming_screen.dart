import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/providers.dart';
import '../../data/repositories.dart';
import '../../domain/emi_payment_rules.dart';
import '../../domain/enums.dart';
import '../../shared/finance_display_widgets.dart';
import '../emis/emis_screen.dart';
import '../money/money_screen.dart';
import '../subscriptions/subscriptions_screen.dart';

class UpcomingScreen extends ConsumerWidget {
  const UpcomingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(financeRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Upcoming')),
      body: StreamBuilder<List<ReminderItem>>(
        stream: repo.watchReminders(attentionOnly: false),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final today = dateOnly(DateTime.now());
          final end = today.add(const Duration(days: 30));
          final items = snapshot.data!
              .where(
                (item) =>
                    item.status != ReminderStatus.completed &&
                    !dateOnly(item.dueAt).isAfter(end),
              )
              .toList();
          if (items.isEmpty) return const Center(child: Text('All clear'));
          final weekEnd = today.add(const Duration(days: 7));
          final monthEnd = DateTime(today.year, today.month + 1);
          final groups = <String, List<ReminderItem>>{
            'Overdue': [],
            'This week': [],
            'Later this month': [],
            'Next month': [],
          };
          for (final item in items) {
            final due = dateOnly(item.dueAt);
            final key = due.isBefore(today)
                ? 'Overdue'
                : due.isBefore(weekEnd)
                ? 'This week'
                : due.isBefore(monthEnd)
                ? 'Later this month'
                : 'Next month';
            groups[key]!.add(item);
          }
          final rows = <(String?, ReminderItem?)>[
            for (final entry in groups.entries)
              if (entry.value.isNotEmpty) ...[
                (entry.key, null),
                for (final item in entry.value) (null, item),
              ],
          ];
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final (heading, item) = rows[index];
              if (heading != null) {
                return Padding(
                  padding: const EdgeInsets.only(top: 20, bottom: 8),
                  child: Text(
                    heading,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                );
              }
              final color = switch (item!.entityType) {
                'emi' => AppTheme.colorsOf(context).emi,
                'money' => AppTheme.colorsOf(context).receive,
                _ => AppTheme.colorsOf(context).subscriptions,
              };
              final days = dateOnly(item.dueAt).difference(today).inDays;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(radius: 5, backgroundColor: color),
                title: Text(item.title),
                subtitle: Text(
                  days < 0
                      ? '${-days} days overdue'
                      : days == 0
                      ? 'Due today'
                      : days == 1
                      ? 'Due tomorrow'
                      : 'in $days days',
                ),
                trailing: AmountText(item.amountPaise),
                onTap: () async {
                  if (item.entityType == 'emi') {
                    await Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => EmiDetailScreen(item.entityId),
                      ),
                    );
                  } else if (item.entityType == 'money') {
                    await Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => MoneyDetailScreen(item.entityId),
                      ),
                    );
                  } else {
                    final sub = await repo.subscription(item.entityId);
                    if (context.mounted && sub != null) {
                      openSubscriptionDetailSheet(context, sub);
                    }
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}
