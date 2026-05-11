import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'WebSocketClient.dart';

class _Zone {
  final String name;
  final double x, y, w, h;
  const _Zone(this.name, this.x, this.y, this.w, this.h);
}

class _Sprite {
  final String imageFile;
  final String type;
  final double x, y, w, h;
  final int frameW, frameH;
  const _Sprite(
    this.imageFile,
    this.type,
    this.x,
    this.y,
    this.w,
    this.h,
    this.frameW,
    this.frameH,
  );
}

class _TileLayer {
  final String sheetFile;
  final int tileW, tileH, sheetCols;
  final List<List<int>> map;
  const _TileLayer(
    this.sheetFile,
    this.tileW,
    this.tileH,
    this.sheetCols,
    this.map,
  );
}

class _AnimDef {
  final String name, mediaFile;
  final int startFrame, endFrame;
  final double fps;
  final bool loop;
  const _AnimDef(
    this.name,
    this.mediaFile,
    this.startFrame,
    this.endFrame,
    this.fps,
    this.loop,
  );
  int get frameCount => endFrame - startFrame + 1;
}

class _RemotePlayer {
  final String id, name, color, facing;
  final double x, y, vx, vy;
  final int hp, maxHp, score;
  final bool hasSword, alive, attacking, invulnerable;
  const _RemotePlayer({
    required this.id,
    required this.name,
    required this.color,
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.facing,
    required this.hp,
    required this.maxHp,
    required this.hasSword,
    required this.alive,
    required this.attacking,
    required this.invulnerable,
    required this.score,
  });

  factory _RemotePlayer.fromJson(Map<String, dynamic> j) => _RemotePlayer(
    id: j['id'] as String,
    name: j['name'] as String? ?? 'Duck',
    color: j['color'] as String? ?? 'yellow',
    x: (j['x'] as num).toDouble(),
    y: (j['y'] as num).toDouble(),
    vx: (j['vx'] as num? ?? 0).toDouble(),
    vy: (j['vy'] as num? ?? 0).toDouble(),
    facing: j['facing'] as String? ?? 'right',
    hp: (j['hp'] as num? ?? 3).toInt(),
    maxHp: (j['maxHp'] as num? ?? 3).toInt(),
    hasSword: j['hasSword'] as bool? ?? false,
    alive: j['alive'] as bool? ?? true,
    attacking: j['attacking'] as bool? ?? false,
    invulnerable: j['invulnerable'] as bool? ?? false,
    score: (j['score'] as num? ?? 0).toInt(),
  );
}

class _ItemState {
  final String id;
  final double x, y, w, h;
  final bool active;
  const _ItemState(this.id, this.x, this.y, this.w, this.h, this.active);
  factory _ItemState.fromJson(Map<String, dynamic> j) => _ItemState(
    j['id'] as String,
    (j['x'] as num).toDouble(),
    (j['y'] as num).toDouble(),
    (j['w'] as num).toDouble(),
    (j['h'] as num).toDouble(),
    j['active'] as bool? ?? true,
  );
}

const double _worldW = 1128.0;
const double _worldH = 552.0;
const int _sheetCols = 14;

class GameLogic extends StatefulWidget {
  final GameWebSocketClient client;
  final String playerName;
  const GameLogic({super.key, required this.client, required this.playerName});

  @override
  State<GameLogic> createState() => _GameLogicState();
}

class _GameLogicState extends State<GameLogic>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  String? _error;

  List<_TileLayer> _tileLayers = [];
  List<_Sprite> _staticSprites = [];
  List<_Zone> _zones = [];
  final Map<String, _AnimDef> _animations = {};
  final Map<String, Size> _frameSizes = {};
  ui.Image? _bgImage;
  final Map<String, ui.Image> _images = {};

  final Map<String, _RemotePlayer> _players = {};
  final Map<String, _ItemState> _swords = {};
  final Map<String, _ItemState> _hearts = {};

  String _phase = 'playing';
  String? _winnerName;
  bool _returningToLobby = false;

  StreamSubscription? _wsSub;
  Ticker? _ticker;
  double _elapsed = 0;
  bool _left = false, _right = false, _jump = false, _attack = false;
  DateTime _lastInputSent = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _loadLevel();
    _wsSub = widget.client.messages.listen(_onWsMessage);
    _ticker = createTicker((elapsed) {
      _elapsed = elapsed.inMilliseconds / 1000.0;
      if (mounted) setState(() {});
    })..start();
  }

  Future<ui.Image> _loadImage(String relativePath) async {
    if (_images.containsKey(relativePath)) return _images[relativePath]!;
    final data = await rootBundle.load('assets/$relativePath');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final img = (await codec.getNextFrame()).image;
    _images[relativePath] = img;
    return img;
  }

  void _registerAnimation(
    String name,
    String mediaFile,
    int startFrame,
    int endFrame,
    double fps, {
    bool loop = true,
  }) {
    _animations[name] = _AnimDef(
      name,
      mediaFile,
      startFrame,
      endFrame,
      fps,
      loop,
    );
  }

  Future<void> _loadAnimationsWithFallback(
    Map<String, dynamic> gameData,
  ) async {
    _animations.clear();

    try {
      final animationsPath =
          (gameData['animationsFile'] as String?) ??
          'animations/animations.json';
      final animData =
          jsonDecode(await rootBundle.loadString('assets/$animationsPath'))
              as Map<String, dynamic>;
      for (final a
          in (animData['animations'] as List).cast<Map<String, dynamic>>()) {
        _registerAnimation(
          a['name'] as String,
          a['mediaFile'] as String,
          (a['startFrame'] as num).toInt(),
          (a['endFrame'] as num).toInt(),
          (a['fps'] as num).toDouble(),
          loop: a['loop'] as bool? ?? true,
        );
      }
    } catch (e) {
      debugPrint(
        'No se ha podido cargar el archivo de animaciones definido en game_data.json. Uso animaciones fallback: $e',
      );
      _registerFallbackAnimations();
    }

    final files = _animations.values.map((a) => a.mediaFile).toSet();
    for (final file in files) {
      await _loadImage(file);
    }
  }

  void _registerFallbackAnimations() {
    const colors = ['yellow', 'white', 'orange', 'grey', 'green'];
    const stopFiles = {
      'yellow': 'media/stop_yellow_duck.png',
      'white': 'media/stop_white_duck.png',
      'orange': 'media/stop_orange_duck.png',
      'grey': 'media/stop_grey_duck.png',
      'green': 'media/stop_green_duck.png',
    };
    const rightFiles = {
      'yellow': 'media/right_yellow_duck.png',
      'white': 'media/right_white_duck.png',
      'orange': 'media/orange_duck_right.png',
      'grey': 'media/right_grey_duck.png',
      'green': 'media/right_green_duck.png',
    };
    const leftFiles = {
      'yellow': 'media/left_yellow_duck.png',
      'white': 'media/left_white_duck.png',
      'orange': 'media/orange_duck_left.png',
      'grey': 'media/left_grey_duck.png',
      'green': 'media/left_green_duck.png',
    };
    const dieFiles = {
      'yellow': 'media/die_yellow_duck.png',
      'white': 'media/die_white_duck.png',
      'orange': 'media/die_orange_duck.png',
      'grey': 'media/die_duck_grey.png',
      'green': 'media/die_duck_green (1).png',
    };

    for (final color in colors) {
      _registerAnimation(
        'anim_stop_${color}_duck',
        stopFiles[color]!,
        0,
        1,
        7.0,
      );
      _registerAnimation(
        'anim_right_${color}_duck',
        rightFiles[color]!,
        0,
        3,
        7.5,
      );
      _registerAnimation(
        'anim_left_${color}_duck',
        leftFiles[color]!,
        0,
        3,
        7.5,
      );
      _registerAnimation(
        color == 'green' ? 'anim_die_duck_green' : 'anim_die_${color}_duck',
        dieFiles[color]!,
        0,
        1,
        7.0,
        loop: false,
      );
      _registerAnimation(
        'anim_swd_left_$color',
        'media/sword_left_duck_$color.png',
        1,
        3,
        8.0,
      );
      _registerAnimation(
        'anim_swd_right_$color',
        'media/sword_right_duck_$color.png',
        0,
        2,
        8.0,
      );
    }
    _registerAnimation('anim_swordd', 'media/swoooord_2.png', 0, 2, 7.0);
    _registerAnimation('heart_anim', 'media/corazon_vida_3.png', 0, 3, 7.0);
  }

  Future<void> _loadLevel() async {
    try {
      final gd =
          jsonDecode(await rootBundle.loadString('assets/game_data.json'))
              as Map<String, dynamic>;
      final level = (gd['levels'] as List).first as Map<String, dynamic>;
      final mediaAssets = (gd['mediaAssets'] as List)
          .cast<Map<String, dynamic>>();
      final mediaMap = <String, Map<String, dynamic>>{
        for (final m in mediaAssets) m['fileName'] as String: m,
      };
      _frameSizes
        ..clear()
        ..addEntries(
          mediaAssets.map(
            (m) => MapEntry(
              m['fileName'] as String,
              Size(
                (m['tileWidth'] as num).toDouble(),
                (m['tileHeight'] as num).toDouble(),
              ),
            ),
          ),
        );

      await _loadAnimationsWithFallback(gd);

      final zData =
          jsonDecode(
                await rootBundle.loadString(
                  'assets/zones/level_000_zones.json',
                ),
              )
              as Map<String, dynamic>;
      _zones = (zData['zones'] as List)
          .map(
            (z) => _Zone(
              z['name'] as String,
              (z['x'] as num).toDouble(),
              (z['y'] as num).toDouble(),
              (z['width'] as num).toDouble(),
              (z['height'] as num).toDouble(),
            ),
          )
          .toList();

      _tileLayers = [];
      for (final layer
          in (level['layers'] as List).cast<Map<String, dynamic>>()) {
        if (!(layer['visible'] as bool)) continue;
        final sheetFile = layer['tilesSheetFile'] as String;
        final tileW = (layer['tilesWidth'] as num).toInt();
        final tileH = (layer['tilesHeight'] as num).toInt();
        if (tileW > 100) {
          _bgImage = await _loadImage(sheetFile);
          continue;
        }
        final mapRaw =
            jsonDecode(
                  await rootBundle.loadString('assets/${layer['tileMapFile']}'),
                )
                as Map<String, dynamic>;
        final rows = (mapRaw['tileMap'] as List)
            .map((r) => (r as List).map((v) => v as int).toList())
            .toList();
        await _loadImage(sheetFile);
        _tileLayers.add(_TileLayer(sheetFile, tileW, tileH, _sheetCols, rows));
      }

      _staticSprites = (level['sprites'] as List)
          .map((s) {
            final file = s['imageFile'] as String;
            final ma = mediaMap[file];
            final fw =
                (ma?['tileWidth'] as num?)?.toInt() ??
                (s['width'] as num).toInt();
            final fh =
                (ma?['tileHeight'] as num?)?.toInt() ??
                (s['height'] as num).toInt();
            return _Sprite(
              file,
              s['type'] as String? ?? s['name'] as String,
              (s['x'] as num).toDouble(),
              (s['y'] as num).toDouble(),
              (s['width'] as num).toDouble(),
              (s['height'] as num).toDouble(),
              fw,
              fh,
            );
          })
          .where(
            (s) =>
                !s.type.contains('duck') &&
                !s.type.contains('sword') &&
                !s.type.contains('heart'),
          )
          .toList();

      await Future.wait(_staticSprites.map((s) => _loadImage(s.imageFile)));
      if (mounted) setState(() => _loading = false);
    } catch (e, st) {
      debugPrint('$e\n$st');
      if (mounted)
        setState(() {
          _loading = false;
          _error = e.toString();
        });
    }
  }

  void _onWsMessage(WsMessage msg) {
    if (!mounted) return;
    if (msg.type == WsMessageType.state) {
      final lobby =
          (msg.data['lobby'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final newPhase = lobby['phase'] as String? ?? _phase;
      final winner = (lobby['winner'] as Map?)?.cast<String, dynamic>();
      final players = (msg.data['players'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(_RemotePlayer.fromJson);
      final swords = (msg.data['swords'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(_ItemState.fromJson);
      final hearts = (msg.data['hearts'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(_ItemState.fromJson);
      setState(() {
        _phase = newPhase;
        _winnerName = winner?['name'] as String?;
        _players
          ..clear()
          ..addEntries(players.map((p) => MapEntry(p.id, p)));
        _swords
          ..clear()
          ..addEntries(swords.map((i) => MapEntry(i.id, i)));
        _hearts
          ..clear()
          ..addEntries(hearts.map((i) => MapEntry(i.id, i)));
      });

      if ((newPhase == 'waiting' || newPhase == 'countdown') &&
          !_returningToLobby) {
        _returningToLobby = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Navigator.of(context).pushReplacementNamed(
            '/lobby',
            arguments: {
              'client': widget.client,
              'playerName': widget.playerName,
            },
          );
        });
      }
    } else if (msg.type == WsMessageType.error) {
      setState(
        () => _error = msg.data['message']?.toString() ?? 'Connection error',
      );
    }
  }

  void _setInput({bool? left, bool? right, bool? jump, bool? attack}) {
    _left = left ?? _left;
    _right = right ?? _right;
    _jump = jump ?? _jump;
    _attack = attack ?? _attack;
    _sendInput(force: true);
  }

  void _sendInput({bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastInputSent).inMilliseconds < 50) return;
    _lastInputSent = now;
    widget.client.sendInput(
      left: _left,
      right: _right,
      jump: _jump,
      attack: _attack,
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final down = event is KeyDownEvent || event is KeyRepeatEvent;
    final up = event is KeyUpEvent;
    if (!down && !up) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.keyA || key == LogicalKeyboardKey.arrowLeft)
      _setInput(left: down);
    if (key == LogicalKeyboardKey.keyD || key == LogicalKeyboardKey.arrowRight)
      _setInput(right: down);
    if (key == LogicalKeyboardKey.keyW ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.space)
      _setInput(jump: down);
    if (key == LogicalKeyboardKey.keyJ ||
        key == LogicalKeyboardKey.keyK ||
        key == LogicalKeyboardKey.enter)
      _setInput(attack: down);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _LoadingScreen();
    if (_error != null) return _ErrorScreen(message: _error!);

    final me = widget.client.playerId == null
        ? null
        : _players[widget.client.playerId];

    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: LayoutBuilder(
          builder: (_, box) {
            final scale = (box.maxWidth / _worldW) < (box.maxHeight / _worldH)
                ? box.maxWidth / _worldW
                : box.maxHeight / _worldH;
            final offX = (box.maxWidth - _worldW * scale) / 2;
            final offY = (box.maxHeight - _worldH * scale) / 2;

            return Stack(
              children: [
                Positioned(
                  left: offX,
                  top: offY,
                  width: _worldW * scale,
                  height: _worldH * scale,
                  child: CustomPaint(
                    size: Size(_worldW * scale, _worldH * scale),
                    painter: _LevelPainter(
                      bgImage: _bgImage,
                      tileLayers: _tileLayers,
                      staticSprites: _staticSprites,
                      zones: _zones,
                      images: _images,
                      animations: _animations,
                      frameSizes: _frameSizes,
                      players: _players.values.toList(),
                      swords: _swords.values.toList(),
                      hearts: _hearts.values.toList(),
                      myId: widget.client.playerId,
                      elapsed: _elapsed,
                      scale: scale,
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  top: 16,
                  child: _Hud(me: me, players: _players.values.toList()),
                ),
                if (_phase == 'ended')
                  Positioned.fill(
                    child: _GameOverOverlay(winnerName: _winnerName),
                  ),
                Positioned(
                  left: 18,
                  bottom: 18,
                  child: _TouchButton(
                    label: '◀',
                    onDown: () => _setInput(left: true),
                    onUp: () => _setInput(left: false),
                  ),
                ),
                Positioned(
                  left: 86,
                  bottom: 18,
                  child: _TouchButton(
                    label: '▶',
                    onDown: () => _setInput(right: true),
                    onUp: () => _setInput(right: false),
                  ),
                ),
                Positioned(
                  right: 96,
                  bottom: 18,
                  child: _TouchButton(
                    label: 'JUMP',
                    onDown: () => _setInput(jump: true),
                    onUp: () => _setInput(jump: false),
                    wide: true,
                  ),
                ),
                Positioned(
                  right: 18,
                  bottom: 18,
                  child: _TouchButton(
                    label: 'ATK',
                    onDown: () => _setInput(attack: true),
                    onUp: () => _setInput(attack: false),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _wsSub?.cancel();
    widget.client.sendInput(
      left: false,
      right: false,
      jump: false,
      attack: false,
    );
    super.dispose();
  }
}

class _LevelPainter extends CustomPainter {
  final ui.Image? bgImage;
  final List<_TileLayer> tileLayers;
  final List<_Sprite> staticSprites;
  final List<_Zone> zones;
  final Map<String, ui.Image> images;
  final Map<String, _AnimDef> animations;
  final Map<String, Size> frameSizes;
  final List<_RemotePlayer> players;
  final List<_ItemState> swords;
  final List<_ItemState> hearts;
  final String? myId;
  final double elapsed;
  final double scale;

  const _LevelPainter({
    required this.bgImage,
    required this.tileLayers,
    required this.staticSprites,
    required this.zones,
    required this.images,
    required this.animations,
    required this.frameSizes,
    required this.players,
    required this.swords,
    required this.hearts,
    required this.myId,
    required this.elapsed,
    required this.scale,
  });

  int _frame(_AnimDef def) {
    final raw = (elapsed * def.fps).floor();
    if (def.loop) return def.startFrame + (raw % def.frameCount);
    return def.startFrame + raw.clamp(0, def.frameCount - 1);
  }

  void _drawAnim(
    Canvas canvas,
    String animName,
    double x,
    double y,
    double w,
    double h, {
    bool flash = false,
  }) {
    final def = animations[animName];
    if (def == null) return;
    final img = images[def.mediaFile];
    if (img == null) return;

    // El tamaño de cada frame NO se calcula dividiendo el ancho de la imagen.
    // Viene de game_data.json -> mediaAssets -> tileWidth/tileHeight. Así evitamos
    // que un frame incluya varios frames del spritesheet cuando endFrame no coincide
    // con el total real de columnas del PNG.
    final frameSize =
        frameSizes[def.mediaFile] ??
        Size(img.width.toDouble(), img.height.toDouble());
    final frameW = frameSize.width;
    final frameH = frameSize.height;
    final frame = _frame(def);
    final src = Rect.fromLTWH(frame * frameW, 0, frameW, frameH);

    final paint = Paint()..filterQuality = FilterQuality.none;
    if (flash && (elapsed * 10).floor().isEven)
      paint.colorFilter = const ColorFilter.mode(
        Colors.white70,
        BlendMode.srcATop,
      );
    canvas.drawImageRect(
      img,
      src,
      Rect.fromLTWH(x - w / 2, y - h, w, h),
      paint,
    );
  }

  String _animFor(_RemotePlayer p) {
    if (!p.alive) {
      const die = {
        'yellow': 'anim_die_yellow_duck',
        'white': 'anim_die_white_duck',
        'orange': 'anim_die_orange_duck',
        'grey': 'anim_die_grey_duck',
        'green': 'anim_die_duck_green',
      };
      return die[p.color] ?? 'anim_die_yellow_duck';
    }
    if (p.hasSword) return 'anim_swd_${p.facing}_${p.color}';
    if (p.vx.abs() < 1) return 'anim_stop_${p.color}_duck';
    return 'anim_${p.facing}_${p.color}_duck';
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale, scale);

    if (bgImage != null) {
      canvas.drawImageRect(
        bgImage!,
        Rect.fromLTWH(
          0,
          0,
          bgImage!.width.toDouble(),
          bgImage!.height.toDouble(),
        ),
        Rect.fromLTWH(0, 0, _worldW, _worldH),
        Paint(),
      );
    }

    final tilePaint = Paint()..filterQuality = FilterQuality.none;
    for (final layer in tileLayers) {
      final sheet = images[layer.sheetFile];
      if (sheet == null) continue;
      for (var row = 0; row < layer.map.length; row++) {
        for (var col = 0; col < layer.map[row].length; col++) {
          final id = layer.map[row][col];
          if (id < 0) continue;
          final src = Rect.fromLTWH(
            (id % layer.sheetCols * layer.tileW).toDouble(),
            (id ~/ layer.sheetCols * layer.tileH).toDouble(),
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

    for (final sprite in staticSprites) {
      final img = images[sprite.imageFile];
      if (img == null) continue;
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, sprite.frameW.toDouble(), sprite.frameH.toDouble()),
        Rect.fromLTWH(
          sprite.x - sprite.w / 2,
          sprite.y - sprite.h / 2,
          sprite.w,
          sprite.h,
        ),
        Paint(),
      );
    }

    for (final s in swords.where((s) => s.active)) {
      _drawAnim(canvas, 'anim_swordd', s.x, s.y + s.h / 2, s.w, s.h);
    }
    for (final h in hearts.where((h) => h.active)) {
      _drawAnim(canvas, 'heart_anim', h.x, h.y + h.h / 2, h.w, h.h);
    }

    final sorted = [...players]..sort((a, b) => a.y.compareTo(b.y));
    for (final p in sorted) {
      final anim = _animFor(p);
      final def = animations[anim];
      final fs = def == null ? null : frameSizes[def.mediaFile];
      final w =
          fs?.width ??
          (p.hasSword ? (p.facing == 'right' ? 48.0 : 45.0) : 31.0);
      final h = fs?.height ?? (p.hasSword ? 45.0 : (p.alive ? 32.0 : 20.0));
      if (p.attacking && p.hasSword) {
        final attackPaint = Paint()..color = Colors.white.withOpacity(0.18);
        final arcX = p.facing == 'right' ? p.x : p.x - 42;
        canvas.drawRect(Rect.fromLTWH(arcX, p.y - 28, 42, 24), attackPaint);
      }
      _drawAnim(canvas, anim, p.x, p.y, w, h, flash: p.invulnerable);
      _drawNameplate(canvas, p);
    }

    canvas.restore();
  }

  void _drawNameplate(Canvas canvas, _RemotePlayer p) {
    final tp = TextPainter(
      text: TextSpan(
        text: p.name,
        style: TextStyle(
          color: p.id == myId ? Colors.amber : Colors.white,
          fontSize: 10,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(p.x - tp.width / 2, p.y - 54));
    final hpW = 28.0;
    canvas.drawRect(
      Rect.fromLTWH(p.x - hpW / 2, p.y - 40, hpW, 4),
      Paint()..color = Colors.black54,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        p.x - hpW / 2,
        p.y - 40,
        hpW * (p.hp / p.maxHp.clamp(1, 99).toDouble()),
        4,
      ),
      Paint()..color = Colors.redAccent,
    );
  }

  @override
  bool shouldRepaint(_LevelPainter old) => true;
}

class _Hud extends StatelessWidget {
  final _RemotePlayer? me;
  final List<_RemotePlayer> players;
  const _Hud({required this.me, required this.players});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.black.withOpacity(0.55),
      border: Border.all(color: const Color(0xFFd4a843)),
    ),
    child: DefaultTextStyle(
      style: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 12,
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'HP: ${me == null ? '-' : List.filled(me!.hp, '❤').join()}${me != null && me!.hp < me!.maxHp ? List.filled(me!.maxHp - me!.hp, '♡').join() : ''}',
          ),
          Text('Sword: ${me?.hasSword == true ? 'YES' : 'NO'}'),
          const SizedBox(height: 6),
          ...([...players]..sort((a, b) => b.score.compareTo(a.score))).map(
            (p) => Text('${p.name}: ${p.score}'),
          ),
          const SizedBox(height: 6),
          const Text(
            'A/D or ←/→ move • W/Space jump • J attack',
            style: TextStyle(fontSize: 10, color: Colors.white70),
          ),
        ],
      ),
    ),
  );
}

class _GameOverOverlay extends StatelessWidget {
  final String? winnerName;
  const _GameOverOverlay({required this.winnerName});

  @override
  Widget build(BuildContext context) => Container(
    color: Colors.black.withOpacity(0.62),
    alignment: Alignment.center,
    child: Container(
      width: 360,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1f2e).withOpacity(0.95),
        border: Border.all(color: const Color(0xFFd4a843), width: 3),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'GAME OVER',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Color(0xFFd4a843),
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            winnerName == null ? 'No winner' : '$winnerName wins!',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 18,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Resetting round...',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    ),
  );
}

class _TouchButton extends StatelessWidget {
  final String label;
  final VoidCallback onDown, onUp;
  final bool wide;
  const _TouchButton({
    required this.label,
    required this.onDown,
    required this.onUp,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => onDown(),
    onPointerUp: (_) => onUp(),
    onPointerCancel: (_) => onUp(),
    child: Container(
      width: wide ? 86 : 56,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.48),
        border: Border.all(color: const Color(0xFFd4a843), width: 2),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFFd4a843),
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
        ),
      ),
    ),
  );
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();
  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: Color(0xFF05080f),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: Color(0xFFd4a843)),
          SizedBox(height: 20),
          Text(
            'Loading level...',
            style: TextStyle(
              fontFamily: 'monospace',
              color: Color(0xFFd4a843),
              fontSize: 14,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    ),
  );
}

class _ErrorScreen extends StatelessWidget {
  final String message;
  const _ErrorScreen({required this.message});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF05080f),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Error:\n$message',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'monospace',
            color: Colors.redAccent,
            fontSize: 12,
          ),
        ),
      ),
    ),
  );
}
