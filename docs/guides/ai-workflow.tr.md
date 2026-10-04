# AI-Native Geliştirme İş Akışı

Bu belge, projede AI araçlarıyla etkili çalışmayı tanımlar.
Bu iş akışını takip etmek daha hızlı ve daha yüksek kaliteli sonuçlar üretir.

> **English:** [docs/guides/ai-workflow.md](ai-workflow.md) — for the English version.
>
> **Hangi komutu kullanacağından emin değil misin?** `/help <sorun>` çalıştır — durumunu doğru
> komut sırasına eşler, hiçbir koda dokunmaz.

---

## AI-Native Döngüsü

```
1. BAĞLAM    → Kod istemeden önce AI'ya doğru bilgiyi ver
2. TANIMLA   → Fikri hikayelere ve kabul kriterlerine dönüştür     (/requirements)
3. TASARIM   → AI kodlamadan önce tasarlasın                       (/architect)
4. PLANLA    → Tasarımı takip edilen görevlere böl                 (/task plan)
5. UYGULAMA  → Her seferinde tek görev, AI destekli                (/task next → /implement)
6. GÜVENLİK  → Her değişikliği risk açısından değerlendir          (/security-audit)
7. DOĞRULA   → Kalite kapıları ve eleştirel inceleme               (/qa → /review)
8. BELGE     → Bağlam tazeyken belgeleri güncelle                  (/docs)
```

### Otonom Mod (ajan döngüyü yönetir)

```
Backlog ──▶ /groom ──▶ /triage (issue başına) ──▶ /requirements ──▶ /loop ──▶ PR ──▶ /deploy
               │              │                                        │
         toplu alım     domain kontrolü                       görev başına tam döngü:
                        kabul / eskalasyon / red              architect → implement →
                                                              security-audit → qa → PR
```

---

## Araç Genel Bakışı

| Araç | En İyi Kullanım Alanı | Ana Yapılandırma |
|------|----------------------|-----------------|
| **Claude Code** | Karmaşık ajansal görevler, çok dosya düzenleme, CLI | `AGENTS.md` (`CLAUDE.md` üzerinden), `.claude/commands/`, `.claude/skills/` |
| **Cursor** | Editörde kod üretimi, sohbet, otomatik tamamlama | `.cursor/rules/*.mdc`, `.cursor/mcp.json`; `.claude/commands/` ve `.claude/skills/` dizinlerini okur |
| **OpenCode** | Herhangi bir model sağlayıcısıyla terminal ajanı | `AGENTS.md`, `opencode.json`, `.opencode/commands/` (`.claude/commands/` aynası) |
| **Continue** | VS Code / JetBrains'te satır içi düzenleme, sohbet, otomatik tamamlama | `.continue/config.yaml`, `.continue/rules/` |

Tüm araçlar aynı slash komut adlarını kullanır. Komutları yalnızca `.claude/commands/` içinde
düzenleyin, ardından OpenCode aynasını yenilemek için `bash .initium/scripts/sync-opencode-commands.sh` çalıştırın.

---

## İnsan Destekli İş Akışı

### Adım 1: Önce Bağlam Sağla

AI araçları projenizi anladığında en iyi sonucu üretir. Bağlam şu yollarla sağlanır:

- **`AGENTS.md`** — Proje genel bakışı, komutlar, kurallar (Cursor, OpenCode, Codex, Copilot tarafından yerel olarak okunur; Claude Code bunu `CLAUDE.md` içindeki `@AGENTS.md` içe aktarmasıyla yükler)
- **`.cursor/rules/`** — Her Cursor etkileşiminde yüklenen kalıcı kurallar (dosya türüne göre otomatik)
- **`.claude/skills/`** — 48 teknoloji becerisi (diller, framework'ler, mobil, DevOps, güvenlik, test, tasarım). Görev veya açık dosyalar bir becerinin açıklaması ya da `paths` desenleriyle eşleştiğinde isteğe bağlı yüklenir — bkz. [`skills/README.md`](../../skills/README.md)
- **`.continue/rules/`** — Continue isteklerine dahil edilen kurallar
- **`docs/context/`** — `@docs` ile referans verebileceğiniz daha derin proje bağlamı

Büyük kod tabanlarında kod grafiğini bir kez kurun (`/codegraph setup`); ajanlar tüm dosyaları
okumak yerine sembol, çağıran ve etki analizini sorgular.

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

### Adım 4: Tasarımı Görevlere Böl

```
/task plan
```

`.agent/tasks/` altında her görev için bir Markdown dosyası oluşturur (ID, tahmin, bağımlılıklar,
kabul kriterleri, değişecek dosyalar) — kabaca PR başına bir görev. Yararlı devam komutları:

```
/task list          # tüm görevler ve durumları
/task status        # ilerleme panosu
```

---

### Adım 5: Her Seferinde Tek Görev Uygula

```
/task next                                               # sıradaki engelsiz görev
/implement TASK-001: PasswordReset varlığı ve repository arayüzü oluştur
/task done TASK-001                                      # bağımlı görevlerin önünü açar
```

Her görevden sonra:
- **Üretilen kodu okuyun ve anlayın** — anlamadığınız kodu kabul etmeyin
- Linter ve tip kontrolcüsünü çalıştırın
- Değiştirilen modül için testleri çalıştırın

Ajanın görevler arasında durmadan tüm Tamamlanma Tanımı karşılanana kadar devam etmesini
istiyorsanız `/goal <hedef>` kullanın. Görev listesi üzerinde PR oluşturma ve CI izleme dahil
tamamen otonom bir çalışma için `/loop` kullanın (aşağıdaki "Otonom Ajan İş Akışı" bölümüne bakın).

---

### Adım 6: Güvenlik Değerlendirmesi

Auth, kullanıcı girişi, ödemeler veya veri erişimine dokunan her değişiklik için `/security-audit` çalıştırın:

```
/security-audit diff            # yalnızca bu branch'teki değişiklikleri tara
/security-audit src/payments/   # belirli bir dizini tara
```

**CRITICAL güvenlik bulgusuyla asla PR açmayın.**

Zamanlanmış veya tam taramalar için:
```
/security-audit full    # tüm kod tabanı (bağımlılıklar + SAST + gizli bilgiler)
/security-audit deps    # yalnızca bağımlılık CVE taraması
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

### Adım 7: Kalite Güvencesi ve İnceleme

```
/qa
/review
```

`/qa` şunları çalıştırır: lint → tip kontrolü → testler → kapsam → bağımlılık CVE'leri → öz inceleme.
PR açmadan önce tüm engelleyici sorunları düzeltin. `/review` diff'i proje standartlarına, mimari
kurallara ve OWASP kalıplarına göre denetler. Tespit edilen her sorunu ele alın veya açıkça
"düzeltilmeyecek" olarak işaretleyip nedenini belirtin.

---

### Adım 8: Eksik Testleri Üret

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
- API sözleşmeleri için `/doc-api`, şema belgeleri için `/doc-schema`, akışlar için `/doc-diagrams`

---

## Özel İş Akışları

| Durum | Komut sırası |
|-------|-------------|
| Hata düzeltme | `/debug <belirti>` → `/implement <düzeltme>` → `/test` → `/qa` |
| Refactor / teknik borç | `/refactor <hedef>` (davranışı koruyan, test güvenlik ağıyla) → `/qa` → `/review` |
| Bağımlılık veya runtime yükseltme | `/upgrade audit` → `/upgrade <paket>`, `/upgrade security` veya `/upgrade runtime <ad> <sürüm>` → `/qa` |
| Performans sorunu | `/perf <belirti veya hedef>` — önce ölç, darboğazı düzelt, yeniden ölç |
| Yeni UI yüzeyi | `/design-system` (ürün başına bir kez) → `/design <ekran>` → `/design-review` → `/polish` → `/a11y` |
| Erişilebilirlik denetimi | `/a11y <sayfa, bileşen veya diff>` (WCAG 2.2 AA) |
| LLM destekli özellik | `/architect` → `/implement` → `/eval create <özellik>` → her prompt/model değişikliğinden sonra `/eval run` → `/qa` |
| Veritabanı şema değişikliği | `/migrate <açıklama>` (Expand-Contract + geri alma); yaşam döngüsü kontrolleri için `/db status`, `/db diff`, `/db audit` |
| Altyapı | `/infra <aws\|gcp\|azure\|onprem> init`, ardından `/infra <platform> ci\|secrets\|database\|monitoring` |
| Sürüm yayını | `/qa` → `/deploy <ortam>` → `/doc-changelog` |
| Belgelendirme seti | `/docs`, `/doc-api`, `/doc-schema`, `/doc-diagrams`, `/doc-site`, `/doc-changelog` |
| AI'ya bir kural öğretmek | `/skill new <konu>` veya `/skill update <ad>` |

---

## Otonom Ajan İş Akışı

Ajan her adım için manuel müdahale olmaksızın tam döngüyü yönetir.
Tam durum makinesi için [`.initium/docs/agent/autonomous-workflow.md`](../../.initium/docs/agent/autonomous-workflow.md) dosyasına bakın.

### Ajanı başlatma

```bash
# Backlog'u işle (triage + kabul edilenler için gereksinim analizi)
/groom

# Belirli bir kabul edilmiş görevi uçtan uca çalıştır
/loop PROJ-42

# Yarıda kalan bir göreve kaldığı yerden devam et
/loop resume PROJ-42
```

Ajanı bir sonraki güvenlik kontrolünde durdurmak için `.agent/STOP` dosyasını oluşturun.

### Ajanın otomatik yaptıkları

| Komut | Ne Yapar |
|-------|---------|
| `/groom` | Tracker'ı tarar → her issue için `/triage` → kabul edilenlere `/requirements` çalıştırır |
| `/triage` | Domain uygunluğunu puanlar → KABUL / ESKALASYON / RED |
| `/loop` | `initium-architect` → branch oluştur → `initium-implementer` (hata: `initium-debugger`) → `initium-qa` → `initium-reviewer` → `initium-security` (diff) → PR oluştur → CI izle → staging deployment → deployment sonrası izleme |
| `/escalate` | Ajan ilerleyemediğinde Slack / GitHub / tracker'a bildirim gönderir |

### Ajan ne zaman durur ve sizden yanıt bekler?

Ajan şu durumlarda eskalasyon yapar (duraklar + bildirim gönderir):
- Triage güveni belirsiz olduğunda (0.30–0.79)
- Tasarım riski ORTA veya YÜKSEK olduğunda
- Testler `max_retries` denemeden sonra hâlâ başarısız olduğunda
- `/security-audit` CRITICAL veya HIGH açık bulduğunda
- `/qa` kapıları otomatik düzeltme girişimlerinden sonra başarısız olduğunda
- Üretim deployment onayı gerektiğinde (her zaman)

GitHub issue'suna veya tracker ticket'ına yorum ekleyerek yanıt verin:

| Yorum | Etki |
|-------|------|
| `AGENT_RESUME` | Mevcut fazdan devam et (belirli bir faz için `AGENT_RESUME phase=<faz>`) |
| `AGENT_APPROVE_DESIGN` | Orta/yüksek riskli tasarımı onayla |
| `AGENT_APPROVE_DEPLOY` | Üretim deployment'ını onayla |
| `AGENT_CLARIFY: <metin>` | Açıklama sağla ve yeniden dene |
| `AGENT_SKIP_TASK` | Mevcut alt görevi atla |
| `AGENT_REJECT` | Belirsiz bir triage sonucunu reddet |
| `AGENT_REASSIGN` | İnsan geliştiriciye aktar |
| `AGENT_ABANDON` | Bu ticket'taki tüm çalışmayı durdur |

Tüm eskalasyon kuralları: [`.initium/docs/agent/escalation-protocol.md`](../../.initium/docs/agent/escalation-protocol.md).

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
- GitHub Action veya container imajı sabitlenmiş SHA/digest yerine tag ile ekleniyor
- Auth, yetkilendirme veya kriptografi'ye dokunuluyor — her satırı inceleyin
- Hiçbir şeyi gerçekten doğrulamayan testler üretiliyor (her zaman geçen testler)

---

## Tüm Komutlar — Hızlı Referans

`/help` bu kataloğu AI aracınızın içinde yazdırır; aşağıdaki tablolar onunla aynıdır.

### Kurulum ve yardım

| Komut | Amaç |
|-------|------|
| `/help [soru]` | Tüm komutları göster veya bir soruyu doğru komut sırasına eşle |
| `/init <açıklama>` | Tüm TODO yer tutucularını doldur; kapsamlı modlar `domain:`, `stack:`, `ci:`, `agent:` |
| `/sync-initium [--check\|--dry-run]` | En son Initium güncellemelerini projeye çek |

> **İpucu:** `/help`, ne yapacağından emin olmadığın her durumda ilk başvurman gereken komuttur. Durumunu sade bir dille anlat — AI seni doğru iş akışına ve komutlara yönlendirir.

### Planlama ve tasarım

| Komut | Amaç |
|-------|------|
| `/requirements <konu>` | Kullanıcı hikayeleri, kabul kriterleri, görevler, Tamamlanma Tanımı |
| `/architect <özellik>` | Risk seviyesiyle birlikte kodlamadan önce tasarım |
| `/task plan\|list\|next\|done <ID>\|status` | `.agent/tasks/` altında görev dosyaları oluştur ve takip et |
| `/sprint <tema>` | Sprint planlaması: kapasite, backlog, riskler |

### Geliştirme

| Komut | Amaç |
|-------|------|
| `/implement <görev>` | Testlerle birlikte yapılandırılmış alt-üst uygulama |
| `/goal <hedef>` | Tek bir hedefi, yarıda durmadan Tamamlanma Tanımına kadar sürdür |
| `/refactor <hedef>` | Test güvenlik ağıyla davranışı koruyan refactor |
| `/upgrade [audit\|security\|runtime <ad> <sürüm>\|<paket>]` | Bağımlılıkları ve runtime'ları denetle veya yükselt |
| `/debug <sorun>` | Sistematik hata teşhisi: hipotez → düzeltme → önleme |

### Kalite ve inceleme

| Komut | Amaç |
|-------|------|
| `/test <dosya>` | Kapsamlı testler üret |
| `/qa` | Lint, tipler, testler, kapsam, bağımlılık CVE'leri, öz inceleme |
| `/review` | Standartlara, mimari kurallara ve OWASP'a göre kod incelemesi |
| `/security-audit [diff\|full\|deps\|secrets\|<yol>]` | OWASP SAST + CVE + gizli bilgi taraması |
| `/perf <hedef>` | Performans darboğazını ölç, bul ve düzelt |
| `/a11y <kapsam\|diff>` | WCAG 2.2 AA'ya göre erişilebilirlik denetimi ve düzeltmeleri |
| `/eval create\|run\|compare` | LLM destekli özellikler için değerlendirme setleri |

### UI ve görsel tasarım

| Komut | Amaç |
|-------|------|
| `/design <ekran veya akış>` | Şablon gibi değil, bilinçli ve yerel görünen UI tasarla ve oluştur |
| `/design-review <kapsam\|diff>` | Şablon izleri, işçilik ve Apple HIG / Material 3 uyumu için salt okunur inceleme |
| `/polish <kapsam\|diff>` | Son görsel kalite geçişi (durumlar, boşluklar, tutarlılık) |
| `/design-system [seed\|check\|tokens]` | `DESIGN.md` / `PRODUCT.md` ve tasarım token'larını oluştur veya yenile |

### Bağlam ve bilgi

| Komut | Amaç |
|-------|------|
| `/codegraph [setup\|status\|query\|impact\|refresh]` | Sembol, çağıran ve etki sorguları için kod grafiği |
| `/skill [new\|update\|list]` | `.claude/skills/` altında Agent Skills oluştur, güncelle veya listele |

### Belgelendirme

| Komut | Amaç |
|-------|------|
| `/docs <dosya veya özellik>` | Kod düzeyinde belgeler, mimari belgeler veya kullanıcı kılavuzları |
| `/doc-api` | Tam OpenAPI 3.x spec |
| `/doc-schema` | ER diyagramlarıyla veritabanı şeması |
| `/doc-diagrams [akış\|all]` | API ve iş akışları için Mermaid sequence diyagramları |
| `/doc-site` | Belgelendirme sitesini iskelet olarak kur veya yeniden üret |
| `/doc-changelog` | Git geçmişinden `CHANGELOG.md` üret veya güncelle |

### Veritabanı, altyapı, deployment

| Komut | Amaç |
|-------|------|
| `/migrate <açıklama>` | Güvenli DB migrasyonu (Expand-Contract + geri alma planı) |
| `/db init\|create\|dml\|seed\|status\|diff\|audit` | Migrasyon araçları ve veritabanı yaşam döngüsü |
| `/infra <platform> <alt-komut>` | Terraform, Kubernetes veya CI/CD yapılandırmaları iskeleti |
| `/deploy <ortam>` | Deployment öncesi kontrol listesi, yürütme, izleme planı |

### Operasyon ve otonom ajan

| Komut | Amaç |
|-------|------|
| `/standup` | Git geçmişinden günlük özet |
| `/triage <issue>` | Tracker issue'su için domain uygunluk kontrolü |
| `/groom` | Toplu backlog işleme (triage + gereksinimler) |
| `/loop <görev-id>` / `/loop resume <görev-id>` | Tam otonom geliştirme döngüsü |
| `/escalate <önem> <tetikleyici> <görev-id>` | Bloke olunduğunda yapılandırılmış insan bildirimi |

---

## Bağlam Penceresi Yönetimi

Uzun oturumlarda AI araçları bağlamı kaybedebilir. Belirtiler:
- AI mimariye aykırı çözümler öneriyor
- AI daha önceki kararlara aykırı davranıyor
- AI daha önce verilen bilgileri tekrar soruyor

**Sıfırlama stratejisi:**
1. Yeni bir oturum başlatın
2. Temel dosyalara referans verin: `@AGENTS.md`, `@docs/architecture/overview.md`, mevcut `.agent/tasks/TASK-*.md`
3. Mevcut görevi kısaca özetleyin
4. Kaldığınız yerden devam edin

Oturumları baştan küçük tutmak için: tüm dosyaları okumak yerine `/codegraph query` / `/codegraph impact`
kullanın ve teknoloji rehberliğini prompt'a yapıştırmak yerine becerilerin isteğe bağlı yüklenmesine izin verin.

---

## Takım İş Akışı

### Kod İncelemesi
- PR'lar hangi bölümlerin AI tarafından üretildiğini belirtmeli
- AI üretimi koda da insan yazımıyla aynı inceleme standartları uygulanmalı
- Otonom ajanın PR'larını onaylamadan önce `/security-audit diff` çalıştırın

### Bilgi Paylaşımı
- Etkili bir prompt kalıbı keşfettiğinizde bu belgeye ekleyin
- AI sistematik bir hata yaparsa `.cursor/rules/` altına kural ekleyin veya ilgili beceriyi `/skill update <ad>` ile güncelleyin
- Yeni bir domain kavramı tanıtıldığında `docs/context/domain-glossary.md` dosyasını güncelleyin
- Tekrar eden bir güvenlik kalıbı bulduğunuzda `.claude/skills/security-sast/SKILL.md` dosyasına (veya dilin `reference/` dosyasına) ekleyin
