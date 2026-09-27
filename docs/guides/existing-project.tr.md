# Initium'u Mevcut Bir Projeye Eklemek

> 🇬🇧 [English](existing-project.md)

Bu kılavuz; kodu, CI'ı ve kendi kuralları olan bir repoya sahip olup Initium iş akışını (slash
komutları, kurallar, skill'ler, ajan dokümanları) sıfırdan başlamadan almak isteyen ekipler
içindir. Yeni bir proje için Initium'u klonlayın: bkz. [onboarding.tr.md](onboarding.tr.md).

**Süre:** 30–60 dakika; çoğu, Initium'un önerdiklerini gözden geçirmekle geçer.
**Gereksinimler:** git, bash (Windows'ta PowerShell) ve Initium **v1.5.0 veya üzeri** — daha
eski `sync.sh` sürümleri ilk senkronizasyonda mevcut dosyaların üzerine yazar.

---

## Benimseme Neyi Değiştirir

Reponuzda henüz kayıtlı bir Initium commit'i olmadığı için ilk senkronizasyon *benimseme
modunda* çalışır. Bu modda var olan hiçbir dosyanın yerine başkası yazılmaz.

| Initium dosya sınıfı | Dosya reponuzda yoksa | Dosya zaten varsa |
|----------------------|------------------------|-------------------|
| `skeleton_owned` (komutlar, skill'ler, kurallar, ajan dokümanları) | Eklenir | Hiçbir Initium sürümüyle aynı değilse korunur — **Existing kept** altında listelenir |
| `merge_required` (`.gitignore`, `.editorconfig`, `SECURITY.md`, `ci.yml`, PR şablonu, `.claude/settings.json`, `.cursor/mcp.json`, …) | Eklenir | Fark gösterilir, siz seçersiniz (`--auto`'da atlanır) |
| `project_owned` şablonları (`AGENTS.md`, `CLAUDE.md`, `agent.config.yaml`, `docs/context/`, `docs/architecture/`, `.env.example`, …) | TODO şablonu olarak eklenir | Asla dokunulmaz |
| `README*`, `LICENSE`, `CHANGELOG.md`, `CODE_OF_CONDUCT.md`, `.env` | Eklenmez | Asla dokunulmaz |

Yerel `.initium/initium.json` dosyanızda `fileOwnership.project_owned` altına yazdığınız her
yol — bu ve sonraki tüm senkronizasyonlarda — asla yazılmaz. Özette **Protected** olarak görünür.

Mevcut bir repoda en sık çakışan dosyalar: `CONTRIBUTING.md`, `SECURITY.md`, `.editorconfig`,
`.gitignore`, `.devcontainer/devcontainer.json`, `.github/workflows/ci.yml`,
`.github/PULL_REQUEST_TEMPLATE.md`, `.claude/settings.json`, `.cursor/rules/*.mdc`, `opencode.json`
ve var olan bir `AGENTS.md` ya da `CLAUDE.md`.

---

## Adım 1 — Branch Hazırlayın

Initium'un getirdiği her değişikliği tek bir diff olarak inceleyebilmek için temiz bir çalışma
ağacıyla başlayın.

```bash
git status                       # temiz olmalı
git checkout -b chore/adopt-initium
```

---

## Adım 2 — `.initium/` Klasörünü Getirin

`sync.sh` Initium'un içinde yer aldığı için bir sürümü çekip yalnızca `.initium/` klasörünü geri
yükleyin. En güncel sürümü [releases sayfasından](https://github.com/mehmet-yildirim/Initium/releases) seçin.

```bash
INITIUM_TAG=v1.5.0               # en güncel sürüm, v1.5.0 veya üzeri
git remote add skeleton https://github.com/mehmet-yildirim/Initium.git
git fetch --no-tags skeleton "+refs/tags/$INITIUM_TAG:refs/initium/$INITIUM_TAG"
git restore --source="refs/initium/$INITIUM_TAG" --worktree -- .initium/
```

Windows (PowerShell):

```powershell
$InitiumTag = 'v1.5.0'
git remote add skeleton https://github.com/mehmet-yildirim/Initium.git
git fetch --no-tags skeleton "+refs/tags/${InitiumTag}:refs/initium/${InitiumTag}"
git restore --source="refs/initium/$InitiumTag" --worktree -- .initium/
```

Çekilen Initium ref'leri `refs/initium/` altında tutulur; kendi tag ve branch'lerinizle karışmaz.

**İsteğe bağlı — ilk senkronizasyondan önce dosyaları koruyun.** Initium ileride güncellese bile
sizde kalması gereken dosyaları biliyorsanız (özel bir `CONTRIBUTING.md`, kendi
`.cursor/rules/01-coding-standards.mdc` dosyanız), bunları şimdi `.initium/initium.json` içindeki
`project_owned` listesine ekleyin. Sonda `/` olan bir yol tüm klasörü korur.

```json
"project_owned": [
  "AGENTS.md",
  "CONTRIBUTING.md",
  ".cursor/rules/01-coding-standards.mdc",
  ...
]
```

---

## Adım 3 — Önizleyin, Sonra Senkronize Edin

```bash
bash .initium/scripts/sync.sh --ref "$INITIUM_TAG" --dry-run    # her ekleme / koruma / birleştirmeyi gösterir
bash .initium/scripts/sync.sh --ref "$INITIUM_TAG"              # uygular; merge_required dosyaları tek tek sorar
```

Windows: `.initium\scripts\sync.cmd --ref v1.5.0 --dry-run`, ardından `--dry-run` olmadan.

Zaten var olan `merge_required` dosyalar için etkileşimli senkronizasyon farkı gösterir ve `a`
(Initium sürümüyle üzerine yaz), `s` (atla — varsayılan) ya da `o` (ikisini `$VISUAL` ile aç)
seçeneklerini sunar. **Emin olmadığınız her dosyayı atlayın** — Adım 5'te elle birleştirirsiniz.

Sonunda özet dört grup listeler: uygulananlar, atlananlar (elle birleştirilecek), **Protected**
ve **Existing kept**. Bu çıktıyı bir sonraki adım için açık tutun.

---

## Adım 4 — Her "Existing kept" Dosyası İçin Karar Verin

Her kayıt, Initium'un da sağladığı ama sizin sürümünüzün korunduğu bir dosyadır. Her biri için:

```bash
git show "refs/initium/$INITIUM_TAG:<dosya>" | diff -u - <dosya>    # Initium'unki ile sizinki
```

- **Kalıcı olarak sizinkini koruyun** → yolu `.initium/initium.json` içindeki `project_owned`
  listesine ekleyin. Aksi hâlde bir sonraki senkronizasyon (artık benimseme modunda değil)
  dosyayı Initium sürümüyle değiştirir.
- **Initium'unkini alın** → `git checkout "refs/initium/$INITIUM_TAG" -- <dosya>`
- **Birleştirin** → Initium sürümünden ihtiyacınız olanı kendi dosyanıza ekleyin, ardından
  sonraki senkronizasyonlar dokunmasın diye `project_owned` listesine ekleyin.

Tipik kararlar:

| Dosya | Olağan seçim |
|-------|--------------|
| `CONTRIBUTING.md`, `.devcontainer/devcontainer.json` | Sizinkini koruyun → `project_owned` |
| Kendi kurallarınızla aynı adı taşıyan `.cursor/rules/01-…05-*.mdc` | Sizinkini yeniden adlandırın (`10-team-*.mdc`), Initium'unkini alın |
| `opencode.json` | Birleştirin — sağlayıcılarınızı koruyun, Initium'un `instructions` ve komut yollarını ekleyin |
| `docs/guides/team.md` | Initium'unkini alın; rolleri zaten belgeliyorsanız `project_owned` |

---

## Adım 5 — Paylaşılan Yapılandırma Dosyalarını Birleştirin

Bunlar önceden var olan ve atlanan `merge_required` dosyalardır:

- **`.gitignore`** — en azından "AI tool — local overrides & runtime state" bloğunu ekleyin
  (`.agent/state/`, `.agent/audit/`, `.agent/escalations/`, `.agent/outputs/`, `.agent/STOP`,
  `.claude/settings.local.json`, `.codebase-memory/`) ve `.env`'in yok sayıldığından emin olun.
  Dosyanın tamamı: `git show "refs/initium/$INITIUM_TAG:.gitignore"`.
- **`.claude/settings.json`, `.cursor/mcp.json`, `.continue/config.yaml`** — kendi kayıtlarınızı
  koruyun, Initium'un istediğiniz izinlerini, hook'larını ve MCP sunucularını ekleyin.
- **`SECURITY.md`, `.editorconfig`, PR ve issue şablonları** — Initium'unki eksik bir şey
  eklemiyorsa sizinkini koruyun (PR kontrol listesine `/review` ve `/qa` başvurur).

---

## Adım 6 — `AGENTS.md` ve `CLAUDE.md` Dosyalarını Uzlaştırın

Initium tüm ajanları tek bir talimat dosyasında toplar: Cursor, OpenCode, Codex, Copilot ve
Gemini CLI'ın doğrudan okuduğu `AGENTS.md`. `CLAUDE.md` yalnızca onu içe aktarır.

| Sizde olan | Yapılacak |
|------------|-----------|
| Hiçbiri | Bir şey yapmayın — senkronizasyon iki şablonu da ekledi; `/init` bunları Adım 8'de doldurur |
| Yalnızca `AGENTS.md` | Koruyun. Eksik Initium bölümlerini (Essential Commands, Architecture, Testing Standards, Git & PR Workflow, Do Not) ekleyin — `/init` metninizi yeniden yazmadan bunları sona ekler |
| Proje kuralları içeren `CLAUDE.md` | Kuralları `AGENTS.md`'ye taşıyın, `CLAUDE.md`'yi aşağıdaki içe aktarma dosyasına çevirin; altında yalnızca Claude Code'a özgü notları bırakın |
| `.cursorrules` ya da eski `.cursor/rules` | Proje bilgilerini `AGENTS.md` / `00-project-overview.mdc`'ye taşıyın; ekip kurallarını `01–05` ile çakışmayan numaralı `.mdc` dosyaları olarak tutun |

```markdown
@AGENTS.md

<!-- Claude Code-only instructions below; everything else goes in AGENTS.md. -->
```

---

## Adım 7 — Initium'un Eklediği Workflow'ları Gözden Geçirin

Reponuzda aynı yolda bir dosya yoksa senkronizasyon şunları ekledi:

- **`.github/workflows/ci.yml`** — genel bir yer tutucu. Başka adla bir CI'ınız varsa silin (ve
  kendi workflow'unuza dependency review ile SHA'ya sabitlenmiş action'lar eklemeyi düşünün).
  Hiç yoksa `/init ci: <stack'iniz>` ile gerçek bir tane üretin.
- **`.github/workflows/initium-sync.yml`** — Initium güncellemeleri için haftalık PR açar.
  Güncel kalmak için tutun ya da silip `sync.sh`'yi elle çalıştırın. Ayarları:
  `agent.config.yaml → initium_sync`.

---

## Adım 8 — Projeyi `/init` ile Tanımlayın

Repoyu Claude Code'da (ya da Cursor / OpenCode'da) açıp çalıştırın:

```
/init
```

Argümansız `/init`, repoyu mevcut bir kod tabanı olarak ele alır: manifest'lerinizi, betiklerinizi,
dizin ağacınızı ve CI'ınızı okuyarak `AGENTS.md`, `00-project-overview.mdc`, `docs/context/` ve
`docs/architecture/overview.md` dosyalarını gerçekte var olanla doldurur. Yalnızca `TODO` yer
tutucularını değiştirir, mevcut CI'a asla dokunmaz ve mimari kurallardan sapmaları yeniden yazım
önermek yerine "Known deviations" olarak kaydeder. Kod tek başına iş bağlamını anlatmıyorsa bir
cümle ekleyin:

```
/init existing: Acme mağazası için faturalama servisi, ödeme ekibinin sorumluluğunda
```

Ardından:

- `/codegraph setup` — büyük kod tabanlarında önerilir; ajanlar tüm dosyaları okumak yerine
  sembolleri ve çağıranları sorgular.
- `/skill list` — stack'inize uyan skill'leri doğrulayın; ekibe özgü olanları
  `/skill new project-<konu>` ile yazın.
- `bash .initium/scripts/init.sh` — otonom ajanı çalıştıracaksanız `agent.config.yaml` (tracker,
  eskalasyon kanalları, domain anahtar kelimeleri) için isteğe bağlı sihirbaz.
- Kullanmayacağınız şablonları silin (örneğin yalnızca backend olan bir serviste `DESIGN.md` /
  `PRODUCT.md`).

---

## Adım 9 — Doğrulayın ve PR Açın

```bash
bash .initium/scripts/validate.sh     # kalan TODO'lar hata değil, uyarıdır
git add -A
git commit -m "chore: adopt Initium $INITIUM_TAG"
```

`chore/adopt-initium` branch'inden PR açın. İnceleyenler `merge_required` dosyalara,
`.initium/initium.json` içindeki `project_owned` listesine ve `/init`'in ürettiği içeriğe odaklanmalı.

---

## Benimsemeden Sonra

- Güncellemeler `initium-sync.yml` PR'larıyla ya da `bash .initium/scripts/sync.sh` ile
  (Claude Code'da `/sync-initium`) gelir. Bkz. [sync-guide.md](../../.initium/docs/sync-guide.md).
- İkinci senkronizasyondan itibaren benimseme modu kapalıdır: `project_owned` listenizde olmayan
  Initium dosyaları Initium sürümüne güncellenir. Adım 4'ün önemi buradan gelir.
- Yeni ekip üyeleri [onboarding.tr.md](onboarding.tr.md) dosyasını "AI Araçlarını Kurma" bölümünden
  itibaren takip eder.

## Monorepo'lar

Initium'u repo kökünde bir kez kurun. Her servisi `AGENTS.md`'nin repo yapısı bölümünde tanımlayın;
paket düzeyindeki ayrıntıları iç içe `AGENTS.md` dosyaları (ajanlar en yakındakini okur) ya da
path glob'larıyla sınırlanmış `project-<servis>` skill'leri olarak ekleyin.

## Initium'u Kaldırmak

`.initium/`, `.claude/commands/`, `.claude/skills/`, `.opencode/commands/`,
`.cursor/rules/0[1-5]-*.mdc`, `.continue/rules/`, `.agent-templates/` ve Initium workflow'larını
silin; ardından `git remote remove skeleton` ve `git for-each-ref --format='delete %(refname)' refs/initium/ | git update-ref --stdin`
komutlarını çalıştırın. `AGENTS.md`'yi tutun — Initium olmadan da işe yarar.
