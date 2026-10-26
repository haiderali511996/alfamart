import 'package:intl/intl.dart';

final _dbDate = DateFormat('yyyy-MM-dd');
final _displayDate = DateFormat('dd MMM yyyy');
final _displayDateShort = DateFormat('dd MMM');
final _displayDateTime = DateFormat('dd MMM yyyy, hh:mm a');

String toDbDate(DateTime d) => _dbDate.format(d);
DateTime fromDbDate(String s) => _dbDate.parse(s);
String displayDate(String dbDate) => _displayDate.format(fromDbDate(dbDate));
String displayDateShort(DateTime d) => _displayDateShort.format(d);
String displayDateTime(DateTime d) => _displayDateTime.format(d);
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Dashboard / report periods requested by the business.
enum Period {
  day('24 Hours'),
  week('1 Week'),
  month('1 Month'),
  months3('3 Months'),
  months6('6 Months'),
  months12('12 Months'),
  custom('Custom');

  const Period(this.label);
  final String label;

  static const presets = [day, week, month, months3, months6, months12];
}

class DateRange {
  const DateRange(this.start, this.end);
  final DateTime start;
  final DateTime end;

  String get startDb => toDbDate(start);
  String get endDb => toDbDate(end);
  int get days => end.difference(start).inDays + 1;

  String get label => startDb == endDb
      ? _displayDate.format(start)
      : '${_displayDate.format(start)} – ${_displayDate.format(end)}';

  /// Business entries are recorded per business day, so "24 Hours" is the
  /// current business day and the other periods count back from today
  /// (inclusive).
  static DateRange forPeriod(Period p, {DateTime? now}) {
    final today = dateOnly(now ?? DateTime.now());
    DateTime start;
    switch (p) {
      case Period.day:
      case Period.custom:
        start = today;
      case Period.week:
        start = today.subtract(const Duration(days: 6));
      case Period.month:
        start = DateTime(today.year, today.month - 1, today.day + 1);
      case Period.months3:
        start = DateTime(today.year, today.month - 3, today.day + 1);
      case Period.months6:
        start = DateTime(today.year, today.month - 6, today.day + 1);
      case Period.months12:
        start = DateTime(today.year, today.month - 12, today.day + 1);
    }
    return DateRange(start, today);
  }

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.startDb == startDb && other.endDb == endDb;

  @override
  int get hashCode => Object.hash(startDb, endDb);
}
