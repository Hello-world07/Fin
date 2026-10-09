import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import 'forms.dart' show pickAppDate;

InputDecoration financeFieldDecoration(
  BuildContext context, {
  String? hint,
  IconData? icon,
  String? prefix,
  String? suffix,
}) {
  final colors = Theme.of(context).colorScheme;
  final tokens = AppTheme.colorsOf(context);
  final shape = OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide.none,
  );
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: tokens.mutedText),
    prefixIcon: icon == null ? null : Icon(icon),
    prefixText: prefix,
    suffixText: suffix,
    filled: true,
    fillColor: financeFieldFill(context),
    border: shape,
    enabledBorder: shape,
    focusedBorder: shape.copyWith(
      borderSide: BorderSide(color: colors.primary, width: 1.5),
    ),
    errorBorder: shape.copyWith(
      borderSide: BorderSide(color: colors.error, width: 1),
    ),
    focusedErrorBorder: shape.copyWith(
      borderSide: BorderSide(color: colors.error, width: 1.5),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    constraints: const BoxConstraints(minHeight: 56),
  );
}

Color financeFieldFill(BuildContext context) =>
    AppTheme.colorsOf(context).fieldFill;

Color financeSelectedFill(BuildContext context) =>
    AppTheme.colorsOf(context).selectedFill;

class FinanceFieldLabel extends StatelessWidget {
  const FinanceFieldLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: Theme.of(context).textTheme.labelMedium?.copyWith(
      color: AppTheme.colorsOf(context).secondaryText,
      fontWeight: FontWeight.w700,
    ),
  );
}

class FilledField extends StatelessWidget {
  const FilledField({
    super.key,
    required this.label,
    required this.child,
    this.gap = 7,
  });

  final String label;
  final Widget child;
  final double gap;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      FinanceFieldLabel(label),
      SizedBox(height: gap),
      child,
    ],
  );
}

class HeroAmountInput extends StatelessWidget {
  const HeroAmountInput({
    super.key,
    required this.controller,
    required this.label,
    this.onChanged,
    this.validator,
    this.calculator,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String>? onChanged;
  final String? Function(String?)? validator;
  final VoidCallback? calculator;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      FinanceFieldLabel(label),
      const SizedBox(height: 4),
      Row(
        children: [
          Text(
            '₹',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
              decoration: const InputDecoration(
                hintText: '0.00',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              validator: validator,
              onChanged: onChanged,
            ),
          ),
          if (calculator != null)
            IconButton(
              tooltip: 'Calculator',
              onPressed: calculator,
              icon: const Icon(Icons.calculate_outlined),
            ),
        ],
      ),
    ],
  );
}

class SegmentedToggle<T extends Object> extends StatelessWidget {
  const SegmentedToggle({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelectionChanged,
    this.selectedBackground,
    this.selectedForeground,
    this.filled = false,
  });

  final List<ButtonSegment<T>> segments;
  final Set<T> selected;
  final ValueChanged<Set<T>>? onSelectionChanged;
  final Color? selectedBackground;
  final Color? selectedForeground;
  final bool filled;

  @override
  Widget build(BuildContext context) => SegmentedButton<T>(
    segments: segments,
    selected: selected,
    onSelectionChanged: onSelectionChanged,
    showSelectedIcon: false,
    style: ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? selectedBackground
            : filled
            ? financeFieldFill(context)
            : null,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? selectedForeground : null,
      ),
      side: filled ? const WidgetStatePropertyAll(BorderSide.none) : null,
      shape: filled ? const WidgetStatePropertyAll(StadiumBorder()) : null,
    ),
  );
}

class ChipSelector extends StatelessWidget {
  const ChipSelector({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final option in options)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(option),
              selected: selected == option,
              onSelected: (_) => onSelected(option),
              selectedColor: financeSelectedFill(context),
              side: BorderSide(
                color: selected == option
                    ? Theme.of(context).colorScheme.primary
                    : AppTheme.transparent,
              ),
            ),
          ),
      ],
    ),
  );
}

class OptionTile extends StatelessWidget {
  const OptionTile({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? financeSelectedFill(context)
              : financeFieldFill(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? colors.primary : AppTheme.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: selected ? colors.primary : null),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DateTile extends StatelessWidget {
  const DateTile({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.allowClear = false,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool allowClear;

  @override
  Widget build(BuildContext context) => FilledField(
    label: label,
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () async {
        final date = await pickAppDate(context, value ?? DateTime.now());
        if (context.mounted && date != null) onChanged(date);
      },
      child: InputDecorator(
        decoration: financeFieldDecoration(
          context,
          hint: value == null ? 'Not set' : null,
          icon: Icons.calendar_month_outlined,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(value == null ? 'Not set' : formatDate(value!)),
            ),
            if (allowClear && value != null)
              IconButton(
                tooltip: 'Clear date',
                onPressed: () => onChanged(null),
                icon: const Icon(Icons.close),
              )
            else
              const Icon(Icons.keyboard_arrow_down),
          ],
        ),
      ),
    ),
  );
}
