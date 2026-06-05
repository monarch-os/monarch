# Plan — Déléguer le theming de Monarch à Noctalia

> Document de suivi vivant. On coche au fur et à mesure.
> Branche : `feat/niri-migration`.
> Dernier audit de conformité au code : **2026-06-05** — corrigé : bloc `light`
> écrit, nom de la migration de nettoyage (`1779188617`), layout `themes/` aplati,
> compteurs de tests. Theming Plymouth livré (manuel, voir TODO). Reste côté code :
> companion pywalfox.

## Objectif

Supprimer le moteur de thèmes maison de Monarch et déléguer le theming à Noctalia,
en acceptant le modèle de couleurs **Material / wallpaper** (pas de palette ANSI 16
couleurs taillée à la main). Noctalia devient la source de vérité couleurs +
templates + wallpaper + shell ; il ne reste qu'une fine couche Monarch pour le
système/hardware que Noctalia ne peut pas atteindre.

Élément déclencheur : le picker wallpaper de Noctalia ne scanne qu'un seul
`wallpaper.directory` et ne trouvait pas les fonds rangés par thème de Monarch.

## Décisions verrouillées

> **Pivot (2026-05-23)** — On abandonne la curation des 20 thèmes. Monarch ne livre
> plus **qu'un seul scheme `Monarch`**, avec blocs `dark` ET `light` (variante light
> propre à écrire par l'utilisateur). Conséquence : dark/light redevient le **toggle
> global Noctalia** (GTK/Qt via `syncGsettings`), `monarch-theme-apply` ne flippe plus
> `darkMode` → plus de re-fire / double-passe. Les 13 schemes custom non-Monarch ont
> été retirés de `config/noctalia/colorschemes/` ; les built-ins Noctalia restent
> sélectionnables dans le picker. Les sections ci-dessous gardent la trace de l'ancien
> modèle (20 thèmes) là où c'est utile, mais la cible est désormais « Monarch seul ».

- **Modèle couleurs** : Material/wallpaper. Pas d'ANSI curated. Le moteur de
  templates Noctalia n'expose que les tokens Material-3 (`{{colors.<name>.<mode>.<format>}}`)
  + `{{image}}` (chemin wallpaper). Registre : `~/.config/noctalia/user-templates.toml`.
- **Thèmes** : **un seul scheme `Monarch`** (blocs `dark` + `light`). Plus de set de 20.
  - `colorSchemes.useWallpaperColors = false` (les couleurs viennent du scheme choisi).
  - **dark/light = toggle global Noctalia**, pas de flip réactif côté Monarch.
- **Templates intégrés (natifs)** confirmés en VM : alacritty, kitty, foot, ghostty,
  **btop, helix** (+ zed, zenBrowser ; probablement vscode/firefox). Activés via
  `templates.activeTemplates: [{ "enabled": true, "id": "<app>" }]`.
  → **btop et helix n'ont PLUS besoin de user-template.**
- **VSCode** : **natif** via l'extension compagnon *NoctaliaTheme* + son template (suit le scheme).
- **Niri est un template intégré** → focus-ring/border thémés nativement (plus de user-template niri).
- **Apps via user-templates (à écrire)** : neovim, obsidian **seulement** (pas de built-in).
  Mécanisme activé par `templates.enableUserTheming = true` + registre `user-templates.toml`.
- **Couche résiduelle Monarch** : un seul script `monarch-theme-apply` câblé sur le
  **hook natif `hooks.colorGeneration`** (se déclenche à chaque (re)génération de couleurs
  = changement de scheme — pas besoin de « pont user-template »). `hooks.enabled = true`.
  Il gère : RGB clavier, Chromium, et le repointage wallpaper (voir Phase 4).
  *(Plymouth par scheme retiré — voir Phase 5 + TODO.)*
- **GTK/Qt** : géré nativement par `colorSchemes.syncGsettings = true` (pas de hook/script).
- **Wallpaper / couplage thème↔fond** : conservé, mais via le `post_hook` ci-dessus.
  - `wallpaper.directory` repointé vers le dossier du scheme courant.
  - Chemin **(b)** user-writable : `~/.config/monarch/backgrounds/<scheme>/`,
    seedé à l'install depuis les fonds livrés. *(à confirmer)*
  - Le hook applique aussi un fond (`ipc call wallpaper set <path> ""`) pour que
    l'écran change vraiment, pas seulement le picker. *(à confirmer)*
  - On garde des fonds par scheme sous `themes/<scheme>/` (layout aplati, pas de
    sous-dossier `backgrounds/`) ; on supprime le reste de `themes/`.

## Questions ouvertes

- [x] **Navigateur** : les deux. Firefox → natif (Pywalfox). Chromium → hook résiduel (`monarch-theme-apply`).
- [x] Chemin wallpaper **(b)** `~/.config/monarch/backgrounds/<scheme>/` (writable, seedé à l'install).
- [x] « Le fond change vraiment » au changement de thème : oui (`ipc call wallpaper set`).

## Schemes livrés (post-pivot)

**Monarch seul** : `config/noctalia/colorschemes/Monarch/Monarch.json`, blocs `dark`
(existant) + `light` (à écrire proprement par l'utilisateur). C'est le scheme par
défaut (`predefinedScheme = "Monarch"`).

Les built-ins Noctalia (Ayu, Catppuccin, Dracula, Eldritch, Gruvbox, Kanagawa,
Noctalia, Nord, Rose Pine, Tokyo Night) restent disponibles dans le picker — Monarch
n'en livre/curate aucun. Pour eux, `monarch-theme-apply` dégrade gracieusement
(pas de JSON livré → concerns couleur en no-op ; wallpaper marche si un dossier de
fonds existe).

<details><summary>Historique : ancien mapping des 20 thèmes (abandonné)</summary>

14 schemes Material écrits puis retirés : catppuccin-latte, ethereal, everforest,
flexoki-light, hackerman, lumon, matte-black, miasma, osaka-jade, retro-82,
ristretto, vantablack, white (+ monarch, conservé). 6 mappés sur built-ins :
catppuccin, gruvbox, kanagawa, nord, rose-pine, tokyo-night.
</details>

## Matrice de couverture

| Appli | Mécanisme cible |
|---|---|
| alacritty / kitty / foot / ghostty | template **intégré** Noctalia |
| fuzzel | intégré |
| VSCode | natif (extension *NoctaliaTheme* + template) |
| Firefox | natif (Pywalfox) |
| Chromium | résiduel — `monarch-theme-apply` |
| btop / helix | template **intégré** Noctalia |
| neovim / obsidian | user-template Material (à écrire) |
| niri (focus-ring/border) | template **intégré** Noctalia |
| GTK/Qt dark/light + couleurs | natif via `colorSchemes.syncGsettings` (+ templates GTK/Qt dispo) |
| Plymouth (boot) | splash statique Monarch uniquement ; theming par scheme **retiré** (TODO) |
| RGB clavier (asusctl/openrgb) | résiduel — `monarch-theme-apply` |

---

## Phases

### Phase 0 — Préparation
- [x] Brancher le travail (sur `feat/niri-migration`).
- [x] VM : les schemes Noctalia se chargent et s'appliquent (picker OK, UI repeinte au changement).
- [ ] VM : confirmer les templates intégrés + les hooks (en cours, voir Phase 1).

### Phase 1 — Couleurs / schemes Noctalia
- [x] `config/noctalia/settings.json` : `colorSchemes.useWallpaperColors=false`.
- [x] **Templates intégrés activés** dans le défaut. Schéma confirmé en VM :
      `templates.activeTemplates: [{enabled,id}]` + `templates.enableUserTheming`.
      Baké : alacritty, kitty, foot, ghostty, btop, helix. Aussi posé
      `colorSchemes.syncGsettings=true` + `darkMode=true`.
- [x] Ajoutés au défaut : `niri`, `code` (= VSCode), `pywalfox`, `starship`. IDs confirmés en VM.
      (code/pywalfox : companions requis — extension *NoctaliaTheme* / addon pywalfox,
      à wirer à l'install en Phase 6.)
- [x] Écrire les 14 schemes Material sous `config/noctalia/colorschemes/<Nom>/<Nom>.json`
      (déployés via `install/config/config.sh` → `cp -R config/* ~/.config/`).
      Générés depuis `themes/<nom>/colors.toml` via le mapping de `noctalia.json.tpl`
      (inclut un bloc `terminal` ANSI — bonus si Noctalia le consomme, à vérifier en VM).
      Schemes clairs émis sous clé `"light"` : Catppuccin-Latte, Flexoki-Light, White.
      Les 6 thèmes restants utilisent les built-ins Noctalia (catppuccin, gruvbox,
      kanagawa, nord, rose-pine, tokyo-night).
- [x] Shipping décidé : `config/noctalia/colorschemes/` (copié à l'install).
- [x] **Vérifié en VM** : les 14 schemes apparaissent dans le picker ; changer de scheme
      repeint l'UI Noctalia (barre/launcher/control center). Terminal inchangé à ce stade
      (attendu — câblage terminal en Phase 3).

### Phase 2 — User-templates (Material) — RÉDUITE
> btop, helix, alacritty, **niri** sont NATIFs → retirés d'ici. Restent neovim + obsidian.
> **Convention** : les *inputs* vivent sous `config/noctalia/templates/` (shippés par
> `cp -R config/* ~/.config/`), stables face à `monarch-nvim-setup` qui réécrit `~/.config/nvim`.
> Seuls les *outputs* atterrissent dans les dossiers d'app. Tokens Noctalia confirmés :
> 48 tokens MD3 (`primary`, `secondary`, `tertiary`, `error`, `surface*`, `outline*`,
> `on_*`, `*_container`, `*_fixed_dim`, `inverse_*`, `background`, `shadow`, `scrim`…),
> variants `default|dark|light`, formats `hex|hex_stripped|rgb|rgba|hsl|hsla` + canaux,
> plus token `{{image}}` (chemin wallpaper). Schéma registre : `[templates.<id>]` avec
> `input_path` / `output_path` / `post_hook`. `enableUserTheming=true` déjà posé.
- [x] Registre `config/noctalia/user-templates.toml` créé (entrées `nvim-base16` + `obsidian`).
- [x] **neovim** — template base16 `config/noctalia/templates/nvim-base16.lua`
      (input) → `output_path` `~/.config/nvim/lua/matugen.lua`, `post_hook = 'pkill -SIGUSR1 nvim'`.
      Module Lua exposant `setup()` qui appelle `base16-colorscheme.setup{ base00..base0F }`,
      mapping MD3→base16 d'après la doc Noctalia.
      **Option A retenue** (base16-nvim, délégation pure ; perte des colorschemes curated assumée).
      ⚠️ **Dépendance hors-repo** : l'install du plugin `RRethy/base16-nvim`, le `theme.lua`
      statique appelant `require('matugen').setup()`, le hot-reload SIGUSR1, la suppression de
      `all-themes.lua` + du symlink `theme.lua` dans `monarch-nvim-setup` relèvent du
      **package externe `monarch-nvim`** (repo `monarch-pkgs`, `/usr/share/monarch-nvim/`).
      → TODO détaillé documenté : `~/Work/monarch/wiki/monarch-nvim — migration base16-nvim (Noctalia).md`.
      doc : https://docs.noctalia.dev/v4/theming/program-specific/neovim/
- [x] **obsidian** — pas de built-in → user-template CSS custom
      `config/noctalia/templates/obsidian.css` (tokens MD3) → output staging `~/.config/monarch/obsidian/theme.css`,
      `post_hook = monarch-obsidian-theme` qui fan-out vers chaque vault (`.obsidian/themes/Noctalia/`).
      Nouveau script `bin/monarch-obsidian-theme` (remplace `monarch-theme-set-obsidian`, supprimé en Phase 6).
- [ ] **VM à valider** : (a) Noctalia crée bien le parent de l'output (`~/.config/monarch/obsidian/`) ;
      (b) le `post_hook` s'exécute (PATH contient `bin/`) ; (c) base16-nvim côté `monarch-nvim`.

### Phase 3 — Repointer les includes des configs
> **Découverte VM** : Noctalia **auto-injecte** son include dans la config de l'app.
> Confirmé : foot → `include=~/.config/foot/themes/noctalia` ; niri →
> `include "./noctalia.kdl"` (= `~/.config/niri/noctalia.kdl`). Les anciens includes
> Monarch (`~/.config/monarch/current/theme/...`) deviennent **redondants et cassés**.
> → Phase 3 = retirer l'ancien include Monarch + fixer l'include Noctalia **en source**
> (stable face aux `monarch-refresh-*` ; doit rester idempotent avec l'auto-injection).
Sorties Noctalia confirmées : kitty `~/.config/kitty/themes/noctalia.conf` ;
ghostty `~/.config/ghostty/themes/noctalia` (via `theme = noctalia`) ;
alacritty `~/.config/alacritty/themes/noctalia.toml` ; btop `~/.config/btop/themes/noctalia.theme`.
Noctalia auto-injecte pour foot/niri/ghostty/alacritty, **pas pour kitty** (include manuel).
- [x] `config/foot/foot.ini` : ancien include retiré → `include=~/.config/foot/themes/noctalia`.
- [x] `default/niri/config.kdl` : ancien include retiré → `include "./noctalia.kdl"`.
      ⚠️ **Fix boot (révisé 2026-05-23)** : on **ship un défaut `default/niri/noctalia.kdl`**
      (couleurs Monarch : focus-ring/border `active=#b471de`, `inactive=#3c2a6c`) que
      `monarch-refresh-niri` **seed** dans `~/.config/niri/noctalia.kdl` s'il est absent (et **ne
      clobbe pas** une version générée par Noctalia). Avant : on bootstrappait un fichier *vide* —
      mais ce code n'était pas déployé partout, d'où un deadlock observé en VM (include manquant =
      erreur fatale niri → niri ne boote pas → Noctalia ne tourne jamais → fichier jamais généré).
      Le défaut livré rend l'include toujours résoluble au 1er boot ; Noctalia le régénère ensuite.
      Garder le chemin **`./noctalia.kdl`** (injection idempotente Noctalia, grep `(\./)?noctalia\.kdl`).
      niri : `include` depuis 25.11, expansion `~/` + `optional=true` depuis 26.04 (on n'utilise pas
      `optional=true` pour rester compatible 25.11–26.03).
- [x] `config/kitty/kitty.conf` : `include themes/noctalia.conf`.
- [x] `config/ghostty/config` : `theme = noctalia`.
- [x] `config/alacritty/alacritty.toml` : `import = [ "~/.config/alacritty/themes/noctalia.toml" ]`.
- [x] `config/btop/btop.conf` : `color_theme = "noctalia"`.
      → le symlink `~/.config/btop/themes/current.theme` (créé par theme.sh) devient inutile
      → suppression en Phase 6 (`install/config/theme.sh`).

### Phase 4 — Wallpaper
> **Contrat Noctalia confirmé en source** (`Services/Control/HooksService.qml`,
> `Services/UI/WallpaperService.qml`, `Services/Control/IPCService.qml`, `Commons/Settings.qml`) :
> - `hooks.colorGeneration` se déclenche sur **chaque (re)génération de couleurs** (= changement
>   de scheme, et aussi toggle dark/light), et ne passe que **`$1` = `dark|light`** — **pas** le
>   nom du scheme. → `monarch-theme-apply` lit lui-même `colorSchemes.predefinedScheme`.
> - IPC : `ipc call wallpaper set <path> <screen>` avec `screen=""` → tous les moniteurs (OK).
> - `wallpaper.directory` est surveillé (`watchChanges:true`, reload débounce sur **remplacement
>   atomique**) → écrire `settings.json` via temp+`mv` déclenche `onDirectoryChanged` →
>   `refreshWallpapersList()` : le picker se rafraîchit en live. ✅ (résout la question ouverte).
> - `wallpaper.transitionType` est une **liste** (pas une string).
- [x] `config/noctalia/settings.json` : section `wallpaper` (`enabled=true`,
      `directory="~/.config/monarch/backgrounds/monarch"`, `transitionType=["fade"]`,
      `transitionDuration=1500`, `automationEnabled=false`).
- [x] Fonds livrés : `themes/<scheme>/` (fichiers aplatis, pas de sous-dossier `backgrounds/`).
      Le seeding vers `~/.config/monarch/backgrounds/<scheme>/` est **auto-géré par
      `monarch-theme-apply`** (idempotent, `cp -rn` depuis `$MONARCH_PATH/themes/<scheme>/`),
      plus robuste qu'un seeding install-only et testable en VM sans réinstall.
- [x] `monarch-theme-apply` (nouveau `bin/`) : repointe `wallpaper.directory` (chemin (b),
      écriture atomique) avec **garde d'idempotence** (ne fait rien si même dossier → préserve
      le fond choisi lors d'un simple toggle dark/light), **fallback si dossier vide/absent**,
      et **normalisation** display name → kebab-case (+ alias `rosepine`→`rose-pine`).
- [x] `monarch-theme-apply` : `ipc call wallpaper set <fond> ""` (1er fond du dossier) — seulement
      quand le dossier change, pour vraiment changer l'écran.
- [x] `monarch-menu` Background → `ipc call wallpaper toggle` (ouvre le picker Noctalia).
- [x] Vérifier en VM : hot-reload de `wallpaper.directory` rafraîchit le picker ; `monarch theme apply`
      (lancé à la main) repointe + applique ; pas de boucle (`useWallpaperColors=false`).

### Phase 5 — Couche résiduelle (hooks)
- [x] `hooks.colorGeneration = "monarch-theme-apply"` + `hooks.enabled = true` dans
      `config/noctalia/settings.json` (section `hooks`). Le hook tourne `monarch-theme-apply`
      (sur le PATH Monarch) à chaque (re)génération de couleurs, avec `$1=dark|light`.
- [x] `monarch-theme-apply` : wallpaper + RGB clavier + Chromium (plus de darkMode, plus de plymouth).
      **Toutes les couleurs sont dérivées du JSON de scheme Noctalia** livré sous
      `~/.config/noctalia/colorschemes/<Scheme>/<Scheme>.json`, **bloc de l'apparence active**
      (`$1=dark|light` du hook, sinon `colorSchemes.darkMode` ; fallback sur le bloc dispo) :
      `mPrimary`=accent clavier, `mSurface`=fond Chromium (fallback `terminal.*`).
      - **RGB clavier** : logique asusctl + qmk_hid (Framework 16) inlinée (cheap, sans sudo →
        OK sur le hook). Couleur = `mPrimary`.
      - **Chromium** : écrit `BrowserThemeColor` dans `/etc/chromium/policies/managed/color.json`
        (rendu world-writable à l'install par `theme.sh` → pas de sudo) + refresh des navigateurs
        lancés. Chrome/Edge/Brave seulement si leur dossier de policy existe et est writable.
- [x] **Plymouth : theming par scheme RETIRÉ (2026-05-23).** Le recolor dynamique (`sudo` +
      rebuild initramfs) était peu fiable et inutilisé → `sync_plymouth` retiré de
      `monarch-theme-apply` ; scripts `monarch-plymouth-set`/`-preview` supprimés. Le **splash de
      boot Monarch statique reste** (`default/plymouth/` + `monarch-refresh-plymouth`/`-reset` +
      `install/login/plymouth.sh`). **TODO** : meilleure implémentation du theming Plymouth plus tard.
- [x] GTK/Qt **et** dark/light : 100 % natif Noctalia (`colorSchemes.syncGsettings=true` + toggle
      darkMode global). **`monarch-theme-apply` ne touche plus `darkMode`** (pivot : Monarch livre
      les deux blocs dans son scheme → aucun flip réactif, donc plus de re-fire ni double-passe).
- [x] **Métadonnées par scheme hors couleurs : aucun store séparé.** Tout vient du JSON de scheme
      (bloc actif). Overrides curated abandonnés (modèle Material) : l'ancien `keyboard.rgb` par
      thème et `chromium.theme` → désormais accent/fond du scheme.
- [x] **VM validé** (modèle pré-pivot) : hook déclenché au changement, RGB/Chromium suivent,
      built-ins dégradent sans crash. ⚠️ La bascule GTK/Qt
      en clair se fait désormais via le toggle darkMode natif (et non plus le flip Monarch) —
      **à re-valider** avec le bloc `light` de Monarch une fois écrit.
- [x] **Latence apply : cause supprimée par le pivot.** Le flip `darkMode` réactif (qui re-déclenchait
      une régénération complète sur les schemes clairs) n'existe plus. Reste l'overhead inhérent
      Noctalia/VM ; à re-vérifier sur HW mais plus de double-passe côté Monarch.

### Phase 6 — Démantèlement + plomberie
> **Post-pivot** : 13 schemes custom déjà retirés de `config/noctalia/colorschemes/`
> (reste `Monarch`). Le démantèlement vise maintenant le **mono-Monarch**.
- [x] `rm` scripts `monarch-theme-*` (21 supprimés) : set, set-templates, set-foot,
      set-gnome, set-browser, set-vscode, set-obsidian, set-keyboard*, colors-from-alacritty,
      list, current, install, remove, update, refresh, bg-next, bg-set, bg-install
      + `monarch-plymouth-set-by-theme`. Plymouth theming retiré (2026-05-23) :
      `monarch-plymouth-set` + `monarch-plymouth-preview` aussi supprimés.
      Gardés : `monarch-theme-apply`, `monarch-obsidian-theme`, et le splash statique
      (`monarch-plymouth-reset`, `monarch-refresh-plymouth`, `default/plymouth/`).
- [x] `rm` `default/themed/` (tous les `.tpl`) + `config/monarch/themed/` (sample user-template).
- [x] `themes/` réduit puis re-seedé : dossiers **aplatis par scheme** (`themes/<scheme>/*.png`,
      plus de sous-dossier `backgrounds/`) — `monarch` + 6 wallpapers Omarchy (catppuccin,
      gruvbox, kanagawa, nord, rosepine, tokyo-night), via commit `6906724`.
- [x] **Bloc `light` de `Monarch.json` écrit** (valeurs claires distinctes du `dark` :
      surface `#e1e2e7`, accent `#9854f1` ; commits `95101be` + `072bd32`).
- [x] Éditer `bin/monarch` : retiré `theme list/set` de l'aide ; groupe `theme` = `apply` seul ;
      description du groupe mise à jour.
- [x] Éditer `bin/monarch-menu` : retiré le sélecteur (`show_theme_menu`), le dispatch `theme`,
      et les entrées install/remove/update theme + `show_install_style_menu`. Background = picker Noctalia.
- [x] Éditer `default/niri/binds.kdl` : `Mod+Shift+Ctrl+Space` repointé `theme` → `style`
      (le menu theme n'existe plus) ; `Mod+Ctrl+Space` = picker fonds.
- [x] Éditer `install/config/theme.sh` : retiré initial `monarch-theme-set` + symlinks btop/noctalia
      + dossier user-themes ; garde la policy Chromium ; appelle `monarch-theme-apply` (scheme livré).
- [x] **Companion VSCode** : `monarch-install-vscode` installe l'extension *NoctaliaTheme*
      (Open VSX `Noctalia.noctaliatheme`) + pose `workbench.colorTheme=NoctaliaTheme`.
      (Pas de script d'install VSCodium dans le repo → rien à câbler côté Codium.)
      → **VM** : valider l'id d'extension + le label de thème exact.
- [ ] Companion **pywalfox** (Firefox) : non câblé à l'install (addon + native host = manuel,
      non testable ici). TODO restant.
- [x] Éditer `default/pi/agent/extensions/monarch-system-theme.ts` : lit `colorSchemes.darkMode`
      de `~/.config/noctalia/settings.json` (au lieu de `current/theme/light.mode`).
- [x] `test/monarch-cli-test.sh` : assertions `theme set/list/current` retirées/repointées sur
      `theme apply` ; suite **verte** (EXIT 0).
- [x] Migration de nettoyage `migrations/1779188617.sh` (purge l'ancien état + déploie le scheme +
      `monarch-theme-apply`). Migrations obsolètes supprimées (8) ; 4 éditées (switchover Noctalia,
      loader niri, switch chromium, tmux) pour retirer les appels morts. `fastfetch` lit le scheme
      depuis Noctalia.
- [x] MAJ `AGENTS.md` + `default/monarch-skill/SKILL.md` (modèle délégué à Noctalia).

### Phase 7 — Validation
**Validation statique locale (faite, verte) :**
- [x] `bash test/monarch-cli-test.sh` vert (EXIT 0, 57 assertions ok).
- [x] `bin/monarch commands --check` OK (246 commandes).
- [x] `bash -n` sur tous les scripts `bin/` + `install/` + `migrations/` : OK pour tout ce qui
      touche au theming. *(Note hors-périmètre : `bin/monarch-refresh-pacman` a un bug préexistant —
      `if` sans `fi`, ligne 10 — non lié à cette migration, à corriger à part.)*
- [x] JSON valides : `settings.json` (hooks/templates/wallpaper OK) + `Monarch.json` (bloc `dark`).
- [x] Snippet fastfetch résout bien le scheme depuis Noctalia (`Monarch`).
- [x] Sweep de références mortes (scripts/paths supprimés) : propre côté code.
- [x] `monarch-theme-apply` en HOME bac-à-sable avec la config livrée : chemin install (sans `$1`)
      et chemin hook (`$1=light` sur scheme dark-only → fallback) → exit 0, wallpaper repointé
      sur `monarch`, `darkMode` intact, `settings.json` reste valide.

**À valider en VM (non exécutable ici — niri/Noctalia absents) :**
- [ ] (VM) Toggle dark/light Noctalia → GTK/Qt + shell suivent. (Bloc `light` déjà écrit ✅ — reste la validation du toggle en VM.)
- [x] Changement d'apparence/scheme → terminaux/btop/helix/vscode/niri/wallpaper/Chromium/RGB suivent.
- [x] *(Plymouth theming retiré — plus à valider ; splash statique inchangé.)*
- [x] Companions : id extension VSCode `Noctalia.noctaliatheme` + label `NoctaliaTheme` corrects ;
      template Helix Noctalia écrit bien `~/.config/helix/themes/noctalia.toml`.
- [ ] `monarch migrate` (migration `1779188617`) sur une install pré-pivot : purge + déploie sans casse.
- [ ] Screenshot de contrôle (`monarch capture screenshot fullscreen save`).

## TODO (post-migration)
- [x] **Theming Plymouth — implémentation manuelle (2026-06-05).** Nouveau
      `bin/monarch-plymouth-apply` (`monarch plymouth apply`) : recolore le splash **et**
      l'écran SDDM depuis le scheme Noctalia actif (fond = `mSurface`, assets de l'invite
      déverrouillage = `mOnSurface`, barre de progression = `mPrimary`), puis **un seul**
      rebuild initramfs. **Manuel uniquement** — jamais branché sur `hooks.colorGeneration`
      (c'est la leçon du retrait réactif : le rebuild est inévitable mais doit être délibéré).
      Pendant : `monarch plymouth reset` restaure le défaut. Les variantes SDDM `-failed`
      gardent leur signal rouge (non teintées). Le splash statique livré = scheme Monarch
      dark, donc no-op visuel tant qu'on ne change pas de scheme.
      *(Non fait, par choix : suivi automatique du scheme — éviterait-on le rebuild via un
      cache d'assets pré-rendus ? Reporté tant que le besoin n'est pas avéré.)*
- [x] Bloc `light` de `Monarch.json` écrit (variante claire — commits `95101be` + `072bd32`).
- [ ] Companion **pywalfox** (Firefox) à câbler à l'install (addon + native host).

## Inconnus à valider en VM (récap)
- **Chemins de sortie des templates intégrés** (kitty/foot/ghostty/btop/helix) → pour Phase 3.
- ~~`hooks.colorGeneration` se déclenche bien à chaque changement de scheme.~~ ✅ confirmé en source
  (fire sur `onColorsGenerated`, arg `$1=dark|light`).
- ~~Hot-reload de `settings.json` (`wallpaper.directory`) à chaud.~~ ✅ confirmé en source
  (`FileView watchChanges` + reload sur remplacement atomique). Reste à confirmer empiriquement en VM.
- Pas de boucle : `wallpaper set` ne régénère pas les couleurs (car `useWallpaperColors=false`). ✅
  (chemin `useWallpaperColors` shunté dans `HooksService`, pas de re-déclenchement colorGeneration).
- IDs de template pour vscode / firefox ; neovim/obsidian natifs ou non.
- Le bloc `terminal` des schemes est-il consommé par les templates terminaux (fidélité ANSI) ?
