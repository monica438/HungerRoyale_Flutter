import 'dart:math';
import 'package:flutter/material.dart';
import 'WebSocketClient.dart';
import 'LobbyScreen.dart';

// ── Paleta ──────────────────────────────────────────────
const _stone   = Color(0xFF8d9b8e);
const _stoneDk = Color(0xFF4a5568);
const _gold    = Color(0xFFd4a843);
const _cardBg  = Color(0xFF1a1f2e);

class MainMenu extends StatefulWidget {
  const MainMenu({super.key});
  @override
  State<MainMenu> createState() => _MainMenuState();
}

class _MainMenuState extends State<MainMenu> {
  final _nameCtrl   = TextEditingController();
  final _serverCtrl = TextEditingController(text: 'wss://ltorocordero.ieti.site');
  bool    _connecting = false;
  String? _error;

  Future<void> _connect() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) { setState(() => _error = 'Enter a player name'); return; }
    setState(() { _connecting = true; _error = null; });
    try {
      final client = GameWebSocketClient(url: _serverCtrl.text.trim(), playerName: name);
      await client.connect();
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => LobbyScreen(client: client, playerName: name),
      ));
      if (mounted) setState(() => _connecting = false);
    } catch (e) {
      if (mounted) setState(() { _error = 'Connection failed: $e'; _connecting = false; });
    }
  }

  @override
  void dispose() { _nameCtrl.dispose(); _serverCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(fit: StackFit.expand, children: [
        const _CastleBg(),
        Center(child: SingleChildScrollView(child: _PixelCard(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('DUCK ROYALE', style: TextStyle(
              fontFamily: 'monospace', fontSize: 28, fontWeight: FontWeight.bold,
              color: _gold, letterSpacing: 4,
              shadows: [Shadow(color: Colors.black, blurRadius: 0, offset: Offset(3, 3))],
            )),
            const SizedBox(height: 6),
            const Text('⚔  BATTLE FOR THE CASTLE  ⚔', style: TextStyle(
              fontFamily: 'monospace', fontSize: 10, color: _stone, letterSpacing: 2,
            )),
            const SizedBox(height: 28),
            _PixelTextField(controller: _nameCtrl,   hint: 'Player Name'),
            const SizedBox(height: 12),
            _PixelTextField(controller: _serverCtrl, hint: 'Server URL'),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: Colors.redAccent, fontFamily: 'monospace', fontSize: 11)),
            ],
            const SizedBox(height: 24),
            _PixelButton(
              label: _connecting ? 'CONNECTING...' : 'JOIN BATTLE',
              onPressed: _connecting ? null : _connect,
            ),
          ],
        )))),
      ]),
    );
  }
}

// ── UI Widgets ───────────────────────────────────────────

class _PixelCard extends StatelessWidget {
  final Widget child;
  const _PixelCard({required this.child});
  @override
  Widget build(BuildContext context) => Container(
    width: 320,
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      color: _cardBg.withOpacity(0.88),
      border: Border.all(color: _stoneDk, width: 3),
      boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 0, offset: Offset(5, 5))],
    ),
    child: child,
  );
}

class _PixelTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  const _PixelTextField({required this.controller, required this.hint});
  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white38, fontFamily: 'monospace'),
      filled: true,
      fillColor: const Color(0xFF0e1117),
      enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: _stoneDk, width: 2), borderRadius: BorderRadius.zero),
      focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: _stone,   width: 2), borderRadius: BorderRadius.zero),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
  );
}

class _PixelButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const _PixelButton({required this.label, this.onPressed});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: _gold,
        foregroundColor: Colors.black,
        disabledBackgroundColor: _gold.withOpacity(0.35),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        padding: const EdgeInsets.symmetric(vertical: 14),
        elevation: 0,
        side: const BorderSide(color: Colors.black, width: 2),
      ),
      child: Text(label, style: const TextStyle(
        fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 2,
      )),
    ),
  );
}

// ── Fondo animado ────────────────────────────────────────

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
    // ── Cielo nocturno ──
    canvas.drawRect(Rect.fromLTWH(0, 0, s.width, s.height),
      Paint()..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0xFF05080f), Color(0xFF0d1526), Color(0xFF1a2035)],
        stops: [0.0, 0.55, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, s.width, s.height)));

    // ── Estrellas ──
    for (int i = 0; i < _stars.length; i++) {
      final flicker = (sin(t * 2 * pi * 1.5 + i * 1.7) + 1) / 2;
      canvas.drawCircle(
        Offset(_stars[i].dx * s.width, _stars[i].dy * s.height),
        _sizes[i],
        Paint()..color = Colors.white.withOpacity(0.2 + flicker * 0.7),
      );
    }

    // ── Luna ──
    final moonX = s.width * 0.82;
    final moonY = s.height * 0.12 + sin(t * 2 * pi) * 6;
    canvas.drawCircle(Offset(moonX, moonY), 36,
      Paint()..shader = RadialGradient(colors: [
        const Color(0xFFf5f0d0), const Color(0xFFd4c87a), const Color(0xFF8a7a30).withOpacity(0),
      ], stops: const [0.0, 0.55, 1.0]).createShader(Rect.fromCircle(center: Offset(moonX, moonY), radius: 36)));
    // sombra de luna (crescent)
    canvas.drawCircle(Offset(moonX + 10, moonY - 6), 28,
      Paint()..color = const Color(0xFF0d1526).withOpacity(0.75));

    // ── Nubes oscuras ──
    for (int i = 0; i < 3; i++) {
      final cx = (s.width * (0.1 + i * 0.38) + t * s.width * 0.04 * (i + 1)) % (s.width + 120) - 60;
      final cy = s.height * (0.18 + i * 0.07);
      _drawCloud(canvas, cx, cy, 60.0 + i * 20, const Color(0xFF1c2540));
    }

    // ── Colinas lejanas ──
    _drawHill(canvas, s, s.height * 0.68, s.height * 0.12, const Color(0xFF111827), 2.5, 0.0);
    _drawHill(canvas, s, s.height * 0.75, s.height * 0.10, const Color(0xFF1a2235), 1.8, 0.4);

    // ── Torres del castillo (izq y der) ──
    _drawTower(canvas, s, s.width * 0.08,  s.height * 0.42, 52, 130);
    _drawTower(canvas, s, s.width * 0.82,  s.height * 0.42, 52, 130);
    _drawTower(canvas, s, s.width * 0.18,  s.height * 0.52, 38, 100);
    _drawTower(canvas, s, s.width * 0.72,  s.height * 0.52, 38, 100);

    // ── Muralla central ──
    final wallY = s.height * 0.72;
    canvas.drawRect(Rect.fromLTWH(s.width * 0.22, wallY, s.width * 0.56, s.height * 0.28),
      Paint()..color = const Color(0xFF1e2530));
    // almenas
    const merlonW = 16.0; const merlonH = 14.0; const gap = 10.0;
    for (double x = s.width * 0.22; x < s.width * 0.78; x += merlonW + gap) {
      canvas.drawRect(Rect.fromLTWH(x, wallY - merlonH, merlonW, merlonH),
        Paint()..color = const Color(0xFF2a3340));
    }
    // ventanas de la muralla
    for (int i = 0; i < 3; i++) {
      final wx = s.width * 0.30 + i * s.width * 0.14;
      canvas.drawRect(Rect.fromLTWH(wx, wallY + 20, 14, 22),
        Paint()..color = const Color(0xFFd4a843).withOpacity(0.25 + sin(t * 2 * pi + i) * 0.15));
    }

    // ── Suelo pixelado ──
    final gy = s.height * 0.88;
    final colors = [const Color(0xFF2a3340), const Color(0xFF1e2530), const Color(0xFF141b24)];
    for (int r = 0; r < 3; r++) {
      for (double x = 0; x < s.width; x += 16) {
        canvas.drawRect(Rect.fromLTWH(x + 1, gy + r * 16 + 1, 14, 14),
          Paint()..color = colors[r]);
      }
    }

    // ── Niebla baja ──
    for (int i = 0; i < 4; i++) {
      final fx = (s.width * (i * 0.28) - t * s.width * 0.03 * (i % 2 == 0 ? 1 : -1)) % (s.width + 200) - 100;
      final fy = s.height * (0.78 + i * 0.04);
      canvas.drawOval(
        Rect.fromCenter(center: Offset(fx, fy), width: 280 + i * 60.0, height: 40 + i * 8.0),
        Paint()..color = const Color(0xFF8ab0c8).withOpacity(0.06 + i * 0.02),
      );
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
    // almenas de la torre
    for (double mx = x; mx < x + w; mx += 12) {
      canvas.drawRect(Rect.fromLTWH(mx, y - 12, 8, 12), dark);
    }
    // ventana
    canvas.drawRect(Rect.fromLTWH(x + w / 2 - 6, y + h * 0.25, 12, 18), win);
    // líneas de piedra
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
