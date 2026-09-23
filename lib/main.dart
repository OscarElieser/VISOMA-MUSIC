import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import 'lyrics.dart';
import 'assistant_commands.dart';
import 'catalog.dart';

void main() => runApp(const VisomaApp());

const ink = Color(0xFF0B0B10);
const panel = Color(0xFF1B1A22);
const ember = Color(0xFFFF5B4A);
const violet = Color(0xFFAA8CFF);

/// VÍSOMA's original mark: two sound arcs around a moving central pulse.
class VisomaMark extends StatelessWidget {
  const VisomaMark({super.key, this.size = 28});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size, height: size,
    child: CustomPaint(painter: _VisomaMarkPainter()),
  );
}

class _VisomaMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final stroke = Paint()..style = PaintingStyle.stroke
      ..strokeWidth = size.width * .085..strokeCap = StrokeCap.round;
    stroke.color = ember;
    canvas.drawArc(Rect.fromCircle(center: center, radius: size.width * .38),
      .75, 1.7, false, stroke);
    stroke.color = violet;
    canvas.drawArc(Rect.fromCircle(center: center, radius: size.width * .38),
      3.88, 1.7, false, stroke);
    final pulse = Path()
      ..moveTo(size.width * .27, size.height * .53)
      ..lineTo(size.width * .42, size.height * .53)
      ..lineTo(size.width * .50, size.height * .32)
      ..lineTo(size.width * .59, size.height * .68)
      ..lineTo(size.width * .68, size.height * .47)
      ..lineTo(size.width * .75, size.height * .47);
    canvas.drawPath(pulse, Paint()..color = ember..style = PaintingStyle.stroke
      ..strokeWidth = size.width * .06..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class VisomaApp extends StatelessWidget {
  const VisomaApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'VÍSOMA MUSIC',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: ember, brightness: Brightness.dark),
          scaffoldBackgroundColor: ink,
          cardColor: panel,
          useMaterial3: true,
        ),
        home: const LibraryScreen(),
      );
}

class MediaItem {
  const MediaItem(this.title, this.source, {required this.video, required this.local,
    this.favorite = false, this.lyrics, this.rights, this.canDownload = true,
    this.artist, this.album, this.genre});
  final String title;
  final String source;
  final bool video;
  final bool local;
  final bool favorite;
  final String? lyrics;
  final String? rights;
  final bool canDownload;
  final String? artist;
  final String? album;
  final String? genre;

  MediaItem copyWith({bool? favorite, String? lyrics}) => MediaItem(title, source,
      video: video, local: local, favorite: favorite ?? this.favorite,
      lyrics: lyrics ?? this.lyrics, rights: rights, canDownload: canDownload,
      artist: artist, album: album, genre: genre);

  Map<String, dynamic> toJson() => {
    'title': title, 'source': source, 'video': video,
    'local': local, 'favorite': favorite, 'lyrics': lyrics,
    'rights': rights, 'canDownload': canDownload,
    'artist': artist, 'album': album, 'genre': genre,
  };

  factory MediaItem.fromJson(Map<String, dynamic> value) => MediaItem(
    value['title'] as String, value['source'] as String,
    video: value['video'] == true, local: value['local'] == true,
    favorite: value['favorite'] == true,
    lyrics: value['lyrics'] is String ? value['lyrics'] as String : null,
    rights: value['rights'] is String ? value['rights'] as String : null,
    canDownload: value['canDownload'] != false,
    artist: value['artist'] is String ? value['artist'] as String : null,
    album: value['album'] is String ? value['album'] as String : null,
    genre: value['genre'] is String ? value['genre'] as String : null,
  );
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _audio = AudioPlayer();
  final _url = TextEditingController();
  final _catalogUrl = TextEditingController();
  bool _newOnlineVideo = false;
  final _search = TextEditingController();
  final _items = <MediaItem>[];
  final _playlists = <String, List<String>>{};
  List<MediaItem> _queue = [];
  int _queueIndex = -1;
  VideoPlayerController? _video;
  MediaItem? _current;
  bool _offline = false;
  bool _wifiOnly = true;
  String? _error;
  bool _playing = false;
  bool _loading = true;
  bool _advancing = false;
  String? _downloadStatus;
  HttpClient? _downloadClient;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<PlayerState>? _playerSubscription;
  int _tab = 0;
  int _filter = 0;
  StreamSubscription<List<ConnectivityResult>>? _connectionSubscription;

  @override
  void initState() {
    super.initState();
    _restore();
    _playerSubscription = _audio.playerStateStream.listen((state) {
      if (mounted && _current?.video == false) {
        setState(() => _playing = state.playing);
        if (state.processingState == ProcessingState.completed && !_advancing) {
          _advancing = true;
          unawaited(_next().whenComplete(() { _advancing = false; }));
        }
      }
    });
    _positionSubscription = _audio.positionStream.listen((position) {
      if (mounted && _current?.video == false) setState(() => _position = position);
    });
    _durationSubscription = _audio.durationStream.listen((duration) {
      if (mounted && _current?.video == false) setState(() => _duration = duration ?? Duration.zero);
    });
    _connectionSubscription = Connectivity().onConnectivityChanged.listen((connections) {
      if (_downloadClient != null && !connections.contains(ConnectivityResult.wifi)) {
        _downloadClient?.close(force: true);
        _downloadClient = null;
        if (mounted) setState(() => _downloadStatus = 'Descarga detenida: se perdió el Wi-Fi.');
      }
      if (_current?.local == false &&
          (connections.contains(ConnectivityResult.none) ||
           (_wifiOnly && !connections.contains(ConnectivityResult.wifi)))) {
        unawaited(_audio.pause());
        unawaited(_video?.pause() ?? Future<void>.value());
        if (mounted) setState(() {
          _playing = false;
          _error = 'Conexión cambiada: reproducción online en pausa para proteger tus datos.';
        });
      }
    });
  }

  Future<Directory> get _library async {
    final root = await getApplicationDocumentsDirectory();
    return Directory('${root.path}/visoma_media')..createSync(recursive: true);
  }

  bool _isVideo(String name) => RegExp(r'\.(mp4|m4v|mov|webm|mkv|avi)$', caseSensitive: false).hasMatch(name);

  Future<File> get _index async {
    final root = await getApplicationDocumentsDirectory();
    return File('${root.path}/visoma_library.json');
  }

  Future<void> _save() async {
    final file = await _index;
    final document = {
      'schema': 2,
      'items': _items.map((item) => item.toJson()).toList(),
      'playlists': _playlists,
      'offline': _offline,
      'wifiOnly': _wifiOnly,
    };
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(document), flush: true);
    await temp.rename(file.path);
  }

  Future<void> _restore() async {
    try {
      final file = await _index;
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        final document = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
        final values = decoded is List<dynamic> ? decoded : (document['items'] as List<dynamic>? ?? []);
        final restored = values.map((entry) => MediaItem.fromJson(entry as Map<String, dynamic>));
        for (final item in restored) {
          if (!item.local || await File(item.source).exists()) _items.add(item);
        }
        if (document['playlists'] is Map) {
          (document['playlists'] as Map).forEach((name, sources) {
            if (name is String && sources is List) {
              _playlists[name] = sources.whereType<String>().toList();
            }
          });
        }
        _offline = document['offline'] == true;
        _wifiOnly = document['wifiOnly'] != false;
      } else {
        final directory = await _library;
        for (final file in directory.listSync().whereType<File>()) {
          _items.add(MediaItem(file.uri.pathSegments.last, file.path,
              video: _isVideo(file.path), local: true));
        }
        await _save();
      }
    } catch (error) {
      _error = 'No se pudo leer la biblioteca: $error';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _import() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.any);
    if (result == null) return;
    final directory = await _library;
    for (final selected in result.files) {
      if (selected.path == null) continue;
      try {
        final name = selected.name.replaceAll(RegExp(r'[/\\]'), '_');
        final destination = File('${directory.path}/${DateTime.now().microsecondsSinceEpoch}_$name');
        await File(selected.path!).copy(destination.path);
        if (!mounted) return;
        setState(() => _items.add(MediaItem(name, destination.path,
            video: _isVideo(name), local: true)));
        await _save();
      } catch (error) {
        if (mounted) setState(() => _error = 'No se pudo importar ${selected.name}: $error');
      }
    }
  }

  Future<void> _addOnline() async {
    final uri = Uri.tryParse(_url.text.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      setState(() => _error = 'Introduce una URL HTTPS directa de un archivo autorizado.');
      return;
    }
    setState(() {
      _items.add(MediaItem(uri.pathSegments.isEmpty ? uri.host : uri.pathSegments.last,
          uri.toString(), video: _newOnlineVideo || _isVideo(uri.path), local: false));
      _url.clear();
      _error = null;
    });
    await _save();
  }

  Future<int> _loadCatalog(String address) async {
    final uri = Uri.tryParse(address.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const FormatException('La dirección del catálogo debe usar HTTPS.');
    }
    final connections = await Connectivity().checkConnectivity();
    if (_offline || connections.contains(ConnectivityResult.none) ||
        (_wifiOnly && !connections.contains(ConnectivityResult.wifi))) {
      throw const SocketException('Conecta Wi-Fi o cambia la protección de datos.');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('El catálogo respondió ${response.statusCode}');
      }
      const maxManifest = 1024 * 1024;
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        bytes.add(chunk);
        if (bytes.length > maxManifest) {
          throw const FormatException('El catálogo excede 1 MB.');
        }
      }
      final tracks = parseCatalog(utf8.decode(bytes.takeBytes()));
      var added = 0;
      for (final track in tracks) {
        if (_items.any((item) => item.source == track.url)) continue;
        _items.add(MediaItem(track.title, track.url, video: track.video,
          local: false, rights: track.rights, canDownload: track.downloadAllowed,
          artist: track.artist, album: track.album, genre: track.genre));
        added++;
      }
      if (mounted) setState(() {});
      await _save();
      return added;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _catalogDialog() async {
    _catalogUrl.clear();
    var status = 'Introduce el enlace HTTPS de tu catálogo autorizado.';
    await showDialog<void>(context: context, builder: (dialogContext) => StatefulBuilder(
      builder: (context, refresh) => AlertDialog(
        title: const Text('Conectar catálogo'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(status), const SizedBox(height: 12),
          TextField(controller: _catalogUrl, keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'URL del catálogo JSON')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cerrar')),
          FilledButton(onPressed: () async {
            try {
              final count = await _loadCatalog(_catalogUrl.text);
              if (dialogContext.mounted) refresh(() => status = '$count elementos nuevos añadidos.');
            } catch (error) {
              if (dialogContext.mounted) refresh(() => status = 'No se pudo importar: $error');
            }
          }, child: const Text('Cargar')),
        ],
      ),
    ));
  }

  Future<void> _downloadAuthorized(MediaItem item) async {
    if (item.local || !item.canDownload || _downloadClient != null) return;
    final connections = await Connectivity().checkConnectivity();
    if (!connections.contains(ConnectivityResult.wifi)) {
      setState(() => _error = 'Las descargas solo funcionan por Wi-Fi.');
      return;
    }
    final uri = Uri.tryParse(item.source);
    if (uri == null || uri.scheme != 'https') return;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    _downloadClient = client;
    File? partial;
    const limitBytes = 250 * 1024 * 1024;
    try {
      setState(() => _downloadStatus = 'Preparando ${item.title}…');
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('El servidor respondió ${response.statusCode}');
      }
      final mime = response.headers.contentType?.mimeType ?? '';
      final recognized = mime.startsWith('audio/') || mime.startsWith('video/') ||
          (mime == 'application/octet-stream' &&
           RegExp(r'\.(mp3|m4a|aac|wav|flac|ogg|opus|mp4|m4v|mov|webm|mkv)$',
             caseSensitive: false).hasMatch(uri.path));
      if (!recognized) throw const FormatException('La URL no entregó un archivo de audio o video.');
      if (response.contentLength > limitBytes) throw const FormatException('Archivo mayor que 250 MB.');
      final directory = await _library;
      final cleanName = item.title.replaceAll(RegExp(r'[/\\]'), '_');
      final hasExtension = RegExp(r'\.[a-z0-9]{2,5}$', caseSensitive: false).hasMatch(cleanName);
      final suffix = switch (mime) {
        'audio/mpeg' => '.mp3',
        'audio/flac' => '.flac',
        'audio/ogg' => '.ogg',
        'audio/wav' || 'audio/x-wav' => '.wav',
        'video/webm' => '.webm',
        'video/quicktime' => '.mov',
        'video/mp4' => '.mp4',
        _ => item.video ? '.mp4' : '.m4a',
      };
      final path = '${directory.path}/${DateTime.now().microsecondsSinceEpoch}_$cleanName${hasExtension ? '' : suffix}';
      partial = File('$path.part');
      final sink = partial.openWrite();
      var received = 0;
      try {
        await for (final chunk in response) {
          if (_downloadClient != client) throw const SocketException('Se perdió el Wi-Fi.');
          received += chunk.length;
          if (received > limitBytes) throw const FormatException('Archivo mayor que 250 MB.');
          sink.add(chunk);
          if (mounted && received % (1024 * 1024) < chunk.length) {
            setState(() => _downloadStatus = 'Descargando ${item.title}: ${(received / 1048576).toStringAsFixed(1)} MB');
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (received == 0) throw const FormatException('El archivo está vacío.');
      final finalFile = await partial.rename(path);
      partial = null;
      if (mounted) {
        setState(() {
          _items.add(MediaItem(item.title, finalFile.path,
            video: item.video || mime.startsWith('video/'), local: true,
            artist: item.artist, album: item.album, genre: item.genre,
            lyrics: item.lyrics));
          _downloadStatus = 'Guardado para escuchar sin conexión.';
        });
      }
      await _save();
    } catch (error) {
      if (mounted) setState(() => _error = 'No se pudo descargar: $error');
    } finally {
      client.close(force: true);
      if (_downloadClient == client) _downloadClient = null;
      if (partial != null && await partial.exists()) await partial.delete();
      if (mounted) setState(() => _downloadStatus = null);
    }
  }

  Future<void> _favorite(MediaItem item) async {
    final index = _items.indexOf(item);
    if (index < 0) return;
    setState(() => _items[index] = item.copyWith(favorite: !item.favorite));
    await _save();
  }

  Future<void> _attachLyrics(MediaItem item) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['lrc', 'txt']);
    if (picked == null || picked.files.single.path == null) return;
    try {
      final contents = await File(picked.files.single.path!).readAsString();
      final index = _items.indexWhere((entry) => entry.source == item.source);
      if (index < 0) return;
      setState(() => _items[index] = _items[index].copyWith(lyrics: contents));
      await _save();
      if (mounted) setState(() => _error = 'Letra vinculada a ${item.title}.');
    } catch (error) {
      if (mounted) setState(() => _error = 'No se pudo leer la letra: $error');
    }
  }

  Future<void> _createPlaylist() async {
    final name = TextEditingController();
    final proposed = await showDialog<String>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('Nueva lista'),
      content: TextField(controller: name, autofocus: true, maxLength: 50,
        decoration: const InputDecoration(labelText: 'Nombre de la lista')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, name.text.trim()), child: const Text('Crear')),
      ],
    ));
    name.dispose();
    if (proposed == null || proposed.isEmpty || _playlists.containsKey(proposed)) return;
    setState(() => _playlists[proposed] = []);
    await _save();
  }

  Future<void> _addToPlaylist(MediaItem item) async {
    if (_playlists.isEmpty) await _createPlaylist();
    if (!mounted || _playlists.isEmpty) return;
    final name = await showModalBottomSheet<String>(context: context,
      builder: (sheetContext) => SafeArea(child: ListView(shrinkWrap: true, children: [
        const ListTile(title: Text('Añadir a una lista')),
        for (final title in _playlists.keys)
          ListTile(title: Text(title), trailing: const Icon(Icons.add),
            onTap: () => Navigator.pop(sheetContext, title)),
      ])));
    if (name == null) return;
    if (!_playlists[name]!.contains(item.source)) {
      setState(() => _playlists[name]!.add(item.source));
      await _save();
    }
  }

  Future<void> _deletePlaylist(String name) async {
    setState(() => _playlists.remove(name));
    await _save();
  }

  Future<void> _remove(MediaItem item) async {
    if (_current?.source == item.source) {
      await _audio.stop();
      await _video?.pause();
      if (mounted) setState(() => _current = null);
    }
    setState(() => _items.remove(item));
    for (final sources in _playlists.values) { sources.remove(item.source); }
    // Remove only the library entry. Never delete a user's original media file.
    await _save();
  }

  Future<void> _play(MediaItem item, {List<MediaItem>? queue}) async {
    if (!item.local) {
      final connections = await Connectivity().checkConnectivity();
      if (_offline || connections.contains(ConnectivityResult.none) ||
          (_wifiOnly && !connections.contains(ConnectivityResult.wifi))) {
        if (mounted) setState(() => _error = _offline
            ? 'Modo sin conexión: elige un archivo local.'
            : 'Conecta Wi-Fi o cambia la protección de datos para reproducir online.');
        return;
      }
    }
    try {
      await _audio.stop();
      if (mounted) setState(() { _current = null; _playing = false;
        _position = Duration.zero; _duration = Duration.zero; });
      await _video?.dispose();
      _video = null;
      if (item.video) {
        final controller = item.local
            ? VideoPlayerController.file(File(item.source))
            : VideoPlayerController.networkUrl(Uri.parse(item.source));
        await controller.initialize();
        _video = controller;
        _duration = controller.value.duration;
        controller.addListener(() {
          if (!mounted || _video != controller || _current?.video != true) return;
          final position = controller.value.position;
          if ((position - _position).inMilliseconds.abs() >= 400 ||
              controller.value.isCompleted) {
            setState(() { _position = position; _playing = controller.value.isPlaying; });
          }
        });
        await controller.play();
      } else {
        _duration = await _audio.setAudioSource(item.local
            ? AudioSource.file(item.source)
            : AudioSource.uri(Uri.parse(item.source))) ?? Duration.zero;
        unawaited(_audio.play());
      }
      if (mounted) setState(() {
        _current = item; _playing = true; _error = null;
        if (queue != null) _queue = List<MediaItem>.from(queue);
        if (_queue.isEmpty || !_queue.any((entry) => entry.source == item.source)) {
          _queue = [item];
        }
        _queueIndex = _queue.indexWhere((entry) => entry.source == item.source);
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'No se pudo reproducir: $error');
    }
  }

  Future<void> _next() async {
    if (_queueIndex >= 0 && _queueIndex + 1 < _queue.length) {
      await _play(_queue[_queueIndex + 1]);
    } else {
      if (mounted) setState(() => _playing = false);
    }
  }

  Future<void> _previous() async {
    if (_position.inSeconds > 3) {
      await _seek(Duration.zero);
    } else if (_queueIndex > 0) {
      await _play(_queue[_queueIndex - 1]);
    }
  }

  Future<void> _seek(Duration position) async {
    if (_current?.video == true) {
      await _video?.seekTo(position);
    } else {
      await _audio.seek(position);
    }
    if (mounted) setState(() => _position = position);
  }

  @override
  void dispose() {
    _downloadClient?.close(force: true);
    _connectionSubscription?.cancel();
    _playerSubscription?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _audio.dispose();
    _video?.dispose();
    _url.dispose();
    _catalogUrl.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    final item = _current;
    if (item == null) return;
    if (!_playing && !item.local) {
      final connections = await Connectivity().checkConnectivity();
      if (_offline || connections.contains(ConnectivityResult.none) ||
          (_wifiOnly && !connections.contains(ConnectivityResult.wifi))) {
        if (mounted) setState(() => _error = 'La reproducción online requiere una conexión permitida.');
        return;
      }
    }
    if (item.video) {
      if (_playing) { await _video?.pause(); } else { await _video?.play(); }
    } else {
      if (_playing) { await _audio.pause(); } else { unawaited(_audio.play()); }
    }
    if (mounted) setState(() => _playing = !_playing);
  }

  String _time(Duration duration) {
    final safe = duration.isNegative ? Duration.zero : duration;
    final minutes = safe.inMinutes;
    final seconds = safe.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _showLyrics() {
    final item = _current;
    if (item == null) return;
    final stored = _items.where((entry) => entry.source == item.source);
    final lyrics = stored.isEmpty ? item.lyrics : stored.first.lyrics;
    final timed = lyrics == null ? <LyricLine>[] : parseLrc(lyrics);
    showModalBottomSheet<void>(context: context, isScrollControlled: true,
      builder: (sheetContext) => SafeArea(child: SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * .7,
        child: Column(children: [
          ListTile(title: const Text('Letra'), subtitle: Text(item.title,
            maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(sheetContext))),
          if (lyrics == null) const Expanded(child: Center(child: Text(
            'Aún no hay letra. Puedes vincular un archivo .lrc o .txt desde la biblioteca.'))),
          if (lyrics != null && timed.isEmpty)
            Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(24),
              child: SelectableText(lyrics, style: const TextStyle(fontSize: 18, height: 1.7)))),
          if (timed.isNotEmpty) Expanded(child: StreamBuilder<Duration>(
            stream: Stream.periodic(const Duration(milliseconds: 500), (_) => _position),
            initialData: _position,
            builder: (context, snapshot) {
              final active = activeLyricIndex(timed, snapshot.data ?? Duration.zero);
              return ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: timed.length,
                itemBuilder: (_, index) => InkWell(onTap: () => _seek(timed[index].at),
                  child: Padding(padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(timed[index].text,
                      style: TextStyle(fontSize: index == active ? 22 : 18,
                        fontWeight: index == active ? FontWeight.w800 : FontWeight.normal,
                        color: index == active ? ember : const Color(0xFFB3B0BC))))));
            },
          )),
        ]),
      )));
  }

  Future<String> _executeAssistant(String input) async {
    final command = parseAssistantCommand(input);
    switch (command.action) {
      case AssistantAction.play:
        final matches = _items.where((item) =>
          item.title.toLowerCase().contains(command.query)).toList();
        if (matches.isEmpty) return 'No encontré esa canción en tu biblioteca.';
        await _play(matches.first, queue: matches);
        return _current?.source == matches.first.source
            ? 'Reproduciendo ${matches.first.title}.' : 'No pude iniciar la reproducción.';
      case AssistantAction.pause:
        if (_playing) await _togglePlayback();
        return 'Reproducción en pausa.';
      case AssistantAction.next:
        await _next(); return 'Avanzando en la cola.';
      case AssistantAction.previous:
        await _previous(); return 'Volviendo al elemento anterior.';
      case AssistantAction.travel:
        setState(() => _tab = 2);
        return 'Abriendo Modo viaje.';
      case AssistantAction.offline:
        if (_current?.local == false) {
          await _audio.pause(); await _video?.pause();
        }
        setState(() { _offline = true; _playing = _current?.local == true && _playing; });
        await _save();
        return 'Modo sin conexión activado.';
      case AssistantAction.online:
        setState(() => _offline = false);
        await _save();
        return 'Modo online activado. La protección Wi-Fi sigue vigente.';
      case AssistantAction.help:
        return 'Prueba: «pon [canción]», «pausar», «siguiente», «anterior», «modo viaje» o «sin conexión».';
      case AssistantAction.unknown:
        return 'Todavía no conozco esa orden. Escribe «ayuda» para ver las disponibles.';
    }
  }

  Future<void> _assistantDialog() async {
    final input = TextEditingController();
    var answer = 'Controla tu biblioteca con órdenes escritas, incluso sin internet.';
    await showDialog<void>(context: context, builder: (dialogContext) => StatefulBuilder(
      builder: (context, refresh) => AlertDialog(
        title: const Text('Habla con Vísoma'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(answer), const SizedBox(height: 15),
          TextField(controller: input, autofocus: true,
            decoration: const InputDecoration(labelText: 'Escribe una orden',
              hintText: 'Pon mi canción favorita')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cerrar')),
          FilledButton(onPressed: () async {
            final response = await _executeAssistant(input.text);
            if (dialogContext.mounted) refresh(() => answer = response);
          }, child: const Text('Enviar')),
        ],
      ),
    ));
    input.dispose();
  }

  Future<void> _onlineDialog() async {
    _url.clear();
    _newOnlineVideo = false;
    await showDialog<void>(context: context, builder: (dialogContext) => StatefulBuilder(
      builder: (context, refresh) => AlertDialog(
      title: const Text('Añadir fuente online'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Usa la URL HTTPS directa de un archivo que tengas permiso de reproducir.'),
        const SizedBox(height: 16),
        TextField(controller: _url, keyboardType: TextInputType.url,
          decoration: const InputDecoration(labelText: 'URL del archivo', border: OutlineInputBorder())),
        SwitchListTile(title: const Text('Es un video'), value: _newOnlineVideo,
          onChanged: (value) => refresh(() => _newOnlineVideo = value)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
        FilledButton(onPressed: () async {
          final before = _items.length;
          await _addOnline();
          if (dialogContext.mounted && _items.length > before) Navigator.pop(dialogContext);
        }, child: const Text('Añadir')),
      ],
    )));
  }

  Widget _badge(String text, IconData icon, {Color color = ember}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(color: color.withValues(alpha: .13),
      borderRadius: BorderRadius.circular(30), border: Border.all(color: color.withValues(alpha: .35))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: color, size: 16), const SizedBox(width: 6),
      Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
    ]),
  );

  Widget _hero() => Container(
    height: 216,
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(28),
      gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [Color(0xFF39202A), Color(0xFF231A27), Color(0xFF12131C)])),
    child: Stack(children: [
      Positioned(right: -18, top: -26, child: Container(width: 195, height: 195,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ember.withValues(alpha: .35), width: 20)))),
      Positioned(right: 30, top: 38, child: Container(width: 95, height: 95,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: violet.withValues(alpha: .55), width: 2)),
        child: const Center(child: VisomaMark(size: 70)))),
      Padding(padding: const EdgeInsets.all(24), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('TU UNIVERSO, A TU RITMO', style: TextStyle(color: violet,
            fontWeight: FontWeight.bold, letterSpacing: 1.4, fontSize: 11)),
          const Text('Elige qué vivir\nhoy.', style: TextStyle(fontSize: 31, fontWeight: FontWeight.w800, height: 1.05)),
          Row(children: [
            _badge(_offline ? 'SIN CONEXIÓN' : 'DOS MODOS',
                _offline ? Icons.offline_bolt : Icons.wifi),
            const SizedBox(width: 8),
            _badge('${_items.length} ARCHIVOS', Icons.library_music, color: violet),
          ]),
        ],
      )),
    ]),
  );

  Widget _tile(MediaItem item, {List<MediaItem>? queue}) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(17)),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      leading: Container(width: 48, height: 48, decoration: BoxDecoration(
        color: item.video ? violet.withValues(alpha: .18) : ember.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(12)),
        child: Icon(item.video ? Icons.play_circle_outline : Icons.multitrack_audio,
          color: item.video ? violet : ember)),
      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text('${item.artist == null ? (item.video ? 'Video' : 'Audio') : item.artist!} · ${item.local ? 'Sin conexión' : 'Online'}',
        style: const TextStyle(fontSize: 12, color: Color(0xFFB3B0BC))),
      trailing: PopupMenuButton<String>(onSelected: (action) {
        if (action == 'favorite') { _favorite(item); }
        if (action == 'lyrics') { _attachLyrics(item); }
        if (action == 'playlist') { _addToPlaylist(item); }
        if (action == 'download') { _downloadAuthorized(item); }
        if (action == 'rights') {
          showDialog<void>(context: context, builder: (context) => AlertDialog(
            title: const Text('Fuente y permiso declarado'),
            content: Text(item.rights ?? 'Contenido añadido manualmente.'),
            actions: [TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'))]));
        }
        if (action == 'remove') { _remove(item); }
      }, itemBuilder: (_) => [
        PopupMenuItem(value: 'favorite', child: Text(item.favorite ? 'Quitar favorito' : 'Añadir favorito')),
        const PopupMenuItem(value: 'playlist', child: Text('Añadir a lista')),
        if (!item.local && item.canDownload) const PopupMenuItem(value: 'download', child: Text('Guardar sin conexión (Wi-Fi)')),
        if (item.rights != null) const PopupMenuItem(value: 'rights', child: Text('Ver permiso declarado')),
        if (!item.video) const PopupMenuItem(value: 'lyrics', child: Text('Vincular letra .lrc/.txt')),
        const PopupMenuItem(value: 'remove', child: Text('Quitar de biblioteca')),
      ]),
      onTap: () => _play(item, queue: queue ?? _items),
    ),
  );

  Widget _empty(String message) => Padding(padding: const EdgeInsets.symmetric(vertical: 28),
    child: Center(child: Text(message, textAlign: TextAlign.center,
      style: const TextStyle(color: Color(0xFFB3B0BC)))));

  Widget _home() {
    final local = _items.where((item) => item.local).toList();
    final recent = _items.reversed.take(4).toList();
    return ListView(padding: const EdgeInsets.fromLTRB(18, 12, 18, 20), children: [
      _hero(), const SizedBox(height: 25),
      const Text('Tu biblioteca empieza aquí', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
      const SizedBox(height: 13),
      Row(children: [
        Expanded(child: FilledButton.icon(onPressed: _import,
          icon: const Icon(Icons.add), label: const Text('Importar archivos'))),
        const SizedBox(width: 9),
        IconButton.filledTonal(onPressed: _onlineDialog,
          tooltip: 'Añadir fuente online', icon: const Icon(Icons.link)),
      ]),
      TextButton.icon(onPressed: _catalogDialog,
        icon: const Icon(Icons.cloud_outlined), label: const Text('Conectar mi catálogo online')),
      const SizedBox(height: 23),
      Row(children: [
        const Expanded(child: Text('Listos para salir', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
        TextButton(onPressed: () => setState(() => _tab = 2), child: const Text('Modo viaje')),
      ]),
      if (local.isEmpty) _empty('Importa música o videos para escucharlos sin datos.'),
      for (final item in local.take(3)) _tile(item),
      const SizedBox(height: 14),
      const Text('Añadidos recientemente', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      if (recent.isEmpty) _empty('Tu universo musical todavía está vacío.'),
      for (final item in recent) _tile(item),
    ]);
  }

  Widget _libraryView() {
    final query = _search.text.trim().toLowerCase();
    final visible = _items.where((item) =>
      ('${item.title} ${item.artist ?? ''} ${item.album ?? ''} ${item.genre ?? ''}').toLowerCase().contains(query) &&
      (_filter == 0 || (_filter == 1 && !item.video) ||
       (_filter == 2 && item.video) || (_filter == 3 && item.favorite))).toList();
    return ListView(padding: const EdgeInsets.fromLTRB(18, 10, 18, 24), children: [
      const Text('Mi biblioteca', style: TextStyle(fontSize: 29, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Text('${_items.length} elementos · local y online',
        style: const TextStyle(color: Color(0xFFB3B0BC))),
      const SizedBox(height: 18),
      TextField(controller: _search, onChanged: (_) => setState(() {}),
        decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: 'Buscar en mi biblioteca',
          filled: true, fillColor: panel, border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none))),
      const SizedBox(height: 12),
      SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
        for (final (index, label) in [(0, 'Todo'), (1, 'Música'), (2, 'Videos'), (3, 'Favoritos')])
          Padding(padding: const EdgeInsets.only(right: 7), child: ChoiceChip(
            label: Text(label), selected: _filter == index,
            onSelected: (_) => setState(() => _filter = index))),
      ])),
      const SizedBox(height: 16),
      Row(children: [
        const Expanded(child: Text('Mis listas',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
        TextButton.icon(onPressed: _createPlaylist,
          icon: const Icon(Icons.add), label: const Text('Crear')),
      ]),
      if (_playlists.isEmpty) _empty('Crea una lista y añade tus canciones favoritas.'),
      for (final entry in _playlists.entries)
        Card(child: ExpansionTile(
          leading: const Icon(Icons.queue_music, color: violet),
          title: Text(entry.key),
          subtitle: Text('${entry.value.length} elementos'),
          trailing: IconButton(icon: const Icon(Icons.delete_outline),
            tooltip: 'Eliminar lista', onPressed: () => _deletePlaylist(entry.key)),
          children: [
            Builder(builder: (context) {
              final tracks = entry.value.map((source) => _items.where(
                (item) => item.source == source)).where((matches) => matches.isNotEmpty)
                  .map((matches) => matches.first).toList();
              return Column(children: [
                if (tracks.isEmpty) _empty('Añade canciones o videos desde el menú de cada archivo.'),
                for (final item in tracks) _tile(item, queue: tracks),
              ]);
            }),
          ],
        )),
      const SizedBox(height: 15),
      const Text('Todos los archivos', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
      const SizedBox(height: 10),
      if (visible.isEmpty) _empty('No hay elementos en esta vista.'),
      for (final item in visible) _tile(item, queue: visible),
      const SizedBox(height: 12),
      OutlinedButton.icon(onPressed: _onlineDialog, icon: const Icon(Icons.add_link),
        label: const Text('Añadir una fuente online autorizada')),
      OutlinedButton.icon(onPressed: _catalogDialog, icon: const Icon(Icons.cloud_download_outlined),
        label: const Text('Conectar catálogo autorizado')),
    ]);
  }

  Widget _travel() {
    final local = _items.where((item) => item.local).toList();
    final online = _items.where((item) => !item.local).length;
    return ListView(padding: const EdgeInsets.fromLTRB(18, 10, 18, 24), children: [
      const Text('Modo viaje', style: TextStyle(fontSize: 29, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      const Text('Prepara tu contenido antes de quedarte sin señal.',
        style: TextStyle(color: Color(0xFFB3B0BC))),
      const SizedBox(height: 20),
      Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(23),
        gradient: const LinearGradient(colors: [Color(0xFF442428), Color(0xFF231C31)])),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.offline_bolt, color: ember, size: 34),
          const SizedBox(height: 12),
          Text('${local.length} listos sin conexión',
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('$online elementos online necesitan internet.',
            style: const TextStyle(color: Color(0xFFD3CFD9))),
        ])),
      const SizedBox(height: 16),
      SwitchListTile.adaptive(title: const Text('Usar solo contenido local'),
        subtitle: const Text('Detiene contenido online al activarse.'),
        value: _offline, onChanged: (value) {
          if (value && _current?.local == false) {
            unawaited(_audio.pause());
            unawaited(_video?.pause() ?? Future<void>.value());
            _playing = false;
          }
          setState(() => _offline = value);
          unawaited(_save());
        }),
      SwitchListTile.adaptive(title: const Text('Online solo con Wi-Fi'),
        subtitle: const Text('Protección de datos móviles activada por defecto.'),
        value: _wifiOnly, onChanged: (value) async {
          setState(() => _wifiOnly = value);
          await _save();
          if (value && _current?.local == false) {
            final connections = await Connectivity().checkConnectivity();
            if (!connections.contains(ConnectivityResult.wifi)) {
              await _audio.pause(); await _video?.pause();
              if (mounted) setState(() => _playing = false);
            }
          }
        }),
      const SizedBox(height: 13),
      FilledButton.icon(onPressed: _import, icon: const Icon(Icons.download_for_offline),
        label: const Text('Importar para este viaje')),
      const SizedBox(height: 19),
      const Text('Disponible sin internet', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      if (local.isEmpty) _empty('Todavía no has importado archivos.'),
      for (final item in local) _tile(item),
    ]);
  }

  Widget _miniPlayer() {
    final item = _current;
    if (item == null) return const SizedBox.shrink();
    return Container(margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      decoration: BoxDecoration(color: const Color(0xFF29232B), borderRadius: BorderRadius.circular(17)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (item.video && _video != null && _video!.value.isInitialized)
          ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
            child: AspectRatio(aspectRatio: _video!.value.aspectRatio, child: VideoPlayer(_video!))),
        ListTile(leading: Icon(item.video ? Icons.smart_display : Icons.graphic_eq, color: ember),
          title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(item.local ? 'SIN CONEXIÓN' : 'ONLINE',
            style: const TextStyle(fontSize: 10, letterSpacing: 1, color: violet)),
          trailing: !item.video ? IconButton(icon: const Icon(Icons.lyrics_outlined),
            tooltip: 'Ver letra', onPressed: _showLyrics) : null),
        if (_duration > Duration.zero) Padding(padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(children: [
            Text(_time(_position), style: const TextStyle(fontSize: 11)),
            Expanded(child: Slider(value: _position.inMilliseconds.clamp(0, _duration.inMilliseconds).toDouble(),
              max: _duration.inMilliseconds.toDouble(),
              onChanged: (value) => _seek(Duration(milliseconds: value.round())))),
            Text(_time(_duration), style: const TextStyle(fontSize: 11)),
          ])),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(onPressed: _queueIndex > 0 || _position.inSeconds > 3 ? _previous : null,
            icon: const Icon(Icons.skip_previous_rounded), tooltip: 'Anterior'),
          const SizedBox(width: 8),
          IconButton.filled(onPressed: _togglePlayback,
            icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
            tooltip: _playing ? 'Pausar' : 'Reproducir'),
          const SizedBox(width: 8),
          IconButton(onPressed: _queueIndex + 1 < _queue.length ? _next : null,
            icon: const Icon(Icons.skip_next_rounded), tooltip: 'Siguiente'),
        ]),
      ]));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(backgroundColor: ink, titleSpacing: 18,
      title: const FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
        VisomaMark(), SizedBox(width: 9),
        Text('VÍSOMA', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2)),
        Text(' MUSIC', style: TextStyle(color: ember, fontWeight: FontWeight.w700, letterSpacing: 1)),
      ])), actions: [
        IconButton(onPressed: _assistantDialog, tooltip: 'Comandos de Vísoma',
          icon: const Icon(Icons.auto_awesome, color: violet)),
        IconButton(onPressed: _onlineDialog, tooltip: 'Añadir fuente online', icon: const Icon(Icons.add_link)),
      ]),
    body: SafeArea(child: Column(children: [
      if (_loading) const LinearProgressIndicator(color: ember),
      if (_error != null) MaterialBanner(
        content: Text(_error!), leading: const Icon(Icons.info_outline, color: ember),
        actions: [TextButton(onPressed: () => setState(() => _error = null), child: const Text('Cerrar'))]),
      if (_downloadStatus != null) Padding(padding: const EdgeInsets.all(10),
        child: Column(children: [Text(_downloadStatus!), const LinearProgressIndicator(color: ember)])),
      Expanded(child: IndexedStack(index: _tab, children: [_home(), _libraryView(), _travel()])),
      _miniPlayer(),
    ])),
    bottomNavigationBar: NavigationBar(
      backgroundColor: const Color(0xFF15141B), selectedIndex: _tab,
      onDestinationSelected: (index) => setState(() => _tab = index),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.auto_awesome_outlined),
          selectedIcon: Icon(Icons.auto_awesome), label: 'Inicio'),
        NavigationDestination(icon: Icon(Icons.library_music_outlined),
          selectedIcon: Icon(Icons.library_music), label: 'Biblioteca'),
        NavigationDestination(icon: Icon(Icons.explore_outlined),
          selectedIcon: Icon(Icons.explore), label: 'Modo viaje'),
      ],
    ),
  );
}
