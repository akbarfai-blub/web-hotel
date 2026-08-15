# Design System
## Web Hotel — Hotel Booking Platform

**Versi:** 2.0  
**Tanggal:** Agustus 2026

---

## 1. Prinsip Desain

### Tenang & Mewah
Palet hangat/netral, whitespace cukup, typography editorial, dan imagery hospitality berkualitas.

### Jelas & Terpercaya
CTA booking jelas, harga transparan, status reservation mudah dipahami, dan tidak ada kejutan pada checkout.

### Konsisten
Semua komponen menggunakan semantic design tokens. Hindari magic number dan nilai visual yang hanya muncul pada satu komponen.

### Transaction-first
Pada booking/payment flow, kejelasan dan kecepatan lebih penting daripada dekorasi dan motion.

### Accessible by Default
Keyboard, focus, contrast, label, error state, dan reduced motion harus dipikirkan sejak component level.

---

## 2. Design Token Architecture

Gunakan tiga layer:

```text
Primitive tokens
      ↓
Semantic tokens
      ↓
Components
```

Komponen sebaiknya menggunakan semantic tokens, bukan langsung menggunakan primitive color.

---

## 3. Color Tokens

### 3.1 Primitive

```css
@theme {
  --color-primary-50: #fdf8f3;
  --color-primary-100: #f8ead9;
  --color-primary-300: #e3bc85;
  --color-primary-500: #c08a3e;
  --color-primary-700: #8a5f22;
  --color-primary-900: #4d3410;

  --color-neutral-50: #fafaf9;
  --color-neutral-100: #f1efec;
  --color-neutral-300: #d6d2cb;
  --color-neutral-500: #8c877e;
  --color-neutral-700: #4a463f;
  --color-neutral-900: #1f1c17;

  --color-success: #2e7d4f;
  --color-warning: #b8842c;
  --color-error: #c0392b;
  --color-info: #2f6690;
}
```

### 3.2 Semantic

```css
@theme {
  --color-background: var(--color-neutral-50);
  --color-surface: #ffffff;
  --color-surface-muted: var(--color-neutral-100);

  --color-text-primary: var(--color-neutral-900);
  --color-text-secondary: var(--color-neutral-700);
  --color-text-muted: var(--color-neutral-500);

  --color-border: var(--color-neutral-300);

  --color-action-primary: var(--color-primary-500);
  --color-action-primary-hover: var(--color-primary-700);
  --color-action-primary-foreground: #ffffff;

  --color-status-success: var(--color-success);
  --color-status-warning: var(--color-warning);
  --color-status-error: var(--color-error);
  --color-status-info: var(--color-info);
}
```

---

## 4. Typography

| Elemen | Font | Ukuran | Weight |
|---|---|---:|---:|
| Display | Fraunces / Playfair Display | 48–64px | 600 |
| H1 | Serif | 36–48px | 600 |
| H2 | Serif | 28–36px | 600 |
| H3 | Serif | 24px | 600 |
| Body | Inter | 16px | 400 |
| Body Small | Inter | 14px | 400 |
| Caption | Inter | 13px | 500 |
| Button | Inter | 14–16px | 500–600 |

Gunakan serif untuk storytelling/brand dan sans-serif untuk informasi, form, price, table, dan transaksi.

---

## 5. Spacing

Base 4px:

```text
4, 8, 12, 16, 24, 32, 48, 64, 96px
```

Hindari custom spacing kecuali ada kebutuhan layout yang jelas.

---

## 6. Radius & Shadow

```css
:root {
  --radius-sm: 6px;
  --radius-md: 12px;
  --radius-lg: 20px;
  --radius-full: 9999px;

  --shadow-card: 0 2px 8px rgba(31, 28, 23, 0.06);
  --shadow-elevated: 0 8px 24px rgba(31, 28, 23, 0.12);
}
```

Gunakan shadow secara hemat. Hospitality visual lebih mengandalkan whitespace dan hierarchy daripada heavy elevation.

---

## 7. Breakpoints

| Nama | Ukuran |
|---|---:|
| sm | 640px |
| md | 768px |
| lg | 1024px |
| xl | 1280px |

Design mobile-first.

---

## 8. Component Standards

### 8.1 Button

Variants:

- primary
- secondary
- ghost
- destructive

Sizes:

- sm
- md
- lg

States:

- default
- hover
- active
- focus-visible
- disabled
- loading

Loading state harus mempertahankan ukuran button agar layout tidak bergeser.

---

### 8.2 Search Widget

Field:

- Check-in
- Check-out
- Guests

Behavior:

- Date range picker.
- Guest counter.
- Validasi check-out > check-in.
- Error inline.
- Sticky pada mobile jika sesuai viewport.
- CTA jelas: `Search rooms`.

---

### 8.3 Room Card

Menampilkan:

- Foto 4:3.
- Room type.
- Short description.
- Highlight amenities.
- Max occupancy.
- Price/night.
- Availability indicator.
- CTA `Choose room`.

Harga harus jelas apakah sudah termasuk tax/fee atau belum.

---

### 8.4 Room Detail

Menampilkan:

- Gallery.
- Description.
- Amenities.
- Occupancy.
- Room size.
- Bed information.
- Availability.
- Pricing.
- Booking CTA.

---

### 8.5 Booking Stepper

4 tahap:

```text
1. Room
2. Guest
3. Payment
4. Confirmation
```

Rules:

- User dapat kembali ke step sebelumnya tanpa kehilangan valid state.
- Step yang belum valid tidak boleh dianggap completed.
- Payment step harus meminimalkan distraction.
- Confirmation menampilkan booking reference dan summary.

---

### 8.6 Price Summary

Gunakan breakdown eksplisit:

```text
Room charge
Subtotal
Discount
Tax
Service fee
────────────────
Total
```

Total adalah angka paling prominent.

---

### 8.7 Payment State

Sediakan state UI:

- Preparing payment
- Waiting for payment
- Payment success
- Payment failed
- Payment expired
- Payment cancelled

Jangan menampilkan `Confirmed` hanya karena payment UI selesai. Confirmation final mengikuti status server.

---

### 8.8 Chat Widget

- Floating button bottom-right.
- Chat bubble AI vs user.
- Typing indicator.
- Quick replies.
- Clear fallback ke staff.
- Quick action `Check room availability`.
- Link ke booking engine, bukan payment langsung.

Pada mobile, widget harus tetap mudah ditutup dan tidak menutupi CTA penting.

---

### 8.9 Admin Table

- Sortable.
- Filter status/date.
- Pagination jika diperlukan.
- Row action melalui dropdown.
- Status menggunakan badge.
- Destructive action membutuhkan confirmation.
- Table harus usable pada viewport kecil.

---

### 8.10 Form

Gunakan shadcn/ui dan semantic tokens.

Field:

- label
- input
- hint bila perlu
- error message

Error:

```text
border error
+
message di bawah field
```

Jangan menggunakan alert global untuk kesalahan field.

---

## 9. Reservation Status Visual

| Status | Intent |
|---|---|
| Pending Payment | Warning |
| Confirmed | Success |
| Checked In | Info |
| Checked Out | Neutral |
| Cancelled | Error/Neutral |
| No Show | Error/Neutral |
| Expired | Neutral |

Jangan hanya menggunakan warna; status harus memiliki text label.

---

## 10. Accessibility

Target WCAG AA:

- Body text contrast ≥ 4.5:1.
- Large text ≥ 3:1.
- Focus-visible jelas.
- Semua interactive element keyboard accessible.
- Semua form field memiliki `<label>`.
- Error dikaitkan dengan field.
- Date picker keyboard accessible.
- Stepper keyboard accessible.
- Modal/Dialog memiliki focus management.
- Gunakan `prefers-reduced-motion` untuk user yang meminta reduced motion.

---

## 11. Motion

### Micro interaction
200–300ms.

### Page/section transition
400–600ms bila memang membantu.

### Easing
- Enter: ease-out.
- Exit: ease-in.

### Booking flow
Prioritaskan speed dan clarity. Hindari animation yang menghambat form completion, date selection, atau payment.

### Reduced motion
Animasi dekoratif harus dapat dikurangi/nonaktif saat `prefers-reduced-motion: reduce`.

---

## 12. Responsive Rules

### Mobile

Prioritas:

1. Search.
2. Room information.
3. Price.
4. Booking CTA.

### Desktop

Gunakan layout yang lebih spacious dengan maximum content width dan grid.

Jangan membuat mobile hanya sebagai versi desktop yang diperkecil.

---

## 13. Content & Copy Rules

Gunakan bahasa yang:

- jelas
- singkat
- reassuring
- tidak misleading

Hindari CTA generik seperti `Submit`.

Gunakan:

- `Search rooms`
- `Choose room`
- `Continue to guest details`
- `Proceed to payment`
- `View booking`

Harga harus transparan dan tidak menyembunyikan fee sampai tahap terakhir.

---

## 14. Component Layering

```text
UI primitives
├── Button
├── Input
├── Select
├── Dialog
├── Badge
└── DatePicker

Domain components
├── SearchWidget
├── RoomCard
├── PriceSummary
├── BookingStepper
├── ReservationStatus
└── ChatWidget

Page compositions
├── Landing
├── Room Detail
├── Booking
└── Admin Dashboard
```

Domain component tidak boleh memiliki business logic payment/authorization yang seharusnya berjalan di server.

---

## 15. Definition of Done — UI

Component dianggap selesai jika:

- Memiliki semua required states.
- Responsive.
- Keyboard accessible.
- Focus-visible.
- Menggunakan semantic token.
- Tidak memiliki magic color/spacing.
- Loading/error/empty state tersedia jika relevan.
- Reduced-motion dipertimbangkan untuk animation.
