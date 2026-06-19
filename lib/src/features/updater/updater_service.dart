import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class GitHubRelease {
  final String version;
  final String body;
  final String url;

  GitHubRelease({required this.version, required this.body, required this.url});

  factory GitHubRelease.fromJson(Map<String, dynamic> json) {
    return GitHubRelease(
      version: json['tag_name'] as String,
      body: (json['body'] as String?) ?? 'No changelog provided.',
      url: json['html_url'] as String,
    );
  }
}

class UpdaterService {
  static const String _repoUrl = 'https://api.github.com/repos/MuguDEV/ArcPDF/releases/latest';

  static bool _isNewerVersion(String latest, String current) {
    try {
      final latestParts = latest.split('.').map(int.parse).toList();
      final currentParts = current.split('.').map(int.parse).toList();

      for (int i = 0; i < latestParts.length && i < currentParts.length; i++) {
        if (latestParts[i] > currentParts[i]) return true;
        if (latestParts[i] < currentParts[i]) return false;
      }
      return latestParts.length > currentParts.length;
    } catch (e) {
      return latest != current;
    }
  }

  static Future<GitHubRelease?> checkForUpdates() async {
    try {
      final response = await http.get(Uri.parse(_repoUrl));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final latestRelease = GitHubRelease.fromJson(json);

        final packageInfo = await PackageInfo.fromPlatform();

        // Also strip leading 'v' to handle comparisons like 'v1.0.17' vs '1.0.18' just in case.
        final cleanLatest = latestRelease.version.replaceAll('v', '');
        final cleanCurrent = packageInfo.version;

        if (_isNewerVersion(cleanLatest, cleanCurrent)) {
          return latestRelease;
        }
      }
    } catch (e) {
      // Failed to check for updates
    }
    return null;
  }
}
