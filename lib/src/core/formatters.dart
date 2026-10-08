import 'package:intl/intl.dart';

final _indianCurrency = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
);
final _internationalCurrency = NumberFormat.currency(
  locale: 'en_US',
  symbol: '₹',
  decimalDigits: 0,
);
bool useIndianNumberGrouping = true;

final _date = DateFormat('dd MMM yyyy');
final _dateTime = DateFormat('dd MMM yyyy, hh:mm a');

String formatMoney(int paise) =>
    (useIndianNumberGrouping ? _indianCurrency : _internationalCurrency).format(
      paise / 100,
    );

String formatDate(DateTime date) => _date.format(date);

String formatDateTime(DateTime date) => _dateTime.format(date);

String displayName(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return trimmed;
  return '${trimmed[0].toUpperCase()}${trimmed.substring(1)}';
}

int parseRupeesToPaise(String input) {
  final cleaned = input.replaceAll(',', '').trim();
  final value = double.tryParse(cleaned);
  if (value == null || value <= 0) {
    throw const FormatException('Enter an amount greater than zero');
  }
  return (value * 100).round();
}

String rupeesText(int paise) {
  final rupees = paise / 100;
  if (rupees == rupees.roundToDouble()) return rupees.toInt().toString();
  return rupees.toStringAsFixed(2);
}
