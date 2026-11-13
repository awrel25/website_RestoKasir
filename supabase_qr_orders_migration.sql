-- ============================================================================
-- Migrasi Aditif QR Table Ordering & Status Pembayaran RestoKasir
-- Aman dijalankan berulang kali (idempotent) dan TIDAK menghapus data lama.
-- ============================================================================

-- 1. Tambah kolom payment_status dan order_source pada tabel orders yang ada
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS payment_status text NOT NULL DEFAULT 'unpaid',
  ADD COLUMN IF NOT EXISTS order_source text NOT NULL DEFAULT 'pos';

-- Tambah kolom description pada tabel products untuk deskripsi makanan di website pelanggan
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS description text;

-- Sinkronisasi nilai awal untuk data order lama agar tetap konsisten
UPDATE public.orders
SET payment_status = CASE
  WHEN lower(coalesce(status, '')) IN ('pesanan selesai', 'selesai') THEN 'paid'
  ELSE 'unpaid'
END
WHERE payment_status = 'unpaid';

UPDATE public.orders
SET order_source = 'qr'
WHERE order_source = 'pos'
  AND (
    lower(coalesce(payment_method, '')) LIKE '%(meja)%'
    OR lower(coalesce(invoice_no, '')) LIKE 'web-%'
    OR lower(coalesce(cashier_name, '')) LIKE 'meja %'
  );

-- 2. Tabel daftar meja resmi per restoran untuk validasi QR Code
CREATE TABLE IF NOT EXISTS public.restaurant_tables (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  resto_id uuid NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  table_number integer NOT NULL CHECK (table_number >= 1 AND table_number <= 99),
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (resto_id, table_number)
);

ALTER TABLE public.restaurant_tables ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public read active restaurant_tables" ON public.restaurant_tables;
CREATE POLICY "Public read active restaurant_tables"
  ON public.restaurant_tables
  FOR SELECT
  TO anon, authenticated
  USING (is_active = true);

-- Isi meja default 1..20 untuk semua restoran yang sudah terdaftar (tanpa menimpa yg ada)
INSERT INTO public.restaurant_tables (resto_id, table_number, is_active)
SELECT r.id, gs.n, true
FROM public.restaurants r
CROSS JOIN generate_series(1, 20) AS gs(n)
ON CONFLICT (resto_id, table_number) DO NOTHING;

-- 3. Fungsi server-side agar harga dihitung dari database & meja divalidasi backend
CREATE OR REPLACE FUNCTION public.submit_qr_order(
  p_resto_id uuid,
  p_table_number integer,
  p_customer_name text,
  p_notes text DEFAULT '',
  p_payment_method text DEFAULT 'CASHIER',
  p_items jsonb DEFAULT '[]'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_table_valid boolean;
  v_item jsonb;
  v_prod record;
  v_qty integer;
  v_subtotal integer := 0;
  v_service_fee integer := 0;
  v_total integer := 0;
  v_invoice text;
  v_order_id uuid;
  v_created_at timestamptz;
  v_norm_method text;
  v_cashier_label text;
  v_items_summary text[] := ARRAY[]::text[];
BEGIN
  IF p_customer_name IS NULL OR btrim(p_customer_name) = '' THEN
    RAISE EXCEPTION 'Nama pemesan wajib diisi.';
  END IF;

  IF jsonb_array_length(coalesce(p_items, '[]'::jsonb)) = 0 THEN
    RAISE EXCEPTION 'Keranjang pesanan kosong.';
  END IF;

  -- Validasi nomor meja aktif di database
  SELECT EXISTS (
    SELECT 1
    FROM public.restaurant_tables rt
    WHERE rt.resto_id = p_resto_id
      AND rt.table_number = p_table_number
      AND rt.is_active = true
  ) INTO v_table_valid;

  IF NOT v_table_valid THEN
    RAISE EXCEPTION 'QR Code meja tidak valid atau meja tidak aktif.';
  END IF;

  v_norm_method := CASE
    WHEN upper(coalesce(p_payment_method, '')) = 'QRIS_DEMO' THEN 'QRIS_DEMO'
    ELSE 'CASHIER'
  END;

  -- Hitung subtotal strictly dari harga tabel products (anti manipulasi frontend)
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_qty := coalesce((v_item->>'quantity')::integer, 0);
    IF v_qty <= 0 THEN
      RAISE EXCEPTION 'Jumlah produk harus lebih dari 0.';
    END IF;

    SELECT id, name, price, stock, is_available
    INTO v_prod
    FROM public.products
    WHERE id = (v_item->>'product_id')::uuid
      AND resto_id = p_resto_id
    FOR UPDATE;

    IF NOT FOUND OR v_prod.is_available = false THEN
      RAISE EXCEPTION 'Produk tidak tersedia.';
    END IF;

    IF v_prod.stock < v_qty THEN
      RAISE EXCEPTION 'Stok % tidak mencukupi (tersisa %).', v_prod.name, v_prod.stock;
    END IF;

    v_subtotal := v_subtotal + (v_prod.price * v_qty);
    v_items_summary := array_append(v_items_summary, v_prod.name || ' x' || v_qty);
  END LOOP;

  v_service_fee := round(v_subtotal * 0.05);
  v_total := v_subtotal + v_service_fee;

  v_invoice := 'WEB-' || to_char(now(), 'YYYYMMDD') || '-' || lpad((floor(random() * 9000 + 1000))::text, 4, '0');
  v_cashier_label := 'Meja ' || lpad(p_table_number::text, 2, '0') || ' (' || btrim(p_customer_name) || ')';
  IF p_notes IS NOT NULL AND btrim(p_notes) <> '' THEN
    v_cashier_label := v_cashier_label || ' - Catatan: ' || btrim(p_notes);
  END IF;
  IF v_norm_method = 'QRIS_DEMO' THEN
    v_cashier_label := v_cashier_label || ' [QRIS DEMO]';
  END IF;

  INSERT INTO public.orders (
    invoice_no,
    resto_id,
    cashier_name,
    table_number,
    subtotal,
    service_fee,
    total,
    payment_method,
    payment_status,
    order_source,
    status
  ) VALUES (
    v_invoice,
    p_resto_id,
    v_cashier_label,
    p_table_number,
    v_subtotal,
    v_service_fee,
    v_total,
    v_norm_method,
    'unpaid',
    'qr',
    'pesanan dibuat'
  )
  RETURNING id, created_at INTO v_order_id, v_created_at;

  -- Simpan order_items dan kurangi stok
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_qty := (v_item->>'quantity')::integer;
    SELECT id, name, price, stock INTO v_prod
    FROM public.products
    WHERE id = (v_item->>'product_id')::uuid;

    INSERT INTO public.order_items (
      order_id,
      product_id,
      product_name,
      price,
      quantity,
      subtotal
    ) VALUES (
      v_order_id,
      v_prod.id,
      v_prod.name,
      v_prod.price,
      v_qty,
      v_prod.price * v_qty
    );

    UPDATE public.products
    SET stock = greatest(0, stock - v_qty),
        is_available = (greatest(0, stock - v_qty) > 0)
    WHERE id = v_prod.id;
  END LOOP;

  RETURN jsonb_build_object(
    'id', v_order_id,
    'invoice_no', v_invoice,
    'table_number', p_table_number,
    'subtotal', v_subtotal,
    'service_fee', v_service_fee,
    'total', v_total,
    'payment_method', v_norm_method,
    'payment_status', 'unpaid',
    'order_source', 'qr',
    'status', 'pesanan dibuat',
    'created_at', v_created_at,
    'items_summary', to_jsonb(v_items_summary)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.submit_qr_order(uuid, integer, text, text, text, jsonb) TO anon, authenticated;

-- 4. Fungsi konfirmasi KHUSUS simulasi QRIS DEMO (tidak pernah mengubah transaksi asli ke 'paid')
CREATE OR REPLACE FUNCTION public.confirm_demo_qris_order(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order record;
BEGIN
  SELECT id, invoice_no, table_number, total, payment_method, payment_status
  INTO v_order
  FROM public.orders
  WHERE id = p_order_id
    AND order_source = 'qr'
    AND payment_method = 'QRIS_DEMO';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order QRIS DEMO tidak ditemukan.';
  END IF;

  UPDATE public.orders
  SET payment_status = 'demo_paid'
  WHERE id = p_order_id
    AND payment_method = 'QRIS_DEMO'
    AND payment_status = 'unpaid';

  RETURN jsonb_build_object(
    'id', v_order.id,
    'invoice_no', v_order.invoice_no,
    'table_number', v_order.table_number,
    'total', v_order.total,
    'payment_status', 'demo_paid'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.confirm_demo_qris_order(uuid) TO anon, authenticated;

-- 5. Aktifkan Supabase Realtime untuk tabel orders
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'orders'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.orders;
  END IF;
END $$;

