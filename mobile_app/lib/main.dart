import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart'; // Importando o Player

// --- Configuração de Rede ---
// ⚠️ ATENÇÃO: Se for rodar no Mac (com backend no Mac), use '127.0.0.1'.
// Se o backend continuar no PC e o app no iPhone físico, use o IP da rede.
const String serverIp = '127.0.0.1'; 
const String baseUrl = 'http://$serverIp:8000';

// --- Provedores (Estado & Lógica) ---

final dioProvider = Provider((ref) {
  return Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));
});

final searchResultsProvider = StateProvider<List<dynamic>>((ref) => []);
final isLoadingProvider = StateProvider<bool>((ref) => false);
final hasSearchedProvider = StateProvider<bool>((ref) => false);

// NOVO: Guarda o ID da busca atual para permitir "Refresh" manual
final currentSearchIdProvider = StateProvider<String?>((ref) => null);

final searchControllerProvider = Provider((ref) {
  return SearchController(ref);
});

class SearchController {
  final Ref ref;
  SearchController(this.ref);

  // Inicia uma NOVA busca
  Future<void> search(String query) async {
    if (query.isEmpty) return;
    
    final dio = ref.read(dioProvider);
    final notifier = ref.read(searchResultsProvider.notifier);
    final loading = ref.read(isLoadingProvider.notifier);
    final hasSearched = ref.read(hasSearchedProvider.notifier);
    final currentId = ref.read(currentSearchIdProvider.notifier);

    try {
      loading.state = true;
      hasSearched.state = true; 
      notifier.state = []; 

      // 1. Inicia busca
      print('🔍 Iniciando busca por: $query');
      final searchResp = await dio.post('/search/$query');
      final searchId = searchResp.data['search_id'];
      
      // Salva o ID para podermos dar refresh depois
      currentId.state = searchId;

      // 2. Inicia o Polling Automático
      await _pollResults(searchId);
      
    } catch (e) {
      print('❌ Erro na busca: $e');
      rethrow;
    } finally {
      loading.state = false;
    }
  }

  // Consulta novamente o ID existente (Manual Refresh)
  Future<void> refresh() async {
    final searchId = ref.read(currentSearchIdProvider);
    if (searchId == null) return;

    final loading = ref.read(isLoadingProvider.notifier);
    try {
      loading.state = true;
      print('🔄 Atualizando resultados para ID: $searchId');
      await _pollResults(searchId, attempts: 1); // Apenas uma checagem rápida
    } catch (e) {
      print('❌ Erro no refresh: $e');
    } finally {
      loading.state = false;
    }
  }

  // Lógica de Polling reutilizável
  Future<void> _pollResults(String searchId, {int attempts = 20}) async {
    final dio = ref.read(dioProvider);
    final notifier = ref.read(searchResultsProvider.notifier);

    // Aumentamos para 20 tentativas de 2s (Total ~40s de busca automática)
    for (int i = 1; i <= attempts; i++) {
      await Future.delayed(const Duration(seconds: 2));

      try {
        final resultsResp = await dio.get('/results/$searchId');
        final List<dynamic> data = resultsResp.data;
        
        // Se a lista mudou ou cresceu, atualizamos a tela
        if (data.isNotEmpty) {
           print('📦 [Poller] Recebidos: ${data.length} itens (Tentativa $i)');
           notifier.state = data;
        } else {
           print('📦 [Poller] Nenhum resultado ainda (Tentativa $i)...');
        }
      } catch (e) {
        print('⚠️ Erro polling: $e');
      }
    }
  }

  Future<void> download(Map<String, dynamic> item) async {
    final dio = ref.read(dioProvider);
    try {
      await dio.post('/download', data: {
        "username": item['username'],
        "filename": item['filename'],
        "size": item['size']
      });
      print('⬇️ Download solicitado: ${item['display_name']}');
    } catch (e) {
      print('❌ Erro no download: $e');
      rethrow;
    }
  }
}

// --- UI ---

void main() {
  runApp(const ProviderScope(child: OrfeuApp()));
}

class OrfeuApp extends StatelessWidget {
  const OrfeuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Orfeu',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD4AF37),
          brightness: Brightness.dark,
          surface: const Color(0xFF121212),
          primary: const Color(0xFFD4AF37),
        ),
        useMaterial3: true,
        textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withOpacity(0.05),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          prefixIconColor: Colors.white54,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final TextEditingController _queryController = TextEditingController();

  void _handleSearch() async {
    FocusScope.of(context).unfocus();
    try {
      await ref.read(searchControllerProvider).search(_queryController.text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(searchResultsProvider);
    final isLoading = ref.watch(isLoadingProvider);
    final hasSearched = ref.watch(hasSearchedProvider);
    final currentSearchId = ref.watch(currentSearchIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.music_note, color: Color(0xFFD4AF37)),
            const SizedBox(width: 10),
            Text('Orfeu', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          // Botão de Refresh Manual (Só aparece se já tivermos buscado algo)
          if (currentSearchId != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: "Atualizar Resultados",
              onPressed: () {
                ref.read(searchControllerProvider).refresh();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Buscando novos resultados...'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            )
        ],
        centerTitle: false,
        backgroundColor: Colors.black,
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _queryController,
              decoration: InputDecoration(
                hintText: 'O que você quer ouvir?',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward, color: Color(0xFFD4AF37)),
                  onPressed: _handleSearch,
                ),
              ),
              onSubmitted: (_) => _handleSearch(),
            ),
          ),

          Expanded(
            child: (isLoading && results.isEmpty)
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: Color(0xFFD4AF37)),
                        SizedBox(height: 20),
                        Text("Consultando o submundo..."),
                        Text("(Isso pode levar alguns segundos)", style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  )
                : results.isEmpty
                    ? Center(
                        child: hasSearched
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.search_off, size: 60, color: Colors.white.withOpacity(0.3)),
                                  const SizedBox(height: 16),
                                  Text("Nenhum resultado ainda.", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16)),
                                  const SizedBox(height: 10),
                                  // Dica para o usuário
                                  TextButton.icon(
                                    onPressed: () => ref.read(searchControllerProvider).refresh(),
                                    icon: const Icon(Icons.refresh, color: Color(0xFFD4AF37)),
                                    label: const Text("Tentar novamente", style: TextStyle(color: Color(0xFFD4AF37))),
                                  )
                                ],
                              )
                            : Text("Busque por Artista ou Música", style: TextStyle(color: Colors.white.withOpacity(0.3))),
                      )
                    : ListView.builder(
                        itemCount: results.length,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemBuilder: (context, index) {
                          final item = results[index];
                          return _buildResultCard(item, context, ref);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(Map<String, dynamic> item, BuildContext context, WidgetRef ref) {
    final isFlac = item['extension'] == 'flac';
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.white.withOpacity(0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isFlac ? const Color(0xFFD4AF37).withOpacity(0.3) : Colors.transparent,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        // AÇÃO DE TOCAR: Abre o PlayerScreen
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => PlayerScreen(item: item)),
          );
        },
        child: ListTile(
          contentPadding: const EdgeInsets.all(12),
          leading: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: isFlac ? const Color(0xFFD4AF37).withOpacity(0.2) : Colors.grey.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                isFlac ? "FLAC" : "MP3",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: isFlac ? const Color(0xFFD4AF37) : Colors.grey,
                ),
              ),
            ),
          ),
          title: Text(
            item['display_name'],
            style: const TextStyle(fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            "${(item['size'] / 1024 / 1024).toStringAsFixed(1)} MB • ${item['bitrate']} kbps",
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.download_rounded),
            onPressed: () async {
               try {
                 await ref.read(searchControllerProvider).download(item);
                 if (context.mounted) {
                   ScaffoldMessenger.of(context).showSnackBar(
                     SnackBar(content: Text('Baixando "${item['display_name']}"...'), backgroundColor: Colors.green),
                   );
                 }
               } catch (e) {
                 if (context.mounted) {
                   ScaffoldMessenger.of(context).showSnackBar(
                     SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
                   );
                 }
               }
            },
          ),
        ),
      ),
    );
  }
}

// --- TELA DO PLAYER (ATUALIZADA) ---
class PlayerScreen extends StatefulWidget {
  final Map<String, dynamic> item;
  const PlayerScreen({super.key, required this.item});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late AudioPlayer _audioPlayer;
  bool _isPlaying = false;
  String _currentQuality = 'lossless';
  Map<String, dynamic>? _metadata;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _initPlayer();
    _fetchMetadata();
  }

  Future<void> _fetchMetadata() async {
    try {
      final dio = Dio(BaseOptions(baseUrl: baseUrl));
      final filename = Uri.encodeComponent(widget.item['filename']);
      final resp = await dio.get('/metadata?filename=$filename');
      if (mounted) {
        setState(() {
          _metadata = resp.data;
        });
      }
    } catch (e) {
      print("Erro ao buscar metadados: $e");
    }
  }

  Future<void> _initPlayer() async {
    try {
      final filename = Uri.encodeComponent(widget.item['filename']);
      // Monta URL de stream: /stream?filename=...&quality=...
      final url = '$baseUrl/stream?filename=$filename&quality=$_currentQuality';
      
      print("Tentando tocar: $url");
      await _audioPlayer.setUrl(url);
      _audioPlayer.play();
      setState(() => _isPlaying = true);
    } catch (e) {
      print("Erro no player: $e");
      setState(() => _error = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao tocar (O download terminou?): $e')),
        );
      }
    }
  }

  void _changeQuality(String quality) {
    setState(() {
      _currentQuality = quality;
      _isPlaying = false; // Pausa enquanto recarrega
    });
    _initPlayer(); // Recarrega com nova URL
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filenameEncoded = Uri.encodeComponent(widget.item['filename']);
    final coverUrl = '$baseUrl/cover?filename=$filenameEncoded';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Tocando Agora",
          style: GoogleFonts.outfit(fontSize: 14, letterSpacing: 2),
        ),
        centerTitle: true,
      ),
      // Adicionado SingleChildScrollView para evitar overflow em telas menores
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // --- CAPA DO ÁLBUM ---
              Container(
                height: 320,
                width: 320,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 30,
                      spreadRadius: 5,
                    )
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.network(
                  coverUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: Colors.white10,
                    child: const Icon(Icons.music_note, size: 80, color: Colors.white24),
                  ),
                ),
              ),
              const SizedBox(height: 40),

              // --- TÍTULO E ARTISTA ---
              Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _metadata?['title'] ?? widget.item['display_name'],
                      style: GoogleFonts.outfit(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _metadata?['artist'] ?? "Artista Desconhecido",
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 20),
              
              // --- BADGE DE QUALIDADE ---
              if (_metadata != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4AF37).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.3)),
                  ),
                  child: Text(
                    _metadata!['tech_label'] ?? "Hi-Res",
                    style: const TextStyle(color: Color(0xFFD4AF37), fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),

              const SizedBox(height: 30),

              // --- BARRA DE PROGRESSO ---
              StreamBuilder<Duration>(
                stream: _audioPlayer.positionStream,
                builder: (context, snapshot) {
                  final position = snapshot.data ?? Duration.zero;
                  final duration = _audioPlayer.duration ?? Duration.zero;
                  return Column(
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        ),
                        child: Slider(
                          value: position.inSeconds.toDouble().clamp(0, duration.inSeconds.toDouble()),
                          max: duration.inSeconds.toDouble() > 0 ? duration.inSeconds.toDouble() : 1,
                          activeColor: const Color(0xFFD4AF37),
                          inactiveColor: Colors.white10,
                          onChanged: (val) {
                            _audioPlayer.seek(Duration(seconds: val.toInt()));
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_formatDuration(position), style: const TextStyle(color: Colors.white38, fontSize: 12)),
                            Text(_formatDuration(duration), style: const TextStyle(color: Colors.white38, fontSize: 12)),
                          ],
                        ),
                      )
                    ],
                  );
                },
              ),

              const SizedBox(height: 10),

              // --- CONTROLES ---
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.skip_previous_rounded, size: 32),
                    onPressed: () {}, // TODO: Playlist
                  ),
                  const SizedBox(width: 20),
                  Container(
                    width: 70,
                    height: 70,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: Icon(
                        _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: Colors.black,
                        size: 40,
                      ),
                      onPressed: () {
                        if (_isPlaying) {
                          _audioPlayer.pause();
                        } else {
                          _audioPlayer.play();
                        }
                        setState(() => _isPlaying = !_isPlaying);
                      },
                    ),
                  ),
                  const SizedBox(width: 20),
                  IconButton(
                    icon: const Icon(Icons.skip_next_rounded, size: 32),
                    onPressed: () {}, // TODO: Playlist
                  ),
                ],
              ),
              
              const SizedBox(height: 20),
              
              // --- SELETOR DE QUALIDADE (TRANSCODING) ---
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: ["low", "medium", "high", "lossless"].map((q) {
                  final isSelected = _currentQuality == q;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: ChoiceChip(
                      label: Text(q.toUpperCase()),
                      selected: isSelected,
                      onSelected: (val) => _changeQuality(q),
                      backgroundColor: Colors.transparent,
                      selectedColor: const Color(0xFFD4AF37),
                      labelStyle: TextStyle(
                        fontSize: 10,
                        color: isSelected ? Colors.black : Colors.white54,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final min = d.inMinutes.toString().padLeft(2, '0');
    final sec = (d.inSeconds % 60).toString().padLeft(2, '0');
    return "$min:$sec";
  }
}