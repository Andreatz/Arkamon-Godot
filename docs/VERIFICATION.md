# Verifica della campagna Godot 0.2

Data del rapporto: **18 ottobre 2026**, fuso Europe/Rome. Ambiente locale: **Godot 4.7.2 stable Standard**, Windows x86_64, renderer Compatibility.

## Batteria locale di integrazione

La batteria comprende **3.750 controlli** nelle otto suite seguenti. La verifica locale completa importa le risorse, esegue le suite, esporta l'applicazione Windows e avvia l'eseguibile. La CI remota ha un esito separato, consultabile nella relativa esecuzione.

| Suite | Controlli | Copertura principale |
| --- | ---: | --- |
| `test_core.gd` | 72 | Dati, HP, D6, efficacia, status, effetti, cattura e salvataggi. |
| `test_battle_session.gd` | 113 | Squadre complete, priorità, sostituzioni, KO multipli, Suprema, status e snapshot con casualità ripristinata. |
| `test_campaign.gd` | 276 | Due giocatori e turni, strade e grafi locali, carrelli atomici, borsa, deposito, cattura, evoluzioni, Arkadex, archivio e percorso fino alle quattro sfide della Lega. |
| `test_game.gd` | 140 | Scena principale, attività della campagna, backup degli scontri, recupero dopo la sconfitta della Lega e rifiuto di catture a deposito pieno. |
| `test_interactions.gd` | 47 | Configurazione delle attività sui punti, requisiti, ricompense, cure, completamento e validazione. |
| `test_media.gd` | 2.716 | Manifest, file importati, ritratti, clip, conteggi e tempi dei fotogrammi e collegamenti agli effetti. |
| `test_challenges.gd` | 325 | Fixture originali v1, riferimento JavaScript v2, costi delle 110 forme, seed Unicode, codici e manomissioni, classifica isolata e menu delle sfide. |
| `test_flow.gd` | 61 | Regressioni della prima demo conservata in `scenes/prototype.tscn`. |
| **Totale** | **3.750** | |

Le verifiche scrivono in percorsi di test dedicati e non sovrascrivono la campagna del giocatore. Il flusso della prima demo è conservato come regressione: il suo superamento non viene presentato come prova della campagna regionale.

`tools/check.ps1` importa le risorse, esegue tutte le otto suite e avvia la scena principale in modalità headless. Con `-ExportWindows` esporta anche il preset **Windows Desktop** con PCK incorporato e avvia l'eseguibile risultante. Lo script considera un fallimento anche gli errori di parsing che Godot talvolta accompagna a un codice di uscita zero.

## Cosa dimostrano i controlli

Il modello della campagna viene attraversato sulle strade reali, con le otto palestre e la serie finale della Lega. Le prove verificano che medaglie, monete e risultati non vengano applicati due volte e che la sola ottava medaglia non produca un finale. Queste prove esercitano le transazioni del modello; non sostituiscono una partita completa giocata manualmente.

I test degli scontri controllano l'ordine degli effetti e la conservazione di HP/status durante KO, EXP e sostituzioni. I test della persistenza controllano salvataggi validi, dati alterati, recupero e ripresa da snapshot. I test delle sfide confrontano generazione di squadre, costi e identificatori con fixture della Beta e un calcolo JavaScript indipendente. Lo stream dei lanci in combattimento rimane quello di Godot, quindi non viene dichiarata equivalenza dei risultati fra motori.

La verifica dei materiali confronta la struttura dei manifest e le risorse utilizzabili dal runtime. La copertura delle animazioni è di 37 forme, 185 clip e 17.754 frame originali a 24 FPS; le altre forme usano ritratti statici. Le trasformazioni spaziali sono documentate nella provenienza, mentre non viene introdotto un campionamento temporale dei frame.

## Controllo del pacchetto e limiti

L'avvio headless dell'eseguibile esportato controlla il caricamento del pacchetto e dei file JSON caricati tramite percorso. Il controllo con renderer OpenGL reale comprende titolo, mappa regionale, mappa locale, battaglia, squadra, analisi, deposito, Arkadex, negozio, impostazioni, Lega, sfide ed editor delle interazioni. Sono state controllate viste a 1280×800 e a 1000×625. I pannelli estesi, come sfide e regia, possono scorrere. Gli screenshot presenti in `docs/images/` sono catture locali della versione 0.2; non costituiscono un benchmark o la prova di ogni combinazione di schermate.

Non sono stati eseguiti benchmark su altri PC, collaudi su Linux/macOS, sessioni multiplayer di rete o una valutazione sistematica di ascolto. Il progetto è locale: account, backend del voto pubblico e servizi della versione web sono fuori da questo porting. Nessun risultato in questo documento misura parità di ogni combinazione di mosse o prestazioni su hardware diverso.

Il workflow [Godot - verifica e build Windows](https://github.com/Andreatz/Arkamon-Godot/actions) è configurato per ripetere controlli ed esportazione su GitHub. **L'esito di Actions va letto nella singola esecuzione**; questo rapporto non dichiara che una build remota ancora in corso sia già riuscita.
