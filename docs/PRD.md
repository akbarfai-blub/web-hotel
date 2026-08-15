# Product Requirements Document (PRD)
## Web Hotel — Hotel Booking & Reservation Platform

**Versi:** 2.0  
**Tipe project:** Portfolio pribadi — single-property hotel  
**Developer:** Solo  
**Tanggal:** Agustus 2026

---

## 1. Latar Belakang & Tujuan

Web Hotel adalah platform reservasi hotel single-property yang dibangun sebagai project portfolio untuk menunjukkan kemampuan end-to-end product development: product thinking, frontend, backend, database engineering, payment integration, security, dan AI/RAG.

### Tujuan utama

- Menunjukkan implementasi end-to-end dari PRD → design system → database → aplikasi.
- Mendemonstrasikan booking engine yang aman dan tahan terhadap double-booking.
- Mendemonstrasikan payment flow Midtrans sandbox dengan webhook dan idempotency.
- Mendemonstrasikan RBAC, Supabase Auth, RLS, validasi input, dan audit trail.
- Mendemonstrasikan AI chatbot berbasis RAG dalam konteks bisnis nyata.
- Menjaga arsitektur tetap sederhana dan realistis untuk solo developer.

---

## 2. Prinsip Arsitektur

- **PostgreSQL adalah source of truth** untuk availability, reservation, pricing snapshot, dan payment state.
- **Next.js Route Handlers** menangani business logic yang bersifat server-side.
- **Supabase Auth** menangani identity/authentication; tabel `public.users` menyimpan application profile.
- **RLS + application authorization + database constraints** digunakan sebagai defense-in-depth.
- **Midtrans webhook** adalah sumber kebenaran untuk konfirmasi payment.
- **Client tidak dipercaya** untuk menentukan harga final, role, atau status reservation.
- **Redis tidak diperlukan pada v1**. Caching dapat ditambahkan setelah ada kebutuhan performa yang terukur.
- Tidak menggunakan microservices atau infrastructure kompleks.

---

## 3. Target Pengguna

| Role | Deskripsi |
|---|---|
| Guest | Mencari kamar, melakukan reservasi, membayar, melihat reservation sendiri, dan menggunakan chatbot |
| Staff | Mengelola reservasi operasional, check-in/out, dan status kamar |
| Admin | Mengelola kamar, room type, pricing, knowledge base, konten, laporan, dan audit |

---

## 4. Ruang Lingkup Fitur

### 4.1 Landing Page (Public)

- Hero section dengan search widget.
- Check-in, check-out, dan jumlah tamu.
- Showcase room types dan fasilitas.
- Galeri foto dengan `next/image`, lazy-loading, WebP/AVIF jika tersedia.
- Testimoni/review.
- Lokasi dan informasi kontak.
- Multi-language ready; minimum ID + EN bila waktu memungkinkan.
- SEO metadata dan structured content dasar.

### 4.2 Booking Engine

Flow utama:

**Search → Availability → Room Detail → Guest Data → Price Review → Payment → Confirmation**

Fitur:

- Pencarian availability berdasarkan tanggal dan occupancy.
- Availability dihitung dari inventory kamar aktual.
- Reservation aktif tidak boleh overlap pada room yang sama.
- Kalkulasi harga dilakukan server-side.
- Price breakdown:
  - room charge
  - subtotal
  - discount
  - tax
  - service fee
  - total
- Harga reservation disimpan sebagai snapshot transaksi.
- Booking flow multi-step dengan state yang persisten saat navigasi antar-step.
- Reservation awal berstatus `pending_payment`.
- Reservation pending memiliki `payment_expires_at`.
- Reservation yang tidak dibayar sampai batas waktu menjadi `expired`.
- Tidak menyimpan data kartu di server.
- Midtrans menangani payment method seperti VA, e-wallet, QRIS, dan metode yang tersedia di sandbox.

### 4.3 Availability & Double-Booking Protection

Availability memiliki dua lapisan:

1. **Application-level check** untuk pengalaman pengguna.
2. **PostgreSQL transaction + exclusion constraint** sebagai final protection.

Saat membuat reservation:

1. Validasi input dengan Zod.
2. Re-check availability.
3. Hitung ulang harga di server.
4. Jalankan transaction.
5. Insert reservation.
6. PostgreSQL menolak overlapping active reservation.
7. Commit jika berhasil.

Client tidak dapat mengubah harga final atau langsung mengubah reservation menjadi `confirmed`.

### 4.4 Payment

Flow:

**Create payment → User pays → Midtrans webhook → Verify → Idempotency check → DB transaction → Confirm reservation**

Requirement:

- Signature/webhook notification harus diverifikasi.
- Webhook bersifat idempotent.
- Payment status disimpan di database.
- Reservation hanya berubah menjadi `confirmed` berdasarkan hasil payment yang tervalidasi.
- Tidak menyimpan card number, CVV, atau credential payment sensitif.
- Mendukung status payment minimal: `pending`, `paid`, `failed`, `refunded`.

### 4.5 Staff/Admin Panel

#### Staff

- Dashboard reservasi.
- Today's arrivals.
- Today's departures.
- Upcoming reservations.
- Reservation detail.
- Check-in.
- Check-out.
- Update room status.

#### Admin

- CRUD room types.
- CRUD rooms.
- Seasonal/dynamic rates.
- Reservation management.
- Basic occupancy report.
- Basic revenue report.
- Knowledge base management.
- Audit log.

### 4.6 Chatbot AI

- Floating chat widget.
- Menjawab FAQ hotel.
- Menjawab informasi room/facility/policy/location.
- Membantu cek availability.
- Mengarahkan user ke booking engine.
- Tidak menangani payment secara langsung.
- RAG menggunakan pgvector.
- Knowledge base memiliki category dan metadata.
- Jika informasi tidak tersedia/confidence rendah, AI tidak mengarang dan menawarkan kontak staff.

### 4.7 Reviews

- Guest dapat membuat review setelah reservation selesai.
- Rating 1–5.
- Comment opsional.
- Review dikaitkan dengan reservation dan guest.

---

## 5. Non-Functional Requirements

### 5.1 Security

- Supabase Auth untuk authentication.
- Tidak menyimpan password hash aplikasi jika menggunakan Supabase Auth.
- Validasi input seluruh form dan Route Handler dengan Zod.
- RBAC untuk guest/staff/admin.
- RLS pada tabel yang mengandung data sensitif/transaksional.
- Authorization dilakukan server-side; role dari request body tidak dipercaya.
- Audit log untuk perubahan data penting.
- Identity number/KTP/Passport dienkripsi di application layer.
- Tidak menyimpan data kartu pembayaran.
- Rate limiting pada endpoint sensitif seperti authentication, reservation creation, payment webhook, dan chatbot.
- HTTPS enforced + HSTS pada deployment production.
- Consent, retention, access, dan deletion policy untuk data pribadi sesuai kebutuhan project dan konteks UU PDP.

### 5.2 Data Integrity

- PostgreSQL constraint untuk validitas data.
- Exclusion constraint untuk mencegah overlapping reservation.
- Transaction untuk operasi booking dan payment state change.
- State transition reservation harus divalidasi server-side.
- Payment webhook idempotent.
- Server selalu menghitung ulang total price.

### 5.3 Performa

Target:

- LCP < 2.5s pada halaman utama.
- Lighthouse Performance ≥ 90 sebagai target portfolio.
- Lighthouse Accessibility ≥ 90.
- Optimasi gambar menggunakan `next/image`.
- Tidak menggunakan Redis pada v1 kecuali benchmark menunjukkan kebutuhan.
- Query availability harus memiliki index yang sesuai.

### 5.4 Accessibility

- WCAG AA sebagai target.
- Keyboard-friendly booking flow.
- Focus-visible state.
- Label form yang benar.
- Date picker dapat digunakan via keyboard.
- Error message dekat dengan field terkait.

---

## 6. Tech Stack

| Layer | Teknologi |
|---|---|
| Frontend | Next.js 14 App Router, TypeScript |
| Styling | Tailwind CSS v4, shadcn/ui |
| Motion | Framer Motion |
| Backend | Next.js Route Handlers |
| Database | PostgreSQL via Supabase |
| Vector Search | pgvector |
| ORM | Prisma |
| Auth | Supabase Auth |
| Payment | Midtrans Sandbox |
| AI | Claude/OpenAI API |
| Validation | Zod |
| Hosting | Vercel |
| Storage | Supabase Storage |
| Monitoring | Sentry |

**Catatan:** Redis/Upstash tidak menjadi dependency v1.

---

## 7. User Flow

### Guest Booking

Landing → Search → Availability → Room Detail → Guest Data → Price Review → Midtrans → Webhook → Confirmation

### Chatbot

Open Chat → Question → RAG Retrieval → AI Answer → Optional Availability → Redirect to Booking

### Staff

Login → Dashboard → Reservation → Check-in / Check-out → Room Status

### Admin

Login → Dashboard → Rooms / Rates / Reservations / Knowledge Base / Reports / Audit

---

## 8. Reservation State Machine

```text
pending_payment
    ├── payment success → confirmed
    ├── payment timeout → expired
    └── cancellation → cancelled

confirmed
    ├── arrival → checked_in
    ├── cancellation → cancelled
    └── no arrival → no_show

checked_in
    └── checkout → checked_out
```

Status tidak boleh diubah sembarang oleh client.

---

## 9. Success Metrics

- Booking sandbox dapat selesai end-to-end tanpa double-booking.
- Payment webhook berhasil mengubah reservation secara idempotent.
- Chatbot menjawab ≥80% FAQ dasar secara akurat pada test set project.
- Lighthouse Performance ≥90.
- Lighthouse Accessibility ≥90.
- Tidak ada API key/payment credential sensitif di client.
- Tidak ada password hash aplikasi bila Supabase Auth digunakan.
- Audit trail tersedia untuk perubahan reservation dan pricing penting.

---

## 10. Out of Scope v1

- Multi-property.
- Multi-tenant.
- Native mobile app.
- OTA/channel manager.
- Loyalty program.
- Advanced revenue management.
- Complex event-driven infrastructure.
- Microservices.
- Redis sebagai dependency wajib.

Kolom `hotel_id` tetap dipertahankan pada domain yang relevan agar schema mudah dikembangkan jika project diperluas.

---

## 11. Roadmap

### Phase 0 — Foundation
- Database schema.
- Prisma.
- Supabase Auth.
- RLS.
- Zod.
- Design tokens.
- Error handling.

### Phase 1 — Public Website
- Landing.
- Room listing/detail.
- Search widget.
- Responsive UI.

### Phase 2 — Booking Engine
- Availability.
- Pricing engine.
- Reservation.
- Transaction.
- Double-booking protection.
- Reservation state machine.

### Phase 3 — Payment
- Midtrans sandbox.
- Payment creation.
- Webhook.
- Signature verification.
- Idempotency.
- Payment expiration.
- Confirmation.

### Phase 4 — Staff/Admin
- Reservation dashboard.
- Check-in/out.
- Room status.
- Room management.
- Rate management.
- Reports.
- Audit logs.

### Phase 5 — AI
- Knowledge base.
- Embeddings.
- pgvector retrieval.
- RAG.
- FAQ.
- Availability assistance.
- Staff fallback.

### Phase 6 — Polish & Production
- Testing.
- Security review.
- Accessibility review.
- Performance optimization.
- Sentry.
- SEO.
- Deployment.

---

## 12. Definition of Done

Feature dianggap selesai jika:

- Input tervalidasi.
- Authorization diterapkan.
- Error state ditangani.
- Loading state ditangani.
- Mobile responsive.
- Accessibility dasar terpenuhi.
- Database constraints relevan tersedia.
- Tidak ada sensitive data yang terekspos ke client.
- Happy path dan failure path diuji.
