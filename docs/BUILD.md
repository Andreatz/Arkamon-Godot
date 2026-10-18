# Aprire, verificare ed esportare Arkamon 0.3

Il progetto usa **Godot 4.7.2 stable Standard**, GDScript e il renderer Compatibility, senza .NET. La build Windows x86_64 è portatile: estrarre tutto lo ZIP e aprire `Arkamon.exe`. Le risorse del gioco sono incorporate nell'eseguibile; per giocare non serve l'editor.

## Preparare l'editor su Windows

Dalla cartella del repository, in PowerShell:

```powershell
$godot = & ./tools/fetch_godot.ps1
& $godot --path . --editor
```

Lo script scarica l'editor dalla release ufficiale `godotengine/godot-builds`, confronta l'archivio con `SHA512-SUMS.txt` prima di estrarlo e restituisce il percorso dell'eseguibile console. I nuovi download vengono verificati; un'installazione già presente viene controllata tramite la versione riportata dal motore.

La destinazione predefinita è `%LOCALAPPDATA%/Arkamon/godot-4.7.2`, fuori dal repository. Per sceglierne un'altra:

```powershell
$godot = & ./tools/fetch_godot.ps1 -Destination 'C:/Strumenti/godot-4.7.2'
```

È possibile anche scaricare manualmente [Godot 4.7.2 Standard](https://godotengine.org/download/archive/4.7.2-stable/), importare `project.godot` nel Project Manager e premere **F5**. La scena di ingresso è `scenes/main.tscn`, coordinata da `scripts/game.gd`. **F6** avvia soltanto la scena aperta. La vecchia demo rimane in `scenes/prototype.tscn` per le regressioni.

La presentazione 0.3 usa lo stage **1440×810, 16:9**, mantenuto proporzionale alla finestra. `scripts/site_shell.gd`, `site_scenes.gd`, `site_player.gd` e `site_battle.gd` separano cornice, scene, strumenti e battaglie dai modelli del dominio.

Le schermate sono composte in GDScript: aprire l'editor non trasforma automaticamente ogni vista in una scena visuale indipendente. Il codice di presentazione è separato dai modelli di battaglia e campagna.

## Eseguire l'intera batteria

```powershell
./tools/check.ps1 -Godot $godot
```

Lo script importa risorse e classi, esegue nove suite, poi avvia brevemente la scena principale senza finestra. Rifiuta codici di uscita non zero ed errori Godot/script, compresi quelli di parsing che il motore può segnalare con uscita zero. Le suite usano percorsi di salvataggio dedicati.

Per eseguire i singoli passaggi, con un eseguibile `godot` disponibile nel percorso di sistema:

```text
godot --headless --path . --editor --quit
godot --headless --path . --script res://tests/test_core.gd
godot --headless --path . --script res://tests/test_flow.gd
godot --headless --path . --script res://tests/test_battle_session.gd
godot --headless --path . --script res://tests/test_campaign.gd
godot --headless --path . --script res://tests/test_game.gd
godot --headless --path . --script res://tests/test_interactions.gd
godot --headless --path . --script res://tests/test_media.gd
godot --headless --path . --script res://tests/test_challenges.gd
godot --headless --path . --script res://tests/test_site_ui.gd
godot --headless --path . --quit-after 120
```

`test_site_ui.gd` è la regressione dedicata alla presentazione 0.3 e agli accessi dalla schermata iniziale. L'elenco dei test qui descrive la batteria prevista: esiti e limiti effettivi sono nel [rapporto delle verifiche](VERIFICATION.md), mentre la CI va controllata nella singola esecuzione Actions.

I comandi Godot sono utilizzabili anche su altri sistemi con il motore adatto, ma questo rilascio viene verificato localmente su Windows. Per controllare grafica, audio e animazioni, usare anche **F5** con il renderer reale: il collaudo headless verifica la logica e l'avvio, non la qualità visiva o sonora.

## Esportare e impacchettare Windows

```powershell
$godot = & ./tools/fetch_godot.ps1 -WithTemplates
./tools/check.ps1 -Godot $godot -ExportWindows

Copy-Item README.md build/windows/LEGGIMI.md
Copy-Item docs/BUILD.md build/windows/SVILUPPO.md
Copy-Item docs/ASSET_PROVENANCE.md build/windows/CREDITI.md
Copy-Item docs/UI_ASSET_PROVENANCE.md build/windows/CREDITI-UI.md
Copy-Item assets/audio/CreditToZachry.txt build/windows/CreditToZachry.txt
Compress-Archive -Path build/windows/* -DestinationPath build/Arkamon-Godot-Windows.zip -Force
```

La prima installazione dei template scarica l'archivio ufficiale completo, circa 1,3 GB, e verifica SHA512 prima dell'estrazione. Installa soltanto i template Windows x86_64 in `%APPDATA%/Godot/export_templates/4.7.2.stable`. I file utente già presenti vengono conservati. Gli archivi scaricati restano nella cartella degli strumenti per il riutilizzo.

Il preset **Windows Desktop** incorpora il PCK, include i JSON caricati dinamicamente ed esclude test, strumenti di sviluppo e documentazione dal pacchetto delle risorse. I documenti e i crediti vengono aggiunti separatamente allo ZIP. Dopo l'export, lo script avvia l'EXE in modalità headless per verificare l'accesso alle risorse incorporate.

Per una sola esportazione, dopo importazione e installazione dei template:

```powershell
New-Item -ItemType Directory -Force build/windows | Out-Null
& $godot --headless --path . --export-release 'Windows Desktop' 'build/windows/Arkamon.exe'
```

Si può usare anche **Progetto → Esporta → Windows Desktop** nell'editor. L'eseguibile non viene firmato con un certificato commerciale.

## Asset originali e controllo visivo

Il progetto include i 48 SVG originali del kit, i PNG della UI e il font Norwester decodificato in TTF per Godot. `data/site_theme.json` conserva colori e coordinate autoriali; `data/portrait_metadata.json` conserva la cornice dei ritratti del sito. Il titolo usa `assets/backgrounds/title.ogv`: video Theora 1280×720, 8 secondi, 192 fotogrammi a 24 FPS, derivato dal filmato originale. Il primo fotogramma è disponibile in `title.webp` per movimento ridotto e avvio senza video.

`tools/import_beta_ui.py` riproduce l'import UI dal commit fissato. Pillow serve per l'ispezione delle immagini; `fonttools[woff]==4.62.1` decodifica il font; l'opzione `--ffmpeg` abilita la conversione del titolo con un eseguibile esterno. Dipendenze e cache restano fuori dal repository. `--cache-only` impedisce richieste di rete. Vedi [UI_ASSET_PROVENANCE.md](UI_ASSET_PROVENANCE.md) per hash, comandi e attribuzioni; non occorre rieseguire questo import per aprire il progetto già completo.

Dopo una modifica alla presentazione, confrontare Titolo, laboratorio, mappa regionale, mappa locale, battaglia e squadra con il riferimento indicato in [UI_REFERENCE_AUDIT.md](UI_REFERENCE_AUDIT.md). Le immagini aggiornate del rilascio sono `docs/images/title.png`, `world.png`, `battle.png` e `party.png`. Identità degli asset non significa identità assoluta del rendering tra Godot e browser.

## Salvataggi e recupero

La cartella `user://` mantiene il nome **Arkamon — Il primo viaggio** per compatibilità con la prima demo. Nella configurazione Windows standard si trova in `%APPDATA%/Godot/app_userdata/Arkamon — Il primo viaggio/`.

| File | Contenuto |
| --- | --- |
| `full_campaign.json` | Campagna 0.2/0.3, entrambi i giocatori, Lega, interazioni e punto di ripresa degli scontri. |
| `campaign.json` | Prima demo Godot; importabile da Partita → Backup nella campagna. |
| `challenges.json` | Classifica locale delle sfide separate. |
| `preferences.cfg` | Preferenze di audio, movimento e velocità delle animazioni. |

La 0.3 mantiene il formato della campagna 0.2 e il percorso dei dati utente. Non è richiesta una conversione dei salvataggi 0.2.

`SaveStore` usa `.tmp` e `.bak` per scritture e recupero della campagna. I backup manuali si esportano e ripristinano da **Partita → Backup**. La migrazione della demo richiede conferma prima di sostituire una campagna attuale. Non è previsto l'import diretto del salvataggio della versione browser.

## GitHub Actions

Il workflow **Godot - verifica e build Windows** parte sui push a `main` e sulle pull request ed è avviabile manualmente da **Actions**. Usa Godot 4.7.2 ufficiale, checksum per i nuovi download e action fissate a commit. La cache conserva editor e template necessari; il workflow esegue le stesse verifiche ed esporta il pacchetto Windows.

Nelle esecuzioni riuscite, l'artefatto **Arkamon-Godot-Windows** contiene `Arkamon-Godot-Windows.zip` e resta disponibile per 14 giorni. Il workflow non pubblica release. La presenza del workflow nel repository non attesta da sola che una specifica esecuzione sia già terminata con successo.

Riferimenti: [riga di comando Godot](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html), [esportazione Windows](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_windows.html), [rapporto delle verifiche locali](VERIFICATION.md).
