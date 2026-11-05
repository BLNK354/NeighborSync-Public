import '../services/supabase_service.dart';

/// Folders in My Files.
///
/// A file's folder is `documents.category`. Built-in folders are fixed here;
/// folders people make are in `personal_folders` with a `shared` flag.
///
/// Residents' built-in folders are visible to the HOA office. A folder the
/// resident makes is private unless shared; its files are stored `is_private`
/// and officers cannot read them. An officer's own drive is always private.

/// Where proof-of-ownership uploads from Profile are filed.
const kProofFolder = 'Proof of Ownership';

/// Built-in folders for residents and tenants.
const kResidentBuiltInFolders = <String>[
  'Permit',
  'Government ID',
  'Contract / Lease',
  'Payment Proof',
  kProofFolder,
  'Receipt',
  'Insurance',
  'Other',
];

/// Built-in folders for officers.
const kOfficerBuiltInFolders = <String>[
  'Personal',
  'Work',
  'Government ID',
  'Contract',
  'Receipt',
  'Other',
];

/// Kinds of proof of ownership (key to label). One file per kind.
const kProofTypes = <String, String>{
  'title': 'Land title / TCT',
  'tax_declaration': 'Tax declaration',
  'deed_of_sale': 'Deed of sale',
  'lease_contract': 'Lease contract (tenants)',
  'utility_bill': 'Utility bill in my name',
  'other': 'Other supporting document',
};

int _byName(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());

/// Folders [ownerId] made, oldest first. Under RLS an officer only gets
/// the ones the owner shared.
Future<List<Map<String, dynamic>>> loadPersonalFolders(int ownerId) async {
  final rows = await SupabaseService.instance.client
      .from('personal_folders')
      .select('id, name, shared, created_at')
      .eq('owner_id', ownerId)
      .order('created_at');
  return List<Map<String, dynamic>>.from(rows as List);
}

/// What the office may file into for a household: the built-in folders
/// plus any the household shared, A-Z.
Future<List<String>> sharedFoldersFor(int ownerId) async {
  final names = <String>{...kResidentBuiltInFolders};
  try {
    for (final f in await loadPersonalFolders(ownerId)) {
      if (f['shared'] == true) names.add((f['name'] ?? '').toString().trim());
    }
  } catch (_) {
    // On failure the built-in folders are still offered.
  }
  names.removeWhere((n) => n.isEmpty);
  return names.toList()..sort(_byName);
}

/// Built-ins in their usual order, then the person's own folders A-Z.
List<String> folderOrder(List<String> builtIns, Iterable<String> custom) {
  final extra = custom
      .where((c) => !builtIns.any((b) => b.toLowerCase() == c.toLowerCase()))
      .toList()
    ..sort(_byName);
  return [...builtIns, ...extra];
}
