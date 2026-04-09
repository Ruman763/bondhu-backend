import 'dart:convert';
import 'dart:io';

Future<String?> readFileAsBase64(String path) async {
  final file = File(path);
  if (!await file.exists()) return null;
  final bytes = await file.readAsBytes();
  return base64Encode(bytes);
}
