import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:image_picker/image_picker.dart';

/// The live profile-photo picker. **The only file on the avatar path that
/// touches a plugin** — everything downstream takes bytes through the
/// [AvatarPicker] seam, which is what keeps MethodChannel mocks out of the
/// test suite.
class PlatformAvatarPicker implements AvatarPicker {
  PlatformAvatarPicker({ImagePicker? images}) : _images = images ?? ImagePicker();

  final ImagePicker _images;

  @override
  Future<PickedAvatar?> pickAvatar({bool fromCamera = false}) async {
    final file = await _images.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      // A cheap first cut at the server's 8 MB ceiling so the common case never
      // reaches it. Advisory only — some Android OEM camera stacks ignore both
      // of these, so the controller still checks the real byte length.
      imageQuality: 85,
      maxWidth: 1024,
    );
    if (file == null) return null;

    final bytes = await file.readAsBytes();
    // Send the ORIGINAL bytes. The server re-encodes to JPEG and that re-encode
    // is what strips EXIF — pre-processing here would not remove the GPS
    // coordinates a photo taken at home carries, it would only cost quality.
    return (bytes: bytes, filename: file.name);
  }
}
