// Serwer łączący demo obiegu faktur (04_demo) z bazą ObiegFaktur w SQL Server.
// Uruchomienie: npm install, potem npm start, i w przeglądarce http://localhost:3000
//
// Serwer jest celowo „cienki”: reguły procesu (duplikaty, próg, zastępstwa, uprawnienia,
// powiadomienia) wykonują procedury składowane w bazie. Serwer tylko przekazuje dane.

const http = require('http');
const fs = require('fs');
const path = require('path');
const sql = require('msnodesqlv8');

// Polskie znaki w konsoli Windows
if (process.platform === 'win32') { try { require('child_process').execSync('chcp 65001', { stdio: 'ignore' }); } catch (e) {} }

const PORT = Number(process.env.PORT) || 3000;
const SERWER_SQL = process.env.SERWER_SQL || 'localhost\\SQLEXPRESS';
const BAZA = 'ObiegFaktur';
const conn = baza => `Driver={ODBC Driver 18 for SQL Server};Server=${SERWER_SQL};Database=${baza};` +
  'Trusted_Connection=yes;TrustServerCertificate=yes;';
const KATALOG_DEMO = path.join(__dirname, '..', '04_demo');
const SKRYPT_BAZY = path.join(__dirname, '..', '03_baza_danych.sql');

/* ------------------------------------------------------------------ */
/* Połączenie z bazą                                                   */
/* ------------------------------------------------------------------ */
let polaczenie = null;

function otworz(baza) {
  return new Promise((res, rej) => sql.open(conn(baza), (err, c) => (err ? rej(err) : res(c))));
}
async function polacz() {
  if (!polaczenie) polaczenie = await otworz(BAZA);
  return polaczenie;
}
function zamknij(c) {
  return new Promise(res => c.close(() => res()));
}

// Wykonuje zapytanie i zwraca wiersze ostatniego niepustego wyniku
function zapytanie(c, tekst, parametry = []) {
  return new Promise((res, rej) => {
    let ostatnie = [];
    let koniec = false;
    c.query(tekst, parametry, (err, wiersze, wiecej) => {
      if (koniec) return;
      if (err) { koniec = true; return rej(err); }
      if (wiersze && wiersze.length) ostatnie = wiersze;
      if (!wiecej) { koniec = true; res(ostatnie); }
    });
  });
}
async function q(tekst, parametry) {
  try {
    return await zapytanie(await polacz(), tekst, parametry);
  } catch (e) {
    if (/connection|link failure|communication/i.test(e.message)) polaczenie = null;   // spróbuj ponownie przy następnym żądaniu
    throw e;
  }
}

// Komunikat błędu z SQL Servera bez przedrostków sterownika ODBC
function komunikat(e) {
  const m = String(e && e.message || e).replace(/^(\s*\[[^\]]*\])+\s*/, '').trim();
  if (/UQ_Faktury_Duplikat/.test(m)) return 'Duplikat! Taka faktura od tego dostawcy jest już w systemie.';
  if (/CK_Dostawcy_NIP/.test(m)) return 'Niepoprawny NIP – musi mieć 10 cyfr i poprawną sumę kontrolną.';
  if (/CK_Zastepstwa_Osoba/.test(m)) return 'Osoba nie może zastępować samej siebie.';
  if (/CK_Zastepstwa_Daty/.test(m)) return 'Podaj poprawny zakres dat (Do ≥ Od).';
  return m;
}

/* ------------------------------------------------------------------ */
/* Stan aplikacji w formacie, którego używa demo                       */
/* (daty jako numery dni względem dzisiejszego dnia)                    */
/* ------------------------------------------------------------------ */
const DZIEN = kol => `DATEDIFF(DAY, CAST(SYSDATETIME() AS DATE), ${kol})`;

function dzisISO() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

async function stan() {
  const ust = await q(`SELECT Klucz, CAST(Wartosc AS FLOAT) AS Wartosc FROM dbo.Ustawienia`);
  const u = Object.fromEntries(ust.map(r => [r.Klucz, r.Wartosc]));
  const [dostawcy, mpk, zastepstwa, faktury, hist, maile] = [
    await q(`SELECT Id AS id, Nazwa AS nazwa, NIP AS nip FROM dbo.Dostawcy ORDER BY Id`),
    await q(`SELECT Id AS id, Kod AS kod, Nazwa AS nazwa, KierownikId AS kier FROM dbo.MPK ORDER BY Id`),
    await q(`SELECT Id AS id, UzytkownikId AS kto, ZastepcaId AS zastepca, ${DZIEN('DataOd')} AS od, ${DZIEN('DataDo')} AS do
             FROM dbo.Zastepstwa ORDER BY DataOd`),
    await q(`SELECT Id AS id, NumerFaktury AS nr, DostawcaId AS dost, MpkId AS mpk,
                    ${DZIEN('DataWystawienia')} AS wyst, ${DZIEN('TerminPlatnosci')} AS termin,
                    CAST(KwotaNetto AS FLOAT) AS netto, CAST(KwotaVAT AS FLOAT) AS vat, ISNULL(Opis, N'') AS opis, Status AS status,
                    ${DZIEN('DataRejestracji')} AS rej, ${DZIEN('DataZmianyStatusu')} AS zmiana, ${DZIEN('DataZakonczenia')} AS koniec,
                    CASE WHEN PlikPdf IS NOT NULL THEN ISNULL(Zalacznik, N'faktura.pdf') END AS zal
             FROM dbo.Faktury ORDER BY Id`),
    await q(`SELECT FakturaId AS f, ${DZIEN('DataDecyzji')} AS dzien, Krok AS krok, UzytkownikId AS uid,
                    Decyzja AS decyzja, ISNULL(Komentarz, N'') AS kom
             FROM dbo.HistoriaObiegu ORDER BY Id`),
    await q(`SELECT Id AS id, ${DZIEN('DataUtworzenia')} AS dzien, UzytkownikId AS do, Temat AS temat, Tresc AS tresc
             FROM dbo.Powiadomienia ORDER BY Id`),
  ];
  for (const f of faktury) f.hist = hist.filter(h => h.f === f.id).map(({ f, ...h }) => h);
  return {
    zrodlo: { serwer: SERWER_SQL, baza: BAZA },
    start: dzisISO(),
    dzien: u.PrzesuniecieDni || 0,
    cfg: { prog: u.ProgDyrektora, sla: u.DniDoPrzypomnienia, ostrz: u.DniOstrzezeniaPlatnosc },
    dostawcy, mpk, zastepstwa, faktury, maile,
  };
}

// Gdy zmiana (zastępstwo, kierownik, nowy dzień) przenosi zadania na inną osobę – powiadom ją
const ODPOWIEDZIALNI = `SELECT Id, dbo.fn_Odpowiedzialny(Id) AS Kto FROM dbo.Faktury
                        WHERE Status NOT IN (N'Zaksięgowana', N'Odrzucona')`;
async function zPrzekazaniem(zmiana) {
  const przed = new Map((await q(ODPOWIEDZIALNI)).map(r => [r.Id, r.Kto]));
  await zmiana();
  for (const r of await q(ODPOWIEDZIALNI)) {
    if (!przed.has(r.Id) || przed.get(r.Id) === r.Kto || r.Kto == null) continue;
    await q(`INSERT dbo.Powiadomienia (UzytkownikId, FakturaId, Temat, Tresc, DataUtworzenia)
             SELECT ?, f.Id, N'Przekazano Ci zadanie: ' + f.NumerFaktury,
                    N'Faktura ' + dbo.fn_OpisFaktury(f.Id) + N' (krok: ' + f.Status + N') przeszła do Ciebie od: '
                    + (SELECT ImieNazwisko FROM dbo.Uzytkownicy WHERE Id = ?) + N' – zmiana zastępstw lub kierownika działu.',
                    dbo.fn_Teraz()
             FROM dbo.Faktury f WHERE f.Id = ?`, [r.Kto, przed.get(r.Id), r.Id]);
  }
}

const isoNaDate = s => (/^\d{4}-\d{2}-\d{2}$/.test(String(s)) ? s : null);
const nipOk = n => /^\d{10}$/.test(n) &&
  [6, 5, 7, 2, 3, 4, 5, 6, 7].reduce((a, w, i) => a + w * +n[i], 0) % 11 === +n[9];

/* ------------------------------------------------------------------ */
/* API                                                                 */
/* ------------------------------------------------------------------ */
const trasy = [
  ['GET', /^\/api\/stan$/, async () => stan()],

  ['GET', /^\/api\/faktury\/(\d+)\/pdf$/, async (m, _b, res) => {
    const [r] = await q(`SELECT PlikPdf, Zalacznik FROM dbo.Faktury WHERE Id = ?`, [+m[1]]);
    if (!r || !r.PlikPdf) throw Object.assign(new Error('Brak pliku PDF.'), { kod: 404 });
    res.writeHead(200, { 'Content-Type': 'application/pdf',
      'Content-Disposition': `inline; filename="${encodeURIComponent(r.Zalacznik || 'faktura.pdf')}"` });
    res.end(r.PlikPdf);
    return undefined;
  }],

  ['POST', /^\/api\/faktury$/, async (_m, b) => {
    const pdf = b.pdf ? Buffer.from(b.pdf, 'base64') : null;
    const [r] = await q(`EXEC dbo.sp_Rejestruj @UzytkownikId = ?, @NumerFaktury = ?, @DostawcaId = ?, @MpkId = ?,
        @DataWystawienia = ?, @TerminPlatnosci = ?, @KwotaNetto = ?, @KwotaVAT = ?, @Opis = ?, @Zalacznik = ?,
        @PlikPdf = ?, @DoWyjasnienia = ?`,
      [b.uid, b.nr || '', b.dost || null, b.mpk || null, isoNaDate(b.wyst), isoNaDate(b.termin),
       b.netto, b.vat, b.opis || '', b.zal || null, pdf ? sql.VarBinary(pdf) : null, b.braki ? 1 : 0]);
    return r;
  }],

  ['POST', /^\/api\/faktury\/(\d+)\/krok$/, async (m, b) => {
    const id = +m[1];
    const [f] = await q(`SELECT Status FROM dbo.Faktury WHERE Id = ?`, [id]);
    if (!f) throw new Error('Nie ma takiej faktury.');
    if (f.Status === 'Akceptacja kierownika' || f.Status === 'Akceptacja dyrektora') {
      const [r] = await q(`EXEC dbo.sp_Decyzja @FakturaId = ?, @UzytkownikId = ?, @Decyzja = ?, @Komentarz = ?`,
        [id, b.uid, b.akceptuj ? 'Zaakceptowana' : 'Odrzucona', b.kom || '']);
      return r;
    }
    const [r] = await q(`EXEC dbo.sp_KrokKsiegowosci @FakturaId = ?, @UzytkownikId = ?, @Komentarz = ?`, [id, b.uid, b.kom || '']);
    return r;
  }],

  ['POST', /^\/api\/dzien$/, async () => {
    await zPrzekazaniem(() => q(`UPDATE dbo.Ustawienia SET Wartosc = Wartosc + 1 WHERE Klucz = N'PrzesuniecieDni'`));
    await q(`EXEC dbo.sp_SprawdzTerminy`);
    return { ok: true };
  }],

  ['POST', /^\/api\/reset$/, async () => {
    // Uruchamia od nowa cały skrypt 03_baza_danych.sql (tworzy bazę i dane testowe)
    if (polaczenie) { await zamknij(polaczenie); polaczenie = null; }
    const master = await otworz('master');
    try {
      const partie = fs.readFileSync(SKRYPT_BAZY, 'utf8').replace(/^﻿/, '').split(/^\s*GO\s*$/im).filter(p => p.trim());
      for (const p of partie) await zapytanie(master, p);
    } finally { await zamknij(master); }
    return { ok: true };
  }],

  ['POST', /^\/api\/ustawienia$/, async (_m, b) => {
    const prog = Number(b.prog), sla = parseInt(b.sla, 10), ostrz = parseInt(b.ostrz, 10);
    if (!(prog > 0) || !(sla >= 1) || !(ostrz >= 0))
      throw new Error('Podaj poprawne wartości: próg > 0, przypomnienie ≥ 1 dzień, ostrzeżenie ≥ 0 dni.');
    await q(`UPDATE dbo.Ustawienia SET Wartosc = CASE Klucz WHEN N'ProgDyrektora' THEN ? WHEN N'DniDoPrzypomnienia' THEN ?
             WHEN N'DniOstrzezeniaPlatnosc' THEN ? ELSE Wartosc END`, [prog, sla, ostrz]);
    await q(`EXEC dbo.sp_SprawdzTerminy`);
    return { ok: true };
  }],

  ['POST', /^\/api\/mpk\/(\d+)$/, async (m, b) => {
    await zPrzekazaniem(() => q(`UPDATE dbo.MPK SET KierownikId = ? WHERE Id = ?`, [b.kier, +m[1]]));
    return { ok: true };
  }],

  ['POST', /^\/api\/zastepstwa$/, async (_m, b) => {
    const od = isoNaDate(b.od), dO = isoNaDate(b.do);
    if (!od || !dO) throw new Error('Podaj poprawny zakres dat (Do ≥ Od).');
    const [kolizja] = await q(`SELECT TOP 1 1 AS x FROM dbo.Zastepstwa WHERE UzytkownikId = ? AND ? <= DataDo AND ? >= DataOd`, [b.kto, od, dO]);
    if (kolizja) throw new Error('Ta osoba ma już zastępstwo w tym okresie.');
    await zPrzekazaniem(() => q(`INSERT dbo.Zastepstwa (UzytkownikId, ZastepcaId, DataOd, DataDo) VALUES (?, ?, ?, ?)`, [b.kto, b.zastepca, od, dO]));
    return { ok: true };
  }],

  ['POST', /^\/api\/zastepstwa\/(\d+)\/usun$/, async m => {
    await zPrzekazaniem(() => q(`DELETE dbo.Zastepstwa WHERE Id = ?`, [+m[1]]));
    return { ok: true };
  }],

  ['POST', /^\/api\/dostawcy$/, async (_m, b) => {
    const nazwa = String(b.nazwa || '').trim(), nip = String(b.nip || '').replace(/\D/g, '');
    if (!nazwa) throw new Error('Podaj nazwę dostawcy.');
    if (!nipOk(nip)) throw new Error('Niepoprawny NIP – musi mieć 10 cyfr i poprawną sumę kontrolną.');
    const [jest] = await q(`SELECT Id FROM dbo.Dostawcy WHERE NIP = ?`, [nip]);
    if (jest) throw new Error('Dostawca o tym NIP jest już w słowniku.');
    const [r] = await q(`INSERT dbo.Dostawcy (Nazwa, NIP) OUTPUT INSERTED.Id AS id VALUES (?, ?)`, [nazwa, nip]);
    return r;
  }],
];

/* ------------------------------------------------------------------ */
/* Serwer HTTP: API + pliki strony                                     */
/* ------------------------------------------------------------------ */
const TYPY = { '.html': 'text/html; charset=utf-8', '.pdf': 'application/pdf', '.js': 'text/javascript',
               '.css': 'text/css', '.png': 'image/png', '.svg': 'image/svg+xml', '.ico': 'image/x-icon' };

function wyslijJson(res, kod, dane) {
  res.writeHead(kod, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
  res.end(JSON.stringify(dane));
}

function czytajBody(req) {
  return new Promise((res, rej) => {
    const czesci = [];
    let rozmiar = 0;
    req.on('data', c => { rozmiar += c.length; if (rozmiar > 25 * 1024 * 1024) { rej(new Error('Za duży plik (max 25 MB).')); req.destroy(); } else czesci.push(c); });
    req.on('end', () => { try { res(czesci.length ? JSON.parse(Buffer.concat(czesci).toString('utf8')) : {}); } catch (e) { rej(new Error('Niepoprawne dane.')); } });
    req.on('error', rej);
  });
}

// Zmiany wykonujemy po kolei, żeby równoległe żądania nie wysłały podwójnych powiadomień
let kolejka = Promise.resolve();
const poKolei = zadanie => (kolejka = kolejka.then(zadanie, zadanie));

http.createServer(async (req, res) => {
  const url = decodeURIComponent(req.url.split('?')[0]);

  if (url.startsWith('/api/')) {
    const trasa = trasy.find(([metoda, wzor]) => metoda === req.method && wzor.test(url));
    if (!trasa) return wyslijJson(res, 404, { blad: 'Nieznany adres API.' });
    try {
      const body = req.method === 'POST' ? await czytajBody(req) : {};
      const wykonaj = () => trasa[2](url.match(trasa[1]), body, res);
      const wynik = await (req.method === 'POST' ? poKolei(wykonaj) : wykonaj());
      if (wynik !== undefined) wyslijJson(res, 200, wynik);
    } catch (e) {
      console.error(`${req.method} ${url}:`, e.message);
      if (!res.headersSent) wyslijJson(res, e.kod || 400, { blad: komunikat(e) });
    }
    return;
  }

  // Pliki strony z folderu 04_demo
  const plik = path.normalize(path.join(KATALOG_DEMO, url === '/' ? 'index.html' : url));
  if (!plik.startsWith(KATALOG_DEMO)) { res.writeHead(403); return res.end(); }
  fs.readFile(plik, (err, dane) => {
    if (err) { res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' }); return res.end('Nie znaleziono'); }
    res.writeHead(200, { 'Content-Type': TYPY[path.extname(plik).toLowerCase()] || 'application/octet-stream', 'Cache-Control': 'no-store' });
    res.end(dane);
  });
}).listen(PORT, async () => {
  console.log(`Obieg faktur: http://localhost:${PORT}`);
  try {
    const [r] = await q(`SELECT COUNT(*) AS n FROM dbo.Faktury`);
    console.log(`Połączono z bazą ${BAZA} na ${SERWER_SQL} (faktur: ${r.n}).`);
  } catch (e) {
    console.error(`Nie udało się połączyć z bazą ${BAZA} na ${SERWER_SQL}:`, komunikat(e));
    console.error('Sprawdź, czy SQL Server działa i czy uruchomiono skrypt 03_baza_danych.sql.');
  }
});
