import 'package:flutter/widgets.dart';

import '../services/supabase_service.dart';
import 'user_preferences.dart';

/// The signed-in person's display language, saved per account in
/// `users.preferences.language` ('English (PH)' or 'Filipino').
///
/// Shared widgets (menus, tabs, stat cards, badges, form labels) translate
/// through [tr]. Text with no entry in [_fil] simply stays in English.
class AppLocale extends ChangeNotifier {
  AppLocale._();
  static final instance = AppLocale._();

  static const english = 'English (PH)';
  static const filipino = 'Filipino';
  static const options = [english, filipino];

  String _language = english;
  String get language => _language;
  bool get isFilipino => _language == filipino;

  /// Loads the signed-in person's saved language. Call on every sign-in.
  Future<void> loadForCurrentUser() async {
    try {
      final prefs = await readMyPreferences();
      _apply((prefs['language'] as String?) ?? english);
    } catch (_) {
      _apply(english);
    }
  }

  /// Back to English on sign-out.
  void reset() => _apply(english);

  /// Switches language now and saves it on this account.
  Future<void> setLanguage(String language) async {
    _apply(language);
    final id = await SupabaseService.instance.getMyUserId();
    if (id is int) await patchMyPreferences(id, {'language': language});
  }

  void _apply(String language) {
    final next = options.contains(language) ? language : english;
    if (next == _language) return;
    _language = next;
    notifyListeners();
    // [tr] is not an InheritedWidget, so rebuild everything to show the change.
    final root = WidgetsBinding.instance.rootElement;
    if (root != null) {
      void visit(Element e) {
        e.markNeedsBuild();
        e.visitChildren(visit);
      }
      root.visitChildren(visit);
    }
  }
}

/// Translates [text] into the signed-in person's language. Untranslated text
/// comes back unchanged. ALL-CAPS headers match any case and return in caps.
String tr(String text) {
  if (!AppLocale.instance.isFilipino || text.isEmpty) return text;
  final hit = _fil[text];
  if (hit != null) return hit;
  final upper = text == text.toUpperCase() && text != text.toLowerCase();
  if (upper) {
    for (final e in _fil.entries) {
      if (e.key.toUpperCase() == text) return e.value.toUpperCase();
    }
  }
  return text;
}

/// English to Filipino text for the shared screens, in plain everyday Filipino.
const Map<String, String> _fil = {
  'Good morning': 'Magandang umaga',
  'Good afternoon': 'Magandang hapon',
  'Good evening': 'Magandang gabi',
  // --- menu sections ---
  'Overview': 'Pangkalahatan',
  'My Finances': 'Aking Pananalapi',
  'Community': 'Komunidad',
  'My Requests': 'Aking mga Kahilingan',
  'Account': 'Account',
  'Admin': 'Admin',
  'People': 'Mga Tao',
  'Requests & Services': 'Mga Kahilingan at Serbisyo',
  'Security & People': 'Seguridad at Mga Tao',

  // --- menu items / page titles ---
  'Dashboard': 'Dashboard',
  'Community Map': 'Mapa ng Komunidad',
  'Community Rules': 'Mga Patakaran ng Komunidad',
  'My Payments': 'Aking mga Bayarin',
  'How to Pay': 'Paano Magbayad',
  'Pay a Bill': 'Magbayad ng Bill',
  'My Complaints': 'Aking mga Reklamo',
  'My Permits': 'Aking mga Permit',
  'My Visitors': 'Aking mga Bisita',
  'My Vehicles': 'Aking mga Sasakyan',
  'My Violations': 'Aking mga Paglabag',
  'My Household': 'Aking Sambahayan',
  'My Files': 'Aking mga File',
  'My Profile': 'Aking Profile',
  'Profile': 'Profile',
  'Profile & Settings': 'Profile at Settings',
  'Settings': 'Settings',
  'Documents': 'Mga Dokumento',
  'Announcements': 'Mga Anunsyo',
  'Events': 'Mga Kaganapan',
  'Event': 'Kaganapan',
  'Announcements & Events': 'Mga Anunsyo at Kaganapan',
  'Waste Schedule': 'Iskedyul ng Basura',
  'Waste Collection Schedule': 'Iskedyul ng Pangongolekta ng Basura',
  'Reservations': 'Mga Reserbasyon',
  'Move In/Out': 'Paglipat Papasok/Palabas',
  'Move In / Out Requests': 'Mga Kahilingan sa Paglipat',
  'Move Requests': 'Mga Kahilingan sa Paglipat',
  'Pending Move Requests': 'Nakabinbing Paglipat',
  'Finance': 'Pananalapi',
  'Billing & Payments': 'Singil at Bayad',
  'Billing': 'Singil',
  'Payments': 'Mga Bayad',
  'Budget': 'Badyet',
  'Security': 'Seguridad',
  'Community Security': 'Seguridad ng Komunidad',
  'Security Incidents': 'Mga Insidente sa Seguridad',
  'Assigned to Me': 'Nakatalaga sa Akin',
  'Community Concern': 'Mga Hinaing ng Komunidad',
  'Complaints & Requests': 'Mga Reklamo at Kahilingan',
  'Permits': 'Mga Permit',
  'Vehicles': 'Mga Sasakyan',
  'Gate Passes': 'Mga Gate Pass',
  'All Accounts': 'Lahat ng Account',
  'Residents': 'Mga Residente',
  'Tenants': 'Mga Nangungupahan',
  'Visitors': 'Mga Bisita',
  'Visitor Management': 'Pamamahala ng Bisita',
  'Household Members': 'Mga Kasama sa Bahay',
  'Reports': 'Mga Ulat',
  'Reports & Analytics': 'Mga Ulat at Pagsusuri',
  'Audit Logs': 'Talaan ng Gawain',
  'Backup': 'Backup',
  'Backup & Restore': 'Backup at Pagbalik',
  'CMS': 'CMS',
  'User Approvals': 'Pag-apruba ng User',
  'Services': 'Mga Serbisyo',
  'Sign Out': 'Mag-sign Out',
  'Log Out': 'Mag-log Out',
  'Log out?': 'Mag-log out?',
  'You will need your email and password to log back in.':
      'Kakailanganin mo ang iyong email at password para makapag-log in muli.',

  // --- bottom tabs ---
  'Home': 'Home',
  'Pay': 'Bayad',
  'News': 'Balita',
  'Requests': 'Kahilingan',

  // --- stat cards ---
  'Outstanding': 'Hindi pa Bayad',
  'Paid this year': 'Nabayaran ngayong taon',
  'Next due': 'Susunod na Bayarin',
  'Open Requests': 'Bukas na Kahilingan',
  'Next Collection': 'Susunod na Koleksyon',
  'Upcoming Event': 'Paparating na Kaganapan',
  'Upcoming Events': 'Mga Paparating na Kaganapan',
  'Total': 'Kabuuan',
  'Total Accounts': 'Kabuuang Account',
  'Total Residents': 'Kabuuang Residente',
  'Total Tenants': 'Kabuuang Nangungupahan',
  'Total Billed': 'Kabuuang Siningil',
  'Total Budget': 'Kabuuang Badyet',
  'Total Events': 'Kabuuang Kaganapan',
  'Collected': 'Nakolekta',
  'Collections MTD': 'Nakolekta ngayong Buwan',
  'Collection Rate': 'Antas ng Koleksyon',
  'Overdue': 'Lampas na sa Takdang Petsa',
  'Overdue Accounts': 'Mga Account na Lampas na',
  'Overdue Accts': 'Lampas na',
  'Pending Bills': 'Nakabinbing Bayarin',
  'Open Complaints': 'Bukas na Reklamo',
  'Open Incidents': 'Bukas na Insidente',
  'Incidents': 'Mga Insidente',
  'Pending Approvals': 'Naghihintay ng Pag-apruba',
  'Active Announcements': 'Aktibong Anunsyo',
  'Visitors Today': 'Mga Bisita Ngayon',
  'Vehicles On-Site': 'Sasakyang Nasa Loob',
  'Registered Vehicles': 'Rehistradong Sasakyan',
  'Inside Now': 'Nasa Loob Ngayon',
  'Overstayed': 'Lumampas sa Oras',
  'Expected': 'Inaasahan',
  'Today': 'Ngayon',
  'Tomorrow': 'Bukas',
  'This Month': 'Ngayong Buwan',
  'Upcoming': 'Paparating',
  'Active Leases': 'Aktibong Upa',
  'Expiring Soon': 'Malapit nang Mag-expire',
  'Active Permits': 'Aktibong Permit',
  'Officers': 'Mga Opisyal',
  'Residents + Tenants': 'Residente + Nangungupahan',
  'Repeat Offenders': 'Paulit-ulit na Lumalabag',
  'Critical': 'Kritikal',
  'Warnings': 'Mga Babala',
  'Budget Used': 'Nagamit na Badyet',
  'Budget Utilization': 'Paggamit ng Badyet',
  'Spent': 'Nagastos',
  'Remaining': 'Natitira',
  'Variance': 'Pagkakaiba',
  'View': 'Tingnan',
  'View →': 'Tingnan →',
  'Show all': 'Ipakita lahat',
  'Show these': 'Ipakita ang mga ito',
  'Showing · tap to clear': 'Ipinapakita · pindutin para alisin',
  'Tap to clear': 'Pindutin para alisin',

  // --- statuses (StatusBadge) ---
  'Pending': 'Nakabinbin',
  'Submitted': 'Naisumite',
  'Under Review': 'Sinusuri',
  'In Progress': 'Isinasagawa',
  'Resolved': 'Nalutas',
  'Dismissed': 'Ibinasura',
  'Approved': 'Aprubado',
  'Rejected': 'Tinanggihan',
  'Cancelled': 'Kinansela',
  'Completed': 'Natapos',
  'Scheduled': 'Nakaiskedyul',
  'Expired': 'Nag-expire',
  'Used': 'Nagamit na',
  'Paid': 'Bayad na',
  'Partial': 'Bahagyang Bayad',
  'Waived': 'Pinatawad',
  'Verified': 'Beripikado',
  'Refunded': 'Ibinalik',
  'Active': 'Aktibo',
  'Inactive': 'Hindi Aktibo',
  'Suspended': 'Suspendido',
  'Pending Verification': 'Naghihintay ng Beripikasyon',
  'Registered': 'Rehistrado',
  'Flagged': 'Minarkahan',
  'Sold': 'Naibenta',
  'Open': 'Bukas',
  'Investigating': 'Iniimbestigahan',
  'Closed': 'Sarado',
  'Escalated': 'Iniakyat',
  'Draft': 'Draft',
  'Reported': 'Naiulat',
  'Noticed': 'Napansin',
  'Contested': 'Kinontra',
  'Upheld': 'Pinagtibay',
  'Penalty Imposed': 'May Multa',
  'Published': 'Nailathala',
  'Ongoing': 'Kasalukuyan',

  // --- shared form ---
  'Save': 'I-save',
  'Cancel': 'Kanselahin',
  'Close': 'Isara',
  'Edit': 'I-edit',
  'Delete': 'Burahin',
  'Saving…': 'Sine-save…',
  'New': 'Bagong',
  'Name': 'Pangalan',
  'First Name': 'Pangalan',
  'Last Name': 'Apelyido',
  'Full Name': 'Buong Pangalan',
  'Email': 'Email',
  'Phone': 'Telepono',
  'Contact Number': 'Numero ng Telepono',
  'Address': 'Address',
  'Lot': 'Lote',
  'Status': 'Katayuan',
  'Category': 'Kategorya',
  'Priority': 'Prayoridad',
  'Severity': 'Kalubhaan',
  'Title': 'Pamagat',
  'Subject': 'Paksa',
  'Description': 'Paglalarawan',
  'Details': 'Mga Detalye',
  'Notes': 'Mga Tala',
  'Location': 'Lokasyon',
  'Date': 'Petsa',
  'Start Date': 'Petsa ng Simula',
  'End Date': 'Petsa ng Pagtatapos',
  'Due Date': 'Takdang Petsa',
  'Amount': 'Halaga',
  'Purpose': 'Layunin',
  'Visitor Name': 'Pangalan ng Bisita',
  'Relationship': 'Kaugnayan',
  'Permit Type': 'Uri ng Permit',
  'Applicant': 'Aplikante',
  'Resident': 'Residente',
  'Owner': 'May-ari',
  'Plate Number': 'Numero ng Plaka',
  'Make': 'Tatak',
  'Model': 'Modelo',
  'Color': 'Kulay',
  'Year': 'Taon',
  'Resolution': 'Resolusyon',
  'Assigned To': 'Nakatalaga Kay',
  'Reference #': 'Reference #',
  'Type': 'Uri',
  'Venue': 'Lugar',
  'Content': 'Nilalaman',
  'Pinned': 'Naka-pin',
  'Public': 'Pampubliko',
  'All phases': 'Lahat ng Phase',
  'Photo': 'Larawan',
  'Evidence': 'Ebidensya',

  // --- My Payments / dashboard / settings ---
  'My Bills': 'Aking mga Bill',
  'Payment History': 'Kasaysayan ng Bayad',
  'Send Proof': 'Magpadala ng Patunay',
  'Quick actions': 'Mabilisang aksyon',
  'Pay My Bill': 'Bayaran ang Bill',
  'File a Complaint': 'Mag-file ng Reklamo',
  'Register a Visitor': 'Magrehistro ng Bisita',
  'New Gate Pass': 'Bagong Gate Pass',
  'Request Gate Pass': 'Humiling ng Gate Pass',
  'Apply for Permit': 'Mag-apply ng Permit',
  'Register Household Member': 'Magrehistro ng Kasama sa Bahay',
  'Recent Announcements': 'Mga Bagong Anunsyo',
  'Notification Preferences': 'Mga Kagustuhan sa Abiso',
  'Preferences': 'Mga Kagustuhan',
  'Language': 'Wika',
  'Time Zone': 'Time Zone',
  'Save Settings': 'I-save ang Settings',
  'Replay': 'Ulitin',
  'Replay the tutorial': 'Ulitin ang tutorial',
  'Email notifications': 'Abiso sa email',
  'Push notifications': 'Push na abiso',
  'Billing & dues reminders': 'Paalala sa bayarin at dues',
  'Announcement alerts': 'Alerto sa anunsyo',
  'Manage 2FA': 'Pamahalaan ang 2FA',
  'Welcome back': 'Maligayang pagbabalik',
  'My Balance': 'Aking Balanse',
  'Lease': 'Upa',
  'Only changes the language for your account.':
      'Para lang sa account mo ang pagbabago ng wika.',
};
