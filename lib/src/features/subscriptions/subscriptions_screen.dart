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
import '../../shared/calculator_sheet.dart';

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
            return EmptyState(
              icon: Icons.autorenew,
              title: 'No subscriptions',
              message: 'Add your first subscription to keep renewals in view.',
              actionLabel: 'Add Subscription',
              onAction: () =>
                  openFinanceSheet(context, const SubscriptionFormSheet()),
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
                  .where((item) => item.status == SubscriptionStatus.active)
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
          final renewing = active.where((item) {
            final days = due(
              item,
            ).difference(DateTime(today.year, today.month, today.day)).inDays;
            return days >= 0 && days <= 7;
          }).toList();
          final monthly = active.fold<int>(
            0,
            (sum, item) =>
                sum + monthlyEquivalentPaise(item.amountPaise, item.frequency),
          );
          final yearly = monthly * 12;
          final largest = active
              .where((item) => item.frequency != PaymentFrequency.once)
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
          return ListView(
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              MediaQuery.paddingOf(context).bottom + 112,
            ),
            children: [
              _SubscriptionHero(monthly: monthly, yearly: yearly),
              if (renewing.isNotEmpty) ...[
                const SizedBox(height: 28),
                const _ListHeading('Renewing soon'),
                const SizedBox(height: 12),
                SizedBox(
                  height: 100,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: renewing.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final item = renewing[index];
                      return Container(
                        width: 166,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName(item.name),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              formatMoney(item.amountPaise),
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            Text(
                              relativeDueText(due(item), today),
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 28),
              _ListHeading('Active (${active.length})'),
              for (final item in active)
                _SubscriptionRow(item: item, due: due(item), repo: repo),
              const SizedBox(height: 22),
              _ListHeading('Paused (${paused.length})'),
              for (final item in paused)
                _SubscriptionRow(item: item, due: due(item), repo: repo),
              const SizedBox(height: 22),
              InkWell(
                onTap: () => setState(() => _showCancelled = !_showCancelled),
                child: Row(
                  children: [
                    Expanded(
                      child: _ListHeading('Cancelled (${cancelled.length})'),
                    ),
                    Icon(
                      _showCancelled
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                    ),
                  ],
                ),
              ),
              if (_showCancelled)
                for (final item in cancelled)
                  _SubscriptionRow(item: item, due: due(item), repo: repo),
              if (active.isNotEmpty) ...[
                const SizedBox(height: 28),
                _CategoryBreakdown(items: active),
              ],
              if (largest != null) ...[
                const SizedBox(height: 20),
                Text(
                  'Pausing ${displayName(largest.name)} would save ${formatMoney(monthlyEquivalentPaise(largest.amountPaise, largest.frequency) * 12)} a year',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
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

class _SubscriptionHero extends StatelessWidget {
  const _SubscriptionHero({required this.monthly, required this.yearly});
  final int monthly;
  final int yearly;

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
      ],
    );
  }
}

class _SubscriptionRow extends StatelessWidget {
  const _SubscriptionRow({
    required this.item,
    required this.due,
    required this.repo,
  });
  final Subscription item;
  final DateTime due;
  final FinanceRepository repo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = item.status != SubscriptionStatus.active;
    final color = _categoryColor(item.category);
    return Dismissible(
      key: ValueKey(item.id),
      background: _swipeBackground(
        theme.colorScheme.primary,
        item.status == SubscriptionStatus.paused
            ? Icons.play_arrow
            : Icons.pause,
        item.status == SubscriptionStatus.paused ? 'Resume' : 'Pause',
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
            await repo.setSubscriptionStatus(
              item.id,
              item.status == SubscriptionStatus.paused
                  ? SubscriptionStatus.active
                  : SubscriptionStatus.paused,
            );
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
      child: InkWell(
        onTap: () => openFinanceSheet(
          context,
          SubscriptionFormSheet(subscription: item),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 15),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.12),
                child: Text(
                  item.name.isEmpty ? '?' : item.name[0].toUpperCase(),
                  style: TextStyle(color: color, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName(item.name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: muted
                            ? theme.colorScheme.onSurfaceVariant
                            : null,
                      ),
                    ),
                    Text(
                      '${item.frequency.label} · ${formatDate(due)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatMoney(item.amountPaise),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: muted ? theme.colorScheme.onSurfaceVariant : null,
                    ),
                  ),
                  Text(
                    muted
                        ? item.status.label
                        : relativeDueText(due, DateTime.now()),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: muted ? theme.colorScheme.onSurfaceVariant : color,
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

Color _categoryColor(String? category) => switch (category?.toLowerCase()) {
  'entertainment' || 'streaming' => AppTheme.subscriptions,
  'utilities' => AppTheme.emi,
  'education' => AppTheme.receive,
  'software' => AppTheme.heroEnd,
  _ => AppTheme.seed,
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
                    child: ColoredBox(color: _categoryColor(entry.key)),
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
                    backgroundColor: _categoryColor(entry.key),
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
                        filled: true,
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
                        filled: true,
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
