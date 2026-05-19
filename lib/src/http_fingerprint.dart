import 'dart:async';
import 'dart:io';

class HttpFingerprint {
  final int statusCode;
  final String? serverHeader;
  final String? title;
  final String? vendorGuess;

  const HttpFingerprint({
    required this.statusCode,
    this.serverHeader,
    this.title,
    this.vendorGuess,
  });

  @override
  String toString() => 'HttpFingerprint(server: $serverHeader, title: $title, '
      'vendorGuess: $vendorGuess, statusCode: $statusCode)';
}

// Known vendor markers: case-insensitive substring → canonical name.
const Map<String, String> _vendorMarkers = {
  'EPSON': 'EPSON',
  'EpsonNet': 'EPSON',
  'HP ': 'HP',
  'HP LaserJet': 'HP',
  'HP-ChaiSOE': 'HP',
  'Brother': 'Brother',
  'Canon': 'Canon',
  'Xerox': 'Xerox',
  'Ricoh': 'Ricoh',
  'Samsung': 'Samsung',
  'Lexmark': 'Lexmark',
  'OKI': 'OKI',
  'Konica': 'Konica',
  'Star Micronics': 'Star',
  'Bixolon': 'Bixolon',
  'Citizen': 'Citizen',
  'SNBC': 'SNBC',
  'Zebra': 'Zebra',
  'TSC ': 'TSC',
  'Xprinter': 'Xprinter',
  'XPrinter': 'Xprinter',
  '芯烨': 'Xprinter',
  '佳博': 'Gprinter',
  'Gprinter': 'Gprinter',
  'HOIN': 'HOIN',
  'Rongta': 'Rongta',
  '商米': 'Sunmi',
  'Sunmi': 'Sunmi',
};

HttpFingerprint extractFingerprint({
  required String? serverHeader,
  required String body,
  int statusCode = 200,
}) {
  String? title;
  final titleMatch = RegExp(r'<title[^>]*>([^<]*)</title\s*>',
          caseSensitive: false)
      .firstMatch(body);
  if (titleMatch != null) {
    title = titleMatch.group(1)?.trim();
    if (title != null && title.isEmpty) title = null;
  }

  String? vendor;
  // Prefer Server header — it's more deliberate than body text.
  for (final entry in _vendorMarkers.entries) {
    final hit = serverHeader != null &&
        serverHeader.toLowerCase().contains(entry.key.toLowerCase());
    if (hit) {
      vendor = entry.value;
      break;
    }
  }
  if (vendor == null) {
    for (final entry in _vendorMarkers.entries) {
      if (body.toLowerCase().contains(entry.key.toLowerCase())) {
        vendor = entry.value;
        break;
      }
    }
  }

  return HttpFingerprint(
    statusCode: statusCode,
    serverHeader: serverHeader,
    title: title,
    vendorGuess: vendor,
  );
}

class HttpFingerprintProbe {
  static const int _maxBodyBytes = 64 * 1024;

  static Future<HttpFingerprint?> query(
    String host, {
    int port = 80,
    String path = '/',
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..maxConnectionsPerHost = 1;
    try {
      final req = await client
          .getUrl(Uri.parse('http://$host:$port$path'))
          .timeout(timeout);
      req.followRedirects = true;
      req.maxRedirects = 2;
      req.headers.set(HttpHeaders.acceptHeader, 'text/html, */*');
      final resp = await req.close().timeout(timeout);

      final serverHeader = resp.headers.value(HttpHeaders.serverHeader);

      var bytes = <int>[];
      try {
        await for (final chunk in resp.timeout(timeout)) {
          bytes.addAll(chunk);
          if (bytes.length >= _maxBodyBytes) {
            bytes = bytes.sublist(0, _maxBodyBytes);
            break;
          }
        }
      } catch (_) {
        // Treat as partial body — still try to extract fingerprint.
      }
      final body = String.fromCharCodes(bytes);
      return extractFingerprint(
        serverHeader: serverHeader,
        body: body,
        statusCode: resp.statusCode,
      );
    } on SocketException {
      return null;
    } on TimeoutException {
      return null;
    } on HttpException {
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
