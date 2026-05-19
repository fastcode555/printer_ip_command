// A local fake printer for demoing the CLI output without real hardware.
// - Listens on 9100 (raw ESC/POS): replies to DLE EOT 1 with status byte 0x16,
//   to GS I 65/66/67/68 with manufacturer/model/firmware/serial strings.
// - Listens on 631 (IPP): POST /ipp/print returns a Get-Printer-Attributes
//   response advertising "Epson TM-T88V (fake)".
//
// Usage:
//   fvm dart run bin/fake_printer.dart [--raw-port 9100] [--ipp-port 631]
//   # then in another shell:
//   fvm dart run bin/printer_probe.dart 127.0.0.1

import 'dart:io';
import 'dart:typed_data';

import 'package:printer_ip_command/printer_ip_command.dart';

Future<void> main(List<String> argv) async {
  var rawPort = 9100;
  var ippPort = 631;
  var snmpPort = 161;
  var httpPort = 80;
  for (var i = 0; i < argv.length; i++) {
    if (argv[i] == '--raw-port' && i + 1 < argv.length) {
      rawPort = int.parse(argv[++i]);
    } else if (argv[i] == '--ipp-port' && i + 1 < argv.length) {
      ippPort = int.parse(argv[++i]);
    } else if (argv[i] == '--snmp-port' && i + 1 < argv.length) {
      snmpPort = int.parse(argv[++i]);
    } else if (argv[i] == '--http-port' && i + 1 < argv.length) {
      httpPort = int.parse(argv[++i]);
    }
  }

  final raw = await ServerSocket.bind(InternetAddress.loopbackIPv4, rawPort);
  stdout.writeln('fake raw     listening on 127.0.0.1:${raw.port}');
  raw.listen(_handleRaw);

  final ipp = await HttpServer.bind(InternetAddress.loopbackIPv4, ippPort);
  stdout.writeln('fake IPP     listening on 127.0.0.1:${ipp.port}');
  ipp.listen(_handleIpp);

  final snmp = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, snmpPort);
  stdout.writeln('fake SNMP    listening on 127.0.0.1:${snmp.port}');
  snmp.listen((event) {
    if (event != RawSocketEvent.read) return;
    final dg = snmp.receive();
    if (dg == null) return;
    snmp.send(_buildSnmpResponse(), dg.address, dg.port);
  });

  final http = await HttpServer.bind(InternetAddress.loopbackIPv4, httpPort);
  stdout.writeln('fake HTTP    listening on 127.0.0.1:${http.port}');
  http.listen(_handleHttp);

  stdout.writeln('Press Ctrl-C to stop.');
}

void _handleRaw(Socket socket) {
  final buf = <int>[];
  socket.listen((data) async {
    buf.addAll(data);
    // Quick scan over buffer for known command prefixes; reply per match.
    var i = 0;
    while (i < buf.length) {
      // DLE EOT 1
      if (i + 2 < buf.length &&
          buf[i] == 0x10 && buf[i + 1] == 0x04 && buf[i + 2] == 0x01) {
        socket.add([0x16]);
        await socket.flush();
        i += 3;
        continue;
      }
      // GS I n
      if (i + 2 < buf.length && buf[i] == 0x1D && buf[i + 1] == 0x49) {
        final n = buf[i + 2];
        final reply = switch (n) {
          65 => 'FW-FAKE-1.0',
          66 => 'EPSON',
          67 => 'TM-T88V (fake)',
          68 => 'SN-1234567',
          _ => '',
        };
        if (reply.isNotEmpty) {
          socket.add(reply.codeUnits + [0x00]);
          await socket.flush();
        }
        i += 3;
        continue;
      }
      // PJL UEL preamble: \x1B%-12345X then @PJL INFO ...
      if (buf[i] == 0x1B &&
          i + 9 <= buf.length &&
          String.fromCharCodes(buf.sublist(i, i + 9)) == '\x1B%-12345X') {
        final reply = '\x1B%-12345X'
            '@PJL INFO ID\r\n'
            '"TM-T88V (fake, via PJL)"\r\n'
            '\f'
            '@PJL INFO STATUS\r\n'
            'CODE=10001\r\n'
            'DISPLAY="READY"\r\n'
            'ONLINE=TRUE\r\n'
            '\f'
            '@PJL INFO PAGECOUNT\r\n'
            'PAGECOUNT=42\r\n'
            '\x1B%-12345X';
        socket.add(reply.codeUnits);
        await socket.flush();
        i += 9;
        continue;
      }
      i++;
    }
    buf.removeRange(0, i);
  }, onDone: () => socket.destroy());
}

void _handleHttp(HttpRequest req) async {
  await req.drain<void>();
  req.response
    ..statusCode = 200
    ..headers.set('Server', 'EpsonNet WebConfig 1.0')
    ..headers.contentType = ContentType.html
    ..write('<html><head><title>TM-T88V (fake) Web Configurator</title></head>'
        '<body>Welcome to EPSON TM-T88V Setup.</body></html>');
  await req.response.close();
}

void _handleIpp(HttpRequest req) async {
  await req.drain<void>();
  req.response
    ..statusCode = 200
    ..headers.contentType = ContentType('application', 'ipp')
    ..add(_buildSampleAttrs());
  await req.response.close();
}

Uint8List _buildSampleAttrs() {
  final b = BytesBuilder();
  b.add([0x01, 0x01]); // version 1.1
  b.add([0x00, 0x00]); // successful-ok
  b.add([0x00, 0x00, 0x00, 0x01]); // request-id

  b.addByte(0x01); // operation-attributes-tag
  _attr(b, 0x47, 'attributes-charset', 'utf-8');
  _attr(b, 0x48, 'attributes-natural-language', 'en');

  b.addByte(0x04); // printer-attributes-tag
  _attr(b, 0x41, 'printer-make-and-model', 'Epson TM-T88V (fake)');
  _attrInt(b, 0x23, 'printer-state', 3);
  _attr(b, 0x49, 'document-format-supported', 'application/octet-stream');
  _attr(b, 0x49, '', 'text/plain');

  b.addByte(0x03); // end-of-attributes-tag
  return b.toBytes();
}

void _attr(BytesBuilder b, int tag, String name, String value) {
  b.addByte(tag);
  b.add([(name.length >> 8) & 0xFF, name.length & 0xFF]);
  b.add(name.codeUnits);
  b.add([(value.length >> 8) & 0xFF, value.length & 0xFF]);
  b.add(value.codeUnits);
}

void _attrInt(BytesBuilder b, int tag, String name, int value) {
  b.addByte(tag);
  b.add([(name.length >> 8) & 0xFF, name.length & 0xFF]);
  b.add(name.codeUnits);
  b.add([0x00, 0x04]);
  b.add([
    (value >> 24) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 8) & 0xFF,
    value & 0xFF,
  ]);
}

Uint8List _buildSnmpResponse() {
  final vbList = BytesBuilder();
  void addStringVb(String oid, String value) {
    final oidBytes = encodeOid(oid);
    final inner = <int>[
      0x06, oidBytes.length, ...oidBytes,
      0x04, value.length, ...value.codeUnits,
    ];
    final wrapped = _wrap(0x30, inner);
    vbList.add(wrapped);
  }

  addStringVb('1.3.6.1.2.1.1.1.0', 'EPSON Built-in 10/100 Print Server (fake)');
  addStringVb('1.3.6.1.2.1.1.5.0', 'EPSON-TM-T88V-FAKE');
  addStringVb('1.3.6.1.2.1.43.5.1.1.16.1', 'TM-T88V (fake)');
  addStringVb('1.3.6.1.2.1.43.5.1.1.17.1', 'SN-1234567');

  final vbListWrapped = _wrap(0x30, vbList.toBytes());

  final pdu = BytesBuilder();
  pdu.add([0x02, 0x01, 0x01]); // request-id placeholder; real agents echo input
  pdu.add([0x02, 0x01, 0x00]);
  pdu.add([0x02, 0x01, 0x00]);
  pdu.add(vbListWrapped);
  final pduWrapped = _wrap(0xA2, pdu.toBytes());

  final msg = BytesBuilder();
  msg.add([0x02, 0x01, 0x01]); // SNMPv2c
  msg.add([0x04, 0x06]);
  msg.add('public'.codeUnits);
  msg.add(pduWrapped);
  return Uint8List.fromList(_wrap(0x30, msg.toBytes()));
}

List<int> _wrap(int tag, List<int> content) {
  final out = <int>[tag];
  final n = content.length;
  if (n < 128) {
    out.add(n);
  } else if (n < 256) {
    out.addAll([0x81, n]);
  } else {
    out.addAll([0x82, (n >> 8) & 0xFF, n & 0xFF]);
  }
  out.addAll(content);
  return out;
}
