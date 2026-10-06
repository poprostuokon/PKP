# Runbook — infrastruktura OCI

Dokument opisuje procedurę wdrożenia warstwy Oracle Cloud Infrastructure (OCI) dla
pipeline'u PKP. Zakres obejmuje środowisko produkcyjne (`PKPPROD`): utworzenie instancji
Autonomous Database, konfigurację połączenia (wallet), przygotowanie magazynu obiektowego
oraz reguł dostępu. Środowisko utrzymywane jest w warstwie Always Free.

---

## 1. Instancja Autonomous Database

Konsola OCI → **Autonomous Database → Create Autonomous Database**.

| Pole | Wartość | Uzasadnienie |
|---|---|---|
| Display name | `pkp-prod` | Nazwa prezentacyjna w konsoli |
| Database name | `PKPPROD` | Litery i cyfry, rozpoczęcie od litery, maksymalnie 30 znaków |
| Compartment | `pkp-wroclaw-glowny` | Logiczny kontener zasobów projektu — grupuje ADB, buckety i reguły IAM; wspólny ze środowiskiem DEV |
| Workload type | **Lakehouse** | Wariant Autonomous Data Warehouse (analityczny), właściwy dla warstwy hurtowni i statystyk |
| Tier | **Always Free** | Zerowy budżet; limit dwóch instancji ADB na tenancy (DEV + PROD wykorzystują pełną pulę) |

Pozostałe ustawienia:

- **Network access** — Secure access from everywhere, uwierzytelnianie mTLS.
- **Encryption key** — Oracle-managed key.
- **Hasło ADMIN** — ustawiane przy tworzeniu instancji; wymagane do wykonania migracji Flyway.

---

## 2. Wallet połączeniowy

Strona instancji → **Database connection → Download wallet**.

- Typ: **Instance Wallet** (dedykowany pojedynczej bazie).
- Ustaw hasło paczki wallet (odrębne od hasła bazy danych).
- **Rozpakuj** zawartość do katalogu `OCI\Wallet_PKPPROD`. Sterownik `python-oracledb`
  w trybie *thin* odczytuje katalog, nie archiwum ZIP.
- Wallet produkcyjny jest odrębny od walletu DEV — stanowi niezależne poświadczenie
  połączenia.

Weryfikacja połączenia:

```python
import oracledb
oracledb.connect(user="ADMIN", password="<haslo>", dsn="pkpprod_high",
    config_dir=r"...\OCI\Wallet_PKPPROD", wallet_location=r"...\OCI\Wallet_PKPPROD")
print("PROD OK")
```

Nazwę usługi `pkpprod_high` należy zweryfikować w pliku `tnsnames.ora` wewnątrz walletu.

---

## 3. Magazyn obiektowy (buckety)

**Object Storage → Buckets** (kompartment `pkp-wroclaw-glowny`) → **Create bucket**.

| Bucket | Rola | Reguła lifecycle (delete) |
|---|---|---|
| `prod-pkp` | Warstwa daily — surowe dokumenty JSON | 3 dni |
| `prod-pkp-live` | Warstwa live — pliki różnicowe (delty) | 2 dni |

- Nazwy odrębne od środowiska DEV (`bronze-*`) zapewniają jednoznaczne rozdzielenie
  produkcji od środowiska deweloperskiego.
- Reguły lifecycle: bucket → **Lifecycle Policy Rules** → Delete, wiek 3/2 dni. Wiek
  obiektu liczony jest od momentu przesłania.

---

## 4. Uwierzytelnianie dostępu do bucketów

Pipeline korzysta z **OCI Python SDK** z profilem konfiguracyjnym `~/.oci/config`.

Zmienne środowiskowe dla PROD (odrębne od DEV):

```
PKP_OCI_BUCKET=prod-pkp
PKP_OCI_BUCKET_LIVE=prod-pkp-live
PKP_OCI_PROFILE=<profil z uprawnieniami do prod-*>
PKP_OCI_CONFIG_FILE=<plik konfiguracyjny; w kontenerze /oci/config.docker>
```

Środowisko produkcyjne działa w tym samym tenancy co DEV, dlatego ten sam klucz API
pozostaje wystarczający.

---

## 5. Reguła IAM

Reguła IAM (Identity and Access Management) definiuje uprawnienia w OCI według schematu:
podmiot — operacja — zasób — zakres. Operacja nieobjęta odpowiednią regułą jest domyślnie
blokowana.

W tym przypadku uprawnienie nadawane jest nie użytkownikowi, lecz **samej usłudze Object
Storage** — aby mogła operować na obiektach w kompartmencie projektu. Reguła jest
niezbędna do działania reguł lifecycle (sekcja 3): automatyczne usuwanie wygasłych plików
realizuje usługa Object Storage w tle i wymaga do tego odpowiednich uprawnień. Bez tej
reguły polityki lifecycle nie zostaną wykonane.

```
Allow service objectstorage-eu-paris-1 to manage object-family in compartment pkp-wroclaw-glowny
```

Rozbicie reguły:

| Fragment | Znaczenie |
|---|---|
| `Allow` | Nadanie uprawnienia |
| `service objectstorage-eu-paris-1` | Podmiot — usługa Object Storage w regionie Paryż (nie użytkownik). Region musi być zgodny z regionem instancji |
| `to manage` | Zakres operacji — pełny (read, write, delete). Słabsze poziomy: `inspect`, `read`, `use` |
| `object-family` | Zasób — rodzina obejmująca buckety i przechowywane w nich obiekty |
| `in compartment pkp-wroclaw-glowny` | Ograniczenie do wskazanego kompartmentu |

Lokalizacja: Konsola → **Identity & Security → Policies** → kompartment
`pkp-wroclaw-glowny` (lub root) → **Create Policy**.

---

## 6. Kolejność wdrożenia

1. Utworzenie instancji ADB `PKPPROD` wraz z hasłem ADMIN.
2. Pobranie i rozpakowanie walletu do `OCI\Wallet_PKPPROD`; weryfikacja połączenia
   (`PROD OK`).
3. Utworzenie bucketów `prod-pkp` (3 dni) i `prod-pkp-live` (2 dni) wraz z regułami
   lifecycle.
4. Konfiguracja zmiennych środowiskowych bucketów oraz profilu OCI.
5. Migracja schematu Flyway (`02 RUNBOOK_migracja_flyway.md`).
6. Wdrożenie warstwy kontenerów (`03 RUNBOOK_docker_deployment.md`).

**Elementy do uzupełnienia przed wdrożeniem:** hasło ADMIN (`<haslo>`), ścieżki walletu,
region w regule IAM.
