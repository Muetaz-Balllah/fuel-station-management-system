# دليل رفع النظام على الاستضافات المجانية

هذا الدليل يرفع **نظام إدارة محطة الوقود** باستخدام:

| الجزء | الخدمة | الدور |
|--------|--------|--------|
| واجهة الويب (Flutter Web) | **[Vercel](https://vercel.com/)** | المتصفح للمدير والمشغّل |
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
| رابط API العام | `https://fuel-station-api.onrender.com` | Vercel → `API_BASE_URL` + بناء الهاتف |
| رابط موقع الويب | `https://your-project.vercel.app` | Render (API) → `CORS_ORIGINS` |
| حسابات المنصات | GitHub للربط | Neon / Upstash / Render / Vercel |

قوالب المتغيرات:

- `backend/.env.production.example` — متغيرات خدمة API على Render
- `frontend/.env.deploy.example` — `API_BASE_URL` على Vercel
- `frontend/vercel.json` — إعداد بناء Flutter Web على Vercel
- `render.yaml` — Blueprint: API (Docker) فقط

---

## ترتيب التنفيذ (مهم)

1. **Neon** — PostgreSQL → `DATABASE_URL`
2. **Upstash** — Redis → `REDIS_URL`
3. **Render** — Web Service (Docker) للـ API + المتغيرات
4. **اختبار API** — `GET /api/v1/health`
5. **Vercel** — مشروع Flutter Web + `API_BASE_URL`
6. **Render (API)** — `CORS_ORIGINS` = رابط Vercel
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

- `Dockerfile` (جذر `fuel-station-management-system`) — ينسخ `backend/` ويبني الصورة
- `backend/start.sh` — يستمع على `0.0.0.0` والمنفذ **`PORT`** (Render يضبطه)
- `.dockerignore` (جذر المشروع)

### النشر (يدوي)

1. [https://dashboard.render.com](https://dashboard.render.com) → **New** → **Web Service** → Git.
2. **Runtime:** Docker
3. **Root Directory:** `fuel-station-management-system` (أو `.` إذا Git يبدأ من هذا المجلد)
4. **Dockerfile path:** `Dockerfile` (في الجذر، وليس داخل `backend/`)
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
| `CORS_ORIGINS` | مؤقتاً `*`؛ بعد نشر Vercel = رابط `*.vercel.app` |
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
CORS_ORIGINS=https://your-project.vercel.app
SEED_ON_STARTUP=false
```

### Health check

```text
https://YOUR-API.onrender.com/api/v1/health
```

المتوقع: `"status": "ok"`, `"database": "postgresql"`, `"redis": "ok"`, `"storage": "s3"`, `"storage_ok": "ok"`.

---

## 4) Vercel — Flutter Web

نعم، **Flutter Web** static يعمل على [Vercel](https://vercel.com/) (مثل أي موقع SPA).

**دليل مختصر خطوة بخطوة:** [`VERCEL_DEPLOY_AR.md`](VERCEL_DEPLOY_AR.md) (مهم: لا Next.js ولا `API_UPSTREAM`).

### الملفات في المشروع

| الملف | الغرض |
|--------|--------|
| `frontend/vercel.json` | أمر البناء + `build/web` + rewrite لـ SPA |
| `frontend/scripts/vercel_build.sh` | يستدعي `build_web.sh` (تنزيل Flutter إن لزم + `API_BASE_URL`) |

### النشر

1. [https://vercel.com](https://vercel.com) → **Add New Project** → GitHub.
2. **Root Directory:** `frontend` (أو `fuel-station-management-system/frontend`).
3. Framework Preset: **Other** (الإعدادات تُقرأ من `vercel.json`).
4. **Environment Variables** (Production):

| Key | Value |
|-----|--------|
| `API_BASE_URL` | `https://YOUR-API.onrender.com` (بدون `/` في النهاية) |

5. **Deploy**.

### SPA

`vercel.json` يوجّه كل المسارات إلى `index.html` حتى يعمل ت routing في Flutter.

### ما تحفظه

- رابط مثل: `https://your-project.vercel.app`

### بعد النشر

1. Render (API) → `CORS_ORIGINS=https://your-project.vercel.app`
2. أعد deploy للـ API على Render.

### بناء محلي + Vercel CLI (بديل)

```bash
cd frontend
flutter build web --release --dart-define=API_BASE_URL=https://YOUR-API.onrender.com
npx vercel deploy build/web --prod
```

### ملاحظات

- أول build على Vercel قد يستغرق وقتاً (clone Flutter SDK).
- كل **Redeploy** بعد تغيير `API_BASE_URL` يعيد بناء الويب بالعنوان الجديد.

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

### موقع الويب (Vercel)

- [ ] فتح `https://....vercel.app` — شاشة الدخول
- [ ] تسجيل دخول بدون أخطاء CORS (F12)

### الهاتف (اختياري)

- [ ] APK/IPA م built بـ `API_BASE_URL` الصحيح
- [ ] تسجيل دخول من الشبكة (Wi‑Fi / 4G)

### أمان

- [ ] `SEED_ON_STARTUP=false`
- [ ] `CORS_ORIGINS` = رابط Vercel فقط (ليس `*`)
- [ ] كلمات مرور seed تغيّرت

---

## 7) استكشاف الأخطاء

| العرض | الحل |
|--------|------|
| `redis: down` | `REDIS_URL` = `rediss://` من Upstash |
| CORS في المتصفح | `CORS_ORIGINS` = رابط Vercel كامل |
| الويب يتصل بـ localhost | أعد deploy Vercel مع `API_BASE_URL` |
| الهاتف لا يتصل | تحقق من HTTPS و URL وقت `flutter build` |
| Vercel build failed | راجع Build Logs؛ أو ابنِ web محلياً و `vercel deploy` |
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
| `Dockerfile` | Render Web Service (Docker) |
| `backend/.env.production.example` | متغيرات API |
| `render.yaml` | Blueprint: API فقط |
| `frontend/vercel.json` | استضافة Flutter Web |
| `frontend/scripts/vercel_build.sh` | بناء web على Vercel |
| `frontend/.env.deploy.example` | `API_BASE_URL` لـ Vercel |

مرجع إنجليزي مختصر: [`../DEPLOYMENT.md`](../DEPLOYMENT.md).
