# Runbook — infrastruktura OCI

Instrukcja wdrożenia warstwy OCI pod pipeline PKP. Wdrożenie PROD (`PKPPROD`).

---

## 1. Instancja ADB

Konsola OCI → **Autonomous Database → Create Autonomous Database**.

| Pole | Wartość | Dlaczego |
|---|---|---|
| Display name | `pkp-prod` | nazwa widoczna w konsoli |
| Database name | `PKPPROD` | litery/cyfry, start od litery, max 30 |
| Compartment | `pkp-wroclaw-glowny` | logiczny „folder" na zasoby projektu — trzyma ADB + bucket-y + IAM razem, ten sam co dev |
| Workload type | **Lakehouse** | wariant ADW (analityka), pod hurtownię/statystyki |
| Tier | **Always Free** | budżet zerowy; limit 2 ADB na tenancy (dev+prod = pełne) |

**Network access** → **Secure access from everywhere** + **mTLS**

**Encryption key** → **Oracle-managed key**

Ustaw hasło **ADMIN** przy tworzeniu (potrzebne do migracji).

---

## 2. Wallet

Strona bazy → **Database connection → Download wallet**.

- Typ: **Instance Wallet** (dla tej jednej bazy).
- Ustaw hasło paczki (nie mylić z hasłem bazy).
- **Rozpakuj** do `OCI\Wallet_PKPPROD` — *dlaczego:* python-oracledb thin czyta katalog, nie ZIP.
- Wallet PROD ≠ wallet DEV (osobne poświadczenie połączenia).

Test:
```python
import oracledb
oracledb.connect(user="ADMIN", password="<haslo>", dsn="pkpprod_high",
    config_dir=r"...\OCI\Wallet_PKPPROD", wallet_location=r"...\OCI\Wallet_PKPPROD")
print("PROD OK")
```
`dsn=pkpprod_high` — sprawdź nazwę w `tnsnames.ora`.

---

## 3. Bucket-y

**Object Storage → Buckets** (kompartment `pkp-wroclaw-glowny`) → **Create bucket**.

| Bucket | Rola | Lifecycle delete |
|---|---|---|
| `prod-pkp` | daily (surowy JSON) | **3 dni** |
| `prod-pkp-live` | live (delty) | **2 dni** |

- Nazwy osobne od dev (`bronze-*`) → jawne rozdzielenie prod/dev.
- Lifecycle: bucket → **Lifecycle Policy Rules** → Delete, wiek 3/2 dni. Wiek liczony od uploadu.

---

## 4. Auth do bucketów

Pipeline używa **OCI Python SDK** (profil `~/.oci/config`)

Zmienne env na PROD (osobne dla DEV):
```
PKP_OCI_BUCKET=prod-pkp
PKP_OCI_BUCKET_LIVE=prod-pkp-live
PKP_OCI_PROFILE=<profil z prawami do prod-*>
PKP_OCI_CONFIG_FILE=<config; w kontenerze /oci/config.docker>
```
Ten sam tenancy co dev → ten sam klucz API OK.

---

## 5. IAM policy

Polityka IAM to reguła nadająca uprawnienia w OCI — mówi „kto / co może wykonać jaką operację / na czym / gdzie". Bez odpowiedniej reguły operacja jest blokowana.

Tu nie nadajemy uprawnień userowi, tylko **samej usłudze Object Storage** — żeby mogła działać na obiektach w Twoim kompartmencie. Jest potrzebna m.in. do **lifecycle rules** (auto-kasowanie po 3/2 dniach z sekcji 3): to usługa Object Storage w tle usuwa wygasłe pliki, więc musi mieć do tego prawo. Bez tej reguły reguły lifecycle nie zadziałają.

**Reguła:**


Rozbicie na części:
| Fragment | Znaczenie |
|---|---|
| `Allow` | nadaj uprawnienie |
| `service objectstorage-eu-paris-1` | **komu** — usłudze Object Storage w regionie Paryż (nie userowi). Nazwa regionu musi zgadzać się z regionem instancji |
| `to manage` | **jaki zakres** — pełny (read + write + delete). Słabsze poziomy to `inspect` / `read` / `use` |
| `object-family` | **na czym** — rodzina zasobów: bucket-y i obiekty w nich |
| `in compartment pkp-wroclaw-glowny` | **gdzie** — ograniczone do tego jednego kompartmentu |

**Gdzie utworzyć.** Konsola → **Identity & Security → Policies** → w kompartmencie `pkp-wroclaw-glowny` (lub root) → **Create Policy**.

---

## 6. Kolejność

1. ADB `PKPPROD` + hasło ADMIN
2. wallet → `OCI\Wallet_PKPPROD` + test `PROD OK`
3. bucket-y `prod-pkp` (3d) + `prod-pkp-live` (2d) + lifecycle
4. env bucketów/profilu OCI
5. → migracja Flyway (`02 RUNBOOK_migracja_flyway.md`)
6. → implementacja warstwy docker (`03 RUNBOOK_docker_deployment.md`)

**Do podmiany:** `<haslo>`, ścieżki walletu, region IAM.
