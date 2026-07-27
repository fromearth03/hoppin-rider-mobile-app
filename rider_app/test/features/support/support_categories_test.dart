import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/support/support_categories.dart';

/// SUPPORT-01 — the ticket taxonomy is the CROSS-LANE CONTRACT.
///
/// These are not decoration. Lane 12-02 files the erasure and access requests
/// against these exact wire strings, and the GDPR ops runbook triages on them.
/// A silent rename would break a legal route WITHOUT breaking a compile — so
/// the wire values are pinned here by literal, on purpose.
void main() {
  group('SUPPORT-01: the legal routes (the Lane 12-02 contract)', () {
    test('accountDeletion is exactly the wire string account_deletion', () {
      expect(
        SupportCategories.accountDeletion,
        'account_deletion',
        reason:
            'Lane 12-02 files the Art. 17 erasure ticket under this category '
            'and the ops runbook triages on it. Renaming it silently breaks a '
            'legal route without breaking a compile.',
      );
    });

    test('dataExport is exactly the wire string data_export', () {
      expect(
        SupportCategories.dataExport,
        'data_export',
        reason:
            'Lane 12-02 files the Art. 15/20 access ticket under this '
            'category. It is a statutory route, not a nice-to-have.',
      );
    });

    test('the canonical deletion subject is pinned verbatim', () {
      expect(
        SupportCategories.deletionSubject,
        'Account deletion request — right to erasure (Art. 17)',
        reason:
            'The wire vocabulary is undocumented (gap 75): we do not know '
            'whether the server stores an unknown category. The subject line '
            'is the belt-and-braces mitigation — a human ops reader sees the '
            'request type either way. It must not be reworded per call site.',
      );
    });

    test('the canonical export subject is pinned verbatim', () {
      expect(
        SupportCategories.exportSubject,
        'Data export request — right of access (Art. 15)',
        reason:
            'Same mitigation as the deletion subject — the request type must '
            'be legible to ops even if the category never lands.',
      );
    });

    test('both legal routes are flagged as such', () {
      expect(
        SupportCategories.legalRoutes,
        containsAll(<String>['account_deletion', 'data_export']),
        reason:
            'A ticket in either category carries the 1-calendar-month Art. '
            '12(3) response deadline. Ops needs to know which those are.',
      );
      expect(
        SupportCategories.isLegalRoute(SupportCategories.accountDeletion),
        isTrue,
        reason: 'the erasure route is a statutory route',
      );
      expect(
        SupportCategories.isLegalRoute(SupportCategories.general),
        isFalse,
        reason: 'a general enquiry carries no statutory deadline',
      );
    });
  });

  group('SUPPORT-01: the five original categories are preserved', () {
    test('the pre-existing wire values are unchanged', () {
      expect(SupportCategories.general, 'general',
          reason: 'the server has been accepting this value — do not churn it');
      expect(SupportCategories.fare, 'fare',
          reason: 'the server has been accepting this value — do not churn it');
      expect(SupportCategories.driver, 'driver',
          reason: 'the server has been accepting this value — do not churn it');
      expect(SupportCategories.lostItem, 'lost_item',
          reason: 'the server has been accepting this value — do not churn it');
      expect(SupportCategories.app, 'app',
          reason: 'the server has been accepting this value — do not churn it');
    });
  });

  group('SUPPORT-01: the taxonomy is complete and picker-ready', () {
    test('all seven categories carry a human-readable label', () {
      expect(
        SupportCategories.values,
        hasLength(7),
        reason:
            'five original categories plus the two legal routes — the picker '
            'renders exactly this set',
      );
      for (final value in SupportCategories.values) {
        expect(
          SupportCategories.labels[value],
          isNotNull,
          reason:
              'the picker reads labels from the taxonomy, never from a '
              'literal — an unlabelled category would render blank: $value',
        );
        expect(
          SupportCategories.labels[value],
          isNotEmpty,
          reason: 'a blank label is an unpickable category: $value',
        );
      }
    });

    test('labelFor falls back to the raw value for an unknown category', () {
      expect(
        SupportCategories.labelFor('something_the_server_added'),
        'something_the_server_added',
        reason:
            'the vocabulary is undocumented (gap 75) — an unknown value must '
            'render as itself, never crash and never render blank',
      );
    });

    test('the legal routes sit last in picker order', () {
      final values = SupportCategories.values;
      expect(
        values.indexOf(SupportCategories.accountDeletion),
        greaterThan(values.indexOf(SupportCategories.app)),
        reason:
            'deleting an account is a rare, deliberate act — it must not sit '
            'one mis-tap away from "General"',
      );
    });
  });
}
