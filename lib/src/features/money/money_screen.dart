import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/formatters.dart';
import '../../core/app_theme.dart';
import '../../core/providers.dart';
import '../../data/database.dart';
import '../../data/repositories.dart';
import '../../domain/enums.dart';
import '../../domain/reminder_schedule.dart';
import '../reminders/section_reminders_sheet.dart';
import '../../domain/due_status.dart';
import '../../shared/async_view.dart';
import '../../shared/calculator_sheet.dart';
import '../../shared/empty_state.dart';
import '../../shared/forms.dart';
import '../../shared/finance_form_widgets.dart';
import '../../shared/finance_display_widgets.dart';
import '../../shared/notched_navigation_bar.dart';
import '../assistant/ask_finkeep_sheet.dart';

class MoneyScreen extends ConsumerStatefulWidget {
  const MoneyScreen({super.key});

  @override
  ConsumerState<MoneyScreen> createState() => _MoneyScreenState();
}

enum _MoneyFilter { all, unpaid, partial, overdue, settled }

enum _MoneyRowAction { edit, repayment, add, history, delete }

String _moneyPhoneKey(String name) =>
    'money.phone.${name.trim().toLowerCase()}';
String _moneyRemindedKey(int id) => 'money.reminded.$id';

String _moneyReminderMessage(MoneyRecordDetail detail, {int? amountPaise}) {
  final record = detail.record;
  final amount = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: (amountPaise ?? detail.summary.remainingAmountPaise) % 100 == 0 ? 0 : 2,
  ).format((amountPaise ?? detail.summary.remainingAmountPaise) / 100);
  final date = record.dueDate == null
      ? null
      : DateFormat('dd MMM').format(record.dueDate!);
  final overdue = record.dueDate != null &&
      DateUtils.dateOnly(record.dueDate!).isBefore(
        DateUtils.dateOnly(DateTime.now()),
      );
  final name = displayName(record.personName);
  if (overdue) {
    return 'Hi $name, $amount was due on $date. Could you please send it today? Thank you!';
  }
  if (date != null) {
    return 'Hi $name, a gentle reminder that $amount is due on $date. Please send it when you can. Thank you!';
  }
  return 'Hi $name, a gentle reminder about $amount. Please send it when you can. Thank you!';
}

Future<String?> _savedMoneyPhone(AppDatabase db, String name) async {
  final row = await (db.select(db.settings)
        ..where((setting) => setting.key.equals(_moneyPhoneKey(name))))
      .getSingleOrNull();
  return row?.value;
}

String _whatsAppDigits(String phone) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 10) return '91$digits';
  if (digits.length == 11 && digits.startsWith('0')) {
    return '91${digits.substring(1)}';
  }
  return digits;
}

Future<void> _shareMoneyReminder(
  BuildContext context,
  MoneyRecordDetail detail,
  {int? amountPaise}
) async {
  final db = ProviderScope.containerOf(context).read(databaseProvider);
  final phone = await _savedMoneyPhone(db, detail.record.personName);
  if (!context.mounted) return;
  if (phone == null || _whatsAppDigits(phone).length < 11) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Add a phone number for ${displayName(detail.record.personName)}'),
        action: SnackBarAction(
          label: 'Edit',
          onPressed: () => openFinanceSheet(
            context,
            MoneyFormSheet(record: detail.record),
          ),
        ),
      ),
    );
    return;
  }
  final digits = _whatsAppDigits(phone);
  final message = _moneyReminderMessage(detail, amountPaise: amountPaise);
  final uri = Uri.parse(
    'https://wa.me/$digits?text=${Uri.encodeComponent(message)}',
  );
  AppLifecycleListener? listener;
  var leftApp = false;
  listener = AppLifecycleListener(
    onStateChange: (state) {
      if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.hidden) {
        leftApp = true;
      } else if (state == AppLifecycleState.resumed && leftApp) {
        listener?.dispose();
        unawaited(db.into(db.settings).insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: _moneyRemindedKey(detail.record.id),
            value: DateTime.now().toIso8601String(),
          ),
        ));
      }
    },
  );
  try {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
  } catch (error) {
    debugPrint('WhatsApp reminder launch failed: $error');
  }
  listener.dispose();
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Could not open WhatsApp.'),
          Row(
            children: [
              TextButton(
                onPressed: () => Clipboard.setData(ClipboardData(text: message)),
                child: const Text('Copy message'),
              ),
              TextButton(
                onPressed: () => launchUrl(
                  Uri.parse('sms:$digits?body=${Uri.encodeComponent(message)}'),
                  mode: LaunchMode.externalApplication,
                ),
                child: const Text('Send SMS'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

Future<void> shareMoneyReminder(
  BuildContext context,
  MoneyRecordDetail detail,
  {int? amountPaise}
) => _shareMoneyReminder(context, detail, amountPaise: amountPaise);

String? _moneyAmountText(String? value) {
  final error = amountText(value);
  if (error != null) return error;
  final normalized = value!.trim().replaceAll(',', '');
  if (!RegExp(r'^(?:\d+(?:\.\d{1,2})?|\.\d{1,2})$').hasMatch(normalized)) {
    return 'Use at most 2 decimal places';
  }
  return null;
}

String _moneyRelativeDue(DateTime due, DateTime today) {
  return formatDayDistance(due, today);
}

String _moneyDatedDue(DateTime due, DateTime today) =>
    formatDatedDistance(due, today);

class _PersonBalance {
  _PersonBalance(this.name, this.records);

  final String name;
  final List<MoneyRecordDetail> records;

  late final int total = records.fold(
    0,
    (sum, item) => sum + item.record.amountPaise,
  );
  late final int remaining = records.fold(
    0,
    (sum, item) => sum + item.summary.remainingAmountPaise,
  );
  late final int repaid = records.fold(
    0,
    (sum, item) => sum + item.summary.repaidAmountPaise,
  );
  DateTime? get settledOn {
    if (remaining > 0) return null;
    final dates =
        records
            .expand((item) => item.repayments)
            .map((payment) => payment.paidOn)
            .toList()
          ..sort();
    return dates.lastOrNull;
  }

  late final DateTime? nearestDue = () {
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
  }();

  late final bool overdue =
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
      final relative = _moneyRelativeDue(nearestDue!, DateTime.now());
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

const _moneyPersonColors = <Color>[
  Color(0xFF1D4ED8),
  Color(0xFF6D28D9),
  Color(0xFFBE185D),
  Color(0xFF4338CA),
  Color(0xFFA21CAF),
  Color(0xFFB45309),
];

Color _moneyInk(BuildContext context) => AppTheme.colorsOf(context).text;
Color _moneyMuted(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? AppTheme.colorsOf(context).secondaryText
    : const Color(0xFF475569);
Color _moneyBorder(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? AppTheme.colorsOf(context).outline
    : const Color(0xFFE6ECE9);
Color _moneyAccent(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? Theme.of(context).colorScheme.primary
    : const Color(0xFF0F6B5C);

DueListGroup _moneyDueGroup(DateTime? due, DateTime today) {
  if (due == null) return DueListGroup.nextMonthAndBeyond;
  final dueDay = DateTime(due.year, due.month, due.day);
  if (dueDay.isBefore(today)) return DueListGroup.overdue;
  if (dueDay.difference(today).inDays <= 7) return DueListGroup.thisWeek;
  if (dueDay.year == today.year && dueDay.month == today.month) {
    return DueListGroup.laterThisMonth;
  }
  return DueListGroup.nextMonthAndBeyond;
}

typedef _MoneyVisualKey = ({MoneyDirection direction, DateTime today});
final _moneyVisualProvider =
    Provider.family<_MoneyVisualData?, _MoneyVisualKey>((ref, key) {
      final records = ref.watch(moneyRecordsProvider).valueOrNull;
      if (records == null) return null;
      return _MoneyVisualData(
        records
            .where((item) => item.record.direction == key.direction)
            .toList(),
        key.today,
      );
    });

final _moneyRemindedProvider = StreamProvider<Map<int, DateTime>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.settings)
        ..where((setting) => setting.key.like('money.reminded.%')))
      .watch()
      .map((rows) {
        final result = <int, DateTime>{};
        for (final row in rows) {
          final id = int.tryParse(row.key.substring('money.reminded.'.length));
          final date = DateTime.tryParse(row.value);
          if (id != null && date != null) result[id] = date;
        }
        return result;
      });
});

class _MoneyVisualData {
  _MoneyVisualData(List<MoneyRecordDetail> records, DateTime now)
    : people = _groupMoneyRecords(records),
      today = DateTime(now.year, now.month, now.day),
      months = List.generate(6, (index) {
        final month = DateTime(now.year, now.month + index);
        final due = records
            .where(
              (item) =>
                  item.summary.remainingAmountPaise > 0 &&
                  item.record.dueDate?.year == month.year &&
                  item.record.dueDate?.month == month.month,
            )
            .toList();
        return (month, due);
      });

  final List<_PersonBalance> people;
  final DateTime today;
  final List<(DateTime, List<MoneyRecordDetail>)> months;
  late final int originalTotal = people.fold(
    0,
    (sum, person) => sum + person.total,
  );
  late final int repaid = people.fold(
    0,
    (sum, person) => sum + person.repaid,
  );
  late final int outstanding = originalTotal - repaid;
  late final List<_PersonBalance> overduePeople = people
      .where((person) => person.overdue)
      .toList();
  late final int overdueTotal = overduePeople.fold<int>(
    0,
    (sum, person) => sum + person.remaining,
  );
  late final Map<String, Color> personColors = () {
    final ordered = people.toList()
      ..sort(
        (a, b) =>
            a.records.first.record.id.compareTo(b.records.first.record.id),
      );
    return {
      for (var index = 0; index < ordered.length; index++)
        ordered[index].name.toLowerCase(): switch (ordered[index].name.toLowerCase()) {
          'sandeep' => const Color(0xFF4338CA),
          'laxman' => const Color(0xFF7E22CE),
          'jeevan' => const Color(0xFFBE185D),
          _ => _moneyPersonColors[index % _moneyPersonColors.length],
        },
    };
  }();
  late final List<int> monthTotals = [
    for (final month in months)
      month.$2.fold<int>(
        0,
        (sum, item) => sum + item.summary.remainingAmountPaise,
      ),
  ];
  late final List<_PersonBalance> active = people
      .where((person) => person.remaining > 0)
      .toList();
  late final List<RingSegment> ringSegments = active.isEmpty
      ? [
          const RingSegment(
            label: 'All settled',
            paid: 1,
            total: 1,
            color: Color(0xFF0F6B5C),
          ),
        ]
      : [
          for (var index = 0; index < active.length && index < 6; index++)
            RingSegment(
              label: active[index].name,
              paid: active[index].remaining,
              total: active[index].remaining,
              color: _moneyPersonColors[index],
            ),
          if (active.length > 6)
            RingSegment(
              label: 'Others',
              paid: active
                  .skip(6)
                  .fold<int>(0, (sum, person) => sum + person.remaining),
              total: active
                  .skip(6)
                  .fold<int>(0, (sum, person) => sum + person.remaining),
              color: const Color(0xFF64748B),
            ),
        ];
  late final _PersonBalance? biggest = () {
    final ranked = active.toList()
      ..sort((a, b) => b.remaining.compareTo(a.remaining));
    return ranked.firstOrNull;
  }();

  late final List<MoneyRecordDetail> dueSoonRecords = [
    for (final person in active)
      for (final item in person.records)
        if (item.summary.remainingAmountPaise > 0 &&
            item.record.dueDate != null &&
            DateTime(
                  item.record.dueDate!.year,
                  item.record.dueDate!.month,
                  item.record.dueDate!.day,
                ).difference(today).inDays >=
                0 &&
            DateTime(
                  item.record.dueDate!.year,
                  item.record.dueDate!.month,
                  item.record.dueDate!.day,
                ).difference(today).inDays <=
                7)
          item,
  ];
  late final List<_PersonBalance> dueSoonPeople = active
      .where(
        (person) => dueSoonRecords.any(
          (item) =>
              item.record.personName.trim().toLowerCase() ==
              person.name.trim().toLowerCase(),
        ),
      )
      .toList();
  late final MoneyRecordDetail? nextDatedRecord = () {
    final sorted = active
        .expand((person) => person.records)
        .where(
          (item) =>
              item.summary.remainingAmountPaise > 0 &&
              item.record.dueDate != null &&
              !DateUtils.dateOnly(item.record.dueDate!).isBefore(today),
        )
        .toList()
      ..sort((a, b) => a.record.dueDate!.compareTo(b.record.dueDate!));
    return sorted.firstOrNull;
  }();
}

class _MoneyScreenState extends ConsumerState<MoneyScreen> {
  MoneyDirection _direction = MoneyDirection.given;
  final _filters = <MoneyDirection, _MoneyFilter>{
    MoneyDirection.given: _MoneyFilter.all,
    MoneyDirection.borrowed: _MoneyFilter.all,
  };
  final _searches = <MoneyDirection, TextEditingController>{
    MoneyDirection.given: TextEditingController(),
    MoneyDirection.borrowed: TextEditingController(),
  };
  final _chipScrolls = <MoneyDirection, ScrollController>{
    MoneyDirection.given: ScrollController(),
    MoneyDirection.borrowed: ScrollController(),
  };
  final _queries = <MoneyDirection, String>{
    MoneyDirection.given: '',
    MoneyDirection.borrowed: '',
  };
  Timer? _searchDebounce;
  bool _showScrolledTotal = false;
  final _scrolledPastTotal = <MoneyDirection, bool>{};
  final _remindersInFlight = <int>{};
  final _pageController = PageController();
  _MoneyVisualData _visualFor(
    List<MoneyRecordDetail> items,
    MoneyDirection direction,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return ref.watch(
          _moneyVisualProvider((direction: direction, today: today)),
        ) ??
        _MoneyVisualData(
          items.where((item) => item.record.direction == direction).toList(),
          now,
        );
  }

  void _selectDirection(MoneyDirection direction) {
    _pageController.animateToPage(
      direction == MoneyDirection.given ? 0 : 1,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Future<void> _remindPerson(_PersonBalance person) async {
    final open = person.records
        .where((item) => item.summary.remainingAmountPaise > 0)
        .toList()
      ..sort((a, b) {
        final aDue = a.record.dueDate;
        final bDue = b.record.dueDate;
        if (aDue == null) return bDue == null ? 0 : 1;
        if (bDue == null) return -1;
        return aDue.compareTo(bDue);
      });
    if (open.isNotEmpty) await _remindRecord(open.first);
  }

  Future<void> _remindRecord(MoneyRecordDetail detail) async {
    if (!_remindersInFlight.add(detail.record.id)) return;
    try {
      await _shareMoneyReminder(context, detail);
    } catch (error, stackTrace) {
      debugPrint('Could not open Money reminder: $error\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open the reminder. Please try again.'),
          ),
        );
      }
    } finally {
      _remindersInFlight.remove(detail.record.id);
    }
  }

  Future<MoneyRecordDetail?> _pickPersonRecord(
    List<MoneyRecordDetail> records,
  ) async {
    if (records.length == 1) return records.first;
    return showModalBottomSheet<MoneyRecordDetail>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Choose a record')),
            for (final detail in records)
              ListTile(
                title: Text(displayName(detail.record.personName)),
                subtitle: Text(
                  '${formatDate(detail.record.recordDate)} · ${detail.summary.remainingAmountPaise == 0 ? 'Settled' : 'Open'}',
                ),
                trailing: AmountText(detail.summary.remainingAmountPaise),
                onTap: () => Navigator.pop(sheetContext, detail),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPersonActions(_PersonBalance person) async {
    final open = person.records
        .where((detail) => detail.summary.remainingAmountPaise > 0)
        .toList();
    final action = await showModalBottomSheet<_MoneyRowAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(displayName(person.name))),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () => Navigator.pop(sheetContext, _MoneyRowAction.edit),
            ),
            if (open.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.payments_outlined),
                title: const Text('Record payment'),
                onTap: () =>
                    Navigator.pop(sheetContext, _MoneyRowAction.repayment),
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Add record'),
              onTap: () => Navigator.pop(sheetContext, _MoneyRowAction.add),
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('History'),
              onTap: () => Navigator.pop(sheetContext, _MoneyRowAction.history),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onTap: () => Navigator.pop(sheetContext, _MoneyRowAction.delete),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == _MoneyRowAction.add) {
      openFinanceSheet(
        context,
        MoneyFormSheet(
          initialDirection: _direction,
          initialPerson: person.name,
        ),
      );
      return;
    }
    if (action == _MoneyRowAction.history) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MoneyPersonScreen(person.name, _direction),
        ),
      );
      return;
    }
    final detail = await _pickPersonRecord(
      action == _MoneyRowAction.repayment ? open : person.records,
    );
    if (!mounted || detail == null) return;
    switch (action) {
      case _MoneyRowAction.edit:
        openFinanceSheet(context, MoneyFormSheet(record: detail.record));
      case _MoneyRowAction.repayment:
        openFinanceSheet(
          context,
          RepaymentSheet(
            recordId: detail.record.id,
            remainingPaise: detail.summary.remainingAmountPaise,
          ),
        );
      case _MoneyRowAction.delete:
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
        if (confirmed == true && mounted) {
          await ref
              .read(financeRepositoryProvider)
              .deleteMoneyRecord(detail.record.id);
        }
      case _MoneyRowAction.add:
      case _MoneyRowAction.history:
        break;
    }
  }

  void _openInsight(_MoneyInsight insight, _MoneyVisualData visual) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => _MoneyInsightSheet(
        insight: insight,
        visual: visual,
        direction: _direction,
      ),
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _pageController.dispose();
    for (final controller in _searches.values) {
      controller.dispose();
    }
    for (final controller in _chipScrolls.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _buildPage(
    BuildContext context,
    List<MoneyRecordDetail> items,
    MoneyDirection direction,
  ) {
    final visual = _visualFor(items, direction);
    final reminded = ref.watch(_moneyRemindedProvider).valueOrNull ?? const <int, DateTime>{};
    final people = visual.people;
    final filter = _filters[direction]!;
    final query = _queries[direction]!;
    final visible = people.where((person) {
      final matches = switch (filter) {
        _MoneyFilter.all => true,
        _MoneyFilter.unpaid => person.remaining > 0 && person.repaid == 0,
        _MoneyFilter.partial => person.remaining > 0 && person.repaid > 0,
        _MoneyFilter.overdue => person.overdue,
        _MoneyFilter.settled => person.remaining == 0,
      };
      return matches &&
          (query.isEmpty || person.name.toLowerCase().contains(query));
    }).toList();
    final grouped = <DueListGroup, List<_PersonBalance>>{};
    final settled = <_PersonBalance>[];
    for (final person in visible) {
      if (person.remaining == 0) {
        settled.add(person);
      } else {
        grouped
            .putIfAbsent(
              _moneyDueGroup(person.nearestDue, visual.today),
              () => [],
            )
            .add(person);
      }
    }
    final rows = <(String?, _PersonBalance?, int)>[];
    for (final group in DueListGroup.values) {
      final members = grouped[group];
      if (members == null || members.isEmpty) continue;
      final total = members.fold<int>(
        0,
        (sum, person) => sum + person.remaining,
      );
      rows.add((
        switch (group) {
          DueListGroup.overdue => 'Overdue',
          DueListGroup.thisWeek => 'Within 7 days',
          DueListGroup.laterThisMonth => 'This month',
          DueListGroup.nextMonthAndBeyond || DueListGroup.noDueDate => 'Later',
        },
        null,
        total,
      ));
      for (final person in members) {
        rows.add((null, person, 0));
      }
    }
    if (settled.isNotEmpty) {
      rows.add((
        filter == _MoneyFilter.settled
            ? 'Settled'
            : 'Settled · ${settled.length} ${settled.length == 1 ? 'person' : 'people'}',
        null,
        settled.fold<int>(0, (sum, person) => sum + person.repaid),
      ));
      if (filter == _MoneyFilter.settled) {
        for (final person in settled) {
          rows.add((null, person, 0));
        }
      }
    }
    return ScrollConfiguration(
      behavior: const _MoneyClampedScrollBehavior(),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (direction != _direction) return false;
          final past = notification.metrics.pixels > 80;
          _scrolledPastTotal[direction] = past;
          if (past != _showScrolledTotal) {
            setState(() => _showScrolledTotal = past);
          }
          return false;
        },
        child: Stack(
          children: [
          CustomScrollView(
          key: PageStorageKey('money-${direction.name}'),
          physics: const ClampingScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.only(top: 8),
              sliver: SliverToBoxAdapter(
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MoneyHero(
                    visual: visual,
                    direction: direction,
                    onInsight: (insight) => _openInsight(insight, visual),
                  ),
                  if (people.length >= 6)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: TextField(
                        controller: _searches[direction],
                        onChanged: (value) {
                          _searchDebounce?.cancel();
                          _searchDebounce = Timer(
                            const Duration(milliseconds: 180),
                            () {
                              if (mounted) {
                                setState(
                                  () => _queries[direction] = value
                                      .trim()
                                      .toLowerCase(),
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
                    ),
                  Padding(
                    padding: EdgeInsets.only(
                      top: 20,
                    ),
                    child: Stack(
                      children: [
                        SingleChildScrollView(
                          controller: _chipScrolls[direction],
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.only(left: 16, right: 40),
                          child: Row(
                            children: [
                              for (final entry in const [
                                (_MoneyFilter.all, 'All'),
                                (_MoneyFilter.unpaid, 'Unpaid'),
                                (_MoneyFilter.partial, 'Partly paid'),
                                (_MoneyFilter.overdue, 'Overdue'),
                                (_MoneyFilter.settled, 'Settled'),
                              ])
                                Padding(
                                  padding: const EdgeInsets.only(right: 7),
                                  child: SizedBox(
                                    height: 40,
                                    child: ChoiceChip(
                                    label: Text(entry.$2),
                                    selected: filter == entry.$1,
                                    showCheckmark: false,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    onSelected: (_) => setState(
                                      () => _filters[direction] = entry.$1,
                                    ),
                                    selectedColor:
                                        Theme.of(context).brightness == Brightness.dark
                                            ? const Color(0xFFF1F5F9)
                                            : const Color(0xFF0F172A),
                                    backgroundColor: Colors.transparent,
                                    side: filter == entry.$1
                                        ? BorderSide.none
                                        : BorderSide(
                                            color: _moneyBorder(context),
                                          ),
                                    labelStyle: TextStyle(
                                      color: filter == entry.$1
                                          ? Theme.of(context).brightness == Brightness.dark
                                              ? const Color(0xFF0F172A)
                                              : Colors.white
                                          : _moneyMuted(context),
                                      fontWeight: filter == entry.$1
                                          ? FontWeight.w700
                                          : FontWeight.w600,
                                    ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Positioned(
                          top: 0,
                          bottom: 0,
                          right: 0,
                          child: IgnorePointer(
                            child: Container(
                              width: 24,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Theme.of(context).scaffoldBackgroundColor
                                        .withValues(alpha: 0),
                                    Theme.of(context).scaffoldBackgroundColor,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (visible.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            people.isEmpty
                                ? 'No records yet. Tap + to add money you ${direction == MoneyDirection.given ? 'gave' : 'borrowed'}.'
                                : 'No matching records.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: _moneyMuted(context)),
                          ),
                          if (people.isEmpty)
                            TextButton(
                              onPressed: () => openFinanceSheet(
                                context,
                                MoneyFormSheet(initialDirection: direction),
                              ),
                              child: const Text('Add record'),
                            ),
                        ],
                      ),
                    ),
                ],
                ),
              ),
            ),
            SliverList.builder(
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final row = rows[index];
                final person = row.$2;
                if (person == null) {
                  final isSettled = row.$1!.startsWith('Settled');
                  final count = isSettled
                      ? settled.length
                      : rows
                            .skip(index + 1)
                            .takeWhile((item) => item.$2 != null)
                            .length;
                  return InkWell(
                    onTap: isSettled && filter != _MoneyFilter.settled
                        ? () => setState(
                            () => _filters[direction] = _MoneyFilter.settled,
                          )
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              row.$1!,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: row.$1 == 'Overdue'
                                        ? AppTheme.colorsOf(context).pay
                                        : _moneyInk(context),
                                  ),
                            ),
                          ),
                          if (!isSettled || filter == _MoneyFilter.settled)
                            Text(
                              '$count ${count == 1 ? 'person' : 'people'} · ',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: _moneyMuted(context)),
                            ),
                          AmountText(
                            row.$3,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: _moneyInk(context),
                                  fontWeight: FontWeight.w700,
                              ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      _MoneyPersonTile(
                        key: ValueKey(
                          '${direction.name}:${person.name.toLowerCase()}',
                        ),
                        person: person,
                        avatarColor:
                            visual.personColors[person.name.toLowerCase()]!,
                        direction: direction,
                        lastReminded: person.records
                            .map((item) => reminded[item.record.id])
                            .whereType<DateTime>()
                            .fold<DateTime?>(
                              null,
                              (latest, date) =>
                                  latest == null || date.isAfter(latest)
                                  ? date
                                  : latest,
                            ),
                        onRemind: person.remaining > 0
                            ? () => _remindPerson(person)
                            : null,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => MoneyPersonScreen(
                              person.name,
                              direction,
                            ),
                          ),
                        ),
                        onLongPress: () => _showPersonActions(person),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                );
              },
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: NotchedNavigationMetrics.contentPadding(context),
              ),
            ),
          ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 12,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Theme.of(context).colorScheme.surface,
                      Theme.of(context).colorScheme.surface.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AsyncView(
        value: ref.watch(moneyRecordsProvider),
        builder: (items) {
          return Column(
            children: [
              ColoredBox(
                color: Theme.of(context).colorScheme.surface,
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      SizedBox(
                        height: 56,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Money',
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              Tooltip(
                                message: 'Ask AI',
                                child: IconButton.filledTonal(
                                  onPressed: () => openAskFinKeep(context),
                                  icon: const Icon(Icons.auto_awesome, size: 18),
                                ),
                              ),
                              const SectionReminderButton(
                                type: FinanceReminderType.money,
                              ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: SizedBox(
                          width: double.infinity,
                          child: SegmentedToggle<MoneyDirection>(
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
                            selectedBackground: _moneyAccent(context),
                            selectedForeground: Theme.of(context).colorScheme.onPrimary,
                            onSelectionChanged: (value) =>
                                _selectDirection(value.single),
                          ),
                        ),
                      ),
                      Container(
                        height: 1,
                        color: _showScrolledTotal
                            ? _moneyBorder(context)
                            : Theme.of(context).colorScheme.surface,
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (page) {
                    final next = page == 0
                        ? MoneyDirection.given
                        : MoneyDirection.borrowed;
                    for (final chips in _chipScrolls.values) {
                      if (chips.hasClients) chips.jumpTo(0);
                    }
                    setState(() {
                      _direction = next;
                      _showScrolledTotal = _scrolledPastTotal[next] ?? false;
                    });
                  },
                  children: [
                    _buildPage(context, items, MoneyDirection.given),
                    _buildPage(context, items, MoneyDirection.borrowed),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final int value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final color = emphasized ? _moneyAccent(context) : _moneyInk(context);
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Text(
            '$label ',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          AmountText(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: emphasized ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

enum _MoneyInsight { due, recovered, biggest }

class _MoneyHero extends StatelessWidget {
  const _MoneyHero({
    required this.visual,
    required this.direction,
    required this.onInsight,
  });

  final _MoneyVisualData visual;
  final MoneyDirection direction;
  final ValueChanged<_MoneyInsight> onInsight;

  @override
  Widget build(BuildContext context) {
    final given = direction == MoneyDirection.given;
    final percent = visual.originalTotal == 0
        ? 0
        : (visual.repaid * 100 / visual.originalTotal).round();
    const white = Color(0xFFF8FAF9);
    final muted = white.withValues(alpha: 0.75);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? null : const Color(0xFF17493B),
        gradient: Theme.of(context).brightness == Brightness.dark
            ? const LinearGradient(colors: [
                Color(0xFF17493B), Color(0xFF0F3328)]) : null,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      given ? 'To get back' : 'To pay back',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: muted, fontSize: 13),
                    ),
                    const SizedBox(height: 5),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: AmountText(
                        visual.outstanding,
                        style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          color: white,
                          fontSize: 40,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 84,
                child: Column(
                  children: [
                    RepaintBoundary(
                      child: MiniProgressRing(
                        progress: visual.originalTotal == 0
                            ? 0
                            : visual.repaid / visual.originalTotal,
                        size: 84,
                        strokeWidth: 8,
                        color: const Color(0xFF7EE2B0),
                        backgroundColor: white.withValues(alpha: 0.18),
                        child: Center(
                          child: Text(
                            '$percent%',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(color: white, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      given ? 'recovered' : 'repaid',
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Divider(height: 1, color: white.withValues(alpha: 0.18)),
          const SizedBox(height: 14),
          Row(
            children: [
              _MoneyHeroFigure(
                label: 'Overdue',
                amount: visual.overdueTotal,
                onTap: () => onInsight(_MoneyInsight.due),
              ),
              _MoneyHeroFigure(
                label: 'Due this week',
                amount: visual.dueSoonRecords.fold<int>(
                  0,
                  (sum, item) => sum + item.summary.remainingAmountPaise,
                ),
                onTap: () => onInsight(_MoneyInsight.due),
              ),
              _MoneyHeroFigure(
                label: given ? 'Recovered' : 'Repaid',
                amount: visual.repaid,
                onTap: () => onInsight(_MoneyInsight.recovered),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MoneyHeroFigure extends StatelessWidget {
  const _MoneyHeroFigure({
    required this.label,
    required this.amount,
    required this.onTap,
  });
  final String label;
  final int amount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, maxLines: 2, style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: const Color(0xFFBFD4CB), fontSize: 12)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AmountText(amount, style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(color: const Color(0xFFF8FAF9), fontSize: 15,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    ),
  );
}
class _MoneyClampedScrollBehavior extends MaterialScrollBehavior {
  const _MoneyClampedScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}

class _MoneyInsightSheet extends StatefulWidget {
  const _MoneyInsightSheet({
    required this.insight,
    required this.visual,
    required this.direction,
  });
  final _MoneyInsight insight;
  final _MoneyVisualData visual;
  final MoneyDirection direction;

  @override
  State<_MoneyInsightSheet> createState() => _MoneyInsightSheetState();
}

class _MoneyInsightSheetState extends State<_MoneyInsightSheet> {
  int _selectedMonth = 0;

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.insight) {
      _MoneyInsight.due =>
        widget.direction == MoneyDirection.given ? 'Due soon' : 'Pay soon',
      _MoneyInsight.recovered =>
        widget.direction == MoneyDirection.given ? 'Recovered' : 'Repaid',
      _MoneyInsight.biggest => 'Biggest balance',
    };
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .85,
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.paddingOf(context).bottom + 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (widget.insight == _MoneyInsight.due)
              _dueContent(context)
            else if (widget.insight == _MoneyInsight.recovered)
              _recoveredContent(context)
            else
              _biggestContent(context),
          ],
        ),
      ),
    );
  }

  Widget _dueContent(BuildContext context) {
    final months = widget.visual.months;
    final amounts = widget.visual.monthTotals;
    final maxAmount = amounts.fold<int>(
      0,
      (max, value) => value > max ? value : max,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.visual.active.any((person) => person.overdue)) ...[
          Text(
            'Overdue',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: AppTheme.colorsOf(context).pay,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          for (final person in widget.visual.active.where(
            (person) => person.overdue,
          ))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      displayName(person.name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  AmountText(person.remaining),
                ],
              ),
            ),
          const SizedBox(height: 18),
        ],
        Text('Next 6 months', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 12),
        SizedBox(
          height: 166,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var index = 0; index < months.length; index++)
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _selectedMonth = index),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: AmountText(
                            amounts[index],
                            compact: true,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  fontSize: 12,
                                  color: _moneyMuted(context),
                                ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Container(
                          width: 28,
                          height: maxAmount == 0
                              ? 6
                              : 6 + 90 * amounts[index] / maxAmount,
                          decoration: BoxDecoration(
                            color: index == 0
                                ? _moneyAccent(context)
                                : const Color(
                                    0xFF059669,
                                  ).withValues(alpha: .65),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(6),
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          DateFormat('MMM').format(months[index].$1),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                fontSize: 12,
                                fontWeight: _selectedMonth == index
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          DateFormat('MMMM yyyy').format(months[_selectedMonth].$1),
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        if (months[_selectedMonth].$2.isEmpty)
          const Text('No dated balances this month')
        else
          for (final item in months[_selectedMonth].$2)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(child: Text(displayName(item.record.personName))),
                  AmountText(item.summary.remainingAmountPaise),
                ],
              ),
            ),
      ],
    );
  }

  Widget _recoveredContent(BuildContext context) {
    final visual = widget.visual;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SummaryValue(
          label: widget.direction == MoneyDirection.given
              ? 'Given'
              : 'Borrowed',
          value: visual.originalTotal,
        ),
        const SizedBox(height: 8),
        _SummaryValue(
          label: widget.direction == MoneyDirection.given
              ? 'Received'
              : 'Repaid',
          value: visual.repaid,
          emphasized: true,
        ),
        const SizedBox(height: 18),
        for (final person in visual.people)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    displayName(person.name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${person.total == 0 ? 0 : (person.repaid * 100 / person.total).round()}%',
                ),
                const SizedBox(width: 8),
                AmountText(person.repaid),
              ],
            ),
          ),
      ],
    );
  }

  Widget _biggestContent(BuildContext context) {
    final people = widget.visual.active.toList()
      ..sort((a, b) => b.remaining.compareTo(a.remaining));
    final maxAmount = people.isEmpty ? 1 : people.first.remaining;
    if (people.isEmpty) return const Text('All balances are settled');
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final person in people)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(displayName(person.name))),
                      AmountText(person.remaining),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 7,
                    width: constraints.maxWidth * person.remaining / maxAmount,
                    decoration: BoxDecoration(
                      color:
                          _moneyPersonColors[people.indexOf(person) %
                              _moneyPersonColors.length],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MoneyRemindButton extends StatelessWidget {
  const _MoneyRemindButton({required this.onPressed, required this.filled});

  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final accent = _moneyAccent(context);
    final foreground = filled
        ? Theme.of(context).brightness == Brightness.dark
            ? AppTheme.darkOnPrimary : Colors.white
        : accent;
    return Semantics(
    label: 'Remind on WhatsApp',
    button: true,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: filled ? accent : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
              border: filled ? null : Border.all(color: accent),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.phone_in_talk_outlined, size: 17, color: foreground),
                const SizedBox(width: 5),
                Text('Remind', style: TextStyle(color: foreground)),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  }
}

class _MoneyPersonTile extends StatefulWidget {
  const _MoneyPersonTile({
    super.key,
    required this.person,
    required this.avatarColor,
    required this.direction,
    required this.lastReminded,
    required this.onRemind,
    required this.onTap,
    required this.onLongPress,
  });

  final _PersonBalance person;
  final Color avatarColor;
  final MoneyDirection direction;
  final DateTime? lastReminded;
  final VoidCallback? onRemind;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  State<_MoneyPersonTile> createState() => _MoneyPersonTileState();
}

class _MoneyPersonTileState extends State<_MoneyPersonTile> {
  @override
  Widget build(BuildContext context) {
    final person = widget.person;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final name = displayName(person.name);
    final due = person.nearestDue;
    final statusRed = dark
        ? AppTheme.darkOverdue
        : const Color(0xFFB91C1C);
    final dateRed = dark ? AppTheme.darkDateOverdue : const Color(0xFFB42318);
    final statusAmber = dark
        ? AppTheme.darkUnpaid
        : const Color(0xFF9A5700);
    final dateAmber = dark ? AppTheme.darkDateAmber : const Color(0xFFB54708);
    final blue = dark ? AppTheme.darkPartial : const Color(0xFF1D4ED8);
    final statusColor = person.remaining == 0
        ? (dark ? AppTheme.darkSettled : _moneyAccent(context))
        : person.overdue
        ? statusRed
        : person.repaid > 0
        ? blue
        : statusAmber;
    final status = person.remaining == 0
        ? 'Settled'
        : person.overdue
        ? 'Overdue'
        : person.repaid > 0
        ? 'Partly paid'
        : 'Unpaid';
    final statusFill = dark
        ? switch (status) {
            'Settled' => AppTheme.darkSettledFill,
            'Overdue' => AppTheme.darkOverdueFill,
            'Partly paid' => AppTheme.darkPartialFill,
            _ => AppTheme.darkUnpaidFill,
          }
        : switch (status) {
            'Settled' => const Color(0xFFE7F5EE),
            'Overdue' => const Color(0xFFFEECEB),
            'Partly paid' => const Color(0xFFE8F0FE),
            _ => const Color(0xFFFFF4E5),
          };
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
    final dueColor = days == null
        ? (dark ? _moneyMuted(context) : const Color(0xFF5B6472))
        : days < 0
        ? dateRed
        : days <= 7
        ? dateAmber
        : (dark ? _moneyMuted(context) : const Color(0xFF5B6472));
    final secondary = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(fontSize: 13, color: _moneyMuted(context));
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _moneyBorder(context)),
      ),
      child: Column(
        children: [
          Material(
      color: Colors.transparent,
      child: InkWell(
        onLongPress: widget.onLongPress,
        onTap: widget.onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: widget.avatarColor,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Text(
                        name.characters.first.toUpperCase(),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    if (person.repaid > 0 && person.remaining > 0)
                      Positioned.fill(
                        child: CircularProgressIndicator(
                          value: person.total == 0 ? 0 : person.repaid / person.total,
                          strokeWidth: 3,
                          color: _moneyAccent(context),
                          backgroundColor: _moneyBorder(context),
                        ),
                      ),
                    if (person.remaining == 0)
                      Positioned(
                        right: -3,
                        bottom: -3,
                        child: Icon(
                          Icons.check_circle,
                          size: 16,
                          color: _moneyAccent(context),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 4,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: statusFill,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    status,
                                    style: secondary?.copyWith(
                                      color: statusColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AmountText(
                              person.remaining > 0
                                  ? person.remaining
                                  : person.repaid,
                              maxLines: 1,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            if (person.remaining > 0 && due != null)
                              Text(
                                '${person.records.length > 1 ? 'Next due ' : ''}${_moneyDatedDue(due, DateTime.now())}',
                                textAlign: TextAlign.end,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: secondary?.copyWith(color: dueColor),
                              )
                            else if (person.settledOn != null)
                              Text(
                                'Settled ${DateFormat('d MMM').format(person.settledOn!)}',
                                textAlign: TextAlign.end,
                                maxLines: 2,
                                style: secondary,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Semantics(
                  label: 'Open ${displayName(person.name)} records',
                  child: Icon(
                    Icons.chevron_right,
                  size: 18,
                    color: _moneyMuted(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
          ),
          Divider(height: 1, thickness: 1, color: _moneyBorder(context)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 3,
                    children: [
                      Text(
                        '${person.records.length} ${person.records.length == 1 ? 'record' : 'records'} ·',
                        style: secondary,
                      ),
                      if (person.repaid > 0) ...[
                        AmountText(person.repaid, style: secondary),
                        Text(' of ', style: secondary),
                        AmountText(person.total, style: secondary),
                        Text(' paid', style: secondary),
                      ] else
                        Text(
                          widget.lastReminded == null
                              ? 'Not reminded yet'
                              : remindedAgo(widget.lastReminded!, DateTime.now()),
                          style: secondary,
                        ),
                    ],
                  ),
                ),
                if (widget.onRemind != null) ...[
                  const SizedBox(width: 8),
                  _MoneyRemindButton(
                    onPressed: widget.onRemind!,
                    filled: person.overdue ||
                        (due != null && DateUtils.isSameDay(due, DateTime.now())),
                  ),
                ],
              ],
            ),
          ),
        ],
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
  bool _timeline = false;
  final Set<int> _settlingRecordIds = <int>{};

  Future<MoneyRecordDetail?> _chooseRecord(
    List<MoneyRecordDetail> records,
  ) async {
    if (records.length == 1) return records.first;
    return showModalBottomSheet<MoneyRecordDetail>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Choose a record')),
            for (final detail in records)
              ListTile(
                title: AmountText(detail.summary.remainingAmountPaise),
                subtitle: Text(
                  detail.record.dueDate == null
                      ? 'No due date'
                      : 'Due ${formatDate(detail.record.dueDate!)}',
                ),
                onTap: () => Navigator.pop(sheet, detail),
              ),
          ],
        ),
      ),
    );
  }

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
        final repayment = oldestOpen.firstOrNull;
        return Scaffold(
          appBar: AppBar(
            title: Text(displayName(widget.personName)),
            actions: [
              if (records.isNotEmpty)
                PopupMenuButton<String>(
                  tooltip: 'Person actions',
                  onSelected: (action) async {
                    final detail = await _chooseRecord(records);
                    if (!mounted || !context.mounted || detail == null) return;
                    if (action == 'edit') {
                      openFinanceSheet(
                        context,
                        MoneyFormSheet(record: detail.record),
                      );
                    } else {
                      await _delete(detail);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
            ],
          ),
          body: records.isEmpty
              ? const EmptyState(
                  icon: Icons.person_outline,
                  title: 'No records',
                  message: 'There are no records for this person.',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: _moneyBorder(context)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              RepaintBoundary(
                                child: MiniProgressRing(
                                  progress: person.total == 0
                                      ? 0
                                      : person.repaid / person.total,
                                  size: 96,
                                  strokeWidth: 8,
                                  color: _moneyAccent(context),
                                  child: Center(
                                    child: Text(
                                      '${person.total == 0 ? 0 : (person.repaid * 100 / person.total).round()}%',
                                      style: Theme.of(context).textTheme.titleMedium
                                          ?.copyWith(fontWeight: FontWeight.w800),
                                    ),
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
                                          ?.copyWith(fontSize: 32, fontWeight: FontWeight.w800),
                                    ),
                                    Text(
                                      '${open.length} open · ${settled.length} settled',
                                      style: Theme.of(context).textTheme.bodySmall
                                          ?.copyWith(color: _moneyMuted(context)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: _SummaryValue(
                                    label: widget.direction == MoneyDirection.given
                                        ? 'Lent'
                                        : 'Borrowed',
                                    value: person.total,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: _SummaryValue(
                                    label: 'Repaid',
                                    value: person.repaid,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _RepaymentCadence(records: records),
                    const SizedBox(height: 12),
                    SegmentedToggle<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Records')),
                        ButtonSegment(value: true, label: Text('Timeline')),
                      ],
                      selected: {_timeline},
                      filled: true,
                      selectedBackground: Theme.of(context).colorScheme.surface,
                      selectedForeground: _moneyAccent(context),
                      onSelectionChanged: (value) =>
                          setState(() => _timeline = value.single),
                    ),
                    const SizedBox(height: 14),
                    if (_timeline)
                      _PersonTimeline(
                        records: records,
                        onEdit: (item) => openFinanceSheet(
                          context,
                          MoneyFormSheet(record: item.record),
                        ),
                        onDelete: _delete,
                      )
                    else ...[
                      for (final item in open)
                        _PersonRecordRow(
                          key: ValueKey(
                            '${item.record.id}:${item.repayments.length}',
                          ),
                          detail: item,
                          onSettle: _settlingRecordIds.contains(item.record.id)
                              ? null
                              : () => _settle(item),
                          onExtend: () => _extend(item),
                        ),
                      if (settled.isNotEmpty)
                        ExpansionTile(
                          title: Text('Settled (${settled.length})'),
                          children: [
                            for (final item in settled)
                              _PersonRecordRow(
                                key: ValueKey('settled:${item.record.id}'),
                                detail: item,
                                settled: true,
                                onSettle:
                                    _settlingRecordIds.contains(item.record.id)
                                    ? null
                                    : () => _settle(item),
                                onExtend: () => _extend(item),
                              ),
                          ],
                        ),
                    ],
                  ],
                ),
          bottomNavigationBar: repayment == null
              ? null
              : DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    border: Border(top: BorderSide(color: _moneyBorder(context))),
                  ),
                  child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                              backgroundColor: _moneyAccent(context),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: () async {
                              final detail = await _chooseRecord(open);
                              if (mounted && detail != null) _addRepayment(detail);
                            },
                            icon: const Icon(Icons.add),
                            label: const Text('Add repayment'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: () => _sendReminder(repayment),
                          icon: const Icon(Icons.phone_in_talk_outlined),
                          label: const Text('Remind on WhatsApp'),
                        ),
                      ],
                    ),
                  ),
                  ),
                ),
        );
      },
    );
  }

  Future<void> _sendReminder(MoneyRecordDetail detail) async {
    await _shareMoneyReminder(context, detail);
  }

  void _addRepayment(MoneyRecordDetail detail) => openFinanceSheet(
    context,
    RepaymentSheet(
      recordId: detail.record.id,
      remainingPaise: detail.summary.remainingAmountPaise,
    ),
  );

  Future<void> _settle(MoneyRecordDetail detail) async {
    if (_settlingRecordIds.contains(detail.record.id)) return;
    var confirmedOnce = false;
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
            onPressed: () {
              if (confirmedOnce) return;
              confirmedOnce = true;
              Navigator.pop(dialog, true);
            },
            child: const Text('Settle'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _settlingRecordIds.add(detail.record.id));
    try {
      await ref
          .read(financeRepositoryProvider)
          .addRepayment(
            detail.record.id,
            detail.summary.remainingAmountPaise,
            'Settled in full',
            DateTime.now(),
          );
    } catch (error, stackTrace) {
      debugPrint('Money settlement failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not settle this record. Check its balance and try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _settlingRecordIds.remove(detail.record.id));
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

class _PersonEvent {
  _PersonEvent(this.detail, this.payment, this.date, this.amount);
  final MoneyRecordDetail detail;
  final MoneyRepayment? payment;
  final DateTime date;
  final int amount;
  int running = 0;
}

class _PersonTimeline extends ConsumerWidget {
  const _PersonTimeline({
    required this.records,
    required this.onEdit,
    required this.onDelete,
  });
  final List<MoneyRecordDetail> records;
  final ValueChanged<MoneyRecordDetail> onEdit;
  final ValueChanged<MoneyRecordDetail> onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = <_PersonEvent>[];
    for (final detail in records) {
      var remaining = detail.record.amountPaise;
      final created = _PersonEvent(
        detail,
        null,
        detail.record.recordDate,
        detail.record.amountPaise,
      )..running = remaining;
      events.add(created);
      final repayments = [...detail.repayments]
        ..sort((a, b) => a.id.compareTo(b.id));
      for (final payment in repayments) {
        remaining = (remaining - payment.amountPaise).clamp(
          0,
          detail.record.amountPaise,
        );
        events.add(
          _PersonEvent(detail, payment, payment.paidOn, -payment.amountPaise)
            ..running = remaining,
        );
      }
    }
    events.sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      if (byDate != 0) return byDate;
      if (a.payment == null) return -1;
      if (b.payment == null) return 1;
      return a.payment!.id.compareTo(b.payment!.id);
    });
    final methods = {
      for (final method
          in ref.watch(paymentMethodsProvider).valueOrNull ??
              const <PaymentMethod>[])
        method.id: method.label,
    };
    final today = DateUtils.dateOnly(DateTime.now());
    final ordered = events.reversed.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, event) in ordered.indexed) ...[
          if (index == 0 ||
              DateUtils.dateOnly(ordered[index - 1].date) !=
                  DateUtils.dateOnly(event.date))
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 8),
              child: Text(
                today.difference(DateUtils.dateOnly(event.date)).inDays == 0
                    ? 'Today'
                    : today.difference(DateUtils.dateOnly(event.date)).inDays ==
                          1
                    ? 'Yesterday'
                    : formatDate(event.date),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              event.payment == null
                  ? Icons.arrow_upward
                  : Icons.arrow_downward,
              color: event.payment == null
                  ? _moneyAccent(context)
                  : AppTheme.colorsOf(context).receive,
            ),
            title: Text(
              event.payment == null
                  ? event.detail.record.direction == MoneyDirection.given
                      ? 'You lent ${formatMoney(event.amount.abs())}'
                      : 'You borrowed ${formatMoney(event.amount.abs())}'
                  : event.detail.record.direction == MoneyDirection.given
                      ? '${displayName(event.detail.record.personName)} repaid ${formatMoney(event.amount.abs())}'
                      : 'You repaid ${formatMoney(event.amount.abs())}',
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${formatDateTime(event.date)} · ${event.payment == null ? methods[event.detail.record.paymentMethodId] ?? 'Method not recorded' : 'Method not recorded'}',
                ),
                if (DateUtils.dateOnly(
                  event.detail.record.recordDate,
                ).isAfter(today))
                  StatusPill(
                    label: 'Future date',
                    color: AppTheme.colorsOf(context).emi,
                  ),
                if ((event.payment == null
                            ? event.detail.record.notes
                            : event.payment!.notes)
                        ?.isNotEmpty ==
                    true)
                  Text(
                    (event.payment == null
                        ? event.detail.record.notes
                        : event.payment!.notes)!,
                  ),
                Row(
                  children: [
                    Text(
                      'Balance after: ',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    AmountText(
                      event.running,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ],
            ),
            trailing: AmountText(event.amount.abs()),
            onTap: () => showModalBottomSheet<void>(
              context: context,
              builder: (sheet) => SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      title: Text(
                        event.payment == null ? 'Record' : 'Repayment',
                      ),
                      subtitle: Text(
                        'Amount ${formatMoney(event.amount.abs())}',
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.edit_outlined),
                      title: const Text('Edit record'),
                      onTap: () {
                        Navigator.pop(sheet);
                        onEdit(event.detail);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.note_add_outlined),
                      title: const Text('Add note to record'),
                      onTap: () {
                        Navigator.pop(sheet);
                        onEdit(event.detail);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.delete_outline),
                      title: const Text('Delete record to Recycle bin'),
                      onTap: () {
                        Navigator.pop(sheet);
                        onDelete(event.detail);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _RepaymentCadence extends StatelessWidget {
  const _RepaymentCadence({required this.records});
  final List<MoneyRecordDetail> records;

  @override
  Widget build(BuildContext context) {
    final intervals = <int>[
      for (final detail in records)
        for (final payment in detail.repayments)
          payment.paidOn
              .difference(detail.record.recordDate)
              .inDays
              .clamp(0, 36500),
    ];
    if (intervals.length < 2) return const SizedBox.shrink();
    final days = (intervals.reduce((a, b) => a + b) / intervals.length).round();
    return Text(
      'Usually repays within $days ${days == 1 ? 'day' : 'days'}',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}

class _PersonRecordRow extends StatelessWidget {
  const _PersonRecordRow({
    super.key,
    required this.detail,
    required this.onSettle,
    required this.onExtend,
    this.settled = false,
  });

  final MoneyRecordDetail detail;
  final bool settled;
  final VoidCallback? onSettle;
  final VoidCallback onExtend;

  @override
  Widget build(BuildContext context) {
    final summary = detail.summary;
    final status = settled
        ? 'Settled'
        : summary.repaidAmountPaise > 0
            ? 'Partly paid'
            : detail.record.dueDate != null &&
                    DateUtils.dateOnly(detail.record.dueDate!)
                        .isBefore(DateUtils.dateOnly(DateTime.now()))
                ? 'Overdue'
                : 'Unpaid';
    final statusColor = switch (status) {
      'Settled' => _moneyAccent(context),
      'Overdue' => AppTheme.colorsOf(context).pay,
      'Partly paid' => Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF93C5FD)
          : const Color(0xFF1D4ED8),
      _ => AppTheme.colorsOf(context).emi,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _moneyBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: AmountText(
                  detail.record.amountPaise,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(status, style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: statusColor, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            'Recorded ${formatDate(detail.record.recordDate)}',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: _moneyMuted(context), fontSize: 13),
          ),
          Text(
            detail.record.dueDate == null
                ? 'No due date'
                : 'Due ${_moneyDatedDue(detail.record.dueDate!, DateTime.now())}',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: _moneyMuted(context), fontSize: 13),
          ),
          if (detail.record.notes?.trim().isNotEmpty == true)
            Text(
              detail.record.notes!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: _moneyMuted(context), fontSize: 13),
            ),
          if (!settled) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: onSettle,
                  child: const Text('Settle'),
                ),
                OutlinedButton(
                  onPressed: onExtend,
                  child: const Text('Extend due date'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
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
    var confirmedOnce = false;
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
            onPressed: () {
              if (confirmedOnce) return;
              confirmedOnce = true;
              Navigator.pop(context, true);
            },
            child: const Text('Settle fully'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
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
  bool _submitting = false;
  late final _person = TextEditingController(
    text: widget.record?.personName ?? widget.initialPerson ?? '',
  );
  final _phone = TextEditingController();
  bool _phoneLoaded = false;
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
    final name = widget.record?.personName ?? widget.initialPerson;
    if (name != null) _loadPhoneFor(name);
  }

  Future<void> _loadPhoneFor(String name) async {
    final phone = await _savedMoneyPhone(ref.read(databaseProvider), name);
    if (!mounted || _person.text.trim() != name.trim()) return;
    _phone.text = phone ?? '';
    _phoneLoaded = true;
  }

  @override
  void dispose() {
    _person.dispose();
    _phone.dispose();
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
                      selectedBackground: Theme.of(context).brightness == Brightness.dark
                          ? AppTheme.darkPrimary
                          : _direction == MoneyDirection.given
                              ? financeSelectedFill(context)
                              : AppTheme.colorsOf(context).pay.withValues(alpha: 0.12),
                      selectedForeground: Theme.of(context).brightness == Brightness.dark
                          ? AppTheme.darkOnPrimary
                          : _direction == MoneyDirection.given
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
                      validator: _moneyAmountText,
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
                      onSelected: (name) {
                        setState(() => _person.text = name);
                        _loadPhoneFor(name);
                      },
                    ),
                    const SizedBox(height: 12),
                    FilledField(
                      label: 'PHONE NUMBER (OPTIONAL)',
                      child: TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        decoration: financeFieldDecoration(
                          context,
                          hint: 'Country code and number',
                          icon: Icons.phone_outlined,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return null;
                          return _whatsAppDigits(value).length < 11
                              ? 'Enter a valid phone number'
                              : null;
                        },
                      ),
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
                    if (DateUtils.dateOnly(
                      _date,
                    ).isAfter(DateUtils.dateOnly(DateTime.now()))) ...[
                      const SizedBox(height: 6),
                      Text(
                        'This date is in the future',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 13,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? AppTheme.colorsOf(context).emi
                              : const Color(0xFFB45309),
                        ),
                      ),
                    ],
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
                    onPressed: _submitting ? null : _save,
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
    if (_submitting) return;
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
      final db = ref.read(databaseProvider);
      final personName = _person.text.trim();
      final phone = _phone.text.trim();
      setState(() => _submitting = true);
      closeFinanceSheetAndSave(context, () async {
        await repo.saveMoneyRecord(item);
        if (phone.isEmpty && _phoneLoaded && widget.record != null) {
          await (db.delete(db.settings)
                ..where((setting) => setting.key.equals(_moneyPhoneKey(personName))))
              .go();
        } else if (phone.isNotEmpty) {
          await db.into(db.settings).insertOnConflictUpdate(
            SettingsCompanion.insert(
              key: _moneyPhoneKey(personName),
              value: phone,
            ),
          );
        }
      }, errorMessage: 'Could not save this money record.');
    } on FormatException catch (error) {
      if (mounted) setState(() => _submitting = false);
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
  bool _submitting = false;
  DateTime _paidOn = DateTime.now();
  String _quickAmount = 'Custom';
  String _quickDate = 'Today';

  String? _validateRepaymentAmount(String? value) {
    final base = _moneyAmountText(value);
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
                    onPressed: _submitting ? null : _save,
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
    if (_submitting) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
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
