import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

final updaterHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

enum UpdateCheckStatus { updateAvailable, upToDate, unavailable, failure }

class UpdateCheckResult {
  const UpdateCheckResult(this.status, {this.release});

  final UpdateCheckStatus status;
  final GitHubRelease? release;
}

class GitHubReleaseAsset {
  const GitHubReleaseAsset({required this.name, required this.url, this.size});

  final String name;
  final String url;
  final int? size;
}

class GitHubRelease {
  final String version;
  final String body;
  final String url;
  final List<GitHubReleaseAsset> assets;

  GitHubRelease({
    required this.version,
    required this.body,
    required this.url,
    this.assets = const [],
  });

  factory GitHubRelease.fromJson(Map<String, dynamic> json) {
    return GitHubRelease(
      version: json['tag_name'] as String,
      body: (json['body'] as String?) ?? 'No changelog provided.',
      url: json['html_url'] as String,
      assets: [
        for (final asset in (json['assets'] as List? ?? const []))
          GitHubReleaseAsset(
            name: asset['name'] as String,
            url: asset['browser_download_url'] as String,
            size: asset['size'] as int?,
          ),
      ],
    );
  }
}

class UpdaterService {
  static const String _repoUrl =
      'https://api.github.com/repos/MuguDEV/ArcPDF/releases/latest';
  static const requestTimeout = Duration(seconds: 15);
  static const downloadTimeout = Duration(minutes: 2);

  static bool _isNewerVersion(String latest, String current) {
    final latestVersion = _Version.tryParse(latest);
    final currentVersion = _Version.tryParse(current);
    return latestVersion != null &&
        currentVersion != null &&
        latestVersion.compareTo(currentVersion) > 0;
  }

  /// Compatibility API: callers needing error feedback should use
  /// [checkForUpdateResult] instead of treating null as "up to date".
  static Future<GitHubRelease?> checkForUpdates({
    http.Client? client,
    String? currentVersion,
    Duration timeout = requestTimeout,
  }) async {
    return (await checkForUpdateResult(
      client: client,
      currentVersion: currentVersion,
      timeout: timeout,
    ))
        .release;
  }

  static Future<UpdateCheckResult> checkForUpdateResult({
    http.Client? client,
    String? currentVersion,
    Duration timeout = requestTimeout,
  }) async {
    http.Client? connection = client;
    try {
      connection ??= http.Client();
      final response =
          await connection.get(Uri.parse(_repoUrl)).timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        return const UpdateCheckResult(UpdateCheckStatus.unavailable);
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['draft'] == true) {
        return const UpdateCheckResult(UpdateCheckStatus.unavailable);
      }
      final release = GitHubRelease.fromJson(json);
      _httpsUri(release.url);
      final installed = currentVersion ??
          (await PackageInfo.fromPlatform().timeout(timeout)).version;
      if (_Version.tryParse(release.version) == null ||
          _Version.tryParse(installed) == null) {
        return const UpdateCheckResult(UpdateCheckStatus.failure);
      }
      if (_isNewerVersion(release.version, installed)) {
        return UpdateCheckResult(UpdateCheckStatus.updateAvailable,
            release: release);
      }
      return const UpdateCheckResult(UpdateCheckStatus.upToDate);
    } on TimeoutException {
      return const UpdateCheckResult(UpdateCheckStatus.unavailable);
    } on SocketException {
      return const UpdateCheckResult(UpdateCheckStatus.unavailable);
    } on http.ClientException {
      return const UpdateCheckResult(UpdateCheckStatus.unavailable);
    } catch (_) {
      return const UpdateCheckResult(UpdateCheckStatus.failure);
    } finally {
      if (client == null) connection?.close();
    }
  }

  /// Downloads the APK belonging to the advertised release, not a newly
  /// fetched "latest" release that might have changed since the check.
  static Future<File> downloadUpdate(
    GitHubRelease release, {
    http.Client? client,
    Directory? directory,
    Duration timeout = downloadTimeout,
  }) async {
    http.Client? connection = client;
    Directory? staging;
    try {
      connection ??= http.Client();
      final apks = release.assets
          .where((asset) => asset.name.toLowerCase().endsWith('.apk'))
          .toList();
      if (apks.isEmpty) throw const FormatException('No APK in this release');
      final asset = apks.firstWhere((asset) {
        final name = asset.name.toLowerCase();
        return name.contains('universal') ||
            (!name.contains('arm') && !name.contains('x86'));
      }, orElse: () => apks.first);
      final response =
          await connection.get(_httpsUri(asset.url)).timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('APK download failed (${response.statusCode})');
      }
      final bytes = response.bodyBytes;
      if (bytes.length < 4 ||
          bytes[0] != 0x50 ||
          bytes[1] != 0x4b ||
          bytes[2] != 0x03 ||
          bytes[3] != 0x04) {
        throw const FormatException('Downloaded file is not an APK archive');
      }
      if (asset.size != null && bytes.length != asset.size) {
        throw const FormatException('APK download is incomplete');
      }
      final root = directory ?? await getTemporaryDirectory();
      staging = await root.createTemp('arcpdf_update_');
      final partial = File(p.join(staging.path, 'ArcPDF_Update.apk.part'));
      await partial.writeAsBytes(bytes, flush: true);
      return await partial.rename(p.join(staging.path, 'ArcPDF_Update.apk'));
    } catch (_) {
      if (staging != null) {
        try {
          await staging.delete(recursive: true);
        } on FileSystemException {
          // Preserve the download error if temporary cleanup also fails.
        }
      }
      rethrow;
    } finally {
      if (client == null) connection?.close();
    }
  }

  static Uri _httpsUri(String value) {
    final uri = Uri.parse(value);
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw const FormatException('Expected an HTTPS release URL');
    }
    return uri;
  }
}

/// SemVer precedence, accepting common v/V prefixes and omitted minor/patch
/// components. Build metadata never changes precedence.
class _Version implements Comparable<_Version> {
  _Version(this.core, this.prerelease);
  final List<BigInt> core;
  final List<String> prerelease;

  static _Version? tryParse(String text) {
    final match = RegExp(
      r'^[vV]?(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$',
    ).firstMatch(text.trim());
    if (match == null) return null;
    final parts = [match[1]!, match[2] ?? '0', match[3] ?? '0'];
    final prerelease = match[4]?.split('.') ?? <String>[];
    bool leadingZero(String part) => part.length > 1 && part.startsWith('0');
    if (parts.any(leadingZero) ||
        prerelease.any(
            (part) => RegExp(r'^\d+$').hasMatch(part) && leadingZero(part))) {
      return null;
    }
    return _Version(parts.map(BigInt.parse).toList(), prerelease);
  }

  @override
  int compareTo(_Version other) {
    for (var i = 0; i < 3; i++) {
      final comparison = core[i].compareTo(other.core[i]);
      if (comparison != 0) return comparison;
    }
    if (prerelease.isEmpty || other.prerelease.isEmpty) {
      if (prerelease.isEmpty && other.prerelease.isEmpty) return 0;
      return prerelease.isEmpty ? 1 : -1;
    }
    for (var i = 0; i < prerelease.length && i < other.prerelease.length; i++) {
      final left = prerelease[i];
      final right = other.prerelease[i];
      final leftNumber =
          RegExp(r'^\d+$').hasMatch(left) ? BigInt.parse(left) : null;
      final rightNumber =
          RegExp(r'^\d+$').hasMatch(right) ? BigInt.parse(right) : null;
      final int comparison;
      if (leftNumber != null && rightNumber != null) {
        comparison = leftNumber.compareTo(rightNumber);
      } else if (leftNumber != null || rightNumber != null) {
        comparison = leftNumber != null ? -1 : 1;
      } else {
        comparison = left.compareTo(right);
      }
      if (comparison != 0) return comparison;
    }
    return prerelease.length.compareTo(other.prerelease.length);
  }
}
