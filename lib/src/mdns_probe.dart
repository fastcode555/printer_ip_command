import 'dart:async';
import 'dart:io';

import 'package:multicast_dns/multicast_dns.dart';

/// Result aggregated across mDNS service browses (_ipp, _pdl-datastream,
/// _printer) for a single target IP.
class MdnsResult {
  final String host;
  final List<String> services;
  final String? hostname;
  final Map<String, String> txt;

  const MdnsResult({
    required this.host,
    required this.services,
    this.hostname,
    this.txt = const {},
  });

  String? get modelGuess => txt['ty'] ?? txt['usb_mdl'] ?? txt['product'];
  String? get adminUrl => txt['adminurl'];
  List<String> get supportedFormats =>
      (txt['pdl'] ?? '').split(',').where((s) => s.isNotEmpty).toList();

  @override
  String toString() => 'MdnsResult(host: $host, services: $services, '
      'hostname: $hostname, model: $modelGuess, formats: $supportedFormats)';
}

Map<String, String> parseMdnsTxt(List<String> lines) {
  final out = <String, String>{};
  for (final l in lines) {
    final eq = l.indexOf('=');
    if (eq <= 0) continue;
    out[l.substring(0, eq).toLowerCase()] = l.substring(eq + 1);
  }
  return out;
}

const List<String> _printerServiceTypes = [
  '_ipp._tcp.local',
  '_ipps._tcp.local',
  '_pdl-datastream._tcp.local',
  '_printer._tcp.local',
];

class MdnsProbe {
  /// Browses common printer service types and returns the consolidated record
  /// whose resolved A address matches [host]. Returns null on no match / timeout.
  static Future<MdnsResult?> query(
    String host, {
    Duration timeout = const Duration(seconds: 2),
    List<String> serviceTypes = _printerServiceTypes,
  }) async {
    final client = MDnsClient(rawDatagramSocketFactory: _datagramFactory);
    try {
      await client.start();
    } catch (_) {
      return null;
    }

    final matchedServices = <String>{};
    final aggregatedTxt = <String, String>{};
    String? matchedHostname;
    final deadline = DateTime.now().add(timeout);

    try {
      for (final svc in serviceTypes) {
        if (DateTime.now().isAfter(deadline)) break;
        final remaining = deadline.difference(DateTime.now());
        if (remaining <= Duration.zero) break;

        await for (final PtrResourceRecord ptr in client
            .lookup<PtrResourceRecord>(ResourceRecordQuery.serverPointer(svc))
            .timeout(remaining, onTimeout: (sink) => sink.close())) {
          if (DateTime.now().isAfter(deadline)) break;
          await _resolveAndMatch(
            client: client,
            host: host,
            ptr: ptr,
            deadline: deadline,
            onMatch: (hostname, txt) {
              matchedServices.add(svc);
              if (hostname != null) matchedHostname = hostname;
              aggregatedTxt.addAll(txt);
            },
          );
        }
      }
    } catch (_) {
      // swallow — return whatever was collected
    } finally {
      client.stop();
    }

    if (matchedServices.isEmpty) return null;
    return MdnsResult(
      host: host,
      services: matchedServices.toList(),
      hostname: matchedHostname,
      txt: Map.unmodifiable(aggregatedTxt),
    );
  }

  static Future<void> _resolveAndMatch({
    required MDnsClient client,
    required String host,
    required PtrResourceRecord ptr,
    required DateTime deadline,
    required void Function(String? hostname, Map<String, String> txt) onMatch,
  }) async {
    final instance = ptr.domainName;
    String? hostname;
    final txt = <String, String>{};
    var ipMatched = false;

    final srvRemaining = deadline.difference(DateTime.now());
    if (srvRemaining <= Duration.zero) return;
    await for (final SrvResourceRecord srv in client
        .lookup<SrvResourceRecord>(ResourceRecordQuery.service(instance))
        .timeout(srvRemaining, onTimeout: (sink) => sink.close())) {
      hostname = srv.target;
      final ipRemaining = deadline.difference(DateTime.now());
      if (ipRemaining <= Duration.zero) break;
      await for (final IPAddressResourceRecord ip in client
          .lookup<IPAddressResourceRecord>(
              ResourceRecordQuery.addressIPv4(srv.target))
          .timeout(ipRemaining, onTimeout: (sink) => sink.close())) {
        if (ip.address.address == host) {
          ipMatched = true;
          break;
        }
      }
      if (ipMatched) break;
    }

    if (!ipMatched) return;

    final txtRemaining = deadline.difference(DateTime.now());
    if (txtRemaining > Duration.zero) {
      await for (final TxtResourceRecord rec in client
          .lookup<TxtResourceRecord>(ResourceRecordQuery.text(instance))
          .timeout(txtRemaining, onTimeout: (sink) => sink.close())) {
        txt.addAll(parseMdnsTxt(rec.text.split('\n')));
      }
    }

    onMatch(hostname, txt);
  }
}

Future<RawDatagramSocket> _datagramFactory(
  dynamic host,
  int port, {
  bool reuseAddress = true,
  bool reusePort = false,
  int ttl = 1,
}) {
  return RawDatagramSocket.bind(host, port,
      reuseAddress: reuseAddress, reusePort: reusePort, ttl: ttl);
}
