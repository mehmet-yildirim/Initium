# Takım Oluşturma Kılavuzu — AI-Native Geliştirme

Bu kılavuz, Initium ile çalışırken insan takımlarının nasıl yapılandırılması ve optimize edilmesi gerektiğini tanımlar. AI araçları tekrarlayan işleri, şablonları ve mekanik akıl yürütmeyi üstlenir — takımın işi ise yargı, bağlam ve denetimdir.

> **TODO bölümlerini doldurun** — projeye özgü kişiler ve iletişim bilgileriyle.

> **English:** İngilizce sürüm için [docs/guides/team.md](team.md) dosyasına bakın.

---

## Temel İlke: Daha Az Ama Daha Odaklı Mühendisler

AI bireysel üretkenliği çarpar. 3–6 kişilik, net sahipliğe sahip, derin alan bilgisine ve güçlü AI işbirliği becerilerine sahip küçük bir takım, bu yığında daha büyük geleneksel bir takımı sürekli olarak geride bırakır.

**Takımınızın çabasını yönlendirin:**

| Geleneksel takım zamanını harcadığı yer | AI-native takım zamanını harcadığı yer |
|-----------------------------------------|----------------------------------------|
| Şablon ve iskelet kod yazma | AI tarafından üretilen kodu eleştirel gözle inceleme |
| Belge ve Stack Overflow arama | AI akıl yürütmesini ve çıktısını doğrulama |
| Mekanik yeniden yapılandırma | Mimari kararlar ve alan modellemesi |
| Tekrarlayan test yazma | Anlamlı test senaryoları tasarlama |
| Belgelerin ilk taslağını yazma | AI tarafından üretilen belgeleri doğrulama ve iyileştirme |

Kıdemli-acemi mühendis oranı değişir: **kıdemli veya orta seviye mühendisleri tercih edin** — AI çıktısını güvenle değerlendirebilirler. Acemi mühendisler, AI çıktısını eleştirisiz kabul etmemek için daha güçlü mentorluk gerektirir.

---

## Takım Rolleri

### Teknik Lider / Mimar

**Ne yapar:**
- `docs/architecture/overview.md` ve `docs/architecture/decisions/` içindeki tüm ADR'lerin sahibidir
- Hekzagonal mimari sınırlarını ve tasarım deseni standartlarını tanımlar ve uygular
- `/architect` tarafından işaretlenen yüksek riskli tasarımları onaylar (`risk=HIGH` tetiklendiğinde)
- Yapısal değişiklikler içeren otonom ajan PR'larını birleştirmeden önce inceler
- `AGENTS.md`'yi korur — AI ajanlarının projeyi nasıl anladığının tek doğru kaynağı
- `/sync-initium` aracılığıyla yeni Initium özelliklerinin ne zaman benimseneceğine karar verir

**AI-native sorumluluklar:**
- Otonom ajan mimari kararları artırdığında JIRA/GitHub'da `AGENT_APPROVE_DESIGN` ayarlar
- Katman sınırlarını ihlal eden veya uygunsuz desenler içeren AI tarafından üretilen kod birleştirmelerini engeller
- Ajanın `.initium/docs/agent/` yapılandırmasını ve ayarlamalarını inceler

**TODO: Atanan kişi:** `<isim>`

---

### Alan Sahibi (Domain Owner)

**Ne yapar:**
- `docs/context/domain-boundaries.md`'yi korur — otonom ajan triyajı için en kritik dosya
- Hangi JIRA/Linear/GitHub issue'larının kapsam dahilinde, hangilerinin diğer takımlara ait olduğunu tanımlar
- Ajanın doğru terminoloji kullanması için `docs/context/domain-glossary.md`'yi korur
- Ajan alan uygunluğundan emin olamadığında `/escalate` bildirimlerine yanıt verir (triyaj güveni 0,30–0,79)

**AI-native sorumluluklar:**
- Ajanı yönlendirmek için artırılmış biletlere `AGENT_CLARIFY: <açıklama>` yazar
- Triyaj kararlarını düzenli olarak inceler — ajan issue'ları yanlış sınıflandırıyorsa `domain-boundaries.md`'yi günceller
- Alan modelinin sahibidir; AI önerir, alan sahibi onaylar

**Her sınırlı bağlam için bir alan sahibi hedeflenir. Küçük takımlarda Teknik Lider, Alan Sahibi görevini de üstlenir.**

**TODO: Alanlara göre alan sahipleri:**
- `<alan adı>` → `<isim>`
- `<alan adı>` → `<isim>`

---

### Kıdemli / Orta Seviye Geliştirici

**Ne yapar:**
- Günlük özellik geliştirme için AI araçlarını kullanır (`/requirements`, `/architect`, `/implement`, `/qa`, `/review`)
- Commit yapmadan önce AI tarafından üretilen her satırı okur ve eleştirel olarak değerlendirir
- `/implement`'in doğru çalışması için yeterince ayrıntılı kabul kriterleri ve görev açıklamaları yazar
- Açtığı branch'in kalitesinin sahibidir — AI üretir, insan doğrular

**AI-native sorumluluklar:**
- Her PR'da istisnasız `/security-audit diff` çalıştırır
- PR açmadan önce `/qa` çalıştırır; başarısız kapıları olan PR'lar açmaz
- AI çıktısı yanlış olduğunda, kodu düzeltir VE ilgili kuralı `.cursor/rules/` veya AGENTS.md'de günceller — hatanın tekrarlanmaması için
- `docs/guides/ai-workflow.md`'de "Etkili Prompt Kalıpları" altında etkili prompt kalıplarını paylaşır

**TODO: Takım üyeleri:** `<isimler veya takım listesi linki>`

---

### AI İş Akışı Koordinatörü

**Ne yapar:**
- Tüm AI araçlarının takım genelinde sorunsuz çalışmasını sağlar
- Initium güncellemeleri mevcut olduğunda `/sync-initium` çalıştırır; `merge_required` dosyalarını takımla koordineli olarak birleştirir
- `.cursor/rules/`, `.continue/rules/` ve AGENTS.md kurallarını korur
- `.claude/skills/` dizinini `/skill update <ad>` ile güncel tutar; projeye özgü becerileri `/skill new <konu>` ile ekler
- Hangi komutların az kullanıldığını veya kafa karışıklığına yol açtığını takip eder; promptları iyileştirir veya kalıpları belgeler
- `.cursor/mcp.json` ve `.claude/settings.json`'ı yönetir — MCP sunucularını ve araç izinlerini etkinleştirir/devre dışı bırakır
- `agent.config.yaml` ayarlamalarının sahibidir: güven eşikleri, yeniden deneme limitleri, otonom mod ayarları

**Bu rol ayrı bir kadro gerektirmez.** 3–5 kişilik takımlarda Teknik Lider veya kıdemli bir geliştirici bu göreve döner. 8+ kişilik daha büyük takımlarda bir mühendisin zamanının %20–30'unu bu role ayırın.

**AI-native sorumluluklar:**
- Beklenmeyen davranışlar için `.agent/audit/` içindeki otonom ajan denetim günlüklerini izler
- Ajan issue'ları aşırı veya yetersiz kabul ettiğinde triyaj güven eşiklerini ayarlar
- Takıma sunmadan önce Initium güncellemelerini inceler ve test eder

**TODO: Atanan kişi:** `<isim>`

---

### Güvenlik Şampiyonu

**Ne yapar:**
- Periyodik `/security-audit full` taramaları çalıştırır (haftalık veya her sürümde)
- Herhangi bir PR'ın `/security-audit diff`'inden gelen tüm `CRITICAL` ve `HIGH` bulgularını inceler
- OWASP kontrol listesini ve `.cursor/rules/05-security.mdc`'deki güvenlik kurallarını korur
- Çözülmüş olsa bile HIGH bulgu içeren herhangi bir PR'ın dağıtımını onaylar

**AI-native sorumluluklar:**
- Otonom ajan `/security-audit`'i otomatik çalıştırır — Güvenlik Şampiyonu yalnızca kodu değil, üretilen raporları da inceler
- AI yeni bir güvenlik deseni (iyi veya kötü) sunduğunda, deseni pekiştirmek veya engellemek için `.claude/skills/security-sast/SKILL.md`'yi günceller
- Bağımlılık ve CI tedarik zinciri politikasının sahibidir (`.claude/skills/security-supply-chain/`): sabitlenmiş action'lar, SBOM, provenance, `/upgrade security` sıklığı
- İncelenmemiş güvenlik bulgularına sahip herhangi bir üretim dağıtımı için `AGENT_APPROVE_DEPLOY`'u engeller

**Küçük takımlarda, Teknik Lider veya en güvenlik bilincine sahip geliştirici bu görevi üstlenir.**

**TODO: Atanan kişi:** `<isim>`

---

## Karar Yetki Matrisi

Net sahiplik, ajanın doğru insanın doğru kararı onaylaması olmadan ilerlemesini engeller.

| Karar | Kim karar verir | Otonom ajan tetikleyicisi |
|-------|-----------------|---------------------------|
| Mimari yaklaşım (yüksek riskli) | Teknik Lider | `/escalate` → `AGENT_APPROVE_DESIGN` |
| Alan sınırı (bu issue kapsam dahilinde mi?) | Alan Sahibi | `/escalate` → `AGENT_CLARIFY:` |
| Üretim dağıtımı | Teknik Lider + Güvenlik Şampiyonu | `/escalate` → `AGENT_APPROVE_DEPLOY` |
| CRITICAL güvenlik bulgusu | Güvenlik Şampiyonu | `/escalate` → dağıtımı engeller |
| Main'e birleştirme (otomatik PR) | Herhangi bir kıdemli geliştirici inceleyici | GitHub PR incelemesi |
| Initium güncellemesi (merge_required dosyalar) | AI İş Akışı Koordinatörü | `/sync-initium` incelemesi |
| Ajanı terk etme / yeniden atama | Alan Sahibi veya Teknik Lider | `AGENT_REASSIGN` veya `AGENT_ABANDON` |

---

## Takım Büyüklüğü Önerileri

### 1–3 kişi (solo / mikro takım)

- Teknik Lider her şeyi yapar: mimari, alan sahipliği, AI iş akışı koordinasyonu
- Yarı-otonom ajan modu kullanın (`mode: semi-autonomous` in `agent.config.yaml`) — ajan üretir, insan her PR'dan önce onaylar
- Her PR en az bir başka kişi tarafından incelenmelidir (harici inceleyici veya akran)
- Öncelikler: `AGENTS.md` kalitesi, alan sınırları doğruluğu, her birleştirmeden önce güvenlik denetimi

### 3–6 kişi (standart takım)

- Teknik Lider, mimari + eskalasyon onaylarının sahibidir
- 1–2 geliştirici belirli alan alanlarına sahip olur
- AI İş Akışı Koordinatörü rolü üç ayda bir döner
- Güvenlik Şampiyonu rolü en güvenlik bilincine sahip geliştiriciye atanır (yarı zamanlı)
- Ajan, alan başına yarı-otonom veya seçici-otonom modda çalışabilir
- Haftalık 30 dakikalık "AI iş akışı retrospektifi": neyin işe yaradığı, ajanın neyi yanlış yaptığı, hangi kuralların güncellenmesi gerektiği

### 7–15 kişi (ölçeklendirilmiş takım)

- Tam rol ayrımı: Teknik Lider, 2–3 Alan Sahibi, özel AI İş Akışı Koordinatörü (yarı zamanlı), Güvenlik Şampiyonu
- Initium'u, MCP sunucularını ve ajan altyapısını sahiplenen bir **platform alt takımı** (1–2 kişi) oluşturun
- Her alan sahibi, alanının `domain-boundaries.md` girdilerini yönetir
- Ajan, kabul edilen düşük riskli issue'lar için tam otonom modda çalışır
- İki haftada bir mimari inceleme toplantısı: Teknik Lider + alan sahipleri ajan ADR'lerini inceler
- Takımlar arası: Birden fazla takım bir monorepo paylaşıyorsa, her takımın kendi alan sınırları ve triyaj kapsamı vardır

---

## Yeni Takım Üyesini İşe Alma

Yeni mühendislerin hızla verimli hale gelmesi için:

1. **1. Gün — Bağlam okuma:** `docs/context/project-brief.md`, `docs/context/tech-stack.md`, `docs/architecture/overview.md` ve bu dosyayı okuyun. Ardından `AGENTS.md`'yi okuyun.
2. **1. Gün — AI araç kurulumu:** Claude Code'u yüklemek, Cursor veya Continue'yu yapılandırmak için `docs/guides/onboarding.tr.md`'yi takip edin. `bash .initium/scripts/validate.sh` ile doğrulayın.
3. **2. Gün — İlk `/help`:** `/help ilk görevimi nasıl alırım?` çalıştırın ve talimatları izleyin. AI iş akışı kurulumunu tamamlamadan kod yazmaya başlamayın.
4. **İlk hafta — Gölgelendirilen PR:** Yeni mühendis, tam AI döngüsünü kullanarak bir `good-first-issue` uygular (`/requirements` → `/architect` → `/task plan` → `/implement` → `/qa` → `/review`). Kıdemli bir geliştirici yalnızca son diff'i değil her adımı inceler.
5. **İlk ay — otonom mod yok:** Yeni mühendisler yalnızca insan destekli komutları kullanır. AI çıktısını güvenle inceleyebildikten sonra otonom mod (`/loop`).

**Erken aşılanması gereken temel zihniyet:** AI yetenekli bir işbirlikçidir, bir kehanet değil. Üretilen her satırı okuyun. Her deseni sorgulayın. Çıktıdan insan sorumludur.

---

## Kaçınılması Gereken Anti-Desenler

| Anti-desen | Neden başarısız olur |
|---|---|
| AI PR'larını diff'i okumadan birleştirme | AI, bakışta iyi görünen ancak ince hatalar, yanlış desenler veya güvenlik sorunları içerebilir |
| "AI genellikle güvenlidir" diye `/security-audit diff`'i atlama | AI sıklıkla kimlik doğrulama kontrollerini, girdi doğrulamayı ve enjeksiyon risklerini kaçırır |
| Alan sınırları tanımlanmadan ajanın otonom çalışmasına izin verme | Ajan kapsam dışı issue'ları kabul eder ve alakasız veya zararlı değişiklikler üretir |
| AGENTS.md'yi tek seferlik kurulum olarak değerlendirme | Proje gelişir; kurallar değiştiğinde veya ajan sistematik hatalar yaptığında AGENTS.md güncellenmelidir |
| İnsan incelemesi olmadan mimari kararlar için AI kullanma | Mimari, AI'nın tam olarak değerlendiremeyeceği ödünleşimler içerir — iş bağlamı, takım kapasitesi, operasyonel maliyet |
| AI bir desen hatası yaptığında `.cursor/rules/`'u güncellememek | Hata her gelecek oturumda tekrarlanır |
| Çok erken aşırı otomatikleştirme | Yarı-otonom ile başlayın, tam otonomluğu etkinleştirmeden önce ajanın triyaj doğruluğuna güven kazanın |

---

## Daha Fazla Okuma

| Belge | İçerik |
|-------|--------|
| `AGENTS.md` | Proje kuralları — AI'nın birincil talimat dosyası |
| `docs/guides/ai-workflow.tr.md` | Tam AI-native geliştirme iş akışı referansı |
| `docs/guides/onboarding.tr.md` | Yeni geliştiriciler için adım adım kurulum |
| `docs/context/domain-boundaries.md` | Otonom ajanın üzerinde çalışacağı ve çalışmayacağı şeyler |
| `.initium/docs/agent/autonomous-workflow.md` | Ajan durum makinesi, eskalasyon kapıları, devam etme mantığı |
| `.initium/docs/agent/escalation-protocol.md` | Eskalasyon önem seviyeleri ve insan yanıt prosedürleri |
| `skills/README.md` | 48 teknoloji becerisinin dizini ve her birinin kapsamı |
| `agent.config.yaml` | Otonom ajan yapılandırması — mod, eşikler, tracker anahtarları |
