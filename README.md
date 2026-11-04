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
| `supabase/tests/core.test.sql` | اختبارات pgTAP |

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

## للتطبيق: أخطاء الدوال

كل رفض يأتي برمز خطأ `P0001`، و`message` رمز ثابت مثل `insufficient_balance`، و`details` فيه تفاصيل بصيغة JSON مثل `shortfall`. ويحوّل التطبيق هذه الرموز إلى جمل عربية.

نتيجة مسح الباركود لا تأتي كخطأ، بل بالشكل `{ok, reason}`، لأن الرفض حالة عادية تُعرض لصاحب المطعم. والقيم الممكنة لـ`reason` هي: `wrong_restaurant` و`not_started` و`expired` و`already_picked_up` و`cancelled` و`invalid_token`.

يجب أن يرسل التطبيق مفتاح `p_key` جديداً (UUID) لكل ضغطة من المستخدم، وأن يعيد المفتاح نفسه عند إعادة المحاولة بسبب الشبكة.
