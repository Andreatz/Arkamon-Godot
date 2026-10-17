# Aprire, verificare ed esportare Arkamon

Il progetto usa **Godot 4.7.2 stable, edizione standard** (GDScript, senza .NET).
La build distribuita è un'applicazione Windows x86_64 portatile: estrarre lo ZIP
e aprire `Arkamon.exe`. Le risorse del gioco sono incorporate nell'eseguibile.

## Preparare Godot su Windows

Dalla cartella del repository, aprire PowerShell ed eseguire:

```powershell
$godot = & ./tools/fetch_godot.ps1
```

Lo script scarica la release ufficiale da `godotengine/godot-builds`, confronta
l'archivio con `SHA512-SUMS.txt` prima di estrarlo e restituisce il percorso
dell'eseguibile console. L'editor viene salvato in
`%LOCALAPPDATA%/Arkamon/godot-4.7.2`, fuori dal repository. Si può scegliere
un'altra cartella con `-Destination 'C:\Strumenti\godot-4.7.2'`.

Per aprire l'editor:

```powershell
& $godot --path . --editor
```

In alternativa, scaricare manualmente la stessa versione dal
[sito ufficiale](https://godotengine.org/download/archive/4.7.2-stable/), aprire
il Project Manager e importare `project.godot`. Premere **F6** per la scena
aperta oppure **F5** per il gioco completo.

## Eseguire le verifiche

```powershell
./tools/check.ps1 -Godot $godot
```

Le verifiche importano le risorse, caricano gli script, eseguono i test della
logica e dei salvataggi, poi avviano brevemente la scena principale in modalità
headless. Gli errori di parsing vengono considerati un fallimento anche quando
il motore restituisce un codice di uscita zero.

I singoli passaggi, utili anche su Linux o macOS con Godot 4.7.2, sono:

```text
godot --headless --path . --editor --quit
godot --headless --path . --script res://tests/test_core.gd
godot --headless --path . --script res://tests/test_flow.gd
godot --headless --path . --quit-after 120
```

Per provare la resa grafica, aprire il gioco nell'editor con F5. I controlli
headless verificano l'avvio ma non valutano animazioni, leggibilità o audio.

## Creare la versione Windows

```powershell
$godot = & ./tools/fetch_godot.ps1 -WithTemplates
./tools/check.ps1 -Godot $godot -ExportWindows
Copy-Item README.md build/windows/LEGGIMI.md
Copy-Item docs/ASSET_PROVENANCE.md build/windows/CREDITI.md
Copy-Item assets/audio/CreditToZachry.txt build/windows/CreditToZachry.txt
Compress-Archive -Path build/windows/* -DestinationPath build/Arkamon-Godot-Windows.zip -Force
```

La prima installazione dei template scarica l'archivio ufficiale completo
(circa 1,3 GB); installa soltanto i template Windows x86_64 in
`%APPDATA%/Godot/export_templates/4.7.2.stable`. I file già presenti vengono
conservati. Il download resta nella cartella degli strumenti per riutilizzarlo.

Lo script avvia anche l'eseguibile esportato in modalità headless, per
verificare l'accesso alle risorse incorporate.

Il preset **Windows Desktop** incorpora il PCK, comprende i file JSON del
catalogo ed esclude i test e gli strumenti di sviluppo. Per esportare
direttamente, dopo l'importazione e con i template già installati:

```powershell
New-Item -ItemType Directory -Force build/windows | Out-Null
& $godot --headless --path . --export-release 'Windows Desktop' 'build/windows/Arkamon.exe'
```

È possibile usare anche **Progetto → Esporta → Windows Desktop** nell'editor.
L'eseguibile del prototipo non viene firmato con un certificato commerciale.

## Build automatica su GitHub

Il workflow **Godot - verifica e build Windows** esegue le stesse verifiche a
ogni push e pull request e può essere avviato manualmente dalla scheda
**Actions**. Usa Godot 4.7.2, controlla i checksum dei nuovi download e produce
l'artefatto **Arkamon-Godot-Windows**. Aprire una esecuzione completata e
scaricare l'artefatto in fondo alla pagina; gli artefatti rimangono disponibili
per 14 giorni. Il workflow non pubblica release.

Riferimenti: [riga di comando Godot](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html),
[esportazione Windows](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_windows.html).
