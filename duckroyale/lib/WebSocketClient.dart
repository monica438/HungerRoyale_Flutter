import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class TimeoutException implements Exception {
  final String message;
  const TimeoutException(this.message);
  @override
  String toString() => message;
}

// ── Tipos de mensaje ─────────────────────────────────────

enum WsMessageType {
  joined,
  playerList,
  playerJoined,
  playerMoved,
  playerLeft,
  error,
  unknown,
}

class WsMessage {
  final WsMessageType type;
  final Map<String, dynamic> data;
  const WsMessage(this.type, this.data);
}

// ── Cliente ──────────────────────────────────────────────

class GameWebSocketClient {
  final String url;
  final String playerName;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;

  final _controller = StreamController<WsMessage>.broadcast();
  Stream<WsMessage> get messages => _controller.stream;

  String? playerId;
  bool get isConnected => _channel != null;

  GameWebSocketClient({required this.url, required this.playerName});

  Future<void> connect() async {
    _channel = WebSocketChannel.connect(Uri.parse(url));
    await _channel!.ready.timeout(
      const Duration(seconds: 6),
      onTimeout: () => throw TimeoutException('Server did not respond'),
    );

    _sub = _channel!.stream.listen(
      _onData,
      onError: _onError,
      onDone: _onDone,
    );

    // Unirse a la partida
    _send({'type': 'JOIN', 'name': playerName});
  }

  void sendMove(String direction) {
    assert(['UP', 'LEFT', 'RIGHT'].contains(direction));
    _send({'type': 'MOVE', 'direction': direction});
  }

  void _send(Map<String, dynamic> payload) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode(payload));
    }
  }

  void _onData(dynamic raw) {
    late Map<String, dynamic> json;
    try {
      json = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final type = switch (json['type']) {
      'JOINED'        => WsMessageType.joined,
      'PLAYER_LIST'   => WsMessageType.playerList,
      'PLAYER_JOINED' => WsMessageType.playerJoined,
      'PLAYER_MOVED'  => WsMessageType.playerMoved,
      'PLAYER_LEFT'   => WsMessageType.playerLeft,
      'ERROR'         => WsMessageType.error,
      _               => WsMessageType.unknown,
    };

    if (type == WsMessageType.joined) {
      playerId = json['id'] as String?;
    }

    _controller.add(WsMessage(type, json));
  }

  void _onError(Object err) {
    _controller.add(WsMessage(WsMessageType.error, {'message': err.toString()}));
  }

  void _onDone() {
    _controller.add(WsMessage(WsMessageType.error, {'message': 'Connection closed'}));
  }

  Future<void> disconnect() async {
    await _sub?.cancel();
    await _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    disconnect();
    _controller.close();
  }
}
