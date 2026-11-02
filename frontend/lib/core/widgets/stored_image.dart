import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:frontend/core/networking/api_config.dart';

String? mediaUrl(String? path) {
  if (path == null || path.isEmpty) {
    return null;
  }
  if (path.startsWith('http://') || path.startsWith('https://')) {
    return path;
  }
  return '$apiBaseUrl$path';
}

class StoredImage extends StatelessWidget {
  const StoredImage({
    super.key,
    this.bytes,
    this.url,
    this.fit = BoxFit.cover,
    required this.placeholder,
  });

  final Uint8List? bytes;
  final String? url;
  final BoxFit fit;
  final Widget placeholder;

  @override
  Widget build(BuildContext context) {
    if (bytes != null) {
      return Image.memory(bytes!, fit: fit, gaplessPlayback: true);
    }
    final resolved = mediaUrl(url);
    if (resolved == null) {
      return placeholder;
    }
    return Image.network(
      resolved,
      fit: fit,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => placeholder,
    );
  }
}
