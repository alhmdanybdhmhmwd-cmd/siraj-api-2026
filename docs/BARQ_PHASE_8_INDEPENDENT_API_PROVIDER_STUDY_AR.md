# المرحلة 8 — دراسة مسار API مستقل عن Cloudflare (2026-11-21)

## القرار الفني الحالي
لا يُفعّل أي بديل في الإنتاج الآن. المرشح الأقوى للدراسة العملية هو AWS Lambda Web Functions + API Gateway، مع خدمة بيانات مستقلة عن D1 عند تنفيذ الترحيل. هذا ليس قرار شراء أو ترحيل نهائي؛ يجب أولاً إثبات الوصول من شبكات اليمن دون VPN، وحساب التكلفة الفعلية، وإعداد مزامنة بيانات آمنة.

## لماذا لا يكفي العامل الاحتياطي الحالي؟
- `barq-api-phase2-fallback-test` يعمل على Cloudflare Workers مثل العامل الأساسي، ويشارك موارد Preview نفسها.
- يفيد في اختبار تعطل Worker الأساسي، لكنه لا يعالج انقطاع Cloudflare أو حجب نطاقات workers.dev أو مسار Cloudflare نفسه.
- لا يملك Cron عمداً حتى لا ينفذ تنظيف D1 بالتوازي مع العامل الأساسي على قاعدة البيانات المشتركة. لا بد من منسق failover ينقل ملكية المهام المجدولة حصرياً، وإلا قد تتكرر عمليات التنظيف.
- لا يوجد عنوان fallback مفعّل في Vercel حالياً.

## مقارنة المرشحين
### AWS Lambda Web Functions + API Gateway — المرشح الأول
- AWS Lambda Web Functions تشغل خادم HTTP Node.js عادياً وتوفر HTTPS endpoint، وتذكر وثائق AWS إمكانية التوزيع على مناطق متعددة خلف نقطة نهاية واحدة.
- API Gateway يدعم HTTP APIs وWebSocket APIs؛ وتعرض صفحة التسعير مليون طلب HTTP API ومليون طلب REST API شهرياً ضمن Free Tier لمدة تصل إلى 12 شهراً للحسابات المؤهلة، مع تكاليف إضافية محتملة للنقل والخدمات الأخرى.
- توجد بيئة Node.js مدارة، لكن كود Worker الحالي لا يعمل هناك كما هو: يعتمد على D1 binding وWorkers AI وواجهات Cloudflare Worker. يلزم adapter وإعادة تنفيذ طبقة البيانات/الذكاء الاصطناعي، لا مجرد نسخ ملف `index.js`.
- يجب اختيار منطقة مناسبة بعد قياس الوصول، ودراسة RDS/PostgreSQL أو قاعدة مستقلة متوافقة، وS3 للملفات، ومزامنة/ترحيل البيانات قبل أي cutover.

### Fly.io — مرشح ثانٍ
- يوفر شبكة Anycast وعنوان IPv4 مشتركاً وIPv6، ويمكن تخصيص IPv4 مقابل تكلفة شهرية؛ كما تختلف أسعار نقل البيانات حسب المنطقة.
- يمكن تشغيل Node.js/containers، لكن يلزم أيضاً نقل طبقة البيانات خارج D1 أو إنشاء واجهة بيانات مستقلة. ليس حلاً فورياً بمجرد نشر الحاوية.
- لا يوجد دليل أن الوصول من شبكات اليمن مضمون؛ يلزم اختبار عملي.

### Render — مرشح ثالث
- المناطق المعلنة تشمل Oregon وOhio وVirginia وFrankfurt وSingapore.
- الأسعار المنشورة تتضمن خدمة مجانية محدودة، وخدمة 512MB تبدأ من 7 دولارات شهرياً، إضافة إلى النقل والتخزين وقاعدة البيانات حسب الاستخدام.
- مناسب لنموذج Node.js مستقل، لكن محدودية المناطق وعدم وجود إثبات وصول من اليمن يجعلان اختباره لاحقاً قبل اعتماده.

## توصية التنفيذ الآمن
1. إبقاء Cloudflare الحالي دون تغيير، وعدم توجيه التطبيق أو DNS إلى أي بديل.
2. بناء نموذج API مستقل في بيئة اختبار، مع عقد موحد للـREST ورفع/تنزيل الوسائط، ومفاتيح idempotency، وRange، وCORS، وحدود الأحجام.
3. عدم ربط النموذج بقاعدة الإنتاج أو تخزين الإنتاج. استخدام بيانات اصطناعية وموارد اختبار منفصلة.
4. تنفيذ مقارنة فعلية من يمن نت ويمن موبايل وشبكة يمنية إضافية دون VPN: DNS A/AAAA، TLS، health/live، health/ready، REST، WebSocket عند الحاجة، رفع وتنزيل صغير وكبير، Range، وقياس latency/error rate.
5. اختبار مزود بديل من بلد آخر لا يكفي لإثبات الوصول من اليمن. لا يتم إعلان حل VPN قبل الاختبار اليمني.
6. قبل الترحيل، تصميم نقل قاعدة البيانات مع تحقق row counts/checksums، وتزامن تغييرات تدريجي، ونسخ احتياطية واستعادة مجربة، وخطة rollback.
7. لا تغيير DNS أو تطبيق أو Worker إنتاج أو Tigris bucket، ولا تفعيل fallback، إلا بعد إثبات الوصول من اليمن دون VPN وموافقة المستخدم الصريحة.

## المراجع الرسمية
- AWS Lambda Web Functions: https://docs.aws.amazon.com/lambda/latest/lambda-web/
- AWS Lambda Web Functions for Node.js: https://docs.aws.amazon.com/lambda/latest/dg/web-functions-nodejs.html
- AWS API Gateway pricing: https://aws.amazon.com/api-gateway/pricing/
- AWS Lambda pricing: https://aws.amazon.com/lambda/pricing/
- Fly.io regions: https://fly.io/docs/reference/regions/
- Fly.io pricing: https://fly.io/docs/about/pricing/
- Render regions: https://render.com/docs/regions
- Render pricing: https://render.com/pricing
- Cloudflare D1 external access pattern: https://developers.cloudflare.com/d1/tutorials/build-an-api-to-access-d1/

## حالة الإثبات
- اكتمل تحليل بنية Preview والعامل الاحتياطي.
- أضيف Workflow لفحص إعدادات Wrangler دون نشر أو أسرار.
- لا يوجد حتى الآن مزود مستقل منشور أو اختبار يمني دون VPN.
- لا يوجد أي تغيير إنتاج أو DNS أو تخزين إنتاج ضمن هذا العمل.
