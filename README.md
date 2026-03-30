<<<<<<< HEAD
# Kue Cina Order App

Aplikasi Flutter Web sederhana untuk mencatat orderan kue cina.

## Fitur
- Pilih bulan pesanan
- Input nama pembeli
- Input tanggal order masuk
- Input tanggal diambil
- Input bobot kue cina (kg)
- Status sudah diambil / belum diambil
- Rekap total bobot order bulan terpilih
- Rekap total bobot yang belum diambil
- Harga default kue cina 1 kg = Rp45.000
- Hitung total harga per order otomatis

## Cara menjalankan di VS Code

### Opsi 1: Sudah punya project Flutter
1. Buka project Flutter kamu di VS Code.
2. Ganti isi `lib/main.dart` dengan file dari bundle ini.
3. Tambahkan dependency `intl` pada `pubspec.yaml`.
4. Jalankan:
   ```bash
   flutter pub get
   flutter run -d chrome
   ```

### Opsi 2: Mulai dari folder ini
Karena file platform Flutter biasanya digenerate oleh Flutter CLI, jalankan ini sekali di folder project:

```bash
flutter create . --platforms=web
flutter pub get
flutter run -d chrome
```

Kalau `flutter create .` menimpa `lib/main.dart`, cukup paste lagi isi file `lib/main.dart` dari bundle ini.
=======
# PesanKeranjang
Sebuah aplikasi untuk memudahkan pencatatan orderan kue keranjang, dilengkapi dengan filter tanggal, list orderan yang masuk, cek status serta upload dan download catatan yang sudah pernah dibuat ke dalam format XLSX
>>>>>>> 39f62ac81823a9a940784f8fb23e0ad72a0b797b
