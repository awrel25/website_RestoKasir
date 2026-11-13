# Website Pemesanan Menu Customer (RestoKasir)

Website pemesanan mandiri berbasis QR Code meja dengan satu tema permanen yang bersih serta dua metode pembayaran (**Bayar Melalui Kasir** dan **QRIS Mode Demo**).

## Struktur File di `customer_web/`

| File | Deskripsi |
| :--- | :--- |
| `index.html` | Antarmuka pemesanan customer (identifikasi meja otomatis `?table=01`, detail menu, keranjang, checkout, serta dialog pembayaran). |
| `style.css` | Desain konsisten satu tema permanen (Oranye `#EA580C`, Putih `#FFFFFF`, Off-White `#F8F7F4`, dan Dark Accent `#171614`). |
| `app.js` | Validasi nomor meja QR, verifikasi harga server Supabase, QRIS Mode Demo (`BAYAR`), dan sinkronisasi status `UNPAID` -> `PAID` via Supabase Realtime. |
| `menu.html` | Bundel file tunggal hasil penggabungan `index.html`, `style.css`, dan `app.js`. |
| `pay.html` | Halaman konfirmasi pembayaran QRIS kamera untuk transaksi kasir. |
| `deploy-website.yml` | Konfigurasi GitHub Actions untuk deployment GitHub Pages (`https://awrel25.github.io/website_RestoKasir/`). |
