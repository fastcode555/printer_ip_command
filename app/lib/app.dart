import 'package:flutter/material.dart';

import 'pages/diagnose_page.dart';
import 'services/printer_service.dart';

class PrinterIpApp extends StatelessWidget {
  const PrinterIpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'printer_ip diagnose',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: DiagnosePage(service: PrinterService()),
    );
  }
}
