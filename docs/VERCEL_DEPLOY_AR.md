# رفع واجهة Flutter Web على Vercel (مشروع محطة الوقود)

هذا الدليل **لمشروعك الحالي (Flutter)** — وليس لمشروع Next.js.

| تعليمات قديمة (لا تستخدمها هنا) | مشروعك الآن |
|----------------------------------|-------------|
| Framework: **Next.js** | **Other / Flutter** (من `vercel.json`) |
| `API_UPSTREAM` + proxy على Vercel | **`API_BASE_URL`** — المتصفح يتصل مباشرة بـ Render |
| `npm run build` | **`bash scripts/vercel_build.sh`** → `flutter build web` |

خطأ البناء الذي ظهر (`Next.js`, `useSearchParams`, `/client/coverage`) يعني أن Vercel بنى **تطبيق Next.js** في مجلد `frontend` — هذا **ليس** واجهة Flutter لهذا المشروع.

---

## قبل Vercel

1. ارفع الكود إلى GitHub (مجلد `fuel-station-management-system` أو الجذر الذي فيه `frontend/pubspec.yaml`).
2. تأكد أن خدمة **API على Render** تعمل:  
   `https://YOUR-API.onrender.com/api/v1/health`

---

## خطوات Vercel (اتبعها بالترتيب)

1. افتح [https://vercel.com](https://vercel.com) → سجّل بـ **GitHub**.
2. **Add New… → Project** → اختر المستودع الصحيح (**مشروع محطة الوقود**، وليس repo آخر فيه Next.js فقط).
3. **قبل Deploy** — الإعدادات:

| الإعداد | القيمة |
|---------|--------|
| **Root Directory** | `frontend` أو `fuel-station-management-system/frontend` (المجلد الذي فيه `pubspec.yaml` و `vercel.json`) |
| **Framework Preset** | **Other** (لا تختر Next.js) |
| Build Command | يُقرأ من `vercel.json`: `bash scripts/vercel_build.sh` |
| Output Directory | `build/web` |

4. **Environment Variables** (Production — متغير **واحد** مطلوب للبناء):

| Name | Value |
|------|--------|
| `API_BASE_URL` | `https://YOUR-API.onrender.com` **بدون** `/` في النهاية |

> **لا** تضف `API_UPSTREAM` — غير مستخدم في Flutter.

5. **Deploy** وانتظر (أول مرة قد تأخذ 5–15 دقيقة بسبب تنزيل Flutter SDK).
6. افتح رابط الموقع (`https://….vercel.app`) → جرّب **تسجيل الدخول**.  
   أول طلب API قد يتأخر إذا كان Render في وضع السكون.

---

## بعد نجاح Vercel

1. انسخ رابط الموقع، مثل: `https://your-project.vercel.app`
2. في **Render → Web Service (API) → Environment**:
   ```env
   CORS_ORIGINS=https://your-project.vercel.app
   ```
3. أعد **Deploy** للـ API على Render.
4. (موصى به) `SEED_ON_STARTUP=false` بعد أول تجربة ناجحة.

---

## إذا فشل البناء مرة أخرى

| في السجل | السبب | الحل |
|----------|--------|------|
| `npm install`, `next build`, `Next.js` | Vercel يظن المشروع Next.js | Root Directory = مجلد Flutter؛ Framework = Other؛ وجود `vercel.json` |
| `set API_BASE_URL` / build failed فوراً | متغير ناقص | أضف `API_BASE_URL` في Vercel ثم Redeploy |
| `git clone flutter` failed | شبكة | Redeploy أو ابنِ محلياً (أسفل) |

### بناء محلي ثم رفع (بديل)

```bash
cd frontend
flutter pub get
flutter build web --release --dart-define=API_BASE_URL=https://YOUR-API.onrender.com
npx vercel deploy build/web --prod
```

---

## ملخص الملفات في الم repo

- `frontend/vercel.json` — يمنع اعتماد Next.js (`"framework": null`)
- `frontend/scripts/vercel_build.sh` — بنية Flutter Web
- `frontend/lib/core/networking/api_config.dart` — يقرأ `API_BASE_URL` وقت البناء

Backend + Neon + Upstash + S3: [`FREE_HOSTING_GUIDE_AR.md`](FREE_HOSTING_GUIDE_AR.md).
