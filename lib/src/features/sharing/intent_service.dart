import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../pdf/domain/pdf_file_item.dart';
import '../pdf/viewer/pdf_viewer_screen.dart';

import '../navigation/navigation_controller.dart';

final intentServiceProvider = Provider<IntentService>((ref) => IntentService(ref));

class IntentService {
  final Ref ref;
  StreamSubscription? _intentDataStreamSubscription;
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  IntentService(this.ref);

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
      ReceiveSharingIntent.instance.reset(); // clear initial intent
    });
  }

  void _handleSharedFiles(List<SharedMediaFile> files) {
    if (files.isEmpty) return;

    _waitForContextAndNavigate(files);
  }

  Future<void> _waitForContextAndNavigate(List<SharedMediaFile> files, {int maxRetries = 50}) async {
    for (int i = 0; i < maxRetries; i++) {
      final isSplashDone = ref.read(splashDoneProvider);
      final context = navigatorKey.currentContext;

      if (isSplashDone && context != null && context.mounted) {
        for (final file in files) {
          if (file.path.toLowerCase().endsWith('.pdf')) {
            final pdfItem = PdfFileItem.fromFile(File(file.path));

            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => PdfViewerScreen(item: pdfItem),
              ),
            );
          }
        }
        return; // Successfully navigated
      }
      // Wait a short duration before checking again
      await Future.delayed(const Duration(milliseconds: 100));
    }
    debugPrint("Failed to find Navigator context after waiting.");
  }

  void dispose() {
    _intentDataStreamSubscription?.cancel();
  }
}
