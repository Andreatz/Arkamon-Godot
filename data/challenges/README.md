# Provenienza delle regole delle sfide

Il modello riproduce `src/challenges/challengeRules.ts`, `seededRandom.ts` e
le regole della classifica in `challengeStore.ts` di Arkamon-Beta al commit
`7ec91d1f4e3e5252317044b1ee300b8b3e4d80a7`.

`classic_catalog_v1.json` è una copia integrale di
`src/challenges/classicCatalogV1.json` dello stesso commit. Conserva prezzi,
tipi e stadi del catalogo classico. Le regole aggiornate v2 ricalcolano i
prezzi dalle mosse offensive al livello20 del catalogo corrente, secondo la
formula originale. Sono disponibili sei posti, cento crediti e una sola
copia per specie.

La generazione delle squadre e gli identificatori delle configurazioni
usano gli stessi FNV-1a sulle unità UTF-16 e `arkamon-counter-v1` della Beta.
I codici JSON esportano esclusivamente configurazione e versione: statistiche,
HP, mosse e casualità eventualmente iniettati vengono ignorati e ricostruiti.

La battaglia Godot usa invece `RandomNumberGenerator` di Godot. È ripetibile
con lo stesso seed nella stessa versione del gioco, ma lo stream dei tiri
non corrisponde alla Beta. La classifica resta locale alla versione Godot e
filtrata per seed, squadra e versione delle regole; non va unita a classifiche
del gioco browser.

`unicode_nfc.json` contiene decomposizioni canoniche, classi di combinazione
e composizioni della Unicode Character Database, generate con il modulo
`unicodedata` di Python (la versione è registrata nel file). Permette di
normalizzare i seed come `String.normalize('NFC')` dell'originale, incluse
sillabe Hangul e caratteri fuori dal piano multilingue di base.
