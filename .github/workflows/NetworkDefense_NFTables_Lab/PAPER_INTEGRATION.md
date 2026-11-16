# Integrasi hasil pengujian nftables ke paper JOIV

## III. MATERIAL AND METHOD — saran tambahan

Penelitian meliputi tiga kondisi dengan lima host uji dan satu router virtual. Kondisi pertama menggunakan bridge Layer 2 yang sama (flat network). Kondisi kedua memisahkan host ke subnet berbeda namun mengizinkan seluruh trafik melalui nftables (routed-open control). Kondisi ketiga menerapkan default-deny ACL pada chain FORWARD nftables dan hanya mengizinkan koneksi ATTACKER→USER, ATTACKER→WEB, serta WEB→DATABASE pada TCP/8080. Semua skenario menjalankan set koneksi yang identik. Uji diulang dalam tiga siklus dengan lima percobaan koneksi TCP per target tiap siklus. Bukti dikumpulkan melalui CSV percobaan dan counter aturan nftables.

## IV. RESULTS AND DISCUSSION — kerangka yang harus dilengkapi sesudah eksperimen

**Table I. TCP Connectivity by Network Configuration**

| Target | Flat successful/total | Routed-open successful/total | Segmented-ACL successful/total |
|---|---:|---:|---:|
| USER | hasil | hasil | hasil |
| WEB | hasil | hasil | hasil |
| DATABASE | hasil | hasil | hasil |
| ADMIN | hasil | hasil | hasil |

**Table II. Allowed Business Path and Controlled Multi-Hop**

| Pengujian | Flat | Routed-open | Segmented-ACL |
|---|---|---|---|
| WEB → DATABASE | hasil | hasil | hasil |
| ATTACKER → WEB → DATABASE marker | hasil | hasil | hasil |

**Figure 1:** gunakan `results/figure_actual_connections.svg` setelah semua mode diuji.

## Ketepatan interpretasi

Jangan menyebut hasil ini sebagai *malware propagation test* atau *exploit success*. Istilah yang tepat adalah pengujian kebijakan firewall kernel, konektivitas TCP, dan emulasi jalur multi-hop menggunakan marker yang dikendalikan peneliti.
