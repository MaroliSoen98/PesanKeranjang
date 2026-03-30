import 'dart:html' as html;
import 'dart:typed_data';

import 'package:excel/excel.dart' as excel;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

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
      home: const OrderPage(),
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
}

class OrderPage extends StatefulWidget {
  const OrderPage({super.key});

  @override
  State<OrderPage> createState() => _OrderPageState();
}

class _OrderPageState extends State<OrderPage> {
  final TextEditingController _customerController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();

  DateTime? _filterStartDate;
  DateTime? _filterEndDate;

  DateTime? _orderDate;
  DateTime? _pickupDate;

  final List<OrderItem> _orders = [];

  final DateFormat _dateFormat = DateFormat('dd MMM yyyy', 'id_ID');
  final DateFormat _fileDateFormat = DateFormat('yyyyMMdd_HHmmss', 'id_ID');
  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp',
    decimalDigits: 0,
  );

  @override
  void initState() {
    super.initState();
    _setThisMonth();
  }

  @override
  void dispose() {
    _customerController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  List<OrderItem> get _filteredOrders {
    return _orders.where((order) {
      if (_filterStartDate == null || _filterEndDate == null) {
        return true;
      }

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

  double get _totalOrderedWeight {
    return _filteredOrders.fold(0.0, (sum, item) => sum + item.weightKg);
  }

  double get _remainingWeight {
    return _filteredOrders
        .where((item) => !item.isPickedUp)
        .fold(0.0, (sum, item) => sum + item.weightKg);
  }

  double get _totalRevenue {
    return _filteredOrders.fold(0.0, (sum, item) => sum + item.totalPrice);
  }

  int get _totalOrderCount {
    return _filteredOrders.length;
  }

  int get _totalCustomerCount {
    return _groupedOrders.length;
  }

  double _getTotalWeightPerCustomer(List<OrderItem> items) {
    return items.fold(0.0, (sum, item) => sum + item.weightKg);
  }

  double _getRemainingWeightPerCustomer(List<OrderItem> items) {
    return items
        .where((item) => !item.isPickedUp)
        .fold(0.0, (sum, item) => sum + item.weightKg);
  }

  double _getTotalPricePerCustomer(List<OrderItem> items) {
    return items.fold(0.0, (sum, item) => sum + item.totalPrice);
  }

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
                  if (tempEnd.isBefore(tempStart)) {
                    tempEnd = tempStart;
                  }
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
                  if (tempStart.isAfter(tempEnd)) {
                    tempStart = tempEnd;
                  }
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
                                labelText: 'Dari tanggal',
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
                                labelText: 'Sampai tanggal',
                                prefixIcon: Icon(Icons.event),
                              ),
                              child: Text(_dateFormat.format(tempEnd)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.orange.withOpacity(0.18),
                        ),
                      ),
                      child: const Text(
                        'Filter ini berlaku untuk tanggal pesan dan tanggal ambil dengan kondisi AND.',
                      ),
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
                      _filterStartDate = DateTime(
                        tempStart.year,
                        tempStart.month,
                        tempStart.day,
                      );
                      _filterEndDate = DateTime(
                        tempEnd.year,
                        tempEnd.month,
                        tempEnd.day,
                      );
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Pilih'),
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
    final today = DateTime(now.year, now.month, now.day);

    setState(() {
      _filterStartDate = today;
      _filterEndDate = today;
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

  void _clearFilter() {
    setState(() {
      _filterStartDate = null;
      _filterEndDate = null;
    });
  }

  Future<void> _pickOrderDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _orderDate ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
      helpText: 'Pilih tanggal order masuk',
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
      helpText: 'Pilih tanggal diambil pembeli',
    );

    if (picked != null) {
      setState(() {
        _pickupDate = picked;
      });
    }
  }

  void _addOrder() {
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
    });

    _showSnackBar('Order berhasil ditambahkan.');
  }

  Future<void> _editOrder(OrderItem item) async {
    final customerController = TextEditingController(text: item.customerName);
    final weightController =
        TextEditingController(text: item.weightKg.toStringAsFixed(2));

    DateTime selectedOrderDate = item.orderDate;
    DateTime selectedPickupDate = item.pickupDate;
    bool selectedPickedUp = item.isPickedUp;

    Future<void> pickEditOrderDate(StateSetter setModalState) async {
      final picked = await showDatePicker(
        context: context,
        initialDate: selectedOrderDate,
        firstDate: DateTime(2024),
        lastDate: DateTime(2035),
        helpText: 'Pilih tanggal order masuk',
      );

      if (picked != null) {
        setModalState(() {
          selectedOrderDate = picked;
        });
      }
    }

    Future<void> pickEditPickupDate(StateSetter setModalState) async {
      final picked = await showDatePicker(
        context: context,
        initialDate: selectedPickupDate,
        firstDate: DateTime(2024),
        lastDate: DateTime(2035),
        helpText: 'Pilih tanggal diambil pembeli',
      );

      if (picked != null) {
        setModalState(() {
          selectedPickupDate = picked;
        });
      }
    }

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
                        onTap: () => pickEditOrderDate(setModalState),
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
                        onTap: () => pickEditPickupDate(setModalState),
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
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
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
                        onChanged: (value) {
                          setModalState(() {
                            selectedPickedUp = value;
                          });
                        },
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
                  onPressed: () {
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

                    Navigator.pop(context);
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

    customerController.dispose();
    weightController.dispose();
  }

  void _togglePickedUp(OrderItem item, bool? value) {
    setState(() {
      item.isPickedUp = value ?? false;
    });
  }

  void _deleteOrder(OrderItem item) {
    setState(() {
      _orders.remove(item);
    });
    _showSnackBar('Order berhasil dihapus.');
  }

  Future<void> _importXlsx() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        _showSnackBar('Tidak ada file XLSX yang dipilih.');
        return;
      }

      final file = result.files.first;
      final bytes = file.bytes;

      if (bytes == null || bytes.isEmpty) {
        _showSnackBar('Gagal membaca file XLSX.');
        return;
      }

      final workbook = excel.Excel.decodeBytes(bytes);
      if (workbook.tables.isEmpty) {
        throw Exception('Sheet XLSX tidak ditemukan.');
      }

      final firstSheetName = workbook.tables.keys.first;
      final excel.Sheet sheet = workbook.tables[firstSheetName]!;

      final importedOrders = _parseOrdersFromSheet(sheet);

      setState(() {
        _orders
          ..clear()
          ..addAll(importedOrders);
      });

      _showSnackBar(
        'Import XLSX berhasil. ${importedOrders.length} order dimuat.',
      );
    } catch (e) {
      _showSnackBar('Gagal import XLSX: $e');
    }
  }

  void _downloadXlsx() {
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
            .cell(excel.CellIndex.indexByColumnRow(
              columnIndex: col,
              rowIndex: 0,
            ))
            .value = excel.TextCellValue(headers[col]);
      }

      for (int row = 0; row < _orders.length; row++) {
        final item = _orders[row];
        final dataRow = row + 1;

        sheet
            .cell(excel.CellIndex.indexByColumnRow(
              columnIndex: 0,
              rowIndex: dataRow,
            ))
            .value = excel.TextCellValue(item.customerName);

        sheet
            .cell(excel.CellIndex.indexByColumnRow(
              columnIndex: 1,
              rowIndex: dataRow,
            ))
            .value = excel.TextCellValue(OrderItem.toIsoDate(item.orderDate));

        sheet
            .cell(excel.CellIndex.indexByColumnRow(
              columnIndex: 2,
              rowIndex: dataRow,
            ))
            .value = excel.TextCellValue(OrderItem.toIsoDate(item.pickupDate));

        sheet
            .cell(excel.CellIndex.indexByColumnRow(
              columnIndex: 3,
              rowIndex: dataRow,
            ))
            .value = excel.DoubleCellValue(item.weightKg);

        sheet
            .cell(excel.CellIndex.indexByColumnRow(
              columnIndex: 4,
              rowIndex: dataRow,
            ))
            .value = excel.TextCellValue(item.isPickedUp ? 'true' : 'false');

        sheet
            .cell(excel.CellIndex.indexByColumnRow(
              columnIndex: 5,
              rowIndex: dataRow,
            ))
            .value = excel.DoubleCellValue(item.totalPrice);
      }

      final encoded = workbook.encode();
      if (encoded == null || encoded.isEmpty) {
        throw Exception('Gagal membuat file XLSX.');
      }

      final fileBytes = Uint8List.fromList(encoded);

      final blob = html.Blob(
        [fileBytes],
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      final url = html.Url.createObjectUrlFromBlob(blob);

      final anchor = html.AnchorElement(href: url)
        ..setAttribute(
          'download',
          'order_kue_cina_${_fileDateFormat.format(DateTime.now())}.xlsx',
        )
        ..click();

      html.Url.revokeObjectUrl(url);
      anchor.remove();

      _showSnackBar('XLSX berhasil didownload.');
    } catch (e) {
      _showSnackBar('Gagal download XLSX: $e');
    }
  }

  List<OrderItem> _parseOrdersFromSheet(excel.Sheet sheet) {
    final rows = sheet.rows;
    if (rows.isEmpty) {
      throw Exception('File XLSX kosong.');
    }

    final header = rows.first
        .map((cell) => _cellToString(cell).trim().toLowerCase())
        .toList();

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
      throw Exception(
        'Header XLSX tidak sesuai. Gunakan header: '
        'customer_name, order_date, pickup_date, weight_kg, is_picked_up, total_price',
      );
    }

    final result = <OrderItem>[];

    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];

      final isCompletelyEmpty = row.every(
        (cell) => _cellToString(cell).trim().isEmpty,
      );

      if (isCompletelyEmpty) {
        continue;
      }

      final customerName =
          _normalizeCustomerName(_readCell(row, customerIndex));
      final orderDate = _parseFlexibleDate(_readCell(row, orderDateIndex));
      final pickupDate = _parseFlexibleDate(_readCell(row, pickupDateIndex));
      final weightKg = _parseFlexibleDouble(_readCell(row, weightIndex));
      final isPickedUp = _parseBool(_readCell(row, pickedIndex));

      if (customerName.isEmpty ||
          orderDate == null ||
          pickupDate == null ||
          weightKg == null) {
        throw Exception('Format data tidak valid pada baris ke-${i + 1}.');
      }

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

    return result;
  }

  String _readCell(List<excel.Data?> row, int index) {
    if (index >= row.length) return '';
    return _cellToString(row[index]);
  }

  String _cellToString(excel.Data? cell) {
    if (cell == null || cell.value == null) return '';
    return cell.value.toString();
  }

  double? _parseFlexibleDouble(String value) {
    final normalized = value.trim().replaceAll(',', '.');
    return double.tryParse(normalized);
  }

  DateTime? _parseFlexibleDate(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;

    final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
    final slash = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$');

    if (iso.hasMatch(trimmed)) {
      final m = iso.firstMatch(trimmed)!;
      return DateTime(
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
      );
    }

    if (slash.hasMatch(trimmed)) {
      final m = slash.firstMatch(trimmed)!;
      return DateTime(
        int.parse(m.group(3)!),
        int.parse(m.group(2)!),
        int.parse(m.group(1)!),
      );
    }

    try {
      return DateTime.parse(trimmed);
    } catch (_) {
      return null;
    }
  }

  bool _parseBool(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'true' ||
        normalized == '1' ||
        normalized == 'yes' ||
        normalized == 'ya';
  }

  String _normalizeCustomerName(String text) {
    return text
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .map(
          (word) => word[0].toUpperCase() + word.substring(1).toLowerCase(),
        )
        .join(' ');
  }

  String _formatDateOrPlaceholder(DateTime? date, String placeholder) {
    if (date == null) return placeholder;
    return _dateFormat.format(date);
  }

  String _formatRangeText() {
    if (_filterStartDate == null || _filterEndDate == null) {
      return 'Pilih rentang tanggal';
    }
    return '${_dateFormat.format(_filterStartDate!)} - ${_dateFormat.format(_filterEndDate!)}';
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _buildStatusSection(OrderItem item) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: item.isPickedUp
            ? Colors.green.withOpacity(0.14)
            : Colors.orange.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: item.isPickedUp
              ? Colors.green.withOpacity(0.28)
              : Colors.orange.withOpacity(0.20),
        ),
        boxShadow: item.isPickedUp
            ? [
                BoxShadow(
                  color: Colors.green.withOpacity(0.10),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : [],
      ),
      child: Row(
        children: [
          AnimatedScale(
            scale: item.isPickedUp ? 1.05 : 1.0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: Checkbox(
              value: item.isPickedUp,
              activeColor: Colors.green,
              checkColor: Colors.white,
              side: BorderSide(
                color: item.isPickedUp
                    ? Colors.green
                    : Colors.grey.shade500,
                width: 1.4,
              ),
              onChanged: (value) => _togglePickedUp(item, value),
            ),
          ),
          Expanded(
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: item.isPickedUp
                    ? Colors.green.shade800
                    : Colors.black87,
              ),
              child: Text(
                item.isPickedUp ? 'Sudah diambil' : 'Belum diambil',
              ),
            ),
          ),
          IconButton(
            tooltip: 'Edit order',
            onPressed: () => _editOrder(item),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Hapus order',
            onPressed: () => _deleteOrder(item),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pencatatan Order Kue Cina'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Upload XLSX',
            onPressed: _importXlsx,
            icon: const Icon(Icons.upload_file),
          ),
          IconButton(
            tooltip: 'Download XLSX',
            onPressed: _downloadXlsx,
            icon: const Icon(Icons.download),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 1000;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: isWide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 4, child: _buildFormSection()),
                          const SizedBox(width: 16),
                          Expanded(flex: 6, child: _buildSummaryAndList()),
                        ],
                      )
                    : Column(
                        children: [
                          _buildFormSection(),
                          const SizedBox(height: 16),
                          _buildSummaryAndList(),
                        ],
                      ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFormSection() {
    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Filter Tanggal',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Filter berlaku untuk tanggal pesan dan tanggal ambil dengan kondisi AND.',
                ),
                const SizedBox(height: 20),
                InkWell(
                  onTap: _pickDateRange,
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Rentang tanggal',
                      prefixIcon: Icon(Icons.date_range),
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
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.orange.withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'XLSX',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Upload XLSX untuk memuat order, atau download XLSX untuk menyimpan data saat ini.',
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          FilledButton.icon(
                            onPressed: _importXlsx,
                            icon: const Icon(Icons.upload_file),
                            label: const Text('Upload XLSX'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _downloadXlsx,
                            icon: const Icon(Icons.download),
                            label: const Text('Download XLSX'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Input Order',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
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
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Bobot kue cina (kg)',
                    prefixIcon: Icon(Icons.scale),
                    hintText: 'Contoh: 1 atau 2.5',
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _addOrder,
                    icon: const Icon(Icons.add),
                    label: const Text('Tambah Order'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryAndList() {
    final groupedEntries = _groupedOrders.entries.toList();

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _summaryCard(
                title: 'Jumlah customer',
                value: '$_totalCustomerCount orang',
                icon: Icons.group,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _summaryCard(
                title: 'Total order',
                value: '$_totalOrderCount pesanan',
                icon: Icons.receipt_long,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _summaryCard(
                title: 'Total bobot',
                value: '${_totalOrderedWeight.toStringAsFixed(2)} kg',
                icon: Icons.inventory_2,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _summaryCard(
                title: 'Belum diambil',
                value: '${_remainingWeight.toStringAsFixed(2)} kg',
                icon: Icons.pending_actions,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _summaryCard(
          title: 'Total keseluruhan pesanan',
          value: _currencyFormat.format(_totalRevenue),
          icon: Icons.payments,
          fullWidth: true,
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Daftar Order',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text('Periode filter: ${_formatRangeText()}'),
                const SizedBox(height: 16),
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
                      final remainingWeight =
                          _getRemainingWeightPerCustomer(items);
                      final totalPrice = _getTotalPricePerCustomer(items);

                      return Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.black12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
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
                                const SizedBox(width: 12),
                                Align(
                                  alignment: Alignment.topRight,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.black12),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          'Total bobot: ${totalWeight.toStringAsFixed(2)} kg',
                                          textAlign: TextAlign.right,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Belum diambil: ${remainingWeight.toStringAsFixed(2)} kg',
                                          textAlign: TextAlign.right,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Total harga: ${_currencyFormat.format(totalPrice)}',
                                          textAlign: TextAlign.right,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Column(
                              children: items.map((item) {
                                return Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.black12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Tanggal order: ${_dateFormat.format(item.orderDate)}',
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Tanggal ambil: ${_dateFormat.format(item.pickupDate)}',
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Bobot: ${item.weightKg.toStringAsFixed(2)} kg',
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Harga: ${_currencyFormat.format(item.totalPrice)}',
                                      ),
                                      const SizedBox(height: 10),
                                      _buildStatusSection(item),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _summaryCard({
    required String title,
    required String value,
    required IconData icon,
    bool fullWidth = false,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              child: Icon(icon),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: fullWidth ? 15 : 14,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: fullWidth ? 22 : 20,
                      fontWeight: FontWeight.bold,
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