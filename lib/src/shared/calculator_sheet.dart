import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../features/assistant/assistant_math.dart';
import 'calculator_modes.dart';
import 'finance_bottom_sheet.dart';
import 'finance_form_widgets.dart';

enum CalculatorDestination { emi, moneyGiven, moneyBorrowed, subscription }

Future<String?> openCalculator(
  BuildContext context, {
  String initial = '',
  String? amountLabel,
  void Function(CalculatorDestination destination, String amount)?
  onDestination,
  ValueChanged<CalculatorEmiDraft>? onEmiDraft,
}) => showFinanceBottomSheet<String>(
  context,
  builder: (_) => CalculatorSheet(
    initial: initial,
    amountLabel: amountLabel,
    onDestination: onDestination,
    onEmiDraft: onEmiDraft,
  ),
);

class CalculatorSheet extends StatefulWidget {
  const CalculatorSheet({
    super.key,
    required this.initial,
    this.amountLabel,
    this.onDestination,
    this.onEmiDraft,
  });

  final String initial;
  final String? amountLabel;
  final void Function(CalculatorDestination destination, String amount)?
  onDestination;
  final ValueChanged<CalculatorEmiDraft>? onEmiDraft;

  @override
  State<CalculatorSheet> createState() => _CalculatorSheetState();
}

enum _CalculatorMode { calc, emi, tools }

class _TapeEntry {
  const _TapeEntry(this.expression, this.result);
  final String expression;
  final double result;
}

class _CalculatorSheetState extends State<CalculatorSheet> {
  static final List<_TapeEntry> _tape = [];
  late final _expression = ValueNotifier<String>(widget.initial.trim());
  final _error = ValueNotifier<String?>(null);
  _CalculatorMode _mode = _CalculatorMode.calc;
  bool _showDestinations = false;
  double? _modeAmount;

  @override
  void dispose() {
    _expression.dispose();
    _error.dispose();
    super.dispose();
  }

  double? _result() {
    if (_expression.value.trim().isEmpty) return 0;
    try {
      return evaluateAssistantMath(_expression.value);
    } on FormatException {
      return null;
    }
  }

  String _plain(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  void _press(String key) {
    HapticFeedback.selectionClick();
    _error.value = null;
    final current = _expression.value;
    if (key == 'AC') {
      _expression.value = '';
    } else if (key == '⌫') {
      if (current.isNotEmpty) {
        _expression.value = current.substring(0, current.length - 1);
      }
    } else if (key == '=') {
      final result = _result();
      if (result == null) {
        _error.value = 'Check the expression';
        return;
      }
      if (current.isNotEmpty) {
        setState(() {
          _tape.insert(0, _TapeEntry(current, result));
          if (_tape.length > 20) _tape.removeLast();
        });
      }
      _expression.value = _plain(result);
    } else if (current.length < 256) {
      _expression.value = '$current$key';
    }
  }

  double? get _activeAmount =>
      _mode == _CalculatorMode.calc ? _result() : _modeAmount;

  void _useResult() {
    final result = _activeAmount;
    if (result == null || !result.isFinite || result <= 0) {
      _error.value = 'Enter a valid amount';
      return;
    }
    Navigator.pop(context, _plain(result));
  }

  void _useDestination(CalculatorDestination destination) {
    final result = _activeAmount;
    if (result == null || !result.isFinite || result <= 0) {
      _error.value = 'Enter a valid amount';
      return;
    }
    final amount = _plain(result);
    Navigator.pop(context, amount);
    widget.onDestination?.call(destination, amount);
  }

  void _useEmiDraft(CalculatorEmiDraft draft) {
    _modeAmount = draft.monthlyEmi;
    if (widget.onEmiDraft == null) {
      _useDestination(CalculatorDestination.emi);
      return;
    }
    Navigator.pop(context, _plain(draft.monthlyEmi));
    widget.onEmiDraft!(draft);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: size.height * (landscape ? .88 : .92),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Calculator',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Clear history',
                  onPressed: () => setState(_tape.clear),
                  icon: const Icon(Icons.history_toggle_off_outlined),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedToggle<_CalculatorMode>(
              segments: const [
                ButtonSegment(value: _CalculatorMode.calc, label: Text('Calc')),
                ButtonSegment(value: _CalculatorMode.emi, label: Text('EMI')),
                ButtonSegment(
                  value: _CalculatorMode.tools,
                  label: Text('Tools'),
                ),
              ],
              selected: {_mode},
              selectedBackground: AppTheme.heroStart,
              selectedForeground: AppTheme.onHero,
              filled: true,
              onSelectionChanged: (value) => setState(() {
                _mode = value.first;
                _showDestinations = false;
                _modeAmount = null;
              }),
            ),
            const SizedBox(height: 14),
            if (_mode == _CalculatorMode.calc) ...[
              _display(context),
              const SizedBox(height: 12),
              _keypad(landscape),
            ],
            if (_mode == _CalculatorMode.emi)
              CalculatorEmiMode(
                onAmount: (value) => _modeAmount = value,
                onAdd: _useEmiDraft,
              ),
            if (_mode == _CalculatorMode.tools)
              CalculatorToolsMode(onAmount: (value) => _modeAmount = value),
            const SizedBox(height: 12),
            ValueListenableBuilder<String?>(
              valueListenable: _error,
              builder: (_, error, _) => error == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        error,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
            ),
            if (widget.amountLabel != null)
              FilledButton.icon(
                onPressed: _useResult,
                icon: const Icon(Icons.check),
                label: Text('Use ${widget.amountLabel}'),
              )
            else ...[
              FilledButton.icon(
                onPressed: () =>
                    setState(() => _showDestinations = !_showDestinations),
                icon: Icon(_showDestinations ? Icons.close : Icons.call_made),
                label: const Text('Use this amount'),
              ),
              if (_showDestinations)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _destinationChip(
                        CalculatorDestination.emi,
                        Icons.account_balance_outlined,
                        'EMI',
                      ),
                      _destinationChip(
                        CalculatorDestination.moneyGiven,
                        Icons.north_east,
                        'Money given',
                      ),
                      _destinationChip(
                        CalculatorDestination.moneyBorrowed,
                        Icons.south_west,
                        'Money borrowed',
                      ),
                      _destinationChip(
                        CalculatorDestination.subscription,
                        Icons.autorenew,
                        'Subscription',
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _destinationChip(
    CalculatorDestination destination,
    IconData icon,
    String label,
  ) => ActionChip(
    avatar: Icon(icon, size: 18),
    label: Text(label),
    onPressed: () => _useDestination(destination),
  );

  Widget _display(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.heroStart, AppTheme.heroEnd],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_tape.isNotEmpty) ...[
            SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _tape.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final entry = _tape[index];
                  return ActionChip(
                    backgroundColor: AppTheme.heroEnd,
                    side: BorderSide.none,
                    label: Text(
                      '${entry.expression} = ${_plain(entry.result)}',
                      style: textTheme.labelSmall?.copyWith(
                        color: AppTheme.onHero,
                      ),
                    ),
                    onPressed: () => _expression.value = _plain(entry.result),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
          ValueListenableBuilder<String>(
            valueListenable: _expression,
            builder: (context, expression, _) {
              final value = _result();
              final formatted = value == null
                  ? '—'
                  : formatMoney((value * 100).round());
              final words = value == null
                  ? ''
                  : formatAssistantResult(
                      value,
                    ).split('(').last.replaceAll(')', '');
              return Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    expression.isEmpty ? '0' : expression,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppTheme.onHeroMuted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onLongPress: value == null
                        ? null
                        : () {
                            Clipboard.setData(
                              ClipboardData(text: _plain(value)),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Result copied')),
                            );
                          },
                    child: SizedBox(
                      height: 56,
                      child: FittedBox(
                        alignment: Alignment.centerRight,
                        fit: BoxFit.scaleDown,
                        child: Text(
                          formatted,
                          style: textTheme.displaySmall?.copyWith(
                            color: AppTheme.onHero,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Text(
                    words,
                    maxLines: 2,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: AppTheme.onHeroMuted,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _keypad(bool landscape) {
    const rows = [
      ['AC', '(', ')', '⌫'],
      ['7', '8', '9', '÷'],
      ['4', '5', '6', '×'],
      ['1', '2', '3', '-'],
      ['00', '0', '.', '+'],
      ['000', 'k', 'L', 'Cr'],
      ['%', '='],
    ];
    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Row(
              children: [
                for (final key in row)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: _CalculatorKey(
                        label: key,
                        height: landscape ? 40 : 48,
                        onTap: () => _press(key),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CalculatorKey extends StatefulWidget {
  const _CalculatorKey({
    required this.label,
    required this.height,
    required this.onTap,
  });
  final String label;
  final double height;
  final VoidCallback onTap;

  @override
  State<_CalculatorKey> createState() => _CalculatorKeyState();
}

class _CalculatorKeyState extends State<_CalculatorKey> {
  bool pressed = false;

  @override
  Widget build(BuildContext context) {
    final label = widget.label;
    final operator = const {'+', '-', '×', '÷', '%', '(', ')'}.contains(label);
    final muted = label == 'AC' || label == '⌫';
    final color = label == '='
        ? AppTheme.heroEnd
        : operator
        ? AppTheme.accent
        : muted
        ? Theme.of(context).colorScheme.surfaceContainerHigh
        : financeFieldFill(context);
    return AnimatedScale(
      scale: pressed ? .92 : 1,
      duration: const Duration(milliseconds: 90),
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTapDown: (_) => setState(() => pressed = true),
          onTapCancel: () => setState(() => pressed = false),
          onTapUp: (_) => setState(() => pressed = false),
          onTap: widget.onTap,
          child: SizedBox(
            height: widget.height,
            child: Center(
              child: Text(
                label,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: label == '='
                      ? AppTheme.onHero
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
