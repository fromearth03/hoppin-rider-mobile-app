# flutter_stripe's push-provisioning bridge references Stripe's optional
# Issuing/TapAndPay SDK, which this app does not ship. R8 fails the release
# build on the dangling references unless told they are expected.
-dontwarn com.stripe.android.pushProvisioning.**
-dontwarn com.reactnativestripesdk.pushprovisioning.**

# flutter_callkit_incoming (in-app calls) serialises each call's settings by
# field name — ringtone, extras, ids — and R8 renames those fields in release
# builds, so settings silently fall off between Dart and the native ring screen
# (the phone rang without its ringtone). Required by the plugin's README.
-keep class com.hiennv.flutter_callkit_incoming.** { *; }
