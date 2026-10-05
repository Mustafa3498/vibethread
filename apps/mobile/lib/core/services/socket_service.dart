import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'secure_storage_service.dart';

/// Connection lifecycle states exposed to the presentation layer.
enum SocketStatus { disconnected, connecting, connected, reconnecting, error }

/// A raw event received from the server.
@immutable
class SocketEvent {
  const SocketEvent(this.name, this.data);

  final String name;
  final dynamic data;
}

/// Thrown when an operation requires a live socket and none is available.
class SocketNotConnectedException implements Exception {
  const SocketNotConnectedException();

  @override
  String toString() => 'SocketNotConnectedException: socket is not connected';
}

/// Real-time transport built on socket_io_client.
///
/// - Reads the access token from [SecureStorageService] and sends it via the
///   Socket.IO `auth` handshake payload (`socket.handshake.auth.token`).
/// - Refreshes the token before every reconnect attempt, so an access token
///   rotated by the Dio interceptor is picked up automatically.
/// - Exposes a single broadcast event stream that survives socket re-creation,
///   so BLoCs can subscribe once and never re-bind after reconnects.
class SocketService {
  SocketService({
    required SecureStorageService secureStorage,
    required String serverUrl,
    this.reconnectionDelay = const Duration(seconds: 1),
    this.reconnectionDelayMax = const Duration(seconds: 10),
    this.reconnectionAttempts = 10,
  })  : _storage = secureStorage,
        _serverUrl = serverUrl;

  final SecureStorageService _storage;
  final String _serverUrl;
  final Duration reconnectionDelay;
  final Duration reconnectionDelayMax;
  final int reconnectionAttempts;

  io.Socket? _socket;
  bool _disposed = false;
  bool _connecting = false;

  SocketStatus _status = SocketStatus.disconnected;

  final _statusController = StreamController<SocketStatus>.broadcast();
  final _eventController = StreamController<SocketEvent>.broadcast();

  /// Current connection status.
  SocketStatus get status => _status;

  bool get isConnected => _socket?.connected ?? false;

  /// Emits whenever the connection status changes.
  Stream<SocketStatus> get statusStream => _statusController.stream;

  /// Every server event, unfiltered.
  Stream<SocketEvent> get events => _eventController.stream;

  /// Server events with a specific [event] name. The stream survives
  /// reconnects. Payloads that are not of type [T] are skipped.
  Stream<T> on<T>(String event) => _eventController.stream
      .where((e) => e.name == event && e.data is T)
      .map((e) => e.data as T);

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Opens the connection using the stored access token. Safe to call
  /// repeatedly; no-ops if already connected or connecting.
  Future<void> connect() async {
    if (_disposed || _connecting || isConnected) return;
    _connecting = true;

    try {
      final token = await _storage.getAccessToken();
      if (token == null || token.isEmpty) {
        _log('No access token available; aborting connect.');
        _setStatus(SocketStatus.error);
        return;
      }

      _teardownSocket();
      _setStatus(SocketStatus.connecting);

      final socket = io.io(
        _serverUrl,
        io.OptionBuilder()
            .setTransports(['websocket'])
            .setAuth({'token': token})
            .disableAutoConnect()
            .enableReconnection()
            .setReconnectionAttempts(reconnectionAttempts)
            .setReconnectionDelay(reconnectionDelay.inMilliseconds)
            .setReconnectionDelayMax(reconnectionDelayMax.inMilliseconds)
            .setRandomizationFactor(0.5)
            .build(),
      );

      _bindListeners(socket);
      _socket = socket;
      socket.connect();
    } catch (e, st) {
      _log('connect() failed: $e\n$st');
      _setStatus(SocketStatus.error);
    } finally {
      _connecting = false;
    }
  }

  /// Closes the connection (e.g. on logout).
  void disconnect() {
    _teardownSocket();
    _setStatus(SocketStatus.disconnected);
  }

  /// Drops the current connection and reconnects with a fresh token.
  /// Call this after a login or an explicit token refresh.
  Future<void> reconnect() async {
    disconnect();
    await connect();
  }

  /// Releases all resources. The service cannot be used afterwards.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _teardownSocket();
    await _statusController.close();
    await _eventController.close();
  }

  // ---------------------------------------------------------------------------
  // Emitting
  // ---------------------------------------------------------------------------

  /// Fire-and-forget emit. Throws if the socket was never created.
  void emit(String event, [dynamic data]) {
    final socket = _socket;
    if (socket == null) throw const SocketNotConnectedException();
    socket.emit(event, data);
  }

  /// Emit and await the server's acknowledgement.
  Future<T> emitWithAck<T>(
    String event, [
    dynamic data,
    Duration timeout = const Duration(seconds: 10),
  ]) {
    final socket = _socket;
    if (socket == null || !socket.connected) {
      return Future.error(const SocketNotConnectedException());
    }

    final completer = Completer<T>();
    socket.emitWithAck(event, data, ack: (dynamic response) {
      if (completer.isCompleted) return;
      if (response is T) {
        completer.complete(response);
      } else {
        completer.completeError(
          StateError(
            'Ack for "$event" was ${response.runtimeType}, expected $T',
          ),
        );
      }
    });

    return completer.future.timeout(
      timeout,
      onTimeout: () => throw TimeoutException(
        'No acknowledgement for "$event" within $timeout',
        timeout,
      ),
    );
  }

  /// Joins a server-side room. Requires a matching handler on the backend.
  void joinRoom(String room) => emit('room:join', room);

  /// Leaves a server-side room.
  void leaveRoom(String room) => emit('room:leave', room);

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  void _bindListeners(io.Socket socket) {
    socket
      ..onConnect((_) {
        _log('connected (${socket.id})');
        _setStatus(SocketStatus.connected);
      })
      ..onDisconnect((reason) {
        _log('disconnected: $reason');
        // "io server disconnect" means the server kicked us; the client will
        // not auto-reconnect in that case, so retry with a fresh token.
        if (reason == 'io server disconnect' && !_disposed) {
          unawaited(reconnect());
          return;
        }
        _setStatus(
          socket.active ? SocketStatus.reconnecting : SocketStatus.disconnected,
        );
      })
      ..onConnectError((error) {
        _log('connect_error: $error');
        _setStatus(
          socket.active ? SocketStatus.reconnecting : SocketStatus.error,
        );
      })
      ..onError((error) => _log('error: $error'))
      ..onAny((event, data) {
        if (!_eventController.isClosed) {
          _eventController.add(SocketEvent(event, data));
        }
      });

    // Refresh the handshake token before each retry. Best effort: the manager
    // reads `socket.auth` when the transport opens.
    socket.io.on('reconnect_attempt', (_) async {
      _setStatus(SocketStatus.reconnecting);
      try {
        final fresh = await _storage.getAccessToken();
        if (fresh != null && fresh.isNotEmpty) {
          socket.auth = {'token': fresh};
        }
      } catch (e) {
        _log('token refresh before reconnect failed: $e');
      }
    });

    socket.io.on('reconnect_failed', (_) {
      _log('reconnect attempts exhausted');
      _setStatus(SocketStatus.error);
    });
  }

  void _teardownSocket() {
    final socket = _socket;
    _socket = null;
    if (socket == null) return;
    socket
      ..clearListeners()
      ..io.clearListeners()
      ..disconnect()
      ..dispose();
  }

  void _setStatus(SocketStatus next) {
    if (_disposed || _status == next) return;
    _status = next;
    if (!_statusController.isClosed) _statusController.add(next);
  }

  void _log(String message) {
    if (kDebugMode) debugPrint('[SocketService] $message');
  }
}
