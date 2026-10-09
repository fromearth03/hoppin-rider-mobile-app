# Rider personal information and settings

Updated: 10 October 2026

## Date of birth

Personal Information contains Date of birth below Full name. The rider chooses a date and presses Save. The existing profile PATCH endpoint persists `date_of_birth` as YYYY-MM-DD. Minimum age remains 13. An existing saved date is read-only; corrections require support. Editing another profile field does not force the rider to provide a date, but booking does.

Ordinary and scheduled booking both check the signed-in profile before submitting. Missing DOB opens Personal Information. The API remains authoritative: DOB_REQUIRED also sends the rider there when the cached profile is stale. Returning from Personal Information preserves the selected route and requires another explicit booking confirmation. Profile results are discarded after disposal or an account change.

The ride-service change `65d4325` applies the existing eligibility guard to scheduled-ride creation before insertion and returns the same eligibility errors as ordinary booking. It was deployed through CI. No schema migration was needed.

## Device settings

The following choices are persisted together under `hoppin_device_settings` in FlutterSecureStorage and loaded before the first frame. They belong to the device, including when accounts change. Writes are serialised; a failed write keeps the last saved setting and displays an error.

| Setting | Behaviour |
| --- | --- |
| Do not lock the screen | Keeps the display awake while Hoppin is in the foreground. Releases the lock on backgrounding or disposal. Off by default. |
| Navigation | Chooses Device default, Google Maps, Apple Maps or Waze for the directions icons beside live-trip waypoints. Uses real waypoint coordinates. Pickup asks for walking directions where supported; Waze provides driving only. The internal map is unchanged. Device default falls back to Google Maps if no app opens; other launch failures display an error. |
| Distance Units | Miles by default, with Kilometres available. Updates fare, trip details and receipt distance displays. Values sent to the API and fare calculations retain their original units. |
| Language | English (UK), Urdu and Hindi. Updates app copy immediately, persists across restarts, and uses right-to-left layout for Urdu. Bundled fonts support both scripts offline. |

Localisation lives in `app/lib/core/localization`. Exact app-authored strings and recognised variable templates are translated by `tr`/`AppText`. User-entered content, addresses, names, server-authored support replies and legal documents retain their source language. Templates preserve their variable values. Existing server date strings and external maps interfaces are not translated by the catalogue. New app copy should be added to both catalogue translations. Font licences are bundled alongside the font assets.

## Validation

The non-golden suite passed 685 tests with one existing skip. Following the final typography and layout changes, 64 focused tests passed, including six screenshot renders at 390 by 844 pixels across all three languages. A final settings test rerun passed 10 tests. Library analysis has no errors or warnings, with two pre-existing informational auth-controller lints. Whole-project analysis also reports pre-existing test lints and four unused-import warnings in unchanged tests.

Coverage includes missing-DOB booking redirects, DOB save failure and retry, age validation, late profile responses, persisted settings, rapid writes, failed writes, distance conversion, external navigation launch and failure, screen-lock lifecycle, variable translation and changing language back from Urdu. Feature CI includes the new functional tests. Screenshot capture and build evidence are retained in the owner's local Hoppin follow-up directory.

A real phone still needs installation and checks of login, DOB save and booking, Android screen timeout, installed maps app handoff, and settings after restart. Automated tests do not claim these physical-device checks passed.

## Rollback

All related commits use the `codex:` prefix. Revert the rider settings commit to restore the preceding DOB-popup build; previous rider source is `967f6cf`. The preceding APK remains in `~/hoppin-apks`. Android version code 3 is used for the new APK, with the same package and existing test signing certificate. Installing an older version may require an explicit downgrade or uninstall, so rebuilding the old source with a higher version code is the safer update path.

Backend rollback is a revert of `65d4325`, followed by the normal CI push. That removes scheduled-ride eligibility protection and is not needed merely to roll back the app. No owner actions, driver-app code, live rider website or wallet balances were changed.
