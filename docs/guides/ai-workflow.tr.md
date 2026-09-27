# AI-Native Geliştirme İş Akışı

Bu belge, projede AI araçlarıyla etkili çalışmayı tanımlar.
Bu iş akışını takip etmek daha hızlı ve daha yüksek kaliteli sonuçlar üretir.

> **English:** [docs/guides/ai-workflow.md](ai-workflow.md) — for the English version.

---

## AI-Native Döngüsü

```
1. BAĞLAM    → Kod istemeden önce AI'ya doğru bilgiyi ver
2. TASARIM   → AI kodlamadan önce tasarlasın              (/architect)
3. UYGULAMA  → Küçük adımlarla AI destekli uygulama       (/implement)
4. GÜVENLİK  → Her değişikliği risk açısından değerlendir (/security-audit)
5. İNCELEME  → AI çıktısını eleştirel gözle incele        (/review)
6. TEST      → Testleri oluştur ve çalıştır               (/test)
7. BELGE     → Bağlam tazeyken belgeleri güncelle          (/docs)
```

### Otonom Mod (ajan döngüyü yönetir)

```
JIRA backlog ──▶ /triage ──▶ /groom ──▶ /loop ──▶ PR ──▶ /deploy
                   │                      │
             domain kontrolü       görev başına tam döngü:
             kabul/red             architect → implement →
                                   security-audit → qa → PR
```

---

## Araç Genel Bakışı

| Araç | En İyi Kullanım Alanı | Ana Yapılandırma |
|------|----------------------|-----------------|
| **Claude Code** | Karmaşık ajansal görevler, çok dosya düzenleme, CLI | `AGENTS.md`, `.claude/commands/` |
| **Cursor** | Editörde kod üretimi, sohbet, otomatik tamamlama | `.cursor/rules/`, `.cursor/mcp.json` |
| **Continue** | Satır içi düzenleme, sohbet, herhangi bir IDE'de otomatik tamamlama | `.continue/config.yaml` |

---

## İnsan Destekli İş Akışı

### Adım 1: Önce Bağlam Sağla

AI araçları projenizi anladığında en iyi sonucu üretir. Bağlam şu yollarla sağlanır:

- **`AGENTS.md`** — Proje genel bakışı, komutlar, kurallar (Cursor, OpenCode, Codex, Copilot tarafından yerel olarak okunur; Claude Code bunu `CLAUDE.md` içindeki `@AGENTS.md` içe aktarmasıyla yükler)
- **`.cursor/rules/`** — Her Cursor etkileşiminde yüklenen kalıcı kurallar (dosya türüne göre otomatik)
- **`.continue/rules/`** — Her Continue isteğine dahil edilen kurallar
- **`docs/context/`** — `@docs` ile referans verebileceğiniz daha derin proje bağlamı

**Önemli bir göreve başlamadan önce**, AI'nın bağlam sahibi olduğunu doğrulayın:
> "Bu projenin mimarisi ve kodlama standartları hakkında ne biliyorsun?"

---

### Adım 2: Gereksinimleri Analiz Et

Önemsiz olmayan her özellik için önce `/requirements` çalıştırın:

```
/requirements E-posta doğrulamalı şifre sıfırlama akışı ekle
```

Bu şunları üretir: kullanıcı hikayeleri, kabul kriterleri, sıralı görev listesi ve Tamamlanma Tanımı.
Devam etmeden önce inceleyin — AI zımni gereksinimleri veya kapsam dışı öğeleri gözden kaçırabilir.

---

### Adım 3: Kodlamadan Önce Tasarla

50 satırdan büyük herhangi bir özellik için `/architect` çalıştırın:

```
/architect E-posta doğrulamalı şifre sıfırlama akışı ekle
```

Tasarım çıktısını eleştirel gözle inceleyin:
- Yaklaşım mimari ve katman sınırlarımıza uyuyor mu?
- Tüm kenar durumlar belirlendi mi?
- Risk seviyesi kabul edilebilir mi? (`high` → ikinci bir görüş alın)

Tasarımı onayladıktan sonra uygulamaya geçin.

---

### Adım 4: Küçük Adımlarla Uygula

`/implement` komutunu tüm özellik için değil, her seferinde tek bir görev için kullanın:

```
/implement TASK-001: PasswordReset varlığı ve repository arayüzü oluştur
/implement TASK-002: RequestPasswordReset kullanım senaryosunu uygula
/implement TASK-003: POST /auth/password-reset endpoint'ini ekle
```

Her adımdan sonra:
- **Üretilen kodu okuyun ve anlayın** — anlamadığınız kodu kabul etmeyin
- Linter ve tip kontrolcüsünü çalıştırın
- Değiştirilen modül için testleri çalıştırın

---

### Adım 5: Güvenlik Değerlendirmesi

Auth, kullanıcı girişi, ödemeler veya veri erişimine dokunan her değişiklik için `/security-audit` çalıştırın:

```
/security-audit diff            # yalnızca bu branch'teki değişiklikleri tara
/security-audit src/payments/   # belirli bir dizini tara
```

**CRITICAL güvenlik bulgusuyla asla PR açmayın.**

Zamanlanmış veya tam taramalar için:
```
/security-audit full    # tüm kod tabanı
/security-audit deps    # yalnızca CVE taraması
/security-audit secrets # yalnızca gizli bilgi taraması
```

**Önem derecelerine göre eylemler:**

| Önem | Anlamı | Yapılacak |
|------|--------|-----------|
| **CRITICAL** | Doğrudan iş etkisi olan istismar edilebilir açık | PR'ı bloke et, derhal düzelt |
| **HIGH** | Önemli açık, büyük olasılıkla istismar edilebilir | Bu sprint'te düzelt |
| **MEDIUM** | Belirli koşullar gerektirir | 2 sprint içinde düzelt |
| **LOW** | Savunma derinliği iyileştirmesi | Uygun olduğunda düzelt |

---

### Adım 6: Kalite Güvencesi

```
/qa
```

Şunları çalıştırır: lint → tip kontrolü → testler → kapsam → bağımlılık CVE → güvenlik özeti.
PR açmadan önce tüm engelleyici sorunları düzeltin.

---

### Adım 7: Kod İncelemesi

```
/review
```

Diff'i proje standartlarına, mimari kurallara ve OWASP kalıplarına göre denetler.
Tespit edilen her sorunu ele alın veya açıkça "düzeltilmeyecek" olarak işaretleyin ve nedenini belirtin.

---

### Adım 8: Test Üret

Uygulama sırasında testler üretilmediyse:

```
/test src/auth/password-reset.service.ts
```

Üretilen testleri doğrulayın:
- Mutlu yolu, kenar durumları ve hata durumlarını kapsamalı
- Uygulama ayrıntılarını test etmemeli
- Gerçekten hata yakalamalı (bir bug girdiğinizde başarısız olmalı)

---

### Adım 9: Belgele

Bir özelliği tamamladıktan sonra:

```
/docs src/auth/password-reset.service.ts
```

Ayrıca güncelleyin:
- `AGENTS.md` — yeni kurallar veya desenler tanıtıldıysa
- `docs/architecture/decisions/` — önemli bir mimari karar alındıysa
- `docs/context/domain-glossary.md` — yeni domain terimleri eklendiyse

---

## Otonom Ajan İş Akışı

Ajan her adım için manuel müdahale olmaksızın tam döngüyü yönetir.
Tam durum makinesi için `.initium/docs/agent/autonomous-workflow.md` dosyasına bakın.

### Ajanı başlatma

```bash
# Tam backlog'u işle (triage + gereksinim analizi)
/groom

# Belirli bir kabul edilmiş görevi uçtan uca çalıştır
/loop PROJ-42

# Yarıda kalan bir göreve kaldığı yerden devam et
/loop resume PROJ-42
```

### Ajanın otomatik yaptıkları

| Komut | Ne Yapar |
|-------|---------|
| `/groom` | JIRA'yı tarar → her issue'yu triage eder → kabul edilenlere `/requirements` çalıştırır |
| `/triage` | Domain uygunluğunu puanlar → KABUL / ESKALASYON / RED |
| `/loop` | `/architect` → branch oluştur → `/implement` (yeniden deneme döngüsü) → `/security-audit` → `/qa` → PR oluştur → CI izle → staging deployment → deployment sonrası izleme |
| `/escalate` | İnsan müdahalesi gerektiğinde Slack/GitHub'a bildirim gönderir |

### Ajan ne zaman durur ve sizden yanıt bekler?

Ajan şu durumlarda eskalasyon yapar (duraklar + bildirim gönderir):
- Triage güveni belirsiz olduğunda (0.30–0.79)
- Tasarım riski YÜKSEK olduğunda
- Testler `max_retries` denemeden sonra hâlâ başarısız olduğunda
- `/security-audit` CRITICAL veya HIGH açık bulduğunda
- `/qa` kapıları otomatik düzeltme girişimlerinden sonra başarısız olduğunda
- Üretim deployment onayı gerektiğinde (her zaman)

GitHub issue'suna veya JIRA ticket'ına yorum ekleyerek yanıt verin:

| Yorum | Etki |
|-------|------|
| `AGENT_RESUME` | Mevcut fazdan devam et |
| `AGENT_APPROVE_DESIGN` | Yüksek riskli tasarımı onayla |
| `AGENT_CLARIFY: <metin>` | Açıklama sağla ve yeniden dene |
| `AGENT_SKIP_TASK` | Mevcut alt görevi atla |
| `AGENT_REASSIGN` | İnsan geliştiriciye aktar |
| `AGENT_ABANDON` | Bu ticket'taki tüm çalışmayı durdur |

---

## Etkili Prompt Kalıpları

### Bağlam sağlama
```
Hexagonal mimari kullandığımızı, domain katmanının altyapı bağımlılığı olmadığını
ve veritabanı erişimi için Drizzle ORM kullandığımızı göz önüne alarak X'i uygula.
```

### Seçenekler sorma
```
X'i uygulamak için üç farklı yaklaşım nedir? Her biri için karmaşıklık,
performans ve test edilebilirlik açısından değerlendirme yap.
Gerekçesiyle birlikte birini öner.
```

### Minimum değişiklik isteme
```
Başarısız testi düzeltmek için yapılabilecek en küçük değişikliği yap.
Çevresindeki kodu refactor etme.
```

### Bağlamla hata ayıklama
```
Bu test şu hatayla başarısız oluyor: [hatayı yapıştır].
Test edilen fonksiyon: [kodu yapıştır].
Kök nedeni nedir? Minimum düzeltmeyi göster.
```

### AI'yı rotada tutma
```
Tasarım adımında [yaklaşımı] kullanmaya karar verdik. O yaklaşımda kal.
[Reddettiğimiz deseni] kullanma.
```

---

## Dikkat Edilmesi Gereken Tehlike İşaretleri

AI üretilen kodda şunları görürseniz duraksayın ve dikkatlice inceleyin:

- Tartışmadığınız yeni bir bağımlılık ekleniyor
- Kod tabanının geri kalanıyla tutarsız bir desen kullanılıyor
- Bir kod yolu için hata yönetimi atlanıyor
- "Gelecekteki esneklik için" gereksiz soyutlama ekleniyor
- Dokunmadığınız dosyalar değiştiriliyor
- Tartışılmamış TODO yorumları var
- Auth, yetkilendirme veya kriptografi'ye dokunuluyor — her satırı inceleyin
- Hiçbir şeyi gerçekten doğrulamayan testler üretiliyor (her zaman geçen testler)

---

## Tüm Komutlar — Hızlı Referans

### Yardım ve Navigasyon

| Komut | Amaç | Ne Zaman |
|-------|------|---------|
| `/help` | Tüm komutları ve tipik iş akışını göster | Ne yapacağından emin olmadığında her zaman |
| `/help <soru>` | "Yeni bir özelliğe nasıl başlarım?" → doğru komutu göster | Hangi komutu kullanacağından emin olmadığında |
| `/help <konu>` | "Testleri nasıl yazarım?" → konuyu komuta eşler | Belirli bir konu hakkında yönlendirme istediğinde |

> **İpucu:** `/help`, ne yapacağından emin olmadığın her durumda ilk başvurman gereken komuttur. Durumunu sade bir dille anlat — AI seni doğru iş akışına ve komutlara yönlendirir.

### İnsan Destekli Komutlar

| Komut | Amaç | Ne Zaman |
|-------|------|---------|
| `/requirements <konu>` | Kullanıcı hikayeleri, görevler, Tamamlanma Tanımı | Her özellikten önce |
| `/architect <özellik>` | Kodlamadan önce tasarım | 50 satırdan uzun görevler |
| `/implement <görev>` | Yapılandırılmış uygulama | Kodlama sırasında |
| `/security-audit [hedef]` | OWASP + CVE + gizli bilgi taraması | Her PR'dan önce |
| `/qa` | Lint, tipler, testler, kapsam | PR açmadan önce |
| `/review` | Standartlara göre kod incelemesi | Uygulamadan sonra |
| `/test <dosya>` | Kapsamlı testler üret | Herhangi bir modül için |
| `/debug <sorun>` | Sistematik hata teşhisi | Takılı kalındığında |
| `/deploy <ortam>` | Deployment öncesi kontrol listesi | Her deployment'tan önce |
| `/migrate <açıklama>` | Güvenli DB migrasyonu | Şema değişiklikleri için |
| `/sprint <tema>` | Sprint planlaması | Sprint başlangıcında |
| `/docs <dosya>` | Belgelendirme üret | Bir modül tamamlandığında |
| `/standup` | Git geçmişinden günlük özet | Günün başında |

### Otonom Ajan Komutları

| Komut | Amaç | Ne Zaman |
|-------|------|---------|
| `/triage <issue>` | Domain uygunluk kontrolü | Her JIRA issue'su için |
| `/groom` | Toplu backlog işleme | Zamanlanmış veya talep üzerine |
| `/loop <görev-id>` | Tam otonom geliştirme döngüsü | Her kabul edilmiş görev için |
| `/escalate <önem> <tetikleyici> <görev>` | İnsan bildirimi | Ajan bloke olduğunda |

---

## Bağlam Penceresi Yönetimi

Uzun oturumlarda AI araçları bağlamı kaybedebilir. Belirtiler:
- AI mimariye aykırı çözümler öneriyor
- AI daha önceki kararlara aykırı davranıyor
- AI daha önce verilen bilgileri tekrar soruyor

**Sıfırlama stratejisi:**
1. Yeni bir oturum başlatın
2. Temel dosyalara referans verin: `@AGENTS.md`, `@docs/architecture/overview.md`
3. Mevcut görevi kısaca özetleyin
4. Kaldığınız yerden devam edin

---

## Takım İş Akışı

### Kod İncelemesi
- PR'lar hangi bölümlerin AI tarafından üretildiğini belirtmeli
- AI üretimi koda da insan yazımıyla aynı inceleme standartları uygulanmalı
- Otonom ajanın PR'larını onaylamadan önce `/security-audit diff` çalıştırın

### Bilgi Paylaşımı
- Etkili bir prompt kalıbı keşfettiğinizde bu belgeye ekleyin
- AI sistematik bir hata yaparsa ilgili `.cursor/rules/` veya `.continue/rules/` dosyasına kural ekleyin
- Yeni bir domain kavramı tanıtıldığında `docs/context/domain-glossary.md` dosyasını güncelleyin
- Tekrar eden bir güvenlik kalıbı bulduğunuzda `.claude/skills/security-sast/SKILL.md` dosyasına ekleyin
