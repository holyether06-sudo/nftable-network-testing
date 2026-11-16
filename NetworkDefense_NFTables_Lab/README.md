# Eksperimen Kernel Firewall & Controlled Pivot — Network Defense

**Kegunaan:** membandingkan *flat network*, *segmented routed network* tanpa pembatasan, dan *segmented network dengan nftables ACL*. Seluruh endpoint merupakan namespace Linux di dalam lingkungan yang terisolasi; tidak ada IP publik, target eksternal, malware, pencurian kredensial, atau eksploitasi otomatis.

## Status validasi

- **Berhasil diuji di lingkungan ChatGPT:** pembuatan network namespace/veth/bridge, layanan TCP, pengujian flat network, dan pengiriman *marker* aman WEB → DATABASE.
- **Belum dapat dieksekusi di lingkungan ChatGPT:** pengujian routing dan *kernel nftables*. Container membatasi perubahan `net.ipv4.ip_forward` dan belum menyediakan perintah `nft`; jaringan dengan ACL **tidak diuji di sini**.
- **Perlu dijalankan pada mesin/VM Ubuntu dengan izin administrasi** untuk mendapatkan hasil firewall kernel aktual. Script memeriksa hal ini, dan akan berhenti jika persyaratan tidak terpenuhi.

## Persiapan (pada Ubuntu VM yang didedikasikan untuk lab)

Persyaratan: Ubuntu 22.04/24.04 atau distribusi Linux lain yang mendukung network namespaces dan kernel `nf_tables`, user dengan `sudo`, RAM sekitar 2 GB cukup untuk pengujian kecil. **Jangan jalankan di server produksi.**

```bash
sudo apt update
sudo apt install -y iproute2 nftables python3 util-linux
cd NetworkDefense_NFTables_Lab
sudo bash run_lab.sh
```

Jika `unshare` tidak tersedia karena pembatasan hypervisor/OS, script akan berhenti. **Jangan menonaktifkan isolasi sebagai jalan pintas.** Jalankan pada VM Ubuntu tersendiri.

Untuk percobaan singkat sebelum seluruh pengujian:

```bash
sudo CYCLES=1 REPEATS=2 bash run_lab.sh
```

Secara default terdapat **3 siklus independen**, dengan **5 percobaan TCP untuk tiap target pada setiap siklus**. Prosesnya otomatis membuat dan menghapus jaringan sementara pada akhir setiap mode.

## Topologi dan kondisi uji

| Kondisi | Topologi | Kernel firewall | Tujuan |
|---|---|---|---|
| `flat` | Semua host dalam satu bridge IPv4 /24 | Tidak ada | Baseline konektivitas intra-LAN |
| `routed_open` | Lima subnet dengan router Linux | Aturan nftables terbuka | Kontrol: pengaruh segmentasi IP/routing tanpa pembatasan |
| `segmented_acl` | Lima subnet dengan router Linux | `nftables` stateful; default deny | Ukur pengurangan akses yang tidak diizinkan |

Host: ATTACKER (sumber pengujian), USER, WEB, DATABASE, ADMIN dan namespace ROUTER. Port uji TCP **8080** dengan server Python yang hanya menerima permintaan `PING`, `TRIGGER <marker>` atau `MARKER <marker>`. Tidak ada eksekusi perintah jarak jauh.

Aturan inti dalam `segmented_acl`:

| Sumber | Tujuan | Port | Kebijakan |
|---|---|---|---|
| ATTACKER | USER | TCP/8080 | ALLOW |
| ATTACKER | WEB | TCP/8080 | ALLOW |
| ATTACKER | DATABASE | TCP/8080 | DENY |
| ATTACKER | ADMIN | TCP/8080 | DENY |
| WEB | DATABASE | TCP/8080 | ALLOW |

Dengan menggunakan kondisi `routed_open`, kita dapat menguji apakah koneksi yang hilang pada `segmented_acl` disebabkan aturan ACL, bukan hanya adanya subnet berbeda.

## Skenario controlled pivot

1. ATTACKER mencoba koneksi langsung TCP/8080 ke USER, WEB, DATABASE, dan ADMIN.
2. Pada semua mode, WEB juga melakukan koneksi TCP/8080 ke DATABASE sebagai *positive control*.
3. ATTACKER mengirim `TRIGGER <marker>` ke WEB. Server WEB yang **sengaja diprogram dalam fixture** meneruskan `MARKER <marker>` ke DATABASE apabila jalur yang diizinkan ada.
4. DATABASE mencatat marker yang diterima. Ini memperlihatkan jalur komunikasi multi-hop yang **tersedia**, tetapi **bukan bukti host WEB berhasil dieksploitasi, dieksekusi malware, atau terjadi lateral movement riil tanpa kredensial**.

## Bukti yang dihasilkan otomatis

- `results/tcp_<mode>_c<cycle>.csv`: seluruh percobaan koneksi dari ATTACKER.
- `results/pivot_<mode>_c<cycle>.csv`: koneksi WEB → DATABASE sebagai kontrol positif.
- `results/ruleset_<mode>_c<cycle>.txt` dan `.json`: aturan kernel nftables **beserta counter**, diperoleh langsung dari namespace router.
- `results/markers_<mode>_c<cycle>.jsonl`: pencatatan marker yang diterima DATABASE.
- `results/marker_outcomes.txt`: hasil jalur ATTACKER → WEB → DATABASE.
- `results/environment.txt`: kernel, versi program dan waktu pelaksanaan.
- `results/source_sha256.txt`: SHA256 skrip.
- `results/summary.json` dan `results/figure_actual_connections.svg`: ringkasan dan grafik yang dihitung **hanya dari data hasil eksekusi**.

Untuk meregenerasi grafik setelah selesai:

```bash
python3 analyze.py
python3 make_figures.py
```

## Prinsip penulisan hasil paper

- Pisahkan kesimpulan **reachability Layer 3/4** dari keberhasilan eksploitasi nyata.
- Pengurangan host yang bisa dijangkau tidak otomatis berarti peluang kompromi atau ransomware berkurang dengan persentase yang sama.
- Jika marker dapat mencapai DATABASE melalui WEB, tuliskan bahwa itu *reachable multi-hop path under a pre-programmed fixture*, bukan serangan nyata.
- Jangan memakai data dari eksperimen *gateway aplikasi* sebelumnya sebagai data `nftables` kernel.
- Jika pengujian gagal akibat masalah sistem, **tidak boleh** dicatat sebagai paket yang ditolak firewall.

## Perintah pemeriksaan jika gagal

```bash
which nft; nft --version
ip -V
uname -r
sudo unshare -Urnm -- bash -c 'ip link add test0 type veth peer name test1 && ip link del test0 && echo NamespaceOK'
```

Jika `sysctl` di router namespace gagal mengaktifkan forwarding, script berhenti secara eksplisit. Jalankan pada Ubuntu VM yang tidak memblokir `/proc/sys`, dan jangan menggunakan lingkungan yang tidak memberikan kendali jaringan penuh.

## Keterbatasan ilmiah

Ini pengujian *kernel firewall forwarding* (`nftables`) pada jaringan virtual menggunakan endpoint layanan sederhana. Tidak diuji: firewall fisik Cisco, host IDS, malware/worm, RCE, pengambilalihan kredensial, serta kinerja pada jaringan besar. Hasil digunakan untuk mendukung **kebijakan akses** dan **potensi jalur setelah kompromi**, bukan untuk mengklaim semua serangan telah dicegah.

## Alternatif tanpa VM pribadi: GitHub Actions (hosted Ubuntu VM)

GitHub menyediakan runner standar `ubuntu-24.04` berupa VM penuh; untuk repository publik penggunaan runner standar tidak dikenai biaya. Pada repository privat, penggunaan mengikuti kuota dan tarif GitHub Actions yang berlaku. Lihat dokumentasi resmi: https://docs.github.com/en/actions/concepts/runners/github-hosted-runners dan https://docs.github.com/en/actions/how-tos/manage-runners/github-hosted-runners/use-github-hosted-runners.

1. Buat repository GitHub khusus untuk eksperimen ini.
2. Taruh folder `NetworkDefense_NFTables_Lab` di root repository, dan salin workflow dari `NetworkDefense_NFTables_Lab/.github/workflows/run-nftables-lab.yml` ke `.github/workflows/run-nftables-lab.yml` **di root repository**.
3. Pada repository buka **Actions → Network Defense nftables Lab → Run workflow**.
4. Setelah workflow selesai, buka run tersebut dan unduh artifact `network-defense-nftables-evidence` yang memuat CSV, counter nftables, log marker, dan grafik.
5. Jika workflow gagal pada prasyarat kernel/sysctl, berikan log-nya untuk audit. **Jangan mengarang hasil yang tidak tercatat.**

*Catatan:* mode `--vm-root` hanya untuk VM baru yang didedikasikan untuk pengujian, seperti runner GitHub. Mode ini tetap mengisolasi **mount** dan **network** namespace dari host runner, namun menjalankan proses dengan hak root VM untuk konfigurasi router dan nftables. Jangan menjalankannya pada sistem kantor/produksi.

**Status:** workflow telah disusun berdasarkan dokumentasi runner GitHub, tetapi belum dijalankan di akun GitHub pengguna. Kemampuan `nftables` dan network namespace pada runner tertentu harus divalidasi oleh workflow aktual.
