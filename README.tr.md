# Initium — Geliştirici Kılavuzu

İnteraktif insan destekli geliştirmeden, JIRA backlog'undan iş alıp Pull Request teslim eden **tam otonom ajan moduna** kadar çalışan, AI-native yazılım geliştirme için üreteme hazır bir proje şablonu.

[Cursor](https://cursor.sh), [Continue](https://continue.dev), [Claude Code](https://claude.ai/code) ve [OpenCode](https://opencode.ai) araçlarını kutudan çıkar çıkmaz destekler.

> **English:** [README.md](README.md) · **AI İş Akışı:** [docs/guides/ai-workflow.tr.md](docs/guides/ai-workflow.tr.md)

---

## Initium Ne Sağlar?

| Katman | Yapılandırma | Amaç |
|--------|-------------|------|
| **Tüm ajanlar** | `AGENTS.md` | Proje talimatlarının tek kaynağı (Claude Code bunu `CLAUDE.md` içindeki `@AGENTS.md` ile yükler) |
| **Agent Skills** | `.claude/skills/<ad>/SKILL.md` | Açık Agent Skills formatında 37 beceri (yığınlar + arayüz tasarımı) — Claude Code, Cursor ve OpenCode ihtiyaç anında yükler |
| **Claude Code** | `CLAUDE.md`, `.claude/` | 40 slash komutu, olay hook'ları |
| **Cursor** | `.cursor/rules/`, `.claude/skills/`, `.claude/commands/` | 6 temel kural + paylaşılan beceriler ve slash komutları |
| **OpenCode** | `opencode.json`, `.opencode/commands/` | `AGENTS.md` ve becerileri yerel okur; slash komutları `.claude/commands/` ile senkron |
| **Continue** | `.continue/` | Çok-model yapılandırması, `.claude/skills/`'ten üretilen 37 beceri kuralı, kalıcı yönergeler |
| **Kod grafı** | `agent.config.yaml → codegraph`, `/codegraph` | İsteğe bağlı yapısal kod indeksi (MCP) — ajan tüm dosyaları okumak yerine sembol ve çağıranları sorgular |
| **Otonom Ajan** | `agent.config.yaml`, `.initium/docs/agent/` | JIRA taraması, domain doğrulama, tam geliştirme döngüsü, eskalasyon |
| **GitHub** | `.github/` | PR şablonu, issue şablonları, CI iş akışı |
| **Initium senkronizasyonu** | `.initium/initium.json`, `.initium/scripts/sync.{sh,ps1,cmd}` | Özelleştirmelerin üzerine yazmadan Initium güncellemelerini projelerinize aktarma |

---

## Hızlı Başlangıç

```bash
# 1. Klonla
git clone <bu-repo-url> benim-projem && cd benim-projem

# 2. Başlat (git, .env, kontroller)
./.initium/scripts/setup.sh          # macOS/Linux
# .initium\scripts\setup.cmd         # Windows (Batch)
# .\.initium\scripts\setup.ps1       # Windows (PowerShell)

# 3. Etkileşimli sihirbazı çalıştır — proje adı, teknoloji yığını, tracker anahtarlarını doldurur
bash .initium/scripts/init.sh

# 4. AI'nın kalan TODO dosyalarını doldurmasına izin ver
claude
/init <tür> için <kullanıcılar> amacıyla <ad> adlı bir proje geliştiriyorum. Yığın: <dil, framework, DB>.

# 5. Doğrula
bash .initium/scripts/validate.sh   # beklenen: tüm PASS, FAIL yok
```

Kurulumun ardından AI döngüsüyle kodlamaya başla:
```
/requirements <ilk özelliğin>   →  /architect  →  /task plan  →  /implement  →  /qa  →  /deploy
```

> **Projeye yeni misiniz veya ne yapacağınızdan emin değil misiniz?** Claude Code'da veya Cursor'da `/help` yazın — AI sizi durumunuza uygun komuta yönlendirir.

---

## Özelleştirme Kontrol Listesi

### `.initium/scripts/init.sh` + `/init` tarafından otomatik doldurulanlar

| Dosya | Nasıl dolduruluyor |
|-------|--------------------|
| `AGENTS.md` | Sihirbaz mekanik alanları doldurur; AI kuralları üretir |
| `.cursor/rules/00-project-overview.mdc` | AGENTS.md ile aynı |
| `docs/context/project-brief.md` | Açıklamandan AI tarafından üretilir |
| `docs/context/tech-stack.md` | Onaylanan yığından AI tarafından üretilir |
| `docs/context/domain-boundaries.md` | AI tarafından üretilir — **otonom ajan için kritik** |
| `docs/context/domain-glossary.md` | Domain analizinden AI tarafından üretilir |
| `docs/architecture/overview.md` | AI tarafından üretilen mimari şablonu |
| `agent.config.yaml` | Sihirbaz kimlikleri; `/init agent:` tracker anahtarlarını doldurur |
| `.github/workflows/ci.yml` | `/init ci:` yığına göre üretir |

### Manuel eylem gerektirenler
- [ ] `.continue/config.yaml` — API anahtarı ekle; yığınına uyan beceri kurallarını yorum satırından çıkar
- [ ] `.env` — kimlik bilgilerini doldur (`.env.example` dosyasından kopyala)
- [ ] `.cursor/mcp.json` — `"disabled": true` kaldırarak MCP sunucularını etkinleştir
- [ ] Tüm AI tarafından üretilen içeriği ilk commit'ten önce gözden geçir ve iyileştir

---

## Proje Yapısı

```
.
├── AGENTS.md                           # ← DÜZENLE — tüm AI ajanları için proje talimatları
├── CLAUDE.md                           # Claude Code için AGENTS.md'yi içe aktarır — içerik ekleme
├── agent.config.yaml                   # ← DÜZENLE — otonom ajan yapılandırması
├── .initium/
│   ├── initium.json                   # Bu projenin hangi Initium sürümünü baz aldığını takip eder
│   ├── scripts/                       # Initium yaşam döngüsü betikleri (setup, sync, validate)
│   ├── docker/                        # Konteynerleştirilmiş ajan çalışma ortamı
│   │   ├── Dockerfile                 # Node 22 + Claude Code/Cursor CLI + git + cron
│   │   ├── docker-compose.yml         # Tüm ortam değişkenleriyle servis tanımı
│   │   ├── entrypoint.sh              # Başlangıç: repo klon, araç katmanı, cron
│   │   ├── groom-runner.sh            # Cron yükü: git pull → /groom → git push
│   │   ├── webhook-entrypoint.sh      # Webhook modu (secret yoksa cron'a geçer)
│   │   └── .env.example               # Tüm desteklenen değişkenler belgelenmiş
│   └── docs/                          # Initium belgeleri
│       ├── sync-guide.md              # Senkronizasyon rehberi
│       ├── UPDATES.md                 # Güncelleme notları
│       └── agent/                     # Otonom ajan belgeleri
│           ├── autonomous-workflow.md # Durum makinesi, fazlar, kapılar
│           ├── docker-agent.md        # Konteynerleştirilmiş ajan kurulum kılavuzu
│           ├── escalation-protocol.md # Eskalasyon tetikleyicileri ve yanıt protokolü
│           ├── jira-server-setup.md   # Şirket içi Jira Server operatör kılavuzu
│           └── security-evaluator.md  # Ajan döngüsünde güvenlik değerlendirmesi
│
├── .claude/
│   ├── settings.json                   # Araç izinleri + olay hook'ları
│   ├── skills/                         # 37 Agent Skill — <ad>/SKILL.md (tek kaynak)
│   ├── agents/                         # impeccable skill'inin kullandığı alt ajanlar
│   ├── commands/                       # 40 slash komutu (Claude Code'da / yazarak erişilir)
│   │   ├── help.md                     # /help — komutlara ve iş akışlarına rehberlik
│   │   ├── goal.md                     # /goal — ana hedef tamamlanana kadar durmadan çalış
│   │   ├── init.md                     # /init — proje kurulum sihirbazı
│   │   ├── requirements.md … docs.md   # İnsan destekli komutlar (16 adet)
│   │   ├── doc-api.md                  # /doc-api — OpenAPI spec üretimi
│   │   ├── doc-diagrams.md             # /doc-diagrams — API ve iş akışları için sıralı diyagramlar
│   │   ├── doc-site.md                 # /doc-site — belgelendirme sitesi
│   │   ├── doc-changelog.md            # /doc-changelog — CHANGELOG üretimi
│   │   ├── doc-schema.md               # /doc-schema — veritabanı ERD + tablo referansı
│   │   ├── sync-initium.md             # /sync-initium — Initium güncellemelerini uygula
│   │   ├── codegraph.md                # /codegraph — kod grafı kurulumu, sorgu, etki analizi
│   │   ├── refactor.md upgrade.md      # /refactor, /upgrade
│   │   ├── perf.md a11y.md eval.md     # /perf, /a11y, /eval
│   │   ├── design*.md polish.md        # /design, /design-review, /design-system, /polish
│   │   ├── skill.md                    # /skill — Agent Skill oluştur / güncelle
│   │   ├── triage.md                   # /triage  ← otonom ajan
│   │   ├── groom.md                    # /groom   ← otonom ajan
│   │   ├── loop.md                     # /loop    ← otonom ajan
│   │   └── escalate.md                 # /escalate ← otonom ajan
│   └── hooks/                          # Olay tetikleyicileri (post-write, audit-log, on-stop)
│
├── .cursor/
│   ├── prompts/                        # Cursor prompt dosyaları — Claude komutlarının aynısı
│   ├── rules/
│   │   ├── 00-project-overview.mdc    # ← DÜZENLE — her zaman yüklenir
│   │   └── 01 … 05-security.mdc       # Temel kurallar (OWASP her zaman yüklü)
│   └── mcp.json                       # MCP: GitHub, Jira, Linear, Slack, Sentry…
│
├── .continue/
│   ├── config.yaml                    # ← API ANAHTARLARI EKLE + becerileri etkinleştir
│   └── rules/                         # Temel kurallar + 37 beceri dosyası (.claude/skills/'ten üretilir)
│
├── .opencode/commands/                # 40 slash komutu (.claude/commands/ ile aynı)
├── opencode.json                      # OpenCode yönergeleri + kod grafı MCP
│
├── docs/
│   ├── guides/                        # Initium rehber belgeleri — serbestçe düzenleyin
│   │   ├── ai-workflow.md / .tr.md    # AI iş akışı rehberi (İngilizce / Türkçe)
│   │   ├── onboarding.md              # Yeni geliştirici kılavuzu
│   │   ├── team.md                    # Ekip rolleri ve AI-native optimizasyon
│   │   └── workflows/                 # 7 iş akışı kılavuzu (gereksinimler → dağıtım)
│   ├── context/                       # ← TÜMÜNÜ DÜZENLE (AI bağlamı + ajan kapsamı)
│   ├── architecture/                  # ← DÜZENLE + ADR'ler
│
├── skills/README.md                   # Beceri indeksi ve aktivasyon rehberi
├── .agent-templates/webhook-receiver.mjs
└── .initium/
    ├── initium.json                   # Bu projenin hangi Initium sürümünü temel aldığını izler
    ├── scripts/
    │   ├── setup.{sh,cmd,ps1}         # Adım 1 — projeyi başlat
    │   ├── init.{sh,cmd,ps1}          # Adım 2 — yapılandırma sihirbazı
    │   ├── validate.{sh,cmd,ps1}      # 128 noktalı yapılandırma doğrulayıcı
    │   └── sync.{sh,ps1,cmd}          # Initium güncellemelerini uygula
    ├── docker/                        # Konteynerleştirilmiş ajan çalışma ortamı
    │   ├── Dockerfile
    │   ├── docker-compose.yml
    │   ├── entrypoint.sh / groom-runner.sh / webhook-entrypoint.sh
    │   └── .env.example
    └── docs/
        ├── sync-guide.md              # Senkronizasyon rehberi ve birleştirme stratejileri
        ├── UPDATES.md                 # Her Initium sürümü için güncelleme notları
        └── agent/                     # Otonom ajan belgeleri
            ├── autonomous-workflow.md
            ├── docker-agent.md
            ├── escalation-protocol.md
            ├── jira-server-setup.md
            └── security-evaluator.md
```

---

## Slash Komutları Referansı

### Yardım ve Navigasyon

| Komut | Amaç |
|-------|------|
| `/help` | Tüm mevcut komutları ve tipik iş akışını göster |
| `/help <soru>` | Belirli durumunuz için doğru komuta yönlendir |
| `/help <faz>` | "Bir özelliğe nasıl başlarım?" — o faz için adım adım komut dizisi |

> **Yeni geliştirici ipucu:** Sırada ne yapacağınızdan emin olmadığınızda `/help` her zaman ilk komutunuzdur. Durumunuzu sade bir dille anlatın, AI sizi doğru iş akışı ve komutlara yönlendirir.

### Başlatma

| Komut | Amaç |
|-------|------|
| `/init <açıklama>` | Serbest biçimli proje açıklamasından tüm TODO dosyalarını doldur |
| `/init domain: <açıklama>` | Domain sınırları, sözlük ve ajan anahtar kelimeleri üret |
| `/init stack: <yığın>` | Teknoloji yığını belgesi ve AGENTS.md komut bölümünü üret |
| `/init ci: <yığın>` | Yığına özgü CI iş akışı adımları üret |
| `/init agent: <anahtarlar>` | Tracker anahtarları, GitHub sahibi/deposu, eskalasyon kanallarını yapılandır |

### İnsan Destekli Geliştirme

| Komut | Amaç | Ne Zaman |
|-------|------|---------|
| `/requirements` | Kullanıcı hikayeleri + kabul kriterleri + sıralı görev listesi + Tamamlanma Tanımı | Her özellikten önce |
| `/architect` | Tek satır kod yazmadan önce tasarım | 50+ satır görevler |
| `/task plan` | Tasarımı takip edilebilir `.agent/tasks/*.md` dosyalarına böl | Tasarım sonrası, kodlama öncesi |
| `/task next` | Bağımlılıklara göre sonraki işlem yapılabilir görevi getir | Uygulama sırasında |
| `/task done <id>` | Görevi tamamlandı olarak işaretle, bağımlıları aç | Her commit sonrası |
| `/task list` | Tüm görevleri ve durumlarını göster | Her zaman |
| `/implement` | Alt-üst yapılandırılmış uygulama + öz-inceleme | Kodlama sırasında |
| `/goal <hedef>` | Ana hedef tamamlanana kadar durmadan çalış (Definition of Done) | Uçtan uca teslim |
| `/qa` | Lint + tip + testler + kapsam + güvenlik | PR açmadan önce |
| `/security-audit [hedef]` | OWASP Top 10 + CVE + gizli bilgi taraması | Her PR'dan önce |
| `/review` | Standartlara ve OWASP'a göre kod incelemesi | Uygulamadan sonra |
| `/test` | Kapsamlı testler üret (mutlu yol + kenar + hata) | Her modül için |
| `/debug` | Sistematik teşhis: hipotez → düzeltme → önleme | Takıldığında |
| `/deploy` | Deployment öncesi kontrol listesi + izleme planı | Her deployment |
| `/infra <platform>` | AWS / GCP / şirket içi için Terraform / K8s şablonu | Yeni deployment hedefi |
| `/migrate` | Güvenli DB migrasyonu: Expand-Contract + toplu + geri alma | Şema değişiklikleri |
| `/db <alt-komut>` | DB yaşam döngüsü: `init`, `create`, `dml`, `seed`, `status`, `diff` | DB yönetimi |
| `/sprint` | Sprint planlaması: kapasite + backlog + görevler + risk kaydı | Sprint başlangıcı |
| `/standup` | Git geçmişinden günlük özet | Günün başında |
| `/docs <dosya>` | Kod düzeyinde belgelendirme üret (JSDoc, docstring, GoDoc…) | Uygulamadan sonra |
| `/refactor` | Davranışı koruyan refactor, karakterizasyon testleriyle | Teknik borç |
| `/upgrade [audit\|<paket>\|security\|runtime]` | Bağımlılık, framework ve runtime yükseltmelerini migrasyon rehberleriyle yap | Eski bağımlılıklar, CVE'ler |
| `/perf` | Ölç → profille → düzelt → yeniden ölç, regresyon koruması ekle | Gecikme, bellek, bundle boyutu |
| `/a11y [kapsam]` | Web ve mobil için WCAG 2.2 AA denetimi ve düzeltmeleri | UI değişiklikleri |
| `/eval [create\|run\|compare]` | LLM özellikleri için değerlendirme setleri: veri seti, puanlayıcı, eşik, CI | Prompt / model / RAG değişiklikleri |
| `/design <hedef + brief>` | Bağlam → yazılı yön (token'lar, wireframe, tek imza öğe) → uygulama → ekran görüntüsüyle öz-eleştiri | Yeni sayfa, ekran veya bileşen |
| `/design-review [kapsam]` | Salt okunur inceleme: "AI şablonu" izleri, işçilik, durumlar, Apple HIG / Material 3 uyumu, puanlı rapor | UI birleştirmeden önce, "jenerik görünüyor" |
| `/polish [kapsam]` | Son geçiş: bozuk yerleşim, eksik durumlar, token tutarlılığı, tipografi, şablon izleri | Yayından önce |
| `/design-system [scan\|seed\|check\|tokens]` | `DESIGN.md` (Google DESIGN.md formatı) ve `PRODUCT.md` oluştur/yenile; token dosyaları üret | Proje başına bir kez, görsel değişikliklerden sonra |
| `/codegraph [setup\|status\|query\|impact\|refresh]` | MCP üzerinden yapısal kod grafı: sembol arama, çağrı izleme, diff etki analizi — daha az token | Büyük kod tabanları |
| `/skill [new\|update\|list]` | Kod tabanının gerçek kurallarından `.claude/skills/` içinde Agent Skill oluştur | Yeni yığın / kural |

### Belgelendirme Üretimi

| Komut | Amaç | Çıktı |
|-------|------|-------|
| `/doc-api` | OpenAPI 3.x spec üret + doğrula + ReDoc HTML | `openapi.json` + `docs/api/` |
| `/doc-diagrams` | API çağrıları ve iş akışları için Mermaid sıralı diyagramlar üret | `docs/diagrams/` |
| `/doc-site` | Belgelendirme sitesi kur veya yeniden oluştur (Docusaurus / MkDocs) | Dağıtılabilir statik site |
| `/doc-changelog` | Git geçmişinden `CHANGELOG.md` üret (git-cliff) | `CHANGELOG.md` + paydaş özeti |
| `/doc-schema` | Veritabanı ERD + tablo referansı + indeks analizi | `docs/database/` |

### Otonom Ajan

| Komut | Amaç |
|-------|------|
| `/triage <issue>` | Domain uygunluk kontrolü: ≥ 0.80 otomatik kabul, 0.30–0.79 eskalasyon, < 0.30 red |
| `/groom` | Toplu backlog işleme: kabul edilenler için triage + gereksinimler |
| `/loop <görev-id>` | Tam otonom döngü: tasarım → uygulama → belgelendirme → QA → güvenlik → PR → deployment |
| `/escalate <önem> <tetikleyici> <id>` | Slack/GitHub/e-posta yönlendirmeli yapısal insan bildirimi |

### İskelet Bakımı

| Komut | Amaç |
|-------|------|
| `/sync-initium` | Initium yeni geliştirmelerini bu projeye aktar |
| `/sync-initium --dry-run` | Herhangi bir şeyi uygulamadan neyin değişeceğini önizle |
| `/sync-initium --check` | Initium güncellemesi mevcut mu kontrol et |

---

## Otonom Ajan Döngüsü

```
JIRA / Linear / GitHub İssue'ları
    │
    ▼ /groom (zamanlanmış veya webhook)
    ▼ /triage — güven puanı hesaplama
    │   Varlık eşleşmesi +0.30 · Fonksiyonel alan +0.40 · Kod sahipliği +0.20
    │   ≥ 0.80 → KABUL   0.30–0.79 → ESKALASYON   < 0.30 → RED
    ▼
    ▼ /requirements — kullanıcı hikayeleri + görev listesi (JSON + Markdown)
    ▼ /architect — tasarım belgesi + risk seviyesi
    │   risk=YÜKSEK → insan onayı kapısı (AGENT_APPROVE_DESIGN)
    ▼ /task plan — tasarımı .agent/tasks/*.md dosyalarına böl
    │   her dosya: durum, kabul kriterleri, bağımlılıklar
    ▼
    ▼ /loop her görev için (.agent/tasks/ mevcutsa okur):
    │   /task next → uygula → /docs → test → /task done → sonraki görev
    │   başarısız? → /debug (maks deneme) → eskalasyon
    ▼ Belgelendirme senkronizasyonu (koşullu):
    │   apiChanges → /doc-api diff · schemaChanges → /doc-schema migrations
    ▼ /qa — lint + tipler + kapsam + güvenlik
    ▼ /security-audit diff — OWASP + CVE kontrolü
    ▼ PR oluştur (issue'ya bağlantılı, QA raporu, risk seviyesi)
    ▼ CI izle → birleştir (otomatik veya insan)
    ▼ /deploy staging (otomatik) → üretim (insan kapısı)
    ▼ 30 dakika deployment sonrası izleme
    │   metrik düşüşü → otomatik geri alma + kritik eskalasyon
    ▼ Issue tracker: Tamamlandı ✓ · Audit kaydı yazıldı
```

**Güvenlik:** kalıcı durum (kesintide kaldığı yerden devam) · kill switch (`touch .agent/STOP`) · korunan yollar · JSONL audit izi

**İnsan yanıt komutları** (GitHub issue veya JIRA ticket'ına yorum ekle):
`AGENT_RESUME` · `AGENT_APPROVE_DESIGN` · `AGENT_APPROVE_DEPLOY` · `AGENT_CLARIFY: <metin>` · `AGENT_SKIP_TASK` · `AGENT_REASSIGN` · `AGENT_ABANDON`

---

## Konteynerleştirilmiş Ajan (Docker)

Otonom ajanı uzun ömürlü bir Docker konteyneri olarak çalıştırın — geliştirici makinesi gerekmez. İmaj, Initium çalışma ortamını (slash komutları, hook'lar, kurallar) içerir; proje kaynak kodu hiçbir zaman imaja dahil edilmez ve konteyner başlangıcında `GIT_REPO_URL` adresinden klonlanır.

İki tetikleme modu — biri veya ikisi birden kullanılabilir:

| Mod | Servis | Nasıl çalışır |
|-----|--------|---------------|
| **Yoklama** | `agent` | Cron, `GROOM_CRON` zamanlamasına göre `/groom` çalıştırır |
| **Olay tabanlı** | `webhook` | `JIRA_WEBHOOK_SECRET` tanımlıysa Jira webhook alıcısı başlar; tanımlı değilse **otomatik olarak cron'a geçer** |

```bash
# Yalnızca yoklama (cron tabanlı /groom)
cp .initium/docker/.env.example .initium/docker/.env   # anahtarları doldur
docker compose -f .initium/docker/docker-compose.yml up -d agent
docker logs -f initium-agent

# + Webhook alıcısı (anlık triage + cron tarama)
# docker/.env dosyasına JIRA_WEBHOOK_SECRET ekle, ardından:
docker compose -f .initium/docker/docker-compose.yml up -d
# Jira Server'ı şu adrese yönlendir: http://<host>:3001/jira-webhook
```

**Araç katmanı** — konteyner, `GIT_REPO_URL` adresindeki repoyu `/workspace` dizinine klonlar. Repoda `.claude/`, `.cursor/`, `.continue/` veya `agent.config.yaml` yoksa imajdan otomatik olarak kopyalanır. `/init` ile başlatılmış projelerde repodaki özelleştirilmiş kopyalar önceliklidir.

**Desteklenen AI CLI'ları** — `AGENT_CLI` ortam değişkeniyle seçilir (varsayılan: `claude`):

| Değer | CLI | Çalıştırma biçimi | Kural kaynağı |
|-------|-----|-------------------|---------------|
| `claude` | Claude Code | `/groom` slash komutu | `.claude/commands/` |
| `cursor` | Cursor CLI | `groom.md` içeriği prompt olarak iletilir | `.cursor/rules/` |

**Desteklenen AI sağlayıcıları** — ortam değişkenlerinden biri seçilir:

| Sağlayıcı | Gerekli değişkenler |
|-----------|---------------------|
| Anthropic (doğrudan) | `ANTHROPIC_API_KEY` |
| AWS Bedrock | `CLAUDE_CODE_USE_BEDROCK=1` · `AWS_ACCESS_KEY_ID` · `AWS_SECRET_ACCESS_KEY` · `AWS_REGION` |
| Google Vertex AI | `CLAUDE_CODE_USE_VERTEX=1` · `CLOUD_ML_REGION` · `ANTHROPIC_VERTEX_PROJECT_ID` |

**Zamanlama** — `GROOM_CRON` ortam değişkeniyle kontrol edilir (standart cron sözdizimi). Varsayılan: `*/15 * * * *` (`agent.config.yaml → poll_interval_minutes` değeriyle eşleşir).

**Kill switch** — ajanı durdurmak için workspace içinde `.agent/STOP` dosyası oluşturun; konteyneri yeniden başlatmaya gerek yoktur.

Tam kurulum kılavuzu: [.initium/docs/agent/docker-agent.md](.initium/docs/agent/docker-agent.md)

---

## Dil ve Framework Becerileri

Beceriler açık [Agent Skills](https://agentskills.io) formatındadır. Claude Code, Cursor ve OpenCode bunları `.claude/skills/` dizininden ihtiyaç anında yükler (kullanılana kadar yalnızca açıklama bağlamda yer tutar). Continue için üretilen kuralı `.continue/config.yaml` dosyasında yorumdan çıkarman gerekir.

| Kategori | Beceriler |
|----------|-----------|
| **Backend** | Java/Spring Boot · .NET/ASP.NET Core · Python/FastAPI · TypeScript · Node.js (NestJS/Fastify/Hono) · Go · Rust (Axum/Tokio) · Kotlin (Ktor/Spring) · PHP (Laravel) |
| **API ve Entegrasyon** | Microservices · Mesajlaşma (Kafka/RabbitMQ/SQS, outbox) · GraphQL ve gRPC |
| **AI / LLM** | LLM uygulamaları: yapılandırılmış çıktı, RAG, OWASP LLM Top 10, eval, MCP sunucuları |
| **Frontend** | React · Next.js App Router · Vue 3 · Angular 17+ |
| **Mobil** | iOS/Swift · Android/Kotlin · Kotlin Multiplatform · Flutter/Dart · React Native/Expo |
| **Arayüz Tasarımı** | Web görsel tasarımı (`frontend-design`, `impeccable` — Apache-2.0, bkz. `THIRD_PARTY_NOTICES.md`) · Apple Human Interface Guidelines · Material Design 3 Expressive · Tasarım token'ları ve DESIGN.md |
| **Altyapı** | Docker · GitHub Actions CI/CD · Terraform/OpenTofu · OpenTelemetry ve SLO · AWS · GCP · Şirket İçi (k3s/Vault/Ansible) |
| **Çapraz kesen** | Veritabanı Migrasyonları · Güvenlik SAST · Belgelendirme Üretimi |

Tam indeks, aktivasyon kılavuzu ve yeni beceri ekleme için: [skills/README.md](skills/README.md)

---

## MCP Sunucuları

`.cursor/mcp.json` dosyasında yapılandırılmıştır. Etkinleştirmek için: `"disabled": true` satırını kaldır ve gerekli ortam değişkenlerini `.env` dosyasına ekle.

| Sunucu | Amaç | Ortam Değişkenleri |
|--------|------|-------------------|
| `filesystem` · `git` | Çalışma alanı dosyaları, git geçmişi | — (otomatik) |
| `github` | Issue'lar, PR'lar, CI durumu | `GITHUB_TOKEN` |
| `jira` | Issue çek/güncelle — `/triage`, `/groom` tarafından kullanılır | `JIRA_URL`, `JIRA_EMAIL`, `JIRA_API_TOKEN` |
| `linear` | Jira'ya alternatif | `LINEAR_API_KEY` |
| `slack` | Eskalasyon bildirimleri | `SLACK_BOT_TOKEN`, `SLACK_TEAM_ID` |
| `sentry` | Deployment sonrası hata izleme | `SENTRY_AUTH_TOKEN`, `SENTRY_ORG` |
| `postgres` · `brave-search` · `memory` · `puppeteer` | DB incelemesi, web araması, bellek, tarayıcı otomasyonu | bkz. `.cursor/mcp.json` |

---

## Projeyi Güncel Tutma

Güncellemeler otomatik gelir:

- **Haftalık pull request.** `.github/workflows/initium-sync.yml` her pazartesi yeni bir Initium
  sürümü olup olmadığını kontrol eder. Varsa `chore/initium-sync-v<sürüm>` dalında bir PR açar:
  Initium'a ait dosyaların güncellemeleri, elle birleştirilecek `merge_required` dosyaların kontrol
  listesi ve sürüm notları bu PR'da yer alır. Hiçbir şey otomatik birleştirilmez. Tek seferlik kurulum:
  *Settings → Actions → General → Allow GitHub Actions to create and approve pull requests*.
- **Oturum bildirimi.** Claude Code `SessionStart` hook'u (`check-update.mjs`, günlük önbellekli)
  yeni sürüm çıktığında ajana haber verir, ajan da `/sync-initium` önerir.
- **Ayarlar.** `agent.config.yaml → initium_sync`: `channel` (`tags` = yalnızca sürümler ya da `main`),
  `auto_pr`, `notify_local`, `check_interval_hours`.

Elle senkronize etmek için:

```bash
# macOS / Linux / Git Bash
bash .initium/scripts/sync.sh              # etkileşimli: diff gösterir, güvenli dosyaları otomatik uygular
bash .initium/scripts/sync.sh --auto       # etkileşimsiz: Initium-owned dosyaları uygula, birleştirmeleri atla
bash .initium/scripts/sync.sh --check      # güncelleme varsa 10 koduyla çıkar (betikler için --json)
bash .initium/scripts/sync.sh --ref v1.2.0 # belirli bir sürüme sabitle
```

```powershell
# Windows (PowerShell — önerilir)
.\.initium\scripts\sync.ps1            # etkileşimli
.\.initium\scripts\sync.ps1 -Auto     # etkileşimsiz
.\.initium\scripts\sync.ps1 -Check    # sadece kontrol et
```

```bat
:: Windows (Batch — PowerShell'e otomatik yönlendirir)
.initium\scripts\sync.cmd
.initium\scripts\sync.cmd --auto
.initium\scripts\sync.cmd --check
```

Senkronizasyon betiği `.initium/initium.json` kullanarak her dosyayı sınıflandırır:
- **Initium-owned** (komutlar, beceri kuralları, ajan belgeleri) → güvenle otomatik uygulanır; Initium'un sildiği dosyalar, sen değiştirmediysen silinir
- **birleştirme gerekli** (`.continue/config.yaml`, `mcp.json`, `ci.yml`) → diff olarak gösterilir, sen karar verirsin
- **proje-owned** (`AGENTS.md`, `CLAUDE.md`, `docs/context/`, `agent.config.yaml`) → asla dokunulmaz

Tam rehber ve her dosya türü için birleştirme stratejileri: [.initium/docs/sync-guide.md](.initium/docs/sync-guide.md)

---

## Temel Prensipler

1. **Bağlam her şeydir.** AI, projenin amacını ve kısıtlamalarını anladığında daha iyi çıktı üretir. `docs/context/` dosyaları ve beceri kuralları bu bağlamı kalıcı olarak sağlar — her prompt'ta tekrarlamak gerekmez.

2. **Kurallar tekrara karşı.** Standartları beceri dosyalarında bir kez tanımla. "Constructor injection kullan", "her zaman test yaz", "tüm sorguları parametreleştir" — bir kez söyle, her oturum uygulasın.

3. **Yapılandırılmış iş akışları.** Slash komutları tekrarlayan iş akışlarını kodlar; AI bunları tutarlı şekilde uygular — ham gereksinimden birleştirilmiş, dağıtılmış, belgelenmiş PR'a kadar.

4. **İnsanlar sınırı belirler, ajanlar çalıştırır.** Ajan yapılandırılmış eşikler dahilinde özerk hareket eder. Her riskli karar (yüksek riskli tasarım, üretim deployment'ı) insan onayı gerektirir. Her eylem kayıt altına alınır.

---

## Daha Fazla Okuma

| Belge | İçerik |
|-------|--------|
| [docs/guides/ai-workflow.tr.md](docs/guides/ai-workflow.tr.md) | Tam AI-native geliştirme iş akışı referansı |
| [docs/guides/team.tr.md](docs/guides/team.tr.md) | AI-native geliştirme için ekip rolleri, yapısı ve optimizasyonu |
| [docs/guides/onboarding.md](docs/guides/onboarding.md) | Yeni geliştirici kurulum kılavuzu (İngilizce) |
| [docs/guides/onboarding.tr.md](docs/guides/onboarding.tr.md) | Yeni geliştirici kurulum kılavuzu (Türkçe) |
| [.initium/docs/sync-guide.md](.initium/docs/sync-guide.md) | Initium güncellemelerini projeye aktarma |
| [.initium/docs/agent/autonomous-workflow.md](.initium/docs/agent/autonomous-workflow.md) | Ajan durum makinesi, fazlar, kapılar |
| [.initium/docs/agent/docker-agent.md](.initium/docs/agent/docker-agent.md) | Konteynerleştirilmiş ajan kurulumu, ortam değişkenleri, sorun giderme |
| [.initium/docs/agent/jira-server-setup.md](.initium/docs/agent/jira-server-setup.md) | Şirket içi Jira Server operatör kılavuzu |
| [.initium/docs/agent/security-evaluator.md](.initium/docs/agent/security-evaluator.md) | Güvenlik değerlendirme mimarisi |
| [.initium/docs/agent/documentation-agent.md](.initium/docs/agent/documentation-agent.md) | Belgelendirme üretim araçları ve pipeline |
| [skills/README.md](skills/README.md) | Tam beceri indeksi ve aktivasyon kılavuzu |
| [.initium/docs/UPDATES.md](.initium/docs/UPDATES.md) | Initium sürümleri için değişiklik kaydı |

---

## Lisans

Initium [MIT Lisansı](LICENSE) ile yayınlanır. Projeye dahil edilen üçüncü taraf skill'ler kendi
lisanslarını korur, bkz. [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Initium'dan türetilen projeler kendi kodları için istedikleri lisansı seçebilir. `LICENSE`
dosyasını değiştirirsen, projende yer alan Initium dosyaları için Initium'un telif ve izin
bildirimini koru; örneğin bildirimi `THIRD_PARTY_NOTICES.md` dosyasına ekleyebilirsin.

Katkıda bulunanlar [Davranış Kuralları](CODE_OF_CONDUCT.md)'na (Contributor Covenant 3.0) uyar.
