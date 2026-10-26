import 'package:alfamart_cashflow/core/date_range.dart';
import 'package:alfamart_cashflow/core/money.dart';
import 'package:alfamart_cashflow/core/security.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Money', () {
    test('parses rupees and paisa exactly', () {
      expect(Money.tryParse('1,250.50'), 125050);
      expect(Money.tryParse('10'), 1000);
      expect(Money.tryParse('0.1'), 10);
      expect(Money.tryParse(''), 0);
      expect(Money.tryParse('1.234'), isNull);
      expect(Money.tryParse('-5'), isNull);
      expect(Money.tryParse('abc'), isNull);
    });

    test('formats', () {
      expect(Money.format(125050), 'Rs 1,250.5');
      expect(Money.format(100000), 'Rs 1,000');
      expect(Money.toInput(125050), '1250.50');
      expect(Money.toInput(100000), '1000');
    });
  });

  group('PasswordHasher', () {
    test('verifies correct password only', () {
      final salt = PasswordHasher.newSalt();
      final h = PasswordHasher.hash('secret123', salt, iterations: 1000);
      expect(PasswordHasher.verify('secret123', salt, h, 1000), isTrue);
      expect(PasswordHasher.verify('secret124', salt, h, 1000), isFalse);
    });

    test('strength rules', () {
      expect(PasswordHasher.validateStrength('abc'), isNotNull);
      expect(PasswordHasher.validateStrength('abcdefg'), isNotNull);
      expect(PasswordHasher.validateStrength('abc123'), isNull);
    });
  });

  group('DateRange periods', () {
    final now = DateTime(2026, 10, 26, 15);
    test('24 hours is today', () {
      final r = DateRange.forPeriod(Period.day, now: now);
      expect(r.startDb, '2026-10-26');
      expect(r.endDb, '2026-10-26');
    });
    test('week is 7 days inclusive', () {
      expect(DateRange.forPeriod(Period.week, now: now).days, 7);
    });
    test('months count back', () {
      expect(DateRange.forPeriod(Period.month, now: now).startDb, '2026-09-27');
      expect(DateRange.forPeriod(Period.months3, now: now).startDb, '2026-07-27');
      expect(DateRange.forPeriod(Period.months12, now: now).startDb, '2025-10-27');
    });
  });
}
