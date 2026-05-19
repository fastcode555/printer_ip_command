import 'package:flutter/material.dart';
import 'package:printer_ip_command/printer_ip_command.dart';

class DeviceInfoPanel extends StatelessWidget {
  final DeviceInfo device;

  const DeviceInfoPanel({super.key, required this.device});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Device',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            _row('host', device.host),
            _row('protocol', _enumName(device.protocol)),
            _row('vendor', device.vendor),
            _row('model', device.model),
            _row('firmware', device.firmware),
            _row('serial', device.serial),
            _row('mDNS hostname', device.mdnsHostname),
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
}
