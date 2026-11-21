import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String kBase = 'https://masaedi-web.onrender.com';
const Color kTeal = Color(0xFF0D9488);
const Color kBg = Color(0xFFFAF9F5);
const Color kInk = Color(0xFF1F1E1B);

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
        colorScheme: ColorScheme.fromSeed(seedColor: kTeal, primary: kTeal, surface: kBg),
        scaffoldBackgroundColor: kBg,
        appBarTheme: const AppBarTheme(backgroundColor: kBg, foregroundColor: kInk, elevation: 0),
      ),
      home: const Gate(),
    );
  }
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

  static Future<List<String>> listModels() async {
    try {
      final r = await http.get(Uri.parse('$kBase/v1/models'), headers: headers).timeout(const Duration(seconds: 90));
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      final out = <String>[];
      for (final m in (d['data'] as List)) {
        if (m['available'] == true) out.add(m['id'] as String);
        if (out.length >= 6) break;
      }
      return out;
    } catch (_) {
      return ['auto'];
    }
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
    req.body = jsonEncode({'model': model, 'messages': wire, 'stream': true});
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
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: kTeal)));
    if (!loggedIn) {
      return LoginScreen(onDone: () => setState(() => loggedIn = true));
    }
    return ChatListScreen(onLogout: () => setState(() => loggedIn = false));
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
                border: Border.all(color: const Color(0xFFEDECE6)),
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
                  const Text('تسجيل الدخول', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: kInk)),
                  const SizedBox(height: 20),
                  TextField(controller: nameC, textAlign: TextAlign.right, decoration: _dec('اسمك')),
                  const SizedBox(height: 12),
                  TextField(controller: keyC, textAlign: TextAlign.right, decoration: _dec('مفتاح التشغيل (sk-...)'), obscureText: true),
                  if (err != null) ...[
                    const SizedBox(height: 10),
                    Text(err!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFB3261E))),
                  ],
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: busy ? null : login,
                    style: FilledButton.styleFrom(backgroundColor: kTeal, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('دخول', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
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
        title: Text('أهلاً يا ${Api.name}', style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
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
      floatingActionButton: FloatingActionButton.extended(onPressed: newChat, backgroundColor: kTeal, icon: const Icon(Icons.add, color: Colors.white), label: const Text('محادثة جديدة', style: TextStyle(color: Colors.white))),
      body: RefreshIndicator(
        color: kTeal,
        onRefresh: refresh,
        child: loading
            ? const Center(child: CircularProgressIndicator(color: kTeal))
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
                          return Card(
                            color: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            child: ListTile(
                              title: Text(c['title']?.toString() ?? 'محادثة', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: dt != null ? Text('${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}') : null,
                              trailing: const Icon(Icons.chevron_left),
                              onTap: () => Navigator.of(context)
                                  .push(MaterialPageRoute(builder: (_) => ChatScreen(chatId: c['id'].toString(), title: c['title']?.toString() ?? 'محادثة')))
                                  .then((_) => refresh()),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String title;
  const ChatScreen({super.key, required this.chatId, required this.title});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final inputC = TextEditingController();
  final scrollC = ScrollController();
  List<Map<String, dynamic>> msgs = [];
  List<String> models = ['auto'];
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

  String modelLabel(String id) {
    if (id == 'auto') return 'تلقائي';
    if (id == 'fusion') return 'فريق';
    final s = id.split('/').last;
    return s.length > 18 ? '${s.substring(0, 18)}…' : s;
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
    return Scaffold(
      appBar: AppBar(title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
      body: Column(
        children: [
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: models
                  .map((m) => Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: ChoiceChip(
                          label: Text(modelLabel(m)),
                          selected: model == m,
                          selectedColor: kTeal,
                          labelStyle: TextStyle(color: model == m ? Colors.white : kInk, fontSize: 13),
                          onSelected: sending ? null : (_) => setState(() => model = m),
                        ),
                      ))
                  .toList(),
            ),
          ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator(color: kTeal))
                : ListView.builder(
                    controller: scrollC,
                    padding: const EdgeInsets.all(12),
                    itemCount: msgs.length,
                    itemBuilder: (_, i) => Bubble(m: msgs[i], streaming: sending && i == msgs.length - 1),
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
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: kTeal,
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

class Bubble extends StatelessWidget {
  final Map<String, dynamic> m;
  final bool streaming;
  const Bubble({super.key, required this.m, this.streaming = false});
  @override
  Widget build(BuildContext context) {
    final isUser = m['r'] == 'u';
    final text = (m['c'] ?? '').toString();
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        decoration: BoxDecoration(
          color: isUser ? kTeal : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
          border: isUser ? null : Border.all(color: const Color(0xFFEDECE6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text.isEmpty && streaming ? '...' : text,
              textAlign: TextAlign.right,
              style: TextStyle(color: isUser ? Colors.white : kInk, fontSize: 15.5, height: 1.55),
            ),
            if (!isUser && (m['model'] != null))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(modelName(m['model'].toString()), style: const TextStyle(fontSize: 10, color: Colors.black38)),
              ),
          ],
        ),
      ),
    );
  }

  String modelName(String id) => id == 'auto' ? '' : id.split('/').last;
}
