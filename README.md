# Smart Canteen Cloud System (UCS531)

**Cloud-Based Meal Demand Prediction & Food Wastage Analytics System**

- **Live Deployment:** [https://precious-cascaron-b7b473.netlify.app/](https://precious-cascaron-b7b473.netlify.app/)
- **Course:** UCS531 — Cloud Computing
- **Faculty Advisor:** Ms. Ishani Rana
- **Team Members:**
  - Priyancy Ajmani (`1024031064`)
  - Deepansh Mehta (`1024030610`)
  - Gurman Singh (`1024031074`)

---

## 1. Overview & Problem Statement
Campus canteens often over-prepare or under-prepare daily meals due to lack of advance student demand visibility. **Smart Canteen Cloud** solves this using a 3-tier cloud architecture where students pre-book meals before the 11:30 AM cutoff, and a serverless cloud database function predicts optimal kitchen preparation quantities.

## 2. Cloud Architecture
1. **Presentation Tier (Netlify Global CDN):** Responsive frontend built with HTML5, Tailwind CSS, Vanilla JavaScript, and Chart.js served over HTTPS.
2. **Serverless Compute Tier (Supabase PostgreSQL RPC):** `run_demand_prediction(target_date)` executes server-side demand forecasting without dedicated backend VMs.
3. **Managed Data Tier (Supabase PostgreSQL — `ap-south-1`):** Normalized 3-table schema (`menu_items`, `meal_preferences`, `daily_records`) with composite unique constraints (`student_roll, menu_item_id, meal_date`) for idempotent `UPSERT` operations.

## 3. Demand Prediction Formula
```text
Predicted_Demand = ROUND(0.70 × Current_Student_Preferences + 0.30 × Historical_Daily_Average)
```
- **70% Live Preferences:** Captures same-day student demand shifts.
- **30% Historical Average:** Buffers for walk-in students who do not pre-book.

## 4. Repository Structure
```text
smart-canteen-cloud-repo/
├── index.html                                    # Complete SPA (Student Portal, Admin & Prediction, Analytics)
├── config.js                                     # Cloud configuration (Supabase endpoint, cutoff time, team metadata)
├── vercel.json                                   # Static hosting configuration
├── 01_supabase_schema_and_seed.sql           # PostgreSQL tables, constraints, RLS policies & RPC function
├── index.ts                                  # Deno Edge Function alternative for demand prediction
└── README.md                                     # Project documentation & setup guide
```

## 5. Setup & Deployment Instructions
1. Create a free project on [Supabase](https://supabase.com) and execute `sql/01_supabase_schema_and_seed.sql` in the SQL Editor.
2. Add your `SUPABASE_URL` and `SUPABASE_ANON_KEY` in `config.js`.
3. Deploy the root folder to **Netlify** (or Vercel) for global HTTPS CDN hosting.
4. Use Admin PIN `admin123` to unlock the **Admin & Prediction** dashboard.
