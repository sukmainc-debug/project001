// ===== KONFIGURASI SUPABASE =====
// Project URL & Anon Key OmniSeller
const SUPABASE_URL = 'https://jmxlryjmijuusxwmqxrl.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpteGxyeWptaWp1dXN4d21xeHJsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMyNDIxOTksImV4cCI6MjA5ODgxODE5OX0.AAf9QG3Cwv49sZQxkyLhDI27uixTbg_QV8vx9OVzjEI';

// Inisialisasi client Supabase (tersedia secara global sebagai `supabaseClient`)
// PENTING: dibungkus try/catch dan diberi nilai awal `null`. Kalau ditulis
// polos seperti sebelumnya (`const supabaseClient = supabase.createClient(...)`)
// dan script CDN Supabase gagal dimuat (internet lambat/mati, CDN diblokir
// firewall/jaringan kantor-sekolah, ad-blocker, dll), maka `supabase` bernilai
// undefined dan baris ini melempar error SEBELUM sempat mengisi
// `supabaseClient`. Karena dideklarasikan dengan `const`, variabel ini sudah
// "terdaftar" duluan di lingkup global (hoisting) tapi belum diinisialisasi
// (temporal dead zone) — akibatnya SEMUA pengecekan `typeof supabaseClient
// === 'undefined'` di app.js (yang seharusnya aman & menampilkan pesan error
// yang ramah) ikut melempar ReferenceError "Cannot access 'supabaseClient'
// before initialization". Efeknya: tombol "Otentikasi" & "Minta akses" di
// menu login terlihat SAMA SEKALI tidak merespon saat diklik (errornya cuma
// muncul diam-diam di console, sebelum sempat menampilkan pesan apa pun ke
// layar). Dengan `let supabaseClient=null;` di luar try/catch, variabel ini
// SELALU punya nilai (default null) walau inisialisasi gagal, sehingga
// pengecekan `!supabaseClient` di app.js bekerja seperti mestinya dan pesan
// "Koneksi ke Supabase gagal dimuat" benar-benar tampil ke pengguna.
let supabaseClient=null;
try{
  supabaseClient = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
}catch(e){
  console.error('Gagal membuat Supabase client — kemungkinan CDN Supabase gagal dimuat (cek koneksi internet / firewall):',e);
}

// Nama-nama tabel relasional (lihat SETUP-DATABASE.sql)
const TBL_KATEGORI='kategori';
const TBL_MARKETPLACE='marketplace';
const TBL_STOK='stok';
const TBL_PENJUALAN='penjualan'; // tabel LAMA (1 pesanan = 1 barang) — dipertahankan sebagai arsip, TIDAK dipakai lagi untuk sinkron
const TBL_BIAYA='biaya_pengaturan';
const TBL_HPP_PRODUK='hpp_per_produk';
const TBL_PENGATURAN='pengaturan_toko';
// Tabel BARU untuk pesanan multi-item (lihat TAMBAH-MULTI-ITEM.sql):
// 1 pesanan (header, di `pesanan`) bisa punya banyak barang (detail, di `pesanan_item`).
const TBL_PESANAN='pesanan';
const TBL_PESANAN_ITEM='pesanan_item';
// Tabel Inventory (lihat TAMBAH-INVENTORY.sql): pembelian barang dari
// supplier & penggajian karyawan — dipakai untuk mengurangi Laba Bersih.
const TBL_PEMBELIAN='pembelian';
const TBL_PENGGAJIAN='penggajian';
// Tabel History Aktivitas (lihat SETUP-LENGKAP-OMNISELLER.sql Bagian 7):
// mencatat semua aktivitas tambah/edit/hapus/login/dst di seluruh aplikasi.
const TBL_LOG_AKTIVITAS='log_aktivitas';
