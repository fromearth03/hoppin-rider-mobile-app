import 'package:flutter_riverpod/flutter_riverpod.dart';

/// L1c seam over external-URL launching (RIDER-APP-ONLY).
///
/// ## Why this exists at all — nothing in Phase 11 launches anything
///
/// This gateway is deliberately built BEFORE it has a single caller, for two
/// reasons, and neither of them is "we want to open links".
///
/// **1. It makes "the app NEVER dials" PROVABLE.** COMMS-02 (masked in-trip
/// voice) has *zero* backend surface: there is no `POST /rides/:id/call`
/// proxy and no masked-number field on any ride payload (gap #45). So the only
/// number the app could possibly dial is the driver's **personal** one — the
/// exact exposure COMMS-02 exists to prevent, and a Scope-Lock hard
/// prohibition. "We won't dial" is an intention; a recording fake injected
/// over [urlLauncherProvider], driven across every control on the call screen
/// and asserting `calls.isEmpty`, is a **control**. That assertion is the
/// requirement, and this interface is what makes it writable.
///
/// **2. It is the body-swap seat.** When the masked-call proxy (#45) ships,
/// the call screen dials the MASKED number through this gateway with zero view
/// changes. When the tokenised tracking-link endpoint (#57) ships, the share
/// sheet's WhatsApp/SMS/Email targets launch through it. Neither happens today.
///
/// ## The live default is a NO-OP, on purpose
///
/// [NoopUrlLauncher] is the live target — it launches nothing and answers
/// `false`. This mirrors `StripeSdkGateway`, whose `Provider` default IS its
/// no-op (which is exactly why the demo layer needs no override: the
/// dependency direction is app → package, so `hoppin_demo` *cannot* override a
/// rider-app-local provider).
///
/// A concrete `url_launcher`-backed implementation is NOT wired here, because
/// `url_launcher` is not in the manifest and **no Phase-11 surface has anything
/// legitimate to launch**. Adding a real launcher now would add a loaded gun to
/// the room and nothing to shoot at. When a real target exists, the concrete
/// implementation slots in behind this interface — and it will be the ONLY
/// file in `lib/` permitted to import the url-launcher plugin, the same
/// isolation contract `maplibre_gl` and `firebase_` carry. (The plugin name is
/// spelled out nowhere in this file on purpose: the phase gate greps `lib/`
/// for the import string, and a docstring explaining the rule must not be what
/// breaks it — the same trap Wave 0 hit with `SEAM(#`.)
///
/// 🔴 **Nothing in this phase calls [launch] with a telephone URI. Nothing in
/// this phase calls [launch] at all.** The gateway exists so the *absence* of
/// dialling is machine-checkable, and so the future body-swap is free.
///
/// (The dial scheme is never spelled literally in this file: the phase gate
/// greps `lib/` for it, and a docstring *explaining* the prohibition must not
/// be what trips the gate — the same trap Wave 0 hit with `SEAM(#`.)
abstract interface class UrlLauncher {
  /// Opens [uri] in the platform handler. Answers whether it was handled.
  ///
  /// Implementations MUST NOT be given a telephone URI carrying a driver's
  /// personal number — no masked proxy exists to produce a safe one (#45).
  Future<bool> launch(Uri uri);
}

/// The current live gateway: it launches nothing.
///
/// Not a placeholder to be filled in casually — it is the honest live shape.
/// Every Phase-11 comms surface is on a disclosed seam (#45 voice, #57 share)
/// and therefore has **no URL to launch**. A no-op that answers `false` tells
/// the truth; a real launcher pointed at a fabricated URL would not.
class NoopUrlLauncher implements UrlLauncher {
  /// Creates the no-op live gateway.
  const NoopUrlLauncher();

  @override
  Future<bool> launch(Uri uri) async => false;
}

/// Exposes the active [UrlLauncher]. Defaults to [NoopUrlLauncher] — the
/// honest live target. Tests override it with a recording fake so that "the
/// app never dials" is asserted rather than assumed.
final urlLauncherProvider = Provider<UrlLauncher>(
  (ref) => const NoopUrlLauncher(),
);
