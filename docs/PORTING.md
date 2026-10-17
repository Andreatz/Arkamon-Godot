# Struttura e prosecuzione del porting

## La prova attuale

`scenes/main.tscn` è la scena di ingresso. `scripts/main.gd` coordina titolo, scelta, percorso, battaglia e squadra; `scripts/ui.gd` definisce il tema e i componenti grafici comuni. Le schermate sono composte con i nodi Control di Godot. Questa prima iterazione costruisce i pannelli da GDScript: le singole schermate non sono ancora scene `.tscn` indipendenti da impaginare nell'editor.

`CreatureActor` gestisce il ritratto, l'atlas di attesa e i movimenti. I tre atlas originali mantengono ordine, tempi e trasparenza dei fotogrammi, con celle ridotte a 256 pixel. `MapBoard` gestisce la rappresentazione del sentiero; i suoi punti sono definiti per la prova e non importano le mappe locali di Beta.

`BattleRules` carica il catalogo e risolve attacchi, cure e cattura senza dipendere dalle scene. Riceve un `RandomNumberGenerator`, così le verifiche possono riprodurre i lanci. La formula per il danno riprende somma D6, incremento e tabella tipi di Beta; il nome STAB nel riferimento originale indica l'efficacia, senza un secondo moltiplicatore per il tipo dell'attaccante.

`SaveStore` gestisce JSON versione 1, verifica dei dati, file temporaneo e copia precedente. La scena ricostruisce mosse e statistiche dal catalogo quando riprende una partita. Stato di campagna, punto raggiunto e inventario sono specifici di questa prova. Non c'è conversione dei salvataggi web.

## Verifiche significative

- `tests/test_core.gd`: formule D6, HP, effetti supportati, cattura, dati invalidi, scrittura e recupero dei salvataggi.
- `tests/test_flow.gd`: scena reale, scelta, consumi, blocco delle azioni concorrenti, cattura, cambio compagno, progressione, conclusione, sconfitta e ripresa.
- Il controllo Windows esporta e avvia l'eseguibile per verificare che JSON e risorse caricati tramite percorso siano presenti nel pacchetto.
- La verifica visiva locale usa il renderer reale: titolo, scelta, percorso e battaglia. Non è un benchmark delle prestazioni sui PC degli altri giocatori.

## Il prossimo ampliamento utile

Dopo aver giocato la prova e raccolto osservazioni su comandi, tempi e leggibilità, conviene separare titolo, percorso e battaglia in scene dedicate. Il modello di battaglia può poi essere esteso con gli stati alterati e le relative verifiche di parità con Beta, prima di aggiungere altre creature o l'intera campagna.

Le animazioni originali di attacco, colpito, vittoria e KO richiedono un'importazione selettiva successiva. I file video originali non sono necessari al runtime di questa prova. I materiali derivati già importati occupano circa 13 MB con i dati.

Il passaggio a un'esplorazione libera con personaggio, collisioni e tilemap sarebbe una nuova scelta di gameplay: non è necessario per continuare la struttura a tappe e a turni di Arkamon.
