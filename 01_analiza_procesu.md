# Obieg faktur kosztowych – analiza procesu

## 1. Kontekst

Firma handlowo-magazynowa (ok. 80 pracowników) dostaje miesięcznie ok. 300 faktur kosztowych:
za usługi IT, transport, materiały magazynowe i marketing. Każda faktura musi zostać sprawdzona
merytorycznie (czy usługa / towar rzeczywiście był zamówiony) i zatwierdzona przed zapłatą.

## 2. Stan obecny (AS-IS)

1. Faktura przychodzi mailem albo pocztą do księgowości.
2. Księgowa drukuje fakturę i przekazuje ją (lub przesyła mailem) kierownikowi działu.
3. Kierownik podpisuje fakturę i odnosi ją do księgowości.
4. Faktury powyżej 5 000 zł brutto dodatkowo podpisuje dyrektor finansowy.
5. Księgowa księguje fakturę i przekazuje ją do zapłaty.

### Problemy

| # | Problem | Skutek |
|---|---------|--------|
| P1 | Faktury „giną” na biurkach i w skrzynkach mailowych | spóźnione płatności, odsetki, nerwowe telefony od dostawców |
| P2 | Nie wiadomo, u kogo w danej chwili jest faktura | księgowość traci czas na dopytywanie |
| P3 | Gdy kierownik jest na urlopie, faktura czeka na jego powrót | j.w. |
| P4 | Zdarza się, że ta sama faktura zostaje zaksięgowana dwa razy (mail + papier) | podwójna płatność |
| P5 | Brak historii: kto zatwierdził, kiedy i dlaczego odrzucił | problem przy audycie |
| P6 | Brak danych do raportowania (koszty wg działów, czas obiegu) | zarząd nie widzi kosztów na bieżąco |

## 3. Stan docelowy (TO-BE)

Elektroniczny obieg faktury w systemie workflow (np. WEBCON BPS).

### Uczestnicy (role)

| Rola | Co robi w procesie |
|------|--------------------|
| Księgowość | rejestruje fakturę, wyjaśnia braki z dostawcą, księguje |
| Kierownik MPK | zatwierdza merytorycznie faktury swojego działu (MPK = miejsce powstawania kosztów) |
| Dyrektor finansowy | zatwierdza faktury powyżej progu kwotowego |
| System | sprawdza dane, wybiera akceptującego, pilnuje terminów, wysyła powiadomienia |

### Kroki procesu

1. **Rejestracja** (Księgowość) – wprowadzenie danych faktury i załącznika (skan / PDF).
2. **Kontrola danych** (System) – czy pola są uzupełnione, czy faktura nie jest duplikatem.
   - braki → **Wyjaśnienie z dostawcą** (Księgowość) → powrót do rejestracji.
3. **Akceptacja merytoryczna** (Kierownik MPK lub jego zastępca).
   - po 3 dniach bez decyzji → automatyczne przypomnienie + informacja do księgowości.
4. **Akceptacja finansowa** (Dyrektor finansowy) – tylko gdy kwota brutto > 5 000 zł.
5. **Księgowanie i przekazanie do płatności** (Księgowość).
6. Odrzucenie na kroku 3 lub 4 → **zwrot faktury do dostawcy / archiwizacja** (Księgowość).

### Reguły biznesowe

| ID | Reguła |
|----|--------|
| R1 | Wymagane pola: numer faktury, dostawca, MPK, kwota netto, VAT. Kwota netto > 0. |
| R2 | Kwota brutto liczy się sama: netto + VAT (nikt jej nie wpisuje ręcznie – mniej pomyłek). |
| R3 | Duplikat = ten sam dostawca + ten sam numer faktury. System nie pozwala go zapisać. |
| R4 | Akceptującym jest kierownik MPK wybranego na fakturze. |
| R5 | Jeśli kierownik ma w danym dniu aktywne zastępstwo, zadanie trafia do zastępcy. |
| R6 | Faktura z kwotą brutto **powyżej 5 000 zł** wymaga dodatkowej akceptacji dyrektora finansowego. |
| R7 | Odrzucenie wymaga podania komentarza (powodu). |
| R8 | Zatwierdzić może tylko osoba, do której w danej chwili należy zadanie. |
| R9 | Zadanie czekające dłużej niż 3 dni jest oznaczane jako „po terminie”, a akceptujący dostaje przypomnienie. |
| R10 | Każda decyzja zapisuje się w historii: kto, kiedy, jaka decyzja, komentarz. |
| R11 | Termin płatności nie może być wcześniejszy niż data wystawienia. Gdy do terminu zostaje ≤ 3 dni, a faktura jest wciąż w obiegu, księgowość dostaje ostrzeżenie. |
| R12 | NIP dostawcy musi mieć poprawną sumę kontrolną. Nowego dostawcę dodaje się do słownika przed rejestracją faktury. |
| R13 | Próg kwotowy, liczba dni do przypomnienia, kierowników MPK, zastępstwa i słownik dostawców zmienia administrator w panelu ustawień – bez zmian w kodzie. |

### Automatyzacje

| Automatyzacja | Co robi | Oszczędność |
|---------------|---------|-------------|
| Odczyt danych z PDF | Po wczytaniu faktury system sam wypełnia numer, daty, NIP i kwoty, rozpoznaje dostawcę i podpowiada MPK na podstawie poprzednich faktur | mniej przepisywania i literówek |
| Kontrola danych | Duplikat, suma kontrolna NIP, netto + VAT = brutto | mniej błędów, brak podwójnych płatności |
| Powiadomienia e-mail | Nowe zadanie, przekazanie zadania (zastępstwo), odrzucenie, zaksięgowanie, przypomnienie, zbliżający się termin płatności | nikt nie musi pilnować faktur ręcznie |
| Eksport do Excela | Lista faktur z filtrami do pliku CSV | szybkie zestawienia dla zarządu |

### Formularz faktury

| Pole | Typ | Wymagane | Uwagi |
|------|-----|----------|-------|
| Numer faktury | tekst | tak | |
| Dostawca | lista (słownik dostawców) | tak | z NIP |
| MPK | lista (słownik MPK) | tak | wyznacza akceptującego |
| Data wystawienia | data | tak | |
| Termin płatności | data | tak | nie wcześniej niż data wystawienia |
| Kwota netto | liczba | tak | > 0 |
| VAT | liczba | tak | ≥ 0 |
| Kwota brutto | liczba | – | wyliczana (R2) |
| Opis | tekst wielowierszowy | nie | czego dotyczy faktura |
| Załącznik | plik | tak | PDF faktury; dane odczytywane automatycznie, podgląd obok formularza |
| Komentarz do decyzji | tekst | przy odrzuceniu | R7 |

### Raporty i wskaźniki

- Faktury czekające na decyzję dłużej niż 3 dni (z nazwiskiem osoby, u której utknęły).
- Średni czas obiegu faktury (od rejestracji do zaksięgowania) wg działów.
- Wartość faktur wg MPK i statusu.
- Odsetek faktur odrzuconych.
- Faktury, którym zbliża się lub minął termin płatności.

## 4. Korzyści

| Problem | Rozwiązanie |
|---------|-------------|
| P1, P2 | Każda faktura ma status i przypisaną osobę; widać to w raporcie |
| P3 | Zastępstwa (R5) |
| P4 | Blokada duplikatów (R3) |
| P5 | Historia decyzji (R10) |
| P6 | Raporty i dashboard |
| Spóźnienia | Przypomnienia po 3 dniach (R9) i ostrzeżenia o terminie płatności (R11) |
| Ręczne przepisywanie faktur | Automatyczny odczyt danych z PDF |

## 5. Pytania otwarte do klienta

To pytania, które zadałbym na warsztacie analitycznym, zanim cokolwiek zbuduję:

1. Czy próg 5 000 zł jest liczony od kwoty netto, czy brutto? Czy może się zmieniać?
2. Czy faktura może być rozbita na kilka MPK (np. 60% IT, 40% Magazyn)? Kto wtedy zatwierdza?
3. Co ma się stać z fakturą odrzuconą – korekta od dostawcy wraca jako nowa faktura czy do tego samego obiegu?
4. Czy faktury w walutach obcych też przechodzą ten obieg? Według jakiego kursu liczyć próg?
5. Czy dane mają trafiać automatycznie do systemu ERP (integracja), czy księgowanie zostaje ręczne?
6. Kto ustawia zastępstwa – sam kierownik czy kadry?
