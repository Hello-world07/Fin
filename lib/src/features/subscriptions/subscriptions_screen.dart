import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/providers.dart';
import '../../data/database.dart';
import '../../domain/due_status.dart';
import '../../domain/enums.dart';
import '../../domain/money_math.dart';
import '../../shared/async_view.dart';
import '../../shared/empty_state.dart';
import '../../shared/forms.dart';
import '../../shared/finance_form_widgets.dart';
import '../../shared/calculator_sheet.dart';

class SubscriptionsScreen extends ConsumerWidget {
  const SubscriptionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(financeRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Subscriptions')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            openFinanceSheet(context, const SubscriptionFormSheet()),
        icon: const Icon(Icons.add),
        label: const Text('Add Subscription'),
      ),
      body: AsyncView(
        value: ref.watch(subscriptionsProvider),
        builder: (items) {
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.autorenew,
              title: 'No subscriptions',
              message:
                  'Add monthly or yearly renewals so they show up before billing.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: items.length + 1,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              if (index == 0) return _SubscriptionSummary(items: items);
              final item = items[index - 1];
              final dueText = item.status == SubscriptionStatus.active
                  ? relativeDueText(item.nextBillingDate, DateTime.now())
                  : 'Not active';
              final dueColor = dueText.startsWith('Overdue')
                  ? Theme.of(context).colorScheme.error
                  : dueText == 'Due today'
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant;
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                title: Text(
                  displayName(item.name),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${item.frequency.label} · ${item.status.label}'),
                    Text(
                      'Next billing date · ${formatDate(item.nextBillingDate)}',
                    ),
                    Text(
                      dueText,
                      style: TextStyle(
                        color: dueColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      formatMoney(item.amountPaise),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert),
                      onSelected: (selection) async {
                        if (selection == 'delete') {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text(
                                'Delete \'${displayName(item.name)}\'?',
                              ),
                              content: const Text(
                                'This removes the subscription from your tracker.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) {
                            await repo.deleteSubscription(item.id);
                          }
                        } else {
                          final status = SubscriptionStatus.values.firstWhere(
                            (value) => value.name == selection,
                          );
                          await repo.setSubscriptionStatus(item.id, status);
                        }
                      },
                      itemBuilder: (context) => [
                        for (final status in SubscriptionStatus.values)
                          PopupMenuItem(
                            value: status.name,
                            child: Text(status.label),
                          ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete subscription'),
                        ),
                      ],
                    ),
                  ],
                ),
                onTap: () => openFinanceSheet(
                  context,
                  SubscriptionFormSheet(subscription: item),
                ),
                leading: const CircleAvatar(child: Icon(Icons.autorenew)),
              );
            },
          );
        },
      ),
    );
  }
}

class _SubscriptionSummary extends StatelessWidget {
  const _SubscriptionSummary({required this.items});

  final List<Subscription> items;

  @override
  Widget build(BuildContext context) {
    final active = items
        .where((item) => item.status == SubscriptionStatus.active)
        .toList();
    final monthly = active.fold<int>(
      0,
      (sum, item) =>
          sum + monthlyEquivalentPaise(item.amountPaise, item.frequency),
    );
    final activeLabel = active.length == 1 ? 'subscription' : 'subscriptions';
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${active.length} active $activeLabel',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatMoney(monthly),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '/ month recurring',
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

class SubscriptionFormSheet extends ConsumerStatefulWidget {
  const SubscriptionFormSheet({
    super.key,
    this.subscription,
    this.initialAmount,
  });

  final Subscription? subscription;
  final String? initialAmount;

  @override
  ConsumerState<SubscriptionFormSheet> createState() =>
      _SubscriptionFormSheetState();
}

class _SubscriptionFormSheetState extends ConsumerState<SubscriptionFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: widget.subscription?.name ?? '',
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
  late DateTime _next = widget.subscription?.nextBillingDate ?? DateTime.now();
  late PaymentFrequency _frequency =
      widget.subscription?.frequency ?? PaymentFrequency.monthly;
  late SubscriptionStatus _status =
      widget.subscription?.status ?? SubscriptionStatus.active;
  String? _saveError;

  @override
  void dispose() {
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
                        onSelectionChanged: (values) =>
                            setState(() => _frequency = values.single),
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledField(
                      label: 'STATUS',
                      child: SegmentedToggle<SubscriptionStatus>(
                        segments: statusSegments,
                        selected: {_status},
                        onSelectionChanged: (values) =>
                            setState(() => _status = values.single),
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
                    ChipSelector(
                      options: categoryLabels,
                      selected: selectedCategory,
                      onSelected: (label) => setState(
                        () => _category = _valueForCategoryLabel(label),
                      ),
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
        await repo.saveSubscription(item);
      }, errorMessage: 'Could not save subscription. Please try again.');
    } on FormatException catch (error) {
      setState(() => _saveError = error.message);
    }
  }
}
