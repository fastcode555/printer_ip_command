import 'package:printer_ip_command/src/mdns_probe.dart';
import 'package:test/test.dart';

void main() {
  group('parseMdnsTxt', () {
    test('extracts key=value pairs, lowercases keys', () {
      final m = parseMdnsTxt(const [
        'ty=Epson TM-T88V',
        'pdl=application/octet-stream',
        'rp=ipp/print',
      ]);
      expect(m['ty'], 'Epson TM-T88V');
      expect(m['pdl'], 'application/octet-stream');
      expect(m['rp'], 'ipp/print');
    });

    test('handles equals signs in value', () {
      final m = parseMdnsTxt(const ['url=http://x.local/path?k=v']);
      expect(m['url'], 'http://x.local/path?k=v');
    });

    test('ignores malformed lines without =', () {
      final m = parseMdnsTxt(const ['nokeyvaluehere', 'ty=ok']);
      expect(m.length, 1);
      expect(m['ty'], 'ok');
    });

    test('last value wins on duplicate keys', () {
      final m = parseMdnsTxt(const ['ty=A', 'ty=B']);
      expect(m['ty'], 'B');
    });
  });

  group('MdnsResult.summary', () {
    test('prefers `ty` TXT field for model', () {
      final r = MdnsResult(
        host: '10.0.0.5',
        services: const ['_ipp._tcp'],
        hostname: 'TM-T88V.local',
        txt: const {'ty': 'Epson TM-T88V', 'usb_mdl': 'TM-T88V'},
      );
      expect(r.modelGuess, 'Epson TM-T88V');
    });

    test('falls back to usb_MDL when ty missing', () {
      final r = MdnsResult(
        host: '10.0.0.5',
        services: const ['_pdl-datastream._tcp'],
        hostname: 'printer.local',
        txt: const {'usb_mdl': 'XP-T80A'},
      );
      expect(r.modelGuess, 'XP-T80A');
    });
  });
}
