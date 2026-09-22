# Wallety Oracle ADB (połączenie do bazy)

Ten folder trzyma **wallety** do połączenia z bazami Oracle Autonomous Database
(ADB) projektu PKP. Wallet to komplet certyfikatów mTLS, bez niego kod nie
połączy się z bazą.

> **UWAGA — sekrety.** Zawartość walletów **nie jest** w repozytorium
> (wykluczona w `.gitignore`). Na nowej maszynie trzeba je wrzucić ręcznie.
> Ten README zostaje w repo jako instrukcja.

## Co ma tu być

| Element                 | Co to                                            |
|-------------------------|--------------------------------------------------|
| `Wallet_PKPDEV/`        | Rozpakowany wallet instancji **DEV** (PKPDEV)    |
| `Wallet_PKPPROD/`       | Rozpakowany wallet instancji **PROD** (PKPPROD)  |
| `Wallet_PKPDEV.zip`     | Ten sam wallet DEV jako `.zip` (źródło)          |
| `Wallet_PKPPROD.zip`    | Ten sam wallet PROD jako `.zip` (źródło)         |

**Po co `.zip`, a po co rozpakowany folder:**
- **`.zip`** = oryginał pobrany z konsoli OCI. Trzymany jako źródło: CI/CD
  (GitHub Actions) dekoduje wallet z sekretu base64 tego zipa, żeby Flyway
  i testy miały dostęp do bazy.
- **folder rozpakowany** = codzienna praca lokalna i Docker. Połączenie w
  trybie *thin* (python-oracledb) czyta stąd `tnsnames.ora`, `sqlnet.ora`
  i `cwallet.sso`. Pozostałe pliki (`ewallet.p12`, `*.jks`, `ewallet.pem`)
  to warianty pod inne tryby połączenia — zostawić bez zmian.

## Jak to zdobyć (nowa maszyna)

1. Konsola OCI → wybierz instancję ADB (**PKPDEV** lub **PKPPROD**) →
   *Database connection* → **Download wallet** (typ: *Instance Wallet*).
2. Wrzuć pobrany plik tutaj jako `Wallet_PKP<ENV>.zip`.
3. Rozpakuj go do folderu `Wallet_PKP<ENV>/`.
4. W pliku `.env` ustaw ścieżkę do folderu walletu (zmienne `PKP_WALLET_*`).

Powtórz dla obu środowisk (DEV i PROD).
