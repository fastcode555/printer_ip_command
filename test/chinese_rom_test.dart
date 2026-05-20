import 'package:printer_ip_command/src/chinese_rom.dart';
import 'package:test/test.dart';

void main() {
  group('classifyLanguage', () {
    test('HONG KONG BIG5 → traditional', () {
      expect(classifyLanguage('HONG KONG BIG5'), ChineseRom.traditional);
    });

    test('TAIWAN BIG5 → traditional', () {
      expect(classifyLanguage('TAIWAN BIG5'), ChineseRom.traditional);
    });

    test('lowercase big5 → traditional (case insensitive)', () {
      expect(classifyLanguage('big5'), ChineseRom.traditional);
    });

    test('CHINA GB18030 → simplified', () {
      expect(classifyLanguage('CHINA GB18030'), ChineseRom.simplified);
    });

    test('CHINA GBK → simplified', () {
      expect(classifyLanguage('CHINA GBK'), ChineseRom.simplified);
    });

    test('bare GB string → simplified (prefix match)', () {
      expect(classifyLanguage('CHINA GB'), ChineseRom.simplified);
    });

    test('null → unknown', () {
      expect(classifyLanguage(null), ChineseRom.unknown);
    });

    test('empty string → unknown', () {
      expect(classifyLanguage(''), ChineseRom.unknown);
    });

    test('JAPAN JIS → unknown (other Asian languages)', () {
      expect(classifyLanguage('JAPAN JIS'), ChineseRom.unknown);
    });

    test('random gibberish → unknown', () {
      expect(classifyLanguage('foobar'), ChineseRom.unknown);
    });

    test('mixed BIG5 wins over GB (priority)', () {
      // Hypothetical string containing both — Big5 should win because it's
      // the more specific Traditional Chinese marker.
      expect(classifyLanguage('BIG5 GB INTL'), ChineseRom.traditional);
    });
  });
}
