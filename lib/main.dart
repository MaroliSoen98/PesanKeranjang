import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';
import 'package:excel/excel.dart' as excel;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart'; // File hasil generate dari flutterfire CLI
import 'dart:math';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint("Handling a background message: ${message.messageId}");
}

final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }
  await initializeDateFormatting('id_ID', null);
  runApp(const KueCinaApp());
}

class KueCinaApp extends StatelessWidget {
  const KueCinaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      title: 'Pesan Keranjang',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.deepOrange,
        scaffoldBackgroundColor: Colors.white,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
        cardTheme: const CardThemeData(
          elevation: 1,
        ),
        datePickerTheme: DatePickerThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors
              .transparent, // Menghilangkan tint warna bawaan Material 3 agar putih bersih
          shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(24), // Lengkungan yang lebih modern
          ),
          headerBackgroundColor: Colors.white, // Header kalender putih
          headerForegroundColor:
              Colors.black87, // Teks judul pada header menjadi gelap
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          // PERBAIKAN: Menambahkan style untuk teks agar tetap terbaca di mode gelap
          titleTextStyle: const TextStyle(
            color: Colors.black87,
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
          contentTextStyle: const TextStyle(
            color: Colors.black87,
            fontSize: 15,
          ),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Setup Notifikasi Firebase
    try {
      await _setupPushNotifications();
    } catch (e) {
      debugPrint('Setup Push Notif Error: $e');
    }

    // 1. Ambil versi aplikasi & data dari SharedPreferences secara bersamaan
    final (packageInfo, loadedOrders) = await (
      PackageInfo.fromPlatform(),
      _loadOrdersFromFirestore(),
    ).wait;

    if (!mounted) return;

    setState(() {
      _appVersion = 'v${packageInfo.version}';
    });

    // 2. Beri jeda agar splash screen terlihat lebih lama (5 detik)
    await Future.delayed(const Duration(seconds: 5));

    if (!mounted) return;

    // Berpindah ke OrderPage sekaligus menghapus SplashScreen dari back-history
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => OrderPage(initialOrders: loadedOrders),
      ),
    );
  }

  Future<void> _setupPushNotifications() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    // Meminta izin kepada user (Wajib untuk Android 13+ dan iOS)
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      // Berlangganan ke topik agar menerima push notif otomatis dari server Firebase
      if (!kIsWeb && Platform.isAndroid) {
        await messaging.subscribeToTopic('pesanan_admin');
      }

      // Ambil token unik HP ini (berguna jika ingin kirim notif ke HP spesifik)
      String? token = await messaging.getToken();
      debugPrint('FCM Token HP ini: $token');

      // Menangani notifikasi saat aplikasi SEDANG DIBUKA (Foreground)
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        if (message.notification != null) {
          rootScaffoldMessengerKey.currentState?.showSnackBar(
            SnackBar(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('🔔 ${message.notification!.title}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 6),
                  Text(message.notification!.body ?? '',
                      maxLines: 10, overflow: TextOverflow.ellipsis),
                ],
              ),
              backgroundColor: Colors.deepOrange,
              duration: const Duration(
                  seconds: 5), // Diperlama agar penjual sempat membaca list
              behavior: SnackBarBehavior
                  .floating, // Dibuat melayang agar ukurannya menyesuaikan isi
            ),
          );
        }
      });
    }
  }

  Future<List<OrderItem>> _loadOrdersFromFirestore() async {
    try {
      final snapshot =
          await FirebaseFirestore.instance.collection(_kCollectionOrders).get();
      return snapshot.docs
          .map((doc) => OrderItem.fromJson(doc.data(), doc.id))
          .toList();
    } catch (e) {
      debugPrint('Gagal load orders dari Firestore: $e');
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset('assets/icon.png', width: 80, height: 80),
                  const SizedBox(height: 16),
                  const Text(
                    'PesanKeranjang',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepOrange,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const CircularProgressIndicator(color: Colors.deepOrange),
                ],
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 64.0),
                child: Text(_appVersion,
                    style: TextStyle(color: Colors.grey.shade600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color? color;
  final bool fullWidth;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    this.color,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: color ?? Colors.blue, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      color: color?.withOpacity(0.8) ?? Colors.blue.shade700,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: fullWidth ? 20 : 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickFilterBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickFilterBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
      ),
    );
  }
}

class _CustomBottomNavItem extends StatelessWidget {
  final int index;
  final int selectedIndex;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final ValueChanged<int> onTap;

  const _CustomBottomNavItem({
    required this.index,
    required this.selectedIndex,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = selectedIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => onTap(index),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              padding: const EdgeInsets.only(bottom: 4),
              child: Icon(
                isSelected ? activeIcon : icon,
                color: isSelected ? Colors.deepOrange : Colors.grey.shade400,
                size: isSelected ? 28 : 24,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.deepOrange : Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 4),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: isSelected ? 1.0 : 0.0,
              child: Container(
                height: 4,
                width: 16,
                decoration: BoxDecoration(
                  color: Colors.deepOrange,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Konstanta global untuk meminimalisir Magic Strings (Code Smell)
const String _kCollectionOrders = 'orders';
const String _kCollectionUsers = 'users';
const String _kApiNotify =
    'https://pesan-keranjang-backend.vercel.app/api/notify';
const String _kApiNotifyCompleted =
    'https://pesan-keranjang-backend.vercel.app/api/notify_completed';

class OrderItem {
  String? id; // ID Dokumen dari Firestore
  String customerName;
  String? customerPhone;
  DateTime orderDate;
  DateTime pickupDate;
  double weightKg;
  bool isPickedUp;
  String? notes;
  String? resi;
  String? fcmToken;
  bool hasItems;
  Map<String, dynamic>? items;

  OrderItem({
    this.id,
    required this.customerName,
    this.customerPhone,
    required this.orderDate,
    required this.pickupDate,
    required this.weightKg,
    required this.isPickedUp,
    this.notes,
    this.resi,
    this.fcmToken,
    this.hasItems = false,
    this.items,
  });

  // Menghitung bobot aktual dalam kg berdasarkan detail item
  double get actualWeightKg {
    if (hasItems && items != null) {
      double total = 0.0;
      items!.forEach((key, value) {
        final qty = (value as num).toDouble();
        if (key == 'susunan_3') {
          total += qty * 3;
        } else if (key == 'susunan_5') {
          total += qty * 5;
        } else if (key == 'susunan_7') {
          total += qty * 7;
        } else {
          total += qty; // Untuk kue cina dan dodol, nilai = kg
        }
      });
      return total;
    }
    return weightKg; // Fallback ke default weightKg jika tidak pakai fitur item detail
  }

  static String toIsoDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Map<String, dynamic> toJson() {
    return {
      'customerName': customerName,
      'customerPhone': customerPhone,
      'orderDate': orderDate.toIso8601String(),
      'pickupDate': pickupDate.toIso8601String(),
      'weightKg': weightKg,
      'isPickedUp': isPickedUp,
      'notes': notes,
      'resi': resi,
      'fcmToken': fcmToken,
      if (items != null) 'items': items,
    };
  }

  factory OrderItem.fromJson(Map<String, dynamic> json, [String? docId]) {
    double parsedWeight = 0.0;
    String parsedNotes = json['notes'] ?? '';
    bool hasItems = false;
    Map<String, dynamic>? parsedItems;

    // Mengambil data 'items' jika pesanan berasal dari aplikasi pembeli (Client)
    if (json['items'] != null && json['items'] is Map) {
      final itemsMap = json['items'] as Map<String, dynamic>;
      hasItems = true; // Tandai bahwa ini pesanan gaya baru
      parsedItems = itemsMap; // Simpan map items untuk konversi actualWeightKg

      parsedWeight = itemsMap.length.toDouble(); // Menghitung jumlah jenis item
    } else {
      parsedWeight = (json['weightKg'] as num?)?.toDouble() ?? 0.0;
    }

    return OrderItem(
      id: docId,
      customerName: json['customerName'] ?? '',
      customerPhone: json['customerPhone'],
      orderDate: DateTime.parse(json['orderDate']),
      pickupDate: DateTime.parse(json['pickupDate']),
      weightKg: parsedWeight,
      isPickedUp: json['isPickedUp'] ?? false,
      notes: parsedNotes.isEmpty ? null : parsedNotes,
      resi: json['resi'],
      fcmToken: json['fcmToken'],
      hasItems: hasItems,
      items: parsedItems,
    );
  }
}

class OrderPage extends StatefulWidget {
  final List<OrderItem> initialOrders;

  const OrderPage({super.key, required this.initialOrders});

  @override
  State<OrderPage> createState() => _OrderPageState();
}

class _OrderPageState extends State<OrderPage> {
  int _selectedIndex = 0;
  int _currentPage = 0;
  final int _itemsPerPage = 3; // Menampilkan 3 pembeli per halaman

  bool _isScanning = true;

  StreamSubscription<QuerySnapshot>? _ordersSubscription;
  StreamSubscription<QuerySnapshot>? _usersSubscription;

  final TextEditingController _customerController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  DateTime? _filterStartDate;
  DateTime? _filterEndDate;

  DateTime? _pickupDate;

  final List<OrderItem> _orders = [];

  final List<Map<String, dynamic>> _menuItems = [
    {'id': 'kue_cina', 'name': 'Kue Cina', 'unit': 'kg'},
    {'id': 'susunan_3', 'name': 'Susunan 3', 'unit': 'set'},
    {'id': 'susunan_5', 'name': 'Susunan 5', 'unit': 'set'},
    {'id': 'susunan_7', 'name': 'Susunan 7', 'unit': 'set'},
    {'id': 'dodol_lapis', 'name': 'Dodol Lapis', 'unit': 'kg'},
    {'id': 'dodol_biasa', 'name': 'Dodol Biasa', 'unit': 'kg'},
    {'id': 'dodol_duren', 'name': 'Dodol Duren', 'unit': 'kg'},
  ];

  final Map<String, int> _cart = {};

  void _updateCart(String id, int delta) {
    setState(() {
      int currentQty = _cart[id] ?? 0;
      int newQty = currentQty + delta;
      if (newQty <= 0) {
        _cart.remove(id);
      } else {
        _cart[id] = newQty;
      }
    });
  }

  List<Map<String, String>> _firebaseUsers = [];

  List<Map<String, String>> get _uniqueCustomers {
    final Map<String, String> customers = {};

    // 1. Muat dari koleksi users Firebase (Prioritas Utama)
    for (var user in _firebaseUsers) {
      customers[user['phone']!] = user['name']!;
    }

    // 2. Gabungkan dengan pesanan lokal sebagai fallback data lama
    final sortedOrders = List<OrderItem>.from(_orders)
      ..sort((a, b) => b.orderDate.compareTo(a.orderDate));

    for (var order in sortedOrders) {
      if (order.customerPhone != null &&
          order.customerPhone!.trim().isNotEmpty) {
        // Gunakan nomor WA sebagai kunci agar tidak ada data ganda
        if (!customers.containsKey(order.customerPhone!)) {
          customers[order.customerPhone!] = order.customerName;
        }
      }
    }
    return customers.entries
        .map((e) => {'phone': e.key, 'name': e.value})
        .toList()
      ..sort((a, b) =>
          a['name']!.toLowerCase().compareTo(b['name']!.toLowerCase()));
  }

  final DateFormat _dateFormat = DateFormat('dd MMM yyyy', 'id_ID');

  @override
  void initState() {
    super.initState();
    _orders.addAll(widget.initialOrders);
    _setThisMonth();

    // Mulai mendengarkan perubahan Firestore secara real-time
    _ordersSubscription = FirebaseFirestore.instance
        .collection(_kCollectionOrders)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      final updatedOrders = snapshot.docs
          .map((doc) => OrderItem.fromJson(doc.data(), doc.id))
          .toList();
      setState(() {
        _orders.clear();
        _orders.addAll(updatedOrders);
      });
    });

    // Mulai mendengarkan perubahan data users secara real-time
    _usersSubscription = FirebaseFirestore.instance
        .collection(_kCollectionUsers)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      final List<Map<String, String>> users = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final name = data['name'] as String?;
        final phone = data['phone'] as String?;
        if (name != null && phone != null && phone.trim().isNotEmpty) {
          users.add({'name': name, 'phone': phone});
        }
      }
      setState(() {
        _firebaseUsers = users;
      });
    });

    // Jika ada order yang perlu diingatkan, dialog akan muncul setelah halaman ini selesai dibangun
    if (_orders.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _checkReminders();
        }
      });
    }
  }

  @override
  void dispose() {
    _ordersSubscription?.cancel();
    _usersSubscription?.cancel();
    _customerController.dispose();
    _phoneController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _checkReminders() {
    final upcomingOrders = _upcomingOrders;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (upcomingOrders.isEmpty) {
      return; // Jika tidak ada order hari ini/besok, lewati
    }

    // Memutar suara notifikasi bawaan (alert/beep)
    SystemSound.play(SystemSoundType.alert);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          titlePadding: const EdgeInsets.all(0),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          actionsPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          title: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.notifications_active,
                    color: Colors.orange, size: 28),
                SizedBox(width: 16),
                Text('Pengingat Pesanan!',
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          content: SizedBox(
            width: 450,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ada ${upcomingOrders.length} pesanan yang akan diambil dalam waktu dekat.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
                  ),
                  const SizedBox(height: 20),
                  ...upcomingOrders.map((o) {
                    final isToday = DateTime(o.pickupDate.year,
                            o.pickupDate.month, o.pickupDate.day)
                        .isAtSameMomentAs(today);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: isToday
                                ? Colors.red.shade200
                                : Colors.orange.shade200),
                        color: isToday
                            ? Colors.red.shade50
                            : Colors.orange.shade50,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isToday
                                ? Icons.warning_amber_rounded
                                : Icons.schedule,
                            color: isToday
                                ? Colors.red.shade700
                                : Colors.orange.shade700,
                            size: 28,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(o.customerName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16)),
                                const SizedBox(height: 4),
                                Text(isToday ? 'Ambil Hari ini' : 'Ambil Besok',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: isToday
                                            ? Colors.red.shade800
                                            : Colors.orange.shade800)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Text(
                              o.hasItems
                                  ? '${o.weightKg.toInt()} item'
                                  : '${o.weightKg.toStringAsFixed(1)} kg',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Close dialog
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        ReminderPage(upcomingOrders: upcomingOrders),
                  ),
                );
              },
              child: const Text('Lihat Detail'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tutup'),
            ),
          ],
        );
      },
    );
  }

  List<OrderItem> get _upcomingOrders {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    return _orders.where((o) {
      if (o.isPickedUp) return false; // Abaikan yang sudah diambil
      final pickup =
          DateTime(o.pickupDate.year, o.pickupDate.month, o.pickupDate.day);
      return pickup.isAtSameMomentAs(today) ||
          pickup.isAtSameMomentAs(tomorrow);
    }).toList()
      // Urutkan berdasarkan tanggal ambil, yang hari ini duluan
      ..sort((a, b) => a.pickupDate.compareTo(b.pickupDate));
  }

  List<OrderItem> get _filteredOrders {
    return _orders.where((order) {
      // Filter pencarian berdasarkan nama pembeli (mengabaikan huruf besar/kecil)
      if (_searchQuery.isNotEmpty) {
        if (!order.customerName
            .toLowerCase()
            .contains(_searchQuery.toLowerCase())) {
          return false;
        }
      }

      if (_filterStartDate == null || _filterEndDate == null) return true;

      final start = DateTime(
        _filterStartDate!.year,
        _filterStartDate!.month,
        _filterStartDate!.day,
      );
      final end = DateTime(
        _filterEndDate!.year,
        _filterEndDate!.month,
        _filterEndDate!.day,
      );
      final orderDateOnly = DateTime(
        order.orderDate.year,
        order.orderDate.month,
        order.orderDate.day,
      );
      final pickupDateOnly = DateTime(
        order.pickupDate.year,
        order.pickupDate.month,
        order.pickupDate.day,
      );

      final orderDateMatch =
          !orderDateOnly.isBefore(start) && !orderDateOnly.isAfter(end);
      final pickupDateMatch =
          !pickupDateOnly.isBefore(start) && !pickupDateOnly.isAfter(end);

      return orderDateMatch && pickupDateMatch;
    }).toList()
      ..sort((a, b) {
        final byName = a.customerName.compareTo(b.customerName);
        if (byName != 0) return byName;
        return a.orderDate.compareTo(b.orderDate);
      });
  }

  Map<String, List<OrderItem>> get _groupedOrders {
    final grouped = <String, List<OrderItem>>{};
    for (final item in _filteredOrders) {
      grouped.putIfAbsent(item.customerName, () => []).add(item);
    }
    for (final entry in grouped.entries) {
      entry.value.sort((a, b) {
        if (a.isPickedUp && !b.isPickedUp) return 1;
        if (!a.isPickedUp && b.isPickedUp) return -1;
        return a.pickupDate.compareTo(b.pickupDate);
      });
    }
    return grouped;
  }

  double get _totalOrderedWeight =>
      _filteredOrders.fold(0.0, (sum, item) => sum + item.actualWeightKg);

  double get _remainingWeight => _filteredOrders
      .where((item) => !item.isPickedUp)
      .fold(0.0, (sum, item) => sum + item.actualWeightKg);

  int get _totalOrderCount => _filteredOrders.length;
  int get _totalCustomerCount => _groupedOrders.length;

  double _getTotalWeightPerCustomer(List<OrderItem> items) =>
      items.fold(0.0, (sum, item) => sum + item.actualWeightKg);

  double _getRemainingWeightPerCustomer(List<OrderItem> items) => items
      .where((item) => !item.isPickedUp)
      .fold(0.0, (sum, item) => sum + item.actualWeightKg);

  Future<void> _pickDateRange() async {
    DateTime tempStart = _filterStartDate ?? DateTime.now();
    DateTime tempEnd = _filterEndDate ?? DateTime.now();

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> pickStartDate() async {
              final picked = await showDatePicker(
                context: context,
                initialDate: tempStart,
                firstDate: DateTime(2024),
                lastDate: DateTime(2035),
                helpText: 'Pilih tanggal awal',
              );
              if (picked != null) {
                setModalState(() {
                  tempStart = picked;
                  if (tempEnd.isBefore(tempStart)) tempEnd = tempStart;
                });
              }
            }

            Future<void> pickEndDate() async {
              final picked = await showDatePicker(
                context: context,
                initialDate: tempEnd,
                firstDate: DateTime(2024),
                lastDate: DateTime(2035),
                helpText: 'Pilih tanggal akhir',
              );
              if (picked != null) {
                setModalState(() {
                  tempEnd = picked;
                  if (tempStart.isAfter(tempEnd)) tempStart = tempEnd;
                });
              }
            }

            return Dialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.date_range_rounded,
                              color: Colors.deepOrange, size: 28),
                          SizedBox(width: 12),
                          Text(
                            'Filter Tanggal',
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      const Text('Mulai Dari',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey)),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: pickStartDate,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 16),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today_rounded,
                                  color: Colors.deepOrange, size: 20),
                              const SizedBox(width: 12),
                              Text(_dateFormat.format(tempStart),
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('Sampai Dengan',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey)),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: pickEndDate,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 16),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.event_rounded,
                                  color: Colors.deepOrange, size: 20),
                              const SizedBox(width: 12),
                              Text(_dateFormat.format(tempEnd),
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _filterStartDate = null;
                                _filterEndDate = null;
                              });
                              Navigator.pop(context);
                            },
                            style: TextButton.styleFrom(
                                foregroundColor: Colors.red.shade400),
                            child: const Text('Reset',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          Row(
                            children: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                style: TextButton.styleFrom(
                                    foregroundColor: Colors.black54),
                                child: const Text('Batal'),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: () {
                                  setState(() {
                                    _filterStartDate = tempStart;
                                    _filterEndDate = tempEnd;
                                  });
                                  Navigator.pop(context);
                                },
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.deepOrange,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(30)),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 24, vertical: 12),
                                  elevation: 2,
                                ),
                                child: const Text('Terapkan',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _setToday() {
    final now = DateTime.now();
    setState(() {
      _filterStartDate = DateTime(now.year, now.month, now.day);
      _filterEndDate = DateTime(now.year, now.month, now.day);
      _currentPage = 0;
    });
  }

  void _setThisMonth() {
    final now = DateTime.now();
    setState(() {
      _filterStartDate = DateTime(now.year, now.month, 1);
      _filterEndDate = DateTime(now.year, now.month + 1, 0);
      _currentPage = 0;
    });
  }

  void _setLast7Days() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _filterEndDate = today;
      _filterStartDate = today.subtract(const Duration(days: 6));
      _currentPage = 0;
    });
  }

  void _clearFilter() => setState(() {
        _filterStartDate = null;
        _filterEndDate = null;
        _currentPage = 0;
      });

  Future<void> _pickPickupDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _pickupDate ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
      helpText: 'Tanggal diambil',
    );
    if (picked != null) {
      setState(() {
        _pickupDate = picked;
      });
    }
  }

  Future<void> _showCustomerListPopup() async {
    await showDialog(
      context: context,
      builder: (context) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filteredCustomers = _uniqueCustomers.where((c) {
              return c['name']!
                      .toLowerCase()
                      .contains(searchQuery.toLowerCase()) ||
                  c['phone']!.contains(searchQuery);
            }).toList();

            return Dialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: 400, maxHeight: 600),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.people_alt_outlined,
                              color: Colors.deepOrange, size: 28),
                          SizedBox(width: 12),
                          Text(
                            'Pilih Pelanggan',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        autofocus: true,
                        onChanged: (val) =>
                            setModalState(() => searchQuery = val),
                        decoration: InputDecoration(
                          hintText: 'Cari atau ketik nama baru...',
                          prefixIcon:
                              const Icon(Icons.search, color: Colors.grey),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.grey.shade200),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide:
                                BorderSide(color: Colors.deepOrange.shade300),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: filteredCustomers.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.person_add_alt_1_outlined,
                                        size: 48, color: Colors.grey.shade400),
                                    const SizedBox(height: 16),
                                    Text(
                                      'Pelanggan tidak ditemukan',
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.grey.shade700),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Tambahkan "$searchQuery" sebagai pelanggan baru?',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: Colors.grey.shade500,
                                          fontSize: 14),
                                    ),
                                    const SizedBox(height: 20),
                                    FilledButton.icon(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Colors.deepOrange,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(30)),
                                      ),
                                      onPressed: () {
                                        _customerController.text = searchQuery;
                                        _phoneController.clear();
                                        Navigator.pop(context);
                                      },
                                      icon: const Icon(Icons.add, size: 18),
                                      label: const Text('Gunakan Nama Ini',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold)),
                                    )
                                  ],
                                ),
                              )
                            : ListView.separated(
                                itemCount: filteredCustomers.length,
                                separatorBuilder: (_, __) => Divider(
                                    height: 1,
                                    color: Colors.grey.shade100,
                                    indent: 56),
                                itemBuilder: (context, index) {
                                  final c = filteredCustomers[index];
                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    leading: CircleAvatar(
                                      radius: 22,
                                      backgroundColor:
                                          Colors.deepOrange.shade50,
                                      child: Text(
                                        c['name']![0].toUpperCase(),
                                        style: TextStyle(
                                            color: Colors.deepOrange.shade700,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18),
                                      ),
                                    ),
                                    title: Text(c['name']!,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                            color: Colors.black87)),
                                    subtitle: Text(c['phone']!,
                                        style: TextStyle(
                                            color: Colors.grey.shade600,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500)),
                                    onTap: () {
                                      _customerController.text = c['name']!;
                                      _phoneController.text = c['phone']!;
                                      Navigator.pop(context);
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _addOrder() async {
    final customerName = _normalizeCustomerName(_customerController.text);
    final customerPhone = _phoneController.text.trim();

    if (customerName.isEmpty ||
        customerPhone.isEmpty ||
        _pickupDate == null ||
        _cart.isEmpty) {
      _showSnackBar('Lengkapi nama pembeli, No. WA, tanggal ambil, dan item.');
      return;
    }

    final now = DateTime.now();
    // Validasi: Tanggal Pengambilan tidak boleh sebelum hari ini
    final orderDateOnly = DateTime(now.year, now.month, now.day);
    final pickupDateOnly =
        DateTime(_pickupDate!.year, _pickupDate!.month, _pickupDate!.day);
    if (orderDateOnly.isAfter(pickupDateOnly)) {
      _showSnackBar('Tanggal pengambilan tidak boleh sebelum hari ini.');
      return;
    }

    final random = Random();
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final randomString =
        List.generate(8, (index) => chars[random.nextInt(chars.length)]).join();
    final noResi = 'RS-$randomString';

    final List<String> summaryList = [];
    final List<String> notifItems = [];
    for (var entry in _cart.entries) {
      final item = _menuItems.firstWhere((m) => m['id'] == entry.key);
      final prefix =
          item['unit'] == 'kg' ? '${entry.value}kg' : '${entry.value}x';
      summaryList.add('- $prefix ${item['name']}');
      notifItems.add('$prefix ${item['name']}');
    }
    final String cartSummary = summaryList.join('\n');
    final String itemsSummary = notifItems.join(' & ');
    final String finalNotes = cartSummary;

    // Cari fcmToken dari riwayat pesanan pelanggan ini jika ada (berdasarkan No. WA)
    String? fcmToken;
    // Bersihkan format nomor HP dari spasi/strip agar pencocokan 100% akurat
    final cleanPhone = customerPhone.replaceAll(RegExp(r'\D'), '');

    final previousOrders = _orders.where((o) {
      if (o.customerPhone == null ||
          o.fcmToken == null ||
          o.fcmToken!.trim().isEmpty) {
        return false;
      }
      final cleanOPhone = o.customerPhone!.replaceAll(RegExp(r'\D'), '');
      return cleanOPhone == cleanPhone;
    }).toList();

    if (previousOrders.isNotEmpty) {
      previousOrders.sort((a, b) => b.orderDate.compareTo(a.orderDate));
      fcmToken = previousOrders
          .first.fcmToken; // Ambil token dari pesanan paling terbaru
      debugPrint('✅ FCM Token berhasil disalin: $fcmToken');
    } else {
      debugPrint(
          '⚠️ FCM Token tidak ditemukan untuk histori No. WA: $cleanPhone');
    }

    final newItem = OrderItem(
      customerName: customerName,
      customerPhone: cleanPhone,
      orderDate: now,
      pickupDate: _pickupDate!,
      weightKg: _cart.length.toDouble(),
      isPickedUp: false,
      notes: finalNotes,
      resi: noResi,
      fcmToken: fcmToken,
      hasItems: true,
      items: _cart,
    );

    try {
      // Simpan ke Firestore menggunakan Nomor Resi sebagai ID Dokumen
      await FirebaseFirestore.instance
          .collection(_kCollectionOrders)
          .doc(noResi)
          .set(newItem.toJson());

      newItem.id = noResi; // Assign ID ke model lokal

      // Daftarkan/Update data user ke collection 'users' agar bisa dipakai login di aplikasi client
      if (cleanPhone.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection(_kCollectionUsers)
            .doc(cleanPhone)
            .set({
          'name': customerName,
          'phone': cleanPhone,
          // Gunakan merge: true agar tidak menimpa data lain (seperti alamat/token) jika user sudah ada
        }, SetOptions(merge: true));
      }

      // Panggil API Vercel untuk Broadcast Notifikasi ke Semua Admin
      try {
        final response = await http.post(
          Uri.parse(_kApiNotify),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'customerName': newItem.customerName,
            'weightKg': newItem.actualWeightKg
                .toInt(), // Supaya admin dapat push notif bobot yang benar
            'itemsSummary': itemsSummary,
          }),
        );
        if (response.statusCode != 200) {
          debugPrint('Vercel API Error: ${response.body}');
        }
      } catch (e) {
        debugPrint('Gagal menghubungi server Vercel: $e');
      }

      setState(() {
        _customerController.clear();
        _phoneController.clear();
        _pickupDate = null;
        _cart.clear();
        _selectedIndex =
            2; // Ubah ke 2 agar beralih ke 'Daftar Order' (karena tab 1 sekarang 'Scan QR')
        _currentPage = 0;
      });

      _showSnackBar('Berhasil! Order disimpan ke database Firebase.');
    } catch (e) {
      _showSnackBar('Gagal menyimpan ke database: $e');
    }
  }

  Future<void> _editOrder(OrderItem item) async {
    final customerController = TextEditingController(text: item.customerName);
    final phoneController =
        TextEditingController(text: item.customerPhone ?? '');
    final weightController =
        TextEditingController(text: item.weightKg.toStringAsFixed(2));
    final notesController = TextEditingController(text: item.notes);
    DateTime selectedOrderDate = item.orderDate;
    DateTime selectedPickupDate = item.pickupDate;
    bool selectedPickedUp = item.isPickedUp;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: const Text('Edit Order'),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: customerController,
                        decoration: InputDecoration(
                          labelText: 'Nama Pembeli',
                          prefixIcon: const Icon(Icons.person_outline),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: 'Nomor WhatsApp',
                          prefixIcon: const Icon(Icons.phone_outlined),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedOrderDate,
                            firstDate: DateTime(2024),
                            lastDate: DateTime(2035),
                          );
                          if (picked != null) {
                            setModalState(() => selectedOrderDate = picked);
                          }
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'Tgl Order Masuk',
                            prefixIcon: const Icon(Icons.edit_calendar),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16)),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide:
                                  BorderSide(color: Colors.grey.shade300),
                            ),
                          ),
                          child: Text(_dateFormat.format(selectedOrderDate)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedPickupDate,
                            firstDate: DateTime(2024),
                            lastDate: DateTime(2035),
                          );
                          if (picked != null) {
                            setModalState(() => selectedPickupDate = picked);
                          }
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'Tgl Pengambilan',
                            prefixIcon: const Icon(Icons.event_available),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16)),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide:
                                  BorderSide(color: Colors.grey.shade300),
                            ),
                          ),
                          child: Text(_dateFormat.format(selectedPickupDate)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: weightController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText:
                              item.hasItems ? 'Jumlah Item' : 'Bobot Kue (kg)',
                          prefixIcon: const Icon(Icons.scale_outlined),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: selectedPickedUp,
                        activeThumbColor: Colors.green,
                        onChanged: (value) =>
                            setModalState(() => selectedPickedUp = value),
                        title: const Text('Sudah diambil'),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Batal'),
                ),
                FilledButton(
                  onPressed: () async {
                    final updatedName =
                        _normalizeCustomerName(customerController.text);
                    final updatedPhone =
                        phoneController.text.replaceAll(RegExp(r'\D'), '');
                    final updatedWeight = double.tryParse(
                      weightController.text.trim().replaceAll(',', '.'),
                    );
                    if (updatedName.isEmpty ||
                        updatedWeight == null ||
                        updatedWeight <= 0) {
                      _showSnackBar(
                        'Nama pembeli dan bobot harus diisi dengan benar.',
                      );
                      return;
                    }

                    // Validasi: Tanggal Pesan tidak boleh lebih besar dari Tanggal Ambil (saat diedit)
                    final editOrderOnly = DateTime(selectedOrderDate.year,
                        selectedOrderDate.month, selectedOrderDate.day);
                    final editPickupOnly = DateTime(selectedPickupDate.year,
                        selectedPickupDate.month, selectedPickupDate.day);
                    if (editOrderOnly.isAfter(editPickupOnly)) {
                      _showSnackBar(
                          'Tanggal pesanan tidak boleh lebih besar dari tanggal pengambilan.');
                      return;
                    }

                    final updatedNotes = notesController.text.trim();
                    // Update spesifik dokumen di Firestore
                    await FirebaseFirestore.instance
                        .collection(_kCollectionOrders)
                        .doc(item.id)
                        .update({
                      'customerName': updatedName,
                      'customerPhone':
                          updatedPhone.isEmpty ? null : updatedPhone,
                      'orderDate': selectedOrderDate.toIso8601String(),
                      'pickupDate': selectedPickupDate.toIso8601String(),
                      'weightKg': updatedWeight,
                      'isPickedUp': selectedPickedUp,
                      'notes': updatedNotes.isEmpty ? null : updatedNotes,
                    });

                    if (mounted) Navigator.pop(context);
                    _showSnackBar('Order berhasil diperbarui.');
                  },
                  child: const Text('Simpan'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteOrder(OrderItem item) async {
    // Hapus dari Firestore berdasarkan ID-nya
    await FirebaseFirestore.instance
        .collection(_kCollectionOrders)
        .doc(item.id)
        .delete();

    _showSnackBar('Order berhasil dihapus.');
  }

  void _showOrderDetails(OrderItem item) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.receipt_long, color: Colors.deepOrange),
              SizedBox(width: 8),
              Text('Detail Pesanan'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.customerName,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(height: 12),
                const Divider(height: 1, color: Colors.black12),
                const SizedBox(height: 12),
                Text('Tgl Pengambilan: ${_dateFormat.format(item.pickupDate)}',
                    style: const TextStyle(fontSize: 15)),
                const SizedBox(height: 8),
                Text(
                    item.hasItems
                        ? 'Pesanan: ${item.weightKg.toInt()} item'
                        : 'Bobot: ${item.weightKg.toStringAsFixed(1)} kg',
                    style: const TextStyle(fontSize: 15)),
                if (item.notes != null && item.notes!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(item.hasItems ? 'Rincian Pesanan:' : 'Catatan:',
                      style:
                          const TextStyle(fontSize: 14, color: Colors.black54)),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.shade100),
                    ),
                    child: Text(
                      item.notes!,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tutup'),
            ),
          ],
        );
      },
    );
  }

  void _showQrCode(OrderItem item) {
    // 1. Siapkan format data untuk QR Code
    final qrData = 'Resi: ${item.resi ?? '-'}\n'
        'Nama: ${item.customerName}\n'
        '${item.hasItems ? "Item:" : "Bobot:"} ${item.hasItems ? "${item.weightKg.toInt()} item" : "${item.weightKg.toStringAsFixed(1)} kg"}\n'
        'Tgl Ambil: ${_dateFormat.format(item.pickupDate)}';

    // 2. Tampilkan dalam bentuk Pop-up Dialog
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'QR Code Pesanan',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          spreadRadius: 2,
                        )
                      ],
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: SizedBox(
                      width: 200,
                      height: 200,
                      child: QrImageView(
                        data: qrData,
                        version: QrVersions.auto,
                        size: 200.0,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    item.customerName,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 22),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  if (item.resi != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.deepOrange.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'No. Resi: ${item.resi}',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.deepOrange.shade800,
                            fontSize: 14),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    '${item.hasItems ? "${item.weightKg.toInt()} item" : "${item.weightKg.toStringAsFixed(1)} kg"} • Ambil: ${_dateFormat.format(item.pickupDate)}',
                    style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.grey.shade700,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                        ),
                        child: const Text('Tutup',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.deepOrange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          elevation: 2,
                        ),
                        onPressed: () {
                          Navigator.pop(
                              context); // Tutup dialog sebelum proses print
                          _printQrCode(item, qrData);
                        },
                        icon: const Icon(Icons.print, size: 18),
                        label: const Text('Cetak',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _printQrCode(OrderItem item, String qrData) async {
    try {
      final doc = pw.Document();

      doc.addPage(
        pw.Page(
          pageFormat:
              PdfPageFormat.roll80, // Menggunakan format struk kasir 80mm
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Column(
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  pw.Text(
                    'Pesan Keranjang',
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold, fontSize: 16),
                  ),
                  if (item.resi != null) ...[
                    pw.SizedBox(height: 4),
                    pw.Text('Resi: ${item.resi}',
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold, fontSize: 12)),
                  ],
                  pw.SizedBox(height: 12),
                  pw.SizedBox(
                    height: 120,
                    width: 120,
                    child: pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: qrData,
                    ),
                  ),
                  pw.SizedBox(height: 12),
                  pw.Text(
                    item.customerName,
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold, fontSize: 14),
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    item.hasItems
                        ? 'Item: ${item.weightKg.toInt()} item'
                        : 'Bobot: ${item.weightKg.toStringAsFixed(1)} kg',
                    style: const pw.TextStyle(fontSize: 12),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Ambil: ${_dateFormat.format(item.pickupDate)}',
                    style: const pw.TextStyle(fontSize: 12),
                  ),
                  if (item.notes != null && item.notes!.isNotEmpty) ...[
                    pw.SizedBox(height: 8),
                    pw.Text(
                      item.hasItems
                          ? 'Rincian:\n${item.notes}'
                          : 'Catatan: ${item.notes}',
                      style: const pw.TextStyle(fontSize: 10),
                      textAlign: pw.TextAlign.center,
                    ),
                  ]
                ],
              ),
            );
          },
        ),
      );

      // Membuka dialog print bawaan OS
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: 'QR_Pesanan_${item.customerName.replaceAll(" ", "_")}',
      );
    } catch (e) {
      _showSnackBar('Gagal mencetak QR Code: $e');
    }
  }

  Future<void> _importXlsx() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final bytes = result.files.first.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Gagal membaca file XLSX.');
      }

      final workbook = excel.Excel.decodeBytes(bytes);
      if (workbook.tables.isEmpty) {
        throw Exception('Sheet XLSX tidak ditemukan.');
      }

      final importedOrders =
          _parseOrdersFromSheet(workbook.tables[workbook.tables.keys.first]!);

      // Operasi massal (Batch Write) Firestore
      final batch = FirebaseFirestore.instance.batch();
      final collection =
          FirebaseFirestore.instance.collection(_kCollectionOrders);

      // Hapus data lama di database (opsional: agar sesuai logika sebelumnya yg me-replace list)
      final oldDocs = await collection.get();
      for (var doc in oldDocs.docs) {
        batch.delete(doc.reference);
      }

      // Masukkan data import yang baru
      for (var item in importedOrders) {
        final docRef = collection.doc();
        item.id = docRef.id;
        batch.set(docRef, item.toJson());
      }

      await batch.commit(); // Eksekusi sekaligus

      setState(() {
        _currentPage = 0;
      });

      _showSnackBar(
          'Import XLSX berhasil. ${importedOrders.length} order dimuat.');
    } catch (e) {
      _showSnackBar('Gagal import XLSX: $e');
    }
  }

  Future<void> _downloadXlsx() async {
    try {
      final workbook = excel.Excel.createExcel();
      final defaultSheetName = workbook.getDefaultSheet() ?? 'Sheet1';
      if (defaultSheetName != 'Orders') {
        workbook.rename(defaultSheetName, 'Orders');
      }
      final excel.Sheet sheet = workbook['Orders'];

      final headers = [
        'customer_name',
        'order_date',
        'pickup_date',
        'weight_kg',
        'is_picked_up',
        'notes',
        'resi',
      ];

      for (int col = 0; col < headers.length; col++) {
        sheet
            .cell(
              excel.CellIndex.indexByColumnRow(
                columnIndex: col,
                rowIndex: 0,
              ),
            )
            .value = excel.TextCellValue(headers[col]);
      }

      for (int row = 0; row < _orders.length; row++) {
        final item = _orders[row];
        final dataRow = row + 1;

        sheet
            .cell(
              excel.CellIndex.indexByColumnRow(
                columnIndex: 0,
                rowIndex: dataRow,
              ),
            )
            .value = excel.TextCellValue(item.customerName);

        sheet
            .cell(
              excel.CellIndex.indexByColumnRow(
                columnIndex: 1,
                rowIndex: dataRow,
              ),
            )
            .value = excel.TextCellValue(item.customerPhone ?? '');

        sheet
            .cell(
              excel.CellIndex.indexByColumnRow(
                columnIndex: 2,
                rowIndex: dataRow,
              ),
            )
            .value = excel.TextCellValue(OrderItem.toIsoDate(item.orderDate));

        sheet
            .cell(
              excel.CellIndex.indexByColumnRow(
                columnIndex: 2,
                rowIndex: dataRow,
              ),
            )
            .value = excel.TextCellValue(OrderItem.toIsoDate(item.pickupDate));

        sheet
                .cell(
                  excel.CellIndex.indexByColumnRow(
                    columnIndex: 3,
                    rowIndex: dataRow,
                  ),
                )
                .value =
            excel.DoubleCellValue(
                item.actualWeightKg); // Ekspor Excel mencatat nilai aktual kg

        sheet
            .cell(
              excel.CellIndex.indexByColumnRow(
                columnIndex: 4,
                rowIndex: dataRow,
              ),
            )
            .value = excel.TextCellValue(item.isPickedUp ? 'true' : 'false');

        sheet
            .cell(
              excel.CellIndex.indexByColumnRow(
                columnIndex: 5,
                rowIndex: dataRow,
              ),
            )
            .value = excel.TextCellValue(item.notes ?? '');

        sheet
            .cell(
              excel.CellIndex.indexByColumnRow(
                columnIndex: 6,
                rowIndex: dataRow,
              ),
            )
            .value = excel.TextCellValue(item.resi ?? '');
      }

      final encoded = workbook.encode();
      if (encoded == null || encoded.isEmpty) {
        throw Exception('Gagal membuat file XLSX.');
      }

      final fileBytes = Uint8List.fromList(encoded);

      Directory? directory;
      if (!kIsWeb && Platform.isAndroid) {
        directory = await getExternalStorageDirectory();
      } else if (!kIsWeb && Platform.isIOS) {
        directory = await getApplicationDocumentsDirectory();
      }

      if (directory != null) {
        final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
        final filePath = '${directory.path}/Order_Kue_Cina_$timestamp.xlsx';
        final file = File(filePath);

        await file.writeAsBytes(fileBytes, flush: true);
        _showSnackBar('Berhasil! File tersimpan.');

        final result = await OpenFilex.open(filePath);
        if (result.type != ResultType.done) {
          _showSnackBar(
            'File tersimpan, tapi tidak ada aplikasi untuk membukanya.',
          );
        }
      }
    } catch (e) {
      _showSnackBar('Gagal menyiapkan XLSX: $e');
    }
  }

  List<OrderItem> _parseOrdersFromSheet(excel.Sheet sheet) {
    final rows = sheet.rows;
    if (rows.isEmpty) throw Exception('File XLSX kosong.');

    final header = rows.first
        .map((cell) => _cellToString(cell).trim().toLowerCase())
        .toList();

    final customerIndex = header.indexOf('customer_name');
    final phoneIndex = header.indexOf('customer_phone');
    final orderDateIndex = header.indexOf('order_date');
    final pickupDateIndex = header.indexOf('pickup_date');
    final weightIndex = header.indexOf('weight_kg');
    final pickedIndex = header.indexOf('is_picked_up');
    final notesIndex = header.indexOf('notes');
    final resiIndex = header.indexOf('resi');

    if (customerIndex == -1 ||
        orderDateIndex == -1 ||
        pickupDateIndex == -1 ||
        weightIndex == -1 ||
        pickedIndex == -1) {
      throw Exception('Header XLSX tidak sesuai standar.');
    }

    final result = <OrderItem>[];
    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.every((cell) => _cellToString(cell).trim().isEmpty)) continue;

      final customerName =
          _normalizeCustomerName(_readCell(row, customerIndex));
      final customerPhone =
          phoneIndex != -1 ? _readCell(row, phoneIndex).trim() : null;
      final orderDate = _parseFlexibleDate(_readCell(row, orderDateIndex));
      final pickupDate = _parseFlexibleDate(_readCell(row, pickupDateIndex));
      final weightKg = _parseFlexibleDouble(_readCell(row, weightIndex));
      final isPickedUp = _parseBool(_readCell(row, pickedIndex));
      final notesStr =
          notesIndex != -1 ? _readCell(row, notesIndex).trim() : '';
      final resiStr = resiIndex != -1 ? _readCell(row, resiIndex).trim() : '';

      if (customerName.isNotEmpty &&
          orderDate != null &&
          pickupDate != null &&
          weightKg != null) {
        result.add(
          OrderItem(
            customerName: customerName,
            customerPhone: customerPhone,
            orderDate: orderDate,
            pickupDate: pickupDate,
            weightKg: weightKg,
            isPickedUp: isPickedUp,
            notes: notesStr.isEmpty ? null : notesStr,
            resi: resiStr.isEmpty ? null : resiStr,
          ),
        );
      }
    }

    return result;
  }

  String _readCell(List<excel.Data?> row, int index) =>
      (index >= row.length) ? '' : _cellToString(row[index]);

  String _cellToString(excel.Data? cell) => cell?.value?.toString() ?? '';

  double? _parseFlexibleDouble(String value) =>
      double.tryParse(value.trim().replaceAll(',', '.'));

  DateTime? _parseFlexibleDate(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    try {
      return DateTime.parse(trimmed);
    } catch (_) {
      return null;
    }
  }

  bool _parseBool(String value) {
    final v = value.trim().toLowerCase();
    return v == 'true' || v == '1' || v == 'yes' || v == 'ya';
  }

  String _normalizeCustomerName(String text) => text
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .map(
        (word) => word[0].toUpperCase() + word.substring(1).toLowerCase(),
      )
      .join(' ');

  String _formatDateOrPlaceholder(DateTime? date, String placeholder) =>
      date == null ? placeholder : _dateFormat.format(date);

  String _formatRangeText() {
    if (_filterStartDate == null || _filterEndDate == null) {
      return 'Pilih rentang tanggal';
    }
    return '${_dateFormat.format(_filterStartDate!)} - ${_dateFormat.format(_filterEndDate!)}';
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Widget _buildInputTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Catat Pesanan',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Masukkan informasi pelanggan dan detail item.',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 32),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _customerController,
                      readOnly: true,
                      onTap: _showCustomerListPopup,
                      decoration: InputDecoration(
                        labelText: 'Nama Pelanggan',
                        hintText: 'Pilih atau ketik baru',
                        prefixIcon: const Icon(Icons.person_outline),
                        suffixIcon: const Icon(Icons.arrow_drop_down),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              BorderSide(color: Colors.deepOrange.shade300),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: 'Nomor WhatsApp',
                        hintText: 'Contoh: 081234567890',
                        prefixIcon: const Icon(Icons.phone_outlined),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              BorderSide(color: Colors.deepOrange.shade300),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      onTap: _pickPickupDate,
                      borderRadius: BorderRadius.circular(12),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Tanggal Pengambilan',
                          prefixIcon: const Icon(Icons.event_available),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade200),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade200),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                BorderSide(color: Colors.deepOrange.shade300),
                          ),
                        ),
                        child: Text(
                          _formatDateOrPlaceholder(
                              _pickupDate, 'Pilih tanggal'),
                          style: TextStyle(
                            color: _pickupDate == null
                                ? Colors.black54
                                : Colors.black87,
                            fontWeight: _pickupDate == null
                                ? FontWeight.normal
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Detail Item',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87),
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    ..._menuItems.asMap().entries.map((entry) {
                      final index = entry.key;
                      final item = entry.value;
                      final id = item['id'] as String;
                      final qty = _cart[id] ?? 0;
                      return Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(item['name'] as String,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 15,
                                              color: Colors.black87)),
                                      const SizedBox(height: 4),
                                      Text('Satuan: ${item['unit']}',
                                          style: TextStyle(
                                              color: Colors.deepOrange.shade600,
                                              fontWeight: FontWeight.w500,
                                              fontSize: 13)),
                                    ],
                                  ),
                                ),
                                if (qty ==
                                    0) // Tombol 'Tambah' jika item belum ada di keranjang
                                  OutlinedButton.icon(
                                    onPressed: () => _updateCart(id, 1),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor:
                                          Colors.deepOrange.shade700,
                                      side: BorderSide(
                                          color: Colors.deepOrange.shade200,
                                          width: 1.5),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      minimumSize: const Size(90, 42),
                                    ),
                                    icon: const Icon(Icons.add, size: 18),
                                    label: const Text(
                                      'Tambah',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  )
                                else // Stepper (+/-) jika item sudah ada
                                  Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.grey.shade300,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          onPressed: () => _updateCart(id, -1),
                                          icon: const Icon(Icons.remove),
                                          color: Colors.deepOrange.shade700,
                                          iconSize: 18,
                                          splashRadius: 20,
                                        ),
                                        SizedBox(
                                          width: 32,
                                          child: Text('$qty',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 15),
                                              textAlign: TextAlign.center),
                                        ),
                                        IconButton(
                                          onPressed: () => _updateCart(id, 1),
                                          icon: const Icon(Icons.add),
                                          color: Colors.deepOrange.shade700,
                                          iconSize: 18,
                                          splashRadius: 20,
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (index < _menuItems.length - 1)
                            Divider(
                                height: 1,
                                color: Colors.grey.shade100,
                                indent: 20,
                                endIndent: 20),
                        ],
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.deepOrange.withOpacity(0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    backgroundColor: Colors.deepOrange,
                    foregroundColor: Colors.white,
                    elevation: 0,
                  ),
                  onPressed: _addOrder,
                  icon: const Icon(Icons.check_circle_outline, size: 20),
                  label: const Text(
                    'Simpan Order',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyOrderState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 72,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'Belum Ada Pesanan',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Input pesanan baru atau impor data Excel.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _importXlsx,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE87570),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              icon: const Icon(Icons.file_upload_outlined, size: 18),
              label: const Text(
                'Import Data dari Excel',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _processScannedQR(String qrData) {
    setState(() {
      _isScanning = false; // Jeda scan sementara agar pop-up tidak muncul ganda
    });

    try {
      final resiMatch = RegExp(r'Resi:\s*(.*?)\n').firstMatch(qrData);
      final nameMatch = RegExp(r'Nama:\s*(.*?)\n').firstMatch(qrData);
      final weightMatch =
          RegExp(r'(?:Bobot|Item):\s*([\d\.]+)\s*(?:kg|macam|item)')
              .firstMatch(qrData);

      List<OrderItem> matchingOrders = [];

      if (resiMatch != null && resiMatch.group(1)?.trim() != '-') {
        final parsedResi = resiMatch.group(1)?.trim();
        matchingOrders = _orders.where((o) => o.resi == parsedResi).toList();
      } else if (nameMatch != null && weightMatch != null) {
        // Fallback untuk QR Code lama yang belum menggunakan nomor resi
        final parsedName = nameMatch.group(1)?.trim();
        final parsedWeightStr = weightMatch.group(1)?.trim();

        if (parsedName != null && parsedWeightStr != null) {
          matchingOrders = _orders
              .where((o) =>
                  o.customerName.toLowerCase() == parsedName.toLowerCase() &&
                  o.weightKg.toStringAsFixed(1) == parsedWeightStr)
              .toList();
        }
      }

      if (matchingOrders.isNotEmpty) {
        // Prioritaskan membuka pesanan yang berstatus "Belum Diambil"
        matchingOrders.sort((a, b) => a.isPickedUp ? 1 : -1);
        final targetOrder = matchingOrders.first;

        _showScannedOrderDialog(targetOrder);
        return;
      }

      // Jika format tidak sesuai atau order sudah terhapus
      _showSnackBar('QR Code tidak dikenali atau pesanan tidak ditemukan.');
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _isScanning = true);
      });
    } catch (e) {
      _showSnackBar('Gagal memproses QR Code.');
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _isScanning = true);
      });
    }
  }

  void _showScannedOrderDialog(OrderItem order) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: order.isPickedUp
                        ? Colors.green.shade50
                        : Colors.deepOrange.shade50,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(
                                order.isPickedUp
                                    ? Icons.check_circle_outline
                                    : Icons.warning_amber_rounded,
                                color: order.isPickedUp
                                    ? Colors.green
                                    : Colors.deepOrange,
                                size: 64,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                order.isPickedUp
                                    ? 'Pesanan Sudah Diambil!'
                                    : 'Pesanan Ditemukan!',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 22,
                                  color: order.isPickedUp
                                      ? Colors.green.shade800
                                      : Colors.deepOrange.shade800,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Icon X untuk Tutup di pojok kiri
                      Positioned(
                        top: 12,
                        left: 12,
                        child: IconButton(
                          icon: const Icon(Icons.close),
                          color: order.isPickedUp
                              ? Colors.green.shade800
                              : Colors.deepOrange.shade800,
                          onPressed: () {
                            Navigator.pop(context);
                            setState(() => _isScanning = true);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Text(
                          order.customerName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 22),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      if (order.resi != null) ...[
                        const SizedBox(height: 8),
                        Center(
                          child: Text(
                            'No. Resi: ${order.resi}',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                color: Colors.grey.shade600),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('TANGGAL AMBIL',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5)),
                                const SizedBox(height: 4),
                                Text(_dateFormat.format(order.pickupDate),
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                    order.hasItems
                                        ? 'JUMLAH ITEM'
                                        : 'TOTAL BOBOT',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5)),
                                const SizedBox(height: 4),
                                Text(
                                    order.hasItems
                                        ? '${order.weightKg.toInt()} Jenis'
                                        : '${order.actualWeightKg.toStringAsFixed(1)} kg',
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (order.hasItems &&
                          order.items != null &&
                          order.items!.isNotEmpty) ...[
                        const Divider(height: 32),
                        const Text(
                          'Rincian Pesanan',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: order.items!.entries.map((entry) {
                              final item = _menuItems.firstWhere(
                                  (m) => m['id'] == entry.key,
                                  orElse: () => {
                                        'id': 'unknown',
                                        'name': 'Item tidak dikenal',
                                        'unit': 'pcs'
                                      });
                              final qty = (entry.value as num).toInt();
                              final unit = item['unit'] as String;
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 6.0),
                                child: Row(
                                  children: [
                                    Text(
                                      '• ${item['name']}',
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500),
                                    ),
                                    const Spacer(),
                                    Text(
                                      '$qty $unit',
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: order.isPickedUp
                                ? Colors.green.shade100
                                : Colors.deepOrange.shade100,
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Text(
                            'STATUS: ${order.isPickedUp ? "SUDAH DIAMBIL" : "BELUM DIAMBIL"}',
                            style: TextStyle(
                              fontSize: 12,
                              letterSpacing: 0.5,
                              color: order.isPickedUp
                                  ? Colors.green.shade800
                                  : Colors.deepOrange.shade800,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
                if (!order.isPickedUp)
                  Container(
                    padding: const EdgeInsets.all(24.0),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(24)),
                    ),
                    child: Center(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black87,
                          elevation: 6, // Memberikan efek pop-out 3D
                          shadowColor: Colors.black45,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 32, vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        onPressed: () async {
                          // Update ke Firestore
                          await FirebaseFirestore.instance
                              .collection(_kCollectionOrders)
                              .doc(order.id)
                              .update({'isPickedUp': true});

                          // Kirim notifikasi pesanan selesai ke pelanggan
                          if (order.fcmToken != null &&
                              order.fcmToken!.isNotEmpty) {
                            try {
                              final response = await http.post(
                                Uri.parse(_kApiNotifyCompleted),
                                headers: {'Content-Type': 'application/json'},
                                body: jsonEncode({
                                  'customerName': order.customerName,
                                  'resi': order.resi,
                                  'fcmToken': order.fcmToken,
                                }),
                              );

                              debugPrint(
                                  'Vercel Response Code: ${response.statusCode}');
                              debugPrint(
                                  'Vercel Response Body: ${response.body}');
                            } catch (e) {
                              debugPrint('API Request Error: $e');
                            }
                          } else {
                            debugPrint(
                                '⚠️ FCM Token kosong! Pesanan ini mungkin dibuat manual oleh admin.');
                          }

                          setState(() {
                            _selectedIndex = 2; // Pindah ke tab daftar order
                          });
                          if (context.mounted) Navigator.pop(context);
                          _showSnackBar(
                              'Order atas nama ${order.customerName} ditandai SUDAH DIAMBIL.');
                          setState(() => _isScanning = true);
                        },
                        icon:
                            const Icon(Icons.check_circle, color: Colors.green),
                        label: const Text(
                          'Tandai Selesai',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                    ),
                  )
                else
                  const SizedBox(
                      height:
                          16), // Jarak estetik saat state order sudah diambil
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildScanTab() {
    // Mengosongkan widget kamera saat tab tidak aktif untuk menghemat RAM dan Baterai HP
    if (_selectedIndex != 1) return const SizedBox();

    return Stack(
      children: [
        MobileScanner(
          onDetect: (capture) {
            if (!_isScanning) return;
            for (final barcode in capture.barcodes) {
              if (barcode.rawValue != null) {
                _processScannedQR(barcode.rawValue!);
                break;
              }
            }
          },
        ),
        const ScannerOverlay(),
        Positioned(
          bottom: 80,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.qr_code_scanner, color: Colors.white, size: 20),
                  SizedBox(width: 12),
                  Text(
                    'Arahkan kamera ke QR Code',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildListTab() {
    if (_orders.isEmpty) {
      return _buildEmptyOrderState();
    }

    final groupedEntries = _groupedOrders.entries.toList();

    groupedEntries.sort((a, b) {
      final allPickedUpA = a.value.every((i) => i.isPickedUp);
      final allPickedUpB = b.value.every((i) => i.isPickedUp);
      if (allPickedUpA && !allPickedUpB) return 1;
      if (!allPickedUpA && allPickedUpB) return -1;
      return a.value.first.pickupDate.compareTo(b.value.first.pickupDate);
    });

    final totalPages = (groupedEntries.length / _itemsPerPage).ceil();

    // Pengamanan batas halaman jika ada pesanan dihapus
    int displayPage = _currentPage;
    if (displayPage >= totalPages && totalPages > 0) {
      displayPage = totalPages - 1;
    } else if (totalPages == 0) {
      displayPage = 0;
    }

    final startIndex = displayPage * _itemsPerPage;
    final endIndex = (startIndex + _itemsPerPage > groupedEntries.length)
        ? groupedEntries.length
        : startIndex + _itemsPerPage;
    final paginatedEntries = groupedEntries.isEmpty
        ? <MapEntry<String, List<OrderItem>>>[]
        : groupedEntries.sublist(startIndex, endIndex);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.calendar_month_outlined,
                              color: Colors.blue.shade700, size: 24),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Filter Tanggal Order',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    InkWell(
                      onTap: _pickDateRange,
                      borderRadius: BorderRadius.circular(16),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Rentang Tanggal',
                          prefixIcon: const Icon(Icons.date_range_outlined),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        child: Text(
                          _formatRangeText(),
                          style: const TextStyle(
                              color: Colors.black87,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _QuickFilterBtn(label: 'Hari ini', onTap: _setToday),
                        _QuickFilterBtn(
                            label: 'Bulan ini', onTap: _setThisMonth),
                        _QuickFilterBtn(label: '7 Hari', onTap: _setLast7Days),
                        _QuickFilterBtn(label: 'Semua', onTap: _clearFilter),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _SummaryCard(
                      title: 'Customer',
                      value: '$_totalCustomerCount',
                      icon: Icons.group,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SummaryCard(
                      title: 'Total Order',
                      value: '$_totalOrderCount',
                      icon: Icons.receipt_long,
                      color: Colors.brown.shade300,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _SummaryCard(
                        title: 'Total Bobot',
                        value: '${_totalOrderedWeight.toStringAsFixed(1)} kg',
                        icon: Icons.inventory_2,
                        color: Colors.deepOrange.shade300),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SummaryCard(
                      title: 'Sisa Pesanan',
                      value: '${_remainingWeight.toStringAsFixed(1)} kg',
                      icon: Icons.pending_actions,
                      color: Colors.orange,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),
              const Text(
                'Daftar Pesanan',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _searchController,
                onChanged: (value) => setState(() {
                  _searchQuery = value;
                  _currentPage = 0;
                }),
                decoration: InputDecoration(
                  hintText: 'Cari nama pembeli...',
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: Colors.deepOrange.shade300),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (groupedEntries.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Text(
                    'Belum ada order pada rentang tanggal yang dipilih.',
                    textAlign: TextAlign.center,
                  ),
                )
              else ...[
                Column(
                  children: paginatedEntries.map((entry) {
                    final customerName = entry.key;
                    final items = entry.value;
                    final allPickedUp = items.every((i) => i.isPickedUp);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color:
                            allPickedUp ? Colors.green.shade50 : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                        border: allPickedUp
                            ? Border.all(color: Colors.green.shade400)
                            : null,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  customerName,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: allPickedUp
                                      ? Colors.green.shade100
                                      : Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      allPickedUp
                                          ? Icons.check_circle_outline
                                          : Icons.inventory_2_outlined,
                                      size: 16,
                                      color: allPickedUp
                                          ? Colors.green.shade700
                                          : Colors.red.shade700,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Sisa : ${_getRemainingWeightPerCustomer(items).toStringAsFixed(1)} kg',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: allPickedUp
                                            ? Colors.green.shade800
                                            : Colors.red.shade800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ...items.asMap().entries.map((itemEntry) {
                            final index = itemEntry.key;
                            final item = itemEntry.value;
                            final isPickedUp = item.isPickedUp;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (index > 0)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                    child: Divider(
                                        height: 1, color: Colors.black12),
                                  ),
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () => _showOrderDetails(item),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 4, horizontal: 4),
                                      child: Column(
                                        children: [
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                'Pesan: ${_dateFormat.format(item.orderDate)}',
                                                style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.black54),
                                              ),
                                              Row(
                                                children: [
                                                  if (item.notes != null &&
                                                      item.notes!.isNotEmpty)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                              right: 8.0),
                                                      child: Icon(Icons.notes,
                                                          size: 18,
                                                          color: Colors
                                                              .deepOrange
                                                              .shade300),
                                                    ),
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 10,
                                                        vertical: 6),
                                                    decoration: BoxDecoration(
                                                      color: isPickedUp
                                                          ? Colors
                                                              .green.shade100
                                                          : Colors.deepOrange
                                                              .shade50,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                    ),
                                                    child: Row(
                                                      children: [
                                                        Icon(
                                                          Icons.event_available,
                                                          size: 16,
                                                          color: isPickedUp
                                                              ? Colors.green
                                                                  .shade700
                                                              : Colors
                                                                  .deepOrange
                                                                  .shade700,
                                                        ),
                                                        const SizedBox(
                                                            width: 6),
                                                        Text(
                                                          'Ambil: ${_dateFormat.format(item.pickupDate)}',
                                                          style: TextStyle(
                                                            fontSize: 13,
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            color: isPickedUp
                                                                ? Colors.green
                                                                    .shade800
                                                                : Colors
                                                                    .deepOrange
                                                                    .shade800,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 16),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                      item.hasItems
                                                          ? 'Jumlah Item'
                                                          : 'Bobot Pesanan',
                                                      style: const TextStyle(
                                                          fontSize: 12,
                                                          color:
                                                              Colors.black54)),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    item.hasItems
                                                        ? '${item.weightKg.toInt()} item'
                                                        : '${item.weightKg.toStringAsFixed(2)} kg',
                                                    style: const TextStyle(
                                                        fontSize: 18,
                                                        fontWeight:
                                                            FontWeight.bold),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  child:
                                      Divider(height: 1, color: Colors.black12),
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: InkWell(
                                        onTap: () async {
                                          final newStatus = !item.isPickedUp;
                                          // Update toggle di Firestore
                                          await FirebaseFirestore.instance
                                              .collection(_kCollectionOrders)
                                              .doc(item.id)
                                              .update(
                                                  {'isPickedUp': newStatus});

                                          // Kirim notifikasi jika status diubah menjadi "Sudah Diambil"
                                          if (newStatus) {
                                            if (item.fcmToken != null &&
                                                item.fcmToken!.isNotEmpty) {
                                              try {
                                                final response =
                                                    await http.post(
                                                  Uri.parse(
                                                      _kApiNotifyCompleted),
                                                  headers: {
                                                    'Content-Type':
                                                        'application/json'
                                                  },
                                                  body: jsonEncode({
                                                    'customerName':
                                                        item.customerName,
                                                    'resi': item.resi,
                                                    'fcmToken': item.fcmToken,
                                                  }),
                                                );

                                                debugPrint(
                                                    'Vercel Response Code: ${response.statusCode}');
                                                debugPrint(
                                                    'Vercel Response Body: ${response.body}');
                                              } catch (e) {
                                                debugPrint(
                                                    'API Request Error: $e');
                                              }
                                            } else {
                                              debugPrint(
                                                  '⚠️ FCM Token kosong! Pesanan ini mungkin dibuat manual oleh admin.');
                                            }
                                          }
                                        },
                                        borderRadius: BorderRadius.circular(8),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 10),
                                          decoration: BoxDecoration(
                                            color: isPickedUp
                                                ? Colors.green
                                                : Colors.white,
                                            border: Border.all(
                                              color: isPickedUp
                                                  ? Colors.green
                                                  : Colors.red.shade300,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                isPickedUp
                                                    ? Icons.check_circle
                                                    : Icons
                                                        .inventory_2_outlined,
                                                size: 18,
                                                color: isPickedUp
                                                    ? Colors.white
                                                    : Colors.red,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                isPickedUp
                                                    ? 'Sudah Diambil'
                                                    : 'Belum Diambil',
                                                style: TextStyle(
                                                  color: isPickedUp
                                                      ? Colors.white
                                                      : Colors.red,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: const Icon(Icons.qr_code_2,
                                          color: Colors.black),
                                      onPressed: () => _showQrCode(item),
                                      tooltip: 'Tampilkan QR Code',
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined,
                                          color: Colors.blue),
                                      onPressed: () => _editOrder(item),
                                      tooltip: 'Edit',
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          color: Colors.red),
                                      onPressed: () => _deleteOrder(item),
                                      tooltip: 'Hapus',
                                    ),
                                  ],
                                ),
                              ],
                            );
                          }),
                        ],
                      ),
                    );
                  }).toList(),
                ),
                if (totalPages > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: IconButton(
                            onPressed: displayPage > 0
                                ? () => setState(
                                    () => _currentPage = displayPage - 1)
                                : null,
                            icon: const Icon(Icons.chevron_left),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          'Halaman ${displayPage + 1} dari $totalPages',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade800),
                        ),
                        const SizedBox(width: 16),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: IconButton(
                            onPressed: displayPage < totalPages - 1
                                ? () => setState(
                                    () => _currentPage = displayPage + 1)
                                : null,
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomBottomNav() {
    return Container(
      padding: const EdgeInsets.only(bottom: 12, top: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _CustomBottomNavItem(
              index: 0,
              selectedIndex: _selectedIndex,
              icon: Icons.add_shopping_cart_outlined,
              activeIcon: Icons.add_shopping_cart,
              label: 'Input Order',
              onTap: _onNavItemTapped,
            ),
            _CustomBottomNavItem(
              index: 1,
              selectedIndex: _selectedIndex,
              icon: Icons.qr_code_scanner_outlined,
              activeIcon: Icons.qr_code_scanner,
              label: 'Scan QR',
              onTap: _onNavItemTapped,
            ),
            _CustomBottomNavItem(
              index: 2,
              selectedIndex: _selectedIndex,
              icon: Icons.list_alt_outlined,
              activeIcon: Icons.list_alt,
              label: 'Daftar Order',
              onTap: _onNavItemTapped,
            ),
          ],
        ),
      ),
    );
  }

  void _onNavItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
      if (index == 1) _isScanning = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shadowColor: Colors.black.withOpacity(0.06),
        elevation: 8,
        title: const Text(
          'Pesan Keranjang',
          style:
              TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange),
        ),
        centerTitle: true,
        actions: [
          // Tombol lonceng hanya muncul jika ada reminder
          if (_upcomingOrders.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 4.0),
              child: Badge(
                label: Text(_upcomingOrders.length.toString()),
                child: IconButton(
                  tooltip: 'Lihat Pengingat',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            ReminderPage(upcomingOrders: _upcomingOrders),
                      ),
                    );
                  },
                  icon: const Icon(Icons.notifications_active),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Import Excel',
            onPressed: _importXlsx,
            icon: const Icon(Icons.upload_file),
          ),
          IconButton(
            tooltip: 'Download Excel',
            onPressed: _downloadXlsx,
            icon: const Icon(Icons.download),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildInputTab(),
          _buildScanTab(), // Menu Kamera
          _buildListTab(),
        ],
      ),
      bottomNavigationBar: _buildCustomBottomNav(),
    );
  }
}

class ScannerOverlay extends StatefulWidget {
  const ScannerOverlay({super.key});

  @override
  State<ScannerOverlay> createState() => _ScannerOverlayState();
}

class _ScannerOverlayState extends State<ScannerOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    // Animasi diperlambat sedikit agar lebih smooth
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const double scanAreaSize = 280.0;

    return Stack(
      children: [
        // Overlay gelap dengan area transparan (cutout) di tengah
        SizedBox.expand(
          child: CustomPaint(
            painter: ScannerOverlayPainter(scanAreaSize: scanAreaSize),
          ),
        ),
        // Bingkai Scanner (Gaya bracket/sudut) dan Garis Laser Animasi
        Center(
          child: SizedBox(
            width: scanAreaSize,
            height: scanAreaSize,
            child: Stack(
              children: [
                // Sudut/bingkai scanner
                CustomPaint(
                  size: const Size(scanAreaSize, scanAreaSize),
                  painter: ScannerBorderPainter(),
                ),
                // Laser Line Animasi
                AnimatedBuilder(
                  animation: _animationController,
                  builder: (context, child) {
                    // Animasi bergerak naik turun dengan efek easing bawaan
                    final curvedValue = Curves.easeInOutSine
                        .transform(_animationController.value);
                    final topOffset = 20.0;
                    final bottomOffset = 20.0;
                    final range = scanAreaSize - topOffset - bottomOffset;
                    final currentY = topOffset + (curvedValue * range);

                    return Positioned(
                      top: currentY,
                      left: 16,
                      right: 16,
                      child: Container(
                        height: 3,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.deepOrange.withOpacity(0.8),
                              blurRadius: 12,
                              spreadRadius: 3,
                            ),
                            BoxShadow(
                              color: Colors.deepOrange.withOpacity(0.4),
                              blurRadius: 24,
                              spreadRadius: 6,
                            ),
                          ],
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class ScannerBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.deepOrange
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const double cornerLength = 40.0;
    const double radius = 20.0;

    final path = Path();

    // Kiri Atas
    path.moveTo(0, cornerLength);
    path.lineTo(0, radius);
    path.quadraticBezierTo(0, 0, radius, 0);
    path.lineTo(cornerLength, 0);

    // Kanan Atas
    path.moveTo(size.width - cornerLength, 0);
    path.lineTo(size.width - radius, 0);
    path.quadraticBezierTo(size.width, 0, size.width, radius);
    path.lineTo(size.width, cornerLength);

    // Kiri Bawah
    path.moveTo(0, size.height - cornerLength);
    path.lineTo(0, size.height - radius);
    path.quadraticBezierTo(0, size.height, radius, size.height);
    path.lineTo(cornerLength, size.height);

    // Kanan Bawah
    path.moveTo(size.width - cornerLength, size.height);
    path.lineTo(size.width - radius, size.height);
    path.quadraticBezierTo(
        size.width, size.height, size.width, size.height - radius);
    path.lineTo(size.width, size.height - cornerLength);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ScannerOverlayPainter extends CustomPainter {
  final double scanAreaSize;

  ScannerOverlayPainter({required this.scanAreaSize});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.65); // Lebih gelap agar fokus

    final cutoutRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: scanAreaSize,
      height: scanAreaSize,
    );

    // PathFillType.evenOdd melubangi area yang tumpang tindih
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(
          RRect.fromRectAndRadius(cutoutRect, const Radius.circular(20)));

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ReminderPage extends StatelessWidget {
  final List<OrderItem> upcomingOrders;

  const ReminderPage({super.key, required this.upcomingOrders});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateFormat = DateFormat('dd MMMM yyyy', 'id_ID');

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shadowColor: Colors.black.withOpacity(0.06),
        elevation: 8,
        foregroundColor: Colors.black87,
        title: const Text(
          'Pengingat Pesanan',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: upcomingOrders.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Icon(Icons.notifications_active_outlined,
                          size: 64, color: Colors.grey.shade400),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Belum Ada Pengingat',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Tidak ada jadwal pengambilan pesanan untuk hari ini atau besok.',
                      style: TextStyle(
                          fontSize: 15,
                          color: Colors.grey.shade500,
                          height: 1.4),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(
                  left: 16, right: 16, top: 16, bottom: 80),
              itemCount: upcomingOrders.length,
              itemBuilder: (context, index) {
                final o = upcomingOrders[index];
                final isToday = DateTime(
                        o.pickupDate.year, o.pickupDate.month, o.pickupDate.day)
                    .isAtSameMomentAs(today);
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                    border: Border.all(
                      color: isToday
                          ? Colors.red.shade100
                          : Colors.orange.shade100,
                      width: 1.5,
                    ),
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: isToday
                                  ? Colors.red.shade50
                                  : Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isToday
                                      ? Icons.warning_rounded
                                      : Icons.schedule_rounded,
                                  color: isToday
                                      ? Colors.red.shade600
                                      : Colors.orange.shade600,
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  isToday ? 'Hari Ini' : 'Besok',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: isToday
                                        ? Colors.red.shade700
                                        : Colors.orange.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            dateFormat.format(o.pickupDate),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        o.customerName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.scale_rounded,
                                color: Colors.grey.shade500, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              o.hasItems ? 'Jumlah Item' : 'Bobot Pesanan',
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              o.hasItems
                                  ? '${o.weightKg.toInt()} item'
                                  : '${o.weightKg.toStringAsFixed(1)} kg',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
