# إعداد أداة تحليل السوق (PriceBuddy)

## 1) تشغيل PriceBuddy على VPS
```bash
mkdir pricebuddy && cd pricebuddy
wget https://raw.githubusercontent.com/jez500/pricebuddy/main/docker-compose.yml
touch .env
docker compose up -d
```
ادخل `http://SERVER:8080` وغيّر بيانات الدخول فوراً، ثم ضع دومين + HTTPS.
أنشئ API Token من قائمة المستخدم > API tokens.

## 2) أسرار Supabase Edge Function
في مشروع Supabase → Edge Functions → Secrets أضف:
- `PRICEBUDDY_BASE_URL` = `https://pb.yourdomain.com/api` (بدون شرطة أخيرة)
- `PRICEBUDDY_API_TOKEN` = التوكن الذي أنشأته

## 3) نشر الدالة
```bash
supabase functions deploy market-prices
```

## 4) الاستخدام داخل الموقع
- القائمة: **الأسعار والكتالوج → تحليل السوق**
- الصلاحية: `catalog_view` أو `catalog_manage` (أو مدير/مالك/أدمن)
- أضف موديلات في PriceBuddy بوسم `جديد` أو `مستعمل` مع روابط الإعلانات.

## 5) اختبار
1. سجّل دخولاً كموظف مخوّل.
2. افتح «تحليل السوق».
3. اضغط «تحديث الآن».
4. انقر صفاً لإضافة رابط مراقبة.
