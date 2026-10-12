import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Color(0xFF0A0A10),
  ));
  runApp(const LuauHubApp());
}

const accent = Color(0xFF7C5CFF);
const cyan = Color(0xFF3CC8FF);
const pink = Color(0xFFFF4FA0);
const panel = Color(0xFF14141E);
const neonGradient = LinearGradient(colors: [accent, cyan]);

class LuauHubApp extends StatelessWidget {
  const LuauHubApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Luau Hub',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF0A0A10),
          colorScheme: ColorScheme.fromSeed(
              seedColor: accent, brightness: Brightness.dark),
          useMaterial3: true,
        ),
        home: const Shell(),
      );
}

// ================= Modelo =================
class ScriptItem {
  final String title, game, code;
  final int views;
  ScriptItem(this.title, this.game, this.code, this.views);

  factory ScriptItem.fromJson(Map<String, dynamic> j) => ScriptItem(
        j['title'] ?? 'Sem título',
        (j['game'] is Map ? j['game']['name'] : j['game']) ?? 'Universal',
        j['script'] ?? '',
        j['views'] ?? 0,
      );

  Map<String, dynamic> toJson() =>
      {'title': title, 'game': game, 'script': code, 'views': views};
}

// ================= Estado =================
class AppState extends ChangeNotifier {
  final editor = TextEditingController(
      text: '-- Luau Hub\nlocal msg = "Olá, mundo!"\nprint(msg)\n');
  final logs = <String>[];
  List<ScriptItem> saved = [];

  AppState() {
    editor.addListener(notifyListeners);
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList('saved') ?? [];
    saved = raw.map((e) => ScriptItem.fromJson(jsonDecode(e))).toList();
    notifyListeners();
  }

  Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(
        'saved', saved.map((e) => jsonEncode(e.toJson())).toList());
  }

  void log(String m) {
    logs.add(m);
    notifyListeners();
  }

  void clearLogs() {
    logs.clear();
    notifyListeners();
  }

  void save(ScriptItem s) {
    saved.insert(0, s);
    _persist();
    notifyListeners();
  }

  void remove(ScriptItem s) {
    saved.remove(s);
    _persist();
    notifyListeners();
  }

  /// Checagem simples de balanceamento (não é um parser Luau completo).
  String validate() {
    final pairs = {'(': ')', '{': '}', '[': ']'};
    final stack = <String>[];
    for (final c in editor.text.split('')) {
      if (pairs.containsKey(c)) stack.add(pairs[c]!);
      if (pairs.values.contains(c)) {
        if (stack.isEmpty || stack.removeLast() != c) {
          return 'Erro: "$c" inesperado';
        }
      }
    }
    return stack.isEmpty
        ? 'OK: sem erros de balanceamento'
        : 'Erro: falta "${stack.last}"';
  }
}

final state = AppState();

// ================= Widgets base =================
class Glass extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color? border;
  const Glass(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(14),
      this.radius = 20,
      this.border});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.05),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                  color: border ?? Colors.white.withOpacity(.09), width: 1),
            ),
            child: child,
          ),
        ),
      );
}

class GlowButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;
  const GlowButton(
      {super.key,
      required this.label,
      required this.icon,
      required this.onTap,
      this.filled = true});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
          decoration: BoxDecoration(
            gradient: filled ? neonGradient : null,
            color: filled ? null : Colors.white.withOpacity(.06),
            borderRadius: BorderRadius.circular(16),
            border: filled
                ? null
                : Border.all(color: Colors.white.withOpacity(.14)),
            boxShadow: filled
                ? [
                    BoxShadow(
                        color: accent.withOpacity(.45),
                        blurRadius: 18,
                        offset: const Offset(0, 6))
                  ]
                : null,
          ),
          child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
        ),
      );
}

// ================= Shell =================
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int tab = 0;
  @override
  void initState() {
    super.initState();
    state.load();
  }

  void goEditor() => setState(() => tab = 0);

  @override
  Widget build(BuildContext context) {
    final pages = [
      const EditorPage(),
      LibraryPage(onOpen: goEditor),
      SavedPage(onOpen: goEditor),
      const SettingsPage(),
    ];
    return Scaffold(
      extendBody: true,
      body: Stack(children: [
        Positioned.fill(
            child: Image.asset('assets/bg.png', fit: BoxFit.cover)),
        SafeArea(
          bottom: false,
          child: Column(children: [
            const Header(),
            Expanded(
                child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: KeyedSubtree(key: ValueKey(tab), child: pages[tab]),
            )),
          ]),
        ),
      ]),
      bottomNavigationBar: _NavBar(
          index: tab, onChange: (i) => setState(() => tab = i)),
    );
  }
}

class Header extends StatelessWidget {
  const Header({super.key});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(14, 8, 14, 6),
        height: 96,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          image: const DecorationImage(
              image: AssetImage('assets/header.png'), fit: BoxFit.cover),
          border: Border.all(color: Colors.white.withOpacity(.1)),
          boxShadow: [
            BoxShadow(color: accent.withOpacity(.3), blurRadius: 24)
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(children: [
          Image.asset('assets/logo.png', width: 64, height: 64),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShaderMask(
                    shaderCallback: (r) => neonGradient.createShader(r),
                    child: const Text('LUAU HUB',
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                            color: Colors.white)),
                  ),
                  const Text('Editor & Biblioteca de scripts',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
                color: Colors.black.withOpacity(.35),
                borderRadius: BorderRadius.circular(20)),
            child: const Text('v2.0',
                style: TextStyle(color: cyan, fontWeight: FontWeight.bold)),
          ),
        ]),
      );
}

class _NavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChange;
  const _NavBar({required this.index, required this.onChange});

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.code_rounded, 'Editor'),
      (Icons.explore_rounded, 'Biblioteca'),
      (Icons.bookmark_rounded, 'Salvos'),
      (Icons.tune_rounded, 'Config'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Glass(
        radius: 28,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: List.generate(items.length, (i) {
            final sel = i == index;
            return Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChange(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    gradient: sel ? neonGradient : null,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: sel
                        ? [
                            BoxShadow(
                                color: accent.withOpacity(.5), blurRadius: 14)
                          ]
                        : null,
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(items[i].$1,
                        color: sel ? Colors.white : Colors.white54),
                    Text(items[i].$2,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: sel ? Colors.white : Colors.white54)),
                  ]),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

// ================= Editor =================
class EditorPage extends StatelessWidget {
  const EditorPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (_, __) {
        final lines = '\n'.allMatches(state.editor.text).length + 1;
        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 100),
          child: Column(children: [
            Expanded(
              flex: 5,
              child: Glass(
                padding: const EdgeInsets.all(0),
                child: Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 6, 0),
                    child: Row(children: [
                      const _Dot(Color(0xFFFF5F57)),
                      const _Dot(Color(0xFFFEBC2E)),
                      const _Dot(Color(0xFF28C840)),
                      const SizedBox(width: 10),
                      const Text('script.lua',
                          style: TextStyle(color: Colors.white54, fontSize: 12)),
                      const Spacer(),
                      IconButton(
                          tooltip: 'Colar',
                          icon: const Icon(Icons.content_paste_rounded, size: 20),
                          onPressed: () async {
                            final d = await Clipboard.getData('text/plain');
                            if (d?.text != null) state.editor.text = d!.text!;
                          }),
                      IconButton(
                          tooltip: 'Limpar',
                          icon: const Icon(Icons.delete_sweep_rounded, size: 20),
                          onPressed: () => state.editor.clear()),
                    ]),
                  ),
                  const Divider(height: 8, color: Colors.white12),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: 1400,
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 34,
                                  child: Text(
                                    List.generate(lines, (i) => '${i + 1}')
                                        .join('\n'),
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 14,
                                        height: 1.45,
                                        color: Colors.white24),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: state.editor,
                                    maxLines: null,
                                    cursorColor: cyan,
                                    keyboardType: TextInputType.multiline,
                                    style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 14,
                                        height: 1.45),
                                    decoration: const InputDecoration.collapsed(
                                        hintText: '-- seu código Luau'),
                                  ),
                                ),
                              ]),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: GlowButton(
                      label: 'Validar',
                      icon: Icons.verified_rounded,
                      onTap: () => state.log(state.validate()))),
              const SizedBox(width: 8),
              Expanded(
                  child: GlowButton(
                      filled: false,
                      label: 'Copiar',
                      icon: Icons.copy_rounded,
                      onTap: () {
                        Clipboard.setData(
                            ClipboardData(text: state.editor.text));
                        state.log('Copiado para a área de transferência');
                      })),
              const SizedBox(width: 8),
              Expanded(
                  child: GlowButton(
                      filled: false,
                      label: 'Salvar',
                      icon: Icons.bookmark_add_rounded,
                      onTap: () {
                        state.save(ScriptItem('Script ${state.saved.length + 1}',
                            'Local', state.editor.text, 0));
                        state.log('Script salvo');
                      })),
            ]),
            const SizedBox(height: 10),
            Expanded(
              flex: 2,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(.55),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: state.logs.isEmpty
                    ? const Text('> console vazio',
                        style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: Colors.white30))
                    : ListView(
                        reverse: true,
                        children: state.logs.reversed
                            .map((l) => Text('> $l',
                                style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                    color: l.startsWith('Erro')
                                        ? pink
                                        : const Color(0xFF7CFFB2))))
                            .toList()),
              ),
            ),
          ]),
        );
      },
    );
  }
}

class _Dot extends StatelessWidget {
  final Color c;
  const _Dot(this.c);
  @override
  Widget build(BuildContext context) => Container(
      width: 10,
      height: 10,
      margin: const EdgeInsets.only(right: 6),
      decoration: BoxDecoration(color: c, shape: BoxShape.circle));
}

// ================= Biblioteca =================
const badges = [
  'assets/badge_game.png',
  'assets/badge_hot.png',
  'assets/badge_star.png'
];

class LibraryPage extends StatefulWidget {
  final VoidCallback onOpen;
  const LibraryPage({super.key, required this.onOpen});
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final q = TextEditingController();
  List<ScriptItem> items = [];
  bool loading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    fetch();
  }

  Future<void> fetch([String query = '']) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final uri = query.isEmpty
          ? Uri.parse('https://scriptblox.com/api/script/fetch')
          : Uri.parse(
              'https://scriptblox.com/api/script/search?q=${Uri.encodeQueryComponent(query)}');
      final r = await http.get(uri).timeout(const Duration(seconds: 15));
      final data = jsonDecode(r.body);
      items = (data['result']['scripts'] as List)
          .map((e) => ScriptItem.fromJson(e))
          .toList();
    } catch (e) {
      error = 'Falha ao carregar. Verifique a internet.';
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
      child: Column(children: [
        Glass(
          radius: 18,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            controller: q,
            textInputAction: TextInputAction.search,
            onSubmitted: fetch,
            decoration: const InputDecoration(
              hintText: 'Buscar scripts…',
              prefixIcon: Icon(Icons.search_rounded, color: cyan),
              border: InputBorder.none,
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (loading)
          const ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(8)),
              child: LinearProgressIndicator(color: accent, minHeight: 3)),
        if (error != null)
          Padding(
              padding: const EdgeInsets.all(12),
              child: Text(error!, style: const TextStyle(color: pink))),
        Expanded(
          child: items.isEmpty && !loading
              ? const _Empty('Nada por aqui')
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 110, top: 4),
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final s = items[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Glass(
                        child: Row(children: [
                          Image.asset(badges[i % badges.length],
                              width: 54, height: 54),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(s.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15)),
                                  const SizedBox(height: 3),
                                  Text('${s.game}  •  ${s.views} views',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 12)),
                                ]),
                          ),
                          IconButton(
                              tooltip: 'Abrir no editor',
                              icon: const Icon(Icons.edit_note_rounded,
                                  color: cyan),
                              onPressed: () {
                                state.editor.text = s.code;
                                widget.onOpen();
                              }),
                          IconButton(
                              tooltip: 'Salvar',
                              icon: const Icon(Icons.bookmark_add_outlined),
                              onPressed: () {
                                state.save(s);
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('Salvo!'),
                                        duration: Duration(seconds: 1)));
                              }),
                        ]),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

// ================= Salvos =================
class SavedPage extends StatelessWidget {
  final VoidCallback onOpen;
  const SavedPage({super.key, required this.onOpen});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: state,
        builder: (_, __) => state.saved.isEmpty
            ? const _Empty('Nenhum script salvo ainda')
            : ListView(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 110),
                children: state.saved
                    .asMap()
                    .entries
                    .map((e) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: GestureDetector(
                            onTap: () {
                              state.editor.text = e.value.code;
                              onOpen();
                            },
                            child: Glass(
                              child: Row(children: [
                                Image.asset(badges[e.key % badges.length],
                                    width: 46, height: 46),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text(e.value.title,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700)),
                                      Text(e.value.game,
                                          style: const TextStyle(
                                              color: Colors.white54,
                                              fontSize: 12)),
                                    ])),
                                IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        color: pink),
                                    onPressed: () => state.remove(e.value)),
                              ]),
                            ),
                          ),
                        ))
                    .toList(),
              ),
      );
}

class _Empty extends StatelessWidget {
  final String text;
  const _Empty(this.text);
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Image.asset('assets/empty.png', width: 180),
          Text(text, style: const TextStyle(color: Colors.white54)),
        ]),
      );
}

// ================= Config =================
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 110),
        children: [
          Glass(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.delete_sweep_rounded, color: cyan),
              title: const Text('Limpar console'),
              onTap: state.clearLogs,
            ),
          ),
          const SizedBox(height: 10),
          Glass(
            child: Row(children: [
              Image.asset('assets/logo.png', width: 56),
              const SizedBox(width: 10),
              const Expanded(
                  child: Text(
                      'Luau Hub 2.0\nEditor e biblioteca de scripts. Este app não executa código no Roblox.',
                      style: TextStyle(color: Colors.white70))),
            ]),
          ),
        ],
      );
}
