# Porting della campagna Godot 0.2

Il riferimento fissato è [Arkamon-Beta al commit 7ec91d1f4e3e5252317044b1ee300b8b3e4d80a7](https://github.com/Andreatz/Arkamon-Beta/tree/7ec91d1f4e3e5252317044b1ee300b8b3e4d80a7). La versione 0.2 trasferisce la campagna regionale per due giocatori e i sistemi locali necessari per giocarla. Non dichiara una parità completa con ogni funzione e strumento della versione web.

## Struttura nativa

`scenes/main.tscn` avvia `scripts/game.gd`. La presentazione della campagna estende `scripts/main.gd`, conservato come base della prima demo; `scenes/prototype.tscn` permette di verificare separatamente quel flusso. I pannelli sono costruiti in GDScript con nodi Control e il tema di `scripts/ui.gd`. Titolo, negozio, deposito e battaglia non sono ancora tutte scene `.tscn` autonome modificabili tramite il solo editor visuale.

| Componente | Responsabilità |
| --- | --- |
| `BattleRules` | Cataloghi, HP, mosse, D6, efficacia, effetti, status e cattura. |
| `BattleSession` | Squadre complete, priorità, azioni, KO e sostituzioni, progressione durante lo scontro, eventi e snapshot ripristinabili. |
| `CampaignModel` | Due giocatori, budget del turno, strade, progressi, inventario, negozio, deposito, evoluzioni, Arkadex, Lega e normalizzazione dei salvataggi. |
| `InteractionRules` e `InteractionEditor` | Configurazione nativa delle attività sui punti delle mappe locali e loro completamento. |
| `ChallengeModel` e `ChallengeMenu` | Squadre a seed/Fanta-Team, codici, versioni delle regole e registro locale separato. |
| `SaveStore` | Validazione e scrittura JSON con file temporaneo, copia precedente e recupero. |
| `WorldBoard` | Mappa regionale e grafi delle mappe locali originali, selezione dei punti e posizioni dei giocatori. |
| `CreatureActor` | Ritratti, riproduzione delle clip originali e reazioni visive agli eventi. |

I modelli del dominio non dipendono dalla scena di gioco. La UI riproduce gli eventi di `BattleSession`; i premi della campagna vengono applicati una sola volta da `CampaignModel`. L'EXP assegnata al KO dalla sessione non viene assegnata nuovamente alla chiusura dello scontro.

## Sistemi trasferiti

La mappa principale conserva **29 nodi e 31 collegamenti**. Le **16 mappe locali** comprendono anche il Percorso 15 segreto, collegato a Roma dopo gli otto capipalestra. Strade, identificatori e geometrie derivano dalle sorgenti originali. Non è stata aggiunta un'esplorazione libera con collisioni e tilemap: il movimento segue i collegamenti e il budget di due azioni della Beta.

`mappe.json`, `allenatori.json`, `incontri.json`, catalogo delle creature, mosse, crescita HP e tipi sono importati dal commit fissato. Gli incontri sui Percorsi 4–14 vengono generati con la stessa costruzione di `src/data/index.ts` e `bilanciamento.ts`: il solo JSON originale contiene 52 righe sui Percorsi 1–3. Questo evita di confondere il catalogo statico con l'intero catalogo disponibile durante il gioco.

Le **110 forme**, i **31 allenatori** e gli **otto capipalestra** sono disponibili nel modello. I giocatori hanno posizione, squadra, 30 box da 35 posti, inventario, sconfitte, catture, Arkadex, diario e archivio personali. Il cap mantiene al massimo cinque livelli di differenza, include i compagni KO e impedisce di accumulare EXP al limite. Le catture fuori fascia o a squadra piena sono conservate nel deposito; uno slot già occupato non viene sovrascritto.

I prezzi e gli effetti dei sette oggetti dell'ArkaStore seguono il catalogo originale: cure percentuali, rianimazione, cure degli status e Masterball per gli incontri selvatici. Gli acquisti sono atomici e gli effetti rifiutati non consumano l'oggetto. Le evoluzioni seguono le soglie del catalogo senza ripristinare automaticamente tutti i PV o cancellare gli status.

La Lega richiede Roma e tutte le otto medaglie. Come nella Beta, gli avversari devono essere configurati: quattro incontri consecutivi nello stesso turno, più un Campione facoltativo. Si scelgono le squadre, la gestione della sconfitta e l'uso degli oggetti fra gli incontri; i PV residui sono conservati. Raggiungere Roma o ottenere l'ottava medaglia non proclama automaticamente un vincitore.

L'editor delle interazioni permette di assegnare dialoghi, ricompense, cure, incontri selvatici, allenatori e negozio ai punti originali. Supporta requisiti di medaglie, tappa precedente, uso unico e completamento personale o condiviso. Le configurazioni sono dati della campagna. I punti senza configurazione rimangono vuoti: non viene inventata una storia per le aree che il riferimento lascia alla regia, compreso il Percorso 15.

## Battaglie, casualità e sfide

Le battaglie supportano squadre, priorità per livello e paralisi, sorteggio in parità, D6, incremento, efficacia, Suprema, status, oggetti, KO e sostituzioni. Nel riferimento Beta il termine STAB indica l'efficacia di tipo: non viene aggiunto un secondo moltiplicatore perché la mossa e l'attaccante hanno lo stesso tipo. I test confrontano formule e casi limite significativi; non costituiscono una dimostrazione automatica della parità di ogni possibile partita con il browser.

Le sfide a seed e Fanta-Team riproducono le regole v1/v2: sei forme al livello 20, cento crediti, specie uniche, catalogo classico congelato, prezzi aggiornati basati sulle mosse offensive, FNV-1a su UTF-16, NFC e generazione deterministica delle squadre. I codici JSON condividono configurazione e versione; HP, mosse e stato casuale eventualmente iniettati vengono ignorati e ricostruiti.

**Lo stream di casualità dei combattimenti resta quello di Godot.** Seed e squadra compatibili non garantiscono gli stessi lanci o risultati della Beta. Le classifiche locali sono separate e confrontano solo la stessa configurazione e versione delle regole. Il generatore counter originale è usato per la generazione delle squadre e per le verifiche di compatibilità.

## Materiali riprodotti

Sono inclusi i ritratti di tutte le forme, sfondi, mappe, avatar e le animazioni disponibili per **37 forme** nella sorgente fissata. Le **185 clip** di attesa, attacco, colpo, vittoria e KO conservano **17.754 fotogrammi originali**, ordine e tempi di **24 FPS**. Non vengono inventati fotogrammi o saltati frame per abbreviare una clip. Le opzioni 2×/3× modificano intenzionalmente la velocità di riproduzione; il movimento ridotto limita gli effetti visivi.

Le altre 73 forme utilizzano ritratti statici con reazioni Godot. Quattro effetti audio e otto effetti grafici generici accompagnano le azioni. Non è stata trasferita la libreria web completa dei **276 effetti curati per mossa**. Compressione, adattamenti e attribuzioni sono descritti in [ASSET_PROVENANCE.md](ASSET_PROVENANCE.md), senza attribuire nuove licenze ai materiali.

## Persistenza e compatibilità

La campagna usa `user://full_campaign.json`; il vecchio prototipo usa `user://campaign.json`; il registro delle sfide usa `user://challenges.json`. Per conservare la compatibilità con la prima demo, il nome della cartella Godot rimane **Arkamon — Il primo viaggio**. Non sono usati direttamente i salvataggi del browser.

Gli snapshot degli scontri comprendono squadre, stato degli Arkamon, turno, slot attivi e generatore casuale. La UI può riprendere dall'ultimo turno salvato. Le scritture mantengono una copia precedente e i backup esportati comprendono entrambi i giocatori. La migrazione della prima demo Godot conserva squadra, monete e pozioni e riparte da Pordenone; le sfere della demo non vengono convertite in un oggetto diverso. La vecchia conclusione della demo non viene trasformata in otto medaglie o in una vittoria della Lega.

## Parti non trasferite

- Votazioni del pubblico tramite QR e relativi servizi/backend.
- Strumenti di regia e amministrazione React completi, compreso il sistema visuale di colori, layout e singoli SVG della UI web.
- Libreria completa degli effetti curati per ogni mossa.
- Importazione diretta dei salvataggi web e funzionalità di rete/account.

L'editor nativo delle interazioni è presente, ma non replica ogni editor della regia web. La separazione futura delle schermate in scene dedicate renderebbe più comodo lavorare sull'impaginazione in Godot; non è un requisito per giocare la campagna attuale.
