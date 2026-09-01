import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/result.dart';

String? _orNull(Object? v) => switch (v) {
      String s when s.trim().isNotEmpty => s,
      _ => null,
    };

/// The outcome of a successful `POST /me/delete-account`.
///
/// The server deletes SYNCHRONOUSLY and irreversibly — it answers `{"status":
/// "deleted"}` with personal data already erased, not a queued request and not
/// a deactivation. Nothing here is reversible from the app.
class AccountDeletion {
  /// The server's own wording, rendered verbatim. Null when it sent none — the
  /// `Ok` is what says the account is gone; the copy is a courtesy.
  final String? message;

  /// `"deleted"` from the live handler.
  final String? status;

  const AccountDeletion({required this.message, required this.status});

  factory AccountDeletion.fromJson(Map<String, dynamic> json) =>
      AccountDeletion(
        message: _orNull(json['message']),
        status: _orNull(json['status']),
      );
}

/// `POST /me/delete-account` — self-service account deletion.
///
/// There is deliberately no deactivate method: no deactivate endpoint exists
/// anywhere in the ride service's route table. See `delete_account_screen.dart`
/// for what the screen does about that.
class AccountRepository {
  final ApiClient _api;
  const AccountRepository(this._api);

  /// Deletes the caller's account. The identity comes from the JWT, so there
  /// is nothing to send.
  ///
  /// A 409 `DELETION_BLOCKED` means the doc's blocking conditions hold (an
  /// active trip, an unresolved dispute, or for drivers an outstanding balance
  /// or compliance investigation). Read the reasons with [blockersOf].
  Future<Result<AccountDeletion>> deleteAccount() async {
    final result = await _api.post<dynamic>('/me/delete-account');
    return switch (result) {
      Ok(:final value) => Ok(AccountDeletion.fromJson(
          value is Map ? Map<String, dynamic>.from(value) : const {})),
      Err(:final error) => Err(error),
    };
  }

  /// The server's `blockers` array, as lines to render.
  ///
  /// `whereType` rather than a cast: the array is server-shaped and a stray
  /// null would otherwise throw out of a method whose signature promises a
  /// plain list — on the one screen where an unhandled throw is least welcome.
  static List<String> blockersOf(ApiException error) {
    final raw = error.fields['blockers'];
    return (raw is List ? raw : const [])
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .toList(growable: false);
  }
}

final accountRepositoryProvider = Provider<AccountRepository>(
    (ref) => AccountRepository(ref.watch(apiClientProvider)));
