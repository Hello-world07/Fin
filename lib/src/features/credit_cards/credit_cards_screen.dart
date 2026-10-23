import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/formatters.dart';
import '../../core/providers.dart';
import '../../data/credit_card_repository.dart';
import '../../data/database.dart';

final _cardRepoProvider = Provider<CreditCardRepository>(
  (ref) => CreditCardRepository(ref.watch(databaseProvider)),
);

class CreditCardsScreen extends ConsumerWidget {
  const CreditCardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppTheme.homePaletteOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Credit cards')),
      body: StreamBuilder<List<CreditCard>>(
        stream: ref.watch(_cardRepoProvider).watchCards(),
        builder: (context, snapshot) {
          final cards = snapshot.data ?? [];
          if (snapshot.hasError) {
            return const Center(child: Text('Could not load cards.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (cards.isEmpty) {
            return const Center(child: Text('No credit cards yet.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            itemCount: cards.length,
            itemBuilder: (context, index) {
              final card = cards[index];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: Icon(Icons.credit_card, color: palette.text),
                title: Text(card.name),
                subtitle: Text(
                  '${card.issuer}${card.lastFour == null ? '' : ' · •••• ${card.lastFour}'}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => _CardDetailScreen(card: card),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAction(context, ref, _CardAction.card),
        icon: const Icon(Icons.add),
        label: const Text('Add card'),
      ),
    );
  }
}

class _CardDetailScreen extends ConsumerWidget {
  const _CardDetailScreen({required this.card});
  final CreditCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(_cardRepoProvider);
    final palette = AppTheme.homePaletteOf(context);
    return Scaffold(
      appBar: AppBar(title: Text(card.name)),
      body: StreamBuilder<List<CardStatement>>(
        stream: repo.watchStatements(card.id),
        builder: (context, statementSnap) => StreamBuilder<List<CardLedgerEntry>>(
          stream: repo.watchEntries(card.id),
          builder: (context, entrySnap) => StreamBuilder<List<CardEmiConversion>>(
            stream: repo.watchConversions(card.id),
            builder: (context, conversionSnap) {
              return StreamBuilder<List<CardConversionPayment>>(
                stream: repo.watchConversionPayments(card.id),
                builder: (context, paymentSnap) {
                  if (statementSnap.hasError ||
                      entrySnap.hasError ||
                      conversionSnap.hasError ||
                      paymentSnap.hasError) {
                    return const Center(
                      child: Text('Could not load card history.'),
                    );
                  }
                  final statements = statementSnap.data ?? [];
                  final entries = entrySnap.data ?? [];
                  final conversions = conversionSnap.data ?? [];
                  final conversionPayments = paymentSnap.data ?? [];
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    children: [
                      Text(card.issuer, style: TextStyle(color: palette.text2)),
                      const SizedBox(height: 20),
                      Text(
                        'Statements',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (statements.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'Add a statement to track its balance and minimum due.',
                          ),
                        ),
                      for (final statement in statements) ...[
                        const SizedBox(height: 10),
                        _StatementTile(statement: statement, entries: entries),
                      ],
                      const SizedBox(height: 24),
                      Text(
                        'Transactions and charges',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Statement balances are entered separately; these entries itemize activity.',
                        style: TextStyle(color: palette.text2, fontSize: 13),
                      ),
                      if (entries.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('No activity yet.'),
                        ),
                      for (final entry in entries)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(entry.description),
                          subtitle: Text(
                            '${_kindLabel(entry.kind)} · ${_date(entry.occurredOn)}',
                          ),
                          trailing: Text(
                            '${entry.kind == 'payment' || entry.kind == 'refund' ? '−' : '+'}${formatMoney(entry.amountPaise)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: palette.text,
                            ),
                          ),
                        ),
                      const SizedBox(height: 24),
                      Text(
                        'Purchase-to-EMI conversions',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tracked separately from card statements and Loan/Product EMIs.',
                        style: TextStyle(color: palette.text2, fontSize: 13),
                      ),
                      if (conversions.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('No conversions yet.'),
                        ),
                      for (final conversion in conversions)
                        Builder(
                          builder: (context) {
                            final paid = conversionPayments
                                .where(
                                  (payment) =>
                                      payment.conversionId == conversion.id,
                                )
                                .length;
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                entries
                                        .where(
                                          (e) =>
                                              e.id ==
                                              conversion.purchaseEntryId,
                                        )
                                        .map((e) => e.description)
                                        .firstOrNull ??
                                    'Purchase',
                              ),
                              subtitle: Text(
                                '${formatMoney(conversion.monthlyEmiPaise)}/mo · $paid/${conversion.tenureMonths} paid · first due ${_date(conversion.firstDueDate)}',
                              ),
                              trailing: paid >= conversion.tenureMonths
                                  ? Text(
                                      '${formatMoney(conversion.monthlyEmiPaise)}/mo',
                                    )
                                  : TextButton(
                                      onPressed: () => _recordConversionPayment(
                                        context,
                                        repo,
                                        conversion,
                                        conversionPayments,
                                      ),
                                      child: const Text('Record EMI'),
                                    ),
                            );
                          },
                        ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final action = await showModalBottomSheet<_CardAction>(
            context: context,
            showDragHandle: true,
            builder: (sheet) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final action in [
                    _CardAction.statement,
                    _CardAction.payment,
                    _CardAction.transaction,
                    _CardAction.conversion,
                  ])
                    ListTile(
                      title: Text(action.label),
                      onTap: () => Navigator.pop(sheet, action),
                    ),
                ],
              ),
            ),
          );
          if (action != null && context.mounted) {
            _openAction(context, ref, action, cardId: card.id);
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
    );
  }
}

class _StatementTile extends StatelessWidget {
  const _StatementTile({required this.statement, required this.entries});
  final CardStatement statement;
  final List<CardLedgerEntry> entries;

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.homePaletteOf(context);
    final paid = CreditCardRepository.paidFor(statement, entries);
    final outstanding = CreditCardRepository.outstandingFor(statement, entries);
    final minimumLeft = (statement.minimumDuePaise - paid).clamp(
      0,
      statement.minimumDuePaise,
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Statement ${_date(statement.statementDate)} · due ${_date(statement.dueDate)}',
            style: TextStyle(color: palette.text2),
          ),
          const SizedBox(height: 8),
          Text(
            '${formatMoney(outstanding)} outstanding',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(
            'Balance ${formatMoney(statement.balancePaise)} · paid ${formatMoney(paid)}',
          ),
          Text(
            'Minimum due ${formatMoney(statement.minimumDuePaise)} · ${formatMoney(minimumLeft)} still needed',
            style: TextStyle(color: palette.text2),
          ),
        ],
      ),
    );
  }
}

enum _CardAction {
  card('Add card'),
  statement('Add statement'),
  payment('Record payment'),
  transaction('Add transaction or charge'),
  conversion('Convert purchase to EMI');

  const _CardAction(this.label);
  final String label;
}

String _date(DateTime value) => '${value.day}/${value.month}/${value.year}';
String _kindLabel(String kind) => switch (kind) {
  'fuelFee' => 'Fuel fee',
  'walletFee' => 'Wallet fee',
  'annualFee' => 'Annual fee',
  'interest' => 'Finance charge',
  'payment' => 'Payment',
  'refund' => 'Refund',
  _ => 'Purchase',
};

Future<void> _recordConversionPayment(
  BuildContext context,
  CreditCardRepository repo,
  CardEmiConversion conversion,
  List<CardConversionPayment> payments,
) async {
  final paid = payments
      .where((p) => p.conversionId == conversion.id)
      .map((p) => p.installmentNumber)
      .toSet();
  final next = [
    for (var i = 1; i <= conversion.tenureMonths; i++) i,
  ].where((i) => !paid.contains(i)).firstOrNull;
  if (next == null) return;
  final amount = TextEditingController(
    text: rupeesText(conversion.monthlyEmiPaise),
  );
  var date = DateTime.now();
  var saving = false;
  try {
    await showDialog<void>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, setDialogState) => AlertDialog(
          title: Text('Record installment $next'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Amount paid'),
              ),
              TextButton.icon(
                onPressed: () async {
                  final selected = await showDatePicker(
                    context: dialog,
                    initialDate: date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (selected != null) setDialogState(() => date = selected);
                },
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(_date(date)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      int value;
                      try {
                        value = parseRupeesToPaise(amount.text);
                      } catch (_) {
                        ScaffoldMessenger.of(dialog).showSnackBar(
                          const SnackBar(
                            content: Text('Enter an amount greater than zero.'),
                          ),
                        );
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        await repo.recordConversionPayment(
                          conversion.id,
                          next,
                          value,
                          date,
                        );
                        if (dialog.mounted) {
                          Navigator.pop(dialog);
                        }
                      } catch (error) {
                        if (dialog.mounted) {
                          ScaffoldMessenger.of(dialog).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Could not record installment: $error',
                              ),
                            ),
                          );
                        }
                        if (dialog.mounted) {
                          setDialogState(() => saving = false);
                        }
                      }
                    },
              child: const Text('Record'),
            ),
          ],
        ),
      ),
    );
  } finally {
    amount.dispose();
  }
}

Future<void> _openAction(
  BuildContext context,
  WidgetRef ref,
  _CardAction action, {
  int? cardId,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CardActionSheet(
      action: action,
      cardId: cardId,
      repo: ref.read(_cardRepoProvider),
    ),
  );
  if (result == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${action.label.replaceFirst('Add', 'Added')} saved.'),
      ),
    );
  }
}

class _CardActionSheet extends StatefulWidget {
  const _CardActionSheet({
    required this.action,
    required this.cardId,
    required this.repo,
  });
  final _CardAction action;
  final int? cardId;
  final CreditCardRepository repo;

  @override
  State<_CardActionSheet> createState() => _CardActionSheetState();
}

class _CardActionSheetState extends State<_CardActionSheet> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _issuer = TextEditingController();
  final _lastFour = TextEditingController();
  final _amount = TextEditingController();
  final _minimum = TextEditingController();
  final _tenure = TextEditingController();
  String _kind = 'purchase';
  int? _statementId;
  int? _purchaseId;
  DateTime _dateValue = DateTime.now();
  DateTime _dueValue = DateTime.now().add(const Duration(days: 20));
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _issuer, _lastFour, _amount, _minimum, _tenure]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate(bool due) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: due ? _dueValue : _dateValue,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() {
        if (due) {
          _dueValue = picked;
        } else {
          _dateValue = picked;
        }
      });
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _saving) return;
    setState(() => _saving = true);
    try {
      final repo = widget.repo;
      switch (widget.action) {
        case _CardAction.card:
          await repo.addCard(
            _name.text,
            _issuer.text,
            lastFour: _lastFour.text.isEmpty ? null : _lastFour.text,
          );
        case _CardAction.statement:
          await repo.addStatement(
            widget.cardId!,
            _dateValue,
            _dueValue,
            parseRupeesToPaise(_amount.text),
            parseRupeesToPaise(_minimum.text),
          );
        case _CardAction.payment:
          await repo.addEntry(
            widget.cardId!,
            'payment',
            'Card payment',
            parseRupeesToPaise(_amount.text),
            _dateValue,
            statementId: _statementId,
          );
        case _CardAction.transaction:
          await repo.addEntry(
            widget.cardId!,
            _kind,
            _name.text,
            parseRupeesToPaise(_amount.text),
            _dateValue,
            statementId: _statementId,
          );
        case _CardAction.conversion:
          await repo.convertPurchase(
            widget.cardId!,
            _purchaseId!,
            parseRupeesToPaise(_amount.text),
            int.parse(_tenure.text),
            _dueValue,
          );
      }
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is ArgumentError
                  ? '${error.message}'
                  : 'Could not save: $error',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool amount = false,
    String? Function(String?)? validator,
  }) => TextFormField(
    controller: controller,
    decoration: InputDecoration(labelText: label),
    keyboardType: amount
        ? const TextInputType.numberWithOptions(decimal: true)
        : TextInputType.text,
    validator:
        validator ??
        (value) => value == null || value.trim().isEmpty ? 'Required' : null,
  );

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  action.label,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                if (action == _CardAction.card) ...[
                  _field(_name, 'Card name'),
                  _field(_issuer, 'Issuer'),
                  TextFormField(
                    controller: _lastFour,
                    decoration: const InputDecoration(
                      labelText: 'Last 4 digits (optional)',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) =>
                        v != null &&
                            v.isNotEmpty &&
                            !RegExp(r'^\d{4}$').hasMatch(v)
                        ? 'Enter exactly 4 digits'
                        : null,
                  ),
                ],
                if (action == _CardAction.statement ||
                    action == _CardAction.payment ||
                    action == _CardAction.transaction ||
                    action == _CardAction.conversion)
                  _field(
                    _amount,
                    switch (action) {
                      _CardAction.statement => 'Statement balance',
                      _CardAction.conversion => 'Monthly EMI',
                      _ => 'Amount',
                    },
                    amount: true,
                    validator: (v) {
                      try {
                        parseRupeesToPaise(v ?? '');
                        return null;
                      } catch (_) {
                        return 'Enter an amount greater than zero';
                      }
                    },
                  ),
                if (action == _CardAction.statement)
                  _field(
                    _minimum,
                    'Minimum due',
                    amount: true,
                    validator: (v) {
                      try {
                        parseRupeesToPaise(v ?? '');
                        return null;
                      } catch (_) {
                        return 'Enter an amount greater than zero';
                      }
                    },
                  ),
                if (action == _CardAction.transaction) ...[
                  _field(_name, 'Description'),
                  DropdownButtonFormField<String>(
                    initialValue: _kind,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: [
                      for (final kind in cardEntryKinds.where(
                        (k) => k != 'payment',
                      ))
                        DropdownMenuItem(
                          value: kind,
                          child: Text(_kindLabel(kind)),
                        ),
                    ],
                    onChanged: (v) => setState(() => _kind = v ?? 'purchase'),
                  ),
                ],
                if (action == _CardAction.payment ||
                    action == _CardAction.transaction)
                  StreamBuilder<List<CardStatement>>(
                    stream: widget.repo.watchStatements(widget.cardId!),
                    builder: (context, snapshot) => DropdownButtonFormField<int?>(
                      initialValue: _statementId,
                      decoration: InputDecoration(
                        labelText: action == _CardAction.payment
                            ? 'Statement to pay'
                            : 'Statement (optional)',
                      ),
                      items: [
                        if (action == _CardAction.transaction)
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('Not assigned'),
                          ),
                        for (final statement
                            in snapshot.data ?? <CardStatement>[])
                          DropdownMenuItem(
                            value: statement.id,
                            child: Text(
                              '${_date(statement.statementDate)} · ${formatMoney(statement.balancePaise)}',
                            ),
                          ),
                      ],
                      validator: (v) =>
                          action == _CardAction.payment && v == null
                          ? 'Choose a statement'
                          : null,
                      onChanged: (v) => setState(() => _statementId = v),
                    ),
                  ),
                if (action == _CardAction.conversion) ...[
                  StreamBuilder<List<CardLedgerEntry>>(
                    stream: widget.repo.watchEntries(widget.cardId!),
                    builder: (context, snapshot) => DropdownButtonFormField<int>(
                      initialValue: _purchaseId,
                      decoration: const InputDecoration(labelText: 'Purchase'),
                      items: [
                        for (final entry
                            in (snapshot.data ?? <CardLedgerEntry>[]).where(
                              (e) => e.kind == 'purchase',
                            ))
                          DropdownMenuItem(
                            value: entry.id,
                            child: Text(
                              '${entry.description} · ${formatMoney(entry.amountPaise)}',
                            ),
                          ),
                      ],
                      validator: (v) => v == null ? 'Choose a purchase' : null,
                      onChanged: (v) => setState(() => _purchaseId = v),
                    ),
                  ),
                  _field(
                    _tenure,
                    'Number of months',
                    validator: (v) => (int.tryParse(v ?? '') ?? 0) <= 0
                        ? 'Enter whole months'
                        : null,
                  ),
                ],
                if (action != _CardAction.card) ...[
                  TextButton.icon(
                    onPressed: () => _pickDate(false),
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(
                      '${action == _CardAction.statement ? 'Statement' : 'Transaction'} date · ${_date(_dateValue)}',
                    ),
                  ),
                  if (action == _CardAction.statement ||
                      action == _CardAction.conversion)
                    TextButton.icon(
                      onPressed: () => _pickDate(true),
                      icon: const Icon(Icons.event_outlined),
                      label: Text(
                        '${action == _CardAction.statement ? 'Due' : 'First EMI due'} · ${_date(_dueValue)}',
                      ),
                    ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving…' : 'Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
