import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/api/api_client.dart';
import '../../core/result.dart';

/// Image bytes fetched WITH the bearer token.
///
/// The image routes require auth, and a plain `NetworkImage` (an `<img>` tag on
/// web) cannot send the header — so the bytes come through [ApiClient] like
/// every other call. Cached for the session: these images appear on screens
/// that open often and must not refetch each time.
final apiImageBytesProvider =
    FutureProvider.family<Uint8List?, String>((ref, url) async {
  final result = await ref.watch(apiClientProvider).getBytes(url);
  return switch (result) {
    Ok(:final value) => value,
    Err() => null,
  };
});

/// An operator-uploaded image, with a local fallback for every way it can fail.
///
/// A missing URL, a failed fetch and bytes that will not decode all land on
/// [fallback] rather than a broken-image box: the artwork is decoration on a
/// control the rider still needs to be able to use.
///
/// Handles SVG as well as raster, because the panel accepts SVG — a flat
/// vehicle silhouette is the one thing it is genuinely better at — and
/// `Image.memory` would simply fail on one.
class ApiImage extends ConsumerWidget {
  final String? url;
  final double width;
  final double height;
  final Widget fallback;

  const ApiImage({
    super.key,
    required this.url,
    required this.width,
    required this.height,
    required this.fallback,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final src = url;
    if (src == null || src.isEmpty) return fallback;

    final bytes = ref.watch(apiImageBytesProvider(src)).valueOrNull;
    if (bytes == null) return fallback;

    if (_looksLikeSvg(src, bytes)) {
      return SvgPicture.memory(
        bytes,
        width: width,
        height: height,
        fit: BoxFit.contain,
        placeholderBuilder: (_) => fallback,
      );
    }
    return Image.memory(
      bytes,
      width: width,
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => fallback,
    );
  }

  /// Sniff the payload rather than trusting the extension alone: the key is
  /// operator-supplied, and an SVG handed to Image.memory renders nothing at
  /// all with no error the rider could act on.
  static bool _looksLikeSvg(String url, Uint8List bytes) {
    if (url.toLowerCase().contains('.svg')) return true;
    final head = String.fromCharCodes(bytes.take(256));
    return head.contains('<svg');
  }
}
