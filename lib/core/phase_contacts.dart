/// Each phase's own office contact details and social pages.
/// Read through the `phase_contacts()` RPC (visitors cannot select `phases`)
/// and saved through `set_phase_contact()`.
library;

import '../services/supabase_service.dart';
import 'social_link.dart';

/// One phase's contact details.
class PhaseContact {
  final String number;
  final String address;
  final String hours;
  final String phone;
  final String email;
  final String mapLink;
  final List<SocialLink> socialLinks;

  const PhaseContact({
    required this.number,
    this.address = '',
    this.hours = '',
    this.phone = '',
    this.email = '',
    this.mapLink = '',
    this.socialLinks = const [],
  });

  /// True when the phase has set any detail of its own.
  /// Phases with none are not shown on the landing page.
  bool get hasAnything =>
      [address, hours, phone, email, mapLink].any((v) => v.trim().isNotEmpty) ||
      socialLinks.isNotEmpty;

  factory PhaseContact.fromRow(Map<String, dynamic> r) {
    String s(String k) => (r[k] ?? '').toString();
    final raw = r['social_links'];
    List<SocialLink> links = const [];
    if (raw is List) {
      links = [
        for (final e in raw)
          if (e is Map && (e['url'] ?? '').toString().isNotEmpty)
            SocialLink(
                platform: (e['platform'] ?? 'website').toString(),
                url: e['url'].toString()),
      ];
    }
    return PhaseContact(
      number: s('number'),
      address: s('address'),
      hours: s('hours'),
      phone: s('phone'),
      email: s('email'),
      mapLink: s('map_link'),
      socialLinks: links,
    );
  }
}

/// Every active phase's contact details, keyed by phase number.
Future<Map<String, PhaseContact>> loadPhaseContacts() async {
  final rows =
      await SupabaseService.instance.client.rpc('phase_contacts') as List;
  return {
    for (final r in rows)
      (r['number'] ?? '').toString():
          PhaseContact.fromRow(Map<String, dynamic>.from(r as Map)),
  };
}

/// Saves one phase's contact details and social links together. The
/// database refuses a phase officer editing any phase but their own.
Future<void> savePhaseContact(PhaseContact c) async {
  await SupabaseService.instance.client.rpc('set_phase_contact', params: {
    'p_number': c.number,
    'p_address': c.address,
    'p_hours': c.hours,
    'p_phone': c.phone,
    'p_email': c.email,
    'p_map_link': c.mapLink,
    'p_social_links': [for (final l in c.socialLinks) l.toJson()],
  });
}
