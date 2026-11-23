import 'package:flutter_test/flutter_test.dart';
import 'package:mellow/core/utils/email_address.dart';

void main() {
  group('normalizeEmail', () {
    test('lowercases and trims', () {
      expect(normalizeEmail('  Ivan.Petrov@Example.COM '), 'ivan.petrov@example.com');
    });

    test('extracts the address from a display-name form', () {
      expect(normalizeEmail('Александр <alex@example.com>'), 'alex@example.com');
    });

    test('strips surrounding quotes', () {
      expect(normalizeEmail('"alex@example.com"'), 'alex@example.com');
    });
  });

  group('parseEmailAddress', () {
    test('parses a bare address', () {
      final parsed = parseEmailAddress('alex@example.com');
      expect(parsed, isNotNull);
      expect(parsed!.address, 'alex@example.com');
      expect(parsed.displayName, isNull);
    });

    test('parses name and address', () {
      final parsed = parseEmailAddress('"Petrov, Alexander" <Alex@Example.com>');
      expect(parsed!.address, 'alex@example.com');
      expect(parsed.displayName, 'Petrov, Alexander');
    });

    test('rejects invalid input', () {
      expect(parseEmailAddress('not-an-email'), isNull);
      expect(parseEmailAddress(''), isNull);
      expect(parseEmailAddress('a@b'), isNull);
      expect(parseEmailAddress('a@@b.com'), isNull);
    });
  });

  group('splitAddressList', () {
    test('splits plain lists', () {
      expect(
        splitAddressList('a@x.com, b@y.com,c@z.com'),
        <String>['a@x.com', 'b@y.com', 'c@z.com'],
      );
    });

    test('does not split inside quotes or angle brackets', () {
      final parts = splitAddressList('"Doe, John" <john@x.com>, jane@y.com');
      expect(parts, <String>['"Doe, John" <john@x.com>', 'jane@y.com']);
    });

    test('ignores empty parts', () {
      expect(splitAddressList('a@x.com, ,'), <String>['a@x.com']);
    });
  });

  group('parseAddressList', () {
    test('deduplicates by normalised address', () {
      final list = parseAddressList('A@X.com, a@x.com, b@y.com');
      expect(list.map((e) => e.address), <String>['a@x.com', 'b@y.com']);
    });

    test('drops invalid entries but keeps valid ones', () {
      final list = parseAddressList('garbage, ok@example.com');
      expect(list.single.address, 'ok@example.com');
    });
  });

  group('isValidEmail', () {
    test('accepts common addresses', () {
      expect(isValidEmail('ivan.petrov@yandex.ru'), isTrue);
      expect(isValidEmail('a+tag@sub.domain.co.uk'), isTrue);
    });

    test('rejects malformed addresses', () {
      expect(isValidEmail('ivan@'), isFalse);
      expect(isValidEmail('@yandex.ru'), isFalse);
      expect(isValidEmail('ivan@yandex'), isFalse);
      expect(isValidEmail('ivan petrov@yandex.ru'), isFalse);
    });
  });

  test('emailDomain', () {
    expect(emailDomain('Ivan@Yandex.RU'), 'yandex.ru');
    expect(emailDomain('broken'), '');
  });

  test('nameFromAddress builds a readable fallback name', () {
    expect(nameFromAddress('ivan.petrov@yandex.ru'), 'Ivan Petrov');
    expect(nameFromAddress('a1@x.com'), 'a1');
  });
}
