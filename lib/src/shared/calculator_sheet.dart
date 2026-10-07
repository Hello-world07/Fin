import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../domain/calculator_math.dart';
import 'finance_bottom_sheet.dart';

enum CalculatorDestination { emi, moneyGiven, moneyBorrowed, subscription }

Future<String?> openCalculator(
  BuildContext context, {
  String initial = '',
  String? amountLabel,
  void Function(CalculatorDestination destination, String amount)?
  onDestination,
}) {
  return showFinanceBottomSheet<String>(
    context,
    builder: (_) => CalculatorSheet(
      initial: initial,
      amountLabel: amountLabel,
      onDestination: onDestination,
    ),
  );
}

class CalculatorSheet extends StatefulWidget {
  const CalculatorSheet({
    super.key,
    required this.initial,
    this.amountLabel,
    this.onDestination,
  });

  final String initial;
  final String? amountLabel;
  final void Function(CalculatorDestination destination, String amount)?
  onDestination;

  @override
  State<CalculatorSheet> createState() => _CalculatorSheetState();
}

class _CalculatorSheetState extends State<CalculatorSheet> {
  late String _expression = widget.initial.trim();
  final _expressionScrollController = ScrollController();
  String? _error;

  @override
  void dispose() {
    _expressionScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = _safeResult();
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Calculator',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Clear',
                  onPressed: () => setState(() => _expression = ''),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SingleChildScrollView(
                    controller: _expressionScrollController,
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: Text(
                      _expression.isEmpty ? '0' : _expression,
                      maxLines: 1,
                      softWrap: false,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _error ??
                        (result == null ? '' : '= ${_formatCurrency(result)}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _error == null
                          ? null
                          : Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ),
            ),
            if (widget.amountLabel == null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final entry in const [
                    (CalculatorDestination.emi, 'Add to EMI'),
                    (CalculatorDestination.moneyGiven, 'Money Given'),
                    (CalculatorDestination.moneyBorrowed, 'Money Borrowed'),
                    (CalculatorDestination.subscription, 'Subscription'),
                  ])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: SizedBox(
                          height: 38,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              visualDensity: VisualDensity.compact,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: () => _useDestination(entry.$1),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                entry.$2,
                                maxLines: 1,
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            for (final row in [
              const ['AC', '%', '÷', '×'],
              const ['7', '8', '9', '-'],
              const ['4', '5', '6', '+'],
              const ['1', '2', '3', '⌫'],
              [
                '0',
                '.',
                '=',
                widget.amountLabel == null
                    ? 'Back'
                    : 'Use ${widget.amountLabel}',
              ],
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    for (final key in row)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: SizedBox(
                            height: 54,
                            child: FilledButton.tonal(
                              onPressed: () => _tap(key),
                              child: FittedBox(child: Text(key)),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _tap(String key) {
    if (key == 'Back') {
      Navigator.pop(context);
      return;
    }
    if (key.startsWith('Use')) {
      _useResult();
      return;
    }
    final previous = _expression;
    setState(() {
      _error = null;
      if (key == 'AC' || key == 'C') {
        _expression = '';
      } else if (key == '⌫') {
        if (_expression.isNotEmpty) {
          _expression = _expression.substring(0, _expression.length - 1);
        }
      } else if (key == '=') {
        final result = _safeResult();
        if (result != null) _expression = _format(result);
      } else {
        _expression += key;
      }
    });
    if (_expression != previous) _scrollExpressionToEnd();
  }

  void _scrollExpressionToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_expressionScrollController.hasClients) return;
      _expressionScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    });
  }

  double? _safeResult() {
    if (_expression.trim().isEmpty) return 0;
    try {
      return evaluateCalculation(_expression);
    } on FormatException {
      return null;
    }
  }

  void _useResult() {
    final result = _safeResult();
    if (result == null) {
      setState(() => _error = 'Enter a valid calculation');
      return;
    }
    Navigator.pop(context, _format(result));
  }

  void _useDestination(CalculatorDestination destination) {
    final result = _safeResult();
    if (result == null) {
      setState(() => _error = 'Enter a valid calculation');
      return;
    }
    final amount = _format(result);
    Navigator.pop(context, amount);
    widget.onDestination?.call(destination, amount);
  }

  String _format(double value) {
    if (!value.isFinite) return '0';
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  String _formatCurrency(double value) {
    if (!value.isFinite) return '';
    return formatMoney((value * 100).round());
  }
}
