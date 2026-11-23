import 'dart:io';

import 'package:flutter/services.dart';

class InterruptedJob {
  const InterruptedJob({
    required this.jobId,
    required this.title,
    required this.stage,
    this.outputPath,
  });

  final String jobId;
  final String title;
  final String stage;
  final String? outputPath;
}

class AndroidJobService {
  const AndroidJobService._();

  static const _channel = MethodChannel('com.arcpdf.app/job_service');

  static Future<void> start({
    required String jobId,
    required String title,
    required String stage,
    String? outputPath,
  }) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('start', {
      'jobId': jobId,
      'title': title,
      'stage': stage,
      'outputPath': outputPath,
    });
  }

  static Future<void> update({
    required String stage,
    double? progress,
  }) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('update', {
      'stage': stage,
      'progress': progress == null ? null : (progress * 100).round(),
    });
  }

  static Future<void> finish() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('finish');
  }

  static Future<InterruptedJob?> recover() async {
    if (!Platform.isAndroid) return null;
    final value = await _channel.invokeMapMethod<String, dynamic>('recover');
    if (value == null) return null;
    return InterruptedJob(
      jobId: value['jobId'] as String? ?? '',
      title: value['title'] as String? ?? 'PDF operation',
      stage: value['stage'] as String? ?? 'Interrupted',
      outputPath: value['outputPath'] as String?,
    );
  }

  static Future<void> clearRecovery() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('clearRecovery');
  }
}
