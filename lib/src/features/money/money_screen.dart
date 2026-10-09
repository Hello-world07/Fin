import 'dart:async';
import 'dart:math' as math;

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/formatters.dart';
import '../../core/app_theme.dart';
import '../../core/providers.dart';
import '../../data/database.dart';
import '../../data/repositories.dart';
import '../../domain/enums.dart';
import '../../domain/due_status.dart';
import '../../shared/async_view.dart';
import '../../shared/calculator_sheet.dart';
import '../../shared/empty_state.dart';
import '../../shared/forms.dart';
import '../../shared/finance_form_widgets.dart';
import '../../shared/finance_display_widgets.dart';
import '../../shared/notched_navigation_bar.dart';
import '../../shared/screen_header.dart';

class MoneyScreen extends ConsumerStatefulWidget {
  const MoneyScreen({super.key});

  @override
  ConsumerState<MoneyScreen> createState() => _MoneyScreenState();
}

enum _MoneyFilter { all, unpaid, partial, overdue, settled }

class _PersonBalance {
  _PersonBalance(this.name, this.records);

  final String name;
  final List<MoneyRecordDetail> records;

  int get total =>
      records.fold(0, (sum, item) => sum + item.record.amountPaise);
  int get remaining =>
      records.fold(0, (sum, item) => sum + item.summary.remainingAmountPaise);
  int get repaid => total - remaining;
  DateTime? get nearestDue {
    final dates =
        records
            .where(
              (item) =>
                  item.summary.remainingAmountPaise > 0 &&
                  item.record.dueDate != null,
            )
            .map((item) => item.record.dueDate!)
            .toList()
          ..sort();
    return dates.firstOrNull;
  }

  bool get overdue =>
      remaining > 0 &&
      nearestDue != null &&
      DateTime(nearestDue!.year, nearestDue!.month, nearestDue!.day).isBefore(
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
      );

  String get statusLabel {
    if (remaining == 0) return 'Settled';
    if (overdue) return 'Overdue';
    if (repaid > 0) return 'Partially paid';
    if (nearestDue != null) {
      final relative = relativeDueText(nearestDue!, DateTime.now());
      return relative.startsWith('in ') ? 'Due $relative' : relative;
    }
    return 'Unpaid';
  }
}

List<_PersonBalance> _groupMoneyRecords(List<MoneyRecordDetail> records) {
  final grouped = <String, List<MoneyRecordDetail>>{};
  for (final item in records) {
    grouped
        .putIfAbsent(item.record.personName.trim().toLowerCase(), () => [])
        .add(item);
  }
  final people = [
    for (final group in grouped.values)
      _PersonBalance(group.first.record.personName.trim(), group),
  ];
  people.sort((a, b) {
    if (a.overdue != b.overdue) return a.overdue ? -1 : 1;
    if ((a.remaining == 0) != (b.remaining == 0)) {
      return a.remaining == 0 ? 1 : -1;
    }
    final aDue = a.nearestDue;
    final bDue = b.nearestDue;
    if (aDue == null && bDue != null) return 1;
    if (aDue != null && bDue == null) return -1;
    if (aDue != null && bDue != null) {
      final order = aDue.compareTo(bDue);
      if (order != 0) return order;
    }
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return people;
}

class _MoneyScreenState extends ConsumerState<MoneyScreen> {
  MoneyDirection _direction = MoneyDirection.given;
  _MoneyFilter _filter = _MoneyFilter.all;
  final _search = TextEditingController();
  Timer? _searchDebounce;
  String _query = '';

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    return Scaffold(
      floatingActionButton: MediaQuery.viewInsetsOf(context).bottom > 0
          ? null
          : Padding(
              padding: EdgeInsets.only(
                bottom: NotchedNavigationMetrics.fabBottomPadding,
              ),
              child: FloatingActionButton.extended(
                onPressed: () => openFinanceSheet(
                  context,
                  MoneyFormSheet(initialDirection: _direction),
                ),
                icon: const Icon(Icons.add),
                label: const Text('New record'),
              ),
            ),
      body: Column(
        children: [
          const ScreenHeader(title: Text('Money')),
          Expanded(
            child: AsyncView(
              value: ref.watch(moneyRecordsProvider),
              builder: (items) {
                final coming = items
                    .where(
                      (item) => item.record.direction == MoneyDirection.given,
                    )
                    .toList();
                final payable = items
                    .where(
                      (item) =>
                          item.record.direction == MoneyDirection.borrowed,
                    )
                    .toList();
                final selected = _direction == MoneyDirection.given
                    ? coming
                    : payable;
                final query = _query;
                final people = _groupMoneyRecords(selected);
                final visible = people.where((person) {
                  if (person.remaining == 0 &&
                      _filter != _MoneyFilter.settled) {
                    return false;
                  }
                  final matchesFilter = switch (_filter) {
                    _MoneyFilter.all => true,
                    _MoneyFilter.unpaid =>
                      person.remaining > 0 && person.repaid == 0,
                    _MoneyFilter.partial =>
                      person.remaining > 0 && person.repaid > 0,
                    _MoneyFilter.overdue => person.overdue,
                    _MoneyFilter.settled => person.remaining == 0,
                  };
                  return matchesFilter &&
                      (query.isEmpty ||
                          person.name.toLowerCase().contains(query));
                }).toList();
                final originalTotal = selected.fold<int>(
                  0,
                  (sum, item) => sum + item.record.amountPaise,
                );
                final outstanding = selected.fold<int>(
                  0,
                  (sum, item) => sum + item.summary.remainingAmountPaise,
                );
                final repaid = originalTotal - outstanding;
                final grouped = <DueListGroup, List<_PersonBalance>>{};
                for (final person in visible) {
                  final group = dueListGroup(
                    person.remaining == 0 ? null : person.nearestDue,
                    DateTime.now(),
                  );
                  grouped.putIfAbsent(group, () => []).add(person);
                }
                final rows = <(String?, _PersonBalance?)>[];
                for (final group in DueListGroup.values) {
                  final section = grouped[group];
                  if (section == null || section.isEmpty) continue;
                  rows.add((group.label, null));
                  for (final person in section) {
                    rows.add((null, person));
                  }
                }
                return ListView.builder(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    0,
                    16,
                    NotchedNavigationMetrics.tabContentPadding(context),
                  ),
                  itemCount: rows.length + 1,
                  itemBuilder: (context, index) {
                    if (index > 0) {
                      final row = rows[index - 1];
                      if (row.$1 != null) return DueListHeader(row.$1!);
                      return Padding(
                        key: ValueKey(
                          '${_direction.name}:${row.$2!.name.toLowerCase()}',
                        ),
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _MoneyPersonTile(
                          person: row.$2!,
                          direction: _direction,
                        ),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SegmentedToggle<MoneyDirection>(
                          segments: const [
                            ButtonSegment(
                              value: MoneyDirection.given,
                              label: Text('Money given'),
                            ),
                            ButtonSegment(
                              value: MoneyDirection.borrowed,
                              label: Text('Money borrowed'),
                            ),
                          ],
                          selected: {_direction},
                          filled: true,
                          selectedBackground: _direction == MoneyDirection.given
                              ? financeSelectedFill(context)
                              : AppTheme.colorsOf(
                                  context,
                                ).pay.withValues(alpha: 0.12),
                          selectedForeground: _direction == MoneyDirection.given
                              ? Theme.of(context).colorScheme.primary
                              : AppTheme.colorsOf(context).pay,
                          onSelectionChanged: (value) =>
                              setState(() => _direction = value.single),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          _direction == MoneyDirection.given
                              ? 'TO RECEIVE'
                              : 'TO PAY',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 3),
                        AmountText(
                          outstanding,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 16),
                        _MoneySplitBar(
                          repaid: repaid,
                          outstanding: outstanding,
                          direction: _direction,
                        ),
                        const SizedBox(height: 14),
                        _SummaryValue(
                          label: _direction == MoneyDirection.given
                              ? 'Total given'
                              : 'Total borrowed',
                          value: originalTotal,
                        ),
                        if (_direction == MoneyDirection.given) ...[
                          const SizedBox(height: 18),
                          _CollectionWeeks(items: selected),
                        ],
                        const SizedBox(height: 20),
                        TextField(
                          controller: _search,
                          onChanged: (value) {
                            _searchDebounce?.cancel();
                            _searchDebounce = Timer(
                              const Duration(milliseconds: 180),
                              () {
                                if (mounted) {
                                  setState(
                                    () => _query = value.trim().toLowerCase(),
                                  );
                                }
                              },
                            );
                          },
                          decoration: financeFieldDecoration(
                            context,
                            hint: 'Search people',
                            icon: Icons.search,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          clipBehavior: Clip.none,
                          child: Row(
                            children: [
                              for (final entry in const [
                                (_MoneyFilter.all, 'All'),
                                (_MoneyFilter.unpaid, 'Unpaid'),
                                (_MoneyFilter.partial, 'Partially paid'),
                                (_MoneyFilter.overdue, 'Overdue'),
                                (_MoneyFilter.settled, 'Settled'),
                              ]) ...[
                                Padding(
                                  padding: const EdgeInsets.only(right: 7),
                                  child: ChoiceChip(
                                    label: Text(entry.$2),
                                    selected: _filter == entry.$1,
                                    onSelected: (_) =>
                                        setState(() => _filter = entry.$1),
                                    selectedColor: financeSelectedFill(context),
                                    side: BorderSide.none,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (visible.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 40),
                            child: EmptyState(
                              icon: Icons.swap_horiz,
                              title: items.isEmpty
                                  ? 'No money records'
                                  : 'No matching records',
                              message: items.isEmpty
                                  ? 'Track money given and borrowed here.'
                                  : 'Try another filter or search term.',
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: AmountText(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _MoneySplitBar extends StatelessWidget {
  const _MoneySplitBar({
    required this.repaid,
    required this.outstanding,
    required this.direction,
  });
  final int repaid;
  final int outstanding;
  final MoneyDirection direction;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          height: 6,
          child: Row(
            children: [
              if (repaid + outstanding == 0)
                Expanded(
                  child: ColoredBox(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                )
              else ...[
                if (repaid > 0)
                  Expanded(
                    flex: repaid,
                    child: ColoredBox(
                      color: AppTheme.colorsOf(context).receive,
                    ),
                  ),
                if (outstanding > 0)
                  Expanded(
                    flex: outstanding,
                    child: ColoredBox(
                      color: direction == MoneyDirection.given
                          ? Theme.of(context).colorScheme.primary
                          : AppTheme.colorsOf(context).pay,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      const SizedBox(height: 6),
      Row(
        children: [
          Expanded(
            child: Text(
              '${direction == MoneyDirection.given ? 'Received' : 'Paid'} ${formatMoney(repaid)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppTheme.colorsOf(context).secondaryText,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Outstanding ${formatMoney(outstanding)}',
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppTheme.colorsOf(context).secondaryText,
              ),
            ),
          ),
        ],
      ),
    ],
  );
}

class _CollectionWeeks extends StatelessWidget {
  const _CollectionWeeks({required this.items});
  final List<MoneyRecordDetail> items;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final values = List<int>.filled(6, 0);
    for (final detail in items) {
      final due = detail.record.dueDate;
      if (due == null || detail.summary.remainingAmountPaise <= 0) continue;
      final days = DateTime(
        due.year,
        due.month,
        due.day,
      ).difference(start).inDays;
      if (days >= 0 && days < 42) {
        values[days ~/ 7] += detail.summary.remainingAmountPaise;
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Expected collections by week',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            AmountText(
              values.fold<int>(0, (a, b) => a + b),
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 48,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _WeekBarsPainter(
                values: values,
                bar: AppTheme.colorsOf(context).receive,
                track: AppTheme.colorsOf(context).fieldFill,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (var i = 0; i < 6; i++)
              Expanded(
                child: Text(
                  'W${i + 1}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _WeekBarsPainter extends CustomPainter {
  const _WeekBarsPainter({
    required this.values,
    required this.bar,
    required this.track,
  });
  final List<int> values;
  final Color bar, track;

  @override
  void paint(Canvas canvas, Size size) {
    final max = values.fold<int>(0, math.max);
    final slot = size.width / 6;
    final width = math.min(slot * 0.6, 28.0);
    for (var i = 0; i < 6; i++) {
      final left = slot * i + (slot - width) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, 0, width, size.height),
          const Radius.circular(5),
        ),
        Paint()..color = track,
      );
      if (max > 0 && values[i] > 0) {
        final height = math.max(5.0, size.height * values[i] / max);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(left, size.height - height, width, height),
            const Radius.circular(5),
          ),
          Paint()..color = bar,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WeekBarsPainter old) =>
      old.bar != bar ||
      old.track != track ||
      old.values.length != values.length ||
      Iterable<int>.generate(
        values.length,
      ).any((i) => old.values[i] != values[i]);
}

class _MoneyPersonTile extends StatelessWidget {
  const _MoneyPersonTile({required this.person, required this.direction});

  final _PersonBalance person;
  final MoneyDirection direction;

  @override
  Widget build(BuildContext context) {
    final progress = person.total == 0 ? 0.0 : person.repaid / person.total;
    final statusColor = person.remaining == 0
        ? AppTheme.colorsOf(context).receive
        : person.overdue
        ? AppTheme.colorsOf(context).pay
        : person.repaid > 0
        ? Theme.of(context).colorScheme.primary
        : person.nearestDue != null
        ? AppTheme.colorsOf(context).emi
        : Theme.of(context).colorScheme.primary;
    final due = person.nearestDue;
    final days = due == null
        ? null
        : DateTime(due.year, due.month, due.day)
              .difference(
                DateTime(
                  DateTime.now().year,
                  DateTime.now().month,
                  DateTime.now().day,
                ),
              )
              .inDays;
    final dueColor = person.remaining == 0
        ? AppTheme.colorsOf(context).receive
        : days == null
        ? AppTheme.colorsOf(context).secondaryText
        : days < 0
        ? AppTheme.colorsOf(context).pay
        : days <= 7
        ? AppTheme.colorsOf(context).emi
        : AppTheme.colorsOf(context).receive;
    return FinanceTonalTile(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => person.records.length == 1
              ? MoneyDetailScreen(person.records.single.record.id)
              : MoneyPersonScreen(person.name, direction),
        ),
      ),
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: financeSelectedFill(context),
        child: Text(
          displayName(person.name).characters.first,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            displayName(person.name),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          Text(
            '${person.records.length} ${person.records.length == 1 ? 'record' : 'records'} · ${person.remaining == 0
                ? 'Settled'
                : person.repaid > 0
                ? 'Partially paid'
                : 'Unpaid'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: statusColor),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: StatusPill(
              label: person.remaining == 0
                  ? 'Settled'
                  : due == null
                  ? 'No due date'
                  : relativeDueText(due, DateTime.now()),
              color: dueColor,
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
                person.remaining,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            if (person.repaid > 0) ...[
              const SizedBox(height: 7),
              MiniProgressRing(
                progress: progress,
                size: 42,
                strokeWidth: 3,
                child: Center(
                  child: Text(
                    '${(progress * 100).round()}%',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class MoneyPersonScreen extends ConsumerStatefulWidget {
  const MoneyPersonScreen(this.personName, this.direction, {super.key});
  final String personName;
  final MoneyDirection direction;

  @override
  ConsumerState<MoneyPersonScreen> createState() => _MoneyPersonScreenState();
}

class _MoneyPersonScreenState extends ConsumerState<MoneyPersonScreen> {
  int? _repaymentRecordId;

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(moneyRecordsProvider);
    return AsyncView(
      value: items,
      builder: (all) {
        final records =
            all
                .where(
                  (item) =>
                      item.record.direction == widget.direction &&
                      item.record.personName.trim().toLowerCase() ==
                          widget.personName.trim().toLowerCase(),
                )
                .toList()
              ..sort(
                (a, b) => (a.record.dueDate ?? DateTime(9999)).compareTo(
                  b.record.dueDate ?? DateTime(9999),
                ),
              );
        final open = records
            .where((item) => item.summary.remainingAmountPaise > 0)
            .toList();
        final settled = records
            .where((item) => item.summary.remainingAmountPaise == 0)
            .toList();
        final person = _PersonBalance(widget.personName, records);
        final oldestOpen = [...open]
          ..sort((a, b) => a.record.recordDate.compareTo(b.record.recordDate));
        final repayment =
            open
                .where((item) => item.record.id == _repaymentRecordId)
                .firstOrNull ??
            oldestOpen.firstOrNull;
        return Scaffold(
          appBar: AppBar(title: Text(displayName(widget.personName))),
          body: records.isEmpty
              ? const EmptyState(
                  icon: Icons.person_outline,
                  title: 'No records',
                  message: 'There are no records for this person.',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  children: [
                    Row(
                      children: [
                        RepaintBoundary(
                          child: MiniProgressRing(
                            progress: person.total == 0
                                ? 0
                                : person.repaid / person.total,
                            size: 90,
                            strokeWidth: 7,
                            child: Text(
                              '${person.total == 0 ? 0 : (person.repaid * 100 / person.total).round()}%',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const FinanceFieldLabel('BALANCE'),
                              AmountText(
                                person.remaining,
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              Text(
                                '${open.length} open · ${settled.length} settled',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _SummaryValue(
                            label: 'Original',
                            value: person.total,
                          ),
                        ),
                        Expanded(
                          child: _SummaryValue(
                            label: 'Repaid',
                            value: person.repaid,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    for (final item in open)
                      _PersonRecordRow(
                        key: ValueKey(item.record.id),
                        detail: item,
                        onAdd: () => _addRepayment(item),
                        onSettle: () => _settle(item),
                        onExtend: () => _extend(item),
                        onEdit: () => openFinanceSheet(
                          context,
                          MoneyFormSheet(record: item.record),
                        ),
                        onDelete: () => _delete(item),
                      ),
                    if (settled.isNotEmpty)
                      ExpansionTile(
                        title: Text('Settled (${settled.length})'),
                        children: [
                          for (final item in settled)
                            ListTile(
                              title: Text(formatDate(item.record.recordDate)),
                              subtitle: AmountText(item.record.amountPaise),
                              trailing: PopupMenuButton<String>(
                                tooltip: 'Record actions',
                                onSelected: (action) => action == 'edit'
                                    ? openFinanceSheet(
                                        context,
                                        MoneyFormSheet(record: item.record),
                                      )
                                    : _delete(item),
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Edit'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Delete'),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
          bottomNavigationBar: repayment == null
              ? null
              : SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (open.length > 1)
                          PopupMenuButton<int>(
                            initialValue: repayment.record.id,
                            onSelected: (id) =>
                                setState(() => _repaymentRecordId = id),
                            itemBuilder: (_) => [
                              for (final item in open)
                                PopupMenuItem(
                                  value: item.record.id,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        formatDate(
                                          item.record.dueDate ??
                                              item.record.recordDate,
                                        ),
                                      ),
                                      const SizedBox(width: 7),
                                      AmountText(
                                        item.summary.remainingAmountPaise,
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Record due ${repayment.record.dueDate == null ? 'any time' : formatDate(repayment.record.dueDate!)}',
                                  ),
                                  const Icon(Icons.arrow_drop_down),
                                ],
                              ),
                            ),
                          ),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => _addRepayment(repayment),
                            icon: const Icon(Icons.add),
                            label: const Text('Add repayment'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }

  void _addRepayment(MoneyRecordDetail detail) => openFinanceSheet(
    context,
    RepaymentSheet(
      recordId: detail.record.id,
      remainingPaise: detail.summary.remainingAmountPaise,
    ),
  );

  Future<void> _settle(MoneyRecordDetail detail) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Settle this record?'),
        content: const Text(
          'Record the full remaining amount as repaid? This does not transfer money.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Settle'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref
          .read(financeRepositoryProvider)
          .addRepayment(
            detail.record.id,
            detail.summary.remainingAmountPaise,
            'Settled in full',
            DateTime.now(),
          );
    }
  }

  Future<void> _extend(MoneyRecordDetail detail) async {
    final choice = await showModalBottomSheet<int>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Extend due date')),
            ListTile(
              title: const Text('+7 days'),
              onTap: () => Navigator.pop(sheet, 7),
            ),
            ListTile(
              title: const Text('+30 days'),
              onTap: () => Navigator.pop(sheet, 30),
            ),
            ListTile(
              title: const Text('Custom date'),
              onTap: () => Navigator.pop(sheet, 0),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    final due = detail.record.dueDate;
    final base = due != null && due.isAfter(DateTime.now())
        ? due
        : DateTime.now();
    final date = choice == 0
        ? await pickAppDate(context, base)
        : DateTime(base.year, base.month, base.day + choice);
    if (date != null && mounted) {
      await ref
          .read(financeRepositoryProvider)
          .updateMoneyDueDate(detail.record.id, date);
    }
  }

  Future<void> _delete(MoneyRecordDetail detail) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Delete record?'),
        content: const Text('The record will move to the Recycle bin.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref
          .read(financeRepositoryProvider)
          .deleteMoneyRecord(detail.record.id);
    }
  }
}

class _PersonRecordRow extends StatelessWidget {
  const _PersonRecordRow({
    super.key,
    required this.detail,
    required this.onAdd,
    required this.onSettle,
    required this.onExtend,
    required this.onEdit,
    required this.onDelete,
  });
  final MoneyRecordDetail detail;
  final VoidCallback onAdd, onSettle, onExtend, onEdit, onDelete;

  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: Row(
      children: [
        Expanded(
          child: AmountText(
            detail.summary.remainingAmountPaise,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Text(
          detail.record.dueDate == null
              ? 'No due date'
              : formatDate(detail.record.dueDate!),
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    ),
    subtitle: Padding(
      padding: const EdgeInsets.only(top: 6),
      child: LinearProgressIndicator(
        value: detail.record.amountPaise == 0
            ? 0
            : detail.summary.repaidAmountPaise / detail.record.amountPaise,
        minHeight: 4,
        borderRadius: BorderRadius.circular(3),
      ),
    ),
    children: [
      _MoneyTimeline(detail: detail),
      Wrap(
        spacing: 4,
        children: [
          TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add repayment'),
          ),
          TextButton(onPressed: onSettle, child: const Text('Settle')),
          TextButton(onPressed: onExtend, child: const Text('Extend due date')),
          IconButton(
            tooltip: 'Edit record',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Delete record',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    ],
  );
}

class MoneyDetailScreen extends ConsumerWidget {
  const MoneyDetailScreen(this.id, {super.key});

  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(financeRepositoryProvider);
    return StreamBuilder<MoneyRecordDetail?>(
      stream: repo.watchMoneyDetail(id),
      builder: (context, snapshot) {
        final detail = snapshot.data;
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Money')),
            body: const Center(
              child: Text('Could not load this money record.'),
            ),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(displayName(detail?.record.personName ?? 'Money')),
            actions: [
              if (detail != null)
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => openFinanceSheet(
                    context,
                    MoneyFormSheet(record: detail.record),
                  ),
                ),
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: detail == null
                    ? null
                    : () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text(
                              'Delete ${displayName(detail.record.personName)}\'s record?',
                            ),
                            content: const Text(
                              'This permanently deletes the record and its repayment details. A deletion entry will remain in Activity History.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.error,
                                  foregroundColor: Theme.of(
                                    context,
                                  ).colorScheme.onError,
                                ),
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Delete record'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true) return;
                        await repo.deleteMoneyRecord(id);
                        if (context.mounted) Navigator.pop(context);
                      },
              ),
            ],
          ),
          body: detail == null
              ? Center(
                  child: snapshot.hasData
                      ? const Text('Record not found')
                      : const CircularProgressIndicator(),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  children: [
                    Text(
                      _headline(detail),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 22),
                    Center(
                      child: MiniProgressRing(
                        progress:
                            detail.summary.repaidAmountPaise /
                            detail.record.amountPaise,
                        size: 140,
                        strokeWidth: 11,
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.outlineVariant,
                        child: Text(
                          '${(detail.summary.repaidAmountPaise * 100 / detail.record.amountPaise).round()}%',
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: _SummaryValue(
                            label:
                                detail.record.direction == MoneyDirection.given
                                ? 'Received'
                                : 'Paid',
                            value: detail.summary.repaidAmountPaise,
                          ),
                        ),
                        Expanded(
                          child: _SummaryValue(
                            label: 'Remaining',
                            value: detail.summary.remainingAmountPaise,
                          ),
                        ),
                        Expanded(
                          child: _SummaryValue(
                            label: 'Original',
                            value: detail.record.amountPaise,
                          ),
                        ),
                      ],
                    ),
                    if (detail.record.dueDate != null) ...[
                      const SizedBox(height: 18),
                      Text(
                        'Due ${formatDate(detail.record.dueDate!)}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.colorsOf(context).secondaryText,
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),
                    Text(
                      'History',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _MoneyTimeline(detail: detail),
                  ],
                ),
          bottomNavigationBar:
              detail == null || detail.summary.remainingAmountPaise == 0
              ? null
              : SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                              shape: const StadiumBorder(),
                            ),
                            onPressed: () => openFinanceSheet(
                              context,
                              RepaymentSheet(
                                recordId: id,
                                remainingPaise:
                                    detail.summary.remainingAmountPaise,
                              ),
                            ),
                            icon: const Icon(Icons.add),
                            label: const Text('Add repayment'),
                          ),
                        ),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 4,
                          children: [
                            TextButton(
                              onPressed: () =>
                                  _settleFully(context, ref, detail),
                              child: const Text('Settle fully'),
                            ),
                            TextButton(
                              onPressed: () =>
                                  _extendDueDate(context, ref, detail),
                              child: const Text('Extend due date'),
                            ),
                            if (detail.record.direction == MoneyDirection.given)
                              TextButton.icon(
                                onPressed: () => _sendReminder(context, detail),
                                icon: const Icon(
                                  Icons.share_outlined,
                                  size: 18,
                                ),
                                label: const Text('Send reminder'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }

  String _headline(MoneyRecordDetail detail) {
    if (detail.summary.remainingAmountPaise == 0) {
      return detail.record.direction == MoneyDirection.given
          ? '${displayName(detail.record.personName)} has settled this record'
          : 'You settled your balance with ${displayName(detail.record.personName)}';
    }
    final due = detail.record.dueDate;
    final relative = due == null ? null : relativeDueText(due, DateTime.now());
    final when = relative == null
        ? ''
        : relative.startsWith('Overdue')
        ? ' · ${relative.toLowerCase()}'
        : relative.startsWith('Due')
        ? ' · ${relative.toLowerCase()}'
        : ' · due $relative';
    if (detail.record.direction == MoneyDirection.given) {
      return '${displayName(detail.record.personName)} owes you ${formatMoney(detail.summary.remainingAmountPaise)}$when';
    }
    return 'You owe ${displayName(detail.record.personName)} ${formatMoney(detail.summary.remainingAmountPaise)}$when';
  }

  Future<void> _settleFully(
    BuildContext context,
    WidgetRef ref,
    MoneyRecordDetail detail,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Settle this record?'),
        content: Text(
          'Record ${formatMoney(detail.summary.remainingAmountPaise)} as repaid in full? This does not transfer money.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Settle fully'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(financeRepositoryProvider)
          .addRepayment(
            id,
            detail.summary.remainingAmountPaise,
            'Settled in full',
            DateTime.now(),
          );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not settle record: $error')),
        );
      }
    }
  }

  Future<void> _extendDueDate(
    BuildContext context,
    WidgetRef ref,
    MoneyRecordDetail detail,
  ) async {
    final choice = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Extend due date')),
            ListTile(
              title: const Text('+7 days'),
              onTap: () => Navigator.pop(context, 7),
            ),
            ListTile(
              title: const Text('+30 days'),
              onTap: () => Navigator.pop(context, 30),
            ),
            ListTile(
              title: const Text('Custom date'),
              onTap: () => Navigator.pop(context, 0),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    final base =
        detail.record.dueDate != null &&
            detail.record.dueDate!.isAfter(DateTime.now())
        ? detail.record.dueDate!
        : DateTime.now();
    final date = choice == 0
        ? await pickAppDate(context, base)
        : DateTime(base.year, base.month, base.day + choice);
    if (date == null) return;
    try {
      await ref.read(financeRepositoryProvider).updateMoneyDueDate(id, date);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not extend due date: $error')),
        );
      }
    }
  }

  Future<void> _sendReminder(
    BuildContext context,
    MoneyRecordDetail detail,
  ) async {
    var message =
        'Hi ${displayName(detail.record.personName)}, a gentle reminder about ${formatMoney(detail.summary.remainingAmountPaise)}${detail.record.dueDate == null ? '' : ' due on ${formatDate(detail.record.dueDate!)}'}. Thank you!';
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send reminder'),
        content: TextFormField(
          initialValue: message,
          onChanged: (value) => message = value,
          minLines: 3,
          maxLines: 6,
          decoration: financeFieldDecoration(context),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, message.trim()),
            child: const Text('Share'),
          ),
        ],
      ),
    );
    if (text == null || text.isEmpty || !context.mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: text,
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open sharing.')),
        );
      }
    }
  }
}

class _MoneyTimeline extends StatelessWidget {
  const _MoneyTimeline({required this.detail});
  final MoneyRecordDetail detail;

  @override
  Widget build(BuildContext context) {
    final repayments = [...detail.repayments]
      ..sort((a, b) {
        final byDate = a.paidOn.compareTo(b.paidOn);
        return byDate == 0 ? a.id.compareTo(b.id) : byDate;
      });
    var remaining = detail.record.amountPaise;
    final nodes = <Widget>[
      _MoneyTimelineNode(
        icon: Icons.add_circle_outline,
        title: 'Record created',
        amount: detail.record.amountPaise,
        remaining: remaining,
        date: detail.record.recordDate,
        note: detail.record.notes,
        last: repayments.isEmpty,
      ),
    ];
    for (var index = 0; index < repayments.length; index++) {
      final payment = repayments[index];
      remaining -= payment.amountPaise;
      nodes.add(
        _MoneyTimelineNode(
          icon: Icons.check_circle_outline,
          title: detail.record.direction == MoneyDirection.given
              ? 'Repayment received'
              : 'Repayment paid',
          amount: payment.amountPaise,
          remaining: remaining,
          date: payment.paidOn,
          note: payment.notes,
          last: index == repayments.length - 1,
        ),
      );
    }
    return Column(children: nodes);
  }
}

class _MoneyTimelineNode extends StatelessWidget {
  const _MoneyTimelineNode({
    required this.icon,
    required this.title,
    required this.amount,
    required this.remaining,
    required this.date,
    required this.note,
    required this.last,
  });
  final IconData icon;
  final String title;
  final int amount;
  final int remaining;
  final DateTime date;
  final String? note;
  final bool last;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      if (!last)
        Positioned(
          left: 14,
          top: 22,
          bottom: 0,
          child: Container(width: 2, color: AppTheme.colorsOf(context).receive),
        ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 30,
            child: Icon(
              icon,
              size: 22,
              color: AppTheme.colorsOf(context).receive,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: AmountText(
                            amount,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatDateTime(date),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.colorsOf(context).secondaryText,
                    ),
                  ),
                  if (note?.isNotEmpty == true) ...[
                    const SizedBox(height: 4),
                    Text(note!, style: Theme.of(context).textTheme.bodySmall),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    '${formatMoney(remaining)} remaining',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.colorsOf(context).secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ],
  );
}

class MoneyFormSheet extends ConsumerStatefulWidget {
  const MoneyFormSheet({
    super.key,
    this.record,
    this.initialAmount,
    this.initialDirection,
    this.initialPerson,
    this.initialDueDate,
  });

  final MoneyRecord? record;
  final String? initialAmount;
  final MoneyDirection? initialDirection;
  final String? initialPerson;
  final DateTime? initialDueDate;

  @override
  ConsumerState<MoneyFormSheet> createState() => _MoneyFormSheetState();
}

class _MoneyFormSheetState extends ConsumerState<MoneyFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _person = TextEditingController(
    text: widget.record?.personName ?? widget.initialPerson ?? '',
  );
  late final _amount = TextEditingController(
    text:
        widget.initialAmount ??
        (widget.record == null ? '' : rupeesText(widget.record!.amountPaise)),
  );
  late final _notes = TextEditingController(text: widget.record?.notes ?? '');
  late MoneyDirection _direction =
      widget.initialDirection ??
      widget.record?.direction ??
      MoneyDirection.given;
  late DateTime _date = widget.record?.recordDate ?? DateTime.now();
  DateTime? _due;
  late int? _paymentMethodId = widget.record?.paymentMethodId;
  String _selectedPayment = 'CASH';

  @override
  void initState() {
    super.initState();
    _due = widget.record?.dueDate ?? widget.initialDueDate;
  }

  @override
  void dispose() {
    _person.dispose();
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final methods = ref.watch(paymentMethodsProvider).valueOrNull ?? const [];
    if (widget.record == null &&
        _paymentMethodId == null &&
        methods.isNotEmpty) {
      _paymentMethodId = _methodIdForTile(_selectedPayment, methods);
    }
    if (widget.record != null && _paymentMethodId != null) {
      final current = methods.where((item) => item.id == _paymentMethodId);
      if (current.isNotEmpty) _selectedPayment = _tileForMethod(current.first);
    }
    final height =
        MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).bottom -
        24 -
        kMinInteractiveDimension;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: height.clamp(300.0, MediaQuery.sizeOf(context).height),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.record == null ? 'New Record' : 'Edit Record',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
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
                    SegmentedToggle<MoneyDirection>(
                      segments: const [
                        ButtonSegment(
                          value: MoneyDirection.given,
                          label: Text('I gave'),
                        ),
                        ButtonSegment(
                          value: MoneyDirection.borrowed,
                          label: Text('I borrowed'),
                        ),
                      ],
                      selected: {_direction},
                      filled: true,
                      selectedBackground: _direction == MoneyDirection.given
                          ? financeSelectedFill(context)
                          : AppTheme.colorsOf(
                              context,
                            ).pay.withValues(alpha: 0.12),
                      selectedForeground: _direction == MoneyDirection.given
                          ? Theme.of(context).colorScheme.primary
                          : AppTheme.colorsOf(context).pay,
                      onSelectionChanged: widget.record == null
                          ? (value) => setState(() => _direction = value.single)
                          : null,
                    ),
                    if (widget.record != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Direction is fixed for an existing record.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 24),
                    HeroAmountInput(
                      controller: _amount,
                      label: 'AMOUNT',
                      validator: amountText,
                      calculator: () =>
                          openCalculator(
                            context,
                            initial: _amount.text,
                            amountLabel: 'Amount',
                          ).then((value) {
                            if (value != null && mounted) {
                              setState(() => _amount.text = value);
                            }
                          }),
                    ),
                    const SizedBox(height: 24),
                    FilledField(
                      label: 'PERSON',
                      child: TextFormField(
                        controller: _person,
                        textCapitalization: TextCapitalization.words,
                        decoration: financeFieldDecoration(
                          context,
                          hint: 'Select or enter person',
                          icon: Icons.person_outline,
                        ),
                        validator: requiredText,
                      ),
                    ),
                    _RecentMoneyPeople(
                      selected: _person,
                      onSelected: (name) => setState(() => _person.text = name),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: DateTile(
                            label: 'RECORD DATE',
                            value: _date,
                            onChanged: (value) {
                              if (value != null) setState(() => _date = value);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DateTile(
                            label: 'DUE DATE',
                            value: _due,
                            allowClear: true,
                            onChanged: (value) => setState(() => _due = value),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final chip in const [
                          'Today',
                          '+7 days',
                          '+30 days',
                          'Custom',
                          'None',
                        ])
                          ActionChip(
                            label: Text(chip),
                            onPressed: () async {
                              if (chip == 'None') {
                                setState(() => _due = null);
                                return;
                              }
                              if (chip == 'Custom') {
                                final picked = await pickAppDate(
                                  context,
                                  _due ?? DateTime.now(),
                                );
                                if (mounted && picked != null) {
                                  setState(() => _due = picked);
                                }
                                return;
                              }
                              final today = DateTime.now();
                              final offset = chip == 'Today'
                                  ? 0
                                  : chip == '+7 days'
                                  ? 7
                                  : 30;
                              setState(
                                () => _due = DateTime(
                                  today.year,
                                  today.month,
                                  today.day + offset,
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const FinanceFieldLabel('PAYMENT METHOD'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (final entry in const [
                          ('CASH', Icons.payments_outlined),
                          ('UPI', Icons.qr_code_2),
                          ('CARD', Icons.credit_card_outlined),
                          ('TRANSFER', Icons.account_balance_outlined),
                        ])
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(
                                right: entry.$1 == 'TRANSFER' ? 0 : 8,
                              ),
                              child: OptionTile(
                                label: entry.$1,
                                icon: entry.$2,
                                selected: _selectedPayment == entry.$1,
                                onTap: () => setState(() {
                                  _selectedPayment = entry.$1;
                                  _paymentMethodId = _methodIdForTile(
                                    entry.$1,
                                    methods,
                                  );
                                }),
                              ),
                            ),
                          ),
                      ],
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
                        minLines: 2,
                        maxLines: 4,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      shape: const StadiumBorder(),
                      minimumSize: const Size.fromHeight(54),
                    ),
                    onPressed: _save,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save Record'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _tileForMethod(PaymentMethod method) {
    final text = '${method.label} ${method.kind}'.toLowerCase();
    if (text.contains('cash')) return 'CASH';
    if (text.contains('upi')) return 'UPI';
    if (text.contains('card')) return 'CARD';
    return 'TRANSFER';
  }

  int? _methodIdForTile(String tile, List<PaymentMethod> methods) {
    final matches = methods.where((method) => _tileForMethod(method) == tile);
    return matches.isEmpty ? null : matches.first.id;
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    try {
      final item = MoneyRecordsCompanion(
        id: widget.record == null
            ? const Value.absent()
            : Value(widget.record!.id),
        personName: Value(_person.text.trim()),
        direction: Value(_direction),
        amountPaise: Value(parseRupeesToPaise(_amount.text)),
        recordDate: Value(_date),
        dueDate: Value(_due),
        paymentMethodId: Value(_paymentMethodId),
        status: Value(widget.record?.status ?? MoneyStatus.active),
        notes: Value(_notes.text.trim().isEmpty ? null : _notes.text.trim()),
        updatedAt: Value(DateTime.now()),
      );
      final repo = ref.read(financeRepositoryProvider);
      closeFinanceSheetAndSave(context, () async {
        await repo.saveMoneyRecord(item);
      }, errorMessage: 'Could not save this money record.');
    } on FormatException catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message.toString())));
    }
  }
}

class _RecentMoneyPeople extends ConsumerStatefulWidget {
  const _RecentMoneyPeople({required this.selected, required this.onSelected});

  final TextEditingController selected;
  final ValueChanged<String> onSelected;

  @override
  ConsumerState<_RecentMoneyPeople> createState() => _RecentMoneyPeopleState();
}

class _RecentMoneyPeopleState extends ConsumerState<_RecentMoneyPeople> {
  Animation<double>? _routeAnimation;
  bool _ready = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (_routeAnimation != animation) {
      _routeAnimation?.removeStatusListener(_onAnimationStatus);
      _routeAnimation = animation;
      animation?.addStatusListener(_onAnimationStatus);
    }
    if (animation == null || animation.status == AnimationStatus.completed) {
      _ready = true;
    }
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _ready) return;
    _routeAnimation?.removeStatusListener(_onAnimationStatus);
    setState(() => _ready = true);
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_onAnimationStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.shrink();
    final records =
        ref.watch(moneyRecordsProvider).valueOrNull ??
        const <MoneyRecordDetail>[];
    final recent = [...records]
      ..sort((a, b) => b.record.updatedAt.compareTo(a.record.updatedAt));
    final people = recent
        .map((item) => item.record.personName.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .take(6)
        .toList();
    if (people.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: ChipSelector(
        options: people,
        selected: widget.selected.text,
        onSelected: widget.onSelected,
      ),
    );
  }
}

class RepaymentSheet extends ConsumerStatefulWidget {
  const RepaymentSheet({
    super.key,
    required this.recordId,
    required this.remainingPaise,
  });

  final int recordId;
  final int remainingPaise;

  @override
  ConsumerState<RepaymentSheet> createState() => _RepaymentSheetState();
}

class _RepaymentSheetState extends ConsumerState<RepaymentSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  DateTime _paidOn = DateTime.now();
  String _quickAmount = 'Custom';
  String _quickDate = 'Today';

  String? _validateRepaymentAmount(String? value) {
    final base = amountText(value);
    if (base != null) return base;
    final amount = parseRupeesToPaise(value!);
    if (amount > widget.remainingPaise) {
      return 'Repayment cannot be greater than the remaining balance of ${formatMoney(widget.remainingPaise)}.';
    }
    return null;
  }

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height =
        MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).bottom -
        24 -
        kMinInteractiveDimension;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: height.clamp(300.0, MediaQuery.sizeOf(context).height),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Add repayment',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Remaining ${formatMoney(widget.remainingPaise)}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: AppTheme.colorsOf(
                                    context,
                                  ).secondaryText,
                                ),
                          ),
                        ],
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
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    HeroAmountInput(
                      controller: _amount,
                      label: 'REPAYMENT AMOUNT',
                      validator: _validateRepaymentAmount,
                      onChanged: (_) {
                        if (_quickAmount != 'Custom') {
                          setState(() => _quickAmount = 'Custom');
                        }
                        _formKey.currentState?.validate();
                      },
                      calculator: () async {
                        final value = await openCalculator(
                          context,
                          initial: _amount.text,
                          amountLabel: 'Repayment amount',
                        );
                        if (value != null && mounted) {
                          _amount.text = value;
                          setState(() => _quickAmount = 'Custom');
                          _formKey.currentState?.validate();
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    ChipSelector(
                      options: [
                        'Full ${formatMoney(widget.remainingPaise)}',
                        'Half ${formatMoney(widget.remainingPaise ~/ 2)}',
                        'Custom',
                      ],
                      selected: _quickAmount,
                      onSelected: (choice) {
                        setState(() => _quickAmount = choice);
                        if (choice.startsWith('Full')) {
                          _amount.text = rupeesText(widget.remainingPaise);
                        }
                        if (choice.startsWith('Half')) {
                          _amount.text = rupeesText(widget.remainingPaise ~/ 2);
                        }
                        _formKey.currentState?.validate();
                      },
                    ),
                    const SizedBox(height: 24),
                    const FinanceFieldLabel('DATE'),
                    const SizedBox(height: 8),
                    ChipSelector(
                      options: const ['Today', 'Yesterday', 'Pick date'],
                      selected: _quickDate,
                      onSelected: (choice) async {
                        if (choice == 'Pick date') {
                          final picked = await pickAppDate(context, _paidOn);
                          if (picked != null && mounted) {
                            setState(() {
                              _paidOn = picked;
                              _quickDate = choice;
                            });
                          }
                          return;
                        }
                        final now = DateTime.now();
                        setState(() {
                          _paidOn = DateTime(
                            now.year,
                            now.month,
                            now.day - (choice == 'Yesterday' ? 1 : 0),
                          );
                          _quickDate = choice;
                        });
                      },
                    ),
                    if (_quickDate == 'Pick date') ...[
                      const SizedBox(height: 6),
                      Text(
                        formatDate(_paidOn),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledField(
                      label: 'NOTE (OPTIONAL)',
                      child: TextFormField(
                        controller: _notes,
                        decoration: financeFieldDecoration(
                          context,
                          hint: 'Add a note',
                        ),
                        maxLines: 2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ChipSelector(
                      options: const ['Cash', 'UPI', 'Bank transfer'],
                      selected: _notes.text,
                      onSelected: (choice) =>
                          setState(() => _notes.text = choice),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      shape: const StadiumBorder(),
                      minimumSize: const Size.fromHeight(54),
                    ),
                    onPressed: _save,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final amount = parseRupeesToPaise(_amount.text);
    final notes = _notes.text.trim();
    final repo = ref.read(financeRepositoryProvider);
    closeFinanceSheetAndSave(
      context,
      () => repo.addRepayment(
        widget.recordId,
        amount,
        notes.isEmpty ? null : notes,
        _paidOn,
      ),
      errorMessage: 'Could not save this repayment.',
    );
  }
}
