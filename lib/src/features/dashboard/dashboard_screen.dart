import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/formatters.dart';
import '../../core/providers.dart';
import '../../data/repositories.dart';
import '../../data/database.dart';
import '../../domain/enums.dart';
import '../../shared/calculator_sheet.dart';
import '../../shared/empty_state.dart';
import '../../shared/finance_display_widgets.dart';
import '../../shared/forms.dart';
import '../../shared/notched_navigation_bar.dart';
import '../../shared/screen_header.dart';
import '../activity/activity_screen.dart';
import '../assistant/ask_finkeep_sheet.dart';
import '../emis/emis_screen.dart';
import '../money/money_screen.dart';
import '../settings/backup_settings_section.dart';
import '../settings/settings_screen.dart';
import '../reminders/reminders_screen.dart';
import '../subscriptions/subscriptions_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _actionsExpanded = false;

  @override
  Widget build(BuildContext context) {
    ref.watch(privacyModeProvider);
    final summary = ref.watch(dashboardProvider);
    final emis = ref.watch(emiDetailsProvider);
    final actions = ref.watch(financialActionsProvider);
    final activity = ref.watch(dashboardActivityProvider);
    final records = ref.watch(moneyRecordsProvider);
    final subscriptions = ref.watch(subscriptionsProvider);
    return Scaffold(
      floatingActionButton: MediaQuery.viewInsetsOf(context).bottom > 0
          ? null
          : Padding(
              padding: EdgeInsets.only(
                bottom: NotchedNavigationMetrics.fabBottomPadding,
              ),
              child: _buildAddMenu(context),
            ),
      body: Stack(
        children: [
          Positioned.fill(
            child: summary.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(
                child: EmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: 'Dashboard unavailable',
                  message: 'Your local finance data could not be loaded.',
                ),
              ),
              data: (data) {
                final noFinanceData =
                    (emis.valueOrNull?.isEmpty ?? false) &&
                    (records.valueOrNull?.isEmpty ?? false) &&
                    (subscriptions.valueOrNull?.isEmpty ?? false);
                return ListView(
                  padding: EdgeInsets.only(
                    bottom: NotchedNavigationMetrics.tabContentPadding(context),
                  ),
                  children: [
                    _DashboardHeader(
                      onAsk: () => openAskFinKeep(context),
                      private: ref.watch(privacyModeProvider).enabled,
                      onPrivacy: () => ref
                          .read(privacyModeProvider.notifier)
                          .setEnabled(!ref.read(privacyModeProvider).enabled),
                      onSettings: () => openSettings(context),
                    ),
                    BackupReminderBanner(
                      onBackUp: () async {
                        try {
                          await showCreateBackupFlow(context, ref);
                        } on FormatException catch (error) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(error.message.toString())),
                            );
                          }
                        } catch (_) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Could not save the backup.'),
                              ),
                            );
                          }
                        }
                      },
                    ),
                    if (noFinanceData)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(24, 36, 24, 32),
                        child: EmptyState(
                          icon: Icons.savings_outlined,
                          title: 'Your money overview starts here',
                          message:
                              'Add an EMI, money record, or subscription to see your financial picture.',
                        ),
                      )
                    else ...[
                      _BalanceHero(
                        incoming: data.comingToMePaise,
                        payable: data.needToPayPaise,
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 26, 20, 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _OutflowSection(summary: data),
                            const SizedBox(height: 32),
                            actions.when(
                              data: (items) => _ThirtyDayTimeline(
                                items: items,
                                dueInSevenDays: data.upcomingPayments,
                                subscriptionsInFourteenDays:
                                    data.upcomingSubscriptions,
                              ),
                              error: (_, _) => const SizedBox.shrink(),
                              loading: () => const SizedBox.shrink(),
                            ),
                            const SizedBox(height: 32),
                            emis.when(
                              data: (items) =>
                                  _EmiProgressSection(items: items),
                              error: (_, _) => const SizedBox.shrink(),
                              loading: () => const SizedBox.shrink(),
                            ),
                            const SizedBox(height: 28),
                            _Insights(
                              summary: data,
                              actions: actions.valueOrNull ?? const [],
                              records: records.valueOrNull ?? const [],
                            ),
                            const SizedBox(height: 28),
                            _NextActions(
                              items: actions.valueOrNull ?? const [],
                            ),
                            const SizedBox(height: 28),
                            _RecentActivity(
                              items: activity.valueOrNull ?? const [],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
          if (_actionsExpanded)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _actionsExpanded = false),
                child: ColoredBox(
                  color: Theme.of(
                    context,
                  ).colorScheme.scrim.withValues(alpha: 0.38),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openCalculator() => openCalculator(
    context,
    onEmiDraft: (draft) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        openFinanceSheet(
          context,
          EmiFormSheet(
            initialEmiAmount: draft.monthlyEmi.toStringAsFixed(2),
            initialPrincipal: draft.principal.toStringAsFixed(2),
            initialInterestRate: draft.annualRate.toString(),
            initialTenureMonths: draft.months,
          ),
        );
      });
    },
    onDestination: (destination, amount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        switch (destination) {
          case CalculatorDestination.emi:
            openFinanceSheet(context, EmiFormSheet(initialEmiAmount: amount));
          case CalculatorDestination.moneyGiven:
            openFinanceSheet(
              context,
              MoneyFormSheet(
                initialAmount: amount,
                initialDirection: MoneyDirection.given,
              ),
            );
          case CalculatorDestination.moneyBorrowed:
            openFinanceSheet(
              context,
              MoneyFormSheet(
                initialAmount: amount,
                initialDirection: MoneyDirection.borrowed,
              ),
            );
          case CalculatorDestination.subscription:
            openFinanceSheet(
              context,
              SubscriptionFormSheet(initialAmount: amount),
            );
        }
      });
    },
  );

  void _closeMenuThen(VoidCallback action) {
    setState(() => _actionsExpanded = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) action();
    });
  }

  Widget _buildAddMenu(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      if (_actionsExpanded) ...[
        _AddAction(
          label: 'Calculator',
          icon: Icons.calculate_outlined,
          onTap: () => _closeMenuThen(_openCalculator),
        ),
        const SizedBox(height: 10),
        _AddAction(
          label: 'Add Subscription',
          icon: Icons.autorenew,
          onTap: () => _closeMenuThen(
            () => openFinanceSheet(context, const SubscriptionFormSheet()),
          ),
        ),
        const SizedBox(height: 10),
        _AddAction(
          label: 'Add Money',
          icon: Icons.swap_horiz,
          onTap: () => _closeMenuThen(
            () => openFinanceSheet(context, const MoneyFormSheet()),
          ),
        ),
        const SizedBox(height: 10),
        _AddAction(
          label: 'Add EMI',
          icon: Icons.account_balance_outlined,
          onTap: () => _closeMenuThen(
            () => openFinanceSheet(context, const EmiFormSheet()),
          ),
        ),
        const SizedBox(height: 12),
      ],
      FloatingActionButton(
        tooltip: _actionsExpanded ? 'Close add menu' : 'Add finance item',
        onPressed: () => setState(() => _actionsExpanded = !_actionsExpanded),
        child: Icon(_actionsExpanded ? Icons.close : Icons.add),
      ),
    ],
  );
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.onAsk,
    required this.onPrivacy,
    required this.onSettings,
    required this.private,
  });

  final VoidCallback onAsk;
  final VoidCallback onPrivacy;
  final VoidCallback onSettings;
  final bool private;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final hour = now.hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    return ScreenHeader(
      horizontalPadding: 22,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'FinKeep',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppTheme.colorsOf(context).text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Local-first money clarity',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppTheme.colorsOf(context).secondaryText,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '$greeting · ${formatDate(now)}',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: private ? 'Show amounts' : 'Hide amounts',
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          onPressed: onPrivacy,
          icon: Icon(
            private ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          ),
        ),
        IconButton(
          tooltip: 'Settings',
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          onPressed: onSettings,
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
      bottom: _AskSearchStrip(onTap: onAsk),
    );
  }
}

class _AskSearchStrip extends StatefulWidget {
  const _AskSearchStrip({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_AskSearchStrip> createState() => _AskSearchStripState();
}

class _AskSearchStripState extends State<_AskSearchStrip> {
  static const _prompts = [
    "Ask: what's due this week?",
    'Ask: who owes me money?',
    'Ask: analyze my portfolio',
  ];
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? true)) {
        setState(() => _index = (_index + 1) % _prompts.length);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: widget.onTap,
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: Row(
            children: [
              const SizedBox(width: 16),
              Icon(
                Icons.auto_awesome_outlined,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AnimatedSwitcher(
                  duration: AppTheme.motionDuration,
                  child: Align(
                    key: ValueKey(_index),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _prompts[_index],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _BalanceHero extends StatelessWidget {
  const _BalanceHero({required this.incoming, required this.payable});

  final int incoming;
  final int payable;

  @override
  Widget build(BuildContext context) {
    final net = incoming - payable;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.heroStart, AppTheme.heroEnd],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
        border: Theme.of(context).brightness == Brightness.dark
            ? Border.all(color: AppTheme.darkColors.outline, width: 1)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'NET POSITION',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppTheme.heroTextOf(context).withValues(alpha: 0.76),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 9),
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: 0, end: net),
            duration: const Duration(milliseconds: 650),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => Text(
              formatMoney(value),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: AppTheme.heroTextOf(context),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              SizedBox(
                width: 96,
                height: 96,
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _BalanceRingPainter(
                      incoming: incoming,
                      payable: payable,
                      receive: AppTheme.colorsOf(context).receive,
                      pay: AppTheme.colorsOf(context).pay,
                      track: AppTheme.heroTextOf(
                        context,
                      ).withValues(alpha: 0.18),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.account_balance_wallet_outlined,
                        color: AppTheme.heroTextOf(
                          context,
                        ).withValues(alpha: 0.88),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 22),
              Expanded(
                child: Column(
                  children: [
                    _HeroLegend(
                      color: AppTheme.colorsOf(context).receive,
                      label: 'Coming to me',
                      value: incoming,
                    ),
                    const SizedBox(height: 16),
                    _HeroLegend(
                      color: AppTheme.colorsOf(context).pay,
                      label: 'I need to pay',
                      value: payable,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            'Position reflects outstanding Money records; recurring commitments are shown below.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppTheme.heroTextOf(context).withValues(alpha: 0.72),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroLegend extends StatelessWidget {
  const _HeroLegend({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppTheme.heroMutedOf(context)),
        ),
      ),
      TweenAnimationBuilder<int>(
        tween: IntTween(begin: 0, end: value),
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOutCubic,
        builder: (context, animated, _) => Text(
          formatMoney(animated),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: AppTheme.heroTextOf(context),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );
}

class _BalanceRingPainter extends CustomPainter {
  const _BalanceRingPainter({
    required this.incoming,
    required this.payable,
    required this.receive,
    required this.pay,
    required this.track,
  });

  final int incoming;
  final int payable;
  final Color receive, pay, track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      rect.deflate(7),
      -math.pi / 2,
      math.pi * 2,
      false,
      stroke..color = track,
    );
    final total = incoming + payable;
    if (total <= 0) return;
    final greenSweep = math.pi * 2 * incoming / total;
    canvas.drawArc(
      rect.deflate(7),
      -math.pi / 2,
      greenSweep,
      false,
      stroke..color = receive,
    );
    canvas.drawArc(
      rect.deflate(7),
      -math.pi / 2 + greenSweep,
      math.pi * 2 - greenSweep,
      false,
      stroke..color = pay,
    );
  }

  @override
  bool shouldRepaint(covariant _BalanceRingPainter oldDelegate) =>
      oldDelegate.incoming != incoming ||
      oldDelegate.payable != payable ||
      oldDelegate.receive != receive ||
      oldDelegate.pay != pay ||
      oldDelegate.track != track;
}

class _OutflowSection extends StatelessWidget {
  const _OutflowSection({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final parts = <(String, int, Color)>[
      ('EMI', summary.monthlyEmisPaise, AppTheme.colorsOf(context).emi),
      (
        'Subscriptions',
        summary.monthlySubscriptionsPaise,
        AppTheme.colorsOf(context).subscriptions,
      ),
      (
        'Money due',
        summary.monthlyMoneyToPayPaise,
        AppTheme.colorsOf(context).pay,
      ),
    ];
    final total = parts.fold<int>(0, (sum, item) => sum + item.$2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          'Monthly outflow',
          detail: '30-day view · dated money due included',
        ),
        const SizedBox(height: 4),
        Text(
          formatMoney(total),
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: SizedBox(
            height: 14,
            child: total == 0
                ? ColoredBox(color: AppTheme.colorsOf(context).fieldFill)
                : Row(
                    children: [
                      for (final part in parts.where((item) => item.$2 > 0))
                        Expanded(
                          flex: part.$2,
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: 1),
                            duration: const Duration(milliseconds: 500),
                            builder: (context, value, _) =>
                                FractionallySizedBox(
                                  widthFactor: value,
                                  alignment: Alignment.centerLeft,
                                  child: ColoredBox(color: part.$3),
                                ),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 18,
          runSpacing: 10,
          children: [
            for (final part in parts)
              _OutflowLegend(
                label: part.$1,
                amount: part.$2,
                total: total,
                color: part.$3,
              ),
          ],
        ),
      ],
    );
  }
}

class _OutflowLegend extends StatelessWidget {
  const _OutflowLegend({
    required this.label,
    required this.amount,
    required this.total,
    required this.color,
  });

  final String label;
  final int amount;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final percent = total == 0 ? 0 : (amount * 100 / total).round();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          '$label $percent%',
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _ThirtyDayTimeline extends StatefulWidget {
  const _ThirtyDayTimeline({
    required this.items,
    required this.dueInSevenDays,
    required this.subscriptionsInFourteenDays,
  });

  final List<ReminderItem> items;
  final int dueInSevenDays;
  final int subscriptionsInFourteenDays;

  @override
  State<_ThirtyDayTimeline> createState() => _ThirtyDayTimelineState();
}

class _ThirtyDayTimelineState extends State<_ThirtyDayTimeline> {
  DateTime _selected = _today();
  bool _showOverdue = false;

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  Widget build(BuildContext context) {
    final today = _today();
    final overdue = widget.items
        .where((item) => item.status == ReminderStatus.overdue)
        .toList();
    final upcoming = widget.items.where((item) {
      final day = DateTime(item.dueAt.year, item.dueAt.month, item.dueAt.day);
      return !day.isBefore(today) &&
          day.difference(today).inDays < 30 &&
          item.status != ReminderStatus.completed;
    }).toList();
    final selectedItems = _showOverdue
        ? overdue
        : widget.items
              .where(
                (item) =>
                    item.status != ReminderStatus.completed &&
                    item.dueAt.year == _selected.year &&
                    item.dueAt.month == _selected.month &&
                    item.dueAt.day == _selected.day,
              )
              .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: _SectionTitle(
                'Coming up',
                detail: 'Next 30 days · red items are overdue',
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const RemindersScreen(),
                ),
              ),
              child: const Text('See all'),
            ),
          ],
        ),
        const SizedBox(height: 13),
        Row(
          children: [
            Expanded(
              child: _WindowCount(
                count: widget.dueInSevenDays,
                label: 'Due incl. overdue · 7 days',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _WindowCount(
                count: widget.subscriptionsInFourteenDays,
                label: 'Subscriptions incl. overdue · 14 days',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 72,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              if (overdue.isNotEmpty)
                _DayPill(
                  label: 'Overdue',
                  count: overdue.length,
                  selected: false,
                  dotColors: [AppTheme.colorsOf(context).pay],
                  onTap: () => setState(() => _showOverdue = true),
                ),
              for (var offset = 0; offset < 30; offset++)
                Builder(
                  builder: (context) {
                    final day = today.add(Duration(days: offset));
                    final dayItems = upcoming
                        .where(
                          (item) =>
                              item.dueAt.year == day.year &&
                              item.dueAt.month == day.month &&
                              item.dueAt.day == day.day,
                        )
                        .toList();
                    return _DayPill(
                      label: offset == 0
                          ? 'Today'
                          : '${day.day} ${_monthShort(day.month)}',
                      count: dayItems.length,
                      selected:
                          day.year == _selected.year &&
                          day.month == _selected.month &&
                          day.day == _selected.day,
                      dotColors: dayItems
                          .map((item) => _actionColor(context, item))
                          .toSet()
                          .toList(),
                      onTap: () => setState(() {
                        _selected = day;
                        _showOverdue = false;
                      }),
                    );
                  },
                ),
            ],
          ),
        ),
        if (selectedItems.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final item in selectedItems) _CompactDueRow(item: item),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              selectedItems.isEmpty && _selected.isBefore(today)
                  ? 'No upcoming items on this day.'
                  : 'Nothing due ${_selected == today ? 'today' : 'on this day'}.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.colorsOf(context).secondaryText,
              ),
            ),
          ),
      ],
    );
  }
}

class _WindowCount extends StatelessWidget {
  const _WindowCount({required this.count, required this.label});

  final int count;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '$count',
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
      Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppTheme.colorsOf(context).secondaryText,
        ),
      ),
    ],
  );
}

class _DayPill extends StatelessWidget {
  const _DayPill({
    required this.label,
    required this.count,
    required this.selected,
    required this.dotColors,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final List<Color> dotColors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: 62,
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? (Theme.of(context).brightness == Brightness.light
                    ? AppTheme.colorsOf(context).selectedFill
                    : Theme.of(context).colorScheme.primaryContainer)
              : AppTheme.transparent,
          borderRadius: BorderRadius.circular(14),
          border: selected ? Border.all(color: AppTheme.accent) : null,
        ),
        child: Column(
          children: [
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            if (count > 0)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final color in dotColors.take(3)) ...[
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 3),
                  ],
                  if (count > 1)
                    Text(
                      '$count',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              )
            else
              const SizedBox(height: 11),
          ],
        ),
      ),
    ),
  );
}

class _EmiProgressSection extends StatelessWidget {
  const _EmiProgressSection({required this.items});

  final List<EmiDetail> items;

  @override
  Widget build(BuildContext context) {
    final active = items
        .where(
          (item) =>
              item.emi.status != EmiStatus.completed &&
              item.emi.status != EmiStatus.paused &&
              item.remainingInstallments > 0,
        )
        .toList();
    if (active.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('EMI progress'),
        const SizedBox(height: 8),
        for (final detail in active)
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => EmiDetailScreen(detail.emi.id)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          displayName(detail.emi.name),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        '${detail.paidInstallments}/${detail.emi.tenureMonths}',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: AppTheme.colorsOf(context).secondaryText,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: detail.paidInstallments / detail.emi.tenureMonths,
                      minHeight: 7,
                      color: AppTheme.colorsOf(context).emi,
                      backgroundColor: AppTheme.colorsOf(context).fieldFill,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Next ${formatDate(detail.nextUnpaidInstallment!.dueDate)}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: AppTheme.colorsOf(context).secondaryText,
                              ),
                        ),
                      ),
                      Text(
                        formatMoney(detail.scheduledInstallmentPaise),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Insights extends StatelessWidget {
  const _Insights({
    required this.summary,
    required this.actions,
    required this.records,
  });

  final DashboardSummary summary;
  final List<ReminderItem> actions;
  final List<MoneyRecordDetail> records;

  @override
  Widget build(BuildContext context) {
    final insights = <String>[];
    if (summary.monthlyOutflowPaise > 0 && summary.monthlyEmisPaise > 0) {
      final share =
          (summary.monthlyEmisPaise * 100 / summary.monthlyOutflowPaise)
              .round();
      insights.add('EMIs are $share% of your 30-day outflow.');
    }
    final nextSubscription = actions
        .where(
          (item) =>
              item.entityType == 'subscription' &&
              item.status == ReminderStatus.upcoming,
        )
        .firstOrNull;
    if (nextSubscription != null) {
      insights.add(
        '${nextSubscription.title} renews ${nextSubscription.subtitle}.',
      );
    }
    final noDueIncoming = records
        .where(
          (item) =>
              item.record.direction == MoneyDirection.given &&
              item.summary.remainingAmountPaise > 0 &&
              item.record.dueDate == null,
        )
        .firstOrNull;
    if (noDueIncoming != null) {
      insights.add(
        '${displayName(noDueIncoming.record.personName)} owes you ${formatMoney(noDueIncoming.summary.remainingAmountPaise)} with no due date.',
      );
    }
    if (insights.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Smart insights'),
        const SizedBox(height: 8),
        for (final insight in insights.take(2))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 17,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 9),
                Expanded(child: Text(insight)),
              ],
            ),
          ),
      ],
    );
  }
}

class _NextActions extends StatelessWidget {
  const _NextActions({required this.items});

  final List<ReminderItem> items;

  @override
  Widget build(BuildContext context) {
    final active =
        items.where((item) => item.status != ReminderStatus.completed).toList()
          ..sort((a, b) {
            final aOverdue = a.status == ReminderStatus.overdue;
            final bOverdue = b.status == ReminderStatus.overdue;
            if (aOverdue != bOverdue) return aOverdue ? -1 : 1;
            return a.dueAt.compareTo(b.dueAt);
          });
    if (active.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Next financial actions'),
        const SizedBox(height: 6),
        for (final item in active.take(6)) _CompactDueRow(item: item),
      ],
    );
  }
}

class _CompactDueRow extends StatelessWidget {
  const _CompactDueRow({required this.item});

  final ReminderItem item;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () {
      switch (item.entityType) {
        case 'emi':
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => EmiDetailScreen(item.entityId)),
          );
        case 'money':
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => MoneyDetailScreen(item.entityId)),
          );
        case 'subscription':
          ProviderScope.containerOf(
            context,
            listen: false,
          ).read(shellIndexProvider.notifier).state = 3;
      }
    },
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: item.status == ReminderStatus.overdue
                  ? AppTheme.colorsOf(context).pay
                  : _actionColor(context, item),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_kind(item.entityType)} · ${item.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  item.status == ReminderStatus.overdue
                      ? 'Overdue · ${formatDate(item.dueAt)}'
                      : item.subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: item.status == ReminderStatus.overdue
                        ? AppTheme.colorsOf(context).pay
                        : AppTheme.colorsOf(context).secondaryText,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            formatMoney(item.amountPaise),
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
}

class _RecentActivity extends StatelessWidget {
  const _RecentActivity({required this.items});

  final List<ActivityLog> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        Row(
          children: [
            const Expanded(child: _SectionTitle('Recent activity')),
            TextButton(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const ActivityScreen())),
              child: const Text('View all'),
            ),
          ],
        ),
        for (final item in items.take(5))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.history,
                  size: 19,
                  color: AppTheme.colorsOf(context).secondaryText,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hideMoneyInText(item.title),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        hideMoneyInText(
                          item.description ?? formatDateTime(item.occurredAt),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.colorsOf(context).secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  formatDate(item.occurredAt),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppTheme.colorsOf(context).secondaryText,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SectionTitle extends SectionHeader {
  const _SectionTitle(super.title, {super.detail});
}

class _AddAction extends StatelessWidget {
  const _AddAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(24),
    elevation: 3,
    child: InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 19),
            const SizedBox(width: 9),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    ),
  );
}

Color _typeColor(BuildContext context, String type) => switch (type) {
  'emi' => AppTheme.colorsOf(context).emi,
  'subscription' => AppTheme.colorsOf(context).subscriptions,
  'money' => AppTheme.colorsOf(context).receive,
  _ => AppTheme.colorsOf(context).secondaryText,
};

Color _actionColor(BuildContext context, ReminderItem item) {
  if (item.status == ReminderStatus.overdue) {
    return AppTheme.colorsOf(context).pay;
  }
  if (item.entityType == 'money' && item.title.startsWith('I owe')) {
    return AppTheme.colorsOf(context).pay;
  }
  return _typeColor(context, item.entityType);
}

String _kind(String type) => switch (type) {
  'emi' => 'EMI',
  'money' => 'Money',
  'subscription' => 'Subscription',
  _ => 'Payment',
};

String _monthShort(int month) => const [
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
][month - 1];
