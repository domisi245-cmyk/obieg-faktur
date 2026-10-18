# Przypadki testowe

Każdy test sprawdza jedną regułę z analizy (R1–R13) albo jedną automatyzację. Tabelę można
wydrukować i użyć jako listy kontrolnej przy testach odbiorczych – kolumna „Wynik” jest do wypełnienia
przez osobę testującą.

Przed testami kliknij **Reset danych**. „Przykład 1–4” to przyciski w zakładce *Nowa faktura*
(zalogowana Anna Nowak). Gdy demo jest otwarte z dysku, wybierz te pliki ręcznie z folderu `04_demo/przyklady`.

## Rejestracja i odczyt PDF

| ID | Reguła | Kroki | Oczekiwany wynik | Wynik |
|----|--------|-------|------------------|-------|
| T01 | PDF | Wczytaj przykład 1 | Podgląd faktury po lewej, „Odczytano automatycznie 8 z 8 pól”, pola formularza na zielono, dostawca TechSerwis i MPK IT-01 podpowiedziane | |
| T02 | R1 | Bez wczytywania PDF wypełnij wszystkie pola ręcznie → Zarejestruj | Komunikat „Dodaj plik PDF faktury” | |
| T03 | R1 | Wczytaj przykład 1, wyczyść pole „Kwota netto” → Zarejestruj | „Uzupełnij wszystkie wymagane pola” | |
| T04 | R2 | Wpisz netto `1000`, kliknij „VAT 23%” | VAT = 230,00, brutto = 1 230,00 zł (pole brutto nie do edycji) | |
| T05 | R11 | Wczytaj przykład 1, ustaw termin płatności przed datą wystawienia | „Termin płatności nie może być wcześniejszy niż data wystawienia” | |
| T06 | R3 | Wczytaj przykład 3 | Już przy odczycie ostrzeżenie ⛔ „Ta faktura jest już w systemie”; Zarejestruj → „Duplikat!” | |
| T07 | R3 | Wczytaj przykład 3, zmień dostawcę na inną firmę → Zarejestruj | Faktura zapisuje się (ten sam numer u innego dostawcy to nie duplikat) | |
| T08 | R12 | Wczytaj przykład 4 | Komunikat, że dostawcy nie ma w słowniku, i przycisk „Dodaj do słownika” | |
| T09 | R12 | T08 → „Dodaj do słownika”, wybierz MPK → Zarejestruj | Dostawca pojawia się na liście i w Ustawieniach, faktura zapisana | |
| T10 | PDF | Wczytaj własny PDF będący skanem (zdjęciem) | Odczyt nie znajduje pól, dane można wpisać ręcznie – aplikacja się nie psuje | |

## Obieg i akceptacje

| ID | Reguła | Kroki | Oczekiwany wynik | Wynik |
|----|--------|-------|------------------|-------|
| T11 | R4 | Zarejestruj przykład 1 (MPK IT-01) | Trafia do Piotra Wiśniewskiego, w zakładce Powiadomienia jest mail „Nowe zadanie” | |
| T12 | R5 | Zarejestruj fakturę na MPK MAG-01 | Trafia do Ewy Dąbrowskiej (zastępstwo za Katarzynę) | |
| T13 | R5 | Kliknij „+1 dzień” 6 razy, zaloguj się jako Katarzyna | Po końcu urlopu zadania Magazynu wracają do Katarzyny, ona dostaje mail „Przekazano Ci zadanie” | |
| T14 | R6 | Zarejestruj przykład 1 (3 075 zł) → Piotr zatwierdza | Status „Do zaksięgowania” (bez dyrektora) | |
| T15 | R6 | Zarejestruj przykład 2 (10 086 zł) → Piotr zatwierdza | Status „Akceptacja dyrektora”, Marek dostaje mail | |
| T16 | R6 | Faktura na dokładnie 5 000,00 zł brutto → kierownik zatwierdza | „Do zaksięgowania” – próg to „powyżej 5000” | |
| T17 | R7 | Kierownik klika „Odrzuć” bez komentarza | Komunikat o wymaganym powodzie, status bez zmian | |
| T18 | R7 | Odrzuć z komentarzem | Status „Odrzucona”, komentarz w historii, Anna dostaje mail z powodem | |
| T19 | R8 | Zaloguj się jako Tomasz, otwórz fakturę działu IT w „Wszystkie faktury” | Brak przycisków Zatwierdź / Odrzuć | |
| T20 | R9 | Kliknij „+1 dzień” 4 razy | Faktury oznaczone „po terminie”, maile „Przypomnienie” i „Faktura utknęła”, raport je pokazuje | |
| T21 | R11 | Kliknij „+1 dzień” 3 razy | Faktura MAG/80/2026 ma termin „minął”, raport „terminy płatności” ją pokazuje | |
| T22 | R10 | Przeprowadź fakturę przez cały obieg | Historia zawiera każdy krok: kto, kiedy, decyzja | |
| T23 | – | Faktura „Do wyjaśnienia” → Anna klika „Uzupełniono” | Faktura trafia do akceptacji kierownika | |
| T24 | PDF | Otwórz szczegóły faktury zarejestrowanej z PDF, odśwież stronę (F5) i otwórz je ponownie | Podgląd PDF nadal widoczny, „Otwórz w nowej karcie” działa | |

## Ustawienia (administrator)

| ID | Reguła | Kroki | Oczekiwany wynik | Wynik |
|----|--------|-------|------------------|-------|
| T25 | R13 | Ustawienia → próg 20 000 → Zapisz; zarejestruj przykład 2 i zatwierdź jako Piotr | Faktura idzie od razu do księgowania | |
| T26 | R13 | Ustawienia → zmień zatwierdzającego dla IT-01 na Tomasza | Zadania IT przechodzą do Tomasza, on dostaje mail „Przekazano Ci zadanie” | |
| T27 | R13 | Dodaj zastępstwo, w którym osoba zastępuje samą siebie | Komunikat o błędzie | |
| T28 | R12 | Dodaj dostawcę z NIP `1234567890` | „Niepoprawny NIP” (zła suma kontrolna) | |

## Lista faktur

| ID | Kroki | Oczekiwany wynik | Wynik |
|----|-------|------------------|-------|
| T29 | Wszystkie faktury → wpisz „trans” | Widać tylko faktury Trans-Logistyki, licznik „Wyświetlono X z Y” | |
| T30 | Dodaj filtr Status = Zaksięgowana → Eksport do Excela | Plik CSV otwiera się w Excelu z polskimi znakami, zawiera tylko widoczne faktury | |

## Testy w bazie SQL

Na końcu pliku `03_baza_danych.sql` są gotowe testy T-1 … T-7 (zakomentowane).
Zaznacz jeden blok myszką i naciśnij F5. Błąd w wyniku oznacza, że reguła działa, bo baza
nie przepuściła złych danych.

## Znaleziony błąd? Tak go opisz

> **Tytuł:** Faktura 5 000,00 zł trafia do dyrektora
> **Kroki:** 1) Anna rejestruje fakturę netto 4065,04 VAT 934,96 (brutto 5000,00) 2) Piotr zatwierdza
> **Oczekiwane:** Do zaksięgowania (R6: tylko *powyżej* 5000)
> **Faktyczne:** Akceptacja dyrektora
> **Priorytet:** średni
