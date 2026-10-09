import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../domain/calculator_tools_math.dart';
import 'finance_form_widgets.dart';

class CalculatorEmiDraft {
  const CalculatorEmiDraft({
    required this.principal,
    required this.annualRate,
    required this.months,
    required this.monthlyEmi,
  });

  final double principal;
  final double annualRate;
  final int months;
  final double monthlyEmi;
}

class CalculatorEmiMode extends StatefulWidget {
  const CalculatorEmiMode({
    super.key,
    required this.onAmount,
    required this.onAdd,
  });
  final ValueChanged<double?> onAmount;
  final ValueChanged<CalculatorEmiDraft> onAdd;

  @override
  State<CalculatorEmiMode> createState() => _CalculatorEmiModeState();
}

class _CalculatorEmiModeState extends State<CalculatorEmiMode> {
  final principal = TextEditingController();
  final rate = TextEditingController();
  final tenure = TextEditingController();
  bool years = false;

  @override
  void dispose() {
    principal.dispose();
    rate.dispose();
    tenure.dispose();
    super.dispose();
  }

  double? get result {
    final p = double.tryParse(principal.text.replaceAll(',', ''));
    final r = double.tryParse(rate.text);
    final n = double.tryParse(tenure.text);
    if (p == null || r == null || n == null || n <= 0) return null;
    try {
      return calculateMonthlyEmi(p, r, (n * (years ? 12 : 1)).round());
    } on FormatException {
      return null;
    }
  }

  void update() {
    setState(() {});
    widget.onAmount(result);
  }

  @override
  Widget build(BuildContext context) {
    final p = double.tryParse(principal.text.replaceAll(',', '')) ?? 0;
    final n = (double.tryParse(tenure.text) ?? 0) * (years ? 12 : 1);
    final emi = result;
    final total = emi == null ? 0.0 : emi * n.round();
    final interest = (total - p).clamp(0.0, double.infinity);
    final style = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ModeField(
          label: 'Principal',
          controller: principal,
          onChanged: update,
          prefix: '₹',
        ),
        const SizedBox(height: 12),
        _ModeField(
          label: 'Interest rate per year',
          controller: rate,
          onChanged: update,
          suffix: '%',
        ),
        const SizedBox(height: 12),
        _ModeField(label: 'Tenure', controller: tenure, onChanged: update),
        const SizedBox(height: 8),
        SegmentedToggle<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Months')),
            ButtonSegment(value: true, label: Text('Years')),
          ],
          selected: {years},
          selectedBackground: AppTheme.heroStart,
          selectedForeground: AppTheme.heroTextOf(context),
          filled: true,
          onSelectionChanged: (selection) {
            years = selection.first;
            update();
          },
        ),
        const SizedBox(height: 18),
        if (emi != null) ...[
          Text(
            'MONTHLY EMI',
            style: style.labelMedium?.copyWith(
              color: AppTheme.colorsOf(context).secondaryText,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            formatMoney((emi * 100).round()),
            style: style.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          _ResultLine('Total interest', interest),
          _ResultLine('Total payable', total),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Row(
              children: [
                Expanded(
                  flex: (p / total * 1000).round().clamp(1, 999),
                  child: ColoredBox(
                    color: Theme.of(context).colorScheme.primary,
                    child: SizedBox(height: 7),
                  ),
                ),
                Expanded(
                  flex: (interest / total * 1000).round().clamp(1, 999),
                  child: const ColoredBox(
                    color: AppTheme.accent,
                    child: SizedBox(height: 7),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => widget.onAdd(
              CalculatorEmiDraft(
                principal: p,
                annualRate: double.parse(rate.text),
                months: n.round(),
                monthlyEmi: emi,
              ),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Add this as EMI'),
          ),
        ],
      ],
    );
  }
}

class CalculatorToolsMode extends StatefulWidget {
  const CalculatorToolsMode({super.key, required this.onAmount});
  final ValueChanged<double?> onAmount;

  @override
  State<CalculatorToolsMode> createState() => _CalculatorToolsModeState();
}

class _CalculatorToolsModeState extends State<CalculatorToolsMode> {
  final amount = TextEditingController();
  final value = TextEditingController();
  final years = TextEditingController();
  CalculatorTool tool = CalculatorTool.gst;
  int gst = 18;
  bool alternate = false;

  @override
  void dispose() {
    amount.dispose();
    value.dispose();
    years.dispose();
    super.dispose();
  }

  double? get result {
    final a = double.tryParse(amount.text.replaceAll(',', ''));
    final v = tool == CalculatorTool.gst
        ? gst.toDouble()
        : double.tryParse(value.text);
    if (a == null || v == null) return null;
    final y = double.tryParse(years.text);
    if (tool == CalculatorTool.interest && y == null) return null;
    try {
      return calculateToolResult(
        tool,
        a,
        v,
        alternate: alternate,
        annualRate: v,
        years: y ?? 0,
      );
    } on FormatException {
      return null;
    }
  }

  void update() {
    setState(() {});
    widget.onAmount(result);
  }

  void selectTool(CalculatorTool next) {
    tool = next;
    value.clear();
    years.clear();
    alternate = false;
    update();
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme;
    final output = result;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final entry in const [
                (CalculatorTool.gst, 'GST'),
                (CalculatorTool.discount, 'Discount'),
                (CalculatorTool.split, 'Split bill'),
                (CalculatorTool.interest, 'Interest'),
                (CalculatorTool.change, '% change'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(entry.$2),
                    selected: tool == entry.$1,
                    onSelected: (_) => selectTool(entry.$1),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _ModeField(
          label: tool == CalculatorTool.change ? 'Starting value' : 'Amount',
          controller: amount,
          onChanged: update,
          prefix: '₹',
        ),
        const SizedBox(height: 12),
        if (tool == CalculatorTool.gst) ...[
          Wrap(
            spacing: 8,
            children: [
              for (final percent in const [5, 12, 18, 28])
                ChoiceChip(
                  label: Text('$percent%'),
                  selected: gst == percent,
                  onSelected: (_) {
                    gst = percent;
                    update();
                  },
                ),
            ],
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Remove GST'),
            value: alternate,
            onChanged: (v) {
              alternate = v;
              update();
            },
          ),
        ] else ...[
          _ModeField(
            label: switch (tool) {
              CalculatorTool.discount => 'Discount %',
              CalculatorTool.split => 'People',
              CalculatorTool.interest => 'Interest rate % per year',
              CalculatorTool.change => 'New value',
              CalculatorTool.gst => '',
            },
            controller: value,
            onChanged: update,
            suffix:
                tool == CalculatorTool.discount ||
                    tool == CalculatorTool.interest
                ? '%'
                : null,
          ),
          if (tool == CalculatorTool.interest) ...[
            const SizedBox(height: 12),
            _ModeField(label: 'Years', controller: years, onChanged: update),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Compound interest'),
              value: alternate,
              onChanged: (v) {
                alternate = v;
                update();
              },
            ),
          ],
        ],
        const SizedBox(height: 12),
        if (output != null) ...[
          Text(
            'RESULT',
            style: style.labelMedium?.copyWith(
              color: AppTheme.colorsOf(context).secondaryText,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            tool == CalculatorTool.change
                ? '${output.toStringAsFixed(2)}%'
                : formatMoney((output * 100).round()),
            style: style.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ],
    );
  }
}

class _ModeField extends StatelessWidget {
  const _ModeField({
    required this.label,
    required this.controller,
    required this.onChanged,
    this.prefix,
    this.suffix,
  });
  final String label;
  final TextEditingController controller;
  final VoidCallback onChanged;
  final String? prefix;
  final String? suffix;

  @override
  Widget build(BuildContext context) => FilledField(
    label: label,
    child: TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) => onChanged(),
      decoration: financeFieldDecoration(
        context,
        prefix: prefix,
        suffix: suffix,
      ),
    ),
  );
}

class _ResultLine extends StatelessWidget {
  const _ResultLine(this.label, this.amount);
  final String label;
  final double amount;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          formatMoney((amount * 100).round()),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}
