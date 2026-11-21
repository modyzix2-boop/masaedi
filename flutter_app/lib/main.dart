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
        if (m['available'] == true) {
          out.add(ModelInfo(m['id'] as String, (m['name'] ?? m['id']) as String));
        }
      }
      return out;
    } catch (_) {
      return [ModelInfo('auto', 'تلقائي')];
    }
  }

  static Future<Map<String, dynamic>> getUsage() async {
    final r = await http.get(Uri.parse('$kBase/v1/usage'), headers: headers).timeout(const Duration(seconds: 90));
    if (r.statusCode != 200) throw Exception('usage ${r.statusCode}');
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  static Stream<String> streamChat(List<Map<String, dynamic>> msgs, String model) async* {
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
          IconButton(
            icon: const Icon(Icons.insights_outlined),
            tooltip: 'لوحة التحكم',
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
  static const favIds = ['auto', 'fusion', 'claude-opus-4-5', 'claude-sonnet-4-5'];
  final inputC = TextEditingController();
  final scrollC = ScrollController();
  List<Map<String, dynamic>> msgs = [];
  List<ModelInfo> models = [ModelInfo('auto', 'تلقائي')];
  String model = 'auto';
  bool sending = false;
  bool loading = true;
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

  void openModelPicker() {
    final searchC = TextEditingController();
    String q = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final filtered = models.where((m) => q.isEmpty || m.id.toLowerCase().contains(q.toLowerCase())).toList();
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.75,
            maxChildSize: 0.95,
            builder: (_, sc) => Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Row(children: [
                  const Icon(Icons.hub_outlined, color: kTeal),
                  const SizedBox(width: 8),
                  Text('${models.length} نموذج شغال دلوقتي', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
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
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    controller: sc,
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final m = filtered[i];
                      final sel = m.id == model;
                      return ListTile(
                        title: Text(m.id, style: TextStyle(fontWeight: sel ? FontWeight.w700 : FontWeight.w400), textDirection: TextDirection.ltr, textAlign: TextAlign.right),
                        subtitle: m.id != m.name ? Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.black45)) : null,
                        trailing: sel ? const Icon(Icons.check_circle, color: kTeal) : null,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        selected: sel,
                        selectedTileColor: kTeal.withOpacity(0.08),
                        onTap: () {
                          setState(() => model = m.id);
                          Navigator.pop(ctx);
                        },
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
    try {
      await for (final part in Api.streamChat(msgs.sublist(0, aiIdx), model)) {
        buf.write(part);
        if (mounted) {
          setState(() => msgs[aiIdx] = {'r': 'a', 'c': buf.toString(), 'model': model});
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

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollC.hasClients) scrollC.jumpTo(scrollC.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final favs = models.where((m) => favIds.contains(m.id)).toList();
    return Scaffold(
      appBar: AppBar(title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17))),
      body: Column(
        children: [
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
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
                    itemCount: msgs.length,
                    itemBuilder: (_, i) => Bubble(key: ValueKey('$i-${msgs[i].hashCode}'), m: msgs[i], streaming: sending && i == msgs.length - 1),
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
                      onSubmitted: (_) => send(),
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
                      onPressed: sending ? null : send,
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
                if (!isUser && widget.m['model'] != null && text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(modelLabel(widget.m['model'].toString()), style: const TextStyle(fontSize: 10, color: Colors.black38), textDirection: TextDirection.ltr),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
