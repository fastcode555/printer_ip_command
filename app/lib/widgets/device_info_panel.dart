import 'package:flutter/material.dart';
import 'package:printer_ip_command/printer_ip_command.dart';

class DeviceInfoPanel extends StatelessWidget {
  final DeviceInfo device;
  final VoidCallback? onCopy;

  const DeviceInfoPanel({super.key, required this.device, this.onCopy});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Device',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                if (onCopy != null)
                  IconButton(
                    icon: const Icon(Icons.copy_outlined, size: 20),
                    tooltip: '复制完整报告',
                    onPressed: onCopy,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            _row('host', device.host),
            _row('protocol', _enumName(device.protocol)),
            _row('vendor', device.vendor),
            _row('model', device.model),
            _row('firmware', device.firmware),
            _row('serial', device.serial),
            _row('mDNS hostname', device.mdnsHostname),
            _row('language', device.language),
            _row('Chinese ROM', _chineseRomText(classifyLanguage(device.language))),
            if (device.documentFormats.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: device.documentFormats
                      .map((f) => Chip(label: Text(f, style: const TextStyle(fontSize: 11))))
                      .toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: const TextStyle(color: Colors.grey)),
          ),
          Expanded(child: Text(value ?? '—')),
        ],
      ),
    );
  }

  String _enumName(Protocol p) => p.toString().split('.').last;

  String _chineseRomText(ChineseRom rom) {
    return switch (rom) {
      ChineseRom.traditional => '繁体 (Big5)',
      ChineseRom.simplified => '简体 (GBK)',
      ChineseRom.unknown => '未知',
    };
  }
}
