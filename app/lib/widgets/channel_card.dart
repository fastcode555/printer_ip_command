import 'package:flutter/material.dart';
import 'package:printer_ip_command/printer_ip_command.dart';

class ChannelCard extends StatelessWidget {
  final String label;
  final ChannelStatus status;
  final Duration elapsed;
  final String summary;

  const ChannelCard({
    super.key,
    required this.label,
    required this.status,
    required this.elapsed,
    required this.summary,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _statusIcon(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(label,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text('${elapsed.inMilliseconds} ms',
                          style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(summary,
                      style: const TextStyle(fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusIcon() {
    switch (status) {
      case ChannelStatus.success:
        return const Icon(Icons.check_circle, color: Colors.green);
      case ChannelStatus.failed:
        return const Icon(Icons.cancel, color: Colors.red);
      case ChannelStatus.skipped:
        return const Icon(Icons.remove_circle_outline, color: Colors.grey);
    }
  }
}
