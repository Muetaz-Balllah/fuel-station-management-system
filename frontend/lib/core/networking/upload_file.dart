import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';

/// Multipart image part. Dio sets the boundary; callers must not override it.
MultipartFile imagePart(List<int> bytes, String filename) {
  final name = filename.trim().isEmpty ? 'image.jpg' : filename.trim();
  return MultipartFile.fromBytes(bytes, filename: name, contentType: imageMediaType(name));
}

MediaType imageMediaType(String filename) {
  final name = filename.toLowerCase();
  if (name.endsWith('.png')) {
    return MediaType('image', 'png');
  }
  if (name.endsWith('.webp')) {
    return MediaType('image', 'webp');
  }
  return MediaType('image', 'jpeg');
}
