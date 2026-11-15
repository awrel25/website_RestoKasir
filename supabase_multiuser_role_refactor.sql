-- ============================================================================
-- Migrasi Refaktor Sistem Role & Multi-User RestoKasir (ADMIN & KASIR)
-- Aman dijalankan berulang kali (idempotent) dan mempertahankan seluruh data lama.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Penyesuaian Kolom & Pembersihan Role OWNER pada profiles
-- ----------------------------------------------------------------------------
-- Ubah seluruh pengguna dengan role 'owner' menjadi 'admin'
UPDATE public.profiles
SET role = 'admin'
WHERE lower(coalesce(role, '')) = 'owner';

-- Pastikan hanya ada 2 role valid: 'admin' dan 'kasir'
UPDATE public.profiles
SET role = 'kasir'
WHERE lower(coalesce(role, '')) NOT IN ('admin', 'kasir');

-- Perbarui / tambahkan CHECK constraint pada public.profiles untuk role
DO $$
BEGIN
  ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS check_profile_role;
  ALTER TABLE public.profiles ADD CONSTRAINT check_profile_role
    CHECK (role IN ('admin', 'kasir'));
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'Constraint check_profile_role already updated or skipped: %', SQLERRM;
END $$;

-- ----------------------------------------------------------------------------
-- 2. Pembuatan Tabel restaurant_members
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.restaurant_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  restaurant_id uuid NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  role text NOT NULL CHECK (role IN ('ADMIN', 'KASIR')),
  status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'INVITED', 'INACTIVE')),
  invited_email text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Indeks untuk pencarian cepat
CREATE INDEX IF NOT EXISTS idx_resto_members_user_id ON public.restaurant_members (user_id);
CREATE INDEX IF NOT EXISTS idx_resto_members_resto_id ON public.restaurant_members (restaurant_id);
CREATE INDEX IF NOT EXISTS idx_resto_members_email ON public.restaurant_members (lower(invited_email));

-- Constraint: Tepat SATU akun ADMIN aktif per restoran
CREATE UNIQUE INDEX IF NOT EXISTS unique_active_admin_per_resto
  ON public.restaurant_members (restaurant_id)
  WHERE role = 'ADMIN' AND status = 'ACTIVE';

-- Constraint: Satu user hanya boleh memiliki satu keanggotaan aktif per restoran
CREATE UNIQUE INDEX IF NOT EXISTS unique_user_restaurant_membership
  ON public.restaurant_members (user_id, restaurant_id)
  WHERE user_id IS NOT NULL;

-- Constraint: Satu email yang diundang tidak boleh terduplikasi dalam status INVITED di restoran yang sama
CREATE UNIQUE INDEX IF NOT EXISTS unique_invited_email_per_resto
  ON public.restaurant_members (restaurant_id, lower(invited_email))
  WHERE invited_email IS NOT NULL AND status = 'INVITED';

-- ----------------------------------------------------------------------------
-- 3. Backfill Data Keanggotaan dari Restoran dan Profil Eksisting
-- ----------------------------------------------------------------------------
-- A. Masukkan pemilik restoran (user_id di tabel restaurants) sebagai ADMIN aktif
INSERT INTO public.restaurant_members (user_id, restaurant_id, role, status, created_at, updated_at)
SELECT DISTINCT
  r.user_id,
  r.id,
  'ADMIN',
  'ACTIVE',
  coalesce(r.created_at, now()),
  now()
FROM public.restaurants r
WHERE r.user_id IS NOT NULL
ON CONFLICT (user_id, restaurant_id) WHERE user_id IS NOT NULL
DO UPDATE SET role = 'ADMIN', status = 'ACTIVE';

-- B. Masukkan profil yang memiliki resto_id dan role admin (jika belum tercatat sebagai admin)
WITH ranked_admins AS (
  SELECT
    p.id AS user_id,
    p.resto_id AS restaurant_id,
    ROW_NUMBER() OVER (PARTITION BY p.resto_id ORDER BY p.id ASC) AS rn
  FROM public.profiles p
  WHERE p.resto_id IS NOT NULL
    AND lower(coalesce(p.role, '')) = 'admin'
    AND NOT EXISTS (
      SELECT 1 FROM public.restaurant_members rm
      WHERE rm.restaurant_id = p.resto_id AND rm.role = 'ADMIN' AND rm.status = 'ACTIVE'
    )
)
INSERT INTO public.restaurant_members (user_id, restaurant_id, role, status, created_at, updated_at)
SELECT user_id, restaurant_id, 'ADMIN', 'ACTIVE', now(), now()
FROM ranked_admins
WHERE rn = 1
ON CONFLICT (user_id, restaurant_id) WHERE user_id IS NOT NULL
DO NOTHING;

-- C. Masukkan seluruh profil kasir yang sudah terhubung dengan resto_id
INSERT INTO public.restaurant_members (user_id, restaurant_id, role, status, created_at, updated_at)
SELECT DISTINCT
  p.id,
  p.resto_id,
  'KASIR',
  'ACTIVE',
  now(),
  now()
FROM public.profiles p
WHERE p.resto_id IS NOT NULL
  AND lower(coalesce(p.role, '')) = 'kasir'
ON CONFLICT (user_id, restaurant_id) WHERE user_id IS NOT NULL
DO UPDATE SET role = 'KASIR', status = 'ACTIVE';

-- D. Masukkan staf dari tabel employees yang memiliki email ke status INVITED jika belum ada user_id aktif
INSERT INTO public.restaurant_members (restaurant_id, role, status, invited_email, created_at, updated_at)
SELECT DISTINCT
  e.resto_id,
  'KASIR',
  'INVITED',
  lower(trim(e.email)),
  coalesce(e.created_at, now()),
  now()
FROM public.employees e
WHERE e.resto_id IS NOT NULL
  AND e.email IS NOT NULL
  AND trim(e.email) != ''
  AND NOT EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE lower(trim(p.email)) = lower(trim(e.email)) AND p.resto_id = e.resto_id
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.restaurant_members rm
    WHERE rm.restaurant_id = e.resto_id AND lower(trim(coalesce(rm.invited_email, ''))) = lower(trim(e.email))
  )
ON CONFLICT DO NOTHING;

-- ----------------------------------------------------------------------------
-- 4. Fungsi & RPC Database untuk Multi-User & Manajemen Keanggotaan
-- ----------------------------------------------------------------------------

-- A. Fungsi untuk Mengklaim Undangan Karyawan saat Login / Register
CREATE OR REPLACE FUNCTION public.claim_staff_invitation(
  p_user_id uuid,
  p_email text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_clean_email text := lower(btrim(coalesce(p_email, '')));
  v_invitation record;
  v_resto_name text;
BEGIN
  IF p_user_id IS NULL OR v_clean_email = '' THEN
    RETURN jsonb_build_object('success', false, 'message', 'Parameter user_id dan email tidak valid.');
  END IF;

  -- Cari undangan aktif berstatus INVITED yang cocok dengan email ini
  SELECT rm.id, rm.restaurant_id, rm.role
  INTO v_invitation
  FROM public.restaurant_members rm
  WHERE lower(btrim(coalesce(rm.invited_email, ''))) = v_clean_email
    AND rm.status = 'INVITED'
  ORDER BY rm.created_at DESC
  LIMIT 1;

  IF v_invitation.id IS NOT NULL THEN
    -- Update restaurant_members menjadi ACTIVE dan pasang user_id
    UPDATE public.restaurant_members
    SET
      user_id = p_user_id,
      status = 'ACTIVE',
      updated_at = now()
    WHERE id = v_invitation.id;

    -- Update profil pengguna dengan role 'kasir' dan resto_id yang sesuai
    UPDATE public.profiles
    SET
      resto_id = v_invitation.restaurant_id,
      role = 'kasir'
    WHERE id = p_user_id;

    SELECT name INTO v_resto_name FROM public.restaurants WHERE id = v_invitation.restaurant_id;

    RETURN jsonb_build_object(
      'success', true,
      'claimed', true,
      'restaurant_id', v_invitation.restaurant_id,
      'restaurant_name', coalesce(v_resto_name, 'Restoran'),
      'role', 'KASIR'
    );
  END IF;

  RETURN jsonb_build_object('success', true, 'claimed', false);
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_staff_invitation(uuid, text) TO authenticated, anon;

-- B. Fungsi untuk Mengundang Karyawan Baru (Hanya ADMIN yang berhak)
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
  v_caller_role text;
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
    RAISE EXCEPTION 'Format email karyawan tidak valid.';
  END IF;

  IF v_clean_name = '' THEN
    RAISE EXCEPTION 'Nama karyawan wajib diisi.';
  END IF;

  -- Verifikasi caller adalah ADMIN aktif dari restoran miliknya
  SELECT rm.restaurant_id, rm.role INTO v_resto_id, v_caller_role
  FROM public.restaurant_members rm
  WHERE rm.user_id = v_caller_uid
    AND rm.status = 'ACTIVE'
  LIMIT 1;

  IF v_resto_id IS NULL OR v_caller_role != 'ADMIN' THEN
    RAISE EXCEPTION 'Hanya ADMIN restoran yang memiliki izin mengundang karyawan.';
  END IF;

  -- Cek apakah email sudah terdaftar di auth.users / profiles
  SELECT p.id INTO v_target_user_id
  FROM public.profiles p
  WHERE lower(trim(p.email)) = v_clean_email
  LIMIT 1;

  -- Cek apakah sudah terdaftar di restaurant_members untuk restoran ini
  SELECT rm.id, rm.status, rm.role INTO v_existing_member
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

  -- Masukkan atau perbarui record di restaurant_members
  IF v_existing_member.id IS NOT NULL THEN
    UPDATE public.restaurant_members
    SET
      user_id = coalesce(v_target_user_id, user_id),
      role = 'KASIR',
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
      'KASIR',
      CASE WHEN v_target_user_id IS NOT NULL THEN 'ACTIVE' ELSE 'INVITED' END,
      v_clean_email
    )
    RETURNING id INTO v_member_id;
  END IF;

  -- Jika user target sudah terdaftar di profiles, langsung hubungkan ke restoran
  IF v_target_user_id IS NOT NULL THEN
    UPDATE public.profiles
    SET resto_id = v_resto_id, role = 'kasir'
    WHERE id = v_target_user_id;
  END IF;

  -- Sinkronkan juga ke tabel employees agar kasir langsung terlihat di daftar karyawan
  SELECT id INTO v_employee_id
  FROM public.employees
  WHERE resto_id = v_resto_id AND lower(trim(coalesce(email, ''))) = v_clean_email
  LIMIT 1;

  IF v_employee_id IS NOT NULL THEN
    UPDATE public.employees
    SET
      name = v_clean_name,
      role = 'Kasir',
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
      'Kasir',
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

-- C. Update Fungsi upsert_my_restaurant: Otomatis Menetapkan Pembuat sebagai ADMIN Tunggal
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
  v_existing_admin_uid uuid;
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

  -- 1. Cek apakah pengguna saat ini sudah memiliki keanggotaan aktif
  SELECT rm.restaurant_id INTO v_resto_id
  FROM public.restaurant_members rm
  WHERE rm.user_id = v_uid AND rm.status = 'ACTIVE'
  LIMIT 1;

  -- 2. Jika belum di restaurant_members, periksa relasi lama di restaurants.user_id atau profiles.resto_id
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

  -- 3. Jika restoran sudah ada: Hanya ADMIN yang diizinkan memperbarui identitas restoran
  IF v_resto_id IS NOT NULL THEN
    SELECT rm.user_id INTO v_existing_admin_uid
    FROM public.restaurant_members rm
    WHERE rm.restaurant_id = v_resto_id AND rm.role = 'ADMIN' AND rm.status = 'ACTIVE'
    LIMIT 1;

    IF v_existing_admin_uid IS NOT NULL AND v_existing_admin_uid != v_uid THEN
      RAISE EXCEPTION 'Hanya akun ADMIN pemilik yang berhak mengubah identitas restoran.';
    END IF;

    UPDATE public.restaurants
    SET
      name = v_clean_name,
      category = coalesce(v_clean_category, category),
      address = v_clean_address,
      phone = v_clean_phone,
      user_id = coalesce(user_id, v_uid)
    WHERE id = v_resto_id;

    -- Pastikan tercatat sebagai ADMIN di restaurant_members
    INSERT INTO public.restaurant_members (user_id, restaurant_id, role, status, updated_at)
    VALUES (v_uid, v_resto_id, 'ADMIN', 'ACTIVE', now())
    ON CONFLICT (user_id, restaurant_id) WHERE user_id IS NOT NULL
    DO UPDATE SET role = 'ADMIN', status = 'ACTIVE', updated_at = now();

  ELSE
    -- 4. Jika restoran belum ada: Buat restoran baru, tetapkan pembuat sebagai ADMIN TUNGGAL
    INSERT INTO public.restaurants (user_id, name, category, address, phone)
    VALUES (v_uid, v_clean_name, v_clean_category, v_clean_address, v_clean_phone)
    RETURNING id INTO v_resto_id;

    -- Tetapkan sebagai ADMIN aktif di restaurant_members
    INSERT INTO public.restaurant_members (user_id, restaurant_id, role, status)
    VALUES (v_uid, v_resto_id, 'ADMIN', 'ACTIVE');
  END IF;

  -- Tautkan resto_id dan role 'admin' ke profil pengguna
  UPDATE public.profiles
  SET
    resto_id = v_resto_id,
    role = 'admin'
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
-- 5. Row Level Security (RLS) untuk restaurant_members, employees, dan restaurants
-- ----------------------------------------------------------------------------
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
CREATE POLICY "Only admin can insert restaurant_members"
  ON public.restaurant_members
  FOR INSERT
  TO authenticated
  WITH CHECK (
    user_id = auth.uid() -- Pengguna baru yang mendaftar restoran sendiri
    OR restaurant_id IN (
      SELECT rm.restaurant_id
      FROM public.restaurant_members rm
      WHERE rm.user_id = auth.uid() AND rm.role = 'ADMIN' AND rm.status = 'ACTIVE'
    )
  );

DROP POLICY IF EXISTS "Only admin can update restaurant_members" ON public.restaurant_members;
CREATE POLICY "Only admin can update restaurant_members"
  ON public.restaurant_members
  FOR UPDATE
  TO authenticated
  USING (
    restaurant_id IN (
      SELECT rm.restaurant_id
      FROM public.restaurant_members rm
      WHERE rm.user_id = auth.uid() AND rm.role = 'ADMIN' AND rm.status = 'ACTIVE'
    )
  );

DROP POLICY IF EXISTS "Only admin can delete restaurant_members" ON public.restaurant_members;
CREATE POLICY "Only admin can delete restaurant_members"
  ON public.restaurant_members
  FOR DELETE
  TO authenticated
  USING (
    restaurant_id IN (
      SELECT rm.restaurant_id
      FROM public.restaurant_members rm
      WHERE rm.user_id = auth.uid() AND rm.role = 'ADMIN' AND rm.status = 'ACTIVE'
    )
    AND role != 'ADMIN' -- Mencegah penghapusan ADMIN tunggal sembarangan
  );

-- Kebijakan RLS untuk public.employees (Hanya ADMIN yang boleh memodifikasi)
ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Members can view employees of same restaurant" ON public.employees;
CREATE POLICY "Members can view employees of same restaurant"
  ON public.employees
  FOR SELECT
  TO authenticated
  USING (
    resto_id IN (
      SELECT rm.restaurant_id
      FROM public.restaurant_members rm
      WHERE rm.user_id = auth.uid() AND rm.status = 'ACTIVE'
    )
  );

DROP POLICY IF EXISTS "Only admin can modify employees" ON public.employees;
CREATE POLICY "Only admin can modify employees"
  ON public.employees
  FOR ALL
  TO authenticated
  USING (
    resto_id IN (
      SELECT rm.restaurant_id
      FROM public.restaurant_members rm
      WHERE rm.user_id = auth.uid() AND rm.role = 'ADMIN' AND rm.status = 'ACTIVE'
    )
  )
  WITH CHECK (
    resto_id IN (
      SELECT rm.restaurant_id
      FROM public.restaurant_members rm
      WHERE rm.user_id = auth.uid() AND rm.role = 'ADMIN' AND rm.status = 'ACTIVE'
    )
  );
