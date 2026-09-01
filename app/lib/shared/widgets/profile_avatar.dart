import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/result.dart';
import '../../core/theme/colors.dart';

/// Avatar bytes fetched WITH the bearer token.
///
/// The avatar route requires auth, and a plain `NetworkImage` (an `<img>` tag
/// on web) cannot send the header — so the bytes come through [ApiClient]
/// like every other call. Cached for the session: the drawer opens often and
/// must not refetch the photo every time.
final profileAvatarBytesProvider =
    FutureProvider.family<Uint8List?, String>((ref, url) async {
  final result = await ref.watch(apiClientProvider).getBytes(url);
  return switch (result) {
    Ok(:final value) => value,
    Err() => null,
  };
});

/// The user photo everywhere it appears (drawer header, profile, receipts).
///
/// Photo when it loads; the name's initial on navy while it hasn't or when
/// the rider has none — never a broken-image box.
class ProfileAvatar extends ConsumerWidget {
  final String? avatarUrl;
  final String? name;
  final double radius;

  const ProfileAvatar({
    super.key,
    required this.avatarUrl,
    required this.name,
    this.radius = 27,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = avatarUrl;
    final bytes =
        url == null ? null : ref.watch(profileAvatarBytesProvider(url)).valueOrNull;

    final display = name?.trim();
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.navy,
      backgroundImage: bytes != null ? MemoryImage(bytes) : null,
      child: bytes == null
          ? Text(
              (display == null || display.isEmpty)
                  ? '?'
                  : display.characters.first.toUpperCase(),
              style: TextStyle(
                color: Colors.white,
                fontSize: radius * 0.72,
                fontWeight: FontWeight.w600,
              ),
            )
          : null,
    );
  }
}
