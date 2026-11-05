import 'package:file_picker/file_picker.dart';
import '../services/supabase_service.dart';
import 'image_compress.dart';

/// Lets the user pick a file and uploads it as proof (evidence).
///
/// Saves to `<folder>/<user_id>/<file>` in the private `documents` bucket;
/// the storage policies match on the user id in that path, so keep it.
/// Does not add a row to the `documents` table (residents could read it).
///
/// Returns the `{path, name}` entry to append to the row's jsonb list,
/// or null when the picker was dismissed. Throws on a failed upload so
/// the caller can show it in its own error slot.
Future<Map<String, dynamic>?> pickAndUploadEvidence({
  required String folder,
  required int userId,
}) async {
  final picked = await FilePicker.platform.pickFiles(withData: true);
  if (picked == null || picked.files.isEmpty) return null;
  final file = picked.files.first;
  if (file.bytes == null) return null;

  // Shrinks photos before upload; other files pass through unchanged.
  final shrunk = compressImageBytes(file.bytes!, file.name);

  // The path is cleaned for use in a URL, and the timestamp stops same-named
  // files overwriting each other. Use the compressed name: its extension can
  // change to .jpg, and a mismatch breaks the content type.
  final safe = shrunk.filename.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final path =
      '$folder/$userId/${DateTime.now().millisecondsSinceEpoch}-$safe';

  await SupabaseService.instance.client.storage
      .from('documents')
      .uploadBinary(path, shrunk.bytes);

  // The original name is stored for display.
  return {'path': path, 'name': file.name};
}
