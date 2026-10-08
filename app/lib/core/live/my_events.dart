import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';

/// One "something of yours changed" signal from the server.
class MyEvent {
  final String kind; // ride | chat | ticket | call
  final String id;
  const MyEvent(this.kind, this.id);
}

/// The rider's live channel (`GET /me/events`).
///
/// The server signals when the rider's ride, ride chat, support ticket or call
/// changes, and screens re-read that item at once instead of polling every few
/// seconds. Opened while something is listening and the app is signed in;
/// reconnects with a back-off. While it is down, [live] is false and screens
/// keep their old, faster refresh, so nothing goes stale.
///
/// Not used on web: the browser HTTP client cannot stream, so web keeps polling.
class MyEvents {
  /// Looked up only when the channel opens, so building a screen never needs
  /// the network client (tests, or before sign-in).
  final ApiClient Function() _api;
  MyEvents(this._api);

  final _events = StreamController<MyEvent>.broadcast();
  bool _live = false;
  int _listeners = 0;
  StreamSubscription<String>? _sub;
  Timer? _retry;

  /// Whether the channel is connected right now.
  bool get live => _live;

  /// Every signal; filter by kind and id.
  Stream<MyEvent> get events => _events.stream;

  /// Signals for one item, for a screen that shows it.
  Stream<MyEvent> watch(String kind, String id) {
    late StreamController<MyEvent> c;
    StreamSubscription<MyEvent>? s;
    c = StreamController<MyEvent>(
      onListen: () {
        _listeners++;
        _open();
        s = events.where((e) => e.kind == kind && (id.isEmpty || e.id == id)).listen(c.add);
      },
      onCancel: () async {
        await s?.cancel();
        _listeners--;
        if (_listeners <= 0) _close();
      },
    );
    return c.stream;
  }

  void _open() {
    if (kIsWeb || _sub != null) return;
    _retry?.cancel();
    final ApiClient api;
    try {
      api = _api();
    } catch (_) {
      return; // no client here: stay on the screens' own refresh
    }
    _sub = api.sse('/me/events', eventNames: true).listen(
      (line) {
        _live = true;
        // `sse(..., eventNames: true)` yields "kind\nid".
        final i = line.indexOf('\n');
        if (i > 0) _events.add(MyEvent(line.substring(0, i), line.substring(i + 1)));
      },
      onError: (_) => _dropped(),
      onDone: _dropped,
      cancelOnError: true,
    );
    // The first byte is a comment; count the stream as live once it opens.
    _live = true;
  }

  void _dropped() {
    _sub = null;
    _live = false;
    if (_listeners > 0) {
      _retry?.cancel();
      _retry = Timer(const Duration(seconds: 10), _open);
    }
  }

  void _close() {
    _retry?.cancel();
    _sub?.cancel();
    _sub = null;
    _live = false;
  }
}

final myEventsProvider =
    Provider<MyEvents>((ref) => MyEvents(() => ref.read(apiClientProvider)));
