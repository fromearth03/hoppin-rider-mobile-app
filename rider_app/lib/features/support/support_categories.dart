/// The support-ticket taxonomy. SINGLE SOURCE OF TRUTH.
///
/// Every `category` value sent to `POST /me/support-tickets` comes from here.
/// Lane 12-02 (Settings + Deletion) imports [accountDeletion] / [dataExport]
/// and their canonical subject lines for the erasure and access routes. Do NOT
/// hand-type these strings anywhere: two copies of a load-bearing legal
/// category WILL drift, and a drifted category means an erasure request that
/// ops cannot find.
///
/// ## The wire vocabulary is UNDOCUMENTED (gap 75 — relay only)
///
/// DOCS/04 does not enumerate the legal values of `category`, `type_code` or
/// `priority`. The server has evidently accepted the five original client-
/// invented values, but we do not know whether it stores them, drops them, or
/// lets ops filter on them. That is an open question for the backend, not a
/// degradation: nothing here silently fails, so this file mints no seam entry.
///
/// **The mitigation is free and does not depend on the backend:** the request
/// type is ALSO carried in the `subject` line ([deletionSubject],
/// [exportSubject]). A human ops reader sees what the ticket is even if the
/// server drops an unknown `category`. Callers filing a legal-route ticket
/// MUST use the canonical subject, not their own wording.
abstract final class SupportCategories {
  // ---------------------------------------------------------------------
  // Wire values — exactly what goes into `category` on the POST body.
  // ---------------------------------------------------------------------

  /// Anything that does not fit the other categories.
  static const String general = 'general';

  /// Fare, charges, refunds, payment methods.
  static const String fare = 'fare';

  /// Driver conduct, safety, vehicle condition.
  static const String driver = 'driver';

  /// Something left in the vehicle.
  static const String lostItem = 'lost_item';

  /// The app itself misbehaved.
  static const String app = 'app';

  /// UK GDPR Art. 17 — right to erasure. **LEGAL ROUTE.**
  ///
  /// There is no `DELETE /me` (gap 43). A deletion request is filed as a real
  /// support ticket under this category and actioned by a human against the
  /// admin API — see `DOCS/10-gdpr-rights-runbook.md`. File it with
  /// [deletionSubject].
  static const String accountDeletion = 'account_deletion';

  /// UK GDPR Art. 15/20 — right of access & portability. **LEGAL ROUTE.**
  ///
  /// There is no `GET /me/data-export` (gap 43). An export request is filed as
  /// a real support ticket under this category and actioned by a human — see
  /// `DOCS/10-gdpr-rights-runbook.md`. File it with [exportSubject].
  static const String dataExport = 'data_export';

  // ---------------------------------------------------------------------
  // Canonical subject lines — the belt-and-braces mitigation for gap 75.
  // The request type rides in the subject too, so ops can triage a legal
  // request even if the server never stored our `category`.
  // ---------------------------------------------------------------------

  /// The exact subject a deletion ticket must carry. Do not reword it.
  static const String deletionSubject =
      'Account deletion request — right to erasure (Art. 17)';

  /// The exact subject a data-export ticket must carry. Do not reword it.
  static const String exportSubject =
      'Data export request — right of access (Art. 15)';

  // ---------------------------------------------------------------------
  // Labels — the picker reads from here, never from a literal.
  // ---------------------------------------------------------------------

  /// Human-readable label for every wire value, in picker order.
  ///
  /// The two legal routes sit last: they are rare, deliberate acts, and they
  /// should not be one mis-tap away from "General".
  static const Map<String, String> labels = <String, String>{
    general: 'General',
    fare: 'Fare or payment',
    driver: 'Driver behaviour',
    lostItem: 'Lost item',
    app: 'App problem',
    accountDeletion: 'Delete my account',
    dataExport: 'Get a copy of my data',
  };

  /// The wire values in picker order.
  static List<String> get values => labels.keys.toList(growable: false);

  /// The label for a wire value, falling back to the raw value if a future
  /// server-side category arrives that this client does not know about.
  static String labelFor(String value) => labels[value] ?? value;

  /// The two categories that carry a statutory right. A ticket in one of these
  /// is subject to the 1-calendar-month response deadline (Art. 12(3)).
  static const List<String> legalRoutes = <String>[accountDeletion, dataExport];

  /// Whether [value] is a statutory-rights route.
  static bool isLegalRoute(String value) => legalRoutes.contains(value);
}
