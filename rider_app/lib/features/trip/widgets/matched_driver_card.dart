import 'package:flutter/material.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// The matched-driver identity card — the rider demo's emotional core.
///
/// Locked hierarchy (riders find cars by PLATE, not by face): the UK plate
/// chip leads, then the vehicle line, then the identity row (initials
/// avatar + name + rating + trips), then a 44px+ message/call/share/safety
/// action row. The ETA headline is NOT here — it is the trip view's hero;
/// this card sits self-contained beneath it.
///
/// Pure presentation (riblet view rules): state in via [info], events out
/// via the callbacks. No repositories, no navigation, no timers. Share
/// behaviour (clipboard + snack) belongs to the CALLER via [onShare].
///
/// [compact] renders the on-road mini-card: one row — small plate + name +
/// rating, no vehicle line, no action row (callers place actions elsewhere).
class MatchedDriverCard extends StatelessWidget {
  /// Creates the card for the matched driver [info].
  const MatchedDriverCard({
    required this.info,
    this.onContact,
    this.onCall,
    this.onShare,
    this.onSafety,
    this.compact = false,
    this.imageHeaders,
    super.key,
  });

  /// Driver identity + vehicle from the DEMO-07 seam.
  final RideDriverInfo info;

  /// Bearer headers used to load [info]'s photo, which is served by the
  /// authenticated `GET /api/v1/images/*path` route. Omit and the photo 401s
  /// into the initials fallback — supply `imageAuthHeadersProvider`.
  final Map<String, String>? imageHeaders;

  /// Message-the-driver intent — the BOUND comms surface
  /// (`POST /rides/:id/messages`).
  final VoidCallback? onContact;

  /// Call-the-driver intent — the SEAMED comms surface (#45).
  ///
  /// Distinct from [onContact] on purpose. Wave 0 deleted a phone-icon button
  /// labelled "Contact" that opened CHAT: an affordance that was not what it
  /// appeared to be. The fix is not to hide calling — it is to make Call a
  /// button of its own that leads somewhere honestly about calling. The caller
  /// routes it to the inert call surface, which discloses that masked calling
  /// is not live yet.
  final VoidCallback? onCall;

  /// Share-trip intent (caller wires clipboard + confirmation).
  final VoidCallback? onShare;

  /// Safety-tools intent.
  final VoidCallback? onSafety;

  /// Mini-card density for the on-road state.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return compact ? _buildCompact(context) : _buildFull(context);
  }

  Widget _buildFull(BuildContext context) {
    final hoppin = context.hoppin;
    return HopCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1 — the plate, visually dominant and centred.
          Center(child: PlateChip(reg: info.plate, size: PlateSize.lg)),
          SizedBox(height: hoppin.spacing.md),
          // 2 — the vehicle line: "colour make model".
          Center(
            child: Text(
              '${info.vehicleColour} ${info.vehicleMake} ${info.vehicleModel}',
              style: hoppin.type.titleSmall
                  .copyWith(color: hoppin.colors.textHi),
            ),
          ),
          SizedBox(height: hoppin.spacing.lg),
          // 3 — identity: avatar + name + rating + trips.
          Row(
            children: [
              _DriverAvatar(
                initials: info.initials,
                photoUrl: info.photoUrl,
                imageHeaders: imageHeaders,
              ),
              SizedBox(width: hoppin.spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.fullName,
                      style: hoppin.type.body.copyWith(
                        color: hoppin.colors.textHi,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: hoppin.spacing.xs),
                    Text(
                      '${_ratingLine(info)} · ${_tripsLine(info)}',
                      style: hoppin.type.bodySmall
                          .copyWith(color: hoppin.colors.textMid),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: hoppin.spacing.lg),
          // 4 — the 4-up action row, every target 44px+.
          //
          // WAVE-0 + PHASE-11: this row used to carry a PHONE icon labelled
          // "Contact" that opened CHAT — a phone affordance that was not a
          // phone, on the three phases where a rider most wants to call.
          // Wave 0 stopped it lying by relabelling it Message. Phase 11
          // finishes the job: Message and Call are now TWO buttons doing TWO
          // things. Message is BOUND (`POST /rides/:id/messages`). Call opens
          // the inert call surface on the disclosed voice seam (#45), which
          // says plainly that masked calling is not live yet — and it NEVER
          // dials, because with no masking proxy the only number reachable
          // would be the driver's personal one.
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.chat_bubble_outline,
                  label: 'Message',
                  onTap: onContact,
                ),
              ),
              SizedBox(width: hoppin.spacing.sm),
              Expanded(
                child: _ActionButton(
                  icon: Icons.phone_outlined,
                  label: 'Call',
                  onTap: onCall,
                ),
              ),
              SizedBox(width: hoppin.spacing.sm),
              Expanded(
                child: _ActionButton(
                  icon: Icons.ios_share_outlined,
                  label: 'Share trip',
                  onTap: onShare,
                ),
              ),
              SizedBox(width: hoppin.spacing.sm),
              Expanded(
                child: _ActionButton(
                  icon: Icons.shield_outlined,
                  label: 'Safety',
                  onTap: onSafety,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompact(BuildContext context) {
    final hoppin = context.hoppin;
    return HopCard(
      padding: EdgeInsets.symmetric(
        horizontal: hoppin.spacing.lg,
        vertical: hoppin.spacing.md,
      ),
      child: Row(
        children: [
          PlateChip(reg: info.plate),
          SizedBox(width: hoppin.spacing.md),
          Expanded(
            child: Text(
              info.fullName,
              style: hoppin.type.bodySmall.copyWith(
                color: hoppin.colors.textHi,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(width: hoppin.spacing.sm),
          Text(
            _ratingLine(info),
            style: hoppin.type.numeralCaption
                .copyWith(color: hoppin.colors.textMid),
          ),
        ],
      ),
    );
  }

  static String _ratingLine(RideDriverInfo info) =>
      '★ ${info.rating.toStringAsFixed(1)}';

  static String _tripsLine(RideDriverInfo info) =>
      '${_thousands(info.tripsCount)} trips';

  /// 1480 -> '1,480' — no intl dependency for one comma.
  static String _thousands(int value) {
    final digits = value.toString();
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      out.write(digits[i]);
      final fromEnd = digits.length - i - 1;
      if (fromEnd > 0 && fromEnd % 3 == 0) out.write(',');
    }
    return out.toString();
  }
}

/// The 44px circular driver avatar.
///
/// The #5 driver-info seam serves a name but frequently no photo (the hosted
/// `/rides/:id/driver-info` returns a null/empty `photo_url`). Rather than
/// paint a blank white box where a face would go, this renders a POLISHED
/// initials treatment on the rider accent tokens as the intentional default:
/// a tinted circle with a hairline accent ring and the driver's initials in
/// accent ink. It reads as a designed identity chip, not a broken image.
///
/// When a real [photoUrl] is present it fades the photo in over that same
/// initials treatment (via [FadeInImage]'s placeholder path) and, if the
/// image fails to load, falls straight back to the initials — so there is no
/// state in which the slot collapses to a bare white rectangle.
class _DriverAvatar extends StatelessWidget {
  const _DriverAvatar({
    required this.initials,
    this.photoUrl,
    this.imageHeaders,
  });

  final String initials;
  final String? photoUrl;

  /// Bearer headers for [photoUrl]. `photo_url` points at
  /// `GET /api/v1/images/*path`, which is authenticated — without these the
  /// request 401s and silently renders as the initials fallback, i.e. exactly
  /// like a driver who never set a photo.
  final Map<String, String>? imageHeaders;

  static const double _size = 44;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final url = photoUrl?.trim();
    final hasPhoto = url != null && url.isNotEmpty;

    final initialsLayer = Center(
      child: Text(
        initials,
        style: hoppin.type.label.copyWith(
          color: colors.accent,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    return Container(
      width: _size,
      height: _size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.accentSubtle,
        shape: BoxShape.circle,
        // A hairline accent ring lifts the initials chip off the card so it
        // reads as an intentional avatar, never an empty placeholder.
        border: Border.all(color: colors.accent.withValues(alpha: 0.24)),
      ),
      child: hasPhoto
          ? Image(
              image: NetworkImage(url, headers: imageHeaders),
              fit: BoxFit.cover,
              // The initials sit UNDER the photo: they show while it loads and
              // stay put if it errors — the slot is never blank.
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : initialsLayer,
              errorBuilder: (context, _, _) => initialsLayer,
            )
          : initialsLayer,
    );
  }
}

/// One 44px+ hairline action target: icon over label, token-coloured ink.
class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(hoppin.radii.input),
      side: BorderSide(color: hoppin.colors.hairline),
    );
    return Material(
      color: hoppin.colors.card,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        customBorder: shape,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            // Horizontal inset is xs, not sm: this button is one of FOUR equal
            // columns inside a card, so every point spent here comes straight
            // out of the label's width.
            padding: EdgeInsets.symmetric(
              horizontal: hoppin.spacing.xs,
              vertical: hoppin.spacing.sm,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: hoppin.colors.accent),
                SizedBox(height: hoppin.spacing.xs),
                // The label SHRINKS rather than clips. Four equal columns
                // inside a gutter'd card leave ~48pt of text width on a 360pt
                // phone, and "Message", "Share trip" and "Safety" ALL ellipsed
                // there — three of the four actions read as "Share tr…". A
                // truncated verb on a safety control is not a style choice, so
                // the label scales to fit its column instead. FittedBox only
                // ever shrinks, so on a roomy width this is pixel-identical.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: hoppin.type.labelSmall
                        .copyWith(color: hoppin.colors.textHi),
                    maxLines: 1,
                    softWrap: false,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
