import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

class EscPosIdentity {
  final String? firmware;       // GS I 65
  final String? manufacturer;   // GS I 66
  final String? model;          // GS I 67
  final String? serial;         // GS I 68
  final String? language;       // GS I 69 (0x45) — "font of language" ROM

  const EscPosIdentity({
    this.firmware,
    this.manufacturer,
    this.model,
    this.serial,
    this.language,
  });

  bool get hasAny =>
      firmware != null ||
      manufacturer != null ||
      model != null ||
      serial != null ||
      language != null;

  @override
  String toString() =>
      'EscPosIdentity(mfr: $manufacturer, model: $model, fw: $firmware, '
      'sn: $serial, lang: $language)';
}

// GS I n — request printer identity. n: 65=firmware 66=mfr 67=model 68=serial
List<int> gsIQuery(int n) => [0x1D, 0x49, n];

String? parseGsIResponse(Uint8List bytes) {
  if (bytes.isEmpty) return null;
  var start = 0;
  if (bytes[0] == 0x5F) start = 1; // Type B header
  var end = bytes.indexOf(0x00, start);
  if (end < 0) end = bytes.length;
  if (end <= start) return null;

  for (var i = start; i < end; i++) {
    final b = bytes[i];
    final printable = b >= 0x20 && b <= 0x7E;
    if (!printable) return null;
  }
  return String.fromCharCodes(bytes.sublist(start, end));
}

/// Convenience: open a socket to host:port, send GS I 65-68, return identity or null on error.
Future<EscPosIdentity?> probeEscPosIdentity(
  String host, {
  int port = 9100,
  Duration connectTimeout = const Duration(seconds: 2),
  Duration totalWait = const Duration(milliseconds: 800),
}) async {
  Socket? socket;
  try {
    socket = await Socket.connect(host, port, timeout: connectTimeout);
    return await queryEscPosIdentity(socket, totalWait: totalWait);
  } on SocketException {
    return null;
  } on TimeoutException {
    return null;
  } finally {
    socket?.destroy();
  }
}

/// Send GS I 65/66/67/68/69 over an already-connected socket and collect responses.
///
/// Strategy: send all five queries back-to-back, then accumulate response bytes
/// for [totalWait]. Split on NUL boundaries to recover five fields in order.
/// Printers that don't implement a given field stay silent — we tolerate fewer
/// than five segments in the reply.
Future<EscPosIdentity> queryEscPosIdentity(
  Socket socket, {
  Duration totalWait = const Duration(milliseconds: 800),
}) async {
  final completer = Completer<List<Uint8List>>();
  final buffer = BytesBuilder();
  final segments = <Uint8List>[];

  void flushSegment() {
    if (buffer.isEmpty) return;
    segments.add(buffer.toBytes());
    buffer.clear();
  }

  late StreamSubscription<List<int>> sub;
  sub = socket.listen(
    (data) {
      for (final b in data) {
        if (b == 0x00) {
          flushSegment();
        } else {
          buffer.addByte(b);
        }
      }
    },
    onDone: () {
      flushSegment();
      if (!completer.isCompleted) completer.complete(segments);
    },
    onError: (Object e) {
      if (!completer.isCompleted) completer.completeError(e);
    },
    cancelOnError: true,
  );

  socket.add(gsIQuery(65));
  socket.add(gsIQuery(66));
  socket.add(gsIQuery(67));
  socket.add(gsIQuery(68));
  socket.add(gsIQuery(69)); // 0x45: font of language (Big5 / GBK / ...)
  await socket.flush();

  try {
    await completer.future.timeout(totalWait);
  } on TimeoutException {
    flushSegment();
  } finally {
    await sub.cancel();
  }

  String? pick(int i) {
    if (i >= segments.length) return null;
    return parseGsIResponse(segments[i]);
  }

  return EscPosIdentity(
    firmware: pick(0),
    manufacturer: pick(1),
    model: pick(2),
    serial: pick(3),
    language: pick(4),
  );
}
