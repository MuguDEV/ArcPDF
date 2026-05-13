import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../pdf/domain/pdf_file_item.dart';
import '../pdf/viewer/pdf_viewer_screen.dart';

final intentServiceProvider = Provider<IntentService>((ref) => IntentService());

class IntentService {
  StreamSubscription? _intentDataStreamSubscription;
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

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

    for (final file in files) {
      if (file.path.toLowerCase().endsWith('.pdf')) {
        final pdfItem = PdfFileItem.fromFile(File(file.path));

        final context = navigatorKey.currentContext;
        if (context != null) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => PdfViewerScreen(item: pdfItem),
            ),
          );
        }
      }
    }
  }

  void dispose() {
    _intentDataStreamSubscription?.cancel();
  }
}
