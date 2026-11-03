# دليل رفع النظام على الاستضافات المجانية

هذا الدليل يرفع **نظام إدارة محطة الوقود** باستخدام:

| الجزء | الخدمة | الدور |
|--------|--------|--------|
| واجهة الويب (Flutter Web) | **Render** (Static Site) | المتصفح للمدير والمشغّل |
| خادم API (FastAPI) | **Render** (Docker Web Service) | منطق النظام و REST API |
| قاعدة البيانات | **Neon** | PostgreSQL |
| جلسات تسجيل الدخول | **Upstash** | Redis |
| تطبيق الهاتف (Android/iOS) | **لا استضافة** | يُثبَّت على الجهاز ويتصل مباشرة بـ API على Render |

> **Flutter على الهاتف:** التطبيق native (APK / IPA / desktop) **لا يُرفع** على Render. تبنيه محلياً أو عبر CI وتثبّته على الأجهزة؛ يكفي أن يعرف عنوان الـ API (`API_BASE_URL`) وقت البناء.

---

## ما الذي تحتاج حفظه؟ (سجلّ أسرارك)

أنشئ ملفاً **خاصاً عندك** ولا ترفعه إلى Git:

| البند | مثال | أين تُستخدم |
|--------|------|-------------|
| `DATABASE_URL` | `postgresql://...@ep-xxx.neon.tech/neondb?sslmode=require` | Render (API) |
| `REDIS_URL` | `rediss://default:...@xxx.upstash.io:6379` | Render (API) |
| مفاتيح S3 | `AWS_ENDPOINT_URL_S3`, `S3_BUCKET`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | Render (API) |
| `JWT_SECRET` | 32+ حرف عشوائي | Render (API) |
| كلمات مرور seed (اختياري) | `SEED_*_PASSWORD` | Render (API) |
| رابط API العام | `https://fuel-station-api.onrender.com` | Static Site → `API_BASE_URL` + بناء الهاتف |
| رابط موقع الويب | `https://fuel-station-web.onrender.com` | Render (API) → `CORS_ORIGINS` |
| حسابات المنصات | GitHub للربط | Neon / Upstash / Render |

قوالب المتغيرات:

- `backend/.env.production.example` — متغيرات خدمة API على Render
- `frontend/.env.deploy.example` — `API_BASE_URL` لموقع Flutter
- `render.yaml` — Blueprint: API (Docker) + Flutter Web (static)

---

## ترتيب التنفيذ (مهم)

1. **Neon** — PostgreSQL → `DATABASE_URL`
2. **Upstash** — Redis → `REDIS_URL`
3. **Render** — Web Service (Docker) للـ API + المتغيرات
4. **اختبار API** — `GET /api/v1/health`
5. **Render** — Static Site لـ Flutter Web + `API_BASE_URL`
6. **Render (API)** — `CORS_ORIGINS` = رابط موقع Flutter
7. **(اختياري)** بناء APK/IPA للهاتف بنفس `API_BASE_URL`
8. **اختبار نهائي** — متصفح + هاتف

---

## 1) Neon — PostgreSQL

1. [https://neon.tech](https://neon.tech) → **New Project**.
2. **Connection details** → انسخ **Connection string** (يفضّل **Pooled**).
3. احفظها كـ **`DATABASE_URL`** في Render (صيغة `postgresql://...` مقبولة؛ التطبيق يحوّلها لـ psycopg).

**ملاحظة:** الخطة المجانية قد توقف DB بعد خمول؛ أول طلب قد يكون أبطأ.

---

## 2) Upstash — Redis (الجلسات)

1. [https://upstash.com](https://upstash.com) → **Create database**.
2. انسخ **Redis URL** (`rediss://...`) — **ليس** REST فقط.
3. ضعه في Render (خدمة API) كـ **`REDIS_URL`**.

---

## 3) Render — FastAPI (Docker Web Service)

### الملفات في المشروع

- `backend/Dockerfile` — صورة Python + `uvicorn`
- `backend/start.sh` — يستمع على `0.0.0.0` والمنفذ **`PORT`** (Render يضبطه)
- `backend/.dockerignore`

### النشر (يدوي)

1. [https://dashboard.render.com](https://dashboard.render.com) → **New** → **Web Service** → Git.
2. **Runtime:** Docker
3. **Root Directory:** `backend` (إذا جذر Git هو `fuel-station-management-system`)
4. **Dockerfile path:** `Dockerfile`
5. **Health Check Path:** `/api/v1/health`
6. **Instance type:** Free (إن وُجد)

### النشر (Blueprint)

**New** → **Blueprint** → الم repo يقرأ **`render.yaml`** (خدمة `fuel-station-api` + موقع Flutter).

### متغيرات البيئة

من `backend/.env.production.example` — كلها في **Environment** لخدمة API:

| المتغير | ملاحظة |
|---------|--------|
| `DATABASE_URL` | Neon |
| `REDIS_URL` | Upstash |
| `JWT_SECRET` | 32+ حرف |
| `AUTO_CREATE_TABLES` | `true` |
| `SEED_ON_STARTUP` | `true` أول مرة، ثم `false` |
| `CORS_ORIGINS` | مؤقتاً `*`؛ بعد نشر Flutter = رابط Static Site |
| `AWS_ENDPOINT_URL_S3` | S3-compatible |
| `S3_BUCKET` | اسم الـ bucket |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | مفاتيح التخزين |
| `S3_PREFIX` | اختياري (`images`) |
| `S3_PUBLIC_BASE_URL` | اختياري |

**تخزين الصور:** على Render القرص مؤقت — فعّل S3 في الإنتاج.

**أول نشر:**

```env
CORS_ORIGINS=*
SEED_ON_STARTUP=true
```

**بعد نشر Flutter Web:**

```env
CORS_ORIGINS=https://fuel-station-web.onrender.com
SEED_ON_STARTUP=false
```

### Health check

```text
https://YOUR-API.onrender.com/api/v1/health
```

المتوقع: `"status": "ok"`, `"database": "postgresql"`, `"redis": "ok"`, `"storage": "s3"`, `"storage_ok": "ok"`.

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
3. عند إنشاء الخدمة، أضف **`API_BASE_URL`** = رابط API على Render (بدون `/` في النهاية).

### الطريقة ب — يدوياً من لوحة Render

1. **New** → **Static Site** → Git repo.
2. **Root Directory:** `frontend` (أو `fuel-station-management-system/frontend` حسب جذر Git).
3. **Build Command:** `bash scripts/render_build.sh`
4. **Publish Directory:** `build/web`
5. **Environment Variables:**

| Key | Value |
|-----|--------|
| `API_BASE_URL` | `https://YOUR-API.onrender.com` |

6. **Create Static Site**.

### SPA (توجيه المسارات)

السكربت يضيف `build/web/_redirects` و`render.yaml` يعرّف rewrite إلى `index.html`.

### ما تحفظه

- URL مثل: `https://fuel-station-web.onrender.com`

### بعد النشر

1. خدمة API على Render → `CORS_ORIGINS=https://your-flutter-site.onrender.com`
2. **Manual Deploy** أو push لإعادة تشغيل API إن لزم.

### بناء محلي (إذا فشل البناء على Render أو كان بطيئاً)

```bash
cd frontend
flutter pub get
flutter build web --release --dart-define=API_BASE_URL=https://YOUR-API.onrender.com
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

نفس عنوان API على Render يُمرَّر وقت البناء:

```bash
cd frontend
flutter build apk --release --dart-define=API_BASE_URL=https://YOUR-API.onrender.com
```

أو iOS:

```bash
flutter build ipa --release --dart-define=API_BASE_URL=https://YOUR-API.onrender.com
```

ثبّت الملف على الجهاز (USB، TestFlight، Google Play internal، إلخ).

### CORS و الهاتف

**CORS** يخص المتصفح فقط. تطبيق Flutter على Android/iOS **لا يستخدم CORS**؛ يكفي أن الـ API على Render متاح عبر HTTPS.

### تطوير يومي على الهاتف

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.x.x:8000
```

(شبكة محلية + API يعمل على جهازك أو على Render.)

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
| `storage_ok: down` | تحقق من S3 bucket والمفاتيح و`AWS_ENDPOINT_URL_S3` |
| صور لا تظهر | health للتخزين؛ أو `S3_PUBLIC_BASE_URL` / مسار `/api/v1/media/` |

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
| `backend/Dockerfile` | Render Web Service (Docker) |
| `backend/.env.production.example` | متغيرات API |
| `render.yaml` | Blueprint: API + Static Site |
| `frontend/scripts/render_build.sh` | بناء Flutter Web |
| `frontend/.env.deploy.example` | `API_BASE_URL` لـ Render |

مرجع إنجليزي مختصر: [`../DEPLOYMENT.md`](../DEPLOYMENT.md).
