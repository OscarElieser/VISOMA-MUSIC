import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

void main() => runApp(const VisomaApp());

class VisomaApp extends StatelessWidget {
  const VisomaApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'VÍSOMA MUSIC',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF8D6BFF),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const LibraryScreen(),
      );
}

class MediaItem {
  const MediaItem(this.title, this.source, {required this.video, required this.local, this.favorite = false});
  final String title;
  final String source;
  final bool video;
  final bool local;
  final bool favorite;

  MediaItem copyWith({bool? favorite}) => MediaItem(title, source,
      video: video, local: local, favorite: favorite ?? this.favorite);

  Map<String, dynamic> toJson() => {
    'title': title, 'source': source, 'video': video,
    'local': local, 'favorite': favorite,
  };

  factory MediaItem.fromJson(Map<String, dynamic> value) => MediaItem(
    value['title'] as String, value['source'] as String,
    video: value['video'] == true, local: value['local'] == true,
    favorite: value['favorite'] == true,
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
  final _search = TextEditingController();
  final _items = <MediaItem>[];
  VideoPlayerController? _video;
  MediaItem? _current;
  bool _offline = false;
  bool _wifiOnly = true;
  String? _error;
  bool _playing = false;
  bool _loading = true;
  StreamSubscription<List<ConnectivityResult>>? _connectionSubscription;

  @override
  void initState() {
    super.initState();
    _restore();
    _audio.playerStateStream.listen((state) {
      if (mounted && _current?.video == false) {
        setState(() => _playing = state.playing);
      }
    });
    _connectionSubscription = Connectivity().onConnectivityChanged.listen((connections) {
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
    await file.writeAsString(jsonEncode(_items.map((item) => item.toJson()).toList()), flush: true);
  }

  Future<void> _restore() async {
    try {
      final file = await _index;
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString()) as List<dynamic>;
        final restored = decoded.map((entry) => MediaItem.fromJson(entry as Map<String, dynamic>));
        for (final item in restored) {
          if (!item.local || await File(item.source).exists()) _items.add(item);
        }
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
          uri.toString(), video: _isVideo(uri.path), local: false));
      _url.clear();
      _error = null;
    });
    await _save();
  }

  Future<void> _favorite(MediaItem item) async {
    final index = _items.indexOf(item);
    if (index < 0) return;
    setState(() => _items[index] = item.copyWith(favorite: !item.favorite));
    await _save();
  }

  Future<void> _remove(MediaItem item) async {
    if (_current == item) {
      await _audio.stop();
      await _video?.pause();
      if (mounted) setState(() => _current = null);
    }
    setState(() => _items.remove(item));
    // Remove only the library entry. Never delete a user's original media file.
    await _save();
  }

  Future<void> _play(MediaItem item) async {
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
      await _video?.dispose();
      _video = null;
      if (mounted) setState(() { _current = null; _playing = false; });
      if (item.video) {
        final controller = item.local
            ? VideoPlayerController.file(File(item.source))
            : VideoPlayerController.networkUrl(Uri.parse(item.source));
        await controller.initialize();
        _video = controller;
        await controller.play();
      } else {
        await _audio.setAudioSource(item.local
            ? AudioSource.file(item.source)
            : AudioSource.uri(Uri.parse(item.source)));
        unawaited(_audio.play());
      }
      if (mounted) setState(() { _current = item; _playing = true; _error = null; });
    } catch (error) {
      if (mounted) setState(() => _error = 'No se pudo reproducir: $error');
    }
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    _audio.dispose();
    _video?.dispose();
    _url.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _items.where((item) => item.title.toLowerCase().contains(_search.text.toLowerCase())).toList();
    final ready = _items.where((item) => item.local).length;
    return Scaffold(
        appBar: AppBar(title: const Text('VÍSOMA MUSIC')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Tu universo de audio y video', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          SwitchListTile(title: const Text('Modo sin conexión'), value: _offline,
              onChanged: (value) {
                if (value && _current?.local == false) {
                  unawaited(_audio.pause());
                  unawaited(_video?.pause() ?? Future<void>.value());
                  _playing = false;
                }
                setState(() => _offline = value);
              }),
          SwitchListTile(title: const Text('Solo Wi-Fi para escuchar online'),
              subtitle: const Text('Activado: no inicia contenido online por datos móviles'),
              value: _wifiOnly, onChanged: (value) async {
                setState(() => _wifiOnly = value);
                if (value && _current?.local == false) {
                  final connections = await Connectivity().checkConnectivity();
                  if (!connections.contains(ConnectivityResult.wifi)) {
                    await _audio.pause();
                    await _video?.pause();
                    if (mounted) setState(() => _playing = false);
                  }
                }
              }),
          FilledButton.icon(onPressed: _import, icon: const Icon(Icons.library_music),
              label: const Text('Importar audio o video')),
          const SizedBox(height: 12),
          TextField(controller: _url, keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'URL directa de contenido autorizado', border: OutlineInputBorder())),
          TextButton.icon(onPressed: _addOnline, icon: const Icon(Icons.add_link),
              label: const Text('Añadir al catálogo online')),
          Card(child: ListTile(leading: const Icon(Icons.travel_explore),
            title: const Text('Modo viaje'),
            subtitle: Text('$ready elementos listos sin conexión · ${_items.length - ready} requieren internet'))),
          if (_error != null) Padding(padding: const EdgeInsets.all(8),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          if (_video != null && _video!.value.isInitialized && _current?.video == true)
            AspectRatio(aspectRatio: _video!.value.aspectRatio,
                child: VideoPlayer(_video!)),
          if (_current != null) ListTile(
            title: Text(_current!.title),
            subtitle: Text(_current!.local ? 'Disponible sin conexión' : 'Online'),
            trailing: IconButton(icon: Icon(_playing ? Icons.pause : Icons.play_arrow), onPressed: () async {
              if (_current!.video) {
                if (_playing) {
                  await _video?.pause();
                } else {
                  await _video?.play();
                }
              } else {
                if (_playing) {
                  await _audio.pause();
                } else {
                  unawaited(_audio.play());
                }
              }
              if (mounted) setState(() => _playing = !_playing);
            }),
          ),
          const Divider(),
          Text('Biblioteca (${_items.length})', style: Theme.of(context).textTheme.titleLarge),
          TextField(controller: _search, onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar en mi biblioteca')),
          if (_loading) const LinearProgressIndicator(),
          for (final item in visible)
            ListTile(leading: Icon(item.video ? Icons.movie : Icons.music_note),
              title: Text(item.title),
              subtitle: Text(item.local ? 'En el dispositivo' : 'En línea'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(icon: Icon(item.favorite ? Icons.favorite : Icons.favorite_border),
                    onPressed: () => _favorite(item)),
                IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _remove(item)),
              ]), onTap: () => _play(item)),
        ]),
      );
  }
}
