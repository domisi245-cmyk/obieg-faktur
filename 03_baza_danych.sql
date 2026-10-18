/* =====================================================================
   Obieg faktur kosztowych – baza danych (Microsoft SQL Server)
   ---------------------------------------------------------------------
   Jak uruchomić:
   1. Zainstaluj SQL Server Express + SQL Server Management Studio (SSMS).
   2. Otwórz ten plik w SSMS i naciśnij F5 (Wykonaj).
   3. Skrypt tworzy bazę od nowa, więc można go uruchamiać wielokrotnie.

   Z tej bazy korzysta aplikacja (folder 06_serwer): każda rejestracja,
   decyzja i zmiana ustawień w przeglądarce trafia tutaj, a reguły procesu
   pilnują procedury składowane – nawet gdyby ktoś ominął aplikację.

   Części skryptu:
   1. Tabele (struktura danych)
   2. Logika procesu (funkcje i procedury)
   3. Dane testowe
   4. Raporty
   5. Testy reguł
   ===================================================================== */

USE master;
GO
IF DB_ID(N'ObiegFaktur') IS NOT NULL
BEGIN
    ALTER DATABASE ObiegFaktur SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE ObiegFaktur;
END
GO
CREATE DATABASE ObiegFaktur;
GO
USE ObiegFaktur;
GO

/* =====================================================================
   1. TABELE
   ===================================================================== */

-- Poprawność NIP (suma kontrolna) – używana w ograniczeniu tabeli Dostawcy (R12)
CREATE OR ALTER FUNCTION dbo.fn_NipPoprawny (@Nip CHAR(10))
RETURNS BIT
AS
BEGIN
    IF @Nip IS NULL OR @Nip LIKE '%[^0-9]%' RETURN 0;
    DECLARE @Suma INT =
          6 * CAST(SUBSTRING(@Nip, 1, 1) AS INT) + 5 * CAST(SUBSTRING(@Nip, 2, 1) AS INT)
        + 7 * CAST(SUBSTRING(@Nip, 3, 1) AS INT) + 2 * CAST(SUBSTRING(@Nip, 4, 1) AS INT)
        + 3 * CAST(SUBSTRING(@Nip, 5, 1) AS INT) + 4 * CAST(SUBSTRING(@Nip, 6, 1) AS INT)
        + 5 * CAST(SUBSTRING(@Nip, 7, 1) AS INT) + 6 * CAST(SUBSTRING(@Nip, 8, 1) AS INT)
        + 7 * CAST(SUBSTRING(@Nip, 9, 1) AS INT);
    RETURN CASE WHEN @Suma % 11 = CAST(SUBSTRING(@Nip, 10, 1) AS INT) THEN 1 ELSE 0 END;
END
GO

-- Pracownicy biorący udział w procesie
CREATE TABLE dbo.Uzytkownicy (
    Id            INT IDENTITY PRIMARY KEY,
    ImieNazwisko  NVARCHAR(100) NOT NULL,
    Email         NVARCHAR(100) NOT NULL UNIQUE,
    Rola          NVARCHAR(20)  NOT NULL
        CHECK (Rola IN (N'Księgowość', N'Kierownik', N'Dyrektor'))
);

-- Miejsca powstawania kosztów (działy). Kierownik MPK zatwierdza faktury działu (R4).
CREATE TABLE dbo.MPK (
    Id           INT IDENTITY PRIMARY KEY,
    Kod          NVARCHAR(10)  NOT NULL UNIQUE,
    Nazwa        NVARCHAR(100) NOT NULL,
    KierownikId  INT NOT NULL REFERENCES dbo.Uzytkownicy(Id)
);

-- Zastępstwa na czas urlopu (R5)
CREATE TABLE dbo.Zastepstwa (
    Id            INT IDENTITY PRIMARY KEY,
    UzytkownikId  INT  NOT NULL REFERENCES dbo.Uzytkownicy(Id),
    ZastepcaId    INT  NOT NULL REFERENCES dbo.Uzytkownicy(Id),
    DataOd        DATE NOT NULL,
    DataDo        DATE NOT NULL,
    CONSTRAINT CK_Zastepstwa_Daty CHECK (DataDo >= DataOd),
    CONSTRAINT CK_Zastepstwa_Osoba CHECK (UzytkownikId <> ZastepcaId)
);

CREATE TABLE dbo.Dostawcy (
    Id     INT IDENTITY PRIMARY KEY,
    Nazwa  NVARCHAR(150) NOT NULL,
    NIP    CHAR(10)      NOT NULL UNIQUE,
    CONSTRAINT CK_Dostawcy_NIP CHECK (dbo.fn_NipPoprawny(NIP) = 1)               -- R12
);

CREATE TABLE dbo.Faktury (
    Id                  INT IDENTITY PRIMARY KEY,
    NumerFaktury        NVARCHAR(50)   NOT NULL,
    DostawcaId          INT            NOT NULL REFERENCES dbo.Dostawcy(Id),
    MpkId               INT            NOT NULL REFERENCES dbo.MPK(Id),
    DataWystawienia     DATE           NOT NULL,
    TerminPlatnosci     DATE           NOT NULL,
    KwotaNetto          DECIMAL(12,2)  NOT NULL CHECK (KwotaNetto > 0),           -- R1
    KwotaVAT            DECIMAL(12,2)  NOT NULL CHECK (KwotaVAT >= 0),
    KwotaBrutto         AS (KwotaNetto + KwotaVAT) PERSISTED,                      -- R2: liczy się sama
    Opis                NVARCHAR(500)  NULL,
    Zalacznik           NVARCHAR(260)  NULL,                                       -- nazwa pliku PDF
    PlikPdf             VARBINARY(MAX) NULL,                                       -- sam plik PDF
    Status              NVARCHAR(30)   NOT NULL
        CHECK (Status IN (N'Do wyjaśnienia', N'Akceptacja kierownika', N'Akceptacja dyrektora',
                          N'Do zaksięgowania', N'Zaksięgowana', N'Odrzucona')),
    DataRejestracji     DATETIME2      NOT NULL DEFAULT SYSDATETIME(),
    DataZmianyStatusu   DATETIME2      NOT NULL DEFAULT SYSDATETIME(),            -- do R9
    DataZakonczenia     DATETIME2      NULL,
    PrzypomnienieDla    DATETIME2      NULL,        -- krok, za który wysłano już przypomnienie
    OstrzezenieWyslane  BIT            NOT NULL DEFAULT 0,  -- ostrzeżenie o terminie płatności
    CONSTRAINT UQ_Faktury_Duplikat UNIQUE (DostawcaId, NumerFaktury),             -- R3
    CONSTRAINT CK_Faktury_Termin CHECK (TerminPlatnosci >= DataWystawienia)       -- R11
);

-- Historia decyzji (R10)
CREATE TABLE dbo.HistoriaObiegu (
    Id            INT IDENTITY PRIMARY KEY,
    FakturaId     INT           NOT NULL REFERENCES dbo.Faktury(Id),
    Krok          NVARCHAR(30)  NOT NULL,
    UzytkownikId  INT           NOT NULL REFERENCES dbo.Uzytkownicy(Id),
    Decyzja       NVARCHAR(20)  NOT NULL
        CHECK (Decyzja IN (N'Zarejestrowana', N'Do wyjaśnienia', N'Uzupełniona', N'Zaakceptowana', N'Odrzucona', N'Zaksięgowana')),
    Komentarz     NVARCHAR(500) NULL,
    DataDecyzji   DATETIME2     NOT NULL DEFAULT SYSDATETIME(),
    -- R7: odrzucenie wymaga komentarza
    CONSTRAINT CK_Historia_KomentarzPrzyOdrzuceniu
        CHECK (Decyzja <> N'Odrzucona' OR LEN(ISNULL(Komentarz, N'')) > 0)
);

-- Parametry procesu zmieniane przez administratora bez programowania (R13)
CREATE TABLE dbo.Ustawienia (
    Klucz    NVARCHAR(50)  PRIMARY KEY,
    Wartosc  DECIMAL(12,2) NOT NULL,
    Opis     NVARCHAR(200) NOT NULL
);

-- Powiadomienia e-mail (kolejka do wysłania przez serwis pocztowy)
CREATE TABLE dbo.Powiadomienia (
    Id              INT IDENTITY PRIMARY KEY,
    UzytkownikId    INT            NOT NULL REFERENCES dbo.Uzytkownicy(Id),
    FakturaId       INT            NULL REFERENCES dbo.Faktury(Id),
    Temat           NVARCHAR(200)  NOT NULL,
    Tresc           NVARCHAR(1000) NOT NULL,
    DataUtworzenia  DATETIME2      NOT NULL DEFAULT SYSDATETIME(),
    DataWyslania    DATETIME2      NULL          -- NULL = jeszcze nie wysłane
);
GO

/* =====================================================================
   2. LOGIKA PROCESU
   ===================================================================== */

-- „Teraz” procesu. W demo przycisk „+1 dzień” przesuwa czas (Ustawienia.PrzesuniecieDni),
-- żeby pokazać przypomnienia i terminy bez czekania kilku dni.
CREATE OR ALTER FUNCTION dbo.fn_Teraz ()
RETURNS DATETIME2
AS
BEGIN
    RETURN DATEADD(DAY,
        ISNULL((SELECT CAST(Wartosc AS INT) FROM dbo.Ustawienia WHERE Klucz = N'PrzesuniecieDni'), 0),
        SYSDATETIME());
END
GO

-- Kto faktycznie zatwierdza w danym dniu: osoba albo jej zastępca (R5)
CREATE OR ALTER FUNCTION dbo.fn_Akceptujacy (@UzytkownikId INT, @Data DATE)
RETURNS INT
AS
BEGIN
    DECLARE @Wynik INT = @UzytkownikId;

    SELECT TOP 1 @Wynik = ZastepcaId
    FROM dbo.Zastepstwa
    WHERE UzytkownikId = @UzytkownikId
      AND @Data BETWEEN DataOd AND DataDo
    ORDER BY DataOd DESC;

    RETURN @Wynik;
END
GO

-- Kto jest teraz odpowiedzialny za fakturę (R4, R5)
CREATE OR ALTER FUNCTION dbo.fn_Odpowiedzialny (@FakturaId INT)
RETURNS INT
AS
BEGIN
    DECLARE @Status NVARCHAR(30), @Kierownik INT, @Wynik INT;
    DECLARE @Dzis DATE = CAST(dbo.fn_Teraz() AS DATE);

    SELECT @Status = f.Status, @Kierownik = m.KierownikId
    FROM dbo.Faktury f JOIN dbo.MPK m ON m.Id = f.MpkId
    WHERE f.Id = @FakturaId;

    IF @Status = N'Akceptacja kierownika'
        SET @Wynik = dbo.fn_Akceptujacy(@Kierownik, @Dzis);
    ELSE IF @Status = N'Akceptacja dyrektora'
        SELECT TOP 1 @Wynik = dbo.fn_Akceptujacy(Id, @Dzis) FROM dbo.Uzytkownicy WHERE Rola = N'Dyrektor' ORDER BY Id;
    ELSE IF @Status IN (N'Do wyjaśnienia', N'Do zaksięgowania')
        SELECT TOP 1 @Wynik = Id FROM dbo.Uzytkownicy WHERE Rola = N'Księgowość' ORDER BY Id;

    RETURN @Wynik;
END
GO

-- Krótki opis faktury do treści powiadomień, np. „118/2026 od Trans-Logistyka S.A. na 15 375,00 zł”
CREATE OR ALTER FUNCTION dbo.fn_OpisFaktury (@FakturaId INT)
RETURNS NVARCHAR(400)
AS
BEGIN
    RETURN (SELECT f.NumerFaktury + N' od ' + d.Nazwa + N' na ' + FORMAT(f.KwotaBrutto, 'N2', 'pl-PL') + N' zł'
            FROM dbo.Faktury f JOIN dbo.Dostawcy d ON d.Id = f.DostawcaId
            WHERE f.Id = @FakturaId);
END
GO

-- Faktury w obiegu z osobą odpowiedzialną (do raportów)
CREATE OR ALTER VIEW dbo.v_FakturyWObiegu
AS
SELECT
    f.Id,
    f.NumerFaktury,
    d.Nazwa        AS Dostawca,
    m.Kod          AS MPK,
    f.KwotaBrutto,
    f.Status,
    f.TerminPlatnosci,
    f.DataZmianyStatusu,
    DATEDIFF(DAY, f.DataZmianyStatusu, dbo.fn_Teraz()) AS DniNaKroku,
    u.ImieNazwisko AS OsobaOdpowiedzialna
FROM dbo.Faktury f
JOIN dbo.Dostawcy d ON d.Id = f.DostawcaId
JOIN dbo.MPK m      ON m.Id = f.MpkId
LEFT JOIN dbo.Uzytkownicy u ON u.Id = dbo.fn_Odpowiedzialny(f.Id)
WHERE f.Status NOT IN (N'Zaksięgowana', N'Odrzucona');
GO

-- Powiadomienie po zmianie statusu: nowe zadanie / odrzucenie / zaksięgowanie
CREATE OR ALTER PROCEDURE dbo.sp_PowiadomONowymKroku
    @FakturaId    INT,
    @UzytkownikId INT,                    -- kto wykonał krok
    @Komentarz    NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Status NVARCHAR(30), @Nr NVARCHAR(50), @Termin DATE, @Kierownik INT;
    SELECT @Status = f.Status, @Nr = f.NumerFaktury, @Termin = f.TerminPlatnosci, @Kierownik = m.KierownikId
    FROM dbo.Faktury f JOIN dbo.MPK m ON m.Id = f.MpkId
    WHERE f.Id = @FakturaId;

    DECLARE @Opis NVARCHAR(400) = dbo.fn_OpisFaktury(@FakturaId);
    DECLARE @Kto INT = dbo.fn_Odpowiedzialny(@FakturaId);
    DECLARE @Ksiegowosc INT = (SELECT TOP 1 Id FROM dbo.Uzytkownicy WHERE Rola = N'Księgowość' ORDER BY Id);
    DECLARE @Teraz DATETIME2 = dbo.fn_Teraz();

    IF @Status = N'Odrzucona'
        INSERT dbo.Powiadomienia (UzytkownikId, FakturaId, Temat, Tresc, DataUtworzenia)
        VALUES (@Ksiegowosc, @FakturaId, N'Faktura odrzucona: ' + @Nr,
                N'Faktura ' + @Opis + N' została odrzucona przez: '
                + (SELECT ImieNazwisko FROM dbo.Uzytkownicy WHERE Id = @UzytkownikId)
                + N'. Powód: „' + ISNULL(@Komentarz, N'') + N'”. Zwróć fakturę do dostawcy.', @Teraz);
    ELSE IF @Status = N'Zaksięgowana'
        INSERT dbo.Powiadomienia (UzytkownikId, FakturaId, Temat, Tresc, DataUtworzenia)
        VALUES (@Kierownik, @FakturaId, N'Faktura zaksięgowana: ' + @Nr,
                N'Faktura ' + @Opis + N' została zaksięgowana i przekazana do płatności (termin: '
                + FORMAT(@Termin, 'dd.MM.yyyy') + N').', @Teraz);
    ELSE IF @Kto IS NOT NULL
        INSERT dbo.Powiadomienia (UzytkownikId, FakturaId, Temat, Tresc, DataUtworzenia)
        VALUES (@Kto, @FakturaId, N'Nowe zadanie (' + LOWER(@Status) + N'): ' + @Nr,
                N'Faktura ' + @Opis + N' czeka na Twoją decyzję.'
                + CASE WHEN @Status = N'Akceptacja kierownika' AND @Kto <> @Kierownik
                       THEN N' Zastępujesz: ' + (SELECT ImieNazwisko FROM dbo.Uzytkownicy WHERE Id = @Kierownik) + N'.'
                       ELSE N'' END
                + N' Termin płatności: ' + FORMAT(@Termin, 'dd.MM.yyyy') + N'.', @Teraz);
END
GO

-- Przypomnienia po X dniach bez decyzji (R9) i ostrzeżenia o terminie płatności (R11).
-- Aplikacja wywołuje ją przy każdej zmianie dnia; w firmie robiłby to zaplanowany job.
CREATE OR ALTER PROCEDURE dbo.sp_SprawdzTerminy
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Teraz DATETIME2 = dbo.fn_Teraz();
    DECLARE @Dzis DATE = CAST(@Teraz AS DATE);
    DECLARE @Sla INT   = (SELECT CAST(Wartosc AS INT) FROM dbo.Ustawienia WHERE Klucz = N'DniDoPrzypomnienia');
    DECLARE @Ostrz INT = (SELECT CAST(Wartosc AS INT) FROM dbo.Ustawienia WHERE Klucz = N'DniOstrzezeniaPlatnosc');
    DECLARE @Ksiegowosc INT = (SELECT TOP 1 Id FROM dbo.Uzytkownicy WHERE Rola = N'Księgowość' ORDER BY Id);

    -- Przypomnienia: jedno na każdy krok
    DECLARE @Przyp TABLE (FakturaId INT, Kto INT, Dni INT);
    INSERT @Przyp
    SELECT f.Id, dbo.fn_Odpowiedzialny(f.Id), DATEDIFF(DAY, f.DataZmianyStatusu, @Teraz)
    FROM dbo.Faktury f
    WHERE f.Status NOT IN (N'Zaksięgowana', N'Odrzucona')
      AND DATEDIFF(DAY, f.DataZmianyStatusu, @Teraz) > @Sla
      AND (f.PrzypomnienieDla IS NULL OR f.PrzypomnienieDla <> f.DataZmianyStatusu);

    INSERT dbo.Powiadomienia (UzytkownikId, FakturaId, Temat, Tresc, DataUtworzenia)
    SELECT p.Kto, p.FakturaId,
           N'Przypomnienie: ' + f.NumerFaktury + N' czeka ' + CAST(p.Dni AS NVARCHAR(10)) + N' dni',
           N'Faktura ' + dbo.fn_OpisFaktury(f.Id) + N' czeka na Twoją decyzję od ' + CAST(p.Dni AS NVARCHAR(10))
           + N' dni (krok: ' + f.Status + N'). Prosimy o decyzję.', @Teraz
    FROM @Przyp p JOIN dbo.Faktury f ON f.Id = p.FakturaId;

    INSERT dbo.Powiadomienia (UzytkownikId, FakturaId, Temat, Tresc, DataUtworzenia)
    SELECT @Ksiegowosc, p.FakturaId,
           N'Faktura utknęła: ' + f.NumerFaktury,
           N'Faktura ' + dbo.fn_OpisFaktury(f.Id) + N' czeka u: ' + u.ImieNazwisko + N' od '
           + CAST(p.Dni AS NVARCHAR(10)) + N' dni. Wysłano przypomnienie.', @Teraz
    FROM @Przyp p
    JOIN dbo.Faktury f ON f.Id = p.FakturaId
    JOIN dbo.Uzytkownicy u ON u.Id = p.Kto
    WHERE p.Kto <> @Ksiegowosc;

    UPDATE f SET PrzypomnienieDla = f.DataZmianyStatusu
    FROM dbo.Faktury f JOIN @Przyp p ON p.FakturaId = f.Id;

    -- Ostrzeżenia o terminie płatności: jedno na fakturę
    DECLARE @Plat TABLE (FakturaId INT, Dni INT);
    INSERT @Plat
    SELECT Id, DATEDIFF(DAY, @Dzis, TerminPlatnosci)
    FROM dbo.Faktury
    WHERE Status NOT IN (N'Zaksięgowana', N'Odrzucona')
      AND OstrzezenieWyslane = 0
      AND DATEDIFF(DAY, @Dzis, TerminPlatnosci) <= @Ostrz;

    INSERT dbo.Powiadomienia (UzytkownikId, FakturaId, Temat, Tresc, DataUtworzenia)
    SELECT @Ksiegowosc, p.FakturaId,
           CASE WHEN p.Dni < 0 THEN N'Minął termin płatności: ' ELSE N'Zbliża się termin płatności: ' END + f.NumerFaktury,
           N'Faktura ' + dbo.fn_OpisFaktury(f.Id) + N' ma termin płatności ' + FORMAT(f.TerminPlatnosci, 'dd.MM.yyyy')
           + N', a jest wciąż na etapie „' + f.Status + N'” (u: ' + ISNULL(u.ImieNazwisko, N'—') + N').', @Teraz
    FROM @Plat p
    JOIN dbo.Faktury f ON f.Id = p.FakturaId
    LEFT JOIN dbo.Uzytkownicy u ON u.Id = dbo.fn_Odpowiedzialny(f.Id);

    UPDATE f SET OstrzezenieWyslane = 1
    FROM dbo.Faktury f JOIN @Plat p ON p.FakturaId = f.Id;
END
GO

-- Rejestracja faktury przez księgowość (R1, R3, R11)
CREATE OR ALTER PROCEDURE dbo.sp_Rejestruj
    @UzytkownikId    INT,
    @NumerFaktury    NVARCHAR(50),
    @DostawcaId      INT,
    @MpkId           INT,
    @DataWystawienia DATE,
    @TerminPlatnosci DATE,
    @KwotaNetto      DECIMAL(12,2),
    @KwotaVAT        DECIMAL(12,2),
    @Opis            NVARCHAR(500)  = NULL,
    @Zalacznik       NVARCHAR(260)  = NULL,
    @PlikPdf         VARBINARY(MAX) = NULL,
    @DoWyjasnienia   BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @NumerFaktury = LTRIM(RTRIM(@NumerFaktury));

    IF ISNULL(@NumerFaktury, N'') = N'' OR @DostawcaId IS NULL OR @MpkId IS NULL OR @DataWystawienia IS NULL
       OR @TerminPlatnosci IS NULL OR @KwotaNetto IS NULL OR @KwotaVAT IS NULL
        THROW 50010, N'Uzupełnij wszystkie wymagane pola.', 1;
    IF @PlikPdf IS NULL
        THROW 50011, N'Dodaj plik PDF faktury – bez załącznika nie da się jej sprawdzić.', 1;
    IF @KwotaNetto <= 0
        THROW 50012, N'Kwota netto musi być większa od zera.', 1;
    IF @KwotaVAT < 0
        THROW 50013, N'VAT nie może być ujemny.', 1;
    IF @TerminPlatnosci < @DataWystawienia
        THROW 50014, N'Termin płatności nie może być wcześniejszy niż data wystawienia.', 1;

    DECLARE @Duplikat NVARCHAR(30) = (SELECT Status FROM dbo.Faktury WHERE DostawcaId = @DostawcaId AND NumerFaktury = @NumerFaktury);
    IF @Duplikat IS NOT NULL
    BEGIN
        DECLARE @Komunikat NVARCHAR(300) = N'Duplikat! Faktura ' + @NumerFaktury
            + N' od tego dostawcy jest już w systemie (status: ' + @Duplikat + N').';
        THROW 50015, @Komunikat, 1;
    END

    DECLARE @Teraz DATETIME2 = dbo.fn_Teraz();
    DECLARE @Status NVARCHAR(30) = CASE WHEN @DoWyjasnienia = 1 THEN N'Do wyjaśnienia' ELSE N'Akceptacja kierownika' END;
    DECLARE @Id INT;

    BEGIN TRANSACTION;
        INSERT dbo.Faktury (NumerFaktury, DostawcaId, MpkId, DataWystawienia, TerminPlatnosci, KwotaNetto, KwotaVAT,
                            Opis, Zalacznik, PlikPdf, Status, DataRejestracji, DataZmianyStatusu)
        VALUES (@NumerFaktury, @DostawcaId, @MpkId, @DataWystawienia, @TerminPlatnosci, @KwotaNetto, @KwotaVAT,
                NULLIF(@Opis, N''), @Zalacznik, @PlikPdf, @Status, @Teraz, @Teraz);
        SET @Id = SCOPE_IDENTITY();

        INSERT dbo.HistoriaObiegu (FakturaId, Krok, UzytkownikId, Decyzja, Komentarz, DataDecyzji)
        VALUES (@Id, N'Rejestracja', @UzytkownikId,
                CASE WHEN @DoWyjasnienia = 1 THEN N'Do wyjaśnienia' ELSE N'Zarejestrowana' END,
                CASE WHEN @DoWyjasnienia = 1 THEN NULLIF(@Opis, N'') END, @Teraz);

        IF @DoWyjasnienia = 0
            EXEC dbo.sp_PowiadomONowymKroku @FakturaId = @Id, @UzytkownikId = @UzytkownikId;
    COMMIT;

    EXEC dbo.sp_SprawdzTerminy;
    SELECT @Id AS Id, @Status AS Status, dbo.fn_Odpowiedzialny(@Id) AS OdpowiedzialnyId;
END
GO

-- Decyzja kierownika lub dyrektora (R6, R7, R8, R10)
CREATE OR ALTER PROCEDURE dbo.sp_Decyzja
    @FakturaId    INT,
    @UzytkownikId INT,
    @Decyzja      NVARCHAR(20),          -- N'Zaakceptowana' albo N'Odrzucona'
    @Komentarz    NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @Komentarz = NULLIF(LTRIM(RTRIM(@Komentarz)), N'');

    DECLARE @Status NVARCHAR(30), @Brutto DECIMAL(12,2);
    SELECT @Status = Status, @Brutto = KwotaBrutto FROM dbo.Faktury WHERE Id = @FakturaId;

    IF @Status IS NULL
        THROW 50001, N'Nie ma faktury o takim Id.', 1;
    IF @Decyzja NOT IN (N'Zaakceptowana', N'Odrzucona')
        THROW 50002, N'Decyzja musi mieć wartość Zaakceptowana albo Odrzucona.', 1;
    IF @Status NOT IN (N'Akceptacja kierownika', N'Akceptacja dyrektora')
        THROW 50004, N'Ta faktura nie czeka teraz na akceptację.', 1;
    IF @UzytkownikId <> ISNULL(dbo.fn_Odpowiedzialny(@FakturaId), -1)
        THROW 50005, N'To zadanie nie jest przypisane do Ciebie.', 1;                       -- R8
    IF @Decyzja = N'Odrzucona' AND @Komentarz IS NULL
        THROW 50003, N'Odrzucenie wymaga podania powodu w komentarzu.', 1;                   -- R7

    -- Próg nie jest wpisany na sztywno – administrator zmienia go w tabeli Ustawienia (R6, R13)
    DECLARE @Prog DECIMAL(12,2) = (SELECT Wartosc FROM dbo.Ustawienia WHERE Klucz = N'ProgDyrektora');
    DECLARE @NowyStatus NVARCHAR(30) =
        CASE
            WHEN @Decyzja = N'Odrzucona'                                 THEN N'Odrzucona'
            WHEN @Status = N'Akceptacja kierownika' AND @Brutto > @Prog THEN N'Akceptacja dyrektora'
            ELSE N'Do zaksięgowania'
        END;
    DECLARE @Teraz DATETIME2 = dbo.fn_Teraz();

    BEGIN TRANSACTION;
        INSERT dbo.HistoriaObiegu (FakturaId, Krok, UzytkownikId, Decyzja, Komentarz, DataDecyzji)    -- R10
        VALUES (@FakturaId, @Status, @UzytkownikId, @Decyzja, @Komentarz, @Teraz);

        UPDATE dbo.Faktury
        SET Status            = @NowyStatus,
            DataZmianyStatusu = @Teraz,
            DataZakonczenia   = CASE WHEN @NowyStatus = N'Odrzucona' THEN @Teraz END
        WHERE Id = @FakturaId;

        EXEC dbo.sp_PowiadomONowymKroku @FakturaId = @FakturaId, @UzytkownikId = @UzytkownikId, @Komentarz = @Komentarz;
    COMMIT;

    SELECT @FakturaId AS FakturaId, @Status AS PoprzedniStatus, @NowyStatus AS NowyStatus;
END
GO

-- Kroki księgowości: uzupełnienie braków i zaksięgowanie
CREATE OR ALTER PROCEDURE dbo.sp_KrokKsiegowosci
    @FakturaId    INT,
    @UzytkownikId INT,
    @Komentarz    NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @Komentarz = NULLIF(LTRIM(RTRIM(@Komentarz)), N'');

    DECLARE @Status NVARCHAR(30) = (SELECT Status FROM dbo.Faktury WHERE Id = @FakturaId);
    IF @Status NOT IN (N'Do wyjaśnienia', N'Do zaksięgowania') OR @Status IS NULL
        THROW 50006, N'Ta faktura nie czeka na księgowość.', 1;
    IF @UzytkownikId <> ISNULL(dbo.fn_Odpowiedzialny(@FakturaId), -1)
        THROW 50005, N'To zadanie nie jest przypisane do Ciebie.', 1;

    DECLARE @NowyStatus NVARCHAR(30) = CASE WHEN @Status = N'Do wyjaśnienia' THEN N'Akceptacja kierownika' ELSE N'Zaksięgowana' END;
    DECLARE @Teraz DATETIME2 = dbo.fn_Teraz();

    BEGIN TRANSACTION;
        INSERT dbo.HistoriaObiegu (FakturaId, Krok, UzytkownikId, Decyzja, Komentarz, DataDecyzji)
        VALUES (@FakturaId, @Status, @UzytkownikId,
                CASE WHEN @Status = N'Do wyjaśnienia' THEN N'Uzupełniona' ELSE N'Zaksięgowana' END, @Komentarz, @Teraz);

        UPDATE dbo.Faktury
        SET Status            = @NowyStatus,
            DataZmianyStatusu = @Teraz,
            DataZakonczenia   = CASE WHEN @NowyStatus = N'Zaksięgowana' THEN @Teraz END
        WHERE Id = @FakturaId;

        EXEC dbo.sp_PowiadomONowymKroku @FakturaId = @FakturaId, @UzytkownikId = @UzytkownikId, @Komentarz = @Komentarz;
    COMMIT;

    SELECT @FakturaId AS FakturaId, @Status AS PoprzedniStatus, @NowyStatus AS NowyStatus;
END
GO

/* =====================================================================
   3. DANE TESTOWE (firmy i osoby są fikcyjne)
   ===================================================================== */

INSERT dbo.Uzytkownicy (ImieNazwisko, Email, Rola) VALUES
 (N'Anna Nowak',          N'anna.nowak@firma.test',          N'Księgowość'),  -- 1
 (N'Piotr Wiśniewski',    N'piotr.wisniewski@firma.test',    N'Kierownik'),   -- 2
 (N'Katarzyna Zielińska', N'katarzyna.zielinska@firma.test', N'Kierownik'),   -- 3
 (N'Tomasz Lewandowski',  N'tomasz.lewandowski@firma.test',  N'Kierownik'),   -- 4
 (N'Marek Kamiński',      N'marek.kaminski@firma.test',      N'Dyrektor'),    -- 5
 (N'Ewa Dąbrowska',       N'ewa.dabrowska@firma.test',       N'Kierownik');   -- 6

INSERT dbo.MPK (Kod, Nazwa, KierownikId) VALUES
 (N'IT-01',  N'Dział IT',  2),
 (N'MAG-01', N'Magazyn',   3),
 (N'MKT-01', N'Marketing', 4);

-- Katarzyna (Magazyn) jest na urlopie – zastępuje ją Ewa
INSERT dbo.Zastepstwa (UzytkownikId, ZastepcaId, DataOd, DataDo) VALUES
 (3, 6, DATEADD(DAY, -2, CAST(SYSDATETIME() AS DATE)), DATEADD(DAY, 5, CAST(SYSDATETIME() AS DATE)));

-- NIP-y fikcyjne, ale z poprawną sumą kontrolną
INSERT dbo.Dostawcy (Nazwa, NIP) VALUES
 (N'TechSerwis Sp. z o.o.',        '9990000008'),
 (N'Trans-Logistyka S.A.',         '9990000014'),
 (N'Agencja Reklamowa Pomysł',     '9990000020'),
 (N'Hurtownia Opakowań Karton',    '9990000037');

INSERT dbo.Ustawienia (Klucz, Wartosc, Opis) VALUES
 (N'ProgDyrektora',       5000, N'Kwota brutto, powyżej której fakturę zatwierdza też dyrektor finansowy'),
 (N'DniDoPrzypomnienia',     3, N'Po ilu dniach bez decyzji wysłać przypomnienie'),
 (N'DniOstrzezeniaPlatnosc', 3, N'Ile dni przed terminem płatności ostrzec księgowość'),
 (N'PrzesuniecieDni',        0, N'Tylko demo: o ile dni przesunięto czas przyciskiem „+1 dzień”');

-- Daty liczone względem dzisiejszego dnia, żeby raporty zawsze pokazywały sensowne wyniki
DECLARE @T DATETIME2 = SYSDATETIME();

INSERT dbo.Faktury (NumerFaktury, DostawcaId, MpkId, DataWystawienia, TerminPlatnosci, KwotaNetto, KwotaVAT,
                    Opis, Status, DataRejestracji, DataZmianyStatusu, DataZakonczenia) VALUES
 (N'FV/2026/001', 1, 1, DATEADD(DAY,-22,@T), DATEADD(DAY, -8,@T),  3200.00,  736.00, N'Serwis serwerów',          N'Zaksięgowana',          DATEADD(DAY,-20,@T), DATEADD(DAY,-15,@T), DATEADD(DAY,-15,@T)),
 (N'118/2026',    2, 2, DATEADD(DAY,-19,@T), DATEADD(DAY, -5,@T), 12500.00, 2875.00, N'Transport palet – wrzesień',N'Zaksięgowana',         DATEADD(DAY,-18,@T), DATEADD(DAY,-10,@T), DATEADD(DAY,-10,@T)),
 (N'F/0456/2026', 3, 3, DATEADD(DAY,-13,@T), DATEADD(DAY,  1,@T),   800.00,  184.00, N'Ulotki',                    N'Odrzucona',             DATEADD(DAY,-12,@T), DATEADD(DAY,-11,@T), DATEADD(DAY,-11,@T)),
 (N'FV/2026/014', 1, 1, DATEADD(DAY, -4,@T), DATEADD(DAY, 10,@T),  4100.00,  943.00, N'Licencje oprogramowania',   N'Akceptacja dyrektora',  DATEADD(DAY, -3,@T), DATEADD(DAY, -1,@T), NULL),
 (N'131/2026',    2, 2, DATEADD(DAY, -6,@T), DATEADD(DAY,  8,@T),  2300.00,  529.00, N'Transport – dostawa pilna', N'Akceptacja kierownika', DATEADD(DAY, -5,@T), DATEADD(DAY, -5,@T), NULL),
 (N'MAG/77/2026', 4, 3, DATEADD(DAY, -5,@T), DATEADD(DAY,  9,@T),  6000.00, 1380.00, N'Materiały targowe',         N'Akceptacja kierownika', DATEADD(DAY, -4,@T), DATEADD(DAY, -4,@T), NULL),
 (N'F/0502/2026', 3, 1, DATEADD(DAY, -2,@T), DATEADD(DAY, 12,@T),   450.00,  103.50, N'Szkolenie online',          N'Akceptacja kierownika', DATEADD(DAY, -1,@T), DATEADD(DAY, -1,@T), NULL),
 (N'MAG/80/2026', 4, 2, DATEADD(DAY, -4,@T), DATEADD(DAY,  2,@T),  1500.00,  345.00, N'Kartony 60x40',             N'Do zaksięgowania',      DATEADD(DAY, -3,@T), DATEADD(DAY, -2,@T), NULL),
 (N'FV/2026/019', 1, 3, DATEADD(DAY, -4,@T), DATEADD(DAY, 10,@T),  2000.00,  460.00, N'Wsparcie strony www',       N'Do wyjaśnienia',        DATEADD(DAY, -3,@T), DATEADD(DAY, -3,@T), NULL),
 (N'097/2026',    2, 1, DATEADD(DAY,-31,@T), DATEADD(DAY,-17,@T),  9800.00, 2254.00, N'Przeprowadzka serwerowni', N'Zaksięgowana',          DATEADD(DAY,-30,@T), DATEADD(DAY,-21,@T), DATEADD(DAY,-21,@T));

INSERT dbo.HistoriaObiegu (FakturaId, Krok, UzytkownikId, Decyzja, Komentarz, DataDecyzji) VALUES
 (1,  N'Rejestracja',           1, N'Zarejestrowana', NULL,                                         DATEADD(DAY,-20,@T)),
 (1,  N'Akceptacja kierownika', 2, N'Zaakceptowana',  NULL,                                         DATEADD(DAY,-17,@T)),
 (1,  N'Do zaksięgowania',      1, N'Zaksięgowana',   NULL,                                         DATEADD(DAY,-15,@T)),
 (2,  N'Rejestracja',           1, N'Zarejestrowana', NULL,                                         DATEADD(DAY,-18,@T)),
 (2,  N'Akceptacja kierownika', 3, N'Zaakceptowana',  NULL,                                         DATEADD(DAY,-16,@T)),
 (2,  N'Akceptacja dyrektora',  5, N'Zaakceptowana',  N'OK, zgodnie z umową ramową',                DATEADD(DAY,-12,@T)),
 (2,  N'Do zaksięgowania',      1, N'Zaksięgowana',   NULL,                                         DATEADD(DAY,-10,@T)),
 (3,  N'Rejestracja',           1, N'Zarejestrowana', NULL,                                         DATEADD(DAY,-12,@T)),
 (3,  N'Akceptacja kierownika', 4, N'Odrzucona',      N'Dział marketingu nie zamawiał tych ulotek', DATEADD(DAY,-11,@T)),
 (4,  N'Rejestracja',           1, N'Zarejestrowana', NULL,                                         DATEADD(DAY, -3,@T)),
 (4,  N'Akceptacja kierownika', 2, N'Zaakceptowana',  NULL,                                         DATEADD(DAY, -1,@T)),
 (5,  N'Rejestracja',           1, N'Zarejestrowana', NULL,                                         DATEADD(DAY, -5,@T)),
 (6,  N'Rejestracja',           1, N'Zarejestrowana', NULL,                                         DATEADD(DAY, -4,@T)),
 (7,  N'Rejestracja',           1, N'Zarejestrowana', NULL,                                         DATEADD(DAY, -1,@T)),
 (8,  N'Rejestracja',           1, N'Zarejestrowana', NULL,                                         DATEADD(DAY, -3,@T)),
 (8,  N'Akceptacja kierownika', 3, N'Zaakceptowana',  NULL,                                         DATEADD(DAY, -2,@T)),
 (9,  N'Rejestracja',           1, N'Do wyjaśnienia', N'Brak numeru zamówienia na fakturze',        DATEADD(DAY, -3,@T)),
 (10, N'Rejestracja',           1, N'Zarejestrowana', NULL,                                         DATEADD(DAY,-30,@T)),
 (10, N'Akceptacja kierownika', 2, N'Zaakceptowana',  NULL,                                         DATEADD(DAY,-27,@T)),
 (10, N'Akceptacja dyrektora',  5, N'Zaakceptowana',  NULL,                                         DATEADD(DAY,-23,@T)),
 (10, N'Do zaksięgowania',      1, N'Zaksięgowana',   NULL,                                         DATEADD(DAY,-21,@T));

-- Pierwsze przypomnienia i ostrzeżenia dla danych startowych
EXEC dbo.sp_SprawdzTerminy;
GO

/* =====================================================================
   4. RAPORTY
   ===================================================================== */

-- R-1. Faktury, które utknęły: czekają na decyzję dłużej niż ustawiona liczba dni (R9)
SELECT NumerFaktury, Dostawca, MPK, KwotaBrutto, Status, DniNaKroku, OsobaOdpowiedzialna
FROM dbo.v_FakturyWObiegu
WHERE DniNaKroku > (SELECT Wartosc FROM dbo.Ustawienia WHERE Klucz = N'DniDoPrzypomnienia')
ORDER BY DniNaKroku DESC;

-- R-2. Faktury w obiegu, którym zbliża się (lub minął) termin płatności (R11)
SELECT NumerFaktury, Dostawca, KwotaBrutto, Status, TerminPlatnosci,
       DATEDIFF(DAY, CAST(dbo.fn_Teraz() AS DATE), TerminPlatnosci) AS DniDoTerminu, OsobaOdpowiedzialna
FROM dbo.v_FakturyWObiegu
WHERE DATEDIFF(DAY, CAST(dbo.fn_Teraz() AS DATE), TerminPlatnosci)
      <= (SELECT Wartosc FROM dbo.Ustawienia WHERE Klucz = N'DniOstrzezeniaPlatnosc')
ORDER BY DniDoTerminu;

-- R-3. Średni czas obiegu (od rejestracji do zaksięgowania) wg działu
SELECT m.Nazwa AS Dzial,
       COUNT(*) AS LiczbaFaktur,
       AVG(CAST(DATEDIFF(HOUR, f.DataRejestracji, f.DataZakonczenia) AS DECIMAL(10,2)) / 24) AS SredniCzasDni
FROM dbo.Faktury f
JOIN dbo.MPK m ON m.Id = f.MpkId
WHERE f.Status = N'Zaksięgowana'
GROUP BY m.Nazwa
ORDER BY SredniCzasDni DESC;

-- R-4. Wartość faktur wg działu i statusu
SELECT m.Nazwa AS Dzial, f.Status, COUNT(*) AS Liczba, SUM(f.KwotaBrutto) AS SumaBrutto
FROM dbo.Faktury f
JOIN dbo.MPK m ON m.Id = f.MpkId
GROUP BY m.Nazwa, f.Status
ORDER BY m.Nazwa, f.Status;

-- R-5. Odsetek faktur odrzuconych (spośród zakończonych)
SELECT
    SUM(CASE WHEN Status = N'Odrzucona' THEN 1 ELSE 0 END) AS Odrzucone,
    COUNT(*) AS Zakonczone,
    CAST(100.0 * SUM(CASE WHEN Status = N'Odrzucona' THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,1)) AS ProcentOdrzuconych
FROM dbo.Faktury
WHERE Status IN (N'Zaksięgowana', N'Odrzucona');

-- R-6. Ostatnie powiadomienia (to, co system „wysłał” mailem)
SELECT TOP 10 p.DataUtworzenia, u.ImieNazwisko AS Do, p.Temat
FROM dbo.Powiadomienia p JOIN dbo.Uzytkownicy u ON u.Id = p.UzytkownikId
ORDER BY p.Id DESC;
GO

/* =====================================================================
   5. TESTY REGUŁ – zaznacz jeden blok i uruchom go osobno (F5).
   Błąd w wyniku oznacza, że reguła działa: baza nie przepuściła złych danych.
   ===================================================================== */

/*
-- T-1: duplikat (R3)
EXEC dbo.sp_Rejestruj @UzytkownikId = 1, @NumerFaktury = N'FV/2026/001', @DostawcaId = 1, @MpkId = 1,
     @DataWystawienia = '2026-10-01', @TerminPlatnosci = '2026-10-15', @KwotaNetto = 100, @KwotaVAT = 23, @PlikPdf = 0x00;

-- T-2: zła osoba (R8) – Piotr próbuje zatwierdzić fakturę Magazynu → błąd 50005
EXEC dbo.sp_Decyzja @FakturaId = 5, @UzytkownikId = 2, @Decyzja = N'Zaakceptowana';

-- T-3: zastępstwo (R5) – Ewa zastępuje Katarzynę, więc może zatwierdzić fakturę Magazynu
EXEC dbo.sp_Decyzja @FakturaId = 5, @UzytkownikId = 6, @Decyzja = N'Zaakceptowana';

-- T-4: odrzucenie bez komentarza (R7) → błąd 50003
EXEC dbo.sp_Decyzja @FakturaId = 7, @UzytkownikId = 2, @Decyzja = N'Odrzucona';

-- T-5: próg kwotowy (R6) – 7 380 zł brutto, po akceptacji kierownika trafia do dyrektora
EXEC dbo.sp_Decyzja @FakturaId = 6, @UzytkownikId = 4, @Decyzja = N'Zaakceptowana';

-- T-6: zmiana progu bez programowania – po tej zmianie faktura 7 380 zł pójdzie od razu do księgowania
UPDATE dbo.Ustawienia SET Wartosc = 10000 WHERE Klucz = N'ProgDyrektora';

-- T-7: niepoprawny NIP (R12) → błąd ograniczenia CK_Dostawcy_NIP
INSERT dbo.Dostawcy (Nazwa, NIP) VALUES (N'Test', '1234567890');

-- T-8: powiadomienia utworzone przez procedury
SELECT p.DataUtworzenia, u.ImieNazwisko AS Do, p.Temat, p.Tresc
FROM dbo.Powiadomienia p JOIN dbo.Uzytkownicy u ON u.Id = p.UzytkownikId
ORDER BY p.Id DESC;
*/
