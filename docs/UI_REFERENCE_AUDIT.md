# Audit della UI canonica di Arkamon-Beta

Riferimento: commit `7ec91d1f4e3e5252317044b1ee300b8b3e4d80a7`. Audit delle sorgenti svolto il 18 ottobre 2026. Copia di 73 file TS/TSX/CSS/JSON in `../tmp/beta-ui-reference`. Non sono stati usati come riferimento grafico i mockup di `docs/ui-previews`, gli asset di studio proposti o i laboratori `#*-lab`.

## Quale interfaccia viene realmente mostrata

| Schermata | Percorso di produzione attivo | Varianti da non confondere |
| --- | --- | --- |
| Titolo | `App.tsx` → `TitoloScene.tsx`; `GameButton` con SVG player-kit. | Non la preview UI Studio né la pagina laboratorio. |
| Nomi e starter | `LaboratorioScene.tsx`, font e colori amministrativi di default. | Le carte sono pulsanti `.arka-panel`, non la nuova `PlayerUi`. |
| Mappa regionale | `MappaPrincipaleScene.tsx`; coordinate/strade/layout salvati in `arkamon-theme.json`. | Le coordinate `COORDS` inline sono fallback, non i valori visuali effettivi di default. |
| Città/percorsi con mappa locale | `CittaScene`/`PercorsoScene` → `LocalMapScene` quando `getLocalMap` esiste. | La vecchia griglia delle attività è aperta come dialogo; non sostituisce la mappa locale. |
| Deposito normale | `DepositoScene.tsx`: `if (!layoutEditing) return PlayerUi(initialScreen='deposito')`. | Il vecchio `DepositView` appare solo con `layoutEditing=true`. |
| Squadra/analisi/Arkadex/borsa/negozio | `src/player-ui/{TeamScreen,AnalysisScreen,ArkadexScreen,BagScreen,StoreScreen}.tsx` dentro `PlayerUi`. | `ArkadexPanel`, `ArkaStorePanel` e il vecchio deposito non sono le viste canoniche di questi strumenti. |

`PlayerTools.tsx` apre `PlayerUi` in un dialogo montato su `document.body`; il negozio richiede l'interazione valida del luogo. Le sei voci della nav sono Menù Partita, Squadra, Deposito, Arkadex, Analisi, Borsa. Negozio è una vista aggiuntiva aperta dall'interazione, non la settima voce permanente.

## Default e modifiche salvate

`defaultAdminTheme.ts` importa `theme/arkamon-theme.json`, tema **Notte Viola**. `AdminRuntime` applica sempre questo stato tramite variabili CSS; il gold/slate iniziale scritto in `index.css :root` viene sostituito. Il tema è personalizzabile in localStorage: una sessione del sito può avere ulteriori override non contenuti nel repository. Il baseline riproducibile è un browser senza salvataggi amministrativi.

`UiDesignRuntime` è attivo anche nel gioco normale, ma `arkamon-theme.json` non contiene un campo design. `createDefaultDesign()` imposta solo Norwester per body/heading/button, con `screens:{}` e nessun livello extra: le proposte dello studio non sono applicate di default.

## Palette, font e unità

- Font effettivo generale: **Arkamon Norwester**, da `/ui/studio/fonts/norwester.woff2`. `Chela One` è registrato ma non è il font canonico di default; nemmeno Inter o Press Start 2P della configurazione Tailwind.
- Tema generale: primary `#c084fc`, hover `#e9d5ff`, bg `#111827`, surface `#24193d`, hover `#3b2860`, testo `#f8fafc`, secondario `#c4b5fd`, bordo `#7c3aed`; HP `#22c55e/#facc15/#ff3856`.
- UI del tema: panelRadius0, buttonRadius0, panelOpacity.85, shadowIntensity1.2, buttonScale.94, stageScale1, fontScale.75, mainMapRoadOpacity.42.
- `html` vale `16px*.75=12px`: misure Tailwind in rem diventano 75% del valore con radice16. Le misure CSS esplicite `px` e `%` non vengono ridotte.
- `PlayerUi` ha palette propria sopra il tema: ink `#f3f9ff`, muted `#bbd0e6`, line `#4c82b3`, blue `#168cf8`, testo finale `#eff8ff`; sfondo `linear-gradient(110deg,#0a172cdf,#112a44bf)` sopra `deposito.png` (solo Menù usa battle_forest).
- `.arka-stage` è 16:9 centrata, con width=min(100vw,100vh*16/9). Le mappe locali usano invece pieno viewport senza rapporto fisso.

## Titolo e laboratorio

Titolo: video `/assets/Sfondo Titolo.mp4`, cover, loop/muted; sopra overlay bg mix45% trasparente. Logo `/ui/logo_arkamon.png`, width500px max90%, `top:-10rem` = -120px con tema; margin-bottom1rem=12px. Stack pulsanti centrato, width18rem=216px, gap.75rem=9px; Nuova Partita font1.25rem=15px, Continua1.125rem=13.5px. Il logo ha animazione iniziale spring da y=-50; pulsanti entrano da y30 con delay1/speed. Non c'è una griglia hero/sidebar nel titolo originale.

Laboratorio: `/backgrounds/laboratory.png` cover center. `/ui/player1.png`: bottom5%, left-15%, height60%, maxwidth75%. `/ui/player2.png`: bottom0 right0 height88%, maxwidth30%. Contenuto centrato sopra con padding2rem=24px su desktop. Titolo desktop2.25rem=27px. Nomi: maxwidth34rem=408px, input max24caratteri, height2.75rem=33px. Starter: griglia3colonne maxwidth45rem=540px, gap1.5rem=18px, cartepadding1.5rem=18px; ritratto8rem=96px, nome1.5rem=18px. Hover scala1.05 e y-10, tap.95. Sono immagini frontali, non obbligatoriamente animate.

## Mappa regionale

Sfondo `/maps/Mappa-Finale.jpg` cover + nero20%. Posizioni dei nodi e punti intermedi delle strade: `theme/arkamon-theme.json layouts.mainMapNodes/mainMapRoads`, non COORDS fallback. Icone `/ui/start_location.png`, `cities.png`, `countries.png`, `route.png`; diametri22.4px per start/città/villaggio e16px per percorsi. Etichetta nodo10px, ring4px bianco nodo corrente o sky300 raggiungibile, offset2px nero. Hover1.25, tap.9.

I rettangoli degli HUD sono percentuali sull'intero stage. Layout effettivo originale:

```json
{
  "turnPanel": {
    "x": 1.5,
    "y": 2,
    "w": 12.777033764356752,
    "h": 5.14189220119167
  },
  "coinsPanel": {
    "x": 1.4993727142264082,
    "y": 9.891892098091743,
    "w": 10.5,
    "h": 5.5
  },
  "positionPanel": {
    "x": 1.4993727142264082,
    "y": 18.432430164234056,
    "w": 15,
    "h": 5.5
  },
  "actionsPanel": {
    "x": 77.51087024702454,
    "y": 7.141892510491449,
    "w": 21.5,
    "h": 5.5
  },
  "enterButton": {
    "x": 85.17286275123676,
    "y": 14.310812563509554,
    "w": 13.8,
    "h": 5.5
  },
  "passButton": {
    "x": 89.3238552504383,
    "y": 21.180742882393503,
    "w": 9.5,
    "h": 5.5
  },
  "depositButton": {
    "x": 89.3238552504383,
    "y": 28.16216195596231,
    "w": 9.499828500287563,
    "h": 6.364866102063978
  },
  "titleButton": {
    "x": 89.3238552504383,
    "y": 87.1537177627151,
    "w": 9.8,
    "h": 5.5
  },
  "legend": {
    "x": 1.5,
    "y": 80.5,
    "w": 9.129529759788763,
    "h": 13.307437484328801
  },
  "footer": {
    "x": 88.26013831696542,
    "y": 96,
    "w": 4,
    "h": 4
  }
}
```

## PlayerUi: dimensioni e cornici effettive

È una vista a pieno viewport: dialogwidth `100vw-24px`, max1920px; height/maxheight `100dvh-24px`; border `#477cac`, radius8px. Non va ridotta dentro il rettangolo 16:9 della mappa. Lo shell normale ha padding20px28px, font14px e lineheight1.45. Topbar base minheight78 padding12px22, logo190px; nav6colonne gap7 padding8px22, margin16px0 minheight72. Footer bordoalto `#395b7d` e bottone Riprendi il Viaggio.

Tutti i pannelli di PlayerUi usano le SVG originali `public/ui/player-kit/` come **border-image a9parti**, non una semplice immagine stirata. Slice: panel-wide163, panel-medium97, button-primary44, button-default48, card-default61, card-selected-violet58, card-selected-cyan56, slot-default62, slot-selected60, slot-cyan62, card-portrait99. Bordi delle cornici: pannelli25px; pulsanti11pxverticali/18pxorizzontali; card/righe13pxverticali18pxorizzontali.

Portrait: `circle-default.svg`/`circle-selected.svg` sotto lo sprite frontale, con framing `portraitMetadata.json`. Header/topbar e nav condividono `panel-wide`; non ridisegnare questi elementi con gradienti inventati.

**Cascade importante:** `player-ui.css` contiene aggiunte successive che prevalgono sulle prime definizioni. In particolare a minwidth1100 AND minheight820 attiva pagine compatte; l'ultimo blocco ridefinisce topbar minheight54 padding4px18, logo145px, navminheight52 e font15px, headingminheight54. A height810 questo mediaquery NON si attiva. Il progetto Godot a1440×810 deve adattare l'altezza utile senza fingere che quel branch CSS sia attivo. Esiste anche override maxheight1000 per l'icona della borsa88px.

## Viste degli strumenti

- Squadra:6righe reali sempre presenti. Desktop grid colonne `minmax(340px,1.15fr) minmax(285px,.9fr) minmax(330px,1fr)`, gap18. Sinistra roster con cerchio54–62px e HP, centro grande portrait, destra stato/mosse/azioni. Selezione card-violet con triangolino cursore. Non un elenco fullwidth di schede.
- Deposito:2colonne `minmax(500px,1.7fr) minmax(320px,.9fr)`, gap24 base/18compatto. Box7×5, filtri nome/tipo/condizione/livellominmax,6mini slot squadra sotto. Destra hero piccolo, HP, livello/crescita, azione Sposta o scambia. Slotvuoti circolari numerati e selezionabili: non disabilitati. La vecchia defaultDepositLayout non è la produzione normale.
- Arkadex:3colonne `.95fr/1.16fr/1fr` (min280/300/330 base); indice **6specie per pagina**, ricerca/scoperta/tipo, centro hero e opzionale toggleanimazione, destra tab Informazioni/Mosse/Evoluzioni. Le forme sconosciute hanno `?`, non richiedono art e non mostrano tipo/nome. Non18cardsgriglia.
- Negozio:3colonne `minmax(320px,1.1fr) minmax(320px,1fr) minmax(240px,.8fr)`, gap22/18. Catalogo7righeconicona46px(34–42compatto), selettorequantità; centro itemhero180px(110–155compatto), nome/descr/prezzo; destra carrello+saldo+svuota/acquista. `StoreScreen` è attivo; `ArkaStorePanel` è il vecchio pannello ausiliario.
- Borsa:2colonne1.6fr/.9fr; griglia4colonne di itemslot142px, dettagliohero180px con cure/target. Icone ufficiali item-potion,item-superpotion,item-revive,item-antidote,item-sphere; Antiparalisi usa type-electric e Sveglia type-psychic.

## Adattamento nativo consegnato

`scripts/site_player.gd` implementa contenuti Squadra/Deposito/Arkadex/Negozio/Borsa/Analisi con cornici e icone originali, colonne canoniche,6slot squadra,7×5box,6specie Arkadex perpagina, filtri,HP, schede e callback di dominio esistenti. Il root possiede shell/nav. BaseGodot1440×810: righe/icone compatte per evitare clipping con la shell fissa; non replica automaticamente l'HTML responsivo o override amministrativi salvati nel browser. Gestione avanzata spostamenti richiama il dialogo Godot esistente. Non è stata avviata una finestra o processo Godot durante questo incarico; QAvisuale e verifica runtime demandate all'integrazione root.
