import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'WebSocketClient.dart';
import 'GameLogic.dart';

const _gold    = Color(0xFFd4a843);
const _stoneDk = Color(0xFF4a5568);
const _cardBg  = Color(0xFF1a1f2e);

class LobbyScreen extends StatefulWidget {
  final GameWebSocketClient client;
  final String playerName;
  const LobbyScreen({super.key, required this.client, required this.playerName});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  final List<String> _players = [];
  String _status = 'Waiting for players...';
  int _countdown = 15;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _players.add(widget.playerName);

    widget.client.messages.listen((msg) {
      if (!mounted) return;
      switch (msg.type) {
        case WsMessageType.playerList:
          final list = (msg.data['players'] as List?)
              ?.map((p) => p['name'] as String)
              .toList() ?? [];
          setState(() {
            _players
              ..clear()
              ..add(widget.playerName)
              ..addAll(list);
          });
          _checkCountdown();

        case WsMessageType.playerJoined:
          setState(() => _players.add(msg.data['name'] as String));
          _checkCountdown();

        case WsMessageType.playerLeft:
          setState(() => _players.remove(msg.data['name'] as String));
          _checkCountdown();

        case WsMessageType.error:
          setState(() => _status = 'Error: ${msg.data['message']}');

        default:
          break;
      }
    });
  }

  void _checkCountdown() {
    if (_players.length > 1 && _timer == null) {
      _startCountdown();
    } else if (_players.length <= 1 && _timer != null) {
      _stopCountdown();
    }
  }

  void _startCountdown() {
    setState(() { _countdown = 15; _status = 'Game starting soon...'; });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _countdown--);
      if (_countdown <= 0) {
        t.cancel();
        _timer = null;
        _goToGame();
      }
    });
  }

  void _stopCountdown() {
    _timer?.cancel();
    _timer = null;
    setState(() { _countdown = 15; _status = 'Waiting for players...'; });
  }

  void _goToGame() {
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => GameLogic(client: widget.client, playerName: widget.playerName),
    ));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _disconnect() {
    _timer?.cancel();
    widget.client.disconnect();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(fit: StackFit.expand, children: [
        const _CastleBg(),
        SafeArea(child: Column(children: [
          const SizedBox(height: 32),

          // Título
          const Text('WAITING ROOM', style: TextStyle(
            fontFamily: 'monospace', fontSize: 22, fontWeight: FontWeight.bold,
            color: _gold, letterSpacing: 4,
            shadows: [Shadow(color: Colors.black, blurRadius: 0, offset: Offset(3, 3))],
          )),
          const SizedBox(height: 4),
          Text(_status, style: const TextStyle(
            fontFamily: 'monospace', fontSize: 10, color: Color(0xFF8d9b8e), letterSpacing: 2,
          )),
          if (_timer != null) ...[  
            const SizedBox(height: 12),
            Text(
              '$_countdown',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: _countdown <= 5 ? Colors.redAccent : _gold,
                shadows: const [Shadow(color: Colors.black, blurRadius: 0, offset: Offset(3, 3))],
              ),
            ),
          ],

          const SizedBox(height: 32),

          // Lista de jugadores
          Expanded(child: Center(child: Container(
            width: 320,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _cardBg.withOpacity(0.88),
              border: Border.all(color: _stoneDk, width: 3),
              boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 0, offset: Offset(5, 5))],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                const Text('PLAYERS  ', style: TextStyle(
                  fontFamily: 'monospace', fontSize: 12, color: _gold, letterSpacing: 2,
                )),
                Text('${_players.length}', style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 12, color: Color(0xFF8d9b8e),
                )),
              ]),
              const SizedBox(height: 12),
              const Divider(color: _stoneDk, height: 1),
              const SizedBox(height: 12),
              ..._players.map((name) => _PlayerRow(
                name: name,
                isMe: name == widget.playerName,
              )),
              const SizedBox(height: 20),
              const _PulsingDots(),
            ]),
          ))),

          const SizedBox(height: 24),

          // Botón salir
          SizedBox(width: 320, child: ElevatedButton(
            onPressed: _disconnect,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2a3340),
              foregroundColor: const Color(0xFF8d9b8e),
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              padding: const EdgeInsets.symmetric(vertical: 12),
              elevation: 0,
              side: const BorderSide(color: _stoneDk, width: 2),
            ),
            child: const Text('LEAVE', style: TextStyle(
              fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 2,
            )),
          )),
          const SizedBox(height: 32),
        ])),
      ]),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  final String name;
  final bool isMe;
  const _PlayerRow({required this.name, required this.isMe});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      Text('🦆 ', style: const TextStyle(fontSize: 14)),
      Text(name, style: TextStyle(
        fontFamily: 'monospace', fontSize: 13,
        color: isMe ? _gold : Colors.white70,
        fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
      )),
      if (isMe) const Text('  (you)', style: TextStyle(
        fontFamily: 'monospace', fontSize: 10, color: Color(0xFF8d9b8e),
      )),
    ]),
  );
}

// ── Puntos animados de espera ────────────────────────────

class _PulsingDots extends StatefulWidget {
  const _PulsingDots();
  @override
  State<_PulsingDots> createState() => _PulsingDotsState();
}

class _PulsingDotsState extends State<_PulsingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _ctrl,
    builder: (_, __) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      for (int i = 0; i < 3; i++) ...[
        const SizedBox(width: 6),
        Opacity(
          opacity: ((sin((_ctrl.value * 2 * pi) - i * 1.0) + 1) / 2).clamp(0.2, 1.0),
          child: const Text('⚔', style: TextStyle(fontSize: 18, color: _gold)),
        ),
      ],
    ]),
  );
}

// ── Fondo (reutilizado del MainMenu) ─────────────────────

class _CastleBg extends StatefulWidget {
  const _CastleBg();
  @override
  State<_CastleBg> createState() => _CastleBgState();
}

class _CastleBgState extends State<_CastleBg> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat();
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _ctrl,
    builder: (_, __) => CustomPaint(painter: _CastlePainter(_ctrl.value), child: const SizedBox.expand()),
  );
}

class _CastlePainter extends CustomPainter {
  final double t;
  _CastlePainter(this.t);

  static final _rng   = Random(7);
  static final _stars = List.generate(80, (_) => Offset(_rng.nextDouble(), _rng.nextDouble() * 0.65));
  static final _sizes = List.generate(80, (_) => _rng.nextDouble() * 2.0 + 0.5);

  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawRect(Rect.fromLTWH(0, 0, s.width, s.height),
      Paint()..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0xFF05080f), Color(0xFF0d1526), Color(0xFF1a2035)],
        stops: [0.0, 0.55, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, s.width, s.height)));

    for (int i = 0; i < _stars.length; i++) {
      final flicker = (sin(t * 2 * pi * 1.5 + i * 1.7) + 1) / 2;
      canvas.drawCircle(
        Offset(_stars[i].dx * s.width, _stars[i].dy * s.height),
        _sizes[i],
        Paint()..color = Colors.white.withOpacity(0.2 + flicker * 0.7),
      );
    }

    final moonX = s.width * 0.82;
    final moonY = s.height * 0.12 + sin(t * 2 * pi) * 6;
    canvas.drawCircle(Offset(moonX, moonY), 36,
      Paint()..shader = RadialGradient(colors: [
        const Color(0xFFf5f0d0), const Color(0xFFd4c87a), const Color(0xFF8a7a30).withOpacity(0),
      ], stops: const [0.0, 0.55, 1.0]).createShader(Rect.fromCircle(center: Offset(moonX, moonY), radius: 36)));
    canvas.drawCircle(Offset(moonX + 10, moonY - 6), 28,
      Paint()..color = const Color(0xFF0d1526).withOpacity(0.75));

    for (int i = 0; i < 3; i++) {
      final cx = (s.width * (0.1 + i * 0.38) + t * s.width * 0.04 * (i + 1)) % (s.width + 120) - 60;
      final cy = s.height * (0.18 + i * 0.07);
      _drawCloud(canvas, cx, cy, 60.0 + i * 20, const Color(0xFF1c2540));
    }

    _drawHill(canvas, s, s.height * 0.68, s.height * 0.12, const Color(0xFF111827), 2.5, 0.0);
    _drawHill(canvas, s, s.height * 0.75, s.height * 0.10, const Color(0xFF1a2235), 1.8, 0.4);

    _drawTower(canvas, s, s.width * 0.08,  s.height * 0.42, 52, 130);
    _drawTower(canvas, s, s.width * 0.82,  s.height * 0.42, 52, 130);
    _drawTower(canvas, s, s.width * 0.18,  s.height * 0.52, 38, 100);
    _drawTower(canvas, s, s.width * 0.72,  s.height * 0.52, 38, 100);

    final wallY = s.height * 0.72;
    canvas.drawRect(Rect.fromLTWH(s.width * 0.22, wallY, s.width * 0.56, s.height * 0.28),
      Paint()..color = const Color(0xFF1e2530));
    const merlonW = 16.0; const merlonH = 14.0; const gap = 10.0;
    for (double x = s.width * 0.22; x < s.width * 0.78; x += merlonW + gap) {
      canvas.drawRect(Rect.fromLTWH(x, wallY - merlonH, merlonW, merlonH),
        Paint()..color = const Color(0xFF2a3340));
    }
    for (int i = 0; i < 3; i++) {
      final wx = s.width * 0.30 + i * s.width * 0.14;
      canvas.drawRect(Rect.fromLTWH(wx, wallY + 20, 14, 22),
        Paint()..color = const Color(0xFFd4a843).withOpacity(0.25 + sin(t * 2 * pi + i) * 0.15));
    }

    final gy = s.height * 0.88;
    final colors = [const Color(0xFF2a3340), const Color(0xFF1e2530), const Color(0xFF141b24)];
    for (int r = 0; r < 3; r++) {
      for (double x = 0; x < s.width; x += 16) {
        canvas.drawRect(Rect.fromLTWH(x + 1, gy + r * 16 + 1, 14, 14), Paint()..color = colors[r]);
      }
    }

    for (int i = 0; i < 4; i++) {
      final fx = (s.width * (i * 0.28) - t * s.width * 0.03 * (i % 2 == 0 ? 1 : -1)) % (s.width + 200) - 100;
      final fy = s.height * (0.78 + i * 0.04);
      canvas.drawOval(Rect.fromCenter(center: Offset(fx, fy), width: 280 + i * 60.0, height: 40 + i * 8.0),
        Paint()..color = const Color(0xFF8ab0c8).withOpacity(0.06 + i * 0.02));
    }
  }

  void _drawCloud(Canvas canvas, double cx, double cy, double r, Color color) {
    final p = Paint()..color = color;
    canvas.drawOval(Rect.fromCenter(center: Offset(cx, cy), width: r * 2.2, height: r * 0.7), p);
    canvas.drawCircle(Offset(cx - r * 0.4, cy), r * 0.45, p);
    canvas.drawCircle(Offset(cx + r * 0.3, cy - 4), r * 0.38, p);
  }

  void _drawTower(Canvas canvas, Size s, double x, double y, double w, double h) {
    final body = Paint()..color = const Color(0xFF1e2530);
    final dark = Paint()..color = const Color(0xFF141b24);
    final win  = Paint()..color = const Color(0xFFd4a843).withOpacity(0.3 + sin(t * 2 * pi + x) * 0.2);
    canvas.drawRect(Rect.fromLTWH(x, y, w, h), body);
    for (double mx = x; mx < x + w; mx += 12) {
      canvas.drawRect(Rect.fromLTWH(mx, y - 12, 8, 12), dark);
    }
    canvas.drawRect(Rect.fromLTWH(x + w / 2 - 6, y + h * 0.25, 12, 18), win);
    for (double ly = y + 16; ly < y + h; ly += 16) {
      canvas.drawLine(Offset(x, ly), Offset(x + w, ly), Paint()..color = const Color(0xFF0e1420)..strokeWidth = 1);
    }
  }

  void _drawHill(Canvas canvas, Size s, double baseY, double height, Color color, double freq, double phase) {
    final path = Path()..moveTo(0, s.height);
    for (double x = 0; x <= s.width; x += 4) {
      final y = baseY - (sin((x / s.width) * pi * freq + phase * pi) * height).abs();
      path.lineTo(x, y);
    }
    path.lineTo(s.width, s.height);
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_CastlePainter old) => old.t != t;
}
