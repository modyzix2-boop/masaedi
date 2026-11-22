import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String kBase = 'https://masaedi-web.onrender.com';
const Color kTeal = Color(0xFF0D9488);
const Color kTealDark = Color(0xFF0A7A6E);
const Color kBg = Color(0xFFFAF9F5);
const Color kInk = Color(0xFF1F1E1B);
const Color kLine = Color(0xFFEDECE6);

void main() => runApp(const MasaediApp());

class MasaediApp extends StatelessWidget {
  const MasaediApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'مساعدي',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Cairo',
        colorScheme: ColorScheme.fromSeed(seedColor: kTeal, primary: kTeal, surface: kBg),
        scaffoldBackgroundColor: kBg,
        appBarTheme: const AppBarTheme(backgroundColor: kBg, foregroundColor: kInk, elevation: 0),
      ),
      home: const Gate(),
    );
  }
}

class ModelInfo {
  final String id;
  final String name;
  ModelInfo(this.id, this.name);
}

class Api {
  static String key = '';
  static String name = '';
  static Map<String, String> get headers => {'Authorization': 'Bearer $key', 'Content-Type': 'application/json'};

  static Future<bool> validateKey(String k) async {
    try {
      final r = await http.get(Uri.parse('$kBase/v1/models'), headers: {'Authorization': 'Bearer $k'}).timeout(const Duration(seconds: 90));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> listChats() async {
    final r = await http.get(Uri.parse('$kBase/v1/client/chats'), headers: headers).timeout(const Duration(seconds: 90));
    if (r.statusCode != 200) throw Exception('chats ${r.statusCode}');
    final d = jsonDecode(utf8.decode(r.bodyBytes));
    return (d['chats'] as List).cast<Map<String, dynamic>>();
  }

  static Future<Map<String, dynamic>> getChat(String id) async {
    final r = await http.get(Uri.parse('$kBase/v1/client/chats/$id'), headers: headers).timeout(const Duration(seconds: 90));
    if (r.statusCode != 200) throw Exception('chat ${r.statusCode}');
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  static Future<void> putChat(String id, String title, List<Map<String, dynamic>> msgs) async {
    await http
        .post(Uri.parse('$kBase/v1/client/chats/$id'), headers: headers, body: jsonEncode({'title': title, 'msgs': msgs}))
        .timeout(const Duration(seconds: 90));
  }

  static Future<void> deleteChat(String id) async {
    try {
      await http.delete(Uri.parse('$kBase/v1/client/chats/$id'), headers: headers).timeout(const Duration(seconds: 30));
    } catch (_) {}
  }

  static Future<List<ModelInfo>> listModels() async {
    try {
      final r = await http.get(Uri.parse('$kBase/v1/models'), headers: headers).timeout(const Duration(seconds: 90));
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      final out = <ModelInfo>[];
      for (final m in (d['data'] as List)) {
        if (m['available'] == true && !_ChatScreenState.hiddenIds.contains(m['id'])) {
          out.add(ModelInfo(m['id'] as String, (m['name'] ?? m['id']) as String));
        }
      }
      return out;
    } catch (_) {
      return [ModelInfo('auto', 'تلقائي')];
    }
  }

  static Future<List<Map<String, dynamic>>> getProviders() async {
    final r = await http.get(Uri.parse('$kBase/v1/providers'), headers: headers).timeout(const Duration(seconds: 90));
    if (r.statusCode != 200) throw Exception('providers ${r.statusCode}');
    final d = jsonDecode(utf8.decode(r.bodyBytes));
    return (d['providers'] as List).cast<Map<String, dynamic>>();
  }

  static Future<Map<String, Map<String, String>>> getProviderKeys() async {
    try {
      final r = await http.get(Uri.parse('$kBase/v1/client/provider-keys'), headers: headers).timeout(const Duration(seconds: 90));
      if (r.statusCode != 200) return {};
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      final out = <String, Map<String, String>>{};
      for (final k in (d['providers'] as List)) {
        out[k['platform'].toString()] = {'key': (k['key'] ?? '').toString(), 'label': (k['label'] ?? '').toString()};
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  static Future<Map<String, dynamic>> getUsage() async {
    final r = await http.get(Uri.parse('$kBase/v1/usage'), headers: headers).timeout(const Duration(seconds: 90));
    if (r.statusCode != 200) throw Exception('usage ${r.statusCode}');
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  static Stream<String> streamChat(List<Map<String, dynamic>> msgs, String model, {void Function(String served)? onServed}) async* {
    final req = http.Request('POST', Uri.parse('$kBase/v1/chat/completions'));
    req.headers.addAll(headers);
    final wire = msgs
        .where((m) => m['gen'] == null && m['art'] != true)
        .toList()
        .reversed
        .take(19)
        .toList()
        .reversed
        .map((m) => {'role': m['r'] == 'u' ? 'user' : 'assistant', 'content': (m['c'] ?? '').toString()})
        .toList();
    req.body = jsonEncode({
      'model': model,
      'messages': wire,
      'stream': true,
      'stream_options': {'include_usage': true},
    });
    final client = http.Client();
    try {
      final resp = await client.send(req).timeout(const Duration(seconds: 120));
      if (resp.statusCode != 200) {
        throw Exception('خطأ من السيرفر (${resp.statusCode})');
      }
      var buf = '';
      await for (final chunk in resp.stream.transform(utf8.decoder)) {
        buf += chunk;
        var idx = buf.indexOf('\n');
        while (idx >= 0) {
          final line = buf.substring(0, idx).trim();
          buf = buf.substring(idx + 1);
          idx = buf.indexOf('\n');
          if (line.startsWith('data:')) {
            final data = line.substring(5).trim();
            if (data == '[DONE]') return;
            try {
              final j = jsonDecode(data);
              final rm = j['model'];
              if (rm is String && onServed != null) onServed(rm);
              final delta = j['choices']?[0]?['delta'];
              final c = delta?['content'];
              if (c is String && c.isNotEmpty) yield c;
            } catch (_) {}
          }
        }
      }
    } finally {
      client.close();
    }
  }
}

String modelLabel(String id) {
  if (id == 'auto') return 'تلقائي';
  if (id == 'fusion') return 'فريق';
  final s = id.split('/').last;
  return s.length > 20 ? '${s.substring(0, 20)}…' : s;
}

class Gate extends StatefulWidget {
  const Gate({super.key});
  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> {
  bool loading = true;
  bool loggedIn = false;
  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      Api.key = p.getString('key') ?? '';
      Api.name = p.getString('name') ?? '';
      setState(() {
        loggedIn = Api.key.isNotEmpty;
        loading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: PulsingDots()));
    if (!loggedIn) {
      return LoginScreen(onDone: () => setState(() => loggedIn = true));
    }
    return ChatListScreen(onLogout: () => setState(() => loggedIn = false));
  }
}

/// Claude-style pulsing dots loader
class PulsingDots extends StatefulWidget {
  final Color color;
  final double size;
  const PulsingDots({super.key, this.color = kTeal, this.size = 9});
  @override
  State<PulsingDots> createState() => _PulsingDotsState();
}

class _PulsingDotsState extends State<PulsingDots> with SingleTickerProviderStateMixin {
  late final AnimationController c;
  @override
  void initState() {
    super.initState();
    c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: c,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final t = (c.value + i / 3) % 1.0;
            final wave = math.sin(t * math.pi);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: widget.color.withOpacity(0.25 + 0.75 * wave),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}

class LoginScreen extends StatefulWidget {
  final VoidCallback onDone;
  const LoginScreen({super.key, required this.onDone});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final nameC = TextEditingController();
  final keyC = TextEditingController();
  bool busy = false;
  String? err;

  Future<void> login() async {
    final k = keyC.text.trim();
    final n = nameC.text.trim();
    if (k.isEmpty || n.isEmpty) {
      setState(() => err = 'اكتب اسمك والمفتاح');
      return;
    }
    setState(() {
      busy = true;
      err = null;
    });
    final ok = await Api.validateKey(k);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        busy = false;
        err = 'المفتاح مش شغال أو السيرفر بيبدأ دلوقتي، جرّب تاني بعد ثواني';
      });
      return;
    }
    final p = await SharedPreferences.getInstance();
    await p.setString('key', k);
    await p.setString('name', n);
    Api.key = k;
    Api.name = n;
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: kLine),
                boxShadow: const [BoxShadow(color: Color(0x11000000), blurRadius: 30, offset: Offset(0, 8))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: kTeal, borderRadius: BorderRadius.circular(16)),
                    child: const Icon(Icons.auto_awesome, color: Colors.white, size: 28),
                  ),
                  const SizedBox(height: 18),
                  const Text('تسجيل الدخول', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: kInk)),
                  const SizedBox(height: 20),
                  TextField(controller: nameC, textAlign: TextAlign.right, decoration: _dec('اسمك')),
                  const SizedBox(height: 12),
                  TextField(controller: keyC, textAlign: TextAlign.right, decoration: _dec('مفتاح التشغيل (freellmapi-...)'), obscureText: true),
                  if (err != null) ...[
                    const SizedBox(height: 10),
                    Text(err!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFB3261E))),
                  ],
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: busy ? null : login,
                    style: FilledButton.styleFrom(backgroundColor: kTeal, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('دخول', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 12),
                  const Text('اسمك ومفتاحك بيتخزنوا على جهازك بس.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.black54)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: kBg,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      );
}

class ChatListScreen extends StatefulWidget {
  final VoidCallback onLogout;
  const ChatListScreen({super.key, required this.onLogout});
  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  List<Map<String, dynamic>> chats = [];
  bool loading = true;
  String? err;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    setState(() {
      loading = true;
      err = null;
    });
    try {
      final c = await Api.listChats();
      if (!mounted) return;
      setState(() {
        chats = c;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        err = 'السيرفر ممكن يكون بيبدأ، اسحب لتحديث الصفحة بعد ثواني';
      });
    }
  }

  void newChat() {
    final id = 'c${DateTime.now().millisecondsSinceEpoch}';
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(chatId: id, title: 'محادثة جديدة'))).then((_) => refresh());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('أهلاً يا ${Api.name}', style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.hub_outlined, size: 20, color: kTeal),
            label: const Text('المزودون', style: TextStyle(color: kTeal, fontWeight: FontWeight.w700, fontSize: 13)),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProvidersScreen())),
          ),
          TextButton.icon(
            icon: const Icon(Icons.insights_outlined, size: 20, color: kTeal),
            label: const Text('لوحة التحكم', style: TextStyle(color: kTeal, fontWeight: FontWeight.w700, fontSize: 13)),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DashboardScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'خروج',
            onPressed: () async {
              final p = await SharedPreferences.getInstance();
              await p.remove('key');
              widget.onLogout();
            },
          )
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: newChat, backgroundColor: kTeal, icon: const Icon(Icons.add, color: Colors.white), label: const Text('محادثة جديدة', style: TextStyle(color: Colors.white))),
      body: RefreshIndicator(
        color: kTeal,
        onRefresh: refresh,
        child: loading
            ? const Center(child: PulsingDots())
            : err != null
                ? ListView(children: [Padding(padding: const EdgeInsets.all(48), child: Text(err!, textAlign: TextAlign.center))])
                : chats.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 120),
                          Icon(Icons.chat_bubble_outline, size: 56, color: Colors.black26),
                          SizedBox(height: 12),
                          Text('مفيش محادثات لسه، ابدأ واحدة جديدة', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: chats.length,
                        itemBuilder: (_, i) {
                          final c = chats[i];
                          final t = (c['updated'] as num?)?.toInt() ?? 0;
                          final dt = t > 0 ? DateTime.fromMillisecondsSinceEpoch(t) : null;
                          return Dismissible(
                            key: Key(c['id'].toString()),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.only(left: 24),
                              decoration: BoxDecoration(color: const Color(0xFFB3261E), borderRadius: BorderRadius.circular(14)),
                              child: const Icon(Icons.delete_outline, color: Colors.white),
                            ),
                            onDismissed: (_) => Api.deleteChat(c['id'].toString()),
                            child: Card(
                              color: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: kLine)),
                              child: ListTile(
                                title: Text(c['title']?.toString() ?? 'محادثة', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                                subtitle: dt != null ? Text('${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}') : null,
                                trailing: const Icon(Icons.chevron_left),
                                onTap: () => Navigator.of(context)
                                    .push(MaterialPageRoute(builder: (_) => ChatScreen(chatId: c['id'].toString(), title: c['title']?.toString() ?? 'محادثة')))
                                    .then((_) => refresh()),
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? usage;
  String? err;
  bool showKey = false;

  @override
  void initState() {
    super.initState();
    Api.getUsage().then((u) {
      if (mounted) setState(() => usage = u);
    }).catchError((_) {
      if (mounted) setState(() => err = 'مش قادر أوصل للسيرفر دلوقتي');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('لوحة التحكم', style: TextStyle(fontWeight: FontWeight.w700))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Row(children: [Icon(Icons.key, color: kTeal, size: 20), SizedBox(width: 8), Text('مفتاحك', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))]),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: kLine)),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      showKey ? Api.key : '••••••••••••••••••••••••••',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.ltr,
                    ),
                  ),
                  IconButton(icon: Icon(showKey ? Icons.visibility_off : Icons.visibility, size: 20), onPressed: () => setState(() => showKey = !showKey)),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: Api.key));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('المفتاح اتنسخ'), duration: Duration(seconds: 1)));
                    },
                  ),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          if (err != null) _card(child: Text(err!, textAlign: TextAlign.center)),
          if (usage == null && err == null) const Center(child: Padding(padding: EdgeInsets.all(24), child: PulsingDots())),
          if (usage != null) ...[
            Row(children: [
              Expanded(child: _statCard('طلبات الشهر', '${usage!['requests'] ?? 0}', Icons.bolt)),
              const SizedBox(width: 12),
              Expanded(child: _statCard('توكنز الشهر', _fmt(usage!['tokens'] ?? 0), Icons.data_usage)),
            ]),
            const SizedBox(height: 14),
            _card(child: Row(children: [
              const Icon(Icons.event_repeat, color: kTeal, size: 20),
              const SizedBox(width: 8),
              Text('العداد بيتصفّر يوم ${_resetDate()}', style: const TextStyle(fontSize: 15)),
            ])),
            const SizedBox(height: 14),
            if ((usage!['byPlatform'] as List?)?.isNotEmpty == true)
              _card(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Text('الاستهلاك حسب المزود', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 10),
                  ...((usage!['byPlatform'] as List).map((p) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          Expanded(child: Text(p['platform'].toString())),
                          Text('${p['requests']} طلب', style: const TextStyle(color: Colors.black54, fontSize: 13)),
                          const SizedBox(width: 12),
                          Text(_fmt(p['tokens'] ?? 0), style: const TextStyle(fontWeight: FontWeight.w700)),
                        ]),
                      ))),
                ]),
              ),
          ],
        ],
      ),
    );
  }

  String _resetDate() {
    try {
      final d = DateTime.parse(usage!['resetsAt'].toString()).toLocal();
      return '${d.day}/${d.month}';
    } catch (_) {
      return 'أول الشهر الجاي';
    }
  }

  String _fmt(dynamic n) {
    final v = (n as num).toInt();
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return '$v';
  }

  Widget _statCard(String label, String value, IconData icon) => _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: kTeal, size: 22),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: kInk)),
          Text(label, style: const TextStyle(color: Colors.black54, fontSize: 13)),
        ]),
      );

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: kLine)),
        child: child,
      );
}

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String title;
  const ChatScreen({super.key, required this.chatId, required this.title});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const favIds = ['auto', 'fusion', 'llama-3.3-70b-fp8-fast', 'gpt-oss-120b'];
  // probe-verified identities (2026-11-22): served model matches the label family
  static const verifiedIds = {
    'qwen3.8-27b','gpt-oss-120b','nemotron-3.5-super-vl','north-mini-code','nemotron-3-ultra-550b',
    'kilo-auto','qwen3.5-9b','free-router','nemotron-3.5-lightning','nemotron-3-nano-30b-reasoning',
    'nemotron-3-nano-omni-reasoning','llama-3.3-70b-fp8-fast','llama-4-scout','command-a-vision',
    'mistral-small-3.1-24b','qwen2.5-coder-32b','llama-3.2-3b','qwen3guard-gen-8b','qwen3guard-gen-0.6b',
    'gemma-sea-lion-v4-27b','allam-2-7b','command-r-2','granite-4.0-h-micro','mistral-7b-instruct-v0.2-lora',
    'aya-expanse-32b','aya-vision-32b','command-r','llama-guard-3-8b','gemma-2b-it-lora',
    'llama-prompt-guard-2-22m','llama-prompt-guard-2-86m'
  };
  // aliases proven to serve a DIFFERENT model than the label, plus catalog phantoms (404): hidden
  static const hiddenIds = {
    'claude-opus-4-5','claude-sonnet-4-5','claude-haiku-4-5',
    'dots3-note-preview','gemini-2.5-flash','gemini-2.5-flash-lite','nemotron-3-120b','qwq-32b',
    'deepseek-r1-distill-qwen-32b','llama-3.2-1b-instruct','llama-3.2-1b-unsloth','llama-3-2-1b-instruct',
    'ctx65536-magidonia-24b-heretic','llama-2-7b-chat-lora','gemma-7b-it-lora','l3-8b-stheno-v3-2-q5-k-m',
    'llava-1.5-7b','thedrummer-behemoth-128b-v3-q4-k-m','gemma-4-e4b-uncensored-aggressive'
  };
  final inputC = TextEditingController();
  final scrollC = ScrollController();
  List<Map<String, dynamic>> msgs = [];
  List<ModelInfo> models = [ModelInfo('auto', 'تلقائي')];
  String model = 'auto';
  bool sending = false;
  bool loading = true;
  bool compareMode = false;
  final Set<String> compareSet = {'llama-3.3-70b-fp8-fast', 'gpt-oss-120b'};
  late String title;

  @override
  void initState() {
    super.initState();
    title = widget.title;
    Api.listModels().then((m) {
      if (mounted && m.isNotEmpty) setState(() => models = m);
    });
    Api.getChat(widget.chatId).then((c) {
      if (!mounted) return;
      setState(() {
        msgs = ((c['msgs'] as List?) ?? []).cast<Map<String, dynamic>>();
        title = c['title']?.toString() ?? title;
        loading = false;
      });
    }).catchError((_) {
      if (mounted) setState(() => loading = false);
    });
  }

  static List<String> modelTags(String id) {
    final l = id.toLowerCase();
    final t = <String>[];
    if (l.contains('coder') || l.contains('mini-code')) t.add('كود');
    if (l.contains('vision') || l.contains('-vl') || l.contains('moondream')) t.add('تحليل الصور');
    if (l.contains('reasoning') || l.contains('120b') || l.contains('397b') || l.contains('550b') || l.contains('behemoth')) t.add('مهام');
    if (l.contains('aya') || l.contains('allam') || l.contains('arabic')) t.add('عربي');
    if (l.contains('guard') || l.contains('safeguard')) t.add('أدوات');
    if (t.isEmpty) t.add('حديث');
    if (!t.contains('حديث') && (l.contains('it') || l.contains('instruct') || l.contains('chat'))) t.add('حديث');
    return t;
  }

  static const tagOrder = ['كود', 'حديث', 'تحليل الصور', 'مهام', 'عربي', 'أدوات'];

  static IconData tagIcon(String t) {
    switch (t) {
      case 'كود':
        return Icons.code;
      case 'تحليل الصور':
        return Icons.image_outlined;
      case 'مهام':
        return Icons.psychology_outlined;
      case 'عربي':
        return Icons.translate;
      case 'أدوات':
        return Icons.build_outlined;
      default:
        return Icons.chat_bubble_outline;
    }
  }

  void openModelPicker() {
    final searchC = TextEditingController();
    String q = '';
    String tagFilter = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final filtered = models.where((m) {
            if (q.isNotEmpty && !m.id.toLowerCase().contains(q.toLowerCase())) return false;
            if (tagFilter.isNotEmpty && !modelTags(m.id).contains(tagFilter)) return false;
            return true;
          }).toList();
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.8,
            maxChildSize: 0.95,
            builder: (_, sc) => Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Row(children: [
                  const Icon(Icons.hub_outlined, color: kTeal),
                  const SizedBox(width: 8),
                  Expanded(child: Text('${models.length} نموذج شغال — الأسماء المستعارة اتخفت', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: searchC,
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(
                    hintText: 'دوّر على نموذج...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: kBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                  onChanged: (v) => setS(() => q = v),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: ChoiceChip(
                          label: const Text('الكل', style: TextStyle(fontSize: 12.5)),
                          selected: tagFilter.isEmpty,
                          selectedColor: kTeal,
                          labelStyle: TextStyle(color: tagFilter.isEmpty ? Colors.white : kInk, fontSize: 12.5),
                          onSelected: (_) => setS(() => tagFilter = ''),
                        ),
                      ),
                      ...tagOrder.map((t) => Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: ChoiceChip(
                              avatar: Icon(tagIcon(t), size: 15, color: tagFilter == t ? Colors.white : kTealDark),
                              label: Text(t),
                              selected: tagFilter == t,
                              selectedColor: kTeal,
                              labelStyle: TextStyle(color: tagFilter == t ? Colors.white : kInk, fontSize: 12.5),
                              onSelected: (_) => setS(() => tagFilter = tagFilter == t ? '' : t),
                            ),
                          )),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(child: Text('مفيش نماذج مطابقة', style: TextStyle(color: Colors.black45)))
                      : ListView.builder(
                          controller: sc,
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final m = filtered[i];
                            final sel = m.id == model;
                            final verified = _ChatScreenState.verifiedIds.contains(m.id);
                            final tags = modelTags(m.id);
                            return Card(
                              color: sel ? kTeal.withOpacity(0.07) : Colors.white,
                              elevation: 0,
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(color: sel ? kTeal : kLine, width: sel ? 1.4 : 1),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () {
                                  setState(() => model = m.id);
                                  Navigator.pop(ctx);
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                    Row(children: [
                                      Expanded(
                                        child: Text(m.id,
                                            style: TextStyle(fontWeight: sel ? FontWeight.w700 : FontWeight.w600, fontSize: 14.5, fontFamily: 'monospace'),
                                            textDirection: TextDirection.ltr,
                                            textAlign: TextAlign.right),
                                      ),
                                      if (verified)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(color: kTeal.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                            Icon(Icons.verified, size: 13, color: kTeal),
                                            SizedBox(width: 3),
                                            Text('موثّق', style: TextStyle(fontSize: 10.5, color: kTeal, fontWeight: FontWeight.w700)),
                                          ]),
                                        ),
                                      if (sel) ...[const SizedBox(width: 6), const Icon(Icons.check_circle, color: kTeal, size: 20)],
                                    ]),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: tags
                                          .map((t) => Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: kLine)),
                                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                                  Icon(tagIcon(t), size: 12, color: kTealDark),
                                                  const SizedBox(width: 4),
                                                  Text(t, style: const TextStyle(fontSize: 11, color: kInk)),
                                                ]),
                                              ))
                                          .toList(),
                                    ),
                                    if (!verified)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Text(m.id.startsWith('gemini') ? 'غير مؤكد — ممكن يكون Gemini حقيقي' : 'الاسم غير مؤكد من السيرفر',
                                            style: const TextStyle(fontSize: 10.5, color: Colors.black38), textAlign: TextAlign.right),
                                      ),
                                  ]),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }


  void openComparePicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          builder: (_, sc) => Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              const Row(children: [
                Icon(Icons.view_column_outlined, color: kTeal),
                SizedBox(width: 8),
                Expanded(child: Text('اختار من 2 لـ 3 نماذج للمقارنة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
              ]),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  controller: sc,
                  itemCount: models.length,
                  itemBuilder: (_, i) {
                    final m = models[i];
                    final sel = compareSet.contains(m.id);
                    return ListTile(
                      dense: true,
                      title: Text(m.id, textDirection: TextDirection.ltr, textAlign: TextAlign.right, style: const TextStyle(fontSize: 13.5, fontFamily: 'monospace')),
                      trailing: Icon(sel ? Icons.check_box : Icons.check_box_outline_blank, color: sel ? kTeal : Colors.black38, size: 22),
                      onTap: () {
                        if (sel) {
                          if (compareSet.length <= 2) return;
                          setS(() => compareSet.remove(m.id));
                          setState(() {});
                        } else {
                          if (compareSet.length >= 3) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الحد الأقصى 3 نماذج في المقارنة'), duration: Duration(seconds: 1)));
                            return;
                          }
                          setS(() => compareSet.add(m.id));
                          setState(() {});
                        }
                      },
                    );
                  },
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> sendCompare() async {
    final text = inputC.text.trim();
    if (text.isEmpty || sending) return;
    final sel = compareSet.where((id) => models.any((m) => m.id == id)).toList();
    if (sel.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختار نموذجين على الأقل من قائمة المقارنة'), duration: Duration(seconds: 2)));
      return;
    }
    inputC.clear();
    final grp = 'g${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      msgs.add({'r': 'u', 'c': text});
      for (final id in sel) {
        msgs.add({'r': 'a', 'c': '', 'model': id, 'grp': grp, 'art': true});
      }
      sending = true;
    });
    if (title == 'محادثة جديدة' || title == 'محادثة') {
      title = text.length > 40 ? '${text.substring(0, 40)}…' : text;
    }
    _toBottom();
    final ctxEnd = msgs.length - sel.length;
    final futures = <Future>[];
    for (var j = 0; j < sel.length; j++) {
      final mid = sel[j];
      final idx = ctxEnd + j;
      futures.add(() async {
        final buf = StringBuffer();
        String? served;
        try {
          await for (final part in Api.streamChat(List.of(msgs.sublist(0, ctxEnd)), mid, onServed: (sm) => served = sm)) {
            buf.write(part);
            if (mounted) setState(() => msgs[idx] = {'r': 'a', 'c': buf.toString(), 'model': mid, 'grp': grp, 'art': true, 'served': served});
          }
          if (buf.isEmpty) throw Exception('empty');
          _toBottom();
        } catch (_) {
          if (mounted && buf.isEmpty) {
            setState(() => msgs[idx] = {'r': 'a', 'c': 'النموذج ده مجاوبش دلوقتي، جرّب تاني', 'model': mid, 'grp': grp, 'art': true});
          }
        }
      }());
    }
    await Future.wait(futures);
    if (mounted) setState(() => sending = false);
    try {
      await Api.putChat(widget.chatId, title, msgs);
    } catch (_) {}
  }

  Future<void> send() async {
    final text = inputC.text.trim();
    if (text.isEmpty || sending) return;
    inputC.clear();
    setState(() {
      msgs.add({'r': 'u', 'c': text});
      msgs.add({'r': 'a', 'c': ''});
      sending = true;
    });
    if (title == 'محادثة جديدة' || title == 'محادثة') {
      title = text.length > 40 ? '${text.substring(0, 40)}…' : text;
    }
    _toBottom();
    final aiIdx = msgs.length - 1;
    final buf = StringBuffer();
    String? served;
    try {
      await for (final part in Api.streamChat(msgs.sublist(0, aiIdx), model, onServed: (sm) => served = sm)) {
        buf.write(part);
        if (mounted) {
          setState(() => msgs[aiIdx] = {'r': 'a', 'c': buf.toString(), 'model': model, 'served': served});
          _toBottom();
        }
      }
      if (buf.isEmpty) throw Exception('فاضي');
    } catch (e) {
      if (mounted) {
        setState(() => msgs[aiIdx] = {'r': 'a', 'c': buf.isEmpty ? 'حصل خطأ في الاتصال، جرّب تاني (السيرفر المجاني بياخد وقت يصحى أحيانًا)' : buf.toString()});
      }
    }
    setState(() => sending = false);
    try {
      await Api.putChat(widget.chatId, title, msgs);
    } catch (_) {}
  }

  List<Map<String, dynamic>> _items() {
    final out = <Map<String, dynamic>>[];
    var i = 0;
    while (i < msgs.length) {
      final g = msgs[i]['grp'];
      if (g != null) {
        final members = <int>[];
        while (i < msgs.length && msgs[i]['grp'] == g) {
          members.add(i);
          i++;
        }
        out.add({'grp': g, 'idx': members});
      } else {
        out.add({'idx': [i]});
        i++;
      }
    }
    return out;
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollC.hasClients) scrollC.jumpTo(scrollC.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final favs = models.where((m) => favIds.contains(m.id)).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        actions: [
          IconButton(
            icon: Icon(Icons.view_column_outlined, color: compareMode ? kTeal : Colors.black45),
            tooltip: 'وضع المقارنة',
            onPressed: sending ? null : () => setState(() => compareMode = !compareMode),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                if (compareMode)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: ActionChip(
                      avatar: const Icon(Icons.tune, size: 16, color: kTeal),
                      label: Text('مقارنة (${compareSet.length} نماذج)', style: const TextStyle(fontSize: 13)),
                      onPressed: sending ? null : openComparePicker,
                    ),
                  ),
                if (compareMode)
                  ...compareSet.map((id) => Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Chip(label: Text(modelLabel(id), style: const TextStyle(fontSize: 12.5))),
                      )),
                if (!compareMode)
                ...favs.map((m) => Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: ChoiceChip(
                        label: Text(modelLabel(m.id)),
                        selected: model == m.id,
                        selectedColor: kTeal,
                        labelStyle: TextStyle(color: model == m.id ? Colors.white : kInk, fontSize: 13),
                        onSelected: sending ? null : (_) => setState(() => model = m.id),
                      ),
                    )),
                if (!compareMode)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: ActionChip(
                    avatar: const Icon(Icons.apps, size: 16, color: kTeal),
                    label: Text('الكل (${models.length})', style: const TextStyle(fontSize: 13)),
                    onPressed: sending ? null : openModelPicker,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: loading
                ? const Center(child: PulsingDots())
                : ListView.builder(
                    controller: scrollC,
                    padding: const EdgeInsets.all(12),
                    itemCount: _items().length,
                    itemBuilder: (_, i) {
                      final it = _items()[i];
                      final idxs = (it['idx'] as List).cast<int>();
                      if (idxs.length == 1) {
                        final ix = idxs[0];
                        return Bubble(key: ValueKey('$ix-${msgs[ix].hashCode}'), m: msgs[ix], streaming: sending && ix == msgs.length - 1);
                      }
                      return CompareRow(key: ValueKey(it['grp'].toString()), members: idxs.map((x) => msgs[x]).toList(), streaming: sending);
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: inputC,
                      textAlign: TextAlign.right,
                      maxLines: 4,
                      minLines: 1,
                      decoration: InputDecoration(
                        hintText: 'اكتب رسالتك هنا...',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      ),
                      onSubmitted: (_) => compareMode ? sendCompare() : send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: sending ? kTealDark : kTeal,
                      boxShadow: const [BoxShadow(color: Color(0x330D9488), blurRadius: 12, offset: Offset(0, 4))],
                    ),
                    child: IconButton(
                      icon: sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.send, color: Colors.white),
                      onPressed: sending ? null : (compareMode ? sendCompare : send),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class Bubble extends StatefulWidget {
  final Map<String, dynamic> m;
  final bool streaming;
  const Bubble({super.key, required this.m, this.streaming = false});
  @override
  State<Bubble> createState() => _BubbleState();
}

class _BubbleState extends State<Bubble> {
  bool appeared = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => appeared = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isUser = widget.m['r'] == 'u';
    final text = (widget.m['c'] ?? '').toString();
    return AnimatedOpacity(
      opacity: appeared ? 1 : 0,
      duration: const Duration(milliseconds: 250),
      child: AnimatedSlide(
        offset: appeared ? Offset.zero : const Offset(0, 0.06),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        child: Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
            decoration: BoxDecoration(
              color: isUser ? kTeal : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isUser ? 16 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 16),
              ),
              border: isUser ? null : Border.all(color: kLine),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (text.isEmpty && widget.streaming)
                  const Padding(padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4), child: PulsingDots(size: 8))
                else if (isUser)
                  Text(text, textAlign: TextAlign.right, style: const TextStyle(color: Colors.white, fontSize: 15.5, height: 1.55))
                else
                  MarkdownBody(
                    data: text,
                    softLineBreak: true,
                    styleSheet: MarkdownStyleSheet(
                      p: const TextStyle(color: kInk, fontSize: 15.5, height: 1.6, fontFamily: 'Cairo'),
                      strong: const TextStyle(fontWeight: FontWeight.w700, color: kInk),
                      h1: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: kInk, height: 1.5),
                      h2: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: kInk, height: 1.5),
                      h3: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, color: kInk, height: 1.5),
                      listBullet: const TextStyle(color: kInk, fontSize: 15.5, height: 1.6),
                      code: TextStyle(fontFamily: 'monospace', fontSize: 13, backgroundColor: kTeal.withOpacity(0.08), color: kTealDark),
                      codeblockDecoration: BoxDecoration(color: const Color(0xFF262625), borderRadius: BorderRadius.circular(10)),
                      blockquoteDecoration: BoxDecoration(border: Border(right: BorderSide(color: kTeal.withOpacity(0.4), width: 3))),
                      horizontalRuleDecoration: const BoxDecoration(border: Border(top: BorderSide(color: kLine))),
                    ),
                  ),
                if (!isUser && text.isNotEmpty && (widget.m['served'] != null || widget.m['model'] != null))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      widget.m['served'] != null ? 'الرد الفعلي: ${widget.m['served']}' : modelLabel(widget.m['model'].toString()),
                      style: const TextStyle(fontSize: 10, color: Colors.black38),
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.left,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ProvidersScreen extends StatefulWidget {
  const ProvidersScreen({super.key});
  @override
  State<ProvidersScreen> createState() => _ProvidersScreenState();
}

class _ProvidersScreenState extends State<ProvidersScreen> {
  List<Map<String, dynamic>>? provs;
  Map<String, int>? counts;
  Map<String, Map<String, String>> keys = {};
  String? err;
  final shown = <String>{};

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => err = null);
    try {
      final res = await Future.wait([Api.getProviders(), Api.getProviderKeys()]);
      if (!mounted) return;
      setState(() {
        provs = res[0] as List<Map<String, dynamic>>;
        keys = res[1] as Map<String, Map<String, String>>;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => err = 'السيرفر ممكن يكون بيبدأ، اسحب لتحديث الصفحة بعد ثواني');
    }
  }

  ({String label, Color color, IconData icon}) _status(String s) {
    switch (s) {
      case 'healthy':
        return (label: 'شغال', color: const Color(0xFF15803D), icon: Icons.check_circle_outline);
      case 'rate_limited':
        return (label: 'محدود مؤقتًا', color: const Color(0xFFB45309), icon: Icons.hourglass_top);
      case 'invalid':
        return (label: 'فيه مشكلة', color: const Color(0xFFB3261E), icon: Icons.error_outline);
      default:
        return (label: 'لسه متأكدناش', color: Colors.black45, icon: Icons.help_outline);
    }
  }

  @override
  Widget build(BuildContext context) {
    final healthy = (provs ?? []).where((p) => p['status'] == 'healthy').length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('المزودون', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [IconButton(icon: const Icon(Icons.refresh), tooltip: 'تحديث', onPressed: load)],
      ),
      body: RefreshIndicator(
        color: kTeal,
        onRefresh: load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: kTeal.withOpacity(0.07), borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                const Icon(Icons.verified_user_outlined, color: kTeal, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    provs == null ? 'بنحمّل حالة المزودين...' : '$healthy من ${provs!.length} مزودين شغالين دلوقتي — الحالة لايف من السيرفر',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            if (err != null)
              Padding(padding: const EdgeInsets.all(32), child: Text(err!, textAlign: TextAlign.center))
            else if (provs == null)
              const Center(child: Padding(padding: EdgeInsets.all(48), child: PulsingDots()))
            else
              ...provs!.map(_provCard),
            const SizedBox(height: 8),
            const Text(
              'المفاتيح دي من حساباتك إنت عند المزودين، محفوظة على السيرفر بتاعك بس. زرار العين بيظهر المفتاح وزرار النسخ بياخده كامل.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.black45, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  Widget _provCard(Map<String, dynamic> p) {
    final platform = p['platform'].toString();
    final name = p['name'].toString();
    final st = _status(p['status'].toString());
    final k = keys[platform];
    final hasKey = k != null && (k['key'] ?? '').isNotEmpty;
    final isShown = shown.contains(platform);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: kLine)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(st.icon, color: st.color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5), textDirection: TextDirection.ltr, textAlign: TextAlign.right),
              Text(platform, style: const TextStyle(fontSize: 11, color: Colors.black38, fontFamily: 'monospace'), textDirection: TextDirection.ltr, textAlign: TextAlign.right),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: st.color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
            child: Text(st.label, style: TextStyle(color: st.color, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ]),
        if (p['status'] == 'rate_limited' && p['resume_at'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('بيرجع يشتغل حوالي ${_fmtTime(p['resume_at'].toString())}', style: const TextStyle(fontSize: 12.5, color: Color(0xFFB45309))),
          ),
        if (p['status'] == 'invalid' && p['last_error'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('آخر خطأ: ${p['last_error']}', style: const TextStyle(fontSize: 12, color: Color(0xFFB3261E)), maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        if (p['requests_remaining_pct'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('فاضل تقريبًا ${p['requests_remaining_pct']}% من حصة الطلبات', style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
          ),
        const SizedBox(height: 10),
        if (hasKey)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: kLine)),
            child: Row(children: [
              const Icon(Icons.vpn_key_outlined, size: 16, color: kTealDark),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isShown ? k!['key']! : '••••••••••••••••••••',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                ),
              ),
              IconButton(
                icon: Icon(isShown ? Icons.visibility_off : Icons.visibility, size: 19),
                tooltip: isShown ? 'إخفاء' : 'إظهار',
                onPressed: () => setState(() => isShown ? shown.remove(platform) : shown.add(platform)),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 19),
                tooltip: 'نسخ',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: k!['key']!));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('مفتاح $name اتنسخ'), duration: const Duration(seconds: 1)));
                },
              ),
            ]),
          )
        else
          const Row(children: [
            Icon(Icons.lock_open, size: 16, color: Colors.black38),
            SizedBox(width: 8),
            Expanded(child: Text('مفيش مفتاح — المزود ده بيشتغل مجانًا من غير حساب', style: TextStyle(fontSize: 12.5, color: Colors.black45))),
          ]),
      ]),
    );
  }

  String _fmtTime(String iso) {
    try {
      final d = DateTime.parse(iso).toLocal();
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return 'قريب';
    }
  }
}


class CompareRow extends StatelessWidget {
  final List<Map<String, dynamic>> members;
  final bool streaming;
  const CompareRow({super.key, required this.members, this.streaming = false});

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 560;
    final cards = members.map((m) => _cmpCard(context, m)).toList();
    if (!wide) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: cards);
    }
    final row = <Widget>[];
    for (var i = 0; i < cards.length; i++) {
      if (i > 0) row.add(const SizedBox(width: 8));
      row.add(Expanded(child: cards[i]));
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: row);
  }

  Widget _cmpCard(BuildContext context, Map<String, dynamic> m) {
    final text = (m['c'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: kLine)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          const Icon(Icons.smart_toy_outlined, size: 15, color: kTeal),
          const SizedBox(width: 6),
          Expanded(
            child: Text(modelLabel(m['model'].toString()),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kTealDark), overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, textAlign: TextAlign.right),
          ),
        ]),
        const SizedBox(height: 6),
        if (text.isEmpty && streaming)
          const Padding(padding: EdgeInsets.all(10), child: Center(child: PulsingDots(size: 7)))
        else if (text.isNotEmpty)
          MarkdownBody(
            data: text,
            softLineBreak: true,
            styleSheet: MarkdownStyleSheet(
              p: const TextStyle(color: kInk, fontSize: 14, height: 1.55, fontFamily: 'Cairo'),
              strong: const TextStyle(fontWeight: FontWeight.w700, color: kInk),
              listBullet: const TextStyle(color: kInk, fontSize: 14, height: 1.55),
              code: TextStyle(fontFamily: 'monospace', fontSize: 12, backgroundColor: kTeal.withOpacity(0.08), color: kTealDark),
              codeblockDecoration: BoxDecoration(color: const Color(0xFF262625), borderRadius: BorderRadius.circular(8)),
            ),
          ),
        if (text.isNotEmpty && m['served'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('الرد الفعلي: ${m['served']}', style: const TextStyle(fontSize: 9.5, color: Colors.black38), textDirection: TextDirection.ltr, textAlign: TextAlign.left),
          ),
      ]),
    );
  }
}
