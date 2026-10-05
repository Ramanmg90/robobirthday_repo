import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

final FlutterLocalNotificationsPlugin np = FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Tehran'));
  await np.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher')));
  runApp(const App());
}

// ───────────── helpers ─────────────
String fa(num n) => n
    .toString()
    .replaceAllMapped(RegExp(r'\d'), (m) => '۰۱۲۳۴۵۶۷۸۹'[int.parse(m[0]!)]);
String money(int n) => fa(n.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ','));

// ───────────── model ─────────────
class Item {
  String n;
  int p;
  bool done;
  Item(this.n, [this.p = 0, this.done = false]);
  Map<String, dynamic> toJson() => {'n': n, 'p': p, 'd': done};
  factory Item.fromJson(Map j) => Item(j['n'], j['p'] ?? 0, j['d'] ?? false);
}

class Data {
  int by = 1388, h = 0, m = 0;
  List<Item> wish = [], bike = [], gift = [];
  List<String> photos = [];

  Map<String, dynamic> toJson() => {
        'by': by,
        'h': h,
        'm': m,
        'wish': wish,
        'bike': bike,
        'gift': gift,
        'photos': photos,
      };

  static List<Item> _items(dynamic l) =>
      (l as List? ?? []).map<Item>((e) => Item.fromJson(e)).toList();

  static Data from(String? s) {
    final d = Data();
    if (s == null) return d;
    final j = jsonDecode(s);
    d.by = j['by'] ?? 1388;
    d.h = j['h'] ?? 0;
    d.m = j['m'] ?? 0;
    d.wish = _items(j['wish']);
    d.bike = _items(j['bike']);
    d.gift = _items(j['gift']);
    d.photos = List<String>.from(j['photos'] ?? []);
    return d;
  }

  /// لحظه‌ی تولد در سال شمسی jy
  DateTime bday(int jy) {
    final g = Jalali(jy, 7, 17).toDateTime();
    return DateTime(g.year, g.month, g.day, h, m);
  }
}

// ───────────── notifications ─────────────
Future<void> schedule(Data d) async {
  try {
    final a = np.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await a?.requestNotificationsPermission();
    await a?.requestExactAlarmsPermission();
    await np.cancelAll();

    final now = DateTime.now();
    final jy = Jalali.fromDateTime(now).year;
    var t = d.bday(jy);
    if (t.isBefore(now)) t = d.bday(jy + 1);

    const det = NotificationDetails(
        android: AndroidNotificationDetails('bday', 'تولد',
            importance: Importance.max, priority: Priority.high));
    Future<void> sch(int id, String title, String body, DateTime when) =>
        np.zonedSchedule(id, title, body, tz.TZDateTime.from(when, tz.local),
            det,
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime);

    await sch(1, '🎂 تولدت مبارک!', 'Robo اولین نفر تبریک می‌گه! 🤖', t);
    final eve = DateTime(t.year, t.month, t.day - 1, 9);
    if (eve.isAfter(now)) {
      await sch(2, '⏳ فردا تولدته!', 'Robo آماده‌ی جشنه 🎉', eve);
    }
  } catch (e) {
    debugPrint('schedule error: $e');
  }
}

// ───────────── app ─────────────
class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) {
    ThemeData th(Brightness b) => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF7C4DFF), brightness: b));
    return MaterialApp(
      title: 'RoboBirthday',
      debugShowCheckedModeBanner: false,
      theme: th(Brightness.light),
      darkTheme: th(Brightness.dark),
      builder: (c, w) => Directionality(textDirection: TextDirection.rtl, child: w!),
      home: const Home(),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  Data d = Data();
  bool loaded = false, preview = false, wasB = false;
  Timer? timer;
  final conf = ConfettiController(duration: const Duration(seconds: 6));
  int msg = 0;
  final normal = [
    'سلام! من Robo‌ام 🤖 دارم روزها رو برات می‌شمرم!',
    'یادت نره، تا تولدت چیزی نمونده 🎂',
    'موتورت منتظره، لیستت رو کامل کن 🏍️',
    'بودجه هدیه رو چک کردی؟ 😂',
    'من آماده‌ام که اولین نفر تبریک بگم!',
  ];
  final bdMsgs = [
    '🎉 تولدت مبارک! از طرف همه‌ی سیم‌ها و بردهای Robo!',
    '🎂 یه سال دیگه آپگرید شدی! نسخه‌ی جدید عالیه!',
    '🤖 بیپ‌بوپ! امروز هر چی خواستی حق توئه!',
  ];
  String say = '';

  @override
  void initState() {
    super.initState();
    say = normal[0];
    _load();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    conf.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    d = Data.from(sp.getString('rb'));
    setState(() => loaded = true);
    schedule(d);
  }

  Future<void> save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('rb', jsonEncode(d.toJson()));
    setState(() {});
  }

  bool isBirthday(DateTime now) {
    final j = Jalali.fromDateTime(now);
    return preview || (j.month == 7 && j.day == 17);
  }

  void talk() {
    final list = wasB ? bdMsgs : normal;
    msg = (msg + 1) % list.length;
    setState(() => say = list[msg]);
  }

  // ───── add dialog ─────
  Future<void> addItem(String title, List<Item> list, {bool price = false}) async {
    final n = TextEditingController(), p = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(title),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: n, autofocus: true, decoration: const InputDecoration(labelText: 'عنوان')),
            if (price)
              TextField(
                  controller: p,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'مبلغ (تومان)')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('لغو')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('افزودن')),
          ],
        ),
      ),
    );
    if (ok == true && n.text.trim().isNotEmpty) {
      list.add(Item(n.text.trim(), int.tryParse(p.text.trim()) ?? 0));
      save();
    }
  }

  Future<void> addPhotos() async {
    final files = await ImagePicker().pickMultiImage(imageQuality: 75, maxWidth: 1080);
    if (files.isEmpty) return;
    final dir = await getApplicationDocumentsDirectory();
    for (final f in files) {
      final path = '${dir.path}/${DateTime.now().microsecondsSinceEpoch}.jpg';
      await File(f.path).copy(path);
      d.photos.add(path);
    }
    save();
  }

  void randomWish() {
    setState(() => say = d.wish.isEmpty
        ? 'اول یه چیزی به لیست آرزوها اضافه کن 😄'
        : '🎁 پیشنهاد من: «${d.wish[Random().nextInt(d.wish.length)].n}»');
  }

  // ───── settings ─────
  void settings() {
    final by = TextEditingController(text: d.by.toString());
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (c, set) => Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(c).viewInsets.bottom + 20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: by,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'سال تولد (شمسی)'),
                onChanged: (v) {
                  d.by = int.tryParse(v) ?? d.by;
                  save();
                  schedule(d);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('ساعت تولد'),
                trailing: Text('${fa(d.h.toString().padLeft(2, '0'))}:${fa(d.m.toString().padLeft(2, '0'))}'),
                onTap: () async {
                  final t = await showTimePicker(
                      context: c, initialTime: TimeOfDay(hour: d.h, minute: d.m));
                  if (t != null) {
                    d.h = t.hour;
                    d.m = t.minute;
                    save();
                    schedule(d);
                    set(() {});
                  }
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('پیش‌نمایش روز تولد 🎉'),
                value: preview,
                onChanged: (v) {
                  setState(() => preview = v);
                  set(() {});
                },
              ),
              FilledButton.tonalIcon(
                onPressed: () async {
                  await schedule(d);
                  if (c.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('اعلان تولد تنظیم شد ✅')));
                  }
                },
                icon: const Icon(Icons.notifications_active),
                label: const Text('تنظیم دوباره‌ی اعلان‌ها'),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // ───── UI pieces ─────
  Widget card(String title, Widget child, {Widget? action}) => Card(
        margin: const EdgeInsets.only(bottom: 14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
              if (action != null) action,
            ]),
            const SizedBox(height: 8),
            child,
          ]),
        ),
      );

  Widget listCard(String title, List<Item> l, {bool price = false, bool check = false, String? foot, Widget? extra}) {
    return card(
      title,
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < l.length; i++)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: check
                ? Checkbox(value: l[i].done, onChanged: (v) {
                    l[i].done = v ?? false;
                    save();
                  })
                : null,
            title: Text(l[i].n,
                style: TextStyle(decoration: l[i].done ? TextDecoration.lineThrough : null)),
            subtitle: l[i].p > 0 ? Text('${money(l[i].p)} تومان') : null,
            trailing: IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  l.removeAt(i);
                  save();
                }),
          ),
        if (foot != null)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(foot, style: const TextStyle(fontWeight: FontWeight.bold))),
        if (extra != null) extra,
      ]),
      action: IconButton.filledTonal(
          icon: const Icon(Icons.add), onPressed: () => addItem(title, l, price: price)),
    );
  }

  Widget robo(bool blink) {
    Widget eye() => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 12,
        height: blink ? 3 : 16,
        decoration: BoxDecoration(color: Colors.cyanAccent, borderRadius: BorderRadius.circular(8)));
    return SizedBox(
      width: 76,
      height: 76,
      child: Stack(alignment: Alignment.center, children: [
        Container(
            width: 68,
            height: 56,
            margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(color: const Color(0xFF7C4DFF), borderRadius: BorderRadius.circular(18))),
        Positioned(top: 0, child: Container(width: 4, height: 14, color: const Color(0xFF7C4DFF))),
        const Positioned(top: 0, child: CircleAvatar(radius: 5, backgroundColor: Color(0xFFFF5C9A))),
        Container(
          width: 50,
          height: 28,
          margin: const EdgeInsets.only(top: 12),
          decoration: BoxDecoration(color: const Color(0xFF1D1A33), borderRadius: BorderRadius.circular(12)),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [eye(), eye()]),
        ),
        Positioned(
            bottom: 8,
            child: Container(
                width: 22,
                height: 5,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(5)))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final now = DateTime.now();
    final jy = Jalali.fromDateTime(now).year;
    final isB = isBirthday(now);
    if (isB && !wasB) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        conf.play();
        setState(() => say = bdMsgs[0]);
      });
    } else if (!isB && wasB) {
      WidgetsBinding.instance.addPostFrameCallback((_) => setState(() => say = normal[0]));
    }
    wasB = isB;

    var target = d.bday(jy);
    if (now.isAfter(target) && !isB) target = d.bday(jy + 1);
    final diff = target.isAfter(now) ? target.difference(now) : Duration.zero;

    var y = 0;
    while (!d.bday(d.by + y + 1).isAfter(now)) {
      y++;
    }
    final since = now.difference(d.bday(d.by + y));

    final bt = d.bike.fold<int>(0, (a, e) => a + e.p);
    final bl = d.bike.where((e) => !e.done).fold<int>(0, (a, e) => a + e.p);
    final gt = d.gift.fold<int>(0, (a, e) => a + e.p);
    final pct = bt > 0 ? min(100, (gt / bt * 100).round()) : 0;

    Widget box(int v, String l) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF7C4DFF), Color(0xFFFF5C9A)]),
                borderRadius: BorderRadius.circular(14)),
            child: Column(children: [
              Text(fa(v), style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
              Text(l, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ),
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('🎂 RoboBirthday'),
        centerTitle: true,
        actions: [IconButton(icon: const Icon(Icons.settings), onPressed: settings)],
      ),
      body: Stack(children: [
        ListView(padding: const EdgeInsets.all(16), children: [
          if (isB)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFFF5C9A), Color(0xFF7C4DFF)]),
                  borderRadius: BorderRadius.circular(20)),
              child: const Text('🎉 تولدت مبارک! 🎉\nامروز روز توئه، حسابی بترکون!',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
            ),
          card(
            '⏳ شمارش معکوس تا ۱۷ مهر',
            Row(children: [
              box(diff.inDays, 'روز'),
              box(diff.inHours % 24, 'ساعت'),
              box(diff.inMinutes % 60, 'دقیقه'),
              box(diff.inSeconds % 60, 'ثانیه'),
            ]),
          ),
          Card(
            margin: const EdgeInsets.only(bottom: 14),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: talk,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  robo(now.second % 4 == 0),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(16)),
                      child: Text(say),
                    ),
                  ),
                ]),
              ),
            ),
          ),
          card(
            '📊 سن تو',
            Center(
              child: Column(children: [
                Text('${fa(y)} سال و ${fa(since.inDays)} روز',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                Text('${fa(since.inHours % 24)} ساعت و ${fa(since.inMinutes % 60)} دقیقه و ${fa(since.inSeconds % 60)} ثانیه',
                    style: TextStyle(color: Theme.of(context).hintColor)),
              ]),
            ),
          ),
          listCard('🎁 امسال چی می‌خوام؟', d.wish,
              extra: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                      onPressed: randomWish,
                      icon: const Icon(Icons.casino),
                      label: const Text('Robo یکی انتخاب کن')))),
          listCard('🏍️ لیست خرید موتور', d.bike,
              price: true,
              check: true,
              foot: 'مجموع: ${money(bt)} ت | باقی‌مانده: ${money(bl)} ت'),
          listCard('💰 بودجه هدیه 😂', d.gift,
              price: true,
              foot: 'جمع هدیه‌ها: ${money(gt)} تومان${bt > 0 ? ' | ${fa(pct)}٪ برای موتور' : ''}'),
          card(
            '📸 خاطرات سال گذشته',
            d.photos.isEmpty
                ? const Text('هنوز عکسی اضافه نکردی')
                : GridView.count(
                    crossAxisCount: 3,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      for (var i = 0; i < d.photos.length; i++)
                        GestureDetector(
                          onLongPress: () {
                            d.photos.removeAt(i);
                            save();
                          },
                          child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(File(d.photos[i]), fit: BoxFit.cover)),
                        ),
                    ],
                  ),
            action: IconButton.filledTonal(icon: const Icon(Icons.add_a_photo), onPressed: addPhotos),
          ),
          const Center(child: Text('برای حذف عکس، روی آن نگه دار', style: TextStyle(fontSize: 12, color: Colors.grey))),
        ]),
        Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: conf,
            blastDirectionality: BlastDirectionality.explosive,
            numberOfParticles: 30,
            gravity: 0.2,
            shouldLoop: false,
          ),
        ),
      ]),
    );
  }
}
