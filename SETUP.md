# Al Ihsan Dairies — Supabase Setup

## 1. Run the schema
Supabase Dashboard → your project → **SQL Editor** → New query → paste the
entire contents of `supabase/schema.sql` → Run.

This creates `products` and `orders` tables, RLS policies, and two RPC
functions (`place_order`, `get_order_status`) that the site calls. It also
seeds one product row (Pure Desi Ghee, 3500 PKR/KG, 100 KG stock) — edit the
`stock` value in that seed insert first if your real stock is different, or
just update it later from the admin panel.

## 2. Create your admin login
Dashboard → **Authentication → Users → Add user**. Create yourself an
email + password. That's what you'll log into `admin.html` with — there's
no more hardcoded password.

## 3. Rotate your service_role key
You pasted it in this chat, which means it's now in plaintext in your
conversation history. Dashboard → **Settings → API → service_role** →
regenerate it.

**Nothing in this project uses the service_role key, and nothing should.**
There is no file to paste it into:
- `schema.sql` is run manually in the Dashboard SQL Editor, where you're
  already authenticated as the project owner — no key involved.
- `index.html`, `order-status.html`, and `admin.html` only use the **anon**
  key, which is safe to expose in client code because it can only act
  through RLS policies and the two RPCs (`place_order`, `get_order_status`).
- Admin access is controlled by Supabase Auth (login step 2), not by a key.

The service_role key bypasses RLS entirely and should only ever sit in a
trusted backend server. This project is static HTML with no backend, so
it has no legitimate place to go here — rotate it and don't reuse it in
this repo.

## 4. Update the placeholder domain
`index.html`, `sitemap.xml`, and `robots.txt` reference
`https://alihsandairies.com/` as a placeholder. Replace with your real
domain or GitHub Pages URL (e.g. `https://sheerazautomate.github.io/dairy/`).

## 5. Deploy
Push to GitHub as usual — GitHub Pages serves static files directly, no
build step needed.

## What changed
- Firebase (Firestore) removed entirely — no more Firebase scripts, config,
  or calls anywhere in the code.
- Orders now go through Supabase via the `place_order` RPC, which also
  atomically decrements stock and rejects the order if stock is insufficient.
- Admin panel (`admin.html`) uses real Supabase Auth instead of a hardcoded
  password shown in plaintext on the page.
- New `order-status.html` lets customers check their order status with just
  their order number + phone number (no login needed) — this calls a
  security-definer function that only returns limited fields, so customers
  can't browse each other's orders or see other people's addresses.
- Admin panel gained: search (name/contact/order #), status filter, live
  stats (total/active/today/revenue), and inline price/stock editing.
- 3D hero animation now skips on mobile / small screens / reduced-motion,
  and loads after first paint instead of blocking page load — should
  meaningfully help mobile load time.
- Added Product JSON-LD, Open Graph tags, robots.txt, sitemap.xml.
