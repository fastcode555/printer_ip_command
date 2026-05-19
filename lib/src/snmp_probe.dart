import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'snmp.dart';

class SnmpResult {
  final String? sysDescr;
  final String? sysName;
  final String? printerName;
  final String? printerSerial;
  final Map<String, String> varBinds;

  const SnmpResult({
    this.sysDescr,
    this.sysName,
    this.printerName,
    this.printerSerial,
    this.varBinds = const {},
  });

  @override
  String toString() =>
      'SnmpResult(sysDescr: $sysDescr, sysName: $sysName, '
      'printerName: $printerName, printerSerial: $printerSerial)';
}

const String _oidSysDescr = '1.3.6.1.2.1.1.1.0';
const String _oidSysName = '1.3.6.1.2.1.1.5.0';
const String _oidPrinterName = '1.3.6.1.2.1.43.5.1.1.16.1';
const String _oidPrinterSerial = '1.3.6.1.2.1.43.5.1.1.17.1';

class SnmpProbe {
  static final _rng = Random.secure();

  static Future<SnmpResult?> query(
    String host, {
    int port = 161,
    String community = 'public',
    Duration timeout = const Duration(seconds: 2),
    List<String> oids = const [
      _oidSysDescr,
      _oidSysName,
      _oidPrinterName,
      _oidPrinterSerial,
    ],
  }) async {
    final requestId = _rng.nextInt(0x7FFFFFFF);
    final request = buildGetRequest(
      community: community,
      requestId: requestId,
      oids: oids,
    );

    RawDatagramSocket? socket;
    final completer = Completer<Uint8List?>();
    StreamSubscription<RawSocketEvent>? sub;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      sub = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = socket!.receive();
        if (dg == null) return;
        if (!completer.isCompleted) {
          completer.complete(Uint8List.fromList(dg.data));
        }
      }, onError: (Object e) {
        if (!completer.isCompleted) completer.complete(null);
      });

      socket.send(request, InternetAddress(host), port);

      final reply = await completer.future.timeout(timeout, onTimeout: () => null);
      if (reply == null) return null;

      final parsed = parseGetResponse(reply);
      return SnmpResult(
        sysDescr: parsed.varBinds[_oidSysDescr],
        sysName: parsed.varBinds[_oidSysName],
        printerName: parsed.varBinds[_oidPrinterName],
        printerSerial: parsed.varBinds[_oidPrinterSerial],
        varBinds: parsed.varBinds,
      );
    } on SocketException {
      return null;
    } on FormatException {
      return null;
    } finally {
      await sub?.cancel();
      socket?.close();
    }
  }
}
