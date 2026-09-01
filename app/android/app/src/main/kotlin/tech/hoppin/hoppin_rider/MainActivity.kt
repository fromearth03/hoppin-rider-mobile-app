package tech.hoppin.hoppin_rider

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity, not FlutterActivity: the Stripe SDK hosts its
// card UI in fragments and refuses to attach to a plain Activity.
class MainActivity : FlutterFragmentActivity()
