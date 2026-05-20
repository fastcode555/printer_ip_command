import 'package:flutter/material.dart';
import 'package:printer_ip_command/printer_ip_command.dart';

import '../services/printer_service.dart';
import '../widgets/channel_card.dart';
import '../widgets/device_info_panel.dart';
import '../widgets/print_test_dialog.dart';

class DiagnosePage extends StatefulWidget {
  final PrinterService service;
  const DiagnosePage({super.key, required this.service});

  @override
  State<DiagnosePage> createState() => _DiagnosePageState();
}

class _DiagnosePageState extends State<DiagnosePage> {
  final _ipCtrl = TextEditingController();
  static final _ipRegex = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');
  bool _deep = false;
  Future<IdentifyReport>? _pending;
  String? _lastIp;

  bool get _ipValid => _ipRegex.hasMatch(_ipCtrl.text.trim());

  @override
  void dispose() {
    _ipCtrl.dispose();
    super.dispose();
  }

  void _runIdentify() {
    final ip = _ipCtrl.text.trim();
    setState(() {
      _lastIp = ip;
      _pending = widget.service.identify(ip, deep: _deep);
    });
  }

  Future<void> _runPrintTest(String host) async {
    final enc = await showPrintTestDialog(context);
    if (enc == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final n = await widget.service.printTest(host, enc);
      messenger.showSnackBar(SnackBar(
        backgroundColor: Colors.green.shade700,
        content: Text('Sent $n bytes'),
      ));
    } on PrintTestException catch (e) {
      messenger.showSnackBar(SnackBar(
        backgroundColor: Colors.red.shade700,
        content: Text(e.message),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('printer_ip diagnose')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _ipCtrl,
              decoration: const InputDecoration(
                labelText: 'Printer IP',
                hintText: '192.168.0.10',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Include invasive probes (PJL/ZPL)'),
              value: _deep,
              onChanged: (v) => setState(() => _deep = v ?? false),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _ipValid ? _runIdentify : null,
              child: const Text('Identify'),
            ),
            const SizedBox(height: 12),
            Expanded(child: _buildResult()),
          ],
        ),
      ),
    );
  }

  Widget _buildResult() {
    final pending = _pending;
    if (pending == null) {
      return const Center(child: Text('Enter an IP and tap Identify.'));
    }
    return FutureBuilder<IdentifyReport>(
      future: pending,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snap.hasData) {
          // Cannot happen — identify never throws. Defensive only.
          return Center(child: Text('error: ${snap.error}'));
        }
        final report = snap.data!;
        final canPrint = report.escPosProbe.ok &&
            report.device.protocol == Protocol.escPos;
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            DeviceInfoPanel(device: report.device),
            ChannelCard(
              label: 'ch1 ESC/POS probe',
              status: report.escPosProbe.status,
              elapsed: report.escPosProbe.elapsed,
              summary: report.escPosProbe.ok
                  ? 'protocol: ${report.escPosProbe.value?.protocol.name ?? '?'}'
                  : report.escPosProbe.error,
            ),
            ChannelCard(
              label: 'ch2 GS I',
              status: report.gsIdentity.status,
              elapsed: report.gsIdentity.elapsed,
              summary: report.gsIdentity.ok
                  ? '${report.gsIdentity.value?.manufacturer ?? '?'} / '
                      '${report.gsIdentity.value?.model ?? '?'}'
                  : report.gsIdentity.error,
            ),
            ChannelCard(
              label: 'ch3 PJL',
              status: report.pjl.status,
              elapsed: report.pjl.elapsed,
              summary: report.pjl.ok
                  ? report.pjl.value?.modelId ?? '(no model)'
                  : report.pjl.error,
            ),
            ChannelCard(
              label: 'ch4 IPP',
              status: report.ipp.status,
              elapsed: report.ipp.elapsed,
              summary: report.ipp.ok
                  ? report.ipp.value?.makeAndModel ?? '(no make/model)'
                  : report.ipp.error,
            ),
            ChannelCard(
              label: 'ch5 SNMP',
              status: report.snmp.status,
              elapsed: report.snmp.elapsed,
              summary: report.snmp.ok
                  ? report.snmp.value?.sysDescr ?? '(no sysDescr)'
                  : report.snmp.error,
            ),
            ChannelCard(
              label: 'ch6 HTTP',
              status: report.http.status,
              elapsed: report.http.elapsed,
              summary: report.http.ok
                  ? report.http.value?.title ?? '(no title)'
                  : report.http.error,
            ),
            ChannelCard(
              label: 'ch7 mDNS',
              status: report.mdns.status,
              elapsed: report.mdns.elapsed,
              summary: report.mdns.ok
                  ? report.mdns.value?.hostname ?? '(no hostname)'
                  : report.mdns.error,
            ),
            if (canPrint)
              Padding(
                padding: const EdgeInsets.all(12),
                child: ElevatedButton(
                  onPressed: () => _runPrintTest(_lastIp!),
                  child: const Text('Send test receipt'),
                ),
              ),
          ],
          ),
        );
      },
    );
  }
}
