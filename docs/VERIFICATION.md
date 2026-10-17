# Verifica della prima versione giocabile

Data: **17 ottobre 2026**. Motore: **Godot 4.7.2 stable Standard**, Windows x86_64, renderer Compatibility.

## Risultati locali

- Importazione con editor headless: completata, nessun errore di script.
- `tests/test_core.gd`: **39 verifiche, 0 errori**.
- `tests/test_flow.gd`: **61 verifiche, 0 errori**.
- Avvio della scena principale headless: completato.
- Export release Windows con PCK incorporato: completato.
- Avvio dell'eseguibile esportato: completato; dati JSON e risorse disponibili nel pacchetto.
- Verifica visiva con renderer OpenGL reale: titolo, scelta, percorso, battaglia e cronaca a 1440×900; titolo, battaglia, guida, impostazioni e conclusione a 1000×625. Nessun comando essenziale tagliato nelle viste controllate.

La verifica del flusso crea una campagna in un percorso di test dedicato. Attraversa cattura, blocco di azioni duplicate, uso e rifiuto di oggetti, squadra, riposo, vittorie, finale, sconfitta e ripresa da una nuova istanza della scena. Non sostituisce il salvataggio del giocatore.

Gli screenshot sono acquisiti dall'applicazione Godot, senza ricostruzioni grafiche esterne. `docs/images/battle.png` mostra una delle catture della prima versione.

## Limiti della verifica

Non sono stati eseguiti benchmark su altri PC, sessioni di lunga durata o prove su Linux/macOS. L'avvio headless dell'eseguibile verifica packaging e caricamenti; il controllo della resa grafica è stato effettuato localmente con il renderer reale. La presenza dei suoni e il loro collegamento agli eventi è verificata nel progetto; non è stata condotta una valutazione di ascolto.

La pipeline GitHub ripete le verifiche e l'export Windows sui commit della proposta. Il suo esito va letto nella relativa esecuzione Actions; questo documento riporta i risultati locali.
