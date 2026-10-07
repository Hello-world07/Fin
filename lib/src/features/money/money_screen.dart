import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/app_theme.dart';
import '../../core/providers.dart';
import '../../data/database.dart';
import '../../data/repositories.dart';
import '../../domain/enums.dart';
import '../../shared/async_view.dart';
import '../../shared/calculator_sheet.dart';
import '../../shared/empty_state.dart';
import '../../shared/forms.dart';
import '../../shared/finance_form_widgets.dart';

class MoneyScreen extends ConsumerStatefulWidget {
  const MoneyScreen({super.key});

  @override
  ConsumerState<MoneyScreen> createState() => _MoneyScreenState();
}

enum _MoneyFilter { all, unpaid, partial, overdue, settled }

class _MoneyScreenState extends ConsumerState<MoneyScreen> {
  MoneyDirection _direction = MoneyDirection.given;
  _MoneyFilter _filter = _MoneyFilter.all;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    return Scaffold(
      appBar: AppBar(title: const Text('Money')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openFinanceSheet(
          context,
          MoneyFormSheet(initialDirection: _direction),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New record'),
      ),
      body: AsyncView(
        value: ref.watch(moneyRecordsProvider),
        builder: (items) {
          final coming = items
              .where((item) => item.record.direction == MoneyDirection.given)
              .toList();
          final payable = items
              .where((item) => item.record.direction == MoneyDirection.borrowed)
              .toList();
          final selected = _direction == MoneyDirection.given
              ? coming
              : payable;
          final query = _search.text.trim().toLowerCase();
          final visible = selected.where((item) {
            final status = item.summary.status;
            final matchesFilter = switch (_filter) {
              _MoneyFilter.all => true,
              _MoneyFilter.unpaid =>
                status != MoneyStatus.settled &&
                    item.summary.repaidAmountPaise == 0,
              _MoneyFilter.partial =>
                item.summary.repaidAmountPaise > 0 &&
                    status != MoneyStatus.settled,
              _MoneyFilter.overdue => status == MoneyStatus.overdue,
              _MoneyFilter.settled => status == MoneyStatus.settled,
            };
            return matchesFilter &&
                (query.isEmpty ||
                    item.record.personName.toLowerCase().contains(query));
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
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              SegmentedButton<MoneyDirection>(
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
                onSelectionChanged: (value) =>
                    setState(() => _direction = value.single),
              ),
              const SizedBox(height: 20),
              Text(
                _direction == MoneyDirection.given
                    ? 'TOTAL TO RECEIVE'
                    : 'TOTAL TO PAY',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                formatMoney(outstanding),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _SummaryValue(
                      label: _direction == MoneyDirection.given
                          ? 'Total given'
                          : 'Total borrowed',
                      value: originalTotal,
                    ),
                  ),
                  Expanded(
                    child: _SummaryValue(
                      label: _direction == MoneyDirection.given
                          ? 'Received'
                          : 'Paid',
                      value: repaid,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Search people',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
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
                          onSelected: (_) => setState(() => _filter = entry.$1),
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
                )
              else
                for (final item in visible) _MoneyRecordTile(item: item),
            ],
          );
        },
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
        Text(
          formatMoney(value),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: label == 'Net position'
                ? value > 0
                      ? Theme.of(context).colorScheme.tertiary
                      : value < 0
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.onSurface
                : null,
          ),
        ),
      ],
    );
  }
}

class _MoneyRecordTile extends StatelessWidget {
  const _MoneyRecordTile({required this.item});

  final MoneyRecordDetail item;

  @override
  Widget build(BuildContext context) {
    final paid = item.summary.repaidAmountPaise;
    final total = item.record.amountPaise;
    final progress = total == 0 ? 0.0 : (paid / total).clamp(0.0, 1.0);
    final actionWord = item.record.direction == MoneyDirection.given
        ? 'Received'
        : 'Paid';
    final settled = item.summary.status == MoneyStatus.settled;
    final statusText = settled
        ? 'Settled'
        : item.record.dueDate == null
        ? item.summary.status.label
        : '${item.summary.status.label} · Due ${formatDate(item.record.dueDate!)}';
    final statusColor = item.summary.status == MoneyStatus.overdue
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => MoneyDetailScreen(item.record.id)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    displayName(item.record.personName),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  formatMoney(item.summary.remainingAmountPaise),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              '$statusText · $actionWord ${formatMoney(paid)} of ${formatMoney(total)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: statusColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 9),
            LinearProgressIndicator(value: progress, minHeight: 4),
            const SizedBox(height: 5),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${formatMoney(item.summary.remainingAmountPaise)} remaining',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Text(
                  '${(progress * 100).round()}% ${settled ? 'settled' : 'repaid'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
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
          floatingActionButton:
              detail == null || detail.summary.remainingAmountPaise == 0
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => openFinanceSheet(
                    context,
                    RepaymentSheet(
                      recordId: id,
                      remainingPaise: detail.summary.remainingAmountPaise,
                    ),
                  ),
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Repayment'),
                ),
          body: detail == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      detail.summary.status.label.toUpperCase(),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: detail.summary.status == MoneyStatus.overdue
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _headline(detail),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      formatMoney(detail.record.amountPaise),
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: detail.record.amountPaise == 0
                          ? 0
                          : (detail.summary.repaidAmountPaise /
                                    detail.record.amountPaise)
                                .clamp(0.0, 1.0),
                      minHeight: 5,
                    ),
                    const SizedBox(height: 12),
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
                      ],
                    ),
                    const SizedBox(height: 18),
                    _MoneyDetailLine(
                      'Due date',
                      detail.record.dueDate == null
                          ? 'Not set'
                          : formatDate(detail.record.dueDate!),
                    ),
                    _MoneyDetailLine(
                      'Record date',
                      formatDate(detail.record.recordDate),
                    ),
                    _MoneyDetailLine('Status', detail.summary.status.label),
                    if (detail.record.notes?.isNotEmpty == true)
                      _MoneyDetailLine('Notes', detail.record.notes!),
                    const SizedBox(height: 24),
                    Text(
                      'Repayment history',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (detail.repayments.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('No repayments yet'),
                      ),
                    for (
                      var index = 0;
                      index < detail.repayments.length;
                      index++
                    )
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 17,
                          child: Text('${index + 1}'),
                        ),
                        title: Text(
                          '${formatMoney(detail.repayments[index].amountPaise)} ${detail.record.direction == MoneyDirection.given ? 'received' : 'paid'}',
                        ),
                        subtitle: Text(
                          '${formatDateTime(detail.repayments[index].paidOn)}${detail.repayments[index].notes?.isNotEmpty == true ? ' · ${detail.repayments[index].notes}' : ''}',
                        ),
                      ),
                    const Divider(height: 28),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(
                        radius: 17,
                        child: Icon(Icons.add, size: 18),
                      ),
                      title: Text(
                        'Record created · ${formatMoney(detail.record.amountPaise)}',
                      ),
                      subtitle: Text(formatDate(detail.record.recordDate)),
                    ),
                  ],
                ),
        );
      },
    );
  }

  String _headline(MoneyRecordDetail detail) {
    if (detail.record.direction == MoneyDirection.given) {
      return '${displayName(detail.record.personName)} owes me ${formatMoney(detail.summary.remainingAmountPaise)}';
    }
    return 'I owe ${displayName(detail.record.personName)} ${formatMoney(detail.summary.remainingAmountPaise)}';
  }
}

class _MoneyDetailLine extends StatelessWidget {
  const _MoneyDetailLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 112,
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class MoneyFormSheet extends ConsumerStatefulWidget {
  const MoneyFormSheet({
    super.key,
    this.record,
    this.initialAmount,
    this.initialDirection,
  });

  final MoneyRecord? record;
  final String? initialAmount;
  final MoneyDirection? initialDirection;

  @override
  ConsumerState<MoneyFormSheet> createState() => _MoneyFormSheetState();
}

class _MoneyFormSheetState extends ConsumerState<MoneyFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _person = TextEditingController(
    text: widget.record?.personName ?? '',
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
    _due = widget.record?.dueDate;
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
                      selectedBackground: _direction == MoneyDirection.given
                          ? financeSelectedFill(context)
                          : AppTheme.pay.withValues(alpha: 0.12),
                      selectedForeground: _direction == MoneyDirection.given
                          ? AppTheme.seed
                          : AppTheme.pay,
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
  bool _saving = false;
  String? _serverError;

  String? _validateRepaymentAmount(String? value) {
    if (_serverError != null) return _serverError;
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
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              fit: FlexFit.loose,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    Text(
                      'Add repayment',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text('Remaining: ${formatMoney(widget.remainingPaise)}'),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _amount,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Amount',
                        prefixText: '₹ ',
                        suffixIcon: IconButton(
                          tooltip: 'Calculator',
                          icon: const Icon(Icons.calculate_outlined),
                          onPressed: () async {
                            final value = await openCalculator(
                              context,
                              initial: _amount.text,
                              amountLabel: 'Repayment amount',
                            );
                            if (value != null) {
                              _amount.text = value;
                              _formKey.currentState?.validate();
                            }
                          },
                        ),
                      ),
                      validator: _validateRepaymentAmount,
                      onChanged: (_) {
                        _serverError = null;
                        _formKey.currentState?.validate();
                      },
                    ),
                    DateField(
                      label: 'Repayment date',
                      value: _paidOn,
                      onChanged: (value) => setState(() => _paidOn = value),
                    ),
                    TextFormField(
                      controller: _notes,
                      decoration: const InputDecoration(labelText: 'Notes'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving
                  ? null
                  : () async {
                      if (_saving) return;
                      if (!_formKey.currentState!.validate()) return;
                      HapticFeedback.lightImpact();
                      setState(() => _saving = true);
                      try {
                        await ref
                            .read(financeRepositoryProvider)
                            .addRepayment(
                              widget.recordId,
                              parseRupeesToPaise(_amount.text),
                              _notes.text.trim().isEmpty
                                  ? null
                                  : _notes.text.trim(),
                              _paidOn,
                            );
                        if (context.mounted) Navigator.pop(context);
                      } on FormatException catch (error) {
                        if (context.mounted) {
                          setState(() {
                            _saving = false;
                            _serverError = error.message.toString();
                          });
                          _formKey.currentState?.validate();
                        }
                      } catch (_) {
                        if (context.mounted) {
                          setState(() => _saving = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Could not save this repayment.'),
                            ),
                          );
                        }
                      }
                    },
              child: Text(_saving ? 'Saving...' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}
