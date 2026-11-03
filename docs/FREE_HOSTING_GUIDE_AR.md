# دليل رفع النظام على الاستضافات المجانية

هذا الدليل يرفع **نظام إدارة محطة الوقود** باستخدام:

| الجزء | الخدمة | الدور |
|--------|--------|--------|
| واجهة الويب (Flutter Web) | **Render** | المتصفح للمدير والمشغّل |
| خادم API (FastAPI) | **Koyeb** | منطق النظام و REST API |
| قاعدة البيانات | **Neon** | PostgreSQL |
| جلسات تسجيل الدخول | **Upstash** | Redis |
| تطبيق الهاتف (Android/iOS) | **لا استضافة** | يُثبَّت على الجهاز ويتصل مباشرة بـ API على Koyeb |

> **Flutter على الهاتف:** التطبيق native (APK / IPA / desktop) **لا يُرفع** على Render. تبنيه محلياً أو عبر CI وتثبّته على الأجهزة؛ يكفي أن يعرف عنوان الـ API (`API_BASE_URL`) وقت البناء.

---

## ما الذي تحتاج حفظه؟ (سجلّ أسرارك)

أنشئ ملفاً **خاصاً عندك** ولا ترفعه إلى Git:

| البند | مثال | أين تُستخدم |
|--------|------|-------------|
| `DATABASE_URL` | `postgresql://...@ep-xxx.neon.tech/neondb?sslmode=require` | Koyeb |
| `REDIS_URL` | `rediss://default:...@xxx.upstash.io:6379` | Koyeb |
| `JWT_SECRET` | 32+ حرف عشوائي | Koyeb |
| كلمات مرور seed (اختياري) | `SEED_*_PASSWORD` | Koyeb |
| رابط API العام | `https://xxx.koyeb.app` | Render → `API_BASE_URL` + بناء تطبيق الهاتف |
| رابط موقع الويب | `https://xxx.onrender.com` | Koyeb → `CORS_ORIGINS` |
| حسابات المنصات | GitHub للربط | Neon / Upstash / Koyeb / Render |

قوالب المتغيرات:

- `backend/.env.production.example` — Koyeb
- `frontend/.env.deploy.example` — Render (`API_BASE_URL`)
- `render.yaml` — Blueprint لموقع Flutter Web (اختياري من لوحة Render)

---

## ترتيب التنفيذ (مهم)

1. **Neon** — PostgreSQL → `DATABASE_URL`
2. **Upstash** — Redis → `REDIS_URL`
3. **Koyeb** — FastAPI + المتغيرات
4. **اختبار API** — `GET /api/v1/health`
5. **Render** — Static Site لـ Flutter Web + `API_BASE_URL`
6. **Koyeb** — `CORS_ORIGINS` = رابط Render
7. **(اختياري)** بناء APK/IPA للهاتف بنفس `API_BASE_URL`
8. **اختبار نهائي** — متصفح + هاتف

---

## 1) Neon — PostgreSQL

1. [https://neon.tech](https://neon.tech) → **New Project**.
2. **Connection details** → انسخ **Connection string** (يفضّل **Pooled**).
3. احفظها كـ **`DATABASE_URL`** في Koyeb (صيغة `postgresql://...` مقبولة؛ التطبيق يحوّلها لـ psycopg).

**ملاحظة:** الخطة المجانية قد توقف DB بعد خمول؛ أول طلب قد يكون أبطأ.

---

## 2) Upstash — Redis (الجلسات)

1. [https://upstash.com](https://upstash.com) → **Create database**.
2. انسخ **Redis URL** (`rediss://...`) — **ليس** REST فقط.
3. ضعه في Koyeb كـ **`REDIS_URL`**.

---

## 3) Koyeb — FastAPI

### الملفات في المشروع

- `backend/Dockerfile`
- `backend/.dockerignore`

### النشر

1. [https://www.koyeb.com](https://www.koyeb.com) → **Create App** → Git.
2. **Docker** — Dockerfile: `backend/Dockerfile` (أو build context = `backend`).
3. **Free** instance (512 MB).

### متغيرات البيئة

من `backend/.env.production.example`:

| المتغير | ملاحظة |
|---------|--------|
| `DATABASE_URL` | Neon |
| `REDIS_URL` | Upstash |
| `JWT_SECRET` | 32+ حرف |
| `AUTO_CREATE_TABLES` | `true` |
| `SEED_ON_STARTUP` | `true` أول مرة، ثم `false` |
| `CORS_ORIGINS` | مؤقتاً `*`؛ بعد Render = رابط الموقع |

**أول نشر:**

```env
CORS_ORIGINS=*
SEED_ON_STARTUP=true
```

**بعد Render:**

```env
CORS_ORIGINS=https://your-service.onrender.com
SEED_ON_STARTUP=false
```

### Health check

```text
https://YOUR-KOYEB-URL/api/v1/health
```

المتوقع: `"status": "ok"`, `"database": "postgresql"`, `"redis": "ok"`.

---

## 4) Render — Flutter Web (Static Site)

### الملفات في المشروع

| الملف | الغرض |
|--------|--------|
| `render.yaml` | Blueprint (Static Site + rewrite للـ SPA) |
| `frontend/scripts/render_build.sh` | تثبيت Flutter (إن لزم) + `flutter build web` + `_redirects` |

### الطريقة أ — Blueprint

1. [https://dashboard.render.com](https://dashboard.render.com) → **New** → **Blueprint**.
2. اربط الم repo؛ Render يقرأ **`render.yaml`** من الجذر (`fuel-station-management-system/render.yaml`).
3. عند إنشاء الخدمة، أضف **`API_BASE_URL`** = رابط Koyeb (بدون `/` في النهاية).

### الطريقة ب — يدوياً من لوحة Render

1. **New** → **Static Site** → Git repo.
2. **Root Directory:** `frontend` (أو `fuel-station-management-system/frontend` حسب جذر Git).
3. **Build Command:** `bash scripts/render_build.sh`
4. **Publish Directory:** `build/web`
5. **Environment Variables:**

| Key | Value |
|-----|--------|
| `API_BASE_URL` | `https://YOUR-KOYEB-URL` |

6. **Create Static Site**.

### SPA (توجيه المسارات)

السكربت يضيف `build/web/_redirects` و`render.yaml` يعرّف rewrite إلى `index.html`.

### ما تحفظه

- URL مثل: `https://fuel-station-web.onrender.com`

### بعد النشر

1. Koyeb → `CORS_ORIGINS=https://your-service.onrender.com`
2. أعد نشر Koyeb إن لزم.

### بناء محلي (إذا فشل البناء على Render أو كان بطيئاً)

```bash
cd frontend
flutter pub get
flutter build web --release --dart-define=API_BASE_URL=https://YOUR-KOYEB-URL
echo /*    /index.html   200 > build/web/_redirects
```

ثم ارفع مجلد `build/web` عبر Render **Manual Deploy** أو Git مع أ artefact — أو غيّر Build Command مؤقتاً لنسخ مخرجات جاهزة (الطريقة المعتادة تبقى السكربت على Render).

### ملاحظات Render المجانية

- Static Sites على الخطة المجانية مناسبة للعرض والتجربة.
- أول build قد يستغرق وقتاً (تنزيل Flutter SDK).
- الخدمات المجانية قد «تنام»؛ أول زيارة للموقع قد تأخذ ثوانٍ.

---

## 5) تطبيق Flutter على الهاتف (بدون استضافة)

لا حاجة لـ Render أو أي static host للـ APK/IPA.

### اتصال التطبيق بالـ API

نفس عنوان Koyeb يُمرَّر وقت البناء:

```bash
cd frontend
flutter build apk --release --dart-define=API_BASE_URL=https://YOUR-KOYEB-URL
```

أو iOS:

```bash
flutter build ipa --release --dart-define=API_BASE_URL=https://YOUR-KOYEB-URL
```

ثبّت الملف على الجهاز (USB، TestFlight، Google Play internal، إلخ).

### CORS و الهاتف

**CORS** يخص المتصفح فقط. تطبيق Flutter على Android/iOS **لا يستخدم CORS**؛ يكفي أن الـ API متاح عبر HTTPS وأن Koyeb يقبل الطلبات.

### تطوير يومي على الهاتف

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.x.x:8000
```

(شبكة محلية + API يعمل على جهازك أو Koyeb.)

---

## 6) الاختبار النهائي (checklist)

### API

- [ ] `/api/v1/health` → ok + postgresql + redis ok

### موقع الويب (Render)

- [ ] فتح `https://....onrender.com` — شاشة الدخول
- [ ] تسجيل دخول بدون أخطاء CORS (F12)

### الهاتف (اختياري)

- [ ] APK/IPA م built بـ `API_BASE_URL` الصحيح
- [ ] تسجيل دخول من الشبكة (Wi‑Fi / 4G)

### أمان

- [ ] `SEED_ON_STARTUP=false`
- [ ] `CORS_ORIGINS` = رابط Render فقط (ليس `*`)
- [ ] كلمات مرور seed تغيّرت

---

## 7) استكشاف الأخطاء

| العرض | الحل |
|--------|------|
| `redis: down` | `REDIS_URL` = `rediss://` من Upstash |
| CORS في المتصفح | `CORS_ORIGINS` = رابط Render كامل |
| الويب يتصل بـ localhost | أعد deploy Render مع `API_BASE_URL` |
| الهاتف لا يتصل | تحقق من HTTPS و URL وقت `flutter build` |
| Render build failed | راجع Logs؛ أو ابنِ web محلياً |
| Neon بطيء أول طلب | cold start — أعد المحاولة |

---

## 8) تطوير محلي

```bash
cd backend
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
uvicorn main:app --reload
```

```bash
cd frontend
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

---

## ملخص ملفات الرفع

| الملف | الغرض |
|--------|--------|
| `backend/Dockerfile` | Koyeb |
| `backend/.env.production.example` | متغيرات Koyeb |
| `render.yaml` | Render Static Site |
| `frontend/scripts/render_build.sh` | بناء Flutter Web |
| `frontend/.env.deploy.example` | `API_BASE_URL` لـ Render |

مرجع إنجليزي مختصر: [`../DEPLOYMENT.md`](../DEPLOYMENT.md).
