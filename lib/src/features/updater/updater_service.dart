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

  static Future<GitHubRelease?> checkForUpdates() async {
    try {
      final response = await http.get(Uri.parse(_repoUrl));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final latestRelease = GitHubRelease.fromJson(json);

        final packageInfo = await PackageInfo.fromPlatform();
        final currentVersion = 'v${packageInfo.version}';

        // simple string compare; if the latest version is different from the current
        if (latestRelease.version != currentVersion) {
          return latestRelease;
        }
      }
    } catch (e) {
      // Failed to check for updates
    }
    return null;
  }
}
