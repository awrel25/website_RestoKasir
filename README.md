# Website Pemesanan Menu & QRIS Pelanggan (RestoKasir)

Folder ini memisahkan file web pelanggan (pemesanan mandiri dari meja dan konfirmasi QRIS kamera) dari kode aplikasi kasir Flutter.

## Struktur File di `customer_web/`

| File | Deskripsi |
| :--- | :--- |
| `index.html` | Antarmuka web pemesanan menu digital (Putih / Hitam + Orange / Kuning). |
| `style.css` | Desain token warna Orange, Kuning, Putih, serta mode Hitam tanpa gradien berlebihan. |
| `app.js` | Logika keranjang belanja, pencarian menu, filter kategori, sinkronisasi nomor meja, dan koneksi REST API ke Supabase. |
| `menu.html` | Versi bundel file tunggal (`HTML + CSS + JS`) untuk host publik di Supabase Storage saat pelanggan scan QR meja. |
| `pay.html` | Halaman konfirmasi pembayaran QRIS via kamera ponsel yang memperbarui status pesanan di aplikasi kasir. |
| `README.md` | Dokumentasi alur kerja pemesanan web meja dan pembayaran QRIS. |

## Alur Kerja Sistem

### 1. Pemesanan Mandiri via Scan Barcode Meja
1. Kasir atau admin mencetak stiker QR Code Meja dari aplikasi kasir (`table_qr_dialog.dart`).
2. Pelanggan duduk di meja dan scan QR Code dengan kamera ponsel.
3. Halaman menu meja terbuka (`menu.html?table=1&resto=RESTO_ID`).
4. Pelanggan memilih menu, melihat stok terkini, mengisi nomor meja, nama pemesan, dan catatan tambahan.
5. Pelanggan memilih metode bayar:
   - **Bayar di Kasir**: Pesanan masuk ke aplikasi kasir (`status: pesanan dibuat`).
   - **QRIS Instan**: Membayar langsung via QRIS dari ponsel.
6. Setelah mengirim pesanan, website menampilkan nomor meja dan mengarahkan pelanggan untuk menyebutkan nomor meja ke kasir agar dicek dan diproses di aplikasi kasir.

### 2. Pembayaran QRIS Scan Kamera (`pay.html`)
1. Ketika kasir memilih pembayaran QRIS pada dialog pembayaran di aplikasi kasir, layar menampilkan QR Code.
2. Pembayar memindai QR Code dengan kamera ponsel untuk membuka `pay.html`.
3. Saat tombol konfirmasi pembayaran ditekan, `pay.html` memperbarui status order di Supabase menjadi `pesanan selesai`.
4. Aplikasi kasir Flutter mendeteksi pembaruan status secara otomatis dan membuka tampilan cetak struk.

## Link Publik (Supabase Storage)
- **Menu Digital Meja**: `https://uinumtttwkwlurvqvidh.supabase.co/storage/v1/object/public/product-images/menu.html`
- **Konfirmasi QRIS Kamera**: `https://uinumtttwkwlurvqvidh.supabase.co/storage/v1/object/public/product-images/pay.html`
