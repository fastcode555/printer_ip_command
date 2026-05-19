import 'dart:async';
import 'dart:io';

class PjlResult {
  final String? modelId;
  final String? statusDisplay;
  final bool? online;
  final int? pageCount;
  final String raw;

  const PjlResult({
    this.modelId,
    this.statusDisplay,
    this.online,
    this.pageCount,
    this.raw = '',
  });

  @override
  String toString() => 'PjlResult(modelId: $modelId, display: $statusDisplay, '
      'online: $online, pageCount: $pageCount)';
}

// UEL = Universal Exit Language: ESC %-12345X
const String _uel = '\x1B%-12345X';
const String _pjlPayload = '$_uel'
    '@PJL INFO ID\r\n'
    '@PJL INFO STATUS\r\n'
    '@PJL INFO PAGECOUNT\r\n'
    '$_uel';

PjlResult parsePjlResponse(String text) {
  String? modelId;
  String? statusDisplay;
  bool? online;
  int? pageCount;

  final blocks = _splitBlocks(text);
  for (final block in blocks) {
    if (block.startsWith('@PJL INFO ID')) {
      modelId = _readFirstValueLine(block);
    } else if (block.startsWith('@PJL INFO STATUS')) {
      final fields = _parseKeyValues(block);
      statusDisplay = _unquote(fields['DISPLAY']);
      final onlineRaw = fields['ONLINE']?.toUpperCase();
      if (onlineRaw == 'TRUE') online = true;
      if (onlineRaw == 'FALSE') online = false;
    } else if (block.startsWith('@PJL INFO PAGECOUNT')) {
      final fields = _parseKeyValues(block);
      final pc = fields['PAGECOUNT'];
      if (pc != null) pageCount = int.tryParse(pc);
    }
  }

  return PjlResult(
    modelId: modelId,
    statusDisplay: statusDisplay,
    online: online,
    pageCount: pageCount,
    raw: text,
  );
}

List<String> _splitBlocks(String text) {
  // PJL blocks begin with "@PJL "; split into chunks keeping the marker.
  final blocks = <String>[];
  final regex = RegExp(r'@PJL [^@\x1B]*', dotAll: false);
  for (final m in regex.allMatches(text)) {
    blocks.add(m.group(0)!.trim());
  }
  return blocks;
}

String? _readFirstValueLine(String block) {
  final lines = block.split(RegExp(r'\r?\n'));
  for (var i = 1; i < lines.length; i++) {
    final t = lines[i].trim();
    if (t.isEmpty) continue;
    return _unquote(t);
  }
  return null;
}

Map<String, String> _parseKeyValues(String block) {
  final map = <String, String>{};
  for (final line in block.split(RegExp(r'\r?\n'))) {
    final eq = line.indexOf('=');
    if (eq <= 0) continue;
    map[line.substring(0, eq).trim()] = line.substring(eq + 1).trim();
  }
  return map;
}

String? _unquote(String? s) {
  if (s == null) return null;
  if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
    return s.substring(1, s.length - 1);
  }
  return s;
}

class PjlProbe {
  static Future<PjlResult?> query(
    String host, {
    int port = 9100,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      socket.add(_pjlPayload.codeUnits);
      await socket.flush();

      final received = <int>[];
      final completer = Completer<void>();
      late StreamSubscription<List<int>> sub;

      bool sawClosingUel() {
        // Response is wrapped: <UEL> @PJL INFO ... <UEL>. If the buffer contains
        // any UEL byte sequence after some PJL content, the printer is done.
        final text = String.fromCharCodes(received);
        final firstAt = text.indexOf('@PJL');
        if (firstAt < 0) return false;
        return text.indexOf(_uel, firstAt) >= 0;
      }

      sub = socket.listen(
        (data) {
          received.addAll(data);
          if (sawClosingUel() && !completer.isCompleted) completer.complete();
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
        onError: (Object e) {
          if (!completer.isCompleted) completer.completeError(e);
        },
        cancelOnError: true,
      );

      try {
        await completer.future.timeout(timeout);
      } on TimeoutException {
        // we'll parse whatever we got
      } finally {
        await sub.cancel();
      }

      if (received.isEmpty) return null;
      final text = String.fromCharCodes(received);
      final parsed = parsePjlResponse(text);
      if (parsed.modelId == null &&
          parsed.statusDisplay == null &&
          parsed.pageCount == null) {
        // Got bytes but no recognizable PJL sections — not a PJL device.
        return null;
      }
      return parsed;
    } on SocketException {
      return null;
    } finally {
      socket?.destroy();
    }
  }
}
