import 'package:flutter/material.dart';
import 'package:printer_ip_command/printer_ip_command.dart';

/// Shows the encoding-selector dialog and returns the chosen encoding
/// (or null if cancelled).
Future<ReceiptEncoding?> showPrintTestDialog(BuildContext context) {
  return showDialog<ReceiptEncoding>(
    context: context,
    builder: (_) => const _PrintTestDialog(),
  );
}

class _PrintTestDialog extends StatefulWidget {
  const _PrintTestDialog();

  @override
  State<_PrintTestDialog> createState() => _PrintTestDialogState();
}

class _PrintTestDialogState extends State<_PrintTestDialog> {
  ReceiptEncoding _selected = ReceiptEncoding.big5;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Send test receipt'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Encoding (must match printer ROM):'),
          const SizedBox(height: 8),
          RadioListTile<ReceiptEncoding>(
            title: const Text('Big5'),
            subtitle: const Text('Traditional Chinese — HK/TW market'),
            value: ReceiptEncoding.big5,
            groupValue: _selected,
            onChanged: (v) => setState(() => _selected = v!),
          ),
          RadioListTile<ReceiptEncoding>(
            title: const Text('GBK'),
            subtitle: const Text('Simplified Chinese — mainland market'),
            value: ReceiptEncoding.gbk,
            groupValue: _selected,
            onChanged: (v) => setState(() => _selected = v!),
          ),
          RadioListTile<ReceiptEncoding>(
            title: const Text('ASCII'),
            subtitle: const Text('No Chinese — works on any printer'),
            value: ReceiptEncoding.ascii,
            groupValue: _selected,
            onChanged: (v) => setState(() => _selected = v!),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_selected),
          child: const Text('Send'),
        ),
      ],
    );
  }
}
