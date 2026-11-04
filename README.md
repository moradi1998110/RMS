# نظام حجز وجبات الموظفين: قاعدة البيانات

هذا المجلد يحتوي على قاعدة بيانات Supabase والنواة المالية للتطبيق. لم تُبنَ واجهات Flutter بعد.

## المحتوى

| الملف | ما فيه |
|---|---|
| `supabase/migrations/..._schema.sql` | الجداول والقيود وحماية السجل المالي من التعديل |
| `supabase/migrations/..._rls.sql` | الصلاحيات حسب الدور |
| `supabase/migrations/..._wallet_booking.sql` | الشحن والحجز والإلغاء |
| `supabase/migrations/..._pickup_delegation.sql` | الاستلام والتخويل وتسوية الوجبات غير المستلمة |
| `supabase/migrations/..._scheduling_jobs.sql` | توليد الوجبات ورمضان والمهام الدورية |
| `supabase/migrations/..._series_cancel_and_horizon.sql` | الإلغاء المتكرر، والنشر حتى نهاية الشهر التالي، ومتابعة تعديلات المدير |
| `supabase/tests/` | اختبارات pgTAP |

## التشغيل

تعمل الاختبارات تلقائياً على GitHub Actions مع كل رفع إلى الريبو.

وللتشغيل على جهازك، تحتاج إلى Docker و[Supabase CLI](https://supabase.com/docs/guides/cli):

```bash
supabase start
```

```bash
supabase db reset
```

```bash
supabase test db
```

## الحسابات

- **أول أدمن:** يُنشأ مرة واحدة بالسكربت `scripts/bootstrap-admin.sh`، وتمرَّر قيمه عبر متغيرات البيئة ولا تُحفظ في الريبو. وبعده ينشئ الأدمن بقية الحسابات من التطبيق.
- **الدوال:** `create-user` و`reset-password` و`set-user-active`. وكلها للأدمن فقط، وتُرجع `create-user` و`reset-password` كلمة المرور المؤقتة مرة واحدة دون تخزينها.
- **تسجيل الدخول:** يكتب المستخدم اسمه فقط، ويحوّله التطبيق إلى `username@meals.invalid` قبل إرساله إلى Supabase Auth.
- **كلمة المرور المؤقتة:** إذا كان `must_change_password` مفعّلاً، يعرض التطبيق شاشة تغيير كلمة المرور، ثم يستدعي `mark_password_changed`.
- **الإنتاج:** يجب إيقاف التسجيل الذاتي في مشروع Supabase أيضاً، لأن `supabase/config.toml` لا يُطبَّق عليه إلا عبر `supabase config push`.

## للتطبيق: أخطاء الدوال

كل رفض يأتي برمز خطأ `P0001`، و`message` رمز ثابت مثل `insufficient_balance`، و`details` فيه تفاصيل بصيغة JSON مثل `shortfall`. ويحوّل التطبيق هذه الرموز إلى جمل عربية.

نتيجة مسح الباركود لا تأتي كخطأ، بل بالشكل `{ok, reason}`، لأن الرفض حالة عادية تُعرض لصاحب المطعم. والقيم الممكنة لـ`reason` هي: `wrong_restaurant` و`not_started` و`expired` و`already_picked_up` و`cancelled` و`invalid_token`.

يجب أن يرسل التطبيق مفتاح `p_key` جديداً (UUID) لكل ضغطة من المستخدم، وأن يعيد المفتاح نفسه عند إعادة المحاولة بسبب الشبكة.
