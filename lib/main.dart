import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:excel/excel.dart' as excel;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID', null);
  runApp(const KueCinaApp());
}

class KueCinaApp extends StatelessWidget {
  const KueCinaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Order Kue Cina',
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
  @override
  void initState() {
    super.initState();
    _navigateToHome();
  }

  Future<void> _navigateToHome() async {
    // Simulasi proses loading / inisialisasi selama 2 detik
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    
    // Berpindah ke OrderPage sekaligus menghapus SplashScreen dari back-history
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const OrderPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F3), // Sesuai warna latar aplikasi
      body: Center(
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
    );
  }
}

class OrderItem {
  String customerName;
  DateTime orderDate;
  DateTime pickupDate;
  double weightKg;
  bool isPickedUp;

  OrderItem({
    required this.customerName,
    required this.orderDate,
    required this.pickupDate,
    required this.weightKg,
    required this.isPickedUp,
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
    };
  }

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      customerName: json['customerName'] ?? '',
      orderDate: DateTime.parse(json['orderDate']),
      pickupDate: DateTime.parse(json['pickupDate']),
      weightKg: (json['weightKg'] as num).toDouble(),
      isPickedUp: json['isPickedUp'] ?? false,
    );
  }
}

class OrderPage extends StatefulWidget {
  const OrderPage({super.key});

  @override
  State<OrderPage> createState() => _OrderPageState();
}

class _OrderPageState extends State<OrderPage> {
  static const String _ordersStorageKey = 'saved_orders';

  int _selectedIndex = 0;

  final TextEditingController _customerController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();

  DateTime? _filterStartDate;
  DateTime? _filterEndDate;

  DateTime? _orderDate;
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
    _setThisMonth();
    _loadOrders();
  }

  @override
  void dispose() {
    _customerController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  Future<void> _saveOrders() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = _orders.map((item) => item.toJson()).toList();
    await prefs.setString(_ordersStorageKey, jsonEncode(jsonList));
  }

  Future<void> _loadOrders() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_ordersStorageKey);

    if (raw == null || raw.isEmpty) return;

    try {
      final List<dynamic> decoded = jsonDecode(raw);
      final loadedOrders = decoded
          .map((item) => OrderItem.fromJson(Map<String, dynamic>.from(item)))
          .toList();

      if (!mounted) return;
      setState(() {
        _orders
          ..clear()
          ..addAll(loadedOrders);
      });

      // Jalankan pengecekan reminder setelah frame selesai dirender
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkReminders();
      });
    } catch (e) {
      debugPrint('Gagal load orders: $e');
    }
  }

  void _checkReminders() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    final upcomingOrders = _orders.where((o) {
      if (o.isPickedUp) return false; // Abaikan yang sudah diambil
      final pickup = DateTime(
          o.pickupDate.year, o.pickupDate.month, o.pickupDate.day);
      return pickup == today || pickup == tomorrow;
    }).toList();

    if (upcomingOrders.isEmpty) return; // Jika tidak ada order hari ini/besok, lewati

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.notifications_active, color: Colors.orange),
              SizedBox(width: 8),
              Text('Pengingat Pesanan!'),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: upcomingOrders.map((o) {
                  final isToday = DateTime(o.pickupDate.year,
                          o.pickupDate.month, o.pickupDate.day) ==
                      today;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      isToday ? Icons.warning : Icons.schedule,
                      color: isToday ? Colors.red : Colors.orange,
                    ),
                    title: Text(
                      o.customerName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                        isToday ? 'Jadwal Ambil: HARI INI' : 'Jadwal Ambil: BESOK'),
                    trailing: Text(
                      '${o.weightKg} kg',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tutup'),
            ),
          ],
        );
      },
    );
  }

  List<OrderItem> get _filteredOrders {
    return _orders.where((order) {
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
      entry.value.sort((a, b) => a.orderDate.compareTo(b.orderDate));
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
                            borderRadius: BorderRadius.circular(12),
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Dari',
                                prefixIcon: Icon(Icons.date_range),
                              ),
                              child: Text(_dateFormat.format(tempStart)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: pickEndDate,
                            borderRadius: BorderRadius.circular(12),
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Sampai',
                                prefixIcon: Icon(Icons.event),
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
    });
  }

  void _setThisMonth() {
    final now = DateTime.now();
    setState(() {
      _filterStartDate = DateTime(now.year, now.month, 1);
      _filterEndDate = DateTime(now.year, now.month + 1, 0);
    });
  }

  void _setLast7Days() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _filterEndDate = today;
      _filterStartDate = today.subtract(const Duration(days: 6));
    });
  }

  void _clearFilter() => setState(() {
        _filterStartDate = null;
        _filterEndDate = null;
      });

  Future<void> _pickOrderDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _orderDate ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
      helpText: 'Tanggal masuk',
    );
    if (picked != null) {
      setState(() {
        _orderDate = picked;
      });
    }
  }

  Future<void> _pickPickupDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _pickupDate ?? _orderDate ?? DateTime.now(),
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
        _orderDate == null ||
        _pickupDate == null ||
        weightKg == null ||
        weightKg <= 0) {
      _showSnackBar(
        'Lengkapi nama pembeli, tanggal order, tanggal ambil, dan bobot kue.',
      );
      return;
    }

    setState(() {
      _orders.add(
        OrderItem(
          customerName: customerName,
          orderDate: _orderDate!,
          pickupDate: _pickupDate!,
          weightKg: weightKg,
          isPickedUp: false,
        ),
      );
      _customerController.clear();
      _weightController.clear();
      _orderDate = null;
      _pickupDate = null;
      _selectedIndex = 1;
    });

    await _saveOrders();
    _showSnackBar('Order berhasil ditambahkan.');
  }

  Future<void> _editOrder(OrderItem item) async {
    final customerController = TextEditingController(text: item.customerName);
    final weightController =
        TextEditingController(text: item.weightKg.toStringAsFixed(2));
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
                        decoration: const InputDecoration(
                          labelText: 'Nama pembeli',
                          prefixIcon: Icon(Icons.person),
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
                        borderRadius: BorderRadius.circular(12),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Tanggal order masuk',
                            prefixIcon: Icon(Icons.edit_calendar),
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
                        borderRadius: BorderRadius.circular(12),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Tanggal diambil pembeli',
                            prefixIcon: Icon(Icons.event_available),
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
                        decoration: const InputDecoration(
                          labelText: 'Bobot kue cina (kg)',
                          prefixIcon: Icon(Icons.scale),
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
                    setState(() {
                      item.customerName = updatedName;
                      item.orderDate = selectedOrderDate;
                      item.pickupDate = selectedPickupDate;
                      item.weightKg = updatedWeight;
                      item.isPickedUp = selectedPickedUp;
                    });
                    await _saveOrders();
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
    setState(() => _orders.remove(item));
    await _saveOrders();
    _showSnackBar('Order berhasil dihapus.');
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

      setState(() {
        _orders.clear();
        _orders.addAll(importedOrders);
      });

      await _saveOrders();
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
      }

      final encoded = workbook.encode();
      if (encoded == null || encoded.isEmpty) {
        throw Exception('Gagal membuat file XLSX.');
      }

      final fileBytes = Uint8List.fromList(encoded);

      Directory? directory;
      if (Platform.isAndroid) {
        directory = await getExternalStorageDirectory();
      } else if (Platform.isIOS) {
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
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Input Order Baru',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Harga kue cina: ${_currencyFormat.format(45000)} / kg',
                    style: const TextStyle(fontSize: 15),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _customerController,
                    decoration: const InputDecoration(
                      labelText: 'Nama pembeli',
                      prefixIcon: Icon(Icons.person),
                    ),
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: _pickOrderDate,
                    borderRadius: BorderRadius.circular(12),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Tanggal order masuk',
                        prefixIcon: Icon(Icons.edit_calendar),
                      ),
                      child: Text(
                        _formatDateOrPlaceholder(_orderDate, 'Pilih tanggal'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: _pickPickupDate,
                    borderRadius: BorderRadius.circular(12),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Tanggal diambil pembeli',
                        prefixIcon: Icon(Icons.event_available),
                      ),
                      child: Text(
                        _formatDateOrPlaceholder(_pickupDate, 'Pilih tanggal'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _weightController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Bobot kue cina (kg)',
                      prefixIcon: Icon(Icons.scale),
                      hintText: 'Contoh: 1 atau 2.5',
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton.icon(
                      onPressed: _addOrder,
                      icon: const Icon(Icons.add),
                      label: const Text(
                        'Simpan Order',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
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

  Widget _buildListTab() {
    if (_orders.isEmpty) {
      return _buildEmptyOrderState();
    }

    final groupedEntries = _groupedOrders.entries.toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Filter Tanggal Order',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: _pickDateRange,
                        borderRadius: BorderRadius.circular(12),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Rentang tanggal',
                            prefixIcon: Icon(Icons.date_range),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          child: Text(_formatRangeText()),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: _setToday,
                            child: const Text('Hari ini'),
                          ),
                          OutlinedButton(
                            onPressed: _setThisMonth,
                            child: const Text('Bulan ini'),
                          ),
                          OutlinedButton(
                            onPressed: _setLast7Days,
                            child: const Text('7 hari'),
                          ),
                          OutlinedButton(
                            onPressed: _clearFilter,
                            child: const Text('Semua'),
                          ),
                        ],
                      ),
                    ],
                  ),
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
              const SizedBox(height: 20),
              const Text(
                'Daftar Pesanan',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
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
                Column(
                  children: groupedEntries.map((entry) {
                    final customerName = entry.key;
                    final items = entry.value;
                    final totalWeight = _getTotalWeightPerCustomer(items);
                    final remainingWeight = _getRemainingWeightPerCustomer(items);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
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
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${totalWeight.toStringAsFixed(1)} kg (Tersisa: ${remainingWeight.toStringAsFixed(1)})',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orange.shade900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 24),
                            ...items.map((item) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.black12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'Masuk: ${_dateFormat.format(item.orderDate)}',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: Colors.black54,
                                            ),
                                          ),
                                          Text(
                                            'Ambil: ${_dateFormat.format(item.pickupDate)}',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            '${item.weightKg.toStringAsFixed(2)} kg',
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Text(
                                            _currencyFormat.format(
                                              item.totalPrice,
                                            ),
                                            style: const TextStyle(
                                              fontSize: 16,
                                              color: Colors.green,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: InkWell(
                                              onTap: () async {
                                                setState(() {
                                                  item.isPickedUp =
                                                      !item.isPickedUp;
                                                });
                                                await _saveOrders();
                                              },
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  vertical: 8,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: item.isPickedUp
                                                      ? Colors.green.shade50
                                                      : Colors.red.shade50,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Icon(
                                                      item.isPickedUp
                                                          ? Icons.check_circle
                                                          : Icons.cancel,
                                                      size: 18,
                                                      color: item.isPickedUp
                                                          ? Colors.green
                                                          : Colors.red,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      item.isPickedUp
                                                          ? 'Selesai'
                                                          : 'Belum Diambil',
                                                      style: TextStyle(
                                                        color: item.isPickedUp
                                                            ? Colors.green
                                                            : Colors.red,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.edit,
                                              color: Colors.blue,
                                            ),
                                            onPressed: () => _editOrder(item),
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.delete,
                                              color: Colors.red,
                                            ),
                                            onPressed: () => _deleteOrder(item),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
            ],
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
        borderRadius: BorderRadius.circular(12),
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
          _buildListTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (int index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.add_shopping_cart_outlined),
            selectedIcon: Icon(Icons.add_shopping_cart),
            label: 'Input Order',
          ),
          NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            selectedIcon: Icon(Icons.list_alt),
            label: 'Daftar Order',
          ),
        ],
      ),
    );
  }
}