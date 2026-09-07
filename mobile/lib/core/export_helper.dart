import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Writes exported bytes (CSV/PDF from the backend) to a temp file and opens
/// the OS share sheet, the standard mobile pattern for "export" since there's
/// no browser download folder to drop into.
Future<void> shareExportedFile(List<int> bytes, String filename) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes, flush: true);
  await Share.shareXFiles([XFile(file.path)], fileNameOverrides: [filename]);
}
