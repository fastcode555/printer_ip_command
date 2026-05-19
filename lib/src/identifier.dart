import 'dart:async';
import 'dart:io';

import 'escpos_identity.dart';
import 'escpos_status.dart';
import 'http_fingerprint.dart';
import 'ipp_probe.dart';
import 'mdns_probe.dart';
import 'pjl_probe.dart';
import 'probe.dart';
import 'protocol.dart';
import 'snmp_probe.dart';

enum ChannelStatus { success, failed, skipped }

class ChannelOutcome<T> {
  final ChannelStatus status;
  final T? value;
  final String error;
  final Duration elapsed;

  const ChannelOutcome({
    required this.status,
    this.value,
    this.error = '',
    required this.elapsed,
  });

  bool get ok => status == ChannelStatus.success;
}

class DeviceInfo {
  final String host;
  final Protocol protocol;
  final String? vendor;
  final String? model;
  final String? firmware;
  final String? serial;
  final String? makeAndModel;
  final String? sysDescr;
  final String? sysName;
  final String? mdnsHostname;
  final List<String> mdnsServices;
  final EscPosStatus? escPosStatus;
  final int? ippState;
  final List<String> documentFormats;

  const DeviceInfo({
    required this.host,
    required this.protocol,
    this.vendor,
    this.model,
    this.firmware,
    this.serial,
    this.makeAndModel,
    this.sysDescr,
    this.sysName,
    this.mdnsHostname,
    this.mdnsServices = const [],
    this.escPosStatus,
    this.ippState,
    this.documentFormats = const [],
  });

  @override
  String toString() => 'DeviceInfo('
      'host: $host, protocol: $protocol, vendor: $vendor, model: $model, '
      'firmware: $firmware, serial: $serial, makeAndModel: $makeAndModel, '
      'sysDescr: $sysDescr, sysName: $sysName, '
      'escPosStatus: $escPosStatus, ippState: $ippState, '
      'documentFormats: $documentFormats)';
}

class IdentifyReport {
  final String host;
  final ChannelOutcome<ProbeResult> escPosProbe;
  final ChannelOutcome<EscPosIdentity> gsIdentity;
  final ChannelOutcome<PjlResult> pjl;
  final ChannelOutcome<IppResult> ipp;
  final ChannelOutcome<SnmpResult> snmp;
  final ChannelOutcome<HttpFingerprint> http;
  final ChannelOutcome<MdnsResult> mdns;
  final DeviceInfo device;

  const IdentifyReport({
    required this.host,
    required this.escPosProbe,
    required this.gsIdentity,
    required this.pjl,
    required this.ipp,
    required this.snmp,
    required this.http,
    required this.mdns,
    required this.device,
  });
}

DeviceInfo mergeDeviceInfo({
  required String host,
  required ProbeResult? probe,
  required IppResult? ipp,
  required EscPosIdentity? identity,
  SnmpResult? snmp,
  PjlResult? pjl,
  HttpFingerprint? http,
  MdnsResult? mdns,
}) {
  final protocol = probe?.protocol ?? Protocol.unknown;
  final vendor = identity?.manufacturer ?? http?.vendorGuess;
  final model = identity?.model ??
      pjl?.modelId ??
      snmp?.printerName ??
      mdns?.modelGuess ??
      ipp?.makeAndModel ??
      http?.title ??
      snmp?.sysDescr;
  final serial = identity?.serial ?? snmp?.printerSerial;
  final mergedFormats = <String>{
    ...?ipp?.documentFormats,
    ...?mdns?.supportedFormats,
  }.toList();
  return DeviceInfo(
    host: host,
    protocol: protocol,
    vendor: vendor,
    model: model,
    firmware: identity?.firmware,
    serial: serial,
    makeAndModel: ipp?.makeAndModel,
    sysDescr: snmp?.sysDescr,
    sysName: snmp?.sysName,
    mdnsHostname: mdns?.hostname,
    mdnsServices: mdns?.services ?? const [],
    escPosStatus: probe?.status,
    ippState: ipp?.state,
    documentFormats: mergedFormats,
  );
}

class PrinterIdentifier {
  /// Identify a printer at [host].
  ///
  /// **[deep]** controls "invasive" probes that may leave bytes in the print
  /// buffer of unrelated firmwares or trigger undefined-command behaviour on
  /// cheap thermals:
  ///   - ZPL `~HI` + TSPL `~!T` sent to 9100   — would print as garbage on ESC/POS
  ///   - PJL `\x1B%-12345X` UEL                — undefined ESC seq for ESC/POS firmware,
  ///                                             clones have been observed wedging
  ///
  /// Default is `false` (safe): only DLE EOT 1 on 9100, plus GS I (Epson-defined
  /// read-only ID query) when ESC/POS is confirmed. Other channels (IPP/SNMP/
  /// HTTP/mDNS) live on independent ports and are always safe.
  static Future<IdentifyReport> identify(
    String host, {
    int rawPort = 9100,
    int ippPort = 631,
    int snmpPort = 161,
    int httpPort = 80,
    String snmpCommunity = 'public',
    Duration timeout = const Duration(seconds: 2),
    bool deep = false,
  }) async {
    final probeOutcome = _run<ProbeResult>(
      () => PrinterProbe.probe(host, port: rawPort, timeout: timeout, deep: deep),
    );
    final pjlOutcome = deep
        ? _run<PjlResult?>(
            () => PjlProbe.query(host, port: rawPort, timeout: timeout),
          )
        : Future.value(const ChannelOutcome<PjlResult?>(
            status: ChannelStatus.skipped,
            elapsed: Duration.zero,
            error: 'invasive probe — only runs with --deep',
          ));
    final ippOutcome = _run<IppResult?>(
      () => IppProbe.query(host, port: ippPort, timeout: timeout),
    );
    final snmpOutcome = _run<SnmpResult?>(
      () => SnmpProbe.query(host,
          port: snmpPort, community: snmpCommunity, timeout: timeout),
    );
    final httpOutcome = _run<HttpFingerprint?>(
      () => HttpFingerprintProbe.query(host, port: httpPort, timeout: timeout),
    );
    final mdnsOutcome = _run<MdnsResult?>(
      () => MdnsProbe.query(host, timeout: timeout),
    );

    final results = await Future.wait([
      probeOutcome,
      pjlOutcome,
      ippOutcome,
      snmpOutcome,
      httpOutcome,
      mdnsOutcome,
    ]);
    final probe = results[0] as ChannelOutcome<ProbeResult>;
    final pjlAny = results[1] as ChannelOutcome<PjlResult?>;
    final ippAny = results[2] as ChannelOutcome<IppResult?>;
    final snmpAny = results[3] as ChannelOutcome<SnmpResult?>;
    final httpAny = results[4] as ChannelOutcome<HttpFingerprint?>;
    final mdnsAny = results[5] as ChannelOutcome<MdnsResult?>;

    final pjl = _coerceNullableSuccess<PjlResult>(
      pjlAny,
      'no PJL response (device does not implement PJL)',
    );
    final ipp = _coerceNullableSuccess<IppResult>(
      ippAny,
      'no IPP response (port closed or path mismatch)',
    );
    final snmp = _coerceNullableSuccess<SnmpResult>(
      snmpAny,
      'no SNMP response (agent disabled or community mismatch)',
    );
    final http = _coerceNullableSuccess<HttpFingerprint>(
      httpAny,
      'no HTTP banner (port closed or non-HTTP)',
    );
    final mdns = _coerceNullableSuccess<MdnsResult>(
      mdnsAny,
      'no mDNS service matching this IP (device not advertising)',
    );

    ChannelOutcome<EscPosIdentity> gsIdentity;
    if (probe.ok && probe.value?.protocol == Protocol.escPos) {
      final raw = await _run<EscPosIdentity?>(
        () => probeEscPosIdentity(host, port: rawPort),
      );
      gsIdentity = _coerceNullableSuccess<EscPosIdentity>(
        raw,
        'no GS I response',
      );
    } else {
      gsIdentity = const ChannelOutcome<EscPosIdentity>(
        status: ChannelStatus.skipped,
        elapsed: Duration.zero,
        error: 'protocol is not ESC/POS',
      );
    }

    final device = mergeDeviceInfo(
      host: host,
      probe: probe.value,
      ipp: ipp.value,
      identity: gsIdentity.value,
      snmp: snmp.value,
      pjl: pjl.value,
      http: http.value,
      mdns: mdns.value,
    );

    return IdentifyReport(
      host: host,
      escPosProbe: probe,
      gsIdentity: gsIdentity,
      pjl: pjl,
      ipp: ipp,
      snmp: snmp,
      http: http,
      mdns: mdns,
      device: device,
    );
  }
}

ChannelOutcome<T> _coerceNullableSuccess<T>(
  ChannelOutcome<T?> outcome,
  String emptyError,
) {
  if (outcome.value == null && outcome.status == ChannelStatus.success) {
    return ChannelOutcome<T>(
      status: ChannelStatus.failed,
      elapsed: outcome.elapsed,
      error: emptyError,
    );
  }
  return ChannelOutcome<T>(
    status: outcome.status,
    value: outcome.value,
    error: outcome.error,
    elapsed: outcome.elapsed,
  );
}

Future<ChannelOutcome<T>> _run<T>(Future<T> Function() body) async {
  final sw = Stopwatch()..start();
  try {
    final v = await body();
    sw.stop();
    return ChannelOutcome<T>(
      status: ChannelStatus.success,
      value: v,
      elapsed: sw.elapsed,
    );
  } on TimeoutException catch (e) {
    sw.stop();
    return ChannelOutcome<T>(
      status: ChannelStatus.failed,
      error: 'timeout: ${e.message ?? ''}',
      elapsed: sw.elapsed,
    );
  } on SocketException catch (e) {
    sw.stop();
    return ChannelOutcome<T>(
      status: ChannelStatus.failed,
      error: 'socket: ${e.message}',
      elapsed: sw.elapsed,
    );
  } catch (e) {
    sw.stop();
    return ChannelOutcome<T>(
      status: ChannelStatus.failed,
      error: e.toString(),
      elapsed: sw.elapsed,
    );
  }
}
