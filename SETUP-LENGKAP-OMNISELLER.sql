-- =========================================================================
-- OMNISELLER DASHBOARD — SETUP LENGKAP (1 FILE, URUT, AMAN DIJALANKAN SEKALI)
-- Jalankan di: Supabase Dashboard > SQL Editor > New Query > Run
--
-- File ini adalah GABUNGAN dari (dalam urutan eksekusi yang benar):
--   1. SETUP-DATABASE.sql        -> 7 tabel dasar (kategori, marketplace,
--                                    stok, penjualan[lama/arsip], biaya_pengaturan,
--                                    hpp_per_produk, pengaturan_toko)
--   2. SETUP-ROLES.sql           -> tabel admin_users + fungsi my_role() +
--                                    RLS berbasis role (owner/staff/viewer/pending)
--   3. TAMBAH-MULTI-ITEM.sql     -> tabel pesanan + pesanan_item (skema yang
--                                    DIPAKAI AKTIF oleh app.js sekarang)
--   4. TAMBAH-ROLE-KASIR.sql     -> tambah role 'kasir'
--   5. [BARU/DIREKONSTRUKSI] tabel pembelian & penggajian -> WAJIB, karena
--      app.js (menu Inventory) aktif membaca/menulis 2 tabel ini, tapi file
--      pembuatnya (TAMBAH-INVENTORY.sql) TIDAK ada di antara file yang
--      diupload. Skema di bawah saya susun ulang dari fungsi
--      syncPembelian_() / syncPenggajian_() / loadFromSupabase() di app.js.
--      >>> CEK KEMBALI bagian ini kalau Anda punya file TAMBAH-INVENTORY.sql
--          aslinya — mungkin ada kolom tambahan yang tidak tertangkap di sini.
--   6. TAMBAH-AUDIT-TRAIL.sql    -> kolom created_by/updated_by otomatis
--
-- TIDAK disertakan (sengaja):
--   - HAPUS-DATA-DUMMY.sql       -> ini script pembersihan data contoh,
--                                    dijalankan NANTI kalau perlu, bukan
--                                    bagian dari setup awal.
--   - Trik "insert manual jadi owner" dari PANDUAN-ROLE-AKSES.md -> hanya
--     dibutuhkan untuk akun admin yang DIBUAT SEBELUM SETUP-ROLES.sql ada.
--     Karena ini instalasi baru (belum ada akun admin sama sekali), Owner
--     pertama akan otomatis terbentuk lewat trigger begitu Anda Sign Up
--     pertama kali dari halaman aplikasi. Cukup pastikan Anda Sign Up
--     PERTAMA KALI setelah script ini selesai dijalankan.
--
-- Aman dijalankan ulang (idempotent): pakai "if not exists" / "or replace" /
-- "drop policy if exists" / "on conflict do nothing" di semua bagian.
-- =========================================================================


-- =========================================================================
-- BAGIAN 1 — TABEL DASAR (dari SETUP-DATABASE.sql)
-- =========================================================================

create table if not exists public.kategori (
  id bigint generated always as identity primary key,
  nama text not null unique,
  color text not null default '#888888',
  created_at timestamptz default now()
);

create table if not exists public.marketplace (
  id bigint generated always as identity primary key,
  nama text not null unique,
  color text not null default '#888888',
  fee_persen numeric not null default 3,
  created_at timestamptz default now()
);

create table if not exists public.stok (
  id bigint generated always as identity primary key,
  sku text not null unique,
  produk text not null,
  varian text default '',
  kategori text default 'Lainnya',
  stok int not null default 0,
  terjual int not null default 0,
  hpp numeric default 0,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Tabel lama (1 pesanan = 1 barang). Dipertahankan sebagai arsip/kompatibilitas
-- skema; app.js versi sekarang TIDAK lagi menulis ke tabel ini (lihat Bagian 3).
create table if not exists public.penjualan (
  id bigint generated always as identity primary key,
  no_pesanan text not null unique,
  tanggal text not null,
  tgl_iso timestamptz not null,
  marketplace text not null,
  produk text not null,
  varian text default '',
  kategori text default 'Lainnya',
  qty int not null default 1,
  total bigint not null default 0,
  status text not null default 'Selesai',
  created_at timestamptz default now()
);

create table if not exists public.biaya_pengaturan (
  id int primary key default 1,
  ongkir numeric default 3000,
  packaging numeric default 1500,
  lain numeric default 500,
  hpp_mode text default 'pct',
  hpp_pct numeric default 45,
  updated_at timestamptz default now(),
  constraint singleton_row check (id = 1)
);

create table if not exists public.hpp_per_produk (
  produk text primary key,
  hpp numeric not null default 0,
  updated_at timestamptz default now()
);

create table if not exists public.pengaturan_toko (
  id int primary key default 1,
  nama_toko text default 'Toko Saya',
  pemilik text default '',
  hp text default '',
  batas_stok int default 10,
  logo text default '',
  updated_at timestamptz default now(),
  constraint singleton_row check (id = 1)
);

alter table public.kategori enable row level security;
alter table public.marketplace enable row level security;
alter table public.stok enable row level security;
alter table public.penjualan enable row level security;
alter table public.biaya_pengaturan enable row level security;
alter table public.hpp_per_produk enable row level security;
alter table public.pengaturan_toko enable row level security;

-- Policy sementara: full akses untuk siapa pun yang login (authenticated).
-- Akan DIPERKETAT jadi berbasis role pada Bagian 2 di bawah.
do $$
declare t text;
begin
  for t in select unnest(array['kategori','marketplace','stok','penjualan','biaya_pengaturan','hpp_per_produk','pengaturan_toko'])
  loop
    execute format('drop policy if exists "admin_full_access" on public.%I', t);
    execute format('create policy "admin_full_access" on public.%I for all using (auth.role() = ''authenticated'') with check (auth.role() = ''authenticated'')', t);
  end loop;
end $$;

insert into public.kategori (nama,color) values
  ('Atasan','#4f3de8'),('Bawahan','#ee4d2d'),('Outer','#00aa5b'),('Aksesoris','#f59e0b'),('Lainnya','#888888')
on conflict (nama) do nothing;

insert into public.marketplace (nama,color,fee_persen) values
  ('Shopee','#ee4d2d',3.5),('Tokopedia','#00aa5b',2.5),('TikTok Shop','#444444',1.8),('Lazada','#1a0dab',4.0)
on conflict (nama) do nothing;

insert into public.biaya_pengaturan (id) values (1) on conflict (id) do nothing;
insert into public.pengaturan_toko (id) values (1) on conflict (id) do nothing;

create index if not exists idx_penjualan_tgl on public.penjualan(tgl_iso);
create index if not exists idx_penjualan_mp on public.penjualan(marketplace);
create index if not exists idx_penjualan_kat on public.penjualan(kategori);
create index if not exists idx_stok_kat on public.stok(kategori);


-- =========================================================================
-- BAGIAN 2 — SISTEM ROLE / HAK AKSES ADMIN (dari SETUP-ROLES.sql)
-- =========================================================================

create table if not exists public.admin_users (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  nama text default '',
  role text not null default 'pending' check (role in ('owner','staff','viewer','pending')),
  created_at timestamptz default now()
);
alter table public.admin_users enable row level security;

create or replace function public.my_role()
returns text language sql stable security definer as $$
  select role from public.admin_users where id = auth.uid();
$$;

-- Trigger: user PERTAMA yang Sign Up otomatis jadi 'owner'; berikutnya 'pending'.
-- Karena ini instalasi baru (belum ada akun sama sekali), Sign Up pertama Anda
-- di aplikasi SETELAH script ini jalan = otomatis jadi Owner.
create or replace function public.handle_new_admin_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.admin_users (id, email, nama, role)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'nama', new.email),
    case when (select count(*) from public.admin_users) = 0 then 'owner' else 'pending' end
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_admin_user();

drop policy if exists "lihat semua profil" on public.admin_users;
create policy "lihat semua profil" on public.admin_users
  for select using (auth.role() = 'authenticated');

drop policy if exists "owner kelola role" on public.admin_users;
create policy "owner kelola role" on public.admin_users
  for update using (public.my_role() = 'owner') with check (public.my_role() = 'owner');

drop policy if exists "owner hapus akses" on public.admin_users;
create policy "owner hapus akses" on public.admin_users
  for delete using (public.my_role() = 'owner');

-- Tabel transaksi/operasional: owner & staff boleh ubah, viewer hanya lihat
do $$
declare t text;
begin
  for t in select unnest(array['kategori','marketplace','stok','penjualan','hpp_per_produk'])
  loop
    execute format('drop policy if exists "admin_full_access" on public.%I', t);
    execute format('drop policy if exists "role_select" on public.%I', t);
    execute format('drop policy if exists "role_write" on public.%I', t);
    execute format('create policy "role_select" on public.%I for select using (public.my_role() in (''owner'',''staff'',''viewer''))', t);
    execute format('create policy "role_write" on public.%I for all using (public.my_role() in (''owner'',''staff'')) with check (public.my_role() in (''owner'',''staff''))', t);
  end loop;
end $$;

-- Tabel pengaturan sensitif: hanya owner yang boleh ubah
do $$
declare t text;
begin
  for t in select unnest(array['biaya_pengaturan','pengaturan_toko'])
  loop
    execute format('drop policy if exists "admin_full_access" on public.%I', t);
    execute format('drop policy if exists "role_select" on public.%I', t);
    execute format('drop policy if exists "role_write" on public.%I', t);
    execute format('create policy "role_select" on public.%I for select using (public.my_role() in (''owner'',''staff'',''viewer''))', t);
    execute format('create policy "role_write" on public.%I for all using (public.my_role() = ''owner'') with check (public.my_role() = ''owner'')', t);
  end loop;
end $$;


-- =========================================================================
-- BAGIAN 3 — PESANAN MULTI-ITEM (dari TAMBAH-MULTI-ITEM.sql)
-- Ini skema yang AKTIF dipakai app.js sekarang (tabel `pesanan` + `pesanan_item`)
-- =========================================================================

create table if not exists public.pesanan (
  id bigint generated always as identity primary key,
  no_pesanan text not null unique,
  tanggal text not null,
  tgl_iso timestamptz not null,
  marketplace text not null,
  status text not null default 'Selesai',
  biaya_admin numeric,
  biaya_tambahan numeric,
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists public.pesanan_item (
  id bigint generated always as identity primary key,
  pesanan_id bigint not null references public.pesanan(id) on delete cascade,
  produk text not null,
  varian text default '',
  kategori text default 'Lainnya',
  qty int not null default 1,
  harga_satuan numeric not null default 0,
  subtotal numeric not null default 0,
  hpp_saat_transaksi numeric default 0,
  created_at timestamptz default now()
);
create index if not exists idx_pesanan_item_pesanan on public.pesanan_item(pesanan_id);
create index if not exists idx_pesanan_item_produk on public.pesanan_item(produk);

alter table public.pesanan enable row level security;
alter table public.pesanan_item enable row level security;

-- Karena my_role() sudah ada (Bagian 2 sudah jalan), langsung pakai RLS berbasis role.
drop policy if exists "role_select" on public.pesanan;
drop policy if exists "role_write" on public.pesanan;
create policy "role_select" on public.pesanan for select using (public.my_role() in ('owner','staff','viewer'));
create policy "role_write" on public.pesanan for all using (public.my_role() in ('owner','staff')) with check (public.my_role() in ('owner','staff'));

drop policy if exists "role_select" on public.pesanan_item;
drop policy if exists "role_write" on public.pesanan_item;
create policy "role_select" on public.pesanan_item for select using (public.my_role() in ('owner','staff','viewer'));
create policy "role_write" on public.pesanan_item for all using (public.my_role() in ('owner','staff')) with check (public.my_role() in ('owner','staff'));

-- Migrasi data lama dari `penjualan` (kosong pada instalasi baru — aman & tidak
-- melakukan apa-apa kalau tabel `penjualan` masih kosong; dipertahankan agar
-- script ini tetap sama persis fungsinya kalau suatu saat ada data lama).
insert into public.pesanan (no_pesanan, tanggal, tgl_iso, marketplace, status, biaya_admin, biaya_tambahan)
select no_pesanan, tanggal, tgl_iso, marketplace, status, biaya_admin, biaya_tambahan
from public.penjualan
on conflict (no_pesanan) do nothing;

insert into public.pesanan_item (pesanan_id, produk, varian, kategori, qty, harga_satuan, subtotal)
select p.id, pj.produk, pj.varian, pj.kategori, pj.qty,
       case when pj.qty > 0 then round(pj.total::numeric / pj.qty) else pj.total end,
       pj.total
from public.penjualan pj
join public.pesanan p on p.no_pesanan = pj.no_pesanan
where not exists (
  select 1 from public.pesanan_item pi where pi.pesanan_id = p.id
);


-- =========================================================================
-- BAGIAN 4 — ROLE 'KASIR' (dari TAMBAH-ROLE-KASIR.sql)
-- =========================================================================

alter table public.admin_users drop constraint if exists admin_users_role_check;
alter table public.admin_users add constraint admin_users_role_check
  check (role in ('owner','staff','kasir','viewer','pending'));

create or replace function public.handle_new_admin_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.admin_users (id, email, nama, role)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'nama', new.email),
    case when (select count(*) from public.admin_users) = 0 then 'owner' else 'pending' end
  );
  return new;
end;
$$;

-- Tabel transaksi pesanan: owner, staff, DAN kasir boleh baca+tulis
do $$
declare t text;
begin
  for t in select unnest(array['penjualan','pesanan','pesanan_item'])
  loop
    if to_regclass('public.'||t) is not null then
      execute format('drop policy if exists "role_select" on public.%I', t);
      execute format('drop policy if exists "role_write" on public.%I', t);
      execute format('create policy "role_select" on public.%I for select using (public.my_role() in (''owner'',''staff'',''kasir'',''viewer''))', t);
      execute format('create policy "role_write" on public.%I for all using (public.my_role() in (''owner'',''staff'',''kasir'')) with check (public.my_role() in (''owner'',''staff'',''kasir''))', t);
    end if;
  end loop;
end $$;

-- Tabel operasional lain (stok, kategori, marketplace, hpp_per_produk):
-- kasir HANYA boleh lihat, tidak boleh ubah
do $$
declare t text;
begin
  for t in select unnest(array['kategori','marketplace','stok','hpp_per_produk'])
  loop
    if to_regclass('public.'||t) is not null then
      execute format('drop policy if exists "role_select" on public.%I', t);
      execute format('drop policy if exists "role_write" on public.%I', t);
      execute format('create policy "role_select" on public.%I for select using (public.my_role() in (''owner'',''staff'',''kasir'',''viewer''))', t);
      execute format('create policy "role_write" on public.%I for all using (public.my_role() in (''owner'',''staff'')) with check (public.my_role() in (''owner'',''staff''))', t);
    end if;
  end loop;
end $$;

-- Tabel pengaturan sensitif (biaya, pengaturan toko): tetap hanya owner
do $$
declare t text;
begin
  for t in select unnest(array['biaya_pengaturan','pengaturan_toko'])
  loop
    if to_regclass('public.'||t) is not null then
      execute format('drop policy if exists "role_select" on public.%I', t);
      execute format('drop policy if exists "role_write" on public.%I', t);
      execute format('create policy "role_select" on public.%I for select using (public.my_role() in (''owner'',''staff'',''kasir'',''viewer''))', t);
      execute format('create policy "role_write" on public.%I for all using (public.my_role() = ''owner'') with check (public.my_role() = ''owner'')', t);
    end if;
  end loop;
end $$;


-- =========================================================================
-- BAGIAN 5 — TABEL INVENTORY: pembelian & penggajian
-- >>> DIREKONSTRUKSI dari app.js (syncPembelian_/syncPenggajian_/loadFromSupabase)
-- >>> karena file aslinya (TAMBAH-INVENTORY.sql) TIDAK ada di file yang diupload.
-- Tanpa tabel ini, menu "Inventory — Pembelian & Penggajian" di app akan error
-- (loadFromSupabase melakukan select ke tabel pembelian & penggajian).
-- =========================================================================

create table if not exists public.pembelian (
  id bigint generated always as identity primary key,
  kode text not null unique,
  tanggal text not null,
  tgl_iso timestamptz not null default now(),
  supplier text default '',
  item text default '',
  qty int not null default 1,
  satuan text default 'pcs',
  harga_satuan numeric not null default 0,
  total numeric not null default 0,
  catatan text default '',
  created_at timestamptz default now()
);

create table if not exists public.penggajian (
  id bigint generated always as identity primary key,
  kode text not null unique,
  tanggal text not null,
  tgl_iso timestamptz not null default now(),
  nama_karyawan text default '',
  jabatan text default '',
  periode text default '',
  nominal numeric not null default 0,
  catatan text default '',
  created_at timestamptz default now()
);

create index if not exists idx_pembelian_tgl on public.pembelian(tgl_iso);
create index if not exists idx_penggajian_tgl on public.penggajian(tgl_iso);

alter table public.pembelian enable row level security;
alter table public.penggajian enable row level security;

-- Sama seperti tabel operasional lain: owner & staff boleh tulis;
-- kasir & viewer hanya boleh lihat (kasir dari UI memang tidak diberi
-- akses ke menu Inventory, ini lapis kedua di level database).
do $$
declare t text;
begin
  for t in select unnest(array['pembelian','penggajian'])
  loop
    execute format('drop policy if exists "role_select" on public.%I', t);
    execute format('drop policy if exists "role_write" on public.%I', t);
    execute format('create policy "role_select" on public.%I for select using (public.my_role() in (''owner'',''staff'',''kasir'',''viewer''))', t);
    execute format('create policy "role_write" on public.%I for all using (public.my_role() in (''owner'',''staff'')) with check (public.my_role() in (''owner'',''staff''))', t);
  end loop;
end $$;


-- =========================================================================
-- BAGIAN 6 — AUDIT TRAIL (dari TAMBAH-AUDIT-TRAIL.sql)
-- =========================================================================

create or replace function public.set_audit_fields()
returns trigger language plpgsql security definer as $$
begin
  if TG_OP = 'INSERT' then
    new.created_by := auth.uid();
    new.updated_by := auth.uid();
  elsif TG_OP = 'UPDATE' then
    new.updated_by := auth.uid();
    new.created_by := old.created_by;
  end if;
  return new;
end;
$$;

do $$
declare t text;
begin
  for t in select unnest(array['penjualan','pesanan','stok'])
  loop
    if to_regclass('public.'||t) is not null then
      execute format('alter table public.%I add column if not exists created_by uuid references auth.users(id)', t);
      execute format('alter table public.%I add column if not exists updated_by uuid references auth.users(id)', t);
      execute format('drop trigger if exists trg_audit_fields on public.%I', t);
      execute format('create trigger trg_audit_fields before insert or update on public.%I for each row execute function public.set_audit_fields()', t);
    end if;
  end loop;
end $$;


-- =========================================================================
-- SELESAI.
-- Langkah selanjutnya di aplikasi:
-- 1. Buka aplikasi (index.html) -> klik "Daftar Administrator Baru" ->
--    daftar dengan email & password Anda -> karena ini akun PERTAMA,
--    otomatis langsung jadi Owner & masuk dashboard.
-- 2. Admin/staff/kasir lain yang daftar setelah ini akan berstatus
--    "Menunggu Persetujuan" sampai Anda approve lewat menu
--    Pengaturan -> Manajemen User & Hak Akses.
-- =========================================================================
