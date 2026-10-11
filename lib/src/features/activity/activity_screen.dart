import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/app_theme.dart';
import '../../core/formatters.dart';
import '../../core/providers.dart';
import '../../data/database.dart';
import '../../domain/enums.dart';
import '../../shared/empty_state.dart';
import '../../shared/finance_display_widgets.dart';
import '../../shared/finance_form_widgets.dart';
import '../emis/emis_screen.dart';
import '../money/money_screen.dart';
import '../settings/settings_screen.dart';
import '../subscriptions/subscriptions_screen.dart';

enum _TypeFilter { all, emi, money, subscription, settings }

enum _WhenFilter { today, yesterday, week, month }

class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});
  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  final _scroll = ScrollController();
  final _search = TextEditingController();
  Timer? _debounce;
  final _events = <ActivityLog>[];
  _TypeFilter _type = _TypeFilter.all;
  _WhenFilter? _when;
  DateTime? _day;
  String _query = '';
  bool _loading = false, _more = true;
  Object? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.hasClients && _scroll.position.extentAfter < 500) _load();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  (DateTime?, DateTime?) get _range {
    final today = DateUtils.dateOnly(DateTime.now());
    if (_day != null) return (_day, _day!.add(const Duration(days: 1)));
    return switch (_when) {
      _WhenFilter.today => (today, today.add(const Duration(days: 1))),
      _WhenFilter.yesterday => (today.subtract(const Duration(days: 1)), today),
      _WhenFilter.week => (
        today.subtract(Duration(days: today.weekday - 1)),
        today.add(const Duration(days: 1)),
      ),
      _WhenFilter.month => (
        DateTime(today.year, today.month),
        DateTime(today.year, today.month + 1),
      ),
      null => (null, null),
    };
  }

  List<ActivityType>? get _types => switch (_type) {
    _TypeFilter.all => null,
    _TypeFilter.emi =>
      ActivityType.values.where((e) => e.name.startsWith('emi')).toList(),
    _TypeFilter.money =>
      ActivityType.values.where((e) => e.name.startsWith('money')).toList(),
    _TypeFilter.subscription =>
      ActivityType.values
          .where((e) => e.name.startsWith('subscription'))
          .toList(),
    _TypeFilter.settings =>
      ActivityType.values
          .where((e) => !RegExp(r'^(emi|money|subscription)').hasMatch(e.name))
          .toList(),
  };

  void _reload() {
    _generation++;
    setState(() {
      _events.clear();
      _more = true;
      _loading = false;
      _error = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _load();
  }

  Future<void> _load() async {
    if (_loading || !_more) return;
    final generation = _generation;
    setState(() => _loading = true);
    try {
      final (from, until) = _range;
      final page = await ref
          .read(financeRepositoryProvider)
          .activityPage(
            offset: _events.length,
            search: _query,
            types: _types,
            from: from,
            until: until,
          );
      if (!mounted || generation != _generation) return;
      setState(() {
        _events.addAll(page);
        _more = page.length == 40;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _calendar() async {
    var month = DateTime(DateTime.now().year, DateTime.now().month);
    var dots = ref.read(financeRepositoryProvider).activityDaysInMonth(month);
    final selected = await showModalBottomSheet<DateTime>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, update) {
          final leading = DateTime(month.year, month.month).weekday - 1;
          final count = DateTime(month.year, month.month + 1, 0).day;
          void move(int delta) => update(() {
            month = DateTime(month.year, month.month + delta);
            dots = ref
                .read(financeRepositoryProvider)
                .activityDaysInMonth(month);
          });
          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Previous month',
                        onPressed: () => move(-1),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Expanded(
                        child: Text(
                          DateFormat('MMMM yyyy').format(month),
                          textAlign: TextAlign.center,
                          style: Theme.of(sheet).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next month',
                        onPressed: () => move(1),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      for (final label in ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                        Expanded(child: Center(child: Text(label))),
                    ],
                  ),
                  FutureBuilder<Set<int>>(
                    future: dots,
                    builder: (sheet, snapshot) => GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 7,
                            mainAxisExtent: 46,
                          ),
                      itemCount: leading + count,
                      itemBuilder: (sheet, index) {
                        final day = index - leading + 1;
                        if (day < 1) return const SizedBox.shrink();
                        return InkWell(
                          onTap: () => Navigator.pop(
                            sheet,
                            DateTime(month.year, month.month, day),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('$day'),
                              if (snapshot.data?.contains(day) ?? false)
                                CircleAvatar(
                                  radius: 2,
                                  backgroundColor: Theme.of(
                                    sheet,
                                  ).colorScheme.primary,
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (!mounted || selected == null) return;
    _day = selected;
    _when = null;
    _reload();
  }

  Future<void> _open(ActivityLog event) async {
    final kind = event.entityType, id = event.entityId;
    if (kind == null || id == null) return;
    final repo = ref.read(financeRepositoryProvider),
        db = ref.read(databaseProvider);
    final archived =
        await (db.select(db.settings)..where(
              (row) =>
                  row.key.equals('$kind.archived.$id') &
                  row.value.equals('true'),
            ))
            .getSingleOrNull() !=
        null;
    final exists = switch (kind) {
      'emi' =>
        await (db.select(
              db.emis,
            )..where((row) => row.id.equals(id))).getSingleOrNull() !=
            null,
      'money' =>
        await (db.select(
              db.moneyRecords,
            )..where((row) => row.id.equals(id))).getSingleOrNull() !=
            null,
      'subscription' =>
        await (db.select(
              db.subscriptions,
            )..where((row) => row.id.equals(id))).getSingleOrNull() !=
            null,
      _ => false,
    };
    if (!mounted) return;
    if (archived || !exists) {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Settings')),
            body: SafeArea(
              child: SettingsScreen(
                showHeading: false,
                openDeleted: true,
                deletedKind: kind,
                deletedId: id,
              ),
            ),
          ),
        ),
      );
    } else if (kind == 'emi') {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => EmiDetailScreen(id)),
      );
    } else if (kind == 'money') {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => MoneyDetailScreen(id)),
      );
    } else if (kind == 'subscription') {
      final sub = await repo.subscription(id);
      if (mounted && sub != null) openSubscriptionDetailSheet(context, sub);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(privacyModeProvider);
    final groups = <DateTime, List<ActivityLog>>{};
    for (final event in _events) {
      groups
          .putIfAbsent(DateUtils.dateOnly(event.occurredAt), () => [])
          .add(event);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity History'),
        actions: [
          IconButton(
            tooltip: 'Activity calendar',
            onPressed: _calendar,
            icon: const Icon(Icons.calendar_month_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _search,
              decoration: financeFieldDecoration(
                context,
                hint: 'Search activity',
                icon: Icons.search,
              ),
              onChanged: (text) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 250), () {
                  if (mounted) {
                    _query = text;
                    _reload();
                  }
                });
              },
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final filter in _TypeFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: ChoiceChip(
                      label: Text(switch (filter) {
                        _TypeFilter.all => 'All',
                        _TypeFilter.emi => 'EMI',
                        _TypeFilter.money => 'Money',
                        _TypeFilter.subscription => 'Subscription',
                        _TypeFilter.settings => 'Settings',
                      }),
                      selected: _type == filter,
                      onSelected: (_) {
                        _type = filter;
                        _reload();
                      },
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final filter in _WhenFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: ChoiceChip(
                      label: Text(switch (filter) {
                        _WhenFilter.today => 'Today',
                        _WhenFilter.yesterday => 'Yesterday',
                        _WhenFilter.week => 'This week',
                        _WhenFilter.month => 'This month',
                      }),
                      selected: _when == filter && _day == null,
                      onSelected: (selected) {
                        _day = null;
                        _when = selected ? filter : null;
                        _reload();
                      },
                    ),
                  ),
                ActionChip(
                  label: const Text('Pick date'),
                  avatar: const Icon(Icons.calendar_today_outlined, size: 16),
                  onPressed: _calendar,
                ),
              ],
            ),
          ),
          if (_day != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: InputChip(
                  label: Text(formatDate(_day!)),
                  onDeleted: () {
                    _day = null;
                    _reload();
                  },
                ),
              ),
            ),
          Expanded(
            child: _events.isEmpty && !_loading
                ? _error != null
                      ? EmptyState(
                          icon: Icons.error_outline,
                          title: 'Could not load activity',
                          message: 'Try again.',
                          actionLabel: 'Retry',
                          onAction: _reload,
                        )
                      : EmptyState(
                          icon: Icons.history,
                          title: _day == null
                              ? 'No activity for this filter'
                              : 'No activity on ${formatDate(_day!)}',
                          message: 'Your financial actions will appear here.',
                        )
                : CustomScrollView(
                    controller: _scroll,
                    slivers: [
                      for (final entry in groups.entries) ...[
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: _DayHeader(
                            entry.key,
                            entry.value,
                            mayContinue: _more && entry.key == groups.keys.last,
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          sliver: SliverList.builder(
                            itemCount: entry.value.length,
                            itemBuilder: (context, index) => _ActivityRow(
                              key: ValueKey(entry.value[index].id),
                              event: entry.value[index],
                              onTap: () => _open(entry.value[index]),
                            ),
                          ),
                        ),
                      ],
                      if (_loading)
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        ),
                      if (_error != null)
                        SliverToBoxAdapter(
                          child: TextButton(
                            onPressed: _load,
                            child: const Text('Could not load more. Retry'),
                          ),
                        ),
                      const SliverToBoxAdapter(child: SizedBox(height: 24)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _DayHeader extends SliverPersistentHeaderDelegate {
  _DayHeader(this.day, this.events, {required this.mayContinue});
  final DateTime day;
  final List<ActivityLog> events;
  final bool mayContinue;
  final bool privacy = privacyAmountsHidden;
  @override
  double get minExtent => 58;
  @override
  double get maxExtent => 58;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final today = DateUtils.dateOnly(DateTime.now());
    final label = day == today
        ? 'Today'
        : day == today.subtract(const Duration(days: 1))
        ? 'Yesterday'
        : DateFormat('EEE d MMM').format(day);
    final repaid = events
        .where((e) => e.type == ActivityType.moneyRepayment)
        .fold<int>(0, (sum, e) => sum + (_activityAmount(e) ?? 0));
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: RepaintBoundary(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 7, 16, 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              Row(
                children: [
                  Text(
                    '${events.length}${mayContinue ? '+' : ''} ${events.length == 1 && !mayContinue ? 'activity' : 'activities'}',
                  ),
                  if (repaid > 0) ...[
                    const Text(' · '),
                    AmountText(repaid),
                    Text(mayContinue ? ' repaid so far' : ' repaid'),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _DayHeader old) =>
      old.day != day ||
      old.events.length != events.length ||
      old.privacy != privacy ||
      old.mayContinue != mayContinue;
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({super.key, required this.event, required this.onTap});
  final ActivityLog event;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final type = event.type.name, colors = AppTheme.colorsOf(context);
    final color = type.startsWith('emi')
        ? colors.emi
        : type.startsWith('money')
        ? colors.receive
        : type.startsWith('subscription')
        ? colors.subscriptions
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final icon = type.startsWith('emi')
        ? Icons.account_balance_outlined
        : type.startsWith('money')
        ? Icons.swap_horiz
        : type.startsWith('subscription')
        ? Icons.autorenew
        : Icons.settings_outlined;
    final amount = _activityAmount(event);
    final outgoing =
        event.type == ActivityType.emiPaymentRecorded ||
        event.type == ActivityType.emiPaidEarly ||
        event.type == ActivityType.moneyGiven ||
        (event.type == ActivityType.moneyRepayment &&
            event.title.startsWith('You repaid'));
    final incoming =
        event.type == ActivityType.moneyBorrowed ||
        (event.type == ActivityType.moneyRepayment && !outgoing);
    final amountColor = incoming
        ? colors.receive
        : outgoing
        ? colors.pay
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final title = _withoutLoggedAmount(event.title, amount),
        detail = _withoutLoggedAmount(event.description ?? '', amount);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.13),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title.isEmpty ? event.type.label : title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${DateFormat.jm().format(event.occurredAt)}${detail.isEmpty ? '' : ' · $detail'}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
                if (amount != null) ...[
                  const SizedBox(width: 8),
                  AmountText(
                    amount,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: amountColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final _loggedMoney = RegExp(
  r'(?:₹|Rs\.?|INR|AED|S\$|R\$|[$€£¥])\s*([0-9][0-9,.’\x27\s]*[0-9]|[0-9])',
  caseSensitive: false,
);

int? _activityAmount(ActivityLog event) {
  final match = _loggedMoney.firstMatch(
    '${event.title} ${event.description ?? ''}',
  );
  if (match == null) return null;
  final number = match.group(1)!.trim();
  final separator = number.lastIndexOf(RegExp(r'[.,]'));
  final decimal = separator >= 0 && number.length - separator - 1 <= 2;
  final digits = number.replaceAll(RegExp(r'[^0-9]'), '');
  final value = int.tryParse(digits);
  if (value == null) return null;
  return decimal
      ? (number.length - separator - 1 == 1 ? value * 10 : value)
      : value * 100;
}

String _withoutLoggedAmount(String value, int? amount) => amount == null
    ? hideMoneyInText(value).trim()
    : value
          .replaceAll(_loggedMoney, '')
          .replaceAll(RegExp(r'\s*[·,]\s*(?=·|$)'), ' ')
          .trim();
