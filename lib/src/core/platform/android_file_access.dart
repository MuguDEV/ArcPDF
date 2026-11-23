import 'dart:io';

import 'package:flutter/services.dart';

class AndroidFileAccess {
  const AndroidFileAccess._();

  static const _channel = MethodChannel('com.arcpdf.app/file_access');

  /// Returns null on Android 10 and earlier, where legacy runtime permission
  /// handling remains authoritative.
  static Future<bool?> status() async {
    if (!Platform.isAndroid) return true;
    return _channel.invokeMethod<bool>('status');
  }

  /// Opens ArcPDF's dedicated All files access settings and resolves only
  /// after the user returns. Returns null for legacy Android versions.
  static Future<bool?> request() async {
    if (!Platform.isAndroid) return true;
    return _channel.invokeMethod<bool>('request');
  }
}
