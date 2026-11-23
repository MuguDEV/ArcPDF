import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app.dart';
import 'src/bootstrap.dart';
import 'src/core/utils/app_diagnostics.dart';
import 'src/shared/widgets/arc_pdf_mark.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppDiagnostics.instance.install();

  // Edge to Edge immersive look
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );

  // Draw a Flutter frame immediately. Waiting for storage/PDF initialization
  // before runApp leaves Android's native launch logo on screen forever when
  // a device has a slow or incompatible local database.
  runApp(const _BootstrapGate());
}

class _BootstrapGate extends StatefulWidget {
  const _BootstrapGate();

  @override
  State<_BootstrapGate> createState() => _BootstrapGateState();
}

class _BootstrapGateState extends State<_BootstrapGate> {
  late Future<void> _startup;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _startup = bootstrap();
  }

  void _retry() {
    setState(_start);
  }

  void _repairMetadata() {
    setState(() => _startup = bootstrap(repairMetadata: true));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _startup,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            !snapshot.hasError) {
          return ProviderScope(
            observers: [AppLogProviderObserver()],
            child: const ArcPdfApp(),
          );
        }
        if (snapshot.hasError) {
          final canRepair = snapshot.error is MetadataRepairRequired;
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.black),
            darkTheme: ThemeData(
              useMaterial3: true,
              brightness: Brightness.dark,
              colorSchemeSeed: Colors.white,
            ),
            home: Builder(
              builder: (screenContext) => Scaffold(
                body: SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const ArcPdfMark(size: 72),
                            const SizedBox(height: 24),
                            Text('ArcPDF couldn’t start',
                                textAlign: TextAlign.center,
                                style: Theme.of(screenContext)
                                    .textTheme
                                    .headlineSmall),
                            const SizedBox(height: 12),
                            Text(
                              'ArcPDF could not open its local app data. Your PDF files were not changed.',
                              textAlign: TextAlign.center,
                              style:
                                  Theme.of(screenContext).textTheme.bodyLarge,
                            ),
                            const SizedBox(height: 24),
                            FilledButton.icon(
                              onPressed: _retry,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Try again'),
                            ),
                            if (canRepair) ...[
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: _repairMetadata,
                                icon: const Icon(Icons.build_outlined),
                                label: const Text('Repair local app data'),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Repair may reset damaged ArcPDF settings, history, or annotations. Your PDF files will not be deleted.',
                                textAlign: TextAlign.center,
                                style:
                                    Theme.of(screenContext).textTheme.bodySmall,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.black),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorSchemeSeed: Colors.white,
          ),
          home: Scaffold(
            body: Center(
              child: Semantics(
                liveRegion: true,
                label: 'Starting ArcPDF',
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ArcPdfMark(size: 88),
                    SizedBox(height: 24),
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Starting ArcPDF…'),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
