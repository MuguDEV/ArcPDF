import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../pdf/domain/pdf_file_item.dart';
import '../pdf/viewer/pdf_viewer_screen.dart';

import '../navigation/navigation_controller.dart';

final intentServiceProvider = Provider<IntentService>((ref) {
  final service = IntentService(ref);

  ref.listen<bool>(splashDoneProvider, (prev, isDone) {
    if (isDone && !service.splashCompleter.isCompleted) {
      service.splashCompleter.complete();
    }
  });

  return service;
});

class IntentService {
  final Ref ref;
  StreamSubscription? _intentDataStreamSubscription;
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  final Completer<void> splashCompleter = Completer<void>();

  IntentService(this.ref) {
    if (ref.read(splashDoneProvider)) {
      splashCompleter.complete();
    }
  }

  void init() {
    // For sharing or opening files while the app is already running
    _intentDataStreamSubscription = ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> value) {
      _handleSharedFiles(value);
    }, onError: (err) {
      debugPrint("getMediaStream error: $err");
    });

    // For sharing or opening files when the app is closed
    ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
      _handleSharedFiles(value);
      if (value.isNotEmpty) {
        ReceiveSharingIntent.instance.reset(); // clear initial intent
      }
    });
  }

  void _handleSharedFiles(List<SharedMediaFile> files) {
    if (files.isEmpty) return;
    _waitForContextAndNavigate(files);
  }

  Future<void> _waitForContextAndNavigate(List<SharedMediaFile> files) async {
    // Wait for the splash screen to finish
    await splashCompleter.future;

    // Small delay to ensure the Navigator is fully mounted after splash updates
    await Future.delayed(const Duration(milliseconds: 100));

    final context = navigatorKey.currentContext;
    if (context != null && context.mounted) {
      // Find the first valid PDF to avoid multiple synchronous pushes
      for (final file in files) {
        if (file.path.toLowerCase().endsWith('.pdf')) {
          final pdfItem = PdfFileItem.fromFile(File(file.path));

          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => PdfViewerScreen(item: pdfItem),
            ),
          );
          break; // Stop after first PDF to prevent jank and multiple page routes
        }
      }
    } else {
      debugPrint("Failed to find Navigator context after splash.");
    }
  }

  void dispose() {
    _intentDataStreamSubscription?.cancel();
  }
}
