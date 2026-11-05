import 'dart:convert';
import 'package:flutter/material.dart';

/// One social account shown on the landing page.
/// Stored in the `homepage.social_links` JSON array.
class SocialLink {
  /// One of [platforms]. An unknown value still shows, with a generic icon.
  final String platform;
  final String url;

  const SocialLink({required this.platform, required this.url});

  /// The platforms offered in the picker, in the order shown.
  static const platforms = <String, String>{
    'facebook': 'Facebook',
    'messenger': 'Messenger',
    'viber': 'Viber',
    'instagram': 'Instagram',
    'tiktok': 'TikTok',
    'youtube': 'YouTube',
    'x': 'X (Twitter)',
    'website': 'Website',
  };

  String get label => platforms[platform] ?? platform;

  IconData get icon {
    switch (platform) {
      case 'facebook':
      case 'messenger':
        return Icons.facebook;
      case 'viber':
      case 'x':
        return Icons.chat_bubble_outline;
      case 'instagram':
        return Icons.camera_alt_outlined;
      case 'tiktok':
        return Icons.music_note_outlined;
      case 'youtube':
        return Icons.play_circle_outline;
      default:
        return Icons.link;
    }
  }

  Map<String, dynamic> toJson() => {'platform': platform, 'url': url};

  /// Reads the stored JSON. Bad or empty data gives an empty list, never an
  /// error, so the public landing page cannot break.
  static List<SocialLink> decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! List) return const [];
      return [
        for (final e in parsed)
          if (e is Map &&
              (e['url'] ?? '').toString().trim().isNotEmpty)
            SocialLink(
              platform: (e['platform'] ?? 'website').toString().trim(),
              url: (e['url']).toString().trim(),
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  static String encode(List<SocialLink> links) =>
      jsonEncode([for (final l in links) l.toJson()]);

  /// Cleans a pasted link, adding https:// if missing. Returns null if it is
  /// not a valid address. A link without a scheme would open on our own site.
  static String? normalize(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final withScheme =
        s.startsWith('http://') || s.startsWith('https://') ? s : 'https://$s';
    final uri = Uri.tryParse(withScheme);
    if (uri == null || uri.host.isEmpty || !uri.host.contains('.')) return null;
    return withScheme;
  }
}
