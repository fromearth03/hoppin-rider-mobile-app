# flutter_stripe's push-provisioning bridge references Stripe's optional
# Issuing/TapAndPay SDK, which this app does not ship. R8 fails the release
# build on the dangling references unless told they are expected.
-dontwarn com.stripe.android.pushProvisioning.**
-dontwarn com.reactnativestripesdk.pushprovisioning.**
