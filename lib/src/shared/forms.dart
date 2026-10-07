import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/formatters.dart';
import '../domain/enums.dart';
import 'calculator_sheet.dart';
import 'finance_bottom_sheet.dart';

String? requiredText(String? value) {
  if (value == null || value.trim().isEmpty) return 'Required';
  return null;
}

String? amountText(String? value) {
  try {
    if (value == null || value.trim().isEmpty) return 'Required';
    parseRupeesToPaise(value);
    return null;
  } on FormatException catch (error) {
    return error.message;
  }
}

Future<DateTime?> pickAppDate(BuildContext context, DateTime initial) {
  final first = DateTime(2000);
  final last = DateTime(2100);
  final safeInitial = initial.isBefore(first)
      ? first
      : initial.isAfter(last)
      ? last
      : initial;
  return showDatePicker(
    context: context,
    initialDate: safeInitial,
    firstDate: first,
    lastDate: last,
    initialEntryMode: DatePickerEntryMode.calendarOnly,
  );
}

class FrequencyField extends StatelessWidget {
  const FrequencyField({
    super.key,
    required this.value,
    required this.onChanged,
    this.includeOnce = false,
    this.labelAbove = false,
  });

  final PaymentFrequency value;
  final ValueChanged<PaymentFrequency?> onChanged;
  final bool includeOnce;
  final bool labelAbove;

  @override
  Widget build(BuildContext context) {
    final values = PaymentFrequency.values.where(
      (item) =>
          item != PaymentFrequency.quarterly &&
          (includeOnce || item != PaymentFrequency.once),
    );
    final field = DropdownButtonFormField<PaymentFrequency>(
      initialValue: value,
      isExpanded: labelAbove,
      icon: Icon(
        labelAbove ? Icons.keyboard_arrow_down : Icons.arrow_drop_down,
      ),
      decoration: InputDecoration(labelText: labelAbove ? null : 'Frequency'),
      items: [
        for (final item in values)
          DropdownMenuItem(value: item, child: Text(item.label)),
      ],
      onChanged: onChanged,
    );
    return labelAbove
        ? LabeledFormField(label: 'Frequency', child: field)
        : field;
  }
}

class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.labelAbove = false,
  });

  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final bool labelAbove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final field = InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final next = await pickAppDate(context, value);
        if (context.mounted && next != null) onChanged(next);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: labelAbove ? null : label,
          prefixIcon: const Icon(Icons.calendar_month_outlined),
          suffixIcon: labelAbove ? const Icon(Icons.keyboard_arrow_down) : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                formatDate(value),
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: colors.onSurface),
              ),
            ),
            if (!labelAbove)
              Icon(Icons.keyboard_arrow_down, color: colors.onSurfaceVariant),
          ],
        ),
      ),
    );
    return labelAbove ? LabeledFormField(label: label, child: field) : field;
  }
}

class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.controller,
    required this.label,
    this.labelAbove = false,
    this.validator = amountText,
  });

  final TextEditingController controller;
  final String label;
  final bool labelAbove;
  final FormFieldValidator<String> validator;

  @override
  Widget build(BuildContext context) {
    final field = TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: labelAbove ? null : label,
        hintText: labelAbove ? '499' : null,
        prefixIcon: labelAbove ? const Center(child: Text('₹')) : null,
        prefixIconConstraints: labelAbove
            ? const BoxConstraints.tightFor(width: 40, height: 48)
            : null,
        suffixIcon: IconButton(
          tooltip: labelAbove ? 'Open calculator' : 'Calculator',
          icon: const Icon(Icons.calculate_outlined),
          onPressed: () async {
            final value = await openCalculator(
              context,
              initial: controller.text,
              amountLabel: labelAbove ? 'Amount' : label,
            );
            if (context.mounted && value != null) controller.text = value;
          },
        ),
      ),
      validator: validator,
    );
    return labelAbove ? LabeledFormField(label: label, child: field) : field;
  }
}

class LabeledFormField extends StatelessWidget {
  const LabeledFormField({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Semantics(label: label, child: child),
      ],
    );
  }
}

Future<void> openFinanceSheet(BuildContext context, Widget child) {
  return showFinanceBottomSheet<void>(context, builder: (_) => child);
}

void closeFinanceSheetAndSave(
  BuildContext context,
  Future<void> Function() save, {
  required String errorMessage,
}) {
  final messenger = ScaffoldMessenger.of(context);
  final closed = ModalRoute.of(context)?.completed;
  unawaited(HapticFeedback.lightImpact());
  Navigator.of(context).pop();
  unawaited(() async {
    if (closed != null) await closed;
    try {
      await save();
    } on FormatException catch (error) {
      if (messenger.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(error.message.toString())),
        );
      }
    } catch (_) {
      if (messenger.mounted) {
        messenger.showSnackBar(SnackBar(content: Text(errorMessage)));
      }
    }
  }());
}
