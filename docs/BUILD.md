# Aprire, verificare ed esportare Arkamon 0.2

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

Le schermate sono composte in GDScript: aprire l'editor non trasforma automaticamente ogni vista in una scena visuale indipendente. Il codice di presentazione è separato dai modelli di battaglia e campagna.

## Eseguire l'intera batteria

```powershell
./tools/check.ps1 -Godot $godot
```

Lo script importa risorse e classi, esegue otto suite, poi avvia brevemente la scena principale senza finestra. Rifiuta codici di uscita non zero ed errori Godot/script, compresi quelli di parsing che il motore può segnalare con uscita zero. Le suite usano percorsi di salvataggio dedicati.

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
godot --headless --path . --quit-after 120
```

I comandi Godot sono utilizzabili anche su altri sistemi con il motore adatto, ma questo rilascio viene verificato localmente su Windows. Per controllare grafica, audio e animazioni, usare anche **F5** con il renderer reale: il collaudo headless verifica la logica e l'avvio, non la qualità visiva o sonora.

## Esportare e impacchettare Windows

```powershell
$godot = & ./tools/fetch_godot.ps1 -WithTemplates
./tools/check.ps1 -Godot $godot -ExportWindows

Copy-Item README.md build/windows/LEGGIMI.md
Copy-Item docs/BUILD.md build/windows/SVILUPPO.md
Copy-Item docs/ASSET_PROVENANCE.md build/windows/CREDITI.md
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

## Salvataggi e recupero

La cartella `user://` mantiene il nome **Arkamon — Il primo viaggio** per compatibilità con la prima demo. Nella configurazione Windows standard si trova in `%APPDATA%/Godot/app_userdata/Arkamon — Il primo viaggio/`.

| File | Contenuto |
| --- | --- |
| `full_campaign.json` | Campagna 0.2, entrambi i giocatori, Lega, interazioni e punto di ripresa degli scontri. |
| `campaign.json` | Prima demo Godot; importabile dal titolo nella campagna. |
| `challenges.json` | Classifica locale delle sfide separate. |
| `preferences.cfg` | Preferenze di audio, movimento e velocità delle animazioni. |

`SaveStore` usa `.tmp` e `.bak` per scritture e recupero della campagna. I backup manuali si esportano e ripristinano da **Diario e strumenti**. La migrazione della demo richiede conferma prima di sostituire una campagna attuale. Non è previsto l'import diretto del salvataggio della versione browser.

## GitHub Actions

Il workflow **Godot - verifica e build Windows** parte sui push a `main` e sulle pull request ed è avviabile manualmente da **Actions**. Usa Godot 4.7.2 ufficiale, checksum per i nuovi download e action fissate a commit. La cache conserva editor e template necessari; il workflow esegue le stesse verifiche ed esporta il pacchetto Windows.

Nelle esecuzioni riuscite, l'artefatto **Arkamon-Godot-Windows** contiene `Arkamon-Godot-Windows.zip` e resta disponibile per 14 giorni. Il workflow non pubblica release. La presenza del workflow nel repository non attesta da sola che una specifica esecuzione sia già terminata con successo.

Riferimenti: [riga di comando Godot](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html), [esportazione Windows](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_windows.html), [rapporto delle verifiche locali](VERIFICATION.md).
