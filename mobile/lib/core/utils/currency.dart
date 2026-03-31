import 'package:intl/intl.dart';
import '../constants.dart';

final _currencyFormat = NumberFormat.currency(
  symbol: '${AppConstants.currency} ',
  decimalDigits: 0,
);

/// Format a number as a currency amount using the app's configured currency.
String formatCurrency(num amount) => _currencyFormat.format(amount);

/// Try to parse a dynamic value (String or num) to double, fallback to 0.
double toDouble(dynamic v) => double.tryParse((v ?? '0').toString()) ?? 0;
