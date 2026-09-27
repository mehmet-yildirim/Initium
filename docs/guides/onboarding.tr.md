# Geliştirici Başlangıç Kılavuzu

Projeye hoş geldin. Bu kılavuz seni sıfırdan verimli bir şekilde çalışmaya mümkün olan en kısa sürede kavuşturmak için hazırlandı.

> **English:** İngilizce sürüm için [docs/guides/onboarding.md](onboarding.md) dosyasına bakın.

---

## Ön Koşullar

Başlamadan önce:

- [ ] TODO: Gerekli araçları listele (ör. Node.js 22+, Docker, Git, vb.)
- [ ] TODO: Gerekli servislere erişim (ör. AWS hesabı, veritabanı, gizli anahtarlar)
- [ ] Git'i iş e-postanla yapılandır: `git config --global user.email "sen@sirket.com"`
- [ ] Bir AI kodlama aracı: [Cursor](https://cursor.com), [VS Code + Continue](https://continue.dev), [Claude Code](https://claude.ai/code) veya [OpenCode](https://opencode.ai)

---

## İlk Kurulum

> **Initium'u zaten kodu olan bir repoya mı ekliyorsunuz?** Initium'u klonlamayın —
> [existing-project.tr.md](existing-project.tr.md) kılavuzunu izleyin, ardından
> [AI Araçlarını Kurma](#ai-araçlarını-kurma) bölümünden devam edin.

### macOS / Linux

```bash
# 1. Klonla
git clone <repo-url>
cd <proje-adı>

# 2. Başlat (git, .env, yapılandırma kontrolleri)
./.initium/scripts/setup.sh

# 3. Etkileşimli sihirbazı çalıştır — proje adı, teknoloji yığını, tracker anahtarlarını doldurur
bash .initium/scripts/init.sh

# 4. AI'nın kalan TODO dosyalarını doldurmasına izin ver
claude
/init <kullanıcılar> için <tür> türünde <ad> adlı bir proje geliştiriyorum. Yığın: <dil, framework, DB>.

# 5. Her şeyin yerli yerinde olduğunu doğrula
bash .initium/scripts/validate.sh   # beklenen: tüm PASS, FAIL yok
```

### Windows (PowerShell — önerilir)

```powershell
# Bir kez: betik çalıştırmaya izin ver
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

.\.initium\scripts\setup.ps1
.\.initium\scripts\init.ps1
# Ardından Claude Code'u aç ve yukarıdaki /init komutunu çalıştır
.\.initium\scripts\validate.ps1
```

### Windows (Batch — izin gerekmez)

```bat
.initium\scripts\setup.cmd
.initium\scripts\init.cmd
.initium\scripts\validate.cmd
```

### Sihirbazdan sonra — manuel olarak doldur

```bash
cp .env.example .env      # kimlik bilgilerini ve API anahtarlarını doldur

# TODO: yerel bağımlılıkları başlat
# ör. docker compose up -d

# TODO: uygulama bağımlılıklarını yükle
# ör. bun install / pip install -e ".[dev]" / go mod tidy

# TODO: veritabanı migrasyonlarını çalıştır
# ör. bun db:migrate / alembic upgrade head

# TODO: uygulamanın çalıştığını doğrula
# ör. bun test / bun dev → http://localhost:3000 adresini aç
```

---

## Projeyi Anlamak

Herhangi bir kod yazmadan önce bu belgeleri sırayla oku:

| Belge | İçerik |
|-------|--------|
| `docs/context/project-brief.md` | Bu projenin ne yaptığı ve kimin için olduğu |
| `docs/context/tech-stack.md` | Teknoloji seçimleri ve gerekçeleri |
| `docs/architecture/overview.md` | Sistemin nasıl yapılandırıldığı |
| `AGENTS.md` | Kodlama kuralları, temel komutlar, mimari özeti |
| `docs/context/domain-glossary.md` | İş terminolojisi — herhangi bir şeyi adlandırmadan önce oku |
| `docs/guides/team.tr.md` | Kimin neye sahip olduğu, eskalasyon zinciri, karar yetkisi |
| `docs/context/domain-boundaries.md` | Kapsam tanımı (otonom ajan için kritik) |

---

## AI Araçlarını Kurma

> **İpucu:** AI aracın kurulduktan sonra, hangi komutu kullanacağından emin olmadığın her durumda `/help` her zaman başlangıç noktandır. Durumunu AI'ya anlat — seni doğru yöne yönlendirir.

### Claude Code

```bash
# Yükle (native installer — önerilen; npm ile kurulum kullanımdan kaldırıldı)
curl -fsSL https://claude.ai/install.sh | bash      # Windows PowerShell: irm https://claude.ai/install.ps1 | iex

# Başlat — AGENTS.md otomatik olarak yüklenir (CLAUDE.md onu içe aktarır)
claude
```

40 özel komutun tamamı (`/` yazarak görebilirsin; aynı adlar Cursor ve OpenCode'da da çalışır):

```
# --- Yardım ve kurulum (emin değilsen buradan başla) ---
/help [soru]      — tüm komutları göster veya "… nasıl yaparım?" sorusunu doğru komut sırasına eşle
/init             — serbest biçimli proje açıklamasından tüm TODO dosyalarını doldur
                    (kapsamlı: /init domain: … | stack: … | ci: … | agent: …)
/sync-initium     — üst Initium'daki yeni geliştirmeleri çek

# --- Planlama ve tasarım ---
/requirements     — gereksinimleri analiz et → kullanıcı hikayeleri, görevler, Tamamlanma Tanımı
/architect        — tek satır kod yazmadan önce tasarım yap
/task plan        — tasarımı takip edilen .agent/tasks/*.md dosyalarına böl (PR başına bir tane)
/task next|list|status|done <id> — görevleri seç, takip et ve tamamla
/sprint           — sprint planlaması: kapasite, backlog, görevler, risk kaydı

# --- Geliştirme ---
/implement        — testlerle birlikte yapılandırılmış alt-üst uygulama
/goal             — tek bir hedefi yarıda durmadan Tamamlanma Tanımına kadar sürdür
/refactor         — test güvenlik ağıyla davranışı koruyan refactor
/upgrade          — bağımlılıkları, framework'leri ve runtime'ları denetle veya yükselt
/debug            — sistematik hata teşhisi: hipotez → düzeltme → önleme

# --- Kalite ve inceleme ---
/test             — kapsamlı testler üret
/qa               — tam kalite kapıları: lint, tipler, testler, kapsam
/review           — proje standartları ve OWASP'a göre kod incelemesi
/security-audit   — OWASP + CVE + gizli bilgi taraması (her PR'dan önce çalıştır)
/perf             — performans darboğazını ölç, bul ve düzelt
/a11y             — erişilebilirlik denetimi ve düzeltmeleri (WCAG 2.2 AA)
/eval             — LLM destekli özellikler için değerlendirme setleri

# --- UI ve görsel tasarım ---
/design           — şablon gibi değil, bilinçli görünen UI tasarla ve oluştur
/design-review    — salt okunur UI incelemesi (şablon izleri, işçilik, Apple HIG / Material 3)
/polish           — yayından önce son görsel kalite geçişi
/design-system    — DESIGN.md / PRODUCT.md ve tasarım token'larını oluştur veya yenile

# --- Bağlam ve bilgi ---
/codegraph        — sembol, çağıran ve etki sorguları için kod grafiği (token tasarrufu)
/skill            — .claude/skills/ altında Agent Skills oluştur, güncelle veya listele

# --- Belgelendirme ---
/docs             — kod düzeyinde belgeler, mimari belgeler, kullanıcı kılavuzları
/doc-api          — OpenAPI spec oluştur/güncelle
/doc-schema       — veritabanı ERD ve tablo referansı
/doc-diagrams     — API ve iş akışları için Mermaid sequence diyagramları
/doc-site         — belgelendirme sitesini iskelet olarak kur veya yeniden üret
/doc-changelog    — git geçmişinden CHANGELOG.md üret

# --- Veritabanı, altyapı, deployment ---
/migrate          — güvenli DB migrasyonu: Expand-Contract + geri alma planı
/db               — veritabanı yaşam döngüsü: init, create, dml, seed, status, diff, audit
/infra            — AWS, GCP, Azure veya şirket içi için Terraform / K8s / CI-CD iskeleti kur
/deploy           — deployment öncesi kontrol listesi + yürütme adımları + izleme planı

# --- Operasyon ve otonom ajan ---
/standup          — git geçmişinden günlük özet
/triage           — Jira/Linear/GitHub issue'su için domain uygunluk kontrolü
/groom            — backlog'u triage + gereksinimler aracılığıyla toplu işle
/loop             — tam otonom döngü: tasarım → kod → QA → PR → deployment
/escalate         — ajan bloke olduğunda yapılandırılmış insan bildirimi
```

Argümanlar ve modlarla tam referans: [`docs/guides/ai-workflow.tr.md`](ai-workflow.tr.md#tüm-komutlar--hızlı-referans).

### Cursor

1. Proje klasörünü Cursor'da aç
2. `.cursor/rules/` içindeki kurallar dosya türüne göre otomatik yüklenir (işlem gerekmez)
3. `.claude/skills/` içindeki beceriler, görev veya açık dosya açıklamalarıyla ya da `paths` desenleriyle eşleştiğinde isteğe bağlı yüklenir
4. `.claude/commands/` içindeki slash komutları Cursor'da doğrudan çalışır — tam listeyi görmek için `/` yaz
5. MCP sunucularını etkinleştir: `.cursor/mcp.json` dosyasını düzenle, `"disabled": true` satırını kaldır, env değişkenlerini `.env` dosyasına ekle
6. Cursor'a giriş yap — sağlayıcı API anahtarı yalnızca kendi anahtarını kullanacaksan gerekir (Settings → Models)

### Continue (VS Code / JetBrains)

1. Continue eklentisini yükle
2. `.continue/config.yaml` dosyasını aç — otomatik algılanır
3. `models:` bölümüne `ANTHROPIC_API_KEY` ekle
4. Teknoloji yığınına uyan beceri kurallarını yorum satırından çıkar (Java, Python, React, iOS, vb.)
5. Slash komutları Continue sohbet panelinde kullanılabilir

### OpenCode

1. [OpenCode](https://opencode.ai/docs/) kur ve bu repoyu proje dizini olarak aç
2. OpenCode `AGENTS.md` ve `.claude/skills/` dizinini yerel olarak okur; kökteki `opencode.json` ayrıca `.cursor/rules/` yönergelerini ekler
3. Tüm Initium slash komutları `.opencode/commands/` içinde (`.claude/commands/` ile aynı)
4. TUI'de `/help`, `/goal`, `/implement` vb. — Claude Code ve Cursor ile aynı isimler
5. `.claude/commands/` düzenledikten sonra:

```bash
bash .initium/scripts/sync-opencode-commands.sh
```

---

## Geliştirme İş Akışı

```bash
# Bir özellik başlat
git checkout main && git pull
git checkout -b feat/PROJE-42-ozellik-adi

# --- AI destekli geliştirme döngüsü ---
/requirements Ödeme yeniden deneme mantığı ekle     # 1. Analiz et ve ayrıştır
/architect                                          # 2. Tasarla (50 satırdan uzun görevler için)
/task plan                                          # 3. .agent/tasks/*.md dosyaları oluştur
/task next                                          # 4. İlk görevi al
/implement TASK-001: ...                            # 5. Bir seferde bir görev uygula
/task done TASK-001                                 # 6. Tamamlandı işaretle, sıradakini al
/docs src/payments/retry.service.ts                 # 7. Yeni kodu belgele
/security-audit diff                                # 8. Güvenlik kontrolü (PR'dan ÖNCE HER ZAMAN)
/qa                                                 # 9. Kalite kapıları
/review                                             # 10. Son kod incelemesi

# Commit yap ve PR aç
git commit -m "feat(payments): ödeme yeniden deneme mantığı ekle"
gh pr create --fill
```

**Tam iş akışı kılavuzu:** [`docs/guides/ai-workflow.tr.md`](ai-workflow.tr.md)

---

## Otonom Ajanı Kurma (İsteğe Bağlı)

Otonom JIRA destekli geliştirme kullanmıyorsan bu bölümü geç.

### 1. Issue tracker'ı yapılandır

`agent.config.yaml` dosyasını düzenle:
```yaml
agent:
  mode: semi-autonomous         # Buradan başla; test ettikten sonra autonomous'a geç
issue_tracker:
  provider: jira                # veya: linear, github, azure-devops
  jira:
    server_url: "${JIRA_URL}"
    project_key: "PROJE_ANAHTARIN"
```

Şirket içinde barındırılan Jira (Data Center) için: [`.initium/docs/agent/jira-server-setup.md`](../../.initium/docs/agent/jira-server-setup.md) dosyasına bak.

### 2. Proje domain'ini tanımla

`docs/context/domain-boundaries.md` dosyasını doldur — ajanın hangi JIRA issue'larını kabul edeceğini kontrol eder:
```
✅ Kapsam dahili:  "Ödeme webhook işleyicisine yeniden deneme mantığı ekle"
❌ Kapsam dışı: "Pazarlama açılış sayfasını güncelle" → Pazarlama ekibi
```

### 3. Ajan ortam değişkenlerini `.env` dosyasına ekle

```env
JIRA_URL=https://jira.sirketiniz.com
JIRA_EMAIL=kullanici-adiniz
JIRA_API_TOKEN=kisisel-erisim-tokeniniz
SLACK_WEBHOOK_URL=https://hooks.slack.com/...
```

### 4. Kurulumu test et

```bash
# Jira API erişimini doğrula
curl -H "Authorization: Bearer $JIRA_API_TOKEN" \
  "$JIRA_URL/rest/api/2/myself" | jq .displayName

# Bilinen bir issue'yu manuel olarak triage et
/triage PROJE-1

# Test issue'su üzerinde tam döngüyü çalıştır
/loop PROJE-1
```

Tam belgeler: [`.initium/docs/agent/autonomous-workflow.md`](../../.initium/docs/agent/autonomous-workflow.md)

---

## Güvenlik Kontrol Listesi (Her PR'dan Önce)

Herhangi bir PR açmadan önce `/security-audit diff` çalıştır:

- [ ] CRITICAL veya HIGH bulgu yok
- [ ] Commit edilmiş gizli bilgi, API anahtarı veya kimlik bilgisi yok
- [ ] Tüm kullanıcı girdileri giriş noktasında doğrulanıyor
- [ ] Veri erişiminden önce yetkilendirme kontrol ediliyor
- [ ] CVSS ≥ 7.0 olan bağımlılık CVE'si yok

Tam güvenlik iş akışı için: [`docs/guides/workflows/05-security-evaluation.md`](workflows/05-security-evaluation.md)

Guardrail hook'ları temel kuralları otomatik uygular: ajanlar `.env` veya anahtar dosyalarını
okuyamaz, yıkıcı ya da force-push komutlarını çalıştıramaz, korunan yolları sormadan
düzenleyemez; pre-commit hook'u da gizli dosyaları ve token'ları reddeder. `setup.sh`
pre-commit hook'unu etkinleştirir; bu adımı atladıysan `git config core.hooksPath .githooks`
çalıştır. Ayrıntılar: [guardrails.md](../../.initium/docs/guardrails.md).

---

## Kurulumunu Güncel Tutma

Initium güncellendiğinde (yeni komutlar, geliştirilmiş beceri kuralları, güvenlik düzeltmeleri):

```bash
# macOS / Linux
bash .initium/scripts/sync.sh --check    # güncelleme mevcut mu kontrol et
bash .initium/scripts/sync.sh            # güncellemeleri etkileşimli olarak uygula
```

```powershell
# Windows
.\.initium\scripts\sync.ps1 -Check
.\.initium\scripts\sync.ps1
```

Senkronizasyon betiği proje özgü dosyalarına (`AGENTS.md`, `docs/context/`, `agent.config.yaml`) asla dokunmaz. AI aracı içinde `/sync-initium` aynı işi rehberli birleştirmeyle yapar. Ayrıntılar için: [`.initium/docs/sync-guide.md`](../../.initium/docs/sync-guide.md)

---

## Temel Komutlar

```bash
# TODO: Bunları projenin gerçek komutlarıyla değiştir

# Geliştirme
bun dev           # Geliştirme sunucusunu başlat

# Test
bun test          # Tüm testleri çalıştır
bun test --watch  # İzleme modu

# Kod kalitesi
bun lint          # Lint
bun typecheck     # Tip kontrolü
bun format        # Biçimlendir

# Veritabanı
bun db:migrate    # Migrasyonları çalıştır
bun db:seed       # Seed verisi yükle

# Derleme
bun build         # Üretim derlemesi
```

---

## Yardım Al

**Sırada ne yapacağından emin değil misin? AI'ya sor.**

Claude Code'da `/help` yaz ve durumunu sade bir dille anlat:

```
/help                                   # tüm komutları ve tam iş akışını göster
/help yeni bir özelliğe nasıl başlarım?
/help bu modül için testleri nasıl yazarım?
/help servis katmanında tip hatası alıyorum
/help PR açmadan önce ne yapmalıyım?
```

Cursor'da sohbette `/help` yazıp ardından sorunuzu ekleyin — `.claude/commands/` içindeki slash komutları Cursor'da doğrudan çalışır.

`/help` komutu iş akışında nerede olduğunu belirleyecek, sorunuzu doğru komut(lar)a eşleyecek ve sana net bir sonraki adım verecek — hiçbir kod yazmadan.

| İhtiyaç | Kaynak |
|---------|--------|
| Ne yapacağını bilmiyorum | Claude Code veya Cursor'da `/help` |
| Proje soruları | Slack / Teams'de `#<kanal>` |
| AI iş akışı rehberliği | [`docs/guides/ai-workflow.tr.md`](ai-workflow.tr.md) |
| Otonom ajan sorunları | [`.initium/docs/agent/escalation-protocol.md`](../../.initium/docs/agent/escalation-protocol.md) |
| Initium hatası veya iyileştirme | Initium deposunda issue aç |

---

## İlk Görev Kontrol Listesi

Kurulum tamamlandıktan sonra:

1. Backlog'dan bir `good-first-issue` bileti al
2. `/requirements <issue açıklaması>` — analiz et ve ayrıştır
3. `/architect <issue açıklaması>` — uygulamayı tasarla
4. `/task plan` — tasarım çıktısından görev dosyaları oluştur
5. Görevi göreve uygula: `/task next` → `/implement TASK-XXX` → `/task done TASK-XXX`
6. `/security-audit diff` — CRITICAL/HIGH bulguları düzelt
7. `/qa` — engelleyici kalite sorunlarını düzelt
8. `/review` — geri bildirimleri ele al
9. Şablonu kullanarak PR aç

Başarılar ve yardım istemekten çekinme!
