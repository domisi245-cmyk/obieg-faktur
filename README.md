# Elektroniczny obieg faktur kosztowych

Projekt przygotowany samodzielnie na potrzeby rekrutacji na stanowisko Junior WEBCON / Junior Konsultant Low-Code.
Pokazuje cały proces: od analizy procesu w firmie, przez model procesu i bazę danych, po działającą aplikację i testy.

## Zobacz

- 🎬 **Prezentacja wideo:** 5 krótkich filmów (łącznie ok. 4 minuty) – linki w tabeli poniżej
- 🖱️ **Demo do samodzielnego przetestowania:** [LINK DO DEMO]
  (wersja online działa bez bazy danych – dane są zapisywane w przeglądarce)

| Film | Co pokazuje |
|------|-------------|
| [1. Rejestracja faktury z PDF](https://www.youtube.com/watch?v=s3sxf5IKI8M) | Odczyt danych z PDF, wykrywanie duplikatów, zapis faktury z plikiem w bazie |
| [2. Akceptacje, próg kwotowy i zastępstwa](https://www.youtube.com/watch?v=3b7ki4CnNuM) | Akceptacja kierownika, przekazanie do dyrektora powyżej progu, historia decyzji, zastępstwa |
| [3. Reguły procesu w bazie danych](https://www.youtube.com/watch?v=7fZp0s-HUoM) | Próba obejścia aplikacji – baza odmawia, bo reguły są w procedurach SQL |
| [4. Przypomnienia, terminy i raport](https://www.youtube.com/watch?v=TJFrMwz9MhQ) | Automatyczne przypomnienia, faktury, które utknęły, terminy płatności, raport |
| [5. Konfiguracja bez programowania](https://www.youtube.com/watch?v=X9FKYPVfLpk) | Zmiana progu akceptacji w panelu ustawień, bez zmian w kodzie |

## Problem

Firma dostaje kilkaset faktur kosztowych miesięcznie. Krążą mailem i na papierze, giną na biurkach,
nie wiadomo, u kogo są, a czasem ta sama faktura zostaje zapłacona dwa razy. Gdy kierownik jest na urlopie,
wszystko stoi.

## Rozwiązanie

Elektroniczny obieg faktury:

1. **Księgowość** wczytuje fakturę PDF – system sam odczytuje numer, daty, NIP i kwoty, rozpoznaje dostawcę i podpowiada dział.
2. System **sprawdza dane**: wymagane pola, duplikaty, poprawność NIP, terminy.
3. Fakturę zatwierdza **kierownik działu** – albo jego zastępca, jeśli kierownik jest na urlopie.
4. Faktury powyżej progu kwotowego zatwierdza dodatkowo **dyrektor finansowy**.
5. **Księgowość** księguje fakturę i przekazuje ją do płatności.

Przez cały czas system zapisuje historię decyzji, wysyła powiadomienia, przypomina o zaległych decyzjach
i ostrzega przed terminem płatności. Próg kwotowy, zastępstwa, kierowników działów i dostawców
zmienia się w panelu ustawień, bez programowania.

## Zawartość repozytorium

| Plik | Co zawiera |
|------|-----------|
| [01_analiza_procesu.md](01_analiza_procesu.md) | Opis problemu, proces obecny i docelowy, reguły biznesowe, formularz, raporty, pytania do klienta |
| [02_proces_obiegu_faktur.bpmn](02_proces_obiegu_faktur.bpmn) | Model procesu w notacji BPMN 2.0 (otwiera się np. na [demo.bpmn.io](https://demo.bpmn.io)) |
| [03_baza_danych.sql](03_baza_danych.sql) | Baza Microsoft SQL Server: tabele, procedury z regułami procesu, dane testowe, raporty, testy reguł |
| [04_demo/](04_demo/) | Aplikacja w przeglądarce + przykładowe faktury PDF (dane fikcyjne) |
| [05_przypadki_testowe.md](05_przypadki_testowe.md) | Scenariusze testowe powiązane z regułami |
| [06_serwer/](06_serwer/) | Serwer Node.js łączący aplikację z bazą SQL Server |

## Jak to działa

```
Przeglądarka (04_demo)  ──▶  Serwer Node.js (06_serwer)  ──▶  SQL Server: baza ObiegFaktur
formularze, podgląd PDF,      przekazuje dane                 reguły procesu, historia decyzji,
odczyt danych z PDF                                           powiadomienia, przypomnienia
```

Reguły procesu (kto może zatwierdzić, próg kwotowy, zastępstwa, blokada duplikatów, wymagany powód odrzucenia)
są zapisane w bazie danych, a nie tylko w aplikacji. Dzięki temu obowiązują zawsze – także wtedy, gdy ktoś
spróbuje ominąć aplikację.

Aplikacja działa w dwóch trybach:
- **z bazą danych** – po uruchomieniu serwera (wersja pokazana na filmach),
- **bez bazy** – sama strona, np. wersja online; dane zapisują się wtedy w przeglądarce.

## Uruchomienie wersji z bazą (Windows)

1. Zainstaluj SQL Server Express i SQL Server Management Studio (SSMS).
2. Otwórz `03_baza_danych.sql` w SSMS i wykonaj (F5) – powstanie baza **ObiegFaktur** z danymi testowymi.
3. Zainstaluj Node.js (wersja LTS).
4. Uruchom `06_serwer/uruchom.bat` – otworzy się aplikacja pod adresem http://localhost:3000.

## Co można rozwinąć

- integracja z systemem ERP (automatyczne księgowanie),
- odczyt skanów faktur (OCR),
- faktury w walutach obcych i podział kosztów na kilka działów,
- logowanie użytkowników i rzeczywista wysyłka maili.

Wszystkie firmy, osoby i dane w projekcie są fikcyjne.
