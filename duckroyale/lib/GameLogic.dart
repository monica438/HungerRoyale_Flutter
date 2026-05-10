import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'WebSocketClient.dart';

// ── Modelos ──────────────────────────────────────────────

class _Zone {
  final String name;
  final double x, y, w, h;
  const _Zone(this.name, this.x, this.y, this.w, this.h);
}

class _Sprite {
  final String imageFile;
  final double x, y, w, h;
  final int frameW, frameH; // tamaño de un frame en el spritesheet
  const _Sprite(this.imageFile, this.x, this.y, this.w, this.h, this.frameW, this.frameH);
}

class _TileLayer {
  final String       sheetFile;
  final int          tileW, tileH, sheetCols;
  final List<List<int>> map;
  const _TileLayer(this.sheetFile, this.tileW, this.tileH, this.sheetCols, this.map);
}

// ── Constantes del nivel ─────────────────────────────────
// 47 cols × 24px = 1128,  23 rows × 24px = 552
const double _worldW    = 1128.0;
const double _worldH    = 552.0;
const int    _tileSize  = 24;
const int    _sheetCols = 14;   // 347px / 24px = 14 columnas completas

// ── GameLogic ────────────────────────────────────────────

class GameLogic extends StatefulWidget {
  final GameWebSocketClient client;
  final String playerName;
  const GameLogic({super.key, required this.client, required this.playerName});

  @override
  State<GameLogic> createState() => _GameLogicState();
}

class _GameLogicState extends State<GameLogic> {
  bool    _loading = true;
  String? _error;

  List<_TileLayer>        _tileLayers = [];
  List<_Sprite>           _sprites    = [];
  List<_Zone>             _zones      = [];
  ui.Image?               _bgImage;
  final Map<String, ui.Image> _images = {};

  @override
  void initState() {
    super.initState();
    _loadLevel();
  }

  // key en _images = path relativo sin 'assets/' (ej. 'media/tilsets_2.png')
  Future<ui.Image> _loadImage(String relativePath) async {
    if (_images.containsKey(relativePath)) return _images[relativePath]!;
    final data  = await rootBundle.load('assets/$relativePath');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final img   = (await codec.getNextFrame()).image;
    _images[relativePath] = img;
    return img;
  }

  Future<void> _loadLevel() async {
    try {
      // ── game_data.json ──
      final gd    = jsonDecode(await rootBundle.loadString('assets/game_data.json')) as Map<String, dynamic>;
      final level = (gd['levels'] as List).first as Map<String, dynamic>;

      // ── Zonas ──
      final zData = jsonDecode(await rootBundle.loadString('assets/zones/level_000_zones.json')) as Map<String, dynamic>;
      _zones = (zData['zones'] as List).map((z) => _Zone(
        z['name'] as String,
        (z['x'] as num).toDouble(), (z['y'] as num).toDouble(),
        (z['width'] as num).toDouble(), (z['height'] as num).toDouble(),
      )).toList();

      // ── Capas de tiles ──
      final layers = (level['layers'] as List).cast<Map<String, dynamic>>();
      _tileLayers = [];
      for (final layer in layers) {
        if (!(layer['visible'] as bool)) continue;
        final sheetFile = layer['tilesSheetFile'] as String;
        final tileW     = (layer['tilesWidth']  as num).toInt();
        final tileH     = (layer['tilesHeight'] as num).toInt();

        // La capa de background (background_2.png) es una imagen única, no un tilemap de tiles
        if (tileW > 100) {
          _bgImage = await _loadImage(sheetFile);
          continue;
        }

        final mapRaw = jsonDecode(await rootBundle.loadString('assets/${layer['tileMapFile']}')) as Map<String, dynamic>;
        final rows   = (mapRaw['tileMap'] as List)
            .map((r) => (r as List).map((v) => v as int).toList())
            .toList();

        await _loadImage(sheetFile);
        _tileLayers.add(_TileLayer(sheetFile, tileW, tileH, _sheetCols, rows));
      }

      // ── Sprites decorativos ──
      // Construir mapa fileName -> tileWidth/tileHeight desde mediaAssets
      final mediaAssets = (gd['mediaAssets'] as List).cast<Map<String, dynamic>>();
      final mediaMap = <String, Map<String, dynamic>>{
        for (final m in mediaAssets) m['fileName'] as String: m,
      };

      _sprites = (level['sprites'] as List).map((s) {
        final file = s['imageFile'] as String;
        final ma   = mediaMap[file];
        final fw   = (ma?['tileWidth']  as num?)?.toInt() ?? (s['width']  as num).toInt();
        final fh   = (ma?['tileHeight'] as num?)?.toInt() ?? (s['height'] as num).toInt();
        return _Sprite(
          file,
          (s['x'] as num).toDouble(), (s['y'] as num).toDouble(),
          (s['width']  as num).toDouble(), (s['height'] as num).toDouble(),
          fw, fh,
        );
      }).toList();

      // Pre-cargar imágenes de sprites
      await Future.wait(_sprites.map((s) => _loadImage(s.imageFile)));

      setState(() => _loading = false);
    } catch (e, st) {
      debugPrint('$e\n$st');
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _LoadingScreen();
    if (_error != null) return _ErrorScreen(message: _error!);

    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(builder: (_, box) {
        // Escala uniforme manteniendo ratio del mundo
        final scale = (box.maxWidth / _worldW) < (box.maxHeight / _worldH)
            ? box.maxWidth  / _worldW
            : box.maxHeight / _worldH;
        final offX = (box.maxWidth  - _worldW * scale) / 2;
        final offY = (box.maxHeight - _worldH * scale) / 2;

        return Stack(children: [
          Positioned(
            left: offX, top: offY,
            width: _worldW * scale, height: _worldH * scale,
            child: CustomPaint(
              size: Size(_worldW * scale, _worldH * scale),
              painter: _LevelPainter(
                bgImage:    _bgImage,
                tileLayers: _tileLayers,
                sprites:    _sprites,
                zones:      _zones,
                images:     _images,
                scale:      scale,
              ),
            ),
          ),
        ]);
      }),
    );
  }
}

// ── Painter ──────────────────────────────────────────────

class _LevelPainter extends CustomPainter {
  final ui.Image?             bgImage;
  final List<_TileLayer>      tileLayers;
  final List<_Sprite>         sprites;
  final List<_Zone>           zones;
  final Map<String, ui.Image> images;
  final double                scale;

  const _LevelPainter({
    required this.bgImage,
    required this.tileLayers,
    required this.sprites,
    required this.zones,
    required this.images,
    required this.scale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Aplicar escala una sola vez: todo lo demás usa coordenadas de mundo
    canvas.save();
    canvas.scale(scale, scale);

    // 1. Fondo
    if (bgImage != null) {
      canvas.drawImageRect(
        bgImage!,
        Rect.fromLTWH(0, 0, bgImage!.width.toDouble(), bgImage!.height.toDouble()),
        Rect.fromLTWH(0, 0, _worldW, _worldH),
        Paint(),
      );
    }

    // 2. Capas de tiles
    final tilePaint = Paint()..filterQuality = FilterQuality.none;
    for (final layer in tileLayers) {
      final sheet = images[layer.sheetFile];
      if (sheet == null) continue;

      for (int row = 0; row < layer.map.length; row++) {
        for (int col = 0; col < layer.map[row].length; col++) {
          final id = layer.map[row][col];
          if (id < 0) continue;

          final srcCol = id % layer.sheetCols;
          final srcRow = id ~/ layer.sheetCols;

          final src = Rect.fromLTWH(
            (srcCol * layer.tileW).toDouble(),
            (srcRow * layer.tileH).toDouble(),
            layer.tileW.toDouble(),
            layer.tileH.toDouble(),
          );
          final dst = Rect.fromLTWH(
            (col * layer.tileW).toDouble(),
            (row * layer.tileH).toDouble(),
            layer.tileW.toDouble(),
            layer.tileH.toDouble(),
          );
          canvas.drawImageRect(sheet, src, dst, tilePaint);
        }
      }
    }

    // 3. Sprites decorativos — solo primer frame, x/y = centro del sprite
    for (final sprite in sprites) {
      final img = images[sprite.imageFile];
      if (img == null) continue;
      final src = Rect.fromLTWH(0, 0, sprite.frameW.toDouble(), sprite.frameH.toDouble());
      final dst = Rect.fromLTWH(
        sprite.x - sprite.w / 2,
        sprite.y - sprite.h / 2,
        sprite.w,
        sprite.h,
      );
      canvas.drawImageRect(img, src, dst, Paint());
    }

    // 4. Zonas — eliminadas (son colisiones, no deben verse)

    canvas.restore();
  }

  @override
  bool shouldRepaint(_LevelPainter old) => false;
}

// ── Pantallas auxiliares ─────────────────────────────────

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();
  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: Color(0xFF05080f),
    body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      CircularProgressIndicator(color: Color(0xFFd4a843)),
      SizedBox(height: 20),
      Text('Loading level...', style: TextStyle(
        fontFamily: 'monospace', color: Color(0xFFd4a843), fontSize: 14, letterSpacing: 2,
      )),
    ])),
  );
}

class _ErrorScreen extends StatelessWidget {
  final String message;
  const _ErrorScreen({required this.message});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF05080f),
    body: Center(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text('Error:\n$message', textAlign: TextAlign.center,
        style: const TextStyle(fontFamily: 'monospace', color: Colors.redAccent, fontSize: 12)),
    )),
  );
}
