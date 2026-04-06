import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
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
import 'dart:ui' as ui;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart'; // File hasil generate dari flutterfire CLI
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

final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

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
        scaffoldBackgroundColor: const Color(0xFFFFF8F3),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
        cardTheme: const CardThemeData(
          elevation: 1,
        ),
        datePickerTheme: DatePickerThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent, // Menghilangkan tint warna bawaan Material 3 agar putih bersih
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24), // Lengkungan yang lebih modern
          ),
          headerBackgroundColor: Colors.white, // Header kalender putih
          headerForegroundColor: Colors.black87, // Teks judul pada header menjadi gelap
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
              content: Text('🔔 ${message.notification!.title}: ${message.notification!.body}'),
              backgroundColor: Colors.deepOrange,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      });
    }
  }

  Future<List<OrderItem>> _loadOrdersFromFirestore() async {
    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('orders').get();
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
      backgroundColor: const Color(0xFFFFF8F3), // Sesuai warna latar aplikasi
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
                child: Text(_appVersion, style: TextStyle(color: Colors.grey.shade600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OrderItem {
  String? id; // ID Dokumen dari Firestore
  String customerName;
  DateTime orderDate;
  DateTime pickupDate;
  double weightKg;
  bool isPickedUp;
  String? notes;

  OrderItem({
    this.id,
    required this.customerName,
    required this.orderDate,
    required this.pickupDate,
    required this.weightKg,
    required this.isPickedUp,
    this.notes,
  });

  double get totalPrice => weightKg * 45000;

  static String toIsoDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Map<String, dynamic> toJson() {
    return {
      'customerName': customerName,
      'orderDate': orderDate.toIso8601String(),
      'pickupDate': pickupDate.toIso8601String(),
      'weightKg': weightKg,
      'isPickedUp': isPickedUp,
      'notes': notes,
    };
  }

  factory OrderItem.fromJson(Map<String, dynamic> json, [String? docId]) {
    return OrderItem(
      id: docId,
      customerName: json['customerName'] ?? '',
      orderDate: DateTime.parse(json['orderDate']),
      pickupDate: DateTime.parse(json['pickupDate']),
      weightKg: (json['weightKg'] as num).toDouble(),
      isPickedUp: json['isPickedUp'] ?? false,
      notes: json['notes'],
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

  final TextEditingController _customerController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  DateTime? _filterStartDate;
  DateTime? _filterEndDate;

  DateTime? _pickupDate;

  final List<OrderItem> _orders = [];

  final DateFormat _dateFormat = DateFormat('dd MMM yyyy', 'id_ID');
  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp',
    decimalDigits: 0,
  );

  @override
  void initState() {
    super.initState();
    _orders.addAll(widget.initialOrders);
    _setThisMonth();

    // Mulai mendengarkan perubahan Firestore secara real-time
    _ordersSubscription = FirebaseFirestore.instance
        .collection('orders')
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
    _customerController.dispose();
    _weightController.dispose();
    _notesController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _checkReminders() {
    final upcomingOrders = _upcomingOrders;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (upcomingOrders.isEmpty) return; // Jika tidak ada order hari ini/besok, lewati

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
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
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
                                Text(
                                    isToday
                                        ? 'Ambil Hari ini'
                                        : 'Ambil Besok',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: isToday
                                            ? Colors.red.shade800
                                            : Colors.orange.shade800)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Text('${o.weightKg.toStringAsFixed(1)} kg',
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
        if (!order.customerName.toLowerCase().contains(_searchQuery.toLowerCase())) {
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
      _filteredOrders.fold(0.0, (sum, item) => sum + item.weightKg);

  double get _remainingWeight => _filteredOrders
      .where((item) => !item.isPickedUp)
      .fold(0.0, (sum, item) => sum + item.weightKg);

  double get _totalRevenue =>
      _filteredOrders.fold(0.0, (sum, item) => sum + item.totalPrice);

  int get _totalOrderCount => _filteredOrders.length;
  int get _totalCustomerCount => _groupedOrders.length;

  double _getTotalWeightPerCustomer(List<OrderItem> items) =>
      items.fold(0.0, (sum, item) => sum + item.weightKg);

  double _getRemainingWeightPerCustomer(List<OrderItem> items) => items
      .where((item) => !item.isPickedUp)
      .fold(0.0, (sum, item) => sum + item.weightKg);

  double _getTotalPricePerCustomer(List<OrderItem> items) =>
      items.fold(0.0, (sum, item) => sum + item.totalPrice);

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

            return AlertDialog(
              title: const Text('Filter Tanggal'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: pickStartDate,
                            borderRadius: BorderRadius.circular(16),
                            child: InputDecorator(
                              decoration: InputDecoration(
                                labelText: 'Dari',
                                prefixIcon: const Icon(Icons.date_range_outlined),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(color: Colors.grey.shade300),
                                ),
                              ),
                              child: Text(_dateFormat.format(tempStart)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: pickEndDate,
                            borderRadius: BorderRadius.circular(16),
                            child: InputDecorator(
                              decoration: InputDecoration(
                                labelText: 'Sampai',
                                prefixIcon: const Icon(Icons.event_outlined),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(color: Colors.grey.shade300),
                                ),
                              ),
                              child: Text(_dateFormat.format(tempEnd)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _filterStartDate = null;
                      _filterEndDate = null;
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Reset'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Batal'),
                ),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _filterStartDate = tempStart;
                      _filterEndDate = tempEnd;
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Terapkan'),
                ),
              ],
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

  Future<void> _addOrder() async {
    final customerName = _normalizeCustomerName(_customerController.text);
    final weightKg =
        double.tryParse(_weightController.text.trim().replaceAll(',', '.'));

    if (customerName.isEmpty ||
        _pickupDate == null ||
        weightKg == null ||
        weightKg <= 0) {
      _showSnackBar(
        'Lengkapi nama pembeli, tanggal ambil, dan bobot kue.',
      );
      return;
    }

    final now = DateTime.now();
    // Validasi: Tanggal Pengambilan tidak boleh sebelum hari ini
    final orderDateOnly = DateTime(now.year, now.month, now.day);
    final pickupDateOnly = DateTime(_pickupDate!.year, _pickupDate!.month, _pickupDate!.day);
    if (orderDateOnly.isAfter(pickupDateOnly)) {
      _showSnackBar('Tanggal pengambilan tidak boleh sebelum hari ini.');
      return;
    }

    final notes = _notesController.text.trim();
    final newItem = OrderItem(
      customerName: customerName,
      orderDate: now,
      pickupDate: _pickupDate!,
      weightKg: weightKg,
      isPickedUp: false,
      notes: notes.isEmpty ? null : notes,
    );

    try {
      // Simpan ke Firestore
      final docRef = await FirebaseFirestore.instance
          .collection('orders')
          .add(newItem.toJson());
      
      newItem.id = docRef.id; // Assign ID hasil generate Firestore ke model lokal

      // Panggil API Vercel untuk Broadcast Notifikasi ke Semua Admin
      try {
        final response = await http.post(
          Uri.parse('https://pesan-keranjang-backend.vercel.app/api/notify'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'customerName': newItem.customerName,
            'weightKg': newItem.weightKg,
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
        _weightController.clear();
        _notesController.clear();
        _pickupDate = null;
        _selectedIndex = 2; // Ubah ke 2 agar beralih ke 'Daftar Order' (karena tab 1 sekarang 'Scan QR')
        _currentPage = 0;
      });

      _showSnackBar('Berhasil! Order disimpan ke database Firebase.');
    } catch (e) {
      _showSnackBar('Gagal menyimpan ke database: $e');
    }
  }

  Future<void> _editOrder(OrderItem item) async {
    final customerController = TextEditingController(text: item.customerName);
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
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
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
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: Colors.grey.shade300),
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
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: Colors.grey.shade300),
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
                          labelText: 'Bobot Kue (kg)',
                          prefixIcon: const Icon(Icons.scale_outlined),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: notesController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: 'Catatan (Opsional)',
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: selectedPickedUp,
                        activeColor: Colors.green,
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
                  final editOrderOnly = DateTime(selectedOrderDate.year, selectedOrderDate.month, selectedOrderDate.day);
                  final editPickupOnly = DateTime(selectedPickupDate.year, selectedPickupDate.month, selectedPickupDate.day);
                  if (editOrderOnly.isAfter(editPickupOnly)) {
                    _showSnackBar('Tanggal pesanan tidak boleh lebih besar dari tanggal pengambilan.');
                    return;
                  }

                    final updatedNotes = notesController.text.trim();
                    // Update spesifik dokumen di Firestore
                    await FirebaseFirestore.instance
                        .collection('orders')
                        .doc(item.id)
                        .update({
                      'customerName': updatedName,
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
    await FirebaseFirestore.instance.collection('orders').doc(item.id).delete();
    
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
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(height: 12),
                const Divider(height: 1, color: Colors.black12),
                const SizedBox(height: 12),
                Text('Tgl Pengambilan: ${_dateFormat.format(item.pickupDate)}', style: const TextStyle(fontSize: 15)),
                const SizedBox(height: 8),
                Text('Bobot: ${item.weightKg.toStringAsFixed(1)} kg', style: const TextStyle(fontSize: 15)),
                const SizedBox(height: 8),
                Text(
                  'Total: ${_currencyFormat.format(item.totalPrice)}',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.green.shade700),
                ),
                if (item.notes != null && item.notes!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('Catatan:', style: TextStyle(fontSize: 14, color: Colors.black54)),
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
    final qrData = 'Nama: ${item.customerName}\n'
        'Bobot: ${item.weightKg.toStringAsFixed(1)} kg\n'
        'Total: ${_currencyFormat.format(item.totalPrice)}\n'
        'Tgl Ambil: ${_dateFormat.format(item.pickupDate)}';

    // 2. Tampilkan dalam bentuk Pop-up Dialog
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('QR Code Pesanan', textAlign: TextAlign.center),
          content: SizedBox(
            width: 320,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade300),
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
                  const SizedBox(height: 16),
                  Text(
                    item.customerName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${item.weightKg.toStringAsFixed(1)} kg • ${_currencyFormat.format(item.totalPrice)}\nAmbil: ${_dateFormat.format(item.pickupDate)}',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tutup'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context); // Tutup dialog sebelum proses print
                _printQrCode(item, qrData);
              },
              icon: const Icon(Icons.print, size: 18),
              label: const Text('Cetak'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _printQrCode(OrderItem item, String qrData) async {
    try {
      final doc = pw.Document();

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.roll80, // Menggunakan format struk kasir 80mm
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Column(
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  pw.Text(
                    'Pesan Keranjang',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16),
                  ),
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
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'Bobot: ${item.weightKg.toStringAsFixed(1)} kg',
                    style: const pw.TextStyle(fontSize: 12),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Total: ${_currencyFormat.format(item.totalPrice)}',
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
                      'Catatan: ${item.notes}',
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
      final collection = FirebaseFirestore.instance.collection('orders');

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

      _showSnackBar('Import XLSX berhasil. ${importedOrders.length} order dimuat.');
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
        'total_price',
        'notes',
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
            .value = excel.DoubleCellValue(item.weightKg);

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
            .value = excel.DoubleCellValue(item.totalPrice);
            
        sheet
            .cell(
              excel.CellIndex.indexByColumnRow(
                columnIndex: 6,
                rowIndex: dataRow,
              ),
            )
            .value = excel.TextCellValue(item.notes ?? '');
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

    final header =
        rows.first.map((cell) => _cellToString(cell).trim().toLowerCase()).toList();

    final customerIndex = header.indexOf('customer_name');
    final orderDateIndex = header.indexOf('order_date');
    final pickupDateIndex = header.indexOf('pickup_date');
    final weightIndex = header.indexOf('weight_kg');
    final pickedIndex = header.indexOf('is_picked_up');
    final notesIndex = header.indexOf('notes');

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

      final customerName = _normalizeCustomerName(_readCell(row, customerIndex));
      final orderDate = _parseFlexibleDate(_readCell(row, orderDateIndex));
      final pickupDate = _parseFlexibleDate(_readCell(row, pickupDateIndex));
      final weightKg = _parseFlexibleDouble(_readCell(row, weightIndex));
      final isPickedUp = _parseBool(_readCell(row, pickedIndex));
      final notesStr = notesIndex != -1 ? _readCell(row, notesIndex).trim() : '';

      if (customerName.isNotEmpty &&
          orderDate != null &&
          pickupDate != null &&
          weightKg != null) {
        result.add(
          OrderItem(
            customerName: customerName,
            orderDate: orderDate,
            pickupDate: pickupDate,
            weightKg: weightKg,
            isPickedUp: isPickedUp,
            notes: notesStr.isEmpty ? null : notesStr,
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 550),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
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
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.deepOrange.shade50,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.add_shopping_cart, color: Colors.deepOrange, size: 28),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Input Order Baru',
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Tambahkan data pesanan pelanggan',
                            style: TextStyle(fontSize: 14, color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                      const SizedBox(width: 12),
                      Text(
                        'Harga saat ini: ${_currencyFormat.format(45000)} / kg',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.blue.shade800),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                  TextField(
                    controller: _customerController,
                    decoration: InputDecoration(
                      labelText: 'Nama Pembeli',
                      hintText: 'Masukkan nama pelanggan',
                      prefixIcon: const Icon(Icons.person_outline),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: _pickPickupDate,
                    borderRadius: BorderRadius.circular(16),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Tgl Pengambilan',
                        prefixIcon: const Icon(Icons.event_available),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                      child: Text(
                        _formatDateOrPlaceholder(_pickupDate, 'Pilih tanggal'),
                        style: TextStyle(color: _pickupDate == null ? Colors.black54 : Colors.black87),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _weightController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Bobot Kue (kg)',
                      hintText: 'Contoh: 1 atau 2.5',
                      prefixIcon: const Icon(Icons.scale_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _notesController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Catatan (Opsional)',
                      hintText: 'Contoh: Kemasan dipisah, boks warna merah, dll.',
                      alignLabelWithHint: true,
                      prefixIcon: const Padding(
                        padding: EdgeInsets.only(bottom: 24),
                        child: Icon(Icons.notes),
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        backgroundColor: Colors.deepOrange,
                        elevation: 2,
                      ),
                      onPressed: _addOrder,
                      icon: const Icon(Icons.save_alt, size: 24),
                      label: const Text(
                        'Simpan Order',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
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
      // Mencari pola Nama dan Bobot dari teks QR yang di-generate sebelumnya
      final nameMatch = RegExp(r'Nama:\s*(.*?)\n').firstMatch(qrData);
      final weightMatch = RegExp(r'Bobot:\s*([\d\.]+)\s*kg').firstMatch(qrData);

      if (nameMatch != null && weightMatch != null) {
        final parsedName = nameMatch.group(1)?.trim();
        final parsedWeightStr = weightMatch.group(1)?.trim();

        if (parsedName != null && parsedWeightStr != null) {
          // Cari pesanan yang persis cocok
          final matchingOrders = _orders.where((o) =>
              o.customerName.toLowerCase() == parsedName.toLowerCase() &&
              o.weightKg.toStringAsFixed(1) == parsedWeightStr
          ).toList();

          if (matchingOrders.isNotEmpty) {
            // Prioritaskan membuka pesanan yang berstatus "Belum Diambil"
            matchingOrders.sort((a, b) => a.isPickedUp ? 1 : -1);
            final targetOrder = matchingOrders.first;

            _showScannedOrderDialog(targetOrder);
            return;
          }
        }
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
        return AlertDialog(
          title: const Text('Pesanan Ditemukan!', textAlign: TextAlign.center),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.green, size: 64),
              const SizedBox(height: 16),
              Text(
                order.customerName,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Column(
                  children: [
                    Text('Bobot: ${order.weightKg.toStringAsFixed(1)} kg', style: const TextStyle(fontSize: 15)),
                    const SizedBox(height: 4),
                    Text('Total: ${_currencyFormat.format(order.totalPrice)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 4),
                    Text('Tgl Ambil: ${_dateFormat.format(order.pickupDate)}', style: const TextStyle(fontSize: 15)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (order.isPickedUp)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                  child: const Text('Status: SUDAH DIAMBIL', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                  child: const Text('Status: BELUM DIAMBIL', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                setState(() => _isScanning = true); // Lanjut mode scan
              },
              child: const Text('Tutup'),
            ),
            if (!order.isPickedUp)
              FilledButton.icon(
                onPressed: () async {
                  // Update ke Firestore
                  await FirebaseFirestore.instance
                      .collection('orders')
                      .doc(order.id)
                      .update({'isPickedUp': true});

                  setState(() {
                    _selectedIndex = 2; // Pindah ke tab daftar order
                  });
                  if (context.mounted) Navigator.pop(context);
                  _showSnackBar('Order atas nama ${order.customerName} ditandai SUDAH DIAMBIL.');
                  setState(() => _isScanning = true);
                },
                icon: const Icon(Icons.check),
                label: const Text('Tandai Selesai'),
              ),
          ],
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
        Center(
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.deepOrange, width: 4),
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        ),
        Positioned(
          bottom: 80,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Arahkan kamera ke QR Code Pesanan',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
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
    final endIndex = (startIndex + _itemsPerPage > groupedEntries.length) ? groupedEntries.length : startIndex + _itemsPerPage;
    final paginatedEntries = groupedEntries.isEmpty ? <MapEntry<String, List<OrderItem>>>[] : groupedEntries.sublist(startIndex, endIndex);

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
                      color: Colors.black.withOpacity(0.04),
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
                          child: Icon(Icons.calendar_month_outlined, color: Colors.blue.shade700, size: 24),
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
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
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
                          style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildQuickFilterBtn('Hari ini', _setToday),
                        _buildQuickFilterBtn('Bulan ini', _setThisMonth),
                        _buildQuickFilterBtn('7 Hari', _setLast7Days),
                        _buildQuickFilterBtn('Semua', _clearFilter),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _summaryCard(
                      title: 'Customer',
                      value: '$_totalCustomerCount',
                      icon: Icons.group,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _summaryCard(
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
                    child: _summaryCard(
                      title: 'Total Bobot',
                      value: '${_totalOrderedWeight.toStringAsFixed(1)} kg',
                      icon: Icons.inventory_2,
                      color : Colors.deepOrange.shade300
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _summaryCard(
                      title: 'Sisa Pesanan',
                      value: '${_remainingWeight.toStringAsFixed(1)} kg',
                      icon: Icons.pending_actions,
                      color: Colors.orange,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _summaryCard(
                title: 'Estimasi Pendapatan',
                value: _currencyFormat.format(_totalRevenue),
                icon: Icons.payments,
                color: Colors.green,
                fullWidth: true,
              ),
              const SizedBox(height: 40),
              const Text(
                'Daftar Pesanan',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
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
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                    border: Border.all(color: Colors.black12),
                  ),
                  child: const Text(
                    'Belum ada order pada rentang tanggal yang dipilih.',
                    textAlign: TextAlign.center,
                  ),
                )
              else
              ...[
                Column(
                  children: paginatedEntries.map((entry) {
                    final customerName = entry.key;
                    final items = entry.value;
                    final allPickedUp = items.every((i) => i.isPickedUp);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: allPickedUp ? Colors.green.shade50 : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: allPickedUp ? Colors.green.shade400 : Colors.grey.shade300,
                        ),
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
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: allPickedUp ? Colors.green.shade100 : Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  allPickedUp ? Icons.check_circle_outline : Icons.inventory_2_outlined,
                                  size: 16,
                                  color: allPickedUp ? Colors.green.shade700 : Colors.red.shade700,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Sisa : ${_getRemainingWeightPerCustomer(items).toStringAsFixed(1)} Kg',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: allPickedUp ? Colors.green.shade800 : Colors.red.shade800,
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
                                child: Divider(height: 1, color: Colors.black12),
                              ),
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () => _showOrderDetails(item),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                                    child: Column(
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              'Pesan: ${_dateFormat.format(item.orderDate)}',
                                              style: const TextStyle(fontSize: 12, color: Colors.black54),
                                            ),
                                            Row(
                                              children: [
                                                if (item.notes != null && item.notes!.isNotEmpty)
                                                  Padding(
                                                    padding: const EdgeInsets.only(right: 8.0),
                                                    child: Icon(Icons.notes, size: 18, color: Colors.deepOrange.shade300),
                                                  ),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                  decoration: BoxDecoration(
                                                    color: isPickedUp ? Colors.green.shade100 : Colors.deepOrange.shade50,
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        Icons.event_available,
                                                        size: 16,
                                                        color: isPickedUp ? Colors.green.shade700 : Colors.deepOrange.shade700,
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Text(
                                                        'Ambil: ${_dateFormat.format(item.pickupDate)}',
                                                        style: TextStyle(
                                                          fontSize: 13,
                                                          fontWeight: FontWeight.w800,
                                                          color: isPickedUp ? Colors.green.shade800 : Colors.deepOrange.shade800,
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
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const Text('Bobot Pesanan', style: TextStyle(fontSize: 12, color: Colors.black54)),
                                                const SizedBox(height: 2),
                                                Text(
                                                  '${item.weightKg.toStringAsFixed(2)} kg',
                                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                                ),
                                              ],
                                            ),
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.end,
                                              children: [
                                                const Text('Total Harga', style: TextStyle(fontSize: 12, color: Colors.black54)),
                                                const SizedBox(height: 2),
                                                Text(
                                                  _currencyFormat.format(item.totalPrice),
                                                  style: TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.w900,
                                                    color: Colors.green.shade700,
                                                  ),
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
                              child: Divider(height: 1, color: Colors.black12),
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap: () async {
                                      // Update toggle di Firestore
                                      await FirebaseFirestore.instance
                                          .collection('orders')
                                          .doc(item.id)
                                          .update({'isPickedUp': !item.isPickedUp});
                                    },
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      decoration: BoxDecoration(
                                        color: isPickedUp ? Colors.green : Colors.white,
                                        border: Border.all(
                                          color: isPickedUp ? Colors.green : Colors.red.shade300,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            isPickedUp ? Icons.check_circle : Icons.inventory_2_outlined,
                                            size: 18,
                                            color: isPickedUp ? Colors.white : Colors.red,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            isPickedUp ? 'Sudah Diambil' : 'Belum Diambil',
                                            style: TextStyle(
                                              color: isPickedUp ? Colors.white : Colors.red,
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
                                  icon: const Icon(Icons.qr_code_2, color: Colors.black),
                                  onPressed: () => _showQrCode(item),
                                  tooltip: 'Tampilkan QR Code',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined, color: Colors.blue),
                                  onPressed: () => _editOrder(item),
                                  tooltip: 'Edit',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                  onPressed: () => _deleteOrder(item),
                                  tooltip: 'Hapus',
                                ),
                              ],
                            ),
                          ],
                        );
                      }).toList(),
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
                            onPressed: displayPage > 0 ? () => setState(() => _currentPage = displayPage - 1) : null,
                            icon: const Icon(Icons.chevron_left),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          'Halaman ${displayPage + 1} dari $totalPages',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade800),
                        ),
                        const SizedBox(width: 16),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: IconButton(
                            onPressed: displayPage < totalPages - 1 ? () => setState(() => _currentPage = displayPage + 1) : null,
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

  Widget _buildQuickFilterBtn(String label, VoidCallback onTap) {
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

  Widget _summaryCard({
    required String title,
    required String value,
    required IconData icon,
    Color? color,
    bool fullWidth = false,
  }) {
    return Card(
      elevation: 0,
      color: color?.withOpacity(0.1) ?? Colors.blue.withOpacity(0.1),
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: color?.withOpacity(0.3) ?? Colors.blue.withOpacity(0.3),
        ),
        borderRadius: BorderRadius.circular(16),
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

  Widget _buildCustomBottomNav() {
    return Container(
      padding: const EdgeInsets.only(bottom: 12, top: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _buildNavItem(0, Icons.add_shopping_cart_outlined, Icons.add_shopping_cart, 'Input Order'),
            _buildCenterNavItem(1, Icons.qr_code_scanner_outlined, Icons.qr_code_scanner, 'Scan QR'),
            _buildNavItem(2, Icons.list_alt_outlined, Icons.list_alt, 'Daftar Order'),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, IconData activeIcon, String label) {
    final isSelected = _selectedIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedIndex = index;
            if (index == 1) _isScanning = true;
          });
        },
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? Colors.deepOrange.shade50 : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                isSelected ? activeIcon : icon,
                color: isSelected ? Colors.deepOrange : Colors.grey.shade400,
                size: 26,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.deepOrange : Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterNavItem(int index, IconData icon, IconData activeIcon, String label) {
    final isSelected = _selectedIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedIndex = index;
            if (index == 1) _isScanning = true;
          });
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.deepOrange,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.deepOrange.withOpacity(isSelected ? 0.4 : 0.2),
                    blurRadius: isSelected ? 12 : 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                isSelected ? activeIcon : icon,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.deepOrange : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Pesan Keranjang',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange),
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

class ReminderPage extends StatelessWidget {
  final List<OrderItem> upcomingOrders;

  const ReminderPage({super.key, required this.upcomingOrders});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateFormat = DateFormat('dd MMMM yyyy', 'id_ID');

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F3), // Match app's background
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
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
                    Text(
                      'Belum Ada Pengingat',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Tidak ada jadwal pengambilan pesanan untuk hari ini atau besok.',
                      style: TextStyle(fontSize: 15, color: Colors.grey.shade500, height: 1.4),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 80),
              itemCount: upcomingOrders.length,
              itemBuilder: (context, index) {
                final o = upcomingOrders[index];
                final isToday = DateTime(o.pickupDate.year, o.pickupDate.month,
                        o.pickupDate.day)
                    .isAtSameMomentAs(today);
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                    border: Border.all(
                      color: isToday ? Colors.red.shade100 : Colors.orange.shade100,
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
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: isToday ? Colors.red.shade50 : Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isToday ? Icons.warning_rounded : Icons.schedule_rounded,
                                  color: isToday ? Colors.red.shade600 : Colors.orange.shade600,
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  isToday ? 'Hari Ini' : 'Besok',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: isToday ? Colors.red.shade700 : Colors.orange.shade700,
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
                            Icon(Icons.scale_rounded, color: Colors.grey.shade500, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Bobot Pesanan',
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${o.weightKg.toStringAsFixed(1)} kg',
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