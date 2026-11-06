import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

// Business owners register as Admin by typing this code on the Register screen.
const adminCode = 'BOOKEASE-ADMIN';
const kBlue = Color(0xFF1565C0);
const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const apptStatuses = ['Pending', 'Approved', 'Rejected', 'Cancelled'];

final db = FirebaseFirestore.instance;
String get uid => FirebaseAuth.instance.currentUser!.uid;

String fmtDate(DateTime d) => '${months[d.month - 1]} ${d.day}, ${d.year}';
String fmtTime(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m ${d.hour >= 12 ? 'PM' : 'AM'}';
}

String fmt(DateTime d) => '${fmtDate(d)} · ${fmtTime(d)}';
String peso(num n) => '₱${n.toStringAsFixed(0)}';
bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

Color statusColor(String s) {
  switch (s) {
    case 'Approved':
      return Colors.green;
    case 'Pending':
      return Colors.orange;
    case 'Rejected':
      return Colors.red;
    default:
      return Colors.grey;
  }
}

void toast(BuildContext c, String m) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

Future<bool> confirm(BuildContext c, String msg) async =>
    (await showDialog<bool>(
        context: c,
        builder: (d) => AlertDialog(content: Text(msg), actions: [
              TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('No')),
              TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Yes')),
            ]))) ??
    false;

// A simple wrapper around a Firestore document.
class Rec {
  final String id;
  final Map<String, dynamic> d;
  Rec(this.id, this.d);
  String s(String k) => (d[k] ?? '') as String;
  DateTime t(String k) => (d[k] as Timestamp).toDate();
  num n(String k) => (d[k] ?? 0) as num;
}

// Live list from Firestore.
class Live extends StatefulWidget {
  final Query<Map<String, dynamic>> query;
  final Widget Function(List<Rec>) builder;
  const Live(this.query, this.builder, {super.key});
  @override
  State<Live> createState() => _LiveState();
}

class _LiveState extends State<Live> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> stream = widget.query.snapshots();
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Could not load data. Check your Firestore rules.\n${snap.error}')));
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        return widget.builder(snap.data!.docs.map((e) => Rec(e.id, e.data())).toList());
      },
    );
  }
}

// ---------------- Booking actions ----------------
Future<String?> bookSlot(Rec slot, String notes) async {
  try {
    final me = (await db.collection('users').doc(uid).get()).data() ?? {};
    final slotRef = db.collection('slots').doc(slot.id);
    final apptRef = db.collection('appointments').doc();
    await db.runTransaction((tx) async {
      final snap = await tx.get(slotRef);
      if (!snap.exists || (snap.data()!['booked'] ?? false) == true) {
        throw 'taken';
      }
      tx.update(slotRef, {'booked': true, 'bookedBy': uid});
      tx.set(apptRef, {
        'customerId': uid,
        'customerName': (me['name'] ?? '') as String,
        'customerEmail': FirebaseAuth.instance.currentUser?.email ?? '',
        'serviceId': slot.s('serviceId'),
        'serviceName': slot.s('serviceName'),
        'slotId': slot.id,
        'start': slot.d['start'],
        'status': 'Pending',
        'notes': notes,
        'createdAt': Timestamp.now(),
      });
    });
    return null;
  } catch (e) {
    if (e.toString().contains('taken')) {
      return 'Sorry, that schedule was just booked by someone else.';
    }
    return 'Could not book: $e';
  }
}

Future<void> setStatus(BuildContext c, Rec a, String status) async {
  try {
    final b = db.batch();
    b.update(db.collection('appointments').doc(a.id), {'status': status});
    final free = status == 'Rejected' || status == 'Cancelled';
    if (free && a.s('slotId').isNotEmpty) {
      b.update(db.collection('slots').doc(a.s('slotId')), {'booked': false, 'bookedBy': ''});
    }
    await b.commit();
    if (c.mounted) toast(c, 'Appointment $status');
  } catch (e) {
    if (c.mounted) toast(c, 'Failed: $e');
  }
}

// ---------------- App ----------------
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const BookEaseApp());
}

class BookEaseApp extends StatelessWidget {
  const BookEaseApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BookEase',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: kBlue).copyWith(
            primary: kBlue,
            onPrimary: Colors.white,
            surface: Colors.white,
            surfaceTint: Colors.transparent,
            surfaceContainerLow: const Color(0xFFF1F7FF),
            surfaceContainer: Colors.white),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
            backgroundColor: kBlue,
            foregroundColor: Colors.white,
            elevation: 0,
            surfaceTintColor: Colors.transparent),
        navigationBarTheme: const NavigationBarThemeData(
            backgroundColor: Colors.white, indicatorColor: Color(0xFFBBDEFB)),
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          return snap.data == null ? const AuthScreen() : const Gate();
        },
      ),
    );
  }
}

// ---------------- Login / Register ----------------
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool register = false, busy = false, admin = false;
  final name = TextEditingController(),
      phone = TextEditingController(),
      email = TextEditingController(),
      pass = TextEditingController(),
      code = TextEditingController();

  void msg(String t) => toast(context, t);

  Future<void> submit() async {
    if (email.text.trim().isEmpty || pass.text.isEmpty || (register && name.text.trim().isEmpty)) {
      msg('Please fill in all required fields.');
      return;
    }
    if (register && admin && code.text.trim() != adminCode) {
      msg('Wrong admin code.');
      return;
    }
    setState(() => busy = true);
    try {
      final auth = FirebaseAuth.instance;
      if (register) {
        final cred = await auth.createUserWithEmailAndPassword(
            email: email.text.trim(), password: pass.text);
        await db.collection('users').doc(cred.user!.uid).set({
          'name': name.text.trim(),
          'phone': phone.text.trim(),
          'email': email.text.trim(),
          'role': admin ? 'admin' : 'customer',
        });
        try {
          await cred.user!.sendEmailVerification();
        } catch (_) {}
      } else {
        await auth.signInWithEmailAndPassword(email: email.text.trim(), password: pass.text);
      }
    } on FirebaseAuthException catch (e) {
      msg(e.message ?? 'Authentication failed.');
    } catch (e) {
      msg('Something went wrong: $e');
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> resetPassword() async {
    if (email.text.trim().isEmpty) {
      msg('Type your email above first, then tap Forgot password.');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email.text.trim());
      msg('Password reset email sent. Check your inbox.');
    } on FirebaseAuthException catch (e) {
      msg(e.message ?? 'Could not send reset email.');
    }
  }

  Widget field(TextEditingController c, String label, {bool hide = false, TextInputType? type}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          obscureText: hide,
          keyboardType: type,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              const Icon(Icons.event_available, size: 72, color: kBlue),
              const Text('BookEase', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const Text('Appointment Booking Management System'),
              const SizedBox(height: 24),
              if (register) ...[
                field(name, 'Full name *'),
                field(phone, 'Phone number', type: TextInputType.phone),
              ],
              field(email, 'Email *', type: TextInputType.emailAddress),
              field(pass, 'Password * (min. 6 characters)', hide: true),
              if (register) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('I am a business owner (Admin)'),
                  value: admin,
                  onChanged: (v) => setState(() => admin = v),
                ),
                if (admin) field(code, 'Admin code'),
              ],
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                    onPressed: busy ? null : submit,
                    child: Text(busy ? 'Please wait...' : (register ? 'Create account' : 'Log in'))),
              ),
              TextButton(
                  onPressed: () => setState(() => register = !register),
                  child: Text(register ? 'Already have an account? Log in' : 'No account yet? Register')),
              if (!register)
                TextButton(onPressed: resetPassword, child: const Text('Forgot password?')),
            ]),
          ),
        ),
      ),
    );
  }
}

// ---------------- Role gate ----------------
class Gate extends StatelessWidget {
  const Gate({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: db.collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final role = (snap.data!.data()?['role'] ?? 'customer') as String;
        return role == 'admin' ? const AdminShell() : const CustomerShell();
      },
    );
  }
}

// ---------------- Customer ----------------
class CustomerShell extends StatefulWidget {
  const CustomerShell({super.key});
  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final pages = [const BookTab(), const MyApptsTab(), const ProfileTab()];
    return Scaffold(
      appBar: AppBar(title: const Text('BookEase')),
      body: pages[tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.event_available), label: 'Book'),
          NavigationDestination(icon: Icon(Icons.history), label: 'My bookings'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }
}

class BookTab extends StatefulWidget {
  const BookTab({super.key});
  @override
  State<BookTab> createState() => _BookTabState();
}

class _BookTabState extends State<BookTab> {
  String service = 'All';
  DateTime? day;

  Future<void> book(Rec slot) async {
    final notes = TextEditingController();
    final ok = await showDialog<bool>(
        context: context,
        builder: (dc) => AlertDialog(
              title: const Text('Confirm booking'),
              content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(slot.s('serviceName'), style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(fmt(slot.t('start'))),
                const SizedBox(height: 12),
                TextField(
                    controller: notes,
                    decoration: const InputDecoration(
                        labelText: 'Notes (optional)', border: OutlineInputBorder())),
              ]),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dc, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(dc, true), child: const Text('Book')),
              ],
            ));
    if (ok != true) return;
    final err = await bookSlot(slot, notes.text.trim());
    if (mounted) toast(context, err ?? 'Booked! Waiting for the admin to approve.');
  }

  @override
  Widget build(BuildContext context) {
    return Live(db.collection('slots').orderBy('start'), (all) {
      final now = DateTime.now();
      final open = all.where((r) => r.d['booked'] != true && r.t('start').isAfter(now)).toList();
      final names = <String>{for (final r in open) r.s('serviceName')}.toList()..sort();
      final sel = names.contains(service) ? service : 'All';
      final shown = open
          .where((r) =>
              (sel == 'All' || r.s('serviceName') == sel) &&
              (day == null || sameDay(r.t('start'), day!)))
          .toList();
      return Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: sel,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Service', border: OutlineInputBorder(), isDense: true),
                items: ['All', ...names].map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
                onChanged: (v) => setState(() => service = v!),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text(day == null ? 'Any date' : fmtDate(day!)),
              onPressed: () async {
                final d = await showDatePicker(
                    context: context,
                    initialDate: day ?? now,
                    firstDate: now,
                    lastDate: DateTime(now.year + 2));
                if (d != null) setState(() => day = d);
              },
            ),
            if (day != null)
              IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => day = null)),
          ]),
        ),
        Expanded(
          child: shown.isEmpty
              ? const Center(child: Text('No available schedules.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: shown.length,
                  itemBuilder: (c, i) {
                    final r = shown[i];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.access_time, color: kBlue),
                        title: Text(r.s('serviceName')),
                        subtitle: Text(
                            '${fmt(r.t('start'))}\n${r.n('duration').toInt()} min · ${peso(r.n('price'))}'),
                        isThreeLine: true,
                        trailing: FilledButton(onPressed: () => book(r), child: const Text('Book')),
                      ),
                    );
                  },
                ),
        ),
      ]);
    });
  }
}

class MyApptsTab extends StatelessWidget {
  const MyApptsTab({super.key});
  @override
  Widget build(BuildContext context) {
    return Live(db.collection('appointments').where('customerId', isEqualTo: uid), (all) {
      final list = [...all]..sort((a, b) => b.t('start').compareTo(a.t('start')));
      if (list.isEmpty) return const Center(child: Text('No bookings yet.'));
      return ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: list.length,
        itemBuilder: (c, i) {
          final a = list[i];
          final st = a.s('status');
          final canCancel =
              (st == 'Pending' || st == 'Approved') && a.t('start').isAfter(DateTime.now());
          return Card(
            child: ListTile(
              title: Text(a.s('serviceName')),
              subtitle: Text(
                  '${fmt(a.t('start'))}${a.s('notes').isEmpty ? '' : '\nNotes: ${a.s('notes')}'}'),
              isThreeLine: a.s('notes').isNotEmpty,
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Chip(
                    label: Text(st, style: const TextStyle(color: Colors.white, fontSize: 11)),
                    backgroundColor: statusColor(st),
                    padding: EdgeInsets.zero),
                if (canCancel)
                  GestureDetector(
                    onTap: () async {
                      if (await confirm(context, 'Cancel this appointment?') && context.mounted) {
                        await setStatus(context, a, 'Cancelled');
                      }
                    },
                    child: const Text('Cancel', style: TextStyle(color: Colors.red)),
                  ),
              ]),
            ),
          );
        },
      );
    });
  }
}

// ---------------- Admin ----------------
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final pages = [
      const AdminDashboard(),
      const AdminAppts(),
      const AdminSchedule(),
      const AdminServices(),
      const ProfileTab(),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('BookEase Admin')),
      body: pages[tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.list_alt), label: 'Bookings'),
          NavigationDestination(icon: Icon(Icons.calendar_month), label: 'Schedule'),
          NavigationDestination(icon: Icon(Icons.design_services), label: 'Services'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }
}

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  Widget stat(String label, int n, Color c, IconData icon) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(children: [
              Icon(icon, color: c),
              Text('$n', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: c)),
              Text(label, style: const TextStyle(fontSize: 12)),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Live(db.collection('appointments'), (all) {
      final now = DateTime.now();
      bool active(Rec a) => a.s('status') == 'Pending' || a.s('status') == 'Approved';
      final pending = all.where((a) => a.s('status') == 'Pending').length;
      final approved = all.where((a) => a.s('status') == 'Approved').length;
      final today = all.where((a) => active(a) && sameDay(a.t('start'), now)).length;
      final upcoming = all.where((a) => active(a) && a.t('start').isAfter(now)).toList()
        ..sort((a, b) => a.t('start').compareTo(b.t('start')));
      return ListView(padding: const EdgeInsets.all(12), children: [
        Row(children: [
          stat('Total', all.length, kBlue, Icons.event_note),
          stat('Pending', pending, Colors.orange, Icons.hourglass_empty),
        ]),
        Row(children: [
          stat('Approved', approved, Colors.green, Icons.check_circle_outline),
          stat('Today', today, Colors.blue, Icons.today),
        ]),
        const Padding(
            padding: EdgeInsets.fromLTRB(4, 12, 4, 4),
            child: Text('Upcoming appointments',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
        if (upcoming.isEmpty)
          const Padding(padding: EdgeInsets.all(16), child: Text('No upcoming appointments.')),
        ...upcoming.take(10).map((a) => Card(
              child: ListTile(
                title: Text('${a.s('customerName')} · ${a.s('serviceName')}'),
                subtitle: Text(fmt(a.t('start'))),
                trailing: Chip(
                    label: Text(a.s('status'),
                        style: const TextStyle(color: Colors.white, fontSize: 11)),
                    backgroundColor: statusColor(a.s('status')),
                    padding: EdgeInsets.zero),
              ),
            )),
      ]);
    });
  }
}

class AdminAppts extends StatefulWidget {
  const AdminAppts({super.key});
  @override
  State<AdminAppts> createState() => _AdminApptsState();
}

class _AdminApptsState extends State<AdminAppts> {
  String q = '', status = 'All';
  @override
  Widget build(BuildContext context) {
    return Live(db.collection('appointments'), (all) {
      final list = all
          .where((a) =>
              (status == 'All' || a.s('status') == status) &&
              ('${a.s('customerName')} ${a.s('serviceName')}').toLowerCase().contains(q.toLowerCase()))
          .toList()
        ..sort((a, b) => b.t('start').compareTo(a.t('start')));
      return Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search customer or service',
                border: OutlineInputBorder(),
                isDense: true),
            onChanged: (v) => setState(() => q = v),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
            for (final s in ['All', ...apptStatuses])
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: ChoiceChip(
                    label: Text(s), selected: status == s, onSelected: (_) => setState(() => status = s)),
              ),
          ]),
        ),
        Expanded(
          child: list.isEmpty
              ? const Center(child: Text('No appointments found.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: list.length,
                  itemBuilder: (c, i) {
                    final a = list[i];
                    final st = a.s('status');
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(
                                child: Text(a.s('serviceName'),
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                            Chip(
                                label: Text(st, style: const TextStyle(color: Colors.white, fontSize: 11)),
                                backgroundColor: statusColor(st),
                                padding: EdgeInsets.zero),
                          ]),
                          Text('${a.s('customerName')} · ${a.s('customerEmail')}'),
                          Text(fmt(a.t('start'))),
                          if (a.s('notes').isNotEmpty) Text('Notes: ${a.s('notes')}'),
                          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                            if (st == 'Pending') ...[
                              TextButton(
                                  onPressed: () => setStatus(context, a, 'Rejected'),
                                  child: const Text('Reject', style: TextStyle(color: Colors.red))),
                              FilledButton(
                                  onPressed: () => setStatus(context, a, 'Approved'),
                                  child: const Text('Approve')),
                            ],
                            if (st == 'Approved')
                              TextButton(
                                  onPressed: () async {
                                    if (await confirm(context, 'Cancel this appointment?') &&
                                        context.mounted) {
                                      await setStatus(context, a, 'Cancelled');
                                    }
                                  },
                                  child: const Text('Cancel', style: TextStyle(color: Colors.red))),
                          ]),
                        ]),
                      ),
                    );
                  },
                ),
        ),
      ]);
    });
  }
}

class AdminSchedule extends StatelessWidget {
  const AdminSchedule({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () =>
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SlotForm())),
          icon: const Icon(Icons.add),
          label: const Text('Add schedule')),
      body: Live(db.collection('slots').orderBy('start'), (list) {
        if (list.isEmpty) return const Center(child: Text('No schedules yet. Tap "Add schedule".'));
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 90, left: 8, right: 8, top: 8),
          itemCount: list.length,
          itemBuilder: (c, i) {
            final r = list[i];
            final booked = r.d['booked'] == true;
            return Card(
              child: ListTile(
                leading: Icon(booked ? Icons.event_busy : Icons.event_available,
                    color: booked ? Colors.red : Colors.green),
                title: Text(r.s('serviceName')),
                subtitle: Text('${fmt(r.t('start'))} · ${booked ? 'Booked' : 'Available'}'),
                trailing: booked
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          if (await confirm(context, 'Delete this schedule?')) {
                            await db.collection('slots').doc(r.id).delete();
                          }
                        }),
              ),
            );
          },
        );
      }),
    );
  }
}

class SlotForm extends StatefulWidget {
  const SlotForm({super.key});
  @override
  State<SlotForm> createState() => _SlotFormState();
}

class _SlotFormState extends State<SlotForm> {
  List<Rec> services = [];
  bool loading = true;
  Rec? svc;
  DateTime day = DateTime.now().add(const Duration(days: 1));
  TimeOfDay time = const TimeOfDay(hour: 9, minute: 0);

  @override
  void initState() {
    super.initState();
    db.collection('services').get().then((q) {
      services = q.docs.map((e) => Rec(e.id, e.data())).toList()
        ..sort((a, b) => a.s('name').compareTo(b.s('name')));
      if (mounted) {
        setState(() {
          loading = false;
          if (services.isNotEmpty) svc = services.first;
        });
      }
    });
  }

  Future<void> save() async {
    final s = svc;
    if (s == null) return;
    final start = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    try {
      await db.collection('slots').add({
        'serviceId': s.id,
        'serviceName': s.s('name'),
        'duration': s.n('duration'),
        'price': s.n('price'),
        'start': Timestamp.fromDate(start),
        'booked': false,
        'bookedBy': '',
      });
      final next = start.add(Duration(minutes: s.n('duration').toInt()));
      if (!mounted) return;
      setState(() => time = TimeOfDay(hour: next.hour, minute: next.minute));
      toast(context, 'Added: ${fmt(start)}');
    } catch (e) {
      if (mounted) toast(context, 'Failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add schedule')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : services.isEmpty
              ? const Center(
                  child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Add a service first (Services tab), then create schedules.')))
              : ListView(padding: const EdgeInsets.all(16), children: [
                  DropdownButtonFormField<Rec>(
                    value: svc,
                    decoration:
                        const InputDecoration(labelText: 'Service', border: OutlineInputBorder()),
                    items: services
                        .map((s) => DropdownMenuItem(value: s, child: Text(s.s('name'))))
                        .toList(),
                    onChanged: (v) => setState(() => svc = v),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                        child: OutlinedButton.icon(
                            icon: const Icon(Icons.calendar_today),
                            label: Text(fmtDate(day)),
                            onPressed: () async {
                              final d = await showDatePicker(
                                  context: context,
                                  initialDate: day,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2100));
                              if (d != null) setState(() => day = d);
                            })),
                    const SizedBox(width: 8),
                    Expanded(
                        child: OutlinedButton.icon(
                            icon: const Icon(Icons.access_time),
                            label: Text(fmtTime(DateTime(2000, 1, 1, time.hour, time.minute))),
                            onPressed: () async {
                              final t = await showTimePicker(context: context, initialTime: time);
                              if (t != null) setState(() => time = t);
                            })),
                  ]),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: save, child: const Text('Add this time slot')),
                  const SizedBox(height: 8),
                  const Text(
                      'Tip: after adding, the time moves forward by the service duration so you can add the next slot quickly.',
                      style: TextStyle(fontSize: 12)),
                ]),
    );
  }
}

class AdminServices extends StatelessWidget {
  const AdminServices({super.key});

  Future<void> serviceDialog(BuildContext c, [Rec? s]) async {
    final name = TextEditingController(text: s?.s('name') ?? '');
    final dur = TextEditingController(text: s == null ? '30' : s.n('duration').toInt().toString());
    final price = TextEditingController(text: s == null ? '0' : s.n('price').toString());
    await showDialog(
        context: c,
        builder: (dc) => AlertDialog(
              title: Text(s == null ? 'Add service' : 'Edit service'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Service name')),
                TextField(
                    controller: dur,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Duration (minutes)')),
                TextField(
                    controller: price,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Price (₱)')),
              ]),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dc), child: const Text('Cancel')),
                FilledButton(
                    onPressed: () async {
                      if (name.text.trim().isEmpty) return;
                      final data = {
                        'name': name.text.trim(),
                        'duration': int.tryParse(dur.text) ?? 30,
                        'price': num.tryParse(price.text) ?? 0,
                      };
                      if (s == null) {
                        await db.collection('services').add(data);
                      } else {
                        await db.collection('services').doc(s.id).update(data);
                      }
                      if (dc.mounted) Navigator.pop(dc);
                    },
                    child: const Text('Save')),
              ],
            ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () => serviceDialog(context),
          icon: const Icon(Icons.add),
          label: const Text('Add service')),
      body: Live(db.collection('services'), (all) {
        final list = [...all]..sort((a, b) => a.s('name').compareTo(b.s('name')));
        if (list.isEmpty) return const Center(child: Text('No services yet. Tap "Add service".'));
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 90, left: 8, right: 8, top: 8),
          itemCount: list.length,
          itemBuilder: (c, i) {
            final s = list[i];
            return Card(
              child: ListTile(
                leading: const Icon(Icons.design_services, color: kBlue),
                title: Text(s.s('name')),
                subtitle: Text('${s.n('duration').toInt()} min · ${peso(s.n('price'))}'),
                onTap: () => serviceDialog(context, s),
                trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      if (await confirm(context, 'Delete "${s.s('name')}"?')) {
                        await db.collection('services').doc(s.id).delete();
                      }
                    }),
              ),
            );
          },
        );
      }),
    );
  }
}

// ---------------- Profile (both roles) ----------------
class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});
  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  final name = TextEditingController(), phone = TextEditingController();
  String role = 'customer';
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    db.collection('users').doc(uid).get().then((d) {
      final m = d.data() ?? {};
      name.text = (m['name'] ?? '') as String;
      phone.text = (m['phone'] ?? '') as String;
      role = (m['role'] ?? 'customer') as String;
      if (mounted) setState(() => loaded = true);
    });
  }

  Widget field(TextEditingController c, String l) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
            controller: c, decoration: InputDecoration(labelText: l, border: const OutlineInputBorder())),
      );

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Center(child: CircularProgressIndicator());
    final u = FirebaseAuth.instance.currentUser;
    final ok = u?.emailVerified ?? false;
    return ListView(padding: const EdgeInsets.all(16), children: [
      const CircleAvatar(radius: 40, child: Icon(Icons.person, size: 40)),
      const SizedBox(height: 8),
      Center(child: Text(u?.email ?? '')),
      Center(child: Chip(label: Text(role == 'admin' ? 'Admin' : 'Customer'))),
      Card(
        child: ListTile(
          leading: Icon(ok ? Icons.verified : Icons.warning_amber,
              color: ok ? Colors.green : Colors.orange),
          title: Text(ok ? 'Email verified' : 'Email not verified'),
          trailing: ok
              ? null
              : Wrap(children: [
                  TextButton(
                      onPressed: () async {
                        try {
                          await u?.sendEmailVerification();
                          if (context.mounted) toast(context, 'Verification email sent.');
                        } catch (e) {
                          if (context.mounted) toast(context, 'Could not send: $e');
                        }
                      },
                      child: const Text('Resend')),
                  TextButton(
                      onPressed: () async {
                        await FirebaseAuth.instance.currentUser?.reload();
                        if (mounted) setState(() {});
                      },
                      child: const Text('Refresh')),
                ]),
        ),
      ),
      const SizedBox(height: 8),
      field(name, 'Full name'),
      field(phone, 'Phone number'),
      FilledButton(
        onPressed: () async {
          await db.collection('users').doc(uid).set(
              {'name': name.text.trim(), 'phone': phone.text.trim(), 'email': u?.email},
              SetOptions(merge: true));
          if (context.mounted) toast(context, 'Profile updated.');
        },
        child: const Text('Save profile'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
          onPressed: () => FirebaseAuth.instance.signOut(),
          icon: const Icon(Icons.logout),
          label: const Text('Log out')),
    ]);
  }
}
