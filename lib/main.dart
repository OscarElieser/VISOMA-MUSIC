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

const ink = Color(0xFF0B0B10);
const panel = Color(0xFF1B1A22);
const ember = Color(0xFFFF5B4A);
const violet = Color(0xFFAA8CFF);

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
  int _tab = 0;
  int _filter = 0;
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
      if (mounted) setState(() { _current = null; _playing = false; });
      await _video?.dispose();
      _video = null;
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

  Future<void> _onlineDialog() async {
    _url.clear();
    await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('Añadir fuente online'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Usa la URL HTTPS directa de un archivo que tengas permiso de reproducir.'),
        const SizedBox(height: 16),
        TextField(controller: _url, keyboardType: TextInputType.url,
          decoration: const InputDecoration(labelText: 'URL del archivo', border: OutlineInputBorder())),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
        FilledButton(onPressed: () async {
          final before = _items.length;
          await _addOnline();
          if (dialogContext.mounted && _items.length > before) Navigator.pop(dialogContext);
        }, child: const Text('Añadir')),
      ],
    ));
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
        child: const Icon(Icons.graphic_eq_rounded, size: 46, color: ember))),
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

  Widget _tile(MediaItem item) => Container(
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
      subtitle: Text('${item.video ? 'Video' : 'Audio'} · ${item.local ? 'Listo sin conexión' : 'Online'}',
        style: const TextStyle(fontSize: 12, color: Color(0xFFB3B0BC))),
      trailing: PopupMenuButton<String>(onSelected: (action) {
        if (action == 'favorite') { _favorite(item); }
        if (action == 'remove') { _remove(item); }
      }, itemBuilder: (_) => [
        PopupMenuItem(value: 'favorite', child: Text(item.favorite ? 'Quitar favorito' : 'Añadir favorito')),
        const PopupMenuItem(value: 'remove', child: Text('Quitar de biblioteca')),
      ]),
      onTap: () => _play(item),
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
    final visible = _items.where((item) =>
      item.title.toLowerCase().contains(_search.text.trim().toLowerCase()) &&
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
      if (visible.isEmpty) _empty('No hay elementos en esta vista.'),
      for (final item in visible) _tile(item),
      const SizedBox(height: 12),
      OutlinedButton.icon(onPressed: _onlineDialog, icon: const Icon(Icons.add_link),
        label: const Text('Añadir una fuente online autorizada')),
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
        }),
      SwitchListTile.adaptive(title: const Text('Online solo con Wi-Fi'),
        subtitle: const Text('Protección de datos móviles activada por defecto.'),
        value: _wifiOnly, onChanged: (value) async {
          setState(() => _wifiOnly = value);
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
          trailing: IconButton(icon: Icon(_playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
            color: ember, size: 34), onPressed: _togglePlayback)),
      ]));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(backgroundColor: ink, titleSpacing: 18,
      title: const FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.blur_circular, color: ember, size: 28), SizedBox(width: 9),
        Text('VÍSOMA', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2)),
        Text(' MUSIC', style: TextStyle(color: ember, fontWeight: FontWeight.w700, letterSpacing: 1)),
      ])), actions: [
        IconButton(onPressed: _onlineDialog, tooltip: 'Añadir fuente online', icon: const Icon(Icons.add_link)),
      ]),
    body: SafeArea(child: Column(children: [
      if (_loading) const LinearProgressIndicator(color: ember),
      if (_error != null) MaterialBanner(
        content: Text(_error!), leading: const Icon(Icons.info_outline, color: ember),
        actions: [TextButton(onPressed: () => setState(() => _error = null), child: const Text('Cerrar'))]),
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
