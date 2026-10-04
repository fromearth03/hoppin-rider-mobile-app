import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/result.dart';

/// `GET /me/data-export` — a copy of everything Hoppin holds on the caller
/// (UK GDPR right of access), as one JSON document.
///
/// Fetched as raw bytes rather than decoded: the app does nothing with the
/// contents except hand the file to the rider, so parsing it would only add a
/// way for a new server field to break the download.
class DataExportRepository {
  final ApiClient _api;
  const DataExportRepository(this._api);

  Future<Result<Uint8List>> download() => _api.getBytes('/me/data-export');
}

final dataExportRepositoryProvider = Provider<DataExportRepository>(
    (ref) => DataExportRepository(ref.watch(apiClientProvider)));
