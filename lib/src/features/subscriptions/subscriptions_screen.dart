import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/app_theme.dart';
import '../../core/providers.dart';
import '../../data/database.dart';
import '../../data/repositories.dart';
import '../../domain/due_status.dart';
import '../../domain/enums.dart';
import '../../domain/money_math.dart';
import '../../domain/subscription_schedule.dart';
import '../../shared/async_view.dart';
import '../../shared/empty_state.dart';
import '../../shared/forms.dart';
import '../../shared/finance_form_widgets.dart';
import '../../shared/finance_display_widgets.dart';
import '../../shared/notched_navigation_bar.dart';
import '../../shared/screen_header.dart';
import '../../shared/finance_bottom_sheet.dart';
import '../../shared/calculator_sheet.dart';

final _subscriptionExtrasProvider = StreamProvider<Map<int, SubscriptionExtra>>(
  (ref) {
    final repo = ref.watch(financeRepositoryProvider);
    return repo.db
        .select(repo.db.settings)
        .watch()
        .asyncMap((_) => repo.subscriptionExtras());
  },
);

class SubscriptionsScreen extends ConsumerStatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  ConsumerState<SubscriptionsScreen> createState() =>
      _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends ConsumerState<SubscriptionsScreen> {
  bool _showCancelled = false;

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(financeRepositoryProvider);
    final extras = ref.watch(_subscriptionExtrasProvider).valueOrNull ?? {};
    return Scaffold(
      floatingActionButton: MediaQuery.viewInsetsOf(context).bottom > 0
          ? null
          : Padding(
              padding: EdgeInsets.only(
                bottom: NotchedNavigationMetrics.fabBottomPadding,
              ),
              child: FloatingActionButton.extended(
                onPressed: () =>
                    openFinanceSheet(context, const SubscriptionFormSheet()),
                icon: const Icon(Icons.add),
                label: const Text('Add Subscription'),
              ),
            ),
      body: Column(
        children: [
          ScreenHeader(
            title: const Text('Subscriptions'),
            actions: [
              IconButton(
                tooltip: 'Renewal reminders',
                icon: const Icon(Icons.notifications_active_outlined),
                onPressed: () => _showReminderSettings(context, repo),
              ),
            ],
          ),
          Expanded(
            child: AsyncView(
              value: ref.watch(subscriptionsProvider),
              builder: (items) {
                if (items.isEmpty) {
                  return ListView(
                    padding: EdgeInsets.only(
                      bottom: NotchedNavigationMetrics.tabContentPadding(
                        context,
                      ),
                    ),
                    children: [
                      EmptyState(
                        icon: Icons.autorenew,
                        title: 'No subscriptions',
                        message:
                            'Add your first subscription to keep renewals in view.',
                        actionLabel: 'Add Subscription',
                        onAction: () => openFinanceSheet(
                          context,
                          const SubscriptionFormSheet(),
                        ),
                      ),
                    ],
                  );
                }
                final today = DateTime.now();
                DateTime due(Subscription item) => nextSubscriptionBillingDate(
                  item.nextBillingDate,
                  item.frequency,
                  today,
                );
                final active =
                    items
                        .where(
                          (item) => item.status == SubscriptionStatus.active,
                        )
                        .toList()
                      ..sort((a, b) => due(a).compareTo(due(b)));
                final paused = items
                    .where((item) => item.status == SubscriptionStatus.paused)
                    .toList();
                final cancelled = items
                    .where(
                      (item) =>
                          item.status != SubscriptionStatus.active &&
                          item.status != SubscriptionStatus.paused,
                    )
                    .toList();
                final radar = <(Subscription, DateTime)>[];
                final through = today.add(const Duration(days: 30));
                final monthStart = DateTime(today.year, today.month);
                final monthEnd = DateTime(today.year, today.month + 1, 0);
                var renewed = 0;
                var upcoming = 0;
                for (final item in active) {
                  for (final date in subscriptionOccurrences(
                    item.nextBillingDate,
                    item.frequency,
                    today,
                    through,
                  )) {
                    radar.add((item, date));
                  }
                  for (final date in subscriptionOccurrences(
                    item.nextBillingDate,
                    item.frequency,
                    monthStart,
                    monthEnd,
                  )) {
                    if (date.isBefore(
                      DateTime(today.year, today.month, today.day),
                    )) {
                      renewed += item.amountPaise;
                    } else {
                      upcoming += item.amountPaise;
                    }
                  }
                }
                radar.sort((a, b) => a.$2.compareTo(b.$2));
                final monthly = active.fold<int>(
                  0,
                  (sum, item) =>
                      sum +
                      monthlyEquivalentPaise(item.amountPaise, item.frequency),
                );
                final yearly = monthly * 12;
                final largest = active
                    .where(
                      (item) =>
                          item.frequency != PaymentFrequency.once &&
                          extras[item.id]?.essential != true,
                    )
                    .fold<Subscription?>(
                      null,
                      (best, item) =>
                          best == null ||
                              monthlyEquivalentPaise(
                                    item.amountPaise,
                                    item.frequency,
                                  ) >
                                  monthlyEquivalentPaise(
                                    best.amountPaise,
                                    best.frequency,
                                  )
                          ? item
                          : best,
                    );
                final builders = <WidgetBuilder>[
                  (_) => _SubscriptionHero(
                    monthly: monthly,
                    yearly: yearly,
                    renewed: renewed,
                    upcoming: upcoming,
                  ),
                ];
                if (radar.isNotEmpty) {
                  builders.add((_) => const SizedBox(height: 28));
                  builders.add((_) => const _ListHeading('Next 30 days'));
                  builders.add((_) => const SizedBox(height: 12));
                  builders.add(
                    (_) => _RenewalRadar(
                      events: radar,
                      onOpen: (item) => openFinanceSheet(
                        context,
                        _SubscriptionDetailSheet(
                          item: item,
                          hostContext: context,
                        ),
                      ),
                    ),
                  );
                }
                void addRows(List<Subscription> section) {
                  final grouped = <DueListGroup, List<Subscription>>{};
                  for (final item in section) {
                    grouped
                        .putIfAbsent(dueListGroup(due(item), today), () => [])
                        .add(item);
                  }
                  for (final group in DueListGroup.values) {
                    final groupItems = grouped[group];
                    if (groupItems == null || groupItems.isEmpty) continue;
                    groupItems.sort((a, b) => due(a).compareTo(due(b)));
                    builders.add((_) => DueListHeader(group.label));
                    for (final item in groupItems) {
                      builders.add(
                        (_) => Padding(
                          key: ValueKey('subscription:${item.id}'),
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _SubscriptionRow(
                            item: item,
                            due: due(item),
                            repo: repo,
                            extra: extras[item.id],
                          ),
                        ),
                      );
                    }
                  }
                }

                builders.add((_) => const SizedBox(height: 28));
                builders.add((_) => _ListHeading('Active (${active.length})'));
                if (active.isEmpty) {
                  builders.add(
                    (_) => const _SectionEmpty('No active subscriptions'),
                  );
                } else {
                  addRows(active);
                }
                builders.add((_) => const SizedBox(height: 22));
                builders.add((_) => _ListHeading('Paused (${paused.length})'));
                if (paused.isEmpty) {
                  builders.add((_) => const _SectionEmpty('Nothing paused'));
                } else {
                  addRows(paused);
                }
                if (cancelled.isNotEmpty) {
                  builders.add((_) => const SizedBox(height: 22));
                  builders.add(
                    (_) => InkWell(
                      onTap: () =>
                          setState(() => _showCancelled = !_showCancelled),
                      child: Row(
                        children: [
                          Expanded(
                            child: _ListHeading(
                              'Cancelled (${cancelled.length})',
                            ),
                          ),
                          Icon(
                            _showCancelled
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                          ),
                        ],
                      ),
                    ),
                  );
                  if (_showCancelled) addRows(cancelled);
                }
                if (active
                        .map((item) => item.category ?? 'Other')
                        .toSet()
                        .length >
                    1) {
                  builders.add((_) => const SizedBox(height: 28));
                  builders.add((_) => _CategoryBreakdown(items: active));
                }
                if (largest != null) {
                  builders.add((_) => const SizedBox(height: 20));
                  builders.add(
                    (context) => Text(
                      'Pausing ${displayName(largest.name)} would save ${formatMoney(monthlyEquivalentPaise(largest.amountPaise, largest.frequency) * 12)} a year',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    0,
                    20,
                    NotchedNavigationMetrics.tabContentPadding(context),
                  ),
                  itemCount: builders.length,
                  itemBuilder: (context, index) => builders[index](context),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showReminderSettings(
  BuildContext context,
  FinanceRepository repo,
) async {
  var (threeDays, oneDay) = await repo.subscriptionReminderDays();
  if (!context.mounted) return;
  await showFinanceBottomSheet<void>(
    context,
    builder: (sheet) => StatefulBuilder(
      builder: (context, update) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Renewal reminders',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SwitchListTile.adaptive(
              title: const Text('3 days before'),
              value: threeDays,
              onChanged: (value) => update(() => threeDays = value),
            ),
            SwitchListTile.adaptive(
              title: const Text('1 day before'),
              value: oneDay,
              onChanged: (value) => update(() => oneDay = value),
            ),
            FilledButton(
              onPressed: () async {
                await repo.setSubscriptionReminderDays(
                  threeDays: threeDays,
                  oneDay: oneDay,
                );
                if (sheet.mounted) Navigator.pop(sheet);
              },
              child: const Text('Save reminders'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ListHeading extends StatelessWidget {
  const _ListHeading(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
  );
}

class _SectionEmpty extends StatelessWidget {
  const _SectionEmpty(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Text(
      message,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _RenewalRadar extends StatelessWidget {
  const _RenewalRadar({required this.events, required this.onOpen});
  final List<(Subscription, DateTime)> events;
  final ValueChanged<Subscription> onOpen;

  @override
  Widget build(BuildContext context) {
    final maxAmount = events.fold<int>(
      1,
      (max, event) => event.$1.amountPaise > max ? event.$1.amountPaise : max,
    );
    return SizedBox(
      height: 94,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: events.length,
        separatorBuilder: (_, _) => const SizedBox(width: 4),
        itemBuilder: (context, index) {
          final (item, date) = events[index];
          final color = _categoryColor(context, item.category);
          final diameter = 10 + 14 * item.amountPaise / maxAmount;
          return InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => onOpen(item),
            child: SizedBox(
              width: 82,
              child: Column(
                children: [
                  Text(
                    '${date.day} ${_monthLabel(date)}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 26,
                    child: Center(
                      child: Container(
                        width: diameter,
                        height: diameter,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    displayName(item.name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  Text(
                    formatMoney(item.amountPaise),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

String _monthLabel(DateTime date) => const [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
][date.month - 1];

class _SubscriptionHero extends StatelessWidget {
  const _SubscriptionHero({
    required this.monthly,
    required this.yearly,
    required this.renewed,
    required this.upcoming,
  });
  final int monthly;
  final int yearly;
  final int renewed;
  final int upcoming;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'MONTHLY RECURRING',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          formatMoney(monthly),
          style: theme.textTheme.headlineLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '${formatMoney(yearly)} per year  ·  ${formatMoney((yearly / 365).round())} per day',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            Text(
              'This month',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              '${formatMoney(renewed)} renewed',
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: Row(
              children: [
                if (renewed > 0)
                  Expanded(
                    flex: renewed,
                    child: ColoredBox(
                      color: AppTheme.colorsOf(context).subscriptions,
                    ),
                  ),
                if (upcoming > 0)
                  Expanded(
                    flex: upcoming,
                    child: ColoredBox(
                      color: theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                if (renewed + upcoming == 0)
                  Expanded(
                    child: ColoredBox(
                      color: theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          '${formatMoney(upcoming)} still to come',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _SubscriptionRow extends StatelessWidget {
  const _SubscriptionRow({
    required this.item,
    required this.due,
    required this.repo,
    this.extra,
  });
  final Subscription item;
  final DateTime due;
  final FinanceRepository repo;
  final SubscriptionExtra? extra;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = item.status != SubscriptionStatus.active;
    final color = _categoryColor(context, item.category);
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    final days = due.difference(day).inDays;
    final urgency = days < 0
        ? theme.colorScheme.error
        : days < 7
        ? AppTheme.colorsOf(context).emi
        : AppTheme.colorsOf(context).receive;
    return Dismissible(
      key: ValueKey(item.id),
      background: _swipeBackground(
        theme.colorScheme.primary,
        item.status == SubscriptionStatus.active
            ? Icons.pause
            : Icons.play_arrow,
        item.status == SubscriptionStatus.active ? 'Pause' : 'Resume',
        Alignment.centerLeft,
      ),
      secondaryBackground: _swipeBackground(
        theme.colorScheme.error,
        Icons.delete_outline,
        'Delete',
        Alignment.centerRight,
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          try {
            if (item.status == SubscriptionStatus.active) {
              await repo.pauseSubscription(item.id);
            } else {
              await repo.resumeSubscription(item.id);
            }
          } catch (_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Could not change subscription status'),
                ),
              );
            }
          }
          return false;
        }
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('Delete ${displayName(item.name)}?'),
            content: const Text(
              'This removes the subscription from your tracker.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (confirmed != true) return false;
        try {
          await repo.deleteSubscription(item.id);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${displayName(item.name)} deleted'),
                action: SnackBarAction(
                  label: 'Undo',
                  onPressed: () async {
                    try {
                      await repo.restoreSubscription(item);
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Could not restore subscription'),
                          ),
                        );
                      }
                    }
                  },
                ),
              ),
            );
          }
          return true;
        } catch (_) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not delete subscription')),
            );
          }
          return false;
        }
      },
      child: FinanceTonalTile(
        onTap: () => openFinanceSheet(
          context,
          _SubscriptionDetailSheet(item: item, hostContext: context),
        ),
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: color.withValues(alpha: 0.12),
          child: Text(
            item.name.isEmpty ? '?' : item.name[0].toUpperCase(),
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              displayName(item.name),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: muted ? theme.colorScheme.onSurfaceVariant : null,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '${item.category?.isNotEmpty == true ? item.category : 'Other'} · ${item.frequency.label}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: StatusPill(
                label: item.status == SubscriptionStatus.active
                    ? relativeDueText(due, today)
                    : item.status.label,
                color: item.status == SubscriptionStatus.active
                    ? urgency
                    : AppTheme.colorsOf(context).secondaryText,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              formatDate(due),
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppTheme.colorsOf(context).secondaryText,
              ),
            ),
            if (item.status == SubscriptionStatus.paused)
              TextButton.icon(
                onPressed: () => repo.resumeSubscription(item.id),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(72, 32),
                ),
                icon: const Icon(Icons.play_arrow, size: 16),
                label: const Text('Resume'),
              ),
            if (item.status == SubscriptionStatus.cancelled)
              Text(
                'Saved ${formatMoney(monthlyEquivalentPaise(item.amountPaise, item.frequency) * 12)}/year',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        trailing: SizedBox(
          width: 86,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: AmountText(
                  item.amountPaise,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: muted ? theme.colorScheme.onSurfaceVariant : null,
                  ),
                ),
              ),
              const SizedBox(height: 7),
              MiniProgressRing(
                progress: item.status == SubscriptionStatus.active
                    ? 1 - days.clamp(0, 30) / 30
                    : 0,
                size: 42,
                strokeWidth: 3,
                child: Center(
                  child: Text(
                    item.status != SubscriptionStatus.active
                        ? '—'
                        : days < 0
                        ? '!'
                        : days > 99
                        ? '99+'
                        : '${days}d',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _swipeBackground(
    Color color,
    IconData icon,
    String label,
    Alignment alignment,
  ) => Container(
    color: color.withValues(alpha: 0.12),
    alignment: alignment,
    padding: const EdgeInsets.symmetric(horizontal: 22),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _SubscriptionDetailSheet extends ConsumerWidget {
  const _SubscriptionDetailSheet({
    required this.item,
    required this.hostContext,
  });
  final Subscription item;
  final BuildContext hostContext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final extra =
        ref.watch(_subscriptionExtrasProvider).valueOrNull?[item.id] ??
        const SubscriptionExtra();
    final repo = ref.read(financeRepositoryProvider);
    final today = DateTime.now();
    final due = nextSubscriptionBillingDate(
      item.nextBillingDate,
      item.frequency,
      today,
    );
    final paidCycles = subscriptionOccurrences(
      item.nextBillingDate,
      item.frequency,
      item.createdAt,
      DateTime(today.year, today.month, today.day - 1),
    ).length;
    final estimatedPaid = paidCycles * item.amountPaise;
    final daily =
        (monthlyEquivalentPaise(item.amountPaise, item.frequency) * 12 / 365)
            .round();
    final reviewAt = DateTime(
      item.createdAt.year,
      item.createdAt.month + 6,
      item.createdAt.day,
    );
    return FractionallySizedBox(
      heightFactor: .86,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: _categoryColor(
                      context,
                      item.category,
                    ).withValues(alpha: .14),
                    child: Text(
                      item.name[0].toUpperCase(),
                      style: TextStyle(
                        color: _categoryColor(context, item.category),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      displayName(item.name),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                formatMoney(item.amountPaise),
                style: theme.textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'per ${item.frequency.label.toLowerCase()}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: ListView(
                  children: [
                    _DetailFigure('Next billing', formatDate(due)),
                    _DetailFigure(
                      'Estimated paid since added',
                      formatMoney(estimatedPaid),
                    ),
                    _DetailFigure('Cost per day', formatMoney(daily)),
                    if (extra.pauseUntil != null)
                      _DetailFigure(
                        'Paused until',
                        formatDate(extra.pauseUntil!),
                      ),
                    if (extra.cancelAt != null)
                      _DetailFigure(
                        'Cancels at cycle end',
                        formatDate(extra.cancelAt!),
                      ),
                    if (extra.trialEndsOn != null)
                      _DetailFigure(
                        'Trial ends',
                        formatDate(extra.trialEndsOn!),
                      ),
                    if (extra.priceHistory.isNotEmpty) ...[
                      const _ListHeading('Price history'),
                      for (final change in extra.priceHistory.reversed)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Text(
                            '${formatDate(change.at)} · ${formatMoney(change.fromPaise)} → ${formatMoney(change.toPaise)}',
                          ),
                        ),
                    ],
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Mark as essential'),
                      value: extra.essential,
                      onChanged: (value) => repo.saveSubscriptionExtra(
                        item.id,
                        extra.copyWith(essential: value),
                      ),
                    ),
                    if (!extra.reviewed &&
                        !today.isBefore(reviewAt) &&
                        item.status == SubscriptionStatus.active)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Still using ${displayName(item.name)}? You\'ve paid about ${formatMoney(estimatedPaid)}.',
                              style: theme.textTheme.bodyMedium,
                            ),
                            Wrap(
                              spacing: 8,
                              children: [
                                TextButton(
                                  onPressed: () => repo.saveSubscriptionExtra(
                                    item.id,
                                    extra.copyWith(reviewed: true),
                                  ),
                                  child: const Text('Keep'),
                                ),
                                TextButton(
                                  onPressed: () => _pause(context, repo),
                                  child: const Text('Pause'),
                                ),
                                TextButton(
                                  onPressed: () => _cancel(context, repo),
                                  child: const Text('Cancel'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: item.status == SubscriptionStatus.paused
                          ? () async {
                              await repo.resumeSubscription(item.id);
                              if (context.mounted) {
                                Navigator.pop(context);
                              }
                            }
                          : item.status == SubscriptionStatus.cancelled
                          ? () async {
                              await repo.resumeSubscription(item.id);
                              if (context.mounted) Navigator.pop(context);
                            }
                          : () => _pause(context, repo),
                      icon: Icon(
                        item.status == SubscriptionStatus.active
                            ? Icons.pause_outlined
                            : Icons.play_arrow,
                      ),
                      label: Text(
                        item.status == SubscriptionStatus.paused
                            ? 'Resume'
                            : item.status == SubscriptionStatus.cancelled
                            ? 'Reactivate'
                            : 'Pause',
                      ),
                    ),
                  ),
                  if (item.status != SubscriptionStatus.cancelled) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () => _cancel(context, repo),
                        icon: const Icon(Icons.block_outlined),
                        label: const Text('Cancel'),
                      ),
                    ),
                  ],
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => _delete(context, repo),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete'),
                    ),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () async {
                        Navigator.pop(context);
                        await Future<void>.delayed(AppTheme.motionDuration);
                        if (hostContext.mounted) {
                          openFinanceSheet(
                            hostContext,
                            SubscriptionFormSheet(subscription: item),
                          );
                        }
                      },
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pause(BuildContext context, FinanceRepository repo) async {
    final result = await _pauseChoice(context);
    if (result == null) return;
    await repo.pauseSubscription(item.id, until: result.until);
    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _cancel(BuildContext context, FinanceRepository repo) async {
    final result = await _cancelChoice(context, item);
    if (result == null) return;
    await repo.cancelSubscription(
      item.id,
      atCycleEnd: result.atCycleEnd,
      reason: result.reason,
    );
    if (!context.mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(hostContext).showSnackBar(
      SnackBar(
        content: Text(
          'You\'ll save ${formatMoney(monthlyEquivalentPaise(item.amountPaise, item.frequency) * 12)} a year',
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context, FinanceRepository repo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Delete ${displayName(item.name)}?'),
        content: const Text('Move this subscription to Deleted?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await repo.deleteSubscription(item.id);
    if (context.mounted) Navigator.pop(context);
    if (hostContext.mounted) {
      ScaffoldMessenger.of(hostContext).showSnackBar(
        SnackBar(
          content: Text('${displayName(item.name)} moved to Deleted'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => repo.restoreSubscription(item),
          ),
        ),
      );
    }
  }
}

class _DetailFigure extends StatelessWidget {
  const _DetailFigure(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

Future<({DateTime? until})?> _pauseChoice(BuildContext context) {
  final now = DateTime.now();
  return showModalBottomSheet<({DateTime? until})>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheet) => Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Pause until', style: Theme.of(sheet).textTheme.titleLarge),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                label: const Text('1 month'),
                onPressed: () => Navigator.pop(sheet, (
                  until: DateTime(now.year, now.month + 1, now.day),
                )),
              ),
              ActionChip(
                label: const Text('3 months'),
                onPressed: () => Navigator.pop(sheet, (
                  until: DateTime(now.year, now.month + 3, now.day),
                )),
              ),
              ActionChip(
                label: const Text('Custom'),
                onPressed: () async {
                  final date = await pickAppDate(sheet, now);
                  if (sheet.mounted && date != null) {
                    Navigator.pop(sheet, (until: date));
                  }
                },
              ),
              ActionChip(
                label: const Text('No end date'),
                onPressed: () => Navigator.pop(sheet, (until: null)),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

Future<({bool atCycleEnd, String? reason})?> _cancelChoice(
  BuildContext context,
  Subscription item,
) {
  String? reason;
  final due = nextSubscriptionBillingDate(
    item.nextBillingDate,
    item.frequency,
    DateTime.now(),
  );
  return showModalBottomSheet<({bool atCycleEnd, String? reason})>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheet) => StatefulBuilder(
      builder: (context, update) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Cancel ${displayName(item.name)}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Text(
              'Save ${formatMoney(monthlyEquivalentPaise(item.amountPaise, item.frequency) * 12)} a year',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in const [
                  'Too expensive',
                  'Not using',
                  'Switched',
                  'Other',
                ])
                  ChoiceChip(
                    label: Text(option),
                    selected: reason == option,
                    onSelected: (_) => update(() => reason = option),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(sheet, (atCycleEnd: false, reason: reason)),
              child: const Text('Cancel now'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(sheet, (atCycleEnd: true, reason: reason)),
              child: Text('Cancel at end of this cycle (${formatDate(due)})'),
            ),
          ],
        ),
      ),
    ),
  );
}

Color _categoryColor(BuildContext context, String? category) => switch (category
    ?.toLowerCase()) {
  'entertainment' || 'streaming' => AppTheme.colorsOf(context).subscriptions,
  'utilities' => AppTheme.colorsOf(context).emi,
  'education' => AppTheme.colorsOf(context).receive,
  'software' => Theme.of(context).colorScheme.primary,
  _ => Theme.of(context).colorScheme.primary,
};

class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({required this.items});
  final List<Subscription> items;

  @override
  Widget build(BuildContext context) {
    final totals = <String, int>{};
    for (final item in items) {
      final category = item.category?.isNotEmpty == true
          ? item.category!
          : 'Other';
      totals.update(
        category,
        (value) =>
            value + monthlyEquivalentPaise(item.amountPaise, item.frequency),
        ifAbsent: () =>
            monthlyEquivalentPaise(item.amountPaise, item.frequency),
      );
    }
    totals.removeWhere((_, value) => value <= 0);
    final total = totals.values.fold<int>(0, (sum, value) => sum + value);
    if (total == 0) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _ListHeading('By category'),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: Row(
              children: [
                for (final entry in totals.entries)
                  Expanded(
                    flex: entry.value,
                    child: ColoredBox(
                      color: _categoryColor(context, entry.key),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            for (final entry in totals.entries)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 4,
                    backgroundColor: _categoryColor(context, entry.key),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    entry.key,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class SubscriptionFormSheet extends ConsumerStatefulWidget {
  const SubscriptionFormSheet({
    super.key,
    this.subscription,
    this.initialAmount,
    this.initialName,
    this.initialFrequency,
    this.initialNextBillingDate,
  });

  final Subscription? subscription;
  final String? initialAmount;
  final String? initialName;
  final PaymentFrequency? initialFrequency;
  final DateTime? initialNextBillingDate;

  @override
  ConsumerState<SubscriptionFormSheet> createState() =>
      _SubscriptionFormSheetState();
}

class _SubscriptionFormSheetState extends ConsumerState<SubscriptionFormSheet> {
  final _formKey = GlobalKey<FormState>();
  SubscriptionExtra _extra = const SubscriptionExtra();
  DateTime? _trialEndsOn;
  bool _essential = false;
  late final _name = TextEditingController(
    text: widget.subscription?.name ?? widget.initialName ?? '',
  );
  late final _amount = TextEditingController(
    text:
        widget.initialAmount ??
        (widget.subscription == null
            ? ''
            : rupeesText(widget.subscription!.amountPaise)),
  );
  late String _category = widget.subscription?.category ?? '';
  late final _notes = TextEditingController(
    text: widget.subscription?.notes ?? '',
  );
  late DateTime _next =
      widget.subscription?.nextBillingDate ??
      widget.initialNextBillingDate ??
      DateTime.now();
  late PaymentFrequency _frequency =
      widget.subscription?.frequency ??
      widget.initialFrequency ??
      PaymentFrequency.monthly;
  late SubscriptionStatus _status =
      widget.subscription?.status ?? SubscriptionStatus.active;
  String? _saveError;
  Animation<double>? _routeAnimation;
  bool _extraLoadStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.subscription == null || _extraLoadStarted) return;
    final animation = ModalRoute.of(context)?.animation;
    if (_routeAnimation != animation) {
      _routeAnimation?.removeStatusListener(_onSheetAnimationStatus);
      _routeAnimation = animation;
      animation?.addStatusListener(_onSheetAnimationStatus);
    }
    if (animation == null || animation.status == AnimationStatus.completed) {
      _startExtraLoad();
    }
  }

  void _onSheetAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _startExtraLoad();
  }

  void _startExtraLoad() {
    if (_extraLoadStarted) return;
    _extraLoadStarted = true;
    _routeAnimation?.removeStatusListener(_onSheetAnimationStatus);
    unawaited(_loadExtra());
  }

  Future<void> _loadExtra() async {
    try {
      final value = await ref
          .read(financeRepositoryProvider)
          .subscriptionExtra(widget.subscription!.id);
      if (!mounted) return;
      setState(() {
        _extra = value;
        _trialEndsOn = value.trialEndsOn;
        _essential = value.essential;
      });
    } catch (error) {
      debugPrint('Subscription extras could not be loaded: $error');
    }
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_onSheetAnimationStatus);
    _name.dispose();
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final frequencySegments = <ButtonSegment<PaymentFrequency>>[
      for (final frequency in const [
        PaymentFrequency.weekly,
        PaymentFrequency.monthly,
        PaymentFrequency.quarterly,
        PaymentFrequency.yearly,
      ])
        ButtonSegment(value: frequency, label: Text(frequency.label)),
      if (_frequency == PaymentFrequency.once)
        const ButtonSegment(value: PaymentFrequency.once, label: Text('Once')),
    ];
    final statusSegments = <ButtonSegment<SubscriptionStatus>>[
      const ButtonSegment(
        value: SubscriptionStatus.active,
        label: Text('Active'),
      ),
      const ButtonSegment(
        value: SubscriptionStatus.paused,
        label: Text('Paused'),
      ),
      if (_status != SubscriptionStatus.active &&
          _status != SubscriptionStatus.paused)
        ButtonSegment(value: _status, label: Text(_status.label)),
    ];
    final categoryLabels = <String>[
      'Entertainment',
      'Music',
      'Cloud',
      'Utilities',
      'Education',
      'Other',
      if (_category.isNotEmpty &&
          !_categoryLabels.contains(_labelForCategoryValue(_category)))
        _category,
      'Not set',
    ];
    final selectedCategory = _labelForCategoryValue(_category);
    return FractionallySizedBox(
      heightFactor: 0.92,
      child: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.subscription == null
                            ? 'Add Subscription'
                            : 'Edit Subscription',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    const SizedBox(height: 4),
                    HeroAmountInput(
                      controller: _amount,
                      label: 'AMOUNT',
                      validator: _validateAmount,
                      calculator: () async {
                        final value = await openCalculator(
                          context,
                          initial: _amount.text,
                          amountLabel: 'Amount',
                        );
                        if (mounted && value != null) {
                          setState(() => _amount.text = value);
                        }
                      },
                    ),
                    const SizedBox(height: 24),
                    FilledField(
                      label: 'NAME *',
                      child: TextFormField(
                        controller: _name,
                        decoration: financeFieldDecoration(
                          context,
                          hint: 'Subscription name',
                          icon: Icons.autorenew,
                        ),
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        validator: (value) => requiredText(value) == null
                            ? null
                            : 'Enter a subscription name',
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledField(
                      label: 'FREQUENCY',
                      child: SegmentedToggle<PaymentFrequency>(
                        segments: frequencySegments,
                        selected: {_frequency},
                        filled: true,
                        onSelectionChanged: (values) =>
                            setState(() => _frequency = values.single),
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledField(
                      label: 'STATUS',
                      child: SizedBox(
                        width: double.infinity,
                        child: SegmentedToggle<SubscriptionStatus>(
                          segments: statusSegments,
                          selected: {_status},
                          filled: true,
                          onSelectionChanged: (values) =>
                              setState(() => _status = values.single),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    DateTile(
                      label: 'NEXT BILLING DATE',
                      value: _next,
                      onChanged: (value) {
                        if (value != null) setState(() => _next = value);
                      },
                    ),
                    const SizedBox(height: 24),
                    const FinanceFieldLabel('CATEGORY'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final label in categoryLabels)
                          ChoiceChip(
                            label: Text(label),
                            selected: selectedCategory == label,
                            selectedColor: financeSelectedFill(context),
                            onSelected: (_) => setState(
                              () => _category = _valueForCategoryLabel(label),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    DateTile(
                      label: 'TRIAL ENDS ON (OPTIONAL)',
                      value: _trialEndsOn,
                      allowClear: true,
                      onChanged: (value) =>
                          setState(() => _trialEndsOn = value),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Mark as essential'),
                      value: _essential,
                      onChanged: (value) => setState(() => _essential = value),
                    ),
                    const SizedBox(height: 24),
                    FilledField(
                      label: 'NOTES',
                      child: TextFormField(
                        controller: _notes,
                        decoration: financeFieldDecoration(
                          context,
                          hint: 'Optional notes',
                        ),
                        keyboardType: TextInputType.multiline,
                        autofocus: false,
                        minLines: 2,
                        maxLines: 5,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_saveError != null) ...[
                      Text(_saveError!, style: TextStyle(color: colors.error)),
                      const SizedBox(height: 8),
                    ],
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        shape: const StadiumBorder(),
                        minimumSize: const Size.fromHeight(54),
                      ),
                      onPressed: _save,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(
                        widget.subscription == null
                            ? 'Save Subscription'
                            : 'Save Changes',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _categoryLabels = [
    'Entertainment',
    'Music',
    'Cloud',
    'Utilities',
    'Education',
    'Other',
  ];

  String _labelForCategoryValue(String value) => switch (value) {
    'Streaming' => 'Music',
    'Software' => 'Cloud',
    '' => 'Not set',
    _ when _categoryLabels.contains(value) => value,
    _ => value,
  };

  String _valueForCategoryLabel(String label) => switch (label) {
    'Music' => 'Streaming',
    'Cloud' => 'Software',
    'Not set' => '',
    _ => label,
  };

  String? _validateAmount(String? value) {
    if (value == null || value.trim().isEmpty) return 'Enter an amount';
    final amount = double.tryParse(value.replaceAll(',', '').trim());
    if (amount == null ||
        !amount.isFinite ||
        amount <= 0 ||
        !(amount * 100).isFinite ||
        (amount * 100).round() <= 0) {
      return 'Enter an amount greater than zero';
    }
    return null;
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    try {
      final item = SubscriptionsCompanion(
        id: widget.subscription == null
            ? const Value.absent()
            : Value(widget.subscription!.id),
        name: Value(_name.text.trim()),
        amountPaise: Value(parseRupeesToPaise(_amount.text)),
        frequency: Value(_frequency),
        nextBillingDate: Value(_next),
        category: Value(_category.isEmpty ? null : _category),
        status: Value(_status),
        notes: Value(_notes.text.trim().isEmpty ? null : _notes.text.trim()),
        updatedAt: Value(DateTime.now()),
      );
      final repo = ref.read(financeRepositoryProvider);
      closeFinanceSheetAndSave(context, () async {
        final id = await repo.saveSubscription(item);
        await repo.saveSubscriptionExtra(
          id,
          _extra.copyWith(
            trialEndsOn: _trialEndsOn,
            clearTrialEndsOn: _trialEndsOn == null,
            essential: _essential,
          ),
        );
      }, errorMessage: 'Could not save subscription. Please try again.');
    } on FormatException catch (error) {
      setState(() => _saveError = error.message);
    }
  }
}
