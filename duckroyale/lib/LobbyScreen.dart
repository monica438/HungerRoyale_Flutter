import 'dart:async';
import 'package:flutter/material.dart';
import 'WebSocketClient.dart';
import 'GameLogic.dart';

const _gold = Color(0xFFd4a843);
const _stoneDk = Color(0xFF4a5568);
const _cardBg = Color(0xFF1a1f2e);

class LobbyScreen extends StatefulWidget {
  final GameWebSocketClient client;
  final String playerName;
  const LobbyScreen({super.key, required this.client, required this.playerName});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  final Map<String, _LobbyPlayer> _playersById = {};
  StreamSubscription? _sub;
  String _phase = 'waiting';
  int? _countdown;
  String? _error;
  bool _navigatingToGame = false;

  @override
  void initState() {
    super.initState();
    _sub = widget.client.messages.listen(_onMessage);
  }

  void _onMessage(WsMessage msg) {
    if (!mounted) return;

    if (msg.type == WsMessageType.error) {
      setState(() => _error = msg.data['message']?.toString() ?? 'Connection error');
      return;
    }

    if (msg.type != WsMessageType.state) return;

    final lobby = (msg.data['lobby'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final players = (msg.data['players'] as List? ?? const [])
        .whereType<Map>()
        .map((p) => p.cast<String, dynamic>());

    setState(() {
      _phase = lobby['phase'] as String? ?? 'waiting';
      _countdown = (lobby['countdown'] as num?)?.toInt();
      _playersById
        ..clear()
        ..addEntries(players.map((p) => MapEntry(
              p['id'] as String,
              _LobbyPlayer(
                id: p['id'] as String,
                name: p['name'] as String? ?? 'Duck',
                color: p['color'] as String? ?? 'yellow',
              ),
            )));
    });

    if (_phase == 'playing' && !_navigatingToGame) {
      _navigatingToGame = true;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => GameLogic(client: widget.client, playerName: widget.playerName),
      ));
    }
  }

  Future<void> _leave() async {
    await _sub?.cancel();
    await widget.client.disconnect();
    if (mounted) Navigator.of(context).pop();
  }

  String get _status {
    if (_error != null) return 'Error: $_error';
    if (_phase == 'countdown') return 'Game starting soon...';
    if (_phase == 'ended') return 'Round finished. Resetting...';
    return 'Waiting for players...';
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final players = _playersById.values.toList();
    final showCountdown = _phase == 'countdown' && _countdown != null;

    return Scaffold(
      backgroundColor: const Color(0xFF05080f),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('WAITING ROOM', style: TextStyle(
                fontFamily: 'monospace', fontSize: 22, fontWeight: FontWeight.bold,
                color: _gold, letterSpacing: 4,
              )),
              const SizedBox(height: 8),
              Text(_status, style: const TextStyle(
                fontFamily: 'monospace', fontSize: 11, color: Color(0xFF8d9b8e), letterSpacing: 1.5,
              )),
              const SizedBox(height: 12),
              if (showCountdown)
                Text('$_countdown', style: TextStyle(
                  fontFamily: 'monospace', fontSize: 52, fontWeight: FontWeight.bold,
                  color: (_countdown ?? 99) <= 5 ? Colors.redAccent : _gold,
                ))
              else
                const SizedBox(height: 62),
              const SizedBox(height: 18),
              Container(
                width: 360,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _cardBg.withOpacity(0.92),
                  border: Border.all(color: _stoneDk, width: 3),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 0, offset: Offset(5, 5))],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Text('PLAYERS  ', style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: _gold, letterSpacing: 2)),
                      Text('${players.length}', style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: Color(0xFF8d9b8e))),
                    ]),
                    const SizedBox(height: 12),
                    const Divider(color: _stoneDk, height: 1),
                    const SizedBox(height: 12),
                    if (players.isEmpty)
                      const Text('Connecting...', style: TextStyle(color: Colors.white70, fontFamily: 'monospace')),
                    ...players.map((p) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        Text(_duckIcon(p.color), style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 8),
                        Text(p.name, style: TextStyle(
                          fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.bold,
                          color: p.id == widget.client.playerId ? _gold : Colors.white70,
                        )),
                        if (p.id == widget.client.playerId)
                          const Text('  (you)', style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFF8d9b8e))),
                      ]),
                    )),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: 360,
                child: ElevatedButton(
                  onPressed: _leave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2a3340), foregroundColor: const Color(0xFF8d9b8e),
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                    side: const BorderSide(color: _stoneDk, width: 2), padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  child: const Text('LEAVE', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, letterSpacing: 2)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LobbyPlayer {
  final String id, name, color;
  const _LobbyPlayer({required this.id, required this.name, required this.color});
}

String _duckIcon(String color) {
  return switch (color) {
    'yellow' => '🦆',
    'white' => '🦢',
    'orange' => '🦆',
    'grey' => '🦆',
    'green' => '🦆',
    _ => '🦆',
  };
}
