import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

enum AmountRegion {
  india('India', 'en_IN'),
  unitedStates('United States', 'en_US'),
  unitedKingdom('United Kingdom', 'en_GB'),
  germany('Germany', 'de_DE'),
  france('France', 'fr_FR'),
  switzerland('Switzerland', 'de_CH'),
  uae('UAE', 'en_US'),
  singapore('Singapore', 'en_SG'),
  japan('Japan', 'ja_JP'),
  brazil('Brazil', 'pt_BR');

  const AmountRegion(this.label, this.locale);
  final String label;
  final String locale;
}

class AmountFormatter {
  const AmountFormatter({this.region = AmountRegion.india, this.symbol = '₹'});

  final AmountRegion region;
  final String symbol;

  String formatNumber(num value, {int decimalDigits = 2}) {
    final formatted = NumberFormat.decimalPatternDigits(
      locale: region.locale,
      decimalDigits: decimalDigits,
    ).format(value);
    return formatted
        .replaceAll(RegExp('[\u00a0\u202f]'), ' ')
        .replaceAll('’', "'");
  }

  String formatPaise(int paise) {
    final decimals = paise % 100 == 0 ? 0 : 2;
    final number = formatNumber(paise.abs() / 100, decimalDigits: decimals);
    final prefix = symbol == 'AED' ? 'AED ' : symbol;
    return '${paise < 0 ? '-' : ''}$prefix$number';
  }

  String get preview => formatNumber(1234567.89);
}

final activeAmountFormatter = ValueNotifier(const AmountFormatter());
bool privacyAmountsHidden = false;
const hiddenAmount = '•••••';

final _date = DateFormat('dd MMM yyyy');
final _dateTime = DateFormat('dd MMM yyyy, hh:mm a');

String formatMoneyUnmasked(int paise) =>
    activeAmountFormatter.value.formatPaise(paise);

String formatCompactMoneyUnmasked(int paise) {
  if (paise.abs() < 100000) return formatMoneyUnmasked(paise);
  final formatter = activeAmountFormatter.value;
  final scaled = paise.abs() / 100000;
  final digits = scaled.abs() >= 100 ? 0 : 1;
  final symbol = formatter.symbol == 'AED' ? 'AED ' : formatter.symbol;
  return '${paise < 0 ? '-' : ''}$symbol${formatter.formatNumber(scaled, decimalDigits: digits)}K';
}

String formatMoney(int paise) =>
    privacyAmountsHidden ? hiddenAmount : formatMoneyUnmasked(paise);

String hideMoneyInText(String value) => privacyAmountsHidden
    ? value.replaceAll(
        RegExp(
          '(?:${RegExp.escape(activeAmountFormatter.value.symbol)}|₹|INR|Rs\\.?|AED)\\s*\\d+(?:[ ,.’\']\\d{3})*(?:[.,]\\d{1,2})?(?:\\s*\\([^)]*\\))?',
          caseSensitive: false,
        ),
        hiddenAmount,
      )
    : value;

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
