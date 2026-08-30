import 'package:flutter/painting.dart' show FontFeature;
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

/// Fixed-width digits, for money that sits in a column.
///
/// WHY: Space Grotesk's default figures are proportional, so a "1" is narrower
/// than a "4". Down a list of payments or a rent roll the decimal points and
/// thousands separators wander from row to row, which reads as sloppy and makes
/// two amounts genuinely harder to compare at a glance. Tabular figures give
/// every digit the same advance width so the columns line up.
///
/// Only for figures — prose set in tabular numerals looks gappy.
const kTabularFigures = <FontFeature>[FontFeature.tabularFigures()];
