import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Event names. They must match the backend `EventType` enum exactly.
abstract final class TrackType {
  static const pageView = 'PAGE_VIEW';
  static const productView = 'PRODUCT_VIEW';
  static const imageZoom = 'IMAGE_ZOOM';
  static const colorSelect = 'COLOR_SELECT';
  static const sizeSelect = 'SIZE_SELECT';
  static const sizeToggle = 'SIZE_TOGGLE';
  static const addToCart = 'ADD_TO_CART';
  static const removeFromCart = 'REMOVE_FROM_CART';
  static const checkoutStart = 'CHECKOUT_START';
  static const checkoutComplete = 'CHECKOUT_COMPLETE';
  static const search = 'SEARCH';
  static const filterApply = 'FILTER_APPLY';
  static const sessionEnd = 'SESSION_END';
}

/// Collects behavior events and ships them in batches to `POST /api/track`.
///
///  * Never throws and never blocks the UI: every public method is safe to
///    call from any widget.
///  * Batches: flushed every 10 s, at 20 queued events, and when the app goes
///    to the background.
///  * Offline / server down: the batch stays in the queue and is retried on
///    the next flush (the queue is capped at 500 events, oldest dropped).
///  * Guests and signed-in users: Dio attaches the access token when there is
///    one, the server links the session to the user.
class TrackingService with WidgetsBindingObserver {
  TrackingService({required Dio dio}) : _dio = dio;

  final Dio _dio;
  static const _anonKey = 'vt_anonymous_id';
  static const _maxQueue = 500;
  static const _batchSize = 50;

  final List<Map<String, dynamic>> _queue = [];
  final Random _rng = Random.secure();

  String _anonymousId = 'pending-device';
  String _sessionId = '';
  String _currentPage = 'app';
  bool _started = false;
  bool _sending = false;
  Timer? _timer;
  Timer? _searchDebounce;

  String get sessionId => _sessionId;

  /// Call once at startup (cheap; failures only disable persistence of the device id).
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _sessionId = _uuid();
    try {
      const storage = FlutterSecureStorage();
      var id = await storage.read(key: _anonKey);
      if (id == null || id.length < 8) {
        id = 'dev-${_uuid()}';
        await storage.write(key: _anonKey, value: id);
      }
      _anonymousId = id;
    } catch (_) {
      _anonymousId = 'dev-${_uuid()}';
    }
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => flush());
  }

  void dispose() {
    _timer?.cancel();
    _searchDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }

  // ───────────────────────── public API ─────────────────────────

  /// Remembers where the user is, so SESSION_END can say where they left.
  void setPage(String page) => _currentPage = page;

  void track(
    String type, {
    String? productId,
    String? variantId,
    String? color,
    String? size,
    int? durationMs,
    String? page,
    Map<String, Object?>? meta,
  }) {
    if (!_started) return;
    _queue.add({
      'type': type,
      if (productId != null) 'productId': productId,
      if (variantId != null) 'variantId': variantId,
      if (color != null) 'color': color,
      if (size != null) 'size': size,
      if (durationMs != null) 'durationMs': durationMs.clamp(0, 3600000),
      'page': page ?? _currentPage,
      if (meta != null && meta.isNotEmpty) 'meta': meta,
      'occurredAt': DateTime.now().toUtc().toIso8601String(),
    });
    if (_queue.length > _maxQueue) _queue.removeRange(0, _queue.length - _maxQueue);
    if (_queue.length >= 20) unawaited(flush());
  }

  /// Debounced: only the final text of a typing burst becomes a SEARCH event.
  void trackSearch(String query) {
    _searchDebounce?.cancel();
    final q = query.trim();
    if (q.length < 2) return;
    _searchDebounce = Timer(const Duration(milliseconds: 900), () {
      track(TrackType.search, page: 'catalog', meta: {'q': q.length > 80 ? q.substring(0, 80) : q});
    });
  }

  /// User signed out: close this session, the next one starts fresh.
  Future<void> endSessionAndRotate() async {
    if (!_started) return;
    track(TrackType.sessionEnd);
    await flush();
    _sessionId = _uuid();
  }

  Future<void> flush() async {
    if (!_started || _sending || _queue.isEmpty) return;
    _sending = true;
    try {
      while (_queue.isNotEmpty) {
        final take = min(_batchSize, _queue.length);
        final batch = _queue.sublist(0, take);
        final ok = await _send(batch);
        if (!ok) break; // keep them, retry on the next flush
        _queue.removeRange(0, take);
      }
    } finally {
      _sending = false;
    }
  }

  // ───────────────────────── internals ─────────────────────────

  /// true = the batch is done with (sent, or permanently rejected).
  Future<bool> _send(List<Map<String, dynamic>> batch) async {
    try {
      await _dio.post<dynamic>(
        '/api/track',
        data: {
          'sessionId': _sessionId,
          'anonymousId': _anonymousId,
          'deviceType': defaultTargetPlatform.name.toLowerCase(),
          'events': batch,
        },
        options: Options(
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );
      return true;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      // 4xx other than auth / timeout / rate limit means the batch itself is bad: drop it.
      if (code != null && code >= 400 && code < 500 && code != 401 && code != 408 && code != 429) {
        debugPrint('[tracking] dropped batch (HTTP $code)');
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      track(TrackType.sessionEnd);
      unawaited(flush());
    }
  }

  String _uuid() {
    final b = List<int>.generate(16, (_) => _rng.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    String h(int from, int to) =>
        b.sublist(from, to).map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h(0, 4)}-${h(4, 6)}-${h(6, 8)}-${h(8, 10)}-${h(10, 16)}';
  }
}
