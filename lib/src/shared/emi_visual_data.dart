import '../core/formatters.dart';
import '../data/repositories.dart';

class EmiRelief {
  const EmiRelief(this.month, this.amountPaise, this.name);
  final DateTime month;
  final int amountPaise;
  final String name;
}

class EmiMonthLoad {
  const EmiMonthLoad(this.month, this.amountPaise, this.parts, this.dropped);
  final DateTime month;
  final int amountPaise;
  final List<(String, int)> parts;
  final bool dropped;
}

class EmiVisualData {
  const EmiVisualData(this.months, this.reliefs, this.currentLoadPaise);
  final List<EmiMonthLoad> months;
  final List<EmiRelief> reliefs;
  final int currentLoadPaise;
}

EmiVisualData buildEmiVisualData(List<EmiDetail> items, DateTime today) {
  final start = DateTime(today.year, today.month);
  final reliefs = <EmiRelief>[];
  for (final item in items) {
    final unpaid = item.installments.where((part) => !part.isPaid).toList();
    if (unpaid.isEmpty) continue;
    reliefs.add(
      EmiRelief(
        DateTime(unpaid.last.dueDate.year, unpaid.last.dueDate.month),
        item.scheduledInstallmentPaise,
        displayName(item.emi.name),
      ),
    );
  }
  reliefs.sort((a, b) => a.month.compareTo(b.month));
  final months = <EmiMonthLoad>[];
  var previous = 0;
  for (var offset = 0; offset < 12; offset++) {
    final month = DateTime(start.year, start.month + offset);
    final parts = <(String, int)>[];
    for (final item in items) {
      var amount = 0;
      for (final part in item.installments) {
        if (!part.isPaid &&
            part.dueDate.year == month.year &&
            part.dueDate.month == month.month) {
          amount += item.amountForInstallment(part.number);
        }
      }
      if (amount > 0) parts.add((displayName(item.emi.name), amount));
    }
    final total = parts.fold<int>(0, (sum, part) => sum + part.$2);
    months.add(
      EmiMonthLoad(month, total, parts, offset > 0 && total < previous),
    );
    previous = total;
  }
  return EmiVisualData(
    months,
    reliefs,
    items.fold<int>(0, (sum, item) => sum + item.scheduledInstallmentPaise),
  );
}
