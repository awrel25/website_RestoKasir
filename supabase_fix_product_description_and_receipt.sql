-- ============================================================================
-- SQL PERBAIKAN: PENYIMPANAN DESKRIPSI PRODUK & SINKRONISASI REALTIME RESTOKASIR
-- ============================================================================
-- Petunjuk:
-- 1. Buka dashboard Supabase Anda: https://supabase.com/dashboard/project/uinumtttwkwlurvqvidh
-- 2. Pilih menu "SQL Editor" pada sidebar sebelah kiri.
-- 3. Buat New Query, paste seluruh isi skrip ini, lalu klik "RUN".
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Tambahkan kolom 'description' ke tabel 'products'
-- ----------------------------------------------------------------------------
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS description text;

-- Tambahkan komentar dokumentasi kolom
COMMENT ON COLUMN public.products.description IS 'Deskripsi lengkap menu makanan/minuman yang tersinkronisasi ke website customer';

-- ----------------------------------------------------------------------------
-- 2. Pastikan tabel 'products' dan 'orders' terdaftar pada Supabase Realtime
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.products;
  EXCEPTION WHEN duplicate_object THEN
    NULL;
  END;

  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.orders;
  EXCEPTION WHEN duplicate_object THEN
    NULL;
  END;
END $$;

-- ----------------------------------------------------------------------------
-- 3. Berikan deskripsi awal yang menggugah selera untuk produk yang sudah ada
-- (Hanya mengisi produk yang saat ini deskripsinya masih kosong / NULL)
-- ----------------------------------------------------------------------------
UPDATE public.products
SET description = CASE
  WHEN name ILIKE '%pancake%' THEN 'Pancake lembut bertabur buah berry segar pilihan, disajikan hangat dengan siraman sirup maple manis alami.'
  WHEN name ILIKE '%nasi padang%' OR name ILIKE '%padang%' THEN 'Paket nasi padang komplit dengan lauk ikan nila goreng renyah, kuah gulai kaya rempah, sambal hijau khas, dan daun singkong rebus.'
  WHEN name ILIKE '%kopi es%' OR name ILIKE '%es kopi%' THEN 'Perpaduan biji kopi robusta pilihan dan susu segar creamy dengan sensasi dingin menyegarkan, cocok menemani hari Anda.'
  WHEN name ILIKE '%kopi%' THEN 'Kopi aromatik seduh segar dengan cita rasa khas nusantara yang mantap dan aroma wangi menggugah semangat.'
  WHEN name ILIKE '%nasgor%' OR name ILIKE '%nasi goreng%' THEN 'Nasi goreng spesial bumbu rempah tradisional dengan potongan ayam gurih, telur mata sapi, dan acar segar.'
  WHEN name ILIKE '%goreng%' THEN 'Camilan goreng renyah bumbu gurih lezat, disajikan hangat dan pas dinikmati bersama teman atau keluarga.'
  WHEN name ILIKE '%rica%' THEN 'Olahan usus ayam bumbu rica-rica pedas gurih menggigit, kaya rempah dan wangi daun kemangi segar.'
  WHEN name ILIKE '%nak enak enak%' THEN 'Menu istimewa racikan chef dengan perpaduan rasa gurih manis lezat yang menggugah selera makan Anda.'
  ELSE 'Hidangan istimewa racikan chef dengan bahan-bahan segar berkualitas tinggi dan bumbu rempah pilihan terbaik.'
END
WHERE description IS NULL OR btrim(description) = '';

-- ----------------------------------------------------------------------------
-- 4. Verifikasi hasil kolom dan deskripsi produk
-- ----------------------------------------------------------------------------
SELECT 
  id,
  name,
  category,
  price,
  stock,
  description
FROM public.products
ORDER BY created_at DESC;
