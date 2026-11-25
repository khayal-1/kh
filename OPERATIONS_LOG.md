# سجل التشغيل والنشر — Khayal Motors
# Operations log and deployment runbook — Khayal Motors

> يُحدَّث هذا السجل عند كل خطوة تخص هذا الطلب. لا يثبت سجلّ الأوامر وحده نجاح النشر؛ يجب توثيق إيصال أو فحص حي. لا تُدرج أي أسرار أو كلمات مرور أو رموز وصول.
>
> Update this log for each step in this request. A command log alone does not prove deployment; record a receipt or live check. Never include secrets, passwords, or access tokens.

## النطاق / Scope

- المطلوب: إنشاء حسابات الموظفين من داخل لوحة المدير فقط، مع إدخال كلمة مرور وتأكيدها وحفظ ملف الموظف وصلاحياته.
- Requested: create staff accounts inside the manager dashboard only, with password and confirmation fields and reliable saving of employee profile and permissions.
- واجهة الموقع مستضافة عبر GitHub Pages وفق إعداد Pages الحي: `https://khayal-1.github.io/elkhayal-motors/`، المصدر `main` في جذر المستودع. لا يُستخدم Vercel لهذا النشر.
- Live GitHub Pages configuration reports `https://khayal-1.github.io/elkhayal-motors/`, source branch `main`, repository root. Vercel is not the frontend deployment target.
- Supabase project: `ztkiavqmbswyxkmddtno` (`El Khayal Motors Website`).

## الحالة الحالية / Current status

- [x] كود واجهة المدير ودالة `manage-staff` موجودان محليًا على فرع `feature/manager-staff-accounts`؛ الأساس السابق `c0cc8a1` منشور على هذا الفرع. تغييرات العمل الإضافية الحالية لم تُرفع إلى `main`.
- [x] Manager UI and `manage-staff` source are present locally on `feature/manager-staff-accounts`; the earlier base commit `c0cc8a1` is on that branch. Current working changes have not been pushed to `main`.
- [x] إعداد GitHub Pages الحي جرى التحقق منه عبر GitHub API؛ `build_type=legacy`, source `main:/`.
- [x] Live GitHub Pages settings were checked through GitHub API: legacy build, source `main:/`.
- [x] نُشرت دالة `manage-staff` من محرر Supabase في المشروع الصحيح؛ القائمة الحية تعرض الآن `manage-staff` و`telegram-photo-upload`. إعداد Verify JWT بقي مفعّلًا؛ لم تُنشأ حسابات ولم يُنفذ SQL جديد.
- [x] `manage-staff` was deployed from Supabase’s editor to the correct project; the live list now shows `manage-staff` and `telegram-photo-upload`. Verify JWT remained enabled; no employee accounts were created and no SQL was run.
- [ ] واجهة الموظفين لم تُنشر بعد إلى GitHub Pages. أُضيف workflow لبناء Vite والنشر إلى Pages، وضُبطت متغيرات إعداد Supabase العامة على المستودع؛ بناء محلي بالقيم الحية نجح ويُنتج روابط `/elkhayal-motors/`. ما زال يلزم نشر هذا التغيير إلى `main` وتفعيل مصدر Pages عبر GitHub Actions ثم فحص الموقع الحي.
- [ ] The staff UI is not yet published to GitHub Pages. A Vite build-and-deploy workflow was added and the repository’s public Supabase build variables were configured; a local build with the live values passed and emitted `/elkhayal-motors/` asset paths. The remaining release is to publish the workflow/code to `main`, switch Pages to GitHub Actions, then verify the live site.
- لا تُنشأ حسابات موظفين أثناء النشر أو الاختبار.
- Do not create employee accounts during deployment or testing.

## تغييرات قاعدة البيانات / Database migrations

| الملف / File | وجوده في المستودع / Repository | الحالة / Status |
|---|---|---|
| `supabase/migrations/202611210001_initial_foundation.sql` | متتبَّع في الفرع الأساسي / tracked in base branch | وجود الملف مؤكد؛ حالة تطبيقه لم تُتحقق في هذه الخطوة / file confirmed; application status not verified in this task |
| `supabase/migrations/202611210002_customer_requests_no_delete.sql` | متتبَّع / tracked | سبق تأكيد تطبيقه في مراجعة التشغيل، لكن لم يُعَد فحص سجل الترحيلات الحي هنا / previously recorded as applied; migration ledger not rechecked here |
| `supabase/migrations/202611210003_least_privilege_catalog_and_requests.sql` | متتبَّع / tracked | سبق تأكيد تطبيقه في مراجعة التشغيل، لكن لم يُعَد فحص سجل الترحيلات الحي هنا / previously recorded as applied; migration ledger not rechecked here |
| `supabase/migrations/202611210005_manager_staff_permissions.sql` | ملف محلي غير متتبَّع حاليًا / currently untracked local file | لا يوجد إثبات أنه طُبّق؛ لا تشغّله تلقائيًا ولا تعتبره مطبقًا / no evidence it was applied; do not run automatically or treat it as applied |

ملاحظة: وجود جدول `employee_permissions` وسياسات مرتبطة به ظهر في مراجعة سابقة، لكن لا يثبت ذلك أن ملف `202611210005_manager_staff_permissions.sql` بعينه طُبّق بالكامل. قبل أي ترحيل إضافي، افحص قاعدة المشروع وسجل الترحيلات لتجنب إعادة التطبيق أو تعارضه.

Note: a prior live review saw the `employee_permissions` table and related policies, but that does not prove this exact `202611210005_manager_staff_permissions.sql` file was fully applied. Inspect the project schema and migration ledger before any additional migration to avoid duplicate or conflicting changes.

## سجل الأوامر / Command record

### أوامر تحقق نُفذت / Verification commands executed

- `git remote -v` — نُفّذ؛ أظهر `origin` إلى `https://github.com/khayal-1/elkhayal-motors.git`.
- `git status --short --branch` — نُفّذ؛ أظهر تغييرات محلية غير ملتزمة وملف الترحيل 005 غير متتبَّع.
- `git branch -a` — نُفّذ؛ أظهر الفرع الحالي `feature/manager-staff-accounts` ووجود `main`.
- `git log --oneline --decorate -8` — نُفّذ؛ أظهر `c0cc8a1` على فرع الميزة والقاعدة المحلية `3dcaa30`؛ هذه ليست وحدها إثباتًا لحالة الخادم الأحدث.
- `git ls-remote --heads origin` — نُفّذ؛ أظهر الفرع البعيد `feature/manager-staff-accounts` عند `c0cc8a1` والفرع البعيد `main` عند `21bbebe348e09da4f933bcd921f74567ffb4a1e9`.
- `gh api repos/khayal-1/elkhayal-motors/pages` — نُفّذ؛ أكد عنوان GitHub Pages ومصدر `main:/`.
- `gh api repos/khayal-1/elkhayal-motors/contents/.github/workflows` — نُفّذ؛ أعاد 404، ولم يظهر مجلد workflow عبر هذا المسار.
- `npm run build` — نُفّذ على فرع الميزة؛ نجح Vite build وأنشأ `dist/`.
- `deno check supabase/functions/manage-staff/index.ts` — نُفّذ؛ اكتمل دون أخطاء فحص.
- `curl -sSIL --max-time 20 https://khayal-1.github.io/elkhayal-motors/` — نُفّذ؛ أعاد HTTP 200 من GitHub Pages.
- `curl -fsSL --max-time 20 https://khayal-1.github.io/elkhayal-motors/` — نُفّذ؛ أعاد HTML يحمّل `app.js` مباشرة.
- `curl -fsSL --max-time 20 https://khayal-1.github.io/elkhayal-motors/app.js` — نُفّذ؛ أظهر أن الملف الحي يستورد `./src/supabase.js`.
- `git show main:src/supabase.js` — نُفّذ؛ أظهر اعتماد الحزمة على متغيرات `import.meta.env` واستيراد `@supabase/supabase-js`؛ لم يُبنَ هذا المسار عبر Vite في إعداد Pages الحالي حسب إعداد legacy الموثق.
- `git add OPERATIONS_LOG.md` و`git diff --cached --check` — نُفّذا؛ التحقق من المسافات/التنسيق نجح.
- `git commit -m "Document staff deployment operations"` — نُفّذ؛ أنشأ commit التوثيق الأول `e2e99206b83e91b390fcccb9b5e987503a9ab3d9`.
- `git push origin HEAD:refs/heads/feature/manager-staff-accounts` — نُفّذ بنجاح؛ الإيصال أكد تحديث الفرع البعيد من `c0cc8a1` إلى `e2e9920`.
- `git ls-remote origin refs/heads/feature/manager-staff-accounts` — نُفّذ بعد الدفع؛ أعاد `e2e99206b83e91b390fcccb9b5e987503a9ab3d9`.

### أوامر نشر مقترحة ولم تُنفّذ / Suggested deployment commands, not run

```sh
supabase login
supabase functions deploy manage-staff --project-ref ztkiavqmbswyxkmddtno
```

الحالة: مقترح سابقًا فقط؛ لم يُشغَّل في سجل هذا العمل. يتطلب مسار CLI مصادقة صالحة. لا تضع Personal Access Token أو أي سر في الأوامر/الدردشة أو في هذا الملف.

Status: previously suggested only; not run during this work. The CLI route requires valid authentication. Never place a Personal Access Token or other secret in commands, chat, or this file.

## أعطال وعوائق موثقة / Recorded failures and blockers

- محاولات سابقة لإدارة نشر الدالة باستخدام الرمز المحفوظ انتهت برفض 401/JWT؛ لا يُعاد استخدام الرمز أو نسخه إلى محرر أو سطر أوامر. تفاصيل الأمر الحرفية لم تُحفظ، لذلك لا يُختلق أمر سابق.
- Earlier function deployment attempts using the stored token were rejected with 401/JWT errors. Do not reuse or copy it into an editor or command line. The exact command text was not retained, so no prior command is invented here.
- أظهر محرر Supabase عبر المتصفح مساحة تحرير واسم دالة وزر نشر، ولم يظهر فيها حقل مخصص آمن للـPersonal Access Token. لم يُرسل الرمز إلى الصفحة.
- The Supabase browser editor exposes source editing, a function name, and a deploy button; no dedicated secure Personal Access Token field was visible. The attempt to enter the full source failed and the editor became unresponsive; the Deploy button was not submitted, and no token was sent to the page.

## الخطوات التالية / Next steps

1. نشر `manage-staff` من محرر Supabase الرسمي بعد مراجعة كامل المصدر، مع تفعيل التحقق من JWT، ثم التحقق من ظهوره في قائمة الدوال واختبار OPTIONS/رفض الطلب غير المصرح به دون إنشاء حساب.
2. Deploy `manage-staff` through Supabase’s official editor after reviewing the full source, retaining JWT verification; confirm it appears in the live list and test OPTIONS/unauthorized rejection without creating an account.
3. بناء الواجهة مع قيم إعداد البناء الموجودة محليًا دون كشفها، والتحقق أن `dist/` ينتج ملفات قابلة للتشغيل على GitHub Pages بمسار المشروع `/elkhayal-motors/`.
4. Build the frontend with its existing local build settings without exposing them; verify `dist/` works under GitHub Pages’ `/elkhayal-motors/` project path.
5. مراجعة التغييرات ورفع التوثيق وحده أولًا إلى فرع الميزة. لا تنشر كود التطبيق إلى `main` إلا بعد التحقق من التوافق والموافقة/المسار المناسب.
6. Review changes and push documentation alone first to the feature branch. Do not publish app code to `main` until compatibility is verified and the appropriate release path is established.
7. بعد النشر إلى Pages، تحقق من صفحة الموقع والميزة من المصدر الحي، ثم وثّق الـcommit وعنوان Pages ونتيجة التحقق هنا. لا تنشئ حسابات موظفين دون طلب منفصل.
8. After a Pages release, verify the live site and feature, then record the commit, Pages URL, and verification result here. Do not create employee accounts without a separate request.

## تحديث تدقيق المستودع / Repository audit update

**21 Nov 2026, 12:20 Cairo / 21 نوفمبر 2026، 12:20 القاهرة**

- تحقق checkout نظيف لفرع `feature/manager-staff-accounts`؛ آخر commit قبل هذا التحديث `4a1ab47afb37b33f80e6843d5987724078c275d3` ويعدّل `OPERATIONS_LOG.md` فقط. لا يحتوي على نشر للدالة أو كود التطبيق.
- A clean checkout of `feature/manager-staff-accounts` was verified. Before this update its HEAD was `4a1ab47afb37b33f80e6843d5987724078c275d3`, changing `OPERATIONS_LOG.md` only. It does not deploy the function or contain the app-code changes.
- الملفات الوحيدة المتتبعة تحت `supabase/migrations/` في هذا الفرع هي `202611210001_initial_foundation.sql` و`202611210002_customer_requests_no_delete.sql` و`202611210003_least_privilege_catalog_and_requests.sql`. لم يُنفّذ أي SQL أو migration جديد أثناء هذا التدقيق.
- The only tracked files under `supabase/migrations/` on this branch are `202611210001_initial_foundation.sql`, `202611210002_customer_requests_no_delete.sql`, and `202611210003_least_privilege_catalog_and_requests.sql`. No SQL or migration was executed during this audit.
- يسجل هذا السجل أن تطبيق `001` غير متحقق هنا، وأن `002` و`003` سبق توثيق تطبيقهما في المراجعة السابقة. ملف `202611210005_manager_staff_permissions.sql` الذي شوهد في مساحة عمل محلية منفصلة غير موجود في الفرع البعيد الحالي، ولا يوجد دليل هنا على تطبيقه؛ لا تشغّله بناءً على اسمه أو وجوده المحلي وحده.
- This log records migration `001` as not verified here, and `002`/`003` as previously recorded applied. `202611210005_manager_staff_permissions.sql`, seen in a separate local worktree, is absent from this remote branch; its application is not established. Do not run it based only on its name or local presence.
- أُعيد التحقق من أن `package.json` يعرّف `npm run build` على أنه `vite build`. هذا لا يجعل GitHub Pages legacy يبني المشروع تلقائيًا؛ لا يزال نشر الواجهة غير مكتمل.
- Rechecked that `package.json` defines `npm run build` as `vite build`. That does not make legacy GitHub Pages build the project automatically; frontend publication remains incomplete.
- نتيجة النشر الحالية: `manage-staff` غير موجودة في قائمة Supabase الحية؛ محرر لوحة التحكم لم يقبل المصدر الكامل ولم يُرسل Deploy. لم تُنشأ حسابات موظفين، ولم يتغير `main` أو الموقع الحي.
- Current deployment result: `manage-staff` is absent from the live Supabase function list; the Dashboard editor did not accept the full source and no Deploy submission occurred. No staff accounts were created, and neither `main` nor the live website changed.

### أوامر التدقيق المنفذة / Audit commands executed

```sh
git clone --branch feature/manager-staff-accounts --single-branch https://github.com/khayal-1/elkhayal-motors.git motors-log
git status --short --branch
ls -la
sed -n '1,260p' OPERATIONS_LOG.md
git rev-parse HEAD
git show --stat --oneline -1
git ls-files 'supabase/migrations/*'
cat package.json
```

الحالة: نُفذت للقراءة والتحقق فقط؛ نجح الاستنساخ، وكانت شجرة العمل نظيفة، ولم تُغيّر ملفات التطبيق أو قاعدة البيانات.

Status: executed for read-only inspection; clone succeeded, the working tree was clean, and no app or database files were changed.

## متابعة التنفيذ / Execution continuation

**21 Nov 2026, 12:20–12:30 Cairo / 21 نوفمبر 2026، 12:20–12:30 القاهرة**

- تمت مصادقة GitHub عبر تسجيل الدخول الاجتماعي إلى Supabase؛ ظهر تحدي تحقق الجهاز، واستُخدم رمز GitHub المرسل للبريد من خلال مرجع التحقق الآمن. بعد العودة إلى Supabase، ظهرت صفحة الوظائف للمشروع الصحيح؛ كانت القائمة تعرض `telegram-photo-upload` فقط في تلك اللحظة.
- GitHub authentication completed through Supabase's GitHub sign-in; the device-verification challenge was completed using the secure email-code reference. Back in Supabase, the correct project functions page was visible; at that time its live list contained only `telegram-photo-upload`.
- فتحت إرشادات Supabase CLI؛ تعرض أمر النشر، وتذكر الحاجة إلى access token. لم يُنشأ رمز جديد ولم يُمرر أي رمز إلى CLI، ولم تُرسل محاولة نشر للدالة.
- Supabase CLI guidance was inspected; it shows the deploy command and notes that an access token may be needed. No new access token was created or passed to the CLI, and no function deployment was submitted.
- `vite.config.js` عُدّل في فرع الميزة لتحديد `base: '/elkhayal-motors/'` حتى تشير ملفات Vite إلى المسار الصحيح لموقع GitHub Pages ذي المسار الفرعي. هذا التعديل لم يُنشر إلى `main`.
- `vite.config.js` was changed on the feature branch to set `base: '/elkhayal-motors/'`, so Vite output uses the project's GitHub Pages subpath. This change has not been published to `main`.
- `corepack pnpm install --frozen-lockfile` — نُفذ بنجاح، دون تغيير lockfile.
- `corepack pnpm run build` — نُفذ بنجاح بعد تثبيت الحزم؛ أُنتجت ملفات `dist/`.
- `deno check supabase/functions/manage-staff/index.ts` — نُفذ بنجاح.
- `npm run build` — محاولة أولى فشلت لأن حزم Vite لم تكن مثبتة في هذا checkout (`vite: not found`)، ثم عُولج ذلك بـ`corepack pnpm install --frozen-lockfile` وأُعيد البناء بنجاح.
- `git fetch origin`, `git status --short --branch`, `git log --oneline --decorate -5`, `git ls-remote origin refs/heads/feature/manager-staff-accounts refs/heads/main`, `git show --stat`, و`git ls-files 'supabase/migrations/*'` — نُفذت للتحقق؛ أكدت الفرع النظيف وHEAD البعيد `0c7b62d` قبل تعديل هذا السجل، مع migrations 001–003 فقط في الفرع.
- حالة النشر لا تزال معلّقة: `manage-staff` غير منشورة، ولم يُنشر البناء إلى GitHub Pages. لا توجد إعدادات عامة فعلية في `.env` لهذا checkout (`.env.example` فقط)، وإعداد Pages الحالي legacy `main:/` لا يشغّل Vite.
- Deployment remains blocked: `manage-staff` is undeployed, and the build has not been published to GitHub Pages. This checkout has no actual public `.env` values (`.env.example` only), and the current legacy `main:/` Pages source does not run Vite.

## متابعة مراجعة وإصلاح ميزة الموظفين / Staff feature review and fixes

**21 Nov 2026, 12:20 Cairo / 21 نوفمبر 2026، 12:20 القاهرة**

- بعد `git fetch origin` والتحقق من `git status --short`, `git log -1 --oneline --decorate`, و`git ls-remote origin refs/heads/feature/manager-staff-accounts`، كان الفرع `feature/manager-staff-accounts` مطابقًا للمرجع البعيد عند `0c7b62d` قبل هذه التغييرات. لم تُستبدل التزامات التوثيق السابقة.
- After `git fetch origin`, `git status --short`, `git log -1 --oneline --decorate`, and `git ls-remote origin refs/heads/feature/manager-staff-accounts`, the local feature branch matched remote commit `0c7b62d` before these changes. Earlier documentation commits were preserved.
- مراجعة `git show c0cc8a1` و`rg` وملفات SQL أظهرت ثغرتين وظيفيتين في الشيفرة المحلية: نموذج المدير لم يكن يرسل كلمة مرور يختارها، والـtrigger ينشئ دور/ملف عميل تلقائيًا لكل مستخدم جديد. عُدلت `app.js` لإضافة إدخال كلمة المرور وتأكيدها وحذف واجهة كلمة المرور المؤقتة القديمة؛ عُدلت `supabase/functions/manage-staff/index.ts` للتحقق من كلمة المرور، تأكيد البريد لحساب الموظف الذي ينشئه المدير، إزالة دور العميل وملف العميل الافتراضي، إضافة دور الموظف والصلاحيات، والتراجع بحذف الحساب الجديد عند فشل خطوة الحفظ. أزيل أيضًا معالج نسخ كلمة المرور المؤقتة.
- Review of `git show c0cc8a1`, `rg`, and SQL files exposed two behavior gaps in local code: the manager form did not send a chosen password, while the auth trigger creates a default customer role/profile for each new user. `app.js` now has password/confirmation inputs and removes the obsolete temporary-password UI; `supabase/functions/manage-staff/index.ts` validates the password, confirms manager-created staff email, removes the auto-created customer role/client row, adds the employee role and permissions, and rolls back the new auth user when a save step fails. The stale temporary-password copy handler was removed.
- عُدّل `vite.config.js` إلى `base: '/elkhayal-motors/'` ليتوافق خرج Vite مع مسار GitHub Pages للمشروع. لم يُنشر هذا التعديل.
- `vite.config.js` now sets `base: '/elkhayal-motors/'` for the GitHub Pages project path. This change has not been published.
- أوامر التحقق: `corepack pnpm run build` نجح؛ `deno check supabase/functions/manage-staff/index.ts` نجح؛ `git diff --check` نجح؛ وتأكد `rg` من إزالة مراجع `temporary_password` و`copyStaffPassword` من واجهة الموظفين ودالتها. لم تُنشأ حسابات موظفين.
- Checks: `corepack pnpm run build` passed; `deno check supabase/functions/manage-staff/index.ts` passed; `git diff --check` passed; `rg` confirmed the staff UI/function no longer reference `temporary_password` or `copyStaffPassword`. No staff accounts were created.
- لا يوجد ترحيل جديد مطلوب أو منفذ لهذه التغييرات المحلية. الفرع يتتبع ملفات الترحيلات `202611210001_initial_foundation.sql` و`202611210002_customer_requests_no_delete.sql` و`202611210003_least_privilege_catalog_and_requests.sql` فقط. سجل المشروع السابق يقول إن ترحيل صلاحيات الموظفين طُبق حيًا، لكن مصدر SQL الذي أنشأ جدول `employee_permissions` غير موجود ضمن الملفات المتتبعة؛ لا أستطيع استعادته أو توثيقه كملف ترحيل دون قراءة تعريفه الحي. حالة 001 غير متحققة، بينما سُجل سابقًا تطبيق 002 و003.
- No new migration was needed or executed for these local code changes. The branch tracks only `202611210001_initial_foundation.sql`, `202611210002_customer_requests_no_delete.sql`, and `202611210003_least_privilege_catalog_and_requests.sql`. Prior project notes report that the staff-permissions migration was applied live, but the SQL source that created `employee_permissions` is absent from tracked files; it cannot safely be recreated/documented as a migration without reading its live definition. Migration 001 remains unverified; 002 and 003 were previously recorded as applied.
- لا تزال `manage-staff` غير منشورة، ولم يُحدّث الموقع. لا ينفذ مصدر Pages الحالي `main:/` بناء Vite تلقائيًا، ولا توجد قيم إعداد Supabase عامة في checkout سوى أمثلة `.env.example`. لا يُرسل هذا الفرع إلى `main`، ولا يُنشأ رمز جديد أو يوضع مفتاح سري في المستودع.
- `manage-staff` remains undeployed and the live site unchanged. Current Pages source `main:/` does not build Vite, and the checkout has no actual public Supabase build settings beyond `.env.example` placeholders. This branch is not being published to `main`; no new token was created and no secret was added to the repository.

- التزام الشيفرة المراجعة: `f82d66957299543636e92a57916829ef79d9fb58` (`Implement manager staff creation and Pages base`)؛ شمل `app.js` و`supabase/functions/manage-staff/index.ts` و`vite.config.js` وهذا السجل فقط. دُفع إلى `feature/manager-staff-accounts` وتحقق أن `git ls-remote` أعاد SHA نفسه. لم يتغير `main` أو موقع GitHub Pages.
- Reviewed code commit: `f82d66957299543636e92a57916829ef79d9fb58` (`Implement manager staff creation and Pages base`); it includes only `app.js`, `supabase/functions/manage-staff/index.ts`, `vite.config.js`, and this log. It was pushed to `feature/manager-staff-accounts`, and `git ls-remote` returned the same SHA. Neither `main` nor GitHub Pages changed.


## متابعة النشر الحالي / Current deployment continuation

**21 Nov 2026 / 21 نوفمبر 2026**

- نُشرت `supabase/functions/manage-staff/index.ts` إلى مشروع Supabase `ztkiavqmbswyxkmddtno` باسم `manage-staff` من محرر Supabase الرسمي بعد التحقق من أن المصدر كامل (8,569 محرفًا) واسم الملف الوحيد `index.ts` واسم الدالة `manage-staff`. أبقى إعداد `Verify JWT with legacy secret` مفعّلًا. صفحة قائمة الدوال الحية أكدت وجود الدالة مع رابطها `https://ztkiavqmbswyxkmddtno.supabase.co/functions/v1/manage-staff` إلى جانب `telegram-photo-upload`. نجح اختبار OPTIONS بإرجاع HTTP 200 وCORS لمصدر GitHub Pages؛ POST غير مصرح بقائمة للقراءة فقط أعاد HTTP 401 لغياب Authorization. لم يُجر اختبار إنشاء مستخدم أو أي كتابة قاعدة بيانات، ولم تُنفّذ migrations.
- Deployed `supabase/functions/manage-staff/index.ts` to Supabase project `ztkiavqmbswyxkmddtno` as `manage-staff` through the official Supabase editor after checking the complete source (8,569 characters), the sole file `index.ts`, and the function name `manage-staff`. The `Verify JWT with legacy secret` setting remained enabled. The live functions list confirmed the function at `https://ztkiavqmbswyxkmddtno.supabase.co/functions/v1/manage-staff` alongside `telegram-photo-upload`. A GitHub Pages-origin OPTIONS test returned HTTP 200 with CORS; an unauthenticated read-only list POST returned HTTP 401 because Authorization was missing. No account-creation test or database write was performed; no migration was run.
- تم فحص API Keys في إعدادات المشروع. أُنشئت متغيرات GitHub Actions عامة للمستودع `khayal-1/elkhayal-motors`: `NEXT_PUBLIC_SUPABASE_URL` و`NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`؛ لا يحتوي المستودع على service-role أو مفتاح سري.
- Supabase project API settings were checked. Public GitHub Actions repository variables `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` were created for `khayal-1/elkhayal-motors`; no service-role or secret key was put in the repository.
- أُضيف `.github/workflows/deploy-pages.yml` لبناء Vite عند الدفع إلى `main` أو التشغيل اليدوي، ورفع `dist/` عبر GitHub Pages Actions. ما زال إعداد Pages الحي `legacy` من `main:/` حتى تفعيل هذا المسار بعد مراجعة الدمج.
- Added `.github/workflows/deploy-pages.yml` to build Vite on pushes to `main` or manual dispatch and deploy `dist/` through GitHub Pages Actions. The live Pages setting remains legacy `main:/` until the Actions path is enabled during release.
- دمجت آخر `origin/main` في فرع الميزة؛ لا تعارض، وتغييره الوحيد كان تعديل نص في `app.js`. أُعيد البناء محليًا بأوامر `NEXT_PUBLIC_SUPABASE_URL=... NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=... corepack pnpm run build`؛ نجح Vite، وتحقق `dist/index.html` من روابط `/elkhayal-motors/assets/...`. الحزمة تحتوي إعداد المشروع ومفتاح النشر العام ولا تحتوي placeholders.
- Merged the latest `origin/main` into the feature branch without conflicts; its only change was a text edit in `app.js`. Rebuilt locally with the public `NEXT_PUBLIC_SUPABASE_URL=... NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=... corepack pnpm run build`; Vite passed and `dist/index.html` contained `/elkhayal-motors/assets/...` paths. The bundle included the project configuration and publishable key, with no placeholders.
- دُفع commit `08212029c3046b7c78cd4cbde2286a3121387a30` إلى فرع `feature/manager-staff-accounts` وتحقق `git ls-remote` من SHA نفسه. طلب السحب الموجود رقم 1 إلى `main` أصبح قابلاً للدمج؛ الشيكات المعروضة فيه تخص معاينة Vercel فقط، وليست اختبار GitHub Pages.
- Commit `08212029c3046b7c78cd4cbde2286a3121387a30` was pushed to `feature/manager-staff-accounts` and `git ls-remote` returned the same SHA. Existing pull request #1 to `main` is mergeable; its displayed checks are Vercel preview checks only, not GitHub Pages tests.
- ضُبط Site URL في Supabase Authentication ليكون `https://khayal-1.github.io/elkhayal-motors/` وأُضيف الرابط نفسه إلى allowlist للتحويلات؛ احتُفظ برابط Vercel القديم في القائمة. عُدّل تسجيل العميل وإعادة إرسال التأكيد لاستخدام `import.meta.env.BASE_URL` كوجهة تحويل، لتصل الروابط إلى مسار Pages الفرعي. لم يُرسل بريد تأكيد أو يُنشأ حساب عميل.
- Supabase Authentication Site URL is now `https://khayal-1.github.io/elkhayal-motors/`, and that URL was added to the redirect allowlist; the old Vercel URL remains allowed. Customer signup and resend-confirmation now use `import.meta.env.BASE_URL` so confirmation links return to the Pages subpath. No confirmation email was sent and no customer account was created.
- لم يتغير إعداد Pages الحي بعد (`legacy main:/`) ولم يتغير الموقع المنشور بعد. لم تُنفّذ أي migration ولم تُنشأ حسابات موظفين.


### أوامر متابعة النشر / Deployment continuation commands

```sh
git merge --no-edit origin/main
NEXT_PUBLIC_SUPABASE_URL='https://ztkiavqmbswyxkmddtno.supabase.co' NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY='<public publishable key from Supabase API Keys>' corepack pnpm run build
deno check supabase/functions/manage-staff/index.ts
git diff --check
gh variable set NEXT_PUBLIC_SUPABASE_URL -R khayal-1/elkhayal-motors --body '<project URL>'
gh variable set NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY -R khayal-1/elkhayal-motors --body '<public publishable key>'
git push origin feature/manager-staff-accounts
git ls-remote origin refs/heads/feature/manager-staff-accounts
```

القيم بين الأقواس توضّح مكان قيم المشروع العامة، وليست أسرارًا؛ لم يُدرج service-role أو Personal Access Token. نجح البناء و`deno check` و`git diff --check`. لم يُشغّل أي أمر migration أو SQL.

The bracketed values indicate the public project configuration inputs, not secrets; no service-role key or Personal Access Token was included. The build, `deno check`, and `git diff --check` passed. No migration or SQL command was run.


- سجّل التغيير إلى redirect URL في Supabase واستخدام مسار Pages في كود التسجيل: `app.js` يحسب `authRedirectUrl` من `import.meta.env.BASE_URL` ويستخدمه في التسجيل وإعادة إرسال تأكيد البريد.
- Recorded the Supabase redirect URL change and Pages-path code update: `app.js` derives `authRedirectUrl` from `import.meta.env.BASE_URL` and uses it for signup and resend-confirmation.

## استعادة GitHub Pages / GitHub Pages recovery

**21 Nov 2026, 13:00–13:05 Cairo / 21 نوفمبر 2026، 13:00–13:05 القاهرة**

- بعد دمج `f9a714b0cc5a6d3b856fce163147381bb1c008c7`، نجح مسار Actions `Deploy website to GitHub Pages` رقم `44896976467` في بناء Vite ورفع ملفات الموقع. بالتزامن، انتهى تشغيل GitHub Pages الداخلي `pages-build-deployment` رقم `44896976186` المبني من Jekyll/مصدر الفرع بعده، فأصبح الموقع يعرض `index.html` القديم الذي يشير إلى `style.css` و`app.js` بدل ملفات Vite؛ كانت ملفات Vite ذات الأسماء المجزأة ترجع 404. هذا تعارض/سباق نشر، وليس خطأ في Supabase أو migration.
- After merge `f9a714b0cc5a6d3b856fce163147381bb1c008c7`, Actions workflow `Deploy website to GitHub Pages` run `44896976467` successfully built Vite and uploaded the site. At the same time, GitHub's internal Jekyll/branch-source `pages-build-deployment` run `44896976186` finished afterward and left the site serving the old `index.html` referencing `style.css` and `app.js`; the hashed Vite files returned 404. This was a deployment race, not a Supabase or migration error.
- أظهر إعداد Pages الحي `build_type: workflow`. شُغّل مسار Actions يدويًا بعد انتهاء عمليتي النشر المتعارضتين، بالأمر `gh workflow run deploy-pages.yml --repo khayal-1/elkhayal-motors --ref main`. اكتمل التشغيل `44897317416` بنجاح. فحصت الرابط العام: صفحة الموقع أعادت HTTP 200، وHTML يشير إلى `/elkhayal-motors/assets/index-DZGts3vm.js` و`/elkhayal-motors/assets/index-BkDdn2fx.css`؛ كلا الملفين أعاد HTTP 200. تضمّن ملف JavaScript المنشور علامات واجهة الموظفين و`manage-staff`.
- Live Pages settings reported `build_type: workflow`. After the conflicting deployments finished, the Actions workflow was manually run with `gh workflow run deploy-pages.yml --repo khayal-1/elkhayal-motors --ref main`. Run `44897317416` completed successfully. Public smoke check: the site returned HTTP 200 and its HTML referenced `/elkhayal-motors/assets/index-DZGts3vm.js` and `/elkhayal-motors/assets/index-BkDdn2fx.css`; both assets returned HTTP 200. The published JavaScript contains the employee UI and `manage-staff` markers.
- تحققت من الأثر عبر `gh api repos/khayal-1/elkhayal-motors/pages`, و`gh run list`، و`gh run view` للتشغيلين، و`gh api repos/khayal-1/elkhayal-motors/deployments/7962401638/statuses`، وتنزيل artifact للتشغيل `44896976467` بواسطة `gh run download`. فُحصت استجابات الرابط والملفات عبر `curl` مع استعلامات منع التخزين المؤقت.
- Evidence checks used `gh api repos/khayal-1/elkhayal-motors/pages`, `gh run list`, `gh run view` for both runs, `gh api repos/khayal-1/elkhayal-motors/deployments/7962401638/statuses`, and `gh run download` for run `44896976467`. Public HTML and assets were checked with cache-busted `curl` requests.
- حالة الدالة `manage-staff` في Supabase: منشورة كما سبق تسجيله. لم تُنشأ أي حسابات موظفين، ولم يُرسل طلب إنشاء مستخدم، ولم تُنفّذ SQL أو migrations جديدة. تحقق الموقع المنشور وملفات الواجهة، لكن لم يُنفّذ اختبار دخول إداري/إنشاء حساب فعلي.
- `manage-staff` remains deployed in Supabase as recorded earlier. No employee accounts were created, no user-creation request was sent, and no SQL or migrations were run. The published site and frontend assets were smoke-tested, but no manager sign-in or real employee-account creation was tested.

### أوامر الاستعادة / Recovery commands

```sh
gh workflow run deploy-pages.yml --repo khayal-1/elkhayal-motors --ref main
gh run watch 44897317416 --repo khayal-1/elkhayal-motors --exit-status
gh run download 44896976467 --repo khayal-1/elkhayal-motors --name github-pages --dir /tmp/motors-pages-artifact
curl -fsSL 'https://khayal-1.github.io/elkhayal-motors/?smoke=<cache-buster>'
```

## Public storefront recovery checks / فحص استعادة المتجر العام

**21 Nov 2026, 13:32 Cairo / 21 نوفمبر 2026، 13:32 القاهرة**

- فُحص الموقعان الحيان من دون تسجيل دخول: صفحة GitHub Pages على `https://khayal-1.github.io/elkhayal-motors/` تحمل ملفاتها من `/elkhayal-motors/assets/...`، ونسخة Vercel النشطة `https://elkhayal-motors-website.vercel.app/` تحمل من `/assets/...`. عاد HTML وملفا JavaScript/CSS من المسارين الحاليين HTTP 200. أظهر المتجر المرئي البطل، البحث والفلاتر وبطاقة دراجة من Supabase؛ ظهرت الصورة كعنصر نائب.
- Read-only checks of both live sites: GitHub Pages at `https://khayal-1.github.io/elkhayal-motors/` loads assets from `/elkhayal-motors/assets/...`; the active Vercel copy at `https://elkhayal-motors-website.vercel.app/` loads from `/assets/...`. The current HTML and JavaScript/CSS asset URLs returned HTTP 200. The visible storefront showed its hero, search/filters, and a Supabase motorcycle card; its image is a placeholder.
- صحح `vite.config.js` ليبقى GitHub Pages هو الأساس (`/elkhayal-motors/`) ويستخدم Vercel مسار الجذر عند ضبط متغير البناء `VERCEL`، بدل إجبار النطاقين على المسار الفرعي. نجاح بناء Pages محليًا أكد `/elkhayal-motors/assets/index-BtIjEGe0.js` وCSS بالبادئة نفسها؛ ونجاح بناء Vercel أكد `/assets/index-DQ4RDD95.js` وCSS بالجذر. نجح `git diff --check`.
- Updated `vite.config.js` so GitHub Pages remains primary at `/elkhayal-motors/`, while a Vercel build uses the domain root when its `VERCEL` build variable is set. Local Pages build emitted `/elkhayal-motors/assets/index-BtIjEGe0.js` plus CSS under the same prefix; the Vercel build emitted `/assets/index-DQ4RDD95.js` plus root CSS. Both builds and `git diff --check` passed.
- فحصت `manage-staff` الحية بطلب OPTIONS للـorigin الدقيق `https://elkhayal-motors-website.vercel.app`؛ عادت 200 و`Access-Control-Allow-Origin` مطابقًا. Origin عشوائي آخر لم يحصل على ترويسة السماح. مصدر الدالة في الفرع لم يتضمن بعد نطاق Vercel؛ أضفت النطاق الدقيق فقط إلى `allowedOrigins` مع إبقاء GitHub Pages وlocalhost كما هما. لم أستخدم wildcard ولم أعد نشر الدالة؛ الاستجابة الحية تثبت أن CORS يعمل بالفعل للنطاق المختبر.
- Checked live `manage-staff` with an OPTIONS request from the exact origin `https://elkhayal-motors-website.vercel.app`; it returned 200 with a matching `Access-Control-Allow-Origin`. An unrelated origin received no allow-origin header. The tracked function source did not yet include the Vercel origin, so only that exact origin was added to `allowedOrigins`, retaining GitHub Pages and localhost. No wildcard was introduced and the function was not redeployed; the live response confirms CORS already works for the tested origin.
- مصدر الكتالوج يقرأ `motorcycles.image_urls` لبطاقات الزوار، بينما سياسات `photo_assets` في ترحيل الأساس تقصر القراءة على المستخدمين المسجلين ذوي الأدوار المعتمدة. سجل الدراجة الظاهر لا يملك `image_urls`، لذا لا يوجد رابط صورة عام لها؛ لم أفتح قراءة عامة لملفات Telegram ولم أغيّر سياسة البيانات. دالة الرفع تتحقق من `catalog_manage` قبل إرسال الصورة، وهذا التحقق موجود بالفعل.
- Catalog source uses `motorcycles.image_urls` for public cards, while the foundation migration restricts `photo_assets` reads to authenticated allowed roles. The visible motorcycle has no `image_urls`, so it has no public image URL; I did not expose Telegram file records or change data policies. The upload function already checks `catalog_manage` before sending an image.
- ملف `20261121130000_hardening_requests_indexes.sql` المتتبع يضع شرط `status = 'pending'` في سياسة `request_create`، لكنه لا يوفر دليلًا مستقلاً على الحالة الحية لقاعدة البيانات. لم أنفذ SQL أو migrations أخرى؛ بقي التحقق الحي من حالة هذا الترحيل خارج ما أثبته هنا.
- Tracked migration `20261121130000_hardening_requests_indexes.sql` adds `status = 'pending'` to the `request_create` policy, but the file alone is not independent evidence of live database status. No SQL or migration was run; live confirmation of this migration remains outstanding.
- لا تغييرات على سجلات أو أسرار أو إعدادات Auth، ولم تتم محاولة تسجيل دخول المدير أو إنشاء حسابات.
- No records, secrets, or Auth settings were changed; no owner sign-in was attempted and no accounts were created.

## إصلاح إنشاء حساب الموظف / Staff account creation fix

**21 Nov 2026, 13:56 Cairo / 21 نوفمبر 2026، 13:56 القاهرة**

- تتبعت طلبًا حيًا إلى `manage-staff`: تحقق Supabase Auth من المستخدم بنجاح، ثم فشل الاستعلام عن دور المدير من `public.user_roles` بـHTTP 403 / SQLSTATE `42501`. سجل قاعدة البيانات أوصى صراحةً بمنح `SELECT` إلى `service_role`. لذلك كانت الدالة تتوقف قبل استدعاء `auth.admin.createUser`، ولم يكن ظهور النموذج دليلًا على إنشاء الحساب.
- Traced a live request to `manage-staff`: Supabase Auth accepted the user, then the manager-role lookup on `public.user_roles` failed with HTTP 403 / SQLSTATE `42501`. The database log explicitly recommended granting `SELECT` to `service_role`. The function therefore stopped before `auth.admin.createUser`; rendering the form had not created an account.
- أُضيف ترحيل محدود `supabase/migrations/20261121140000_grant_manage_staff_service_role.sql`: `service_role` يحصل فقط على قراءة/إضافة/تحديث/حذف `user_roles` اللازمة للتحقق والإسناد والتراجع؛ قراءة `profiles` و`employee_permissions` لعرض الدليل؛ إضافة `employee_permissions`؛ وحذف صف `clients` الذي ينشئه مشغّل تسجيل Supabase تلقائيًا لحساب الموظف. لا تتغير صلاحيات `anon` أو `authenticated` أو سياسات RLS.
- Added the narrowly scoped migration `supabase/migrations/20261121140000_grant_manage_staff_service_role.sql`: `service_role` gets only the `user_roles` read/write permissions needed for verification, assignment and rollback; reads of `profiles` and `employee_permissions` for the staff directory; permission-row inserts; and deletion of the `clients` row created by Supabase's signup trigger for the employee. No `anon`/`authenticated` grants or RLS policies change.
- طُبقت المنح نفسها على قاعدة Supabase الإنتاجية من SQL Editor، ثم تحققت بقراءة `has_table_privilege`: كل العمليات المطلوبة على `user_roles` و`employee_permissions`، وقراءة `profiles`، وحذف صف `clients` أعادت `true`. لم يُنشأ أي مستخدم أو سجل، ولم يتغير كود الدالة المنشورة أو أسرار/Auth.
- Applied those grants to the production Supabase database in SQL Editor, then verified the required `has_table_privilege` checks: `user_roles`, `employee_permissions`, profile reads, and client-row deletion all returned `true`. No user or record was created; the deployed function code, secrets and Auth settings were not changed.
- نجح `npm run build` و`git diff --check`. لم أجرّب إنشاء حساب حقيقي احترامًا لعدم إنشاء موظف اختباري؛ لذلك يلزم من المالك إعادة تجربة النموذج ببيانات الموظف المقصود للتأكد من إتمام Auth والملف والصلاحيات. تسجيل إنشاء الحساب في `manage-staff` يبقى محميًا بدور المدير/المالك/المسؤول قبل أي كتابة.
- `npm run build` and `git diff --check` passed. I did not create a real or test employee; the owner should retry the form with the intended employee details to confirm Auth, profile and permissions finish end to end. `manage-staff` still checks the manager/owner/admin role before any writes.
- لم أعد تشغيل أو تعديل إصلاحات Vite/CORS في `406f2c1`. لا تزال فجوة صورة الدراجة (`image_urls` فارغ) والتحقق المستقل من حالة ترحيل `20261121130000_hardening_requests_indexes.sql` منفصلين عن هذا الإصلاح.
- I did not rerun or alter the Vite/CORS fixes in `406f2c1`. The motorcycle image gap (`image_urls` is empty) and independent verification of migration `20261121130000_hardening_requests_indexes.sql` remain separate follow-ups.

## متابعة رفض إنشاء الموظف / Follow-up on staff creation conflict

**21 Nov 2026, 14:03 Cairo / 21 نوفمبر 2026، 14:03 القاهرة**

- راجعت أحدث سجلات الإنتاج بعد بلاغ المالك. طلب `manage-staff` اجتاز التحقق من المستخدم وقراءة `user_roles` بعد المنحة المنشورة، ثم أعاد `409`; وسجل Supabase Auth المقابل أعاد `422` مع `email_exists`. لم يصل الطلب إلى حفظ دور أو صلاحيات موظف، ولم يُنشأ حساب جديد.
- Reviewed the latest production logs after the owner’s report. `manage-staff` passed user validation and the `user_roles` read after the deployed grant, then returned `409`; the corresponding Supabase Auth request returned `422` with `email_exists`. No employee role/permission writes followed, and no account was created.
- أصل المشكلة في هذه المحاولة أن البريد المُدخل مستخدم بالفعل في Auth؛ الدالة ترفض تكرار البريد عمدًا، ولا تحوّل حسابًا قائمًا إلى موظف. حسّنت `app.js` لقراءة رسالة الخطأ JSON من استجابة Edge Function وعرض سبب واضح بالعربية: «البريد الإلكتروني مستخدم بالفعل؛ استخدم بريدًا آخر للموظف.»
- The current attempt’s blocker is that the submitted email already exists in Auth; the function intentionally rejects duplicate emails and does not convert an existing account into staff. Updated `app.js` to read the Edge Function JSON error response and show a clear Arabic message: “This email is already in use; use another email for the employee.”
- لا يُنفّذ هذا التغيير إنشاء حساب أو تحويل مستخدم حالي. إن كان المقصود موظفًا لديه حساب عميل قائم، يلزم توجيه صريح لذلك المستخدم/البريد قبل أي تحويل للصلاحية؛ أما الحساب الجديد فيحتاج بريدًا غير مستخدم.
- This change does not create an account or convert an existing user. If the intended employee already has a customer account, explicit direction identifying that account is needed before changing its role; a new employee account needs an unused email.
- جارٍ فحص البناء ورفع تعديل واجهة عرض الخطأ إلى `main` ثم التحقق من نشر Pages.
- Build validation and publishing the clearer UI error to `main`, followed by Pages verification, are in progress.
- اكتمل التحديث: الالتزام `36e2492ec12b3c467dfc75ff3edf4bb1b86af1fb` على `main`؛ نجح بناء ونشر GitHub Pages في التشغيل `44902269545`. أعاد HTML وملفا JS/CSS من Pages HTTP 200، واحتوى ملف JS الحي على رسالة الخطأ العربية الجديدة. لم يُجر اختبار إنشاء مستخدم أو تحويل حساب قائم.
- Release complete: commit `36e2492ec12b3c467dfc75ff3edf4bb1b86af1fb` is on `main`; GitHub Pages build/deployment run `44902269545` succeeded. Live Pages HTML and JS/CSS assets returned HTTP 200, and the live JS bundle contains the new Arabic conflict message. No user creation or existing-account conversion was tested.


## الأدوات المالية المتقدمة / Advanced finance suite

**22 Nov 2026 / 22 نوفمبر 2026**

- أضيفت إلى مشروع Supabase الإنتاجي ztkiavqmbswyxkmddtno جداول وأدوات الفترات المحاسبية، الأرصدة الافتتاحية، مراكز التكلفة، سلف الموردين وتسويتها على الفواتير، الأصول الثابتة والإهلاك، تسويات البنوك وحركات المطابقة، سجل الشيكات، القيود المتكررة، وإعدادات نسب الضرائب ومعرفات التسجيل الضريبي للعملاء والموردين.
- تمت إضافة دوال RPC محمية بصلاحية الإدارة المالية، مع دوال واجهة عامة من نوع SECURITY INVOKER، وتحديث سياسات القراءة حتى يستطيع الموظف الذي يحمل finance_manage أو accounting_view قراءة الأدوات المصرح بها. الكتابة تمر عبر الدوال المحمية ولا تُمنح مباشرة للجداول الجديدة.
- تمنع الفترات المغلقة إنشاء القيود أو تغيير تاريخها داخل نطاقها. ترحيل الأرصدة الافتتاحية والقيود المتكررة وإهلاك الأصول ينشئ قيودًا مزدوجة ويعتمد على فحص توازن القيد الحالي.
- أُضيف قيد تكلفة اختياري إلى أسطر القيود. أُضيفت صلاحية finance_manage إلى قائمة صلاحيات الموظفين.
- عُدّل سداد فاتورة المورد ليشترط اختيار الخزينة/البنك، ويُنشئ قيد سداد، ويخصم التسويات السابقة لسلف الموردين من الرصيد المستحق. واجهة الموردين تحمّل الحسابات المالية قبل فتح نموذج السداد.
- أضيفت صفحة «الأدوات المالية المتقدمة» إلى app.js مع نماذج الفترات والأرصدة الافتتاحية ومراكز التكلفة والسلف والأصول والإهلاك والتسويات البنكية والشيكات والقيود المتكررة وإعدادات الضرائب.
- ملفات الترحيل المصدرية محفوظة في supabase/migrations/ تحت الإصدارات 20261122201758 إلى 20261122202221.
- لا توجد نسب ضريبية افتراضية، ولا أرصدة افتتاحية أو أصول أو شيكات أو قيود متكررة تجريبية. لم تُنشأ سجلات مالية تشغيلية. إعداد نسب الضريبة لا يعني بعد تطبيقها آليًا على فواتير البيع والشراء أو تقديم إقرار ضريبي، وتكامل ETA لم يُفعّل.
- لا يزال يلزم اختبار المسارات من حساب إدارة حقيقي دون إدخال بيانات وهمية، وربط التكلفة ومراكز التكلفة بكل العمليات التشغيلية، واستكمال دورة المحاسبة للمبيعات والمشتريات والمرتجعات، واختبار تسوية البنك مقابل كشف فعلي. لا يُعلن اكتمال المحاسبة الكاملة قبل هذه الاختبارات.

- The production Supabase project ztkiavqmbswyxkmddtno now has finance modules for fiscal periods, opening balances, cost centres, supplier advances and allocations, fixed assets and depreciation, bank reconciliations and statement matching, cheque tracking, recurring journals, and tax-rate configuration plus tax IDs on customers and suppliers.
- Guarded finance RPCs were added. Public wrappers use SECURITY INVOKER; writes to the new tables are not granted directly. Read policies now include finance_manage and accounting_view.
- Closed periods reject new journals and journal-date changes within their date range. Opening balances, recurring journals and depreciation create balanced double-entry journals using the existing deferred balance check.
- Journal lines now support an optional cost-centre reference. finance_manage was added to the staff permission catalogue.
- Supplier bill payments now require a selected cash/bank account, create a journal entry, and account for previously allocated supplier advances when checking the remaining bill balance. The supplier page loads financial accounts before opening the payment form.
- Added the «الأدوات المالية المتقدمة» route and its operational forms in app.js.
- Source migrations are tracked under supabase/migrations/ versions 20261122201758 through 20261122202221.
- No default tax rates, opening balances, assets, cheques, or recurring test journals were seeded; no operational finance records were created. Tax-rate configuration is not yet applied automatically to sales/purchase invoices and is not an ETA filing integration.
- Real admin-account testing, full posting integration for sales/purchases/returns, cost-centre assignment across operational workflows, and reconciliation against a real bank statement remain. The accounting system must not be described as fully complete until those checks pass.


## توسعة الأدوات المالية والموارد البشرية والمخزون وعلاقات العملاء / Finance, HR, inventory and CRM expansion

**22 Nov 2026 / 22 نوفمبر 2026**

- أضيفت وحدات مالية متقدمة تشمل الفترات المحاسبية والأرصدة الافتتاحية والأصول والإهلاك والتسويات البنكية والشيكات والقيود المتكررة وإعداد الضرائب وجلسات الخزينة وتسليم النقدية والعهدة النثرية وعكس القيود والموازنات والاستحقاقات وتقارير أعمار الديون ودفتر النقدية.
- أضيف ترحيل محاسبي آلي للمبيعات وفواتيرها ومدفوعاتها وتكلفة البضاعة عند توافر تكلفة شراء موثقة، واستلام المشتريات وفواتير الموردين والمرتجعات ومردودات المبيعات والأرصدة الدائنة للعملاء. المدفوعات التي لم تحدد خزينة/بنك تُسجل مؤقتًا في حساب متحصلات غير موزعة وتُسوّى لاحقًا بقيد إعادة تصنيف؛ لا يُفترض حساب نقدي غير معلوم.
- أضيفت ملفات الموظفين والحضور والإجازات والعهد والسلف والعمولات وكشوف الرواتب وترحيل استحقاق الرواتب والصرف الجزئي وكشوف مستحقات الموظف. لم تُفترض نسب ضرائب أو تأمينات؛ يدخل المحاسب القيم المعتمدة.
- أضيفت تكلفة المخزون وحد إعادة الطلب والتنبيه والجرد مع قيد فروق المخزون وتسجيل VIN/الباركود والضمان وأوامر الصيانة.
- أضيفت حدود ائتمان العملاء ومنع تجاوزها عند إنشاء البيع وكشف حركة العميل وسجل التفاعلات والشكاوى وتصنيف العملاء ومصدر العميل وموافقة التسويق والإشعارات الداخلية.
- طبقت migrations على Supabase ztkiavqmbswyxkmddtno، واستعيدت ملفات SQL للمهاجرات المطبقة إلى supabase/migrations/ للحفاظ على تطابق المصدر مع قاعدة الإنتاج. تم التحقق من أن جميع القيود المحاسبية الموجودة متوازنة (0 قيد غير متوازن)، وأن السجلات التشغيلية المفحوصة لا تفتقد قيود ترحيل. لا يعني ذلك أن جميع الشاشات أو كل السيناريوهات تم اختبارها بحسابات حقيقية.
- لم تُنشأ بيانات اختبار دائمة، ولم تُنشأ موظفون أو فواتير أو مرتجعات تجريبية.
- يلزم الآن نجاح بناء ونشر GitHub Actions بعد آخر تعديل، ثم اختبار الواجهة الفعلية بحسابات الصلاحيات المناسبة. ما زالت بعض الوحدات تحتاج استكمالًا أو مدخلات تشغيلية، ومنها سياسة التقسيط/الفوائد، دورة عروض الأسعار والتحويل إلى فاتورة، مخزون قطع الغيار، وتكامل الرسائل الآلية والدفع الإلكتروني.


## استكمال المبيعات والمحاسبة التشغيلية / Sales and ledger completion

**22 Nov 2026 / 22 نوفمبر 2026**

- أضيفت عروض الأسعار وبنودها وحالاتها وتحويل العرض المعتمد والساري إلى فاتورة بيع، دون حجز المخزون عند إنشاء العرض. أضيفت جداول أقساط مرنة حتى 36 قسطًا، ويجب أن يساوي مجموعها الرصيد المستحق، وتُسجل تحصيلات الأقساط عبر دورة تحصيل الفواتير. لا تُضاف فوائد أو رسوم تمويل تلقائيًا.
- رُبط تسجيل VIN بحركات البيع: تُعلّم الوحدات المسجلة كمباعة عند بيعها، وتعود إلى المتاح عند قبول مرتجع وإعادته للمخزون.
- أضيفت تسوية المقبوضات غير الموزعة على الخزائن والبنوك بقيود إعادة تصنيف لا تعدل القيود الأصلية.
- فُهرست 91 علاقة خارجية كانت بلا فهارس، وجُمعت سياسات القراءة المتكررة لخمس جداول لتقليل كلفة تقييم RLS.
- فحص قاعدة البيانات: القيود غير المتوازنة = صفر. صلاحيات anon على جداول الرواتب والتكاليف وعروض الأسعار غير متاحة، وإدخال هذه الجداول مباشرة عبر authenticated غير متاح. بعد الفهرسة لم يعد Advisor الأداء يبلغ عن مفاتيح خارجية غير مفهرسة؛ بقيت ملاحظات unused indexes معلوماتية فقط.
- ما زال فحص بناء ونشر الواجهة على GitHub Actions مطلوبًا بعد آخر commit؛ لا يُعلن اكتمال النشر قبل ظهور نجاح وظيفتي build وdeploy.


## نشر توسعة الأدوات المالية والتشغيلية / Finance and operations release

**22 Nov 2026 / 22 نوفمبر 2026**

- اكتمل GitHub Actions run 45068809170 بنجاح: وظيفتا build وdeploy نجحتا على الفرع main.
- أضيفت تقارير قائمة الدخل والميزانية العمومية وميزان المراجعة عبر RPC محمي بصلاحيات الإدارة المالية أو accounting_view.
- جرى التحقق من اتزان القيود في قاعدة البيانات: عدد القيود غير المتوازنة = صفر. وبلغ الفرق المحاسبي في معادلة الميزانية وفق البيانات المرحلة الحالية صفرًا.
- أظهر Performance Advisor عدم وجود مفاتيح خارجية غير مفهرسة أو سياسات قراءة متكررة بعد التحسين؛ بقيت ملاحظات unused indexes من المستوى المعلوماتي فقط.
- لا يوجد اختبار يدوي شامل لجميع شاشات الموقع بحسابات موظفين وعملاء حقيقية في هذا الإصدار. أداة فتح الموقع الخارجي لم تتمكن من الوصول إلى GitHub Pages، لذلك نجاح النشر مثبت من Actions وليس من اختبار متصفح مستقل.

## محاضر تسليم الدراجات / Sale delivery receipts

**22 Nov 2026 / 22 نوفمبر 2026**

- أضيف جدول `sale_deliveries` بمحضر فريد لكل فاتورة بيع مرحلة، مع اسم المستلم وهاتفه ووقت التسليم وقراءة العداد والملحقات وحالة الدراجة وملاحظات التسليم.
- أضيف RPC محمي لتسجيل المحضر بعد التحقق من صلاحية المبيعات وحالة الفاتورة، ومنع تسجيل محضر ثانٍ لنفس الفاتورة. لا يسمح بالكتابة المباشرة على الجدول.
- أضيفت شاشة محاضر التسليم إلى أدوات المبيعات، مع قالب طباعة يتضمن توقيع المستلم ومسؤول التسليم.
- تم ربط تحميل البيانات بصلاحيات مدير/مالك/موظف المبيعات أو المالية، بدل الاقتصار على حساب admin.
- لم تُنشأ محاضر أو فواتير تجريبية؛ يلزم اختبار المحضر على فاتورة فعلية عند أول تسليم.

- اكتمل GitHub Actions run **45071402151** بنجاح على `main`: نجح `build` و`deploy` بعد إضافة محاضر التسليم وتوثيق المهاجرات. النشر مثبت من Actions؛ لم يُجرَ بعد اختبار يدوي على جهاز عميل أو حساب موظف فعلي.


## متوسط تكلفة المخزون المرجح / Weighted average inventory cost

**22 Nov 2026 / 22 نوفمبر 2026**

- أضيفت مشغلات تعيد حساب متوسط تكلفة الدراجة المرجح تلقائيًا عند استلام مشتريات أو تسجيل مرتجع مورد، مع احتساب صافي الكمية والقيمة بعد المرتجعات.
- تستخدم شاشة الجرد متوسط التكلفة المرجح في تقييم الزيادة والعجز، مع إبقاء التعديل اليدوي متاحًا للمحاسب عند وجود تسوية موثقة.
- لم تُنشأ حركات شراء أو مرتجعات تجريبية؛ تم التحقق من إنشاء المهاجرة فقط، ويلزم اختبار السيناريو على عملية استلام/مرتجع حقيقية.

- اكتمل GitHub Actions run **45071597370** بنجاح بعد تحديث متوسط تكلفة المخزون: نجح البناء والنشر. لم تُجرَ عملية شراء أو مرتجع اصطناعية لاختبار المشغلات.
