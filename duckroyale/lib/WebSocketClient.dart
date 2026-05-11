import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class TimeoutException implements Exception {
  final String message;
  const TimeoutException(this.message);
  @override
  String toString() => message;
}

enum WsMessageType {
  joined,
  playerList,
  playerJoined,
  playerMoved,
  playerLeft,
  state,
  gameOver,
  error,
  unknown,
}

class WsMessage {
  final WsMessageType type;
  final Map<String, dynamic> data;
  const WsMessage(this.type, this.data);
}

class GameWebSocketClient {
  final String url;
  final String playerName;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  bool _manualClose = false;

  final _controller = StreamController<WsMessage>.broadcast();
  Stream<WsMessage> get messages => _controller.stream;

  String? playerId;
  bool get isConnected => _channel != null;

  GameWebSocketClient({required this.url, required this.playerName});

  Future<void> connect() async {
    _manualClose = false;
    _channel = WebSocketChannel.connect(Uri.parse(url));
    await _channel!.ready.timeout(
      const Duration(seconds: 6),
      onTimeout: () => throw const TimeoutException('Server did not respond'),
    );

    _sub = _channel!.stream.listen(
      _onData,
      onError: _onError,
      onDone: _onDone,
    );

    _send({'type': 'JOIN', 'name': playerName});
  }

  void sendInput({required bool left, required bool right, required bool jump, required bool attack}) {
    _send({'type': 'INPUT', 'left': left, 'right': right, 'jump': jump, 'attack': attack});
  }

  void sendMove(String direction) {
    _send({'type': 'MOVE', 'direction': direction});
  }

  void _send(Map<String, dynamic> payload) {
    final channel = _channel;
    if (channel != null) channel.sink.add(jsonEncode(payload));
  }

  void _onData(dynamic raw) {
    late Map<String, dynamic> json;
    try {
      json = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final type = switch (json['type']) {
      'JOINED' => WsMessageType.joined,
      'PLAYER_LIST' => WsMessageType.playerList,
      'PLAYER_JOINED' => WsMessageType.playerJoined,
      'PLAYER_MOVED' => WsMessageType.playerMoved,
      'PLAYER_LEFT' => WsMessageType.playerLeft,
      'STATE' => WsMessageType.state,
      'GAME_OVER' => WsMessageType.gameOver,
      'ERROR' => WsMessageType.error,
      _ => WsMessageType.unknown,
    };

    if (type == WsMessageType.joined) {
      playerId = json['id'] as String?;
    }

    if (!_controller.isClosed) _controller.add(WsMessage(type, json));
  }

  void _onError(Object err) {
    if (!_manualClose && !_controller.isClosed) {
      _controller.add(WsMessage(WsMessageType.error, {'message': err.toString()}));
    }
  }

  void _onDone() {
    _channel = null;
    playerId = null;
    if (!_manualClose && !_controller.isClosed) {
      _controller.add(const WsMessage(WsMessageType.error, {'message': 'Connection closed'}));
    }
  }

  Future<void> disconnect() async {
    _manualClose = true;
    playerId = null;
    await _sub?.cancel();
    _sub = null;
    await _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    disconnect();
    _controller.close();
  }
}
