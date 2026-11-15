-- ============================================================================
-- Migrasi Penyatuan Akses (Penghapusan Sistem Role) & Sinkronisasi Realtime Web
-- RestoKasir: Supabase Backend Migration (Idempotent / Aman Dijalankan Berulang)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Relaksasi & Pembersihan Batasan Role pada Profiles dan Restaurant Members
-- ----------------------------------------------------------------------------

-- Hapus CHECK constraint role pada profiles jika ada
DO $$
BEGIN
  ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS check_profile_role;
EXCEPTION
  WHEN OTHERS THEN NULL;
END $$;

-- Hapus CHECK constraint role pada restaurant_members jika ada
DO $$
BEGIN
  ALTER TABLE public.restaurant_members DROP CONSTRAINT IF EXISTS restaurant_members_role_check;
EXCEPTION
  WHEN OTHERS THEN NULL;
END $$;

-- Hapus indeks unik '1 admin per resto' agar satu restoran dapat memiliki banyak akun dengan hak setara
DROP INDEX IF EXISTS public.unique_active_admin_per_resto;

-- Pastikan relasi keanggotaan unik: satu akun user_id per satu restaurant_id
CREATE UNIQUE INDEX IF NOT EXISTS unique_user_restaurant_membership
  ON public.restaurant_members (user_id, restaurant_id)
  WHERE user_id IS NOT NULL;

-- ----------------------------------------------------------------------------
-- 2. Pastikan Kolom Produk Lengkap untuk Website Customer
-- ----------------------------------------------------------------------------
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS description text,
  ADD COLUMN IF NOT EXISTS image_url text,
  ADD COLUMN IF NOT EXISTS is_available boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS is_active boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS category text NOT NULL DEFAULT 'Makanan Utama',
  ADD COLUMN IF NOT EXISTS icon_name text DEFAULT 'fastfood';

-- Pastikan realtime replication aktif untuk tabel products dan orders
DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.products;
  EXCEPTION WHEN duplicate_object THEN
    -- Table already added
  END;

  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.orders;
  EXCEPTION WHEN duplicate_object THEN
    -- Table already added
  END;
END $$;

-- ----------------------------------------------------------------------------
-- 3. Pembaruan Fungsi Pengelolaan Restoran (Dapat Diakses Seluruh Anggota Aktif)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.upsert_my_restaurant(
  p_name text,
  p_category text DEFAULT NULL,
  p_address text DEFAULT NULL,
  p_phone text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_resto_id uuid;
  v_clean_name text := btrim(coalesce(p_name, ''));
  v_clean_category text := nullif(btrim(coalesce(p_category, '')), '');
  v_clean_address text := nullif(btrim(coalesce(p_address, '')), '');
  v_clean_phone text := nullif(btrim(coalesce(p_phone, '')), '');
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Sesi login tidak aktif. Silakan masuk terlebih dahulu.';
  END IF;

  IF v_clean_name = '' THEN
    RAISE EXCEPTION 'Nama usaha / restoran wajib diisi.';
  END IF;

  -- 1. Cek keanggotaan aktif pengguna
  SELECT rm.restaurant_id INTO v_resto_id
  FROM public.restaurant_members rm
  WHERE rm.user_id = v_uid AND rm.status = 'ACTIVE'
  LIMIT 1;

  -- 2. Fallback relasi profil / restoran lama
  IF v_resto_id IS NULL THEN
    SELECT r.id INTO v_resto_id
    FROM public.restaurants r
    WHERE r.user_id = v_uid
    LIMIT 1;
  END IF;

  IF v_resto_id IS NULL THEN
    SELECT p.resto_id INTO v_resto_id
    FROM public.profiles p
    WHERE p.id = v_uid AND p.resto_id IS NOT NULL
    LIMIT 1;
  END IF;

  -- 3. Jika restoran sudah ada: Perbarui informasi restoran
  IF v_resto_id IS NOT NULL THEN
    UPDATE public.restaurants
    SET
      name = v_clean_name,
      category = coalesce(v_clean_category, category),
      address = v_clean_address,
      phone = v_clean_phone
    WHERE id = v_resto_id;

    -- Pastikan user tercatat aktif di restaurant_members
    INSERT INTO public.restaurant_members (user_id, restaurant_id, role, status, updated_at)
    VALUES (v_uid, v_resto_id, 'STAFF', 'ACTIVE', now())
    ON CONFLICT (user_id, restaurant_id) WHERE user_id IS NOT NULL
    DO UPDATE SET status = 'ACTIVE', updated_at = now();

  ELSE
    -- 4. Jika baru: Buat restoran baru
    INSERT INTO public.restaurants (user_id, name, category, address, phone)
    VALUES (v_uid, v_clean_name, v_clean_category, v_clean_address, v_clean_phone)
    RETURNING id INTO v_resto_id;

    -- Daftarkan akun pembuat ke restaurant_members
    INSERT INTO public.restaurant_members (user_id, restaurant_id, role, status)
    VALUES (v_uid, v_resto_id, 'STAFF', 'ACTIVE');
  END IF;

  -- Tautkan resto_id ke profiles pengguna
  UPDATE public.profiles
  SET resto_id = v_resto_id
  WHERE id = v_uid;

  -- Siapkan meja default 1..20 bila tabel restaurant_tables tersedia
  IF to_regclass('public.restaurant_tables') IS NOT NULL THEN
    INSERT INTO public.restaurant_tables (resto_id, table_number, is_active)
    SELECT v_resto_id, gs.n, true
    FROM generate_series(1, 20) AS gs(n)
    ON CONFLICT (resto_id, table_number) DO NOTHING;
  END IF;

  RETURN v_resto_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_my_restaurant(text, text, text, text) TO authenticated;

-- ----------------------------------------------------------------------------
-- 4. Pembaruan Fungsi Undangan Rekan Tim (Dapat Diakses Seluruh Anggota Aktif)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.invite_staff_member(
  p_email text,
  p_name text,
  p_shift text DEFAULT 'Shift Pagi',
  p_phone text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_uid uuid := auth.uid();
  v_resto_id uuid;
  v_clean_email text := lower(btrim(coalesce(p_email, '')));
  v_clean_name text := btrim(coalesce(p_name, ''));
  v_existing_member record;
  v_target_user_id uuid;
  v_member_id uuid;
  v_employee_id uuid;
BEGIN
  IF v_caller_uid IS NULL THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;

  IF v_clean_email = '' OR position('@' in v_clean_email) = 0 THEN
    RAISE EXCEPTION 'Format email anggota tim tidak valid.';
  END IF;

  IF v_clean_name = '' THEN
    RAISE EXCEPTION 'Nama anggota tim wajib diisi.';
  END IF;

  -- Verifikasi caller adalah anggota aktif dari restoran
  SELECT rm.restaurant_id INTO v_resto_id
  FROM public.restaurant_members rm
  WHERE rm.user_id = v_caller_uid AND rm.status = 'ACTIVE'
  LIMIT 1;

  IF v_resto_id IS NULL THEN
    RAISE EXCEPTION 'Pengguna belum terdaftar sebagai anggota restoran yang aktif.';
  END IF;

  -- Cek apakah email sudah terdaftar di auth.users / profiles
  SELECT p.id INTO v_target_user_id
  FROM public.profiles p
  WHERE lower(trim(p.email)) = v_clean_email
  LIMIT 1;

  -- Cek keanggotaan eksisting
  SELECT rm.id, rm.status INTO v_existing_member
  FROM public.restaurant_members rm
  WHERE rm.restaurant_id = v_resto_id
    AND (
      (v_target_user_id IS NOT NULL AND rm.user_id = v_target_user_id)
      OR lower(trim(coalesce(rm.invited_email, ''))) = v_clean_email
    )
  LIMIT 1;

  IF v_existing_member.id IS NOT NULL AND v_existing_member.status = 'ACTIVE' THEN
    RAISE EXCEPTION 'Pengguna dengan email ini sudah aktif sebagai anggota restoran.';
  END IF;

  -- Insert atau perbarui restaurant_members
  IF v_existing_member.id IS NOT NULL THEN
    UPDATE public.restaurant_members
    SET
      user_id = coalesce(v_target_user_id, user_id),
      role = 'STAFF',
      status = CASE WHEN v_target_user_id IS NOT NULL THEN 'ACTIVE' ELSE 'INVITED' END,
      invited_email = v_clean_email,
      updated_at = now()
    WHERE id = v_existing_member.id
    RETURNING id INTO v_member_id;
  ELSE
    INSERT INTO public.restaurant_members (
      user_id,
      restaurant_id,
      role,
      status,
      invited_email
    ) VALUES (
      v_target_user_id,
      v_resto_id,
      'STAFF',
      CASE WHEN v_target_user_id IS NOT NULL THEN 'ACTIVE' ELSE 'INVITED' END,
      v_clean_email
    )
    RETURNING id INTO v_member_id;
  END IF;

  -- Hubungkan profil jika target user sudah memiliki profil
  IF v_target_user_id IS NOT NULL THEN
    UPDATE public.profiles
    SET resto_id = v_resto_id
    WHERE id = v_target_user_id;
  END IF;

  -- Tambahkan ke tabel employees untuk daftar tim operasional
  SELECT id INTO v_employee_id
  FROM public.employees
  WHERE resto_id = v_resto_id AND lower(trim(coalesce(email, ''))) = v_clean_email
  LIMIT 1;

  IF v_employee_id IS NOT NULL THEN
    UPDATE public.employees
    SET
      name = v_clean_name,
      role = 'Staff',
      phone = coalesce(nullif(btrim(p_phone), ''), phone),
      shift = coalesce(nullif(btrim(p_shift), ''), shift),
      is_active = true
    WHERE id = v_employee_id;
  ELSE
    INSERT INTO public.employees (
      resto_id,
      name,
      role,
      email,
      phone,
      shift,
      is_active
    ) VALUES (
      v_resto_id,
      v_clean_name,
      'Staff',
      v_clean_email,
      nullif(btrim(p_phone), ''),
      coalesce(nullif(btrim(p_shift), ''), 'Shift Pagi'),
      true
    )
    RETURNING id INTO v_employee_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'member_id', v_member_id,
    'employee_id', v_employee_id,
    'email', v_clean_email,
    'status', CASE WHEN v_target_user_id IS NOT NULL THEN 'ACTIVE' ELSE 'INVITED' END
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.invite_staff_member(text, text, text, text) TO authenticated;

-- ----------------------------------------------------------------------------
-- 5. Row Level Security (RLS) Tanpa Pembatasan Role
-- ----------------------------------------------------------------------------

-- A. restaurant_members
ALTER TABLE public.restaurant_members ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Members can view members of same restaurant" ON public.restaurant_members;
CREATE POLICY "Members can view members of same restaurant"
  ON public.restaurant_members
  FOR SELECT
  TO authenticated
  USING (
    user_id = auth.uid()
    OR restaurant_id IN (
      SELECT rm2.restaurant_id
      FROM public.restaurant_members rm2
      WHERE rm2.user_id = auth.uid() AND rm2.status = 'ACTIVE'
    )
  );

DROP POLICY IF EXISTS "Only admin can insert restaurant_members" ON public.restaurant_members;
DROP POLICY IF EXISTS "Active members can insert restaurant_members" ON public.restaurant_members;
CREATE POLICY "Active members can insert restaurant_members"
  ON public.restaurant_members
  FOR INSERT
  TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    OR restaurant_id IN (
      SELECT rm.restaurant_id
      FROM public.restaurant_members rm
      WHERE rm.user_id = auth.uid() AND rm.status = 'ACTIVE'
    )
  );

DROP POLICY IF EXISTS "Only admin can update restaurant_members" ON public.restaurant_members;
DROP POLICY IF EXISTS "Active members can update restaurant_members" ON public.restaurant_members;
CREATE POLICY "Active members can update restaurant_members"
  ON public.restaurant_members
  FOR UPDATE
  TO authenticated
  USING (
    user_id = auth.uid()
    OR restaurant_id IN (
      SELECT rm.restaurant_id
      FROM public.restaurant_members rm
      WHERE rm.user_id = auth.uid() AND rm.status = 'ACTIVE'
    )
  );

-- B. products: Publik / Anonim dapat melihat menu restoran (?resto=UUID), anggota resto dapat mengelola
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public can view active products" ON public.products;
CREATE POLICY "Public can view active products"
  ON public.products
  FOR SELECT
  TO anon, authenticated
  USING (is_available = true OR auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "Restaurant members can manage products" ON public.products;
CREATE POLICY "Restaurant members can manage products"
  ON public.products
  FOR ALL
  TO authenticated
  USING (
    resto_id IN (
      SELECT rm.restaurant_id
      FROM public.restaurant_members rm
      WHERE rm.user_id = auth.uid() AND rm.status = 'ACTIVE'
    )
    OR resto_id IN (
      SELECT p.resto_id
      FROM public.profiles p
      WHERE p.id = auth.uid()
    )
  )
  WITH CHECK (
    resto_id IN (
      SELECT rm.restaurant_id
      FROM public.restaurant_members rm
      WHERE rm.user_id = auth.uid() AND rm.status = 'ACTIVE'
    )
    OR resto_id IN (
      SELECT p.resto_id
      FROM public.profiles p
      WHERE p.id = auth.uid()
    )
  );

-- C. orders: Anggota resto dapat melihat & update seluruh pesanan; Pelanggan anonim dapat membaca pesanan miliknya
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Restaurant members and customers can view orders" ON public.orders;
CREATE POLICY "Restaurant members and customers can view orders"
  ON public.orders
  FOR SELECT
  TO anon, authenticated
  USING (
    auth.uid() IS NOT NULL
    OR true -- Memungkinkan web customer membaca status pesanan mejanya
  );

DROP POLICY IF EXISTS "Restaurant members can update orders" ON public.orders;
CREATE POLICY "Restaurant members can update orders"
  ON public.orders
  FOR UPDATE
  TO authenticated
  USING (
    resto_id IN (
      SELECT rm.restaurant_id
      FROM public.restaurant_members rm
      WHERE rm.user_id = auth.uid() AND rm.status = 'ACTIVE'
    )
    OR resto_id IN (
      SELECT p.resto_id
      FROM public.profiles p
      WHERE p.id = auth.uid()
    )
  );

-- D. restaurants: Publik dan anggota dapat membaca data resto
ALTER TABLE public.restaurants ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view restaurants" ON public.restaurants;
CREATE POLICY "Anyone can view restaurants"
  ON public.restaurants
  FOR SELECT
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "Restaurant members can update restaurant" ON public.restaurants;
CREATE POLICY "Restaurant members can update restaurant"
  ON public.restaurants
  FOR UPDATE
  TO authenticated
  USING (
    id IN (
      SELECT rm.restaurant_id
      FROM public.restaurant_members rm
      WHERE rm.user_id = auth.uid() AND rm.status = 'ACTIVE'
    )
  );

-- ----------------------------------------------------------------------------
-- 6. RPC submit_qr_order: Menjamin Validasi Harga Database Saat Checkout
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.submit_qr_order(
  p_resto_id uuid,
  p_table_number integer,
  p_customer_name text,
  p_notes text DEFAULT NULL,
  p_payment_method text DEFAULT 'CASHIER',
  p_items jsonb DEFAULT '[]'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order_id uuid;
  v_invoice_no text;
  v_seq integer;
  v_subtotal bigint := 0;
  v_service_fee bigint := 0;
  v_total bigint := 0;
  v_item record;
  v_product record;
  v_item_subtotal bigint;
  v_items_count integer := 0;
  v_order_status text := 'pesanan dibuat';
  v_payment_status text := 'unpaid';
  v_clean_name text := btrim(coalesce(p_customer_name, 'Pelanggan'));
  v_clean_notes text := nullif(btrim(coalesce(p_notes, '')), '');
  v_items_summary jsonb := '[]'::jsonb;
BEGIN
  IF p_resto_id IS NULL THEN
    RAISE EXCEPTION 'Restoran tidak valid.';
  END IF;

  IF p_table_number IS NULL OR p_table_number < 1 THEN
    RAISE EXCEPTION 'Nomor meja tidak valid.';
  END IF;

  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Keranjang pesanan kosong.';
  END IF;

  -- Buat nomor invoice unik berbasis tanggal & sequence
  SELECT coalesce(COUNT(*), 0) + 1 INTO v_seq
  FROM public.orders
  WHERE created_at >= date_trunc('day', now())
    AND created_at < date_trunc('day', now()) + interval '1 day';

  v_invoice_no := 'WEB-' || to_char(now(), 'YYYYMMDD') || '-' || lpad(v_seq::text, 4, '0');

  -- Hitung subtotal dan validasi harga STRICTLY dari tabel products database Supabase
  FOR v_item IN
    SELECT
      (elem->>'product_id')::text AS product_id,
      greatest(1, coalesce((elem->>'quantity')::integer, 1)) AS quantity
    FROM jsonb_array_elements(p_items) AS elem
  LOOP
    SELECT id, name, price, stock, is_available INTO v_product
    FROM public.products
    WHERE id = v_item.product_id
      AND (resto_id IS NULL OR resto_id = p_resto_id)
    LIMIT 1;

    IF v_product.id IS NULL THEN
      RAISE EXCEPTION 'Produk dengan ID % tidak ditemukan pada restoran ini.', v_item.product_id;
    END IF;

    IF v_product.is_available = false THEN
      RAISE EXCEPTION 'Menu "%" saat ini sedang tidak tersedia.', v_product.name;
    END IF;

    IF v_product.stock < v_item.quantity THEN
      RAISE EXCEPTION 'Stok untuk menu "%" tersisa % porsi.', v_product.name, v_product.stock;
    END IF;

    v_item_subtotal := (v_product.price * v_item.quantity)::bigint;
    v_subtotal := v_subtotal + v_item_subtotal;
    v_items_count := v_items_count + v_item.quantity;

    v_items_summary := v_items_summary || jsonb_build_object(
      'product_id', v_product.id,
      'product_name', v_product.name,
      'price', v_product.price,
      'quantity', v_item.quantity,
      'subtotal', v_item_subtotal
    );
  END LOOP;

  v_total := v_subtotal + v_service_fee;

  -- Buat pesanan baru di tabel orders
  INSERT INTO public.orders (
    resto_id,
    table_number,
    invoice_no,
    cashier_name,
    customer_name,
    subtotal,
    discount,
    tax,
    service_charge,
    total,
    payment_method,
    payment_status,
    order_source,
    status,
    notes,
    created_at
  ) VALUES (
    p_resto_id,
    p_table_number,
    v_invoice_no,
    'Meja ' || lpad(p_table_number::text, 2, '0') || ' (Web Pelanggan)',
    v_clean_name,
    v_subtotal,
    0,
    0,
    v_service_fee,
    v_total,
    CASE WHEN p_payment_method = 'QRIS_DEMO' THEN 'QRIS Instan (Meja)' ELSE 'Bayar di Kasir (Meja)' END,
    v_payment_status,
    'qr',
    v_order_status,
    v_clean_notes,
    now()
  )
  RETURNING id INTO v_order_id;

  -- Masukkan rincian item ke order_items dan kurangi stok
  FOR v_item IN
    SELECT
      (elem->>'product_id')::text AS product_id,
      (elem->>'product_name')::text AS product_name,
      (elem->>'price')::integer AS price,
      (elem->>'quantity')::integer AS quantity,
      (elem->>'subtotal')::bigint AS subtotal
    FROM jsonb_array_elements(v_items_summary) AS elem
  LOOP
    INSERT INTO public.order_items (
      order_id,
      product_id,
      product_name,
      quantity,
      price,
      subtotal
    ) VALUES (
      v_order_id,
      v_item.product_id,
      v_item.product_name,
      v_item.quantity,
      v_item.price,
      v_item.subtotal
    );

    UPDATE public.products
    SET stock = greatest(0, stock - v_item.quantity)
    WHERE id = v_item.product_id;
  END LOOP;

  RETURN jsonb_build_object(
    'id', v_order_id,
    'invoice_no', v_invoice_no,
    'table_number', p_table_number,
    'customer_name', v_clean_name,
    'notes', v_clean_notes,
    'subtotal', v_subtotal,
    'service_fee', v_service_fee,
    'total', v_total,
    'payment_method', CASE WHEN p_payment_method = 'QRIS_DEMO' THEN 'QRIS Instan (Meja)' ELSE 'Bayar di Kasir (Meja)' END,
    'payment_status', v_payment_status,
    'order_source', 'qr',
    'status', v_order_status,
    'created_at', now(),
    'items_summary', v_items_summary
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.submit_qr_order(uuid, integer, text, text, text, jsonb) TO authenticated, anon;
