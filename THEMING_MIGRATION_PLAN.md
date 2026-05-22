# Plan — Déléguer le theming de Monarch à Noctalia

> Document de suivi vivant. On coche au fur et à mesure.
> Branche : `feat/niri-migration`.

## Objectif

Supprimer le moteur de thèmes maison de Monarch et déléguer le theming à Noctalia,
en acceptant le modèle de couleurs **Material / wallpaper** (pas de palette ANSI 16
couleurs taillée à la main). Noctalia devient la source de vérité couleurs +
templates + wallpaper + shell ; il ne reste qu'une fine couche Monarch pour le
système/hardware que Noctalia ne peut pas atteindre.

Élément déclencheur : le picker wallpaper de Noctalia ne scanne qu'un seul
`wallpaper.directory` et ne trouvait pas les fonds rangés par thème de Monarch.

## Décisions verrouillées

- **Modèle couleurs** : Material/wallpaper. Pas d'ANSI curated. Le moteur de
  templates Noctalia n'expose que les tokens Material-3 (`{{colors.<name>.<mode>.<format>}}`)
  + `{{image}}` (chemin wallpaper). Registre : `~/.config/noctalia/user-templates.toml`.
- **Thèmes** : on garde les 20, en schemes Noctalia discrets (option a).
  - `colorSchemes.useWallpaperColors = false` (les couleurs viennent du scheme choisi).
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
  Il gère : plymouth, RGB clavier, Chromium, et le repointage wallpaper (voir Phase 4).
- **GTK/Qt** : géré nativement par `colorSchemes.syncGsettings = true` (pas de hook/script).
- **Wallpaper / couplage thème↔fond** : conservé, mais via le `post_hook` ci-dessus.
  - `wallpaper.directory` repointé vers le dossier du scheme courant.
  - Chemin **(b)** user-writable : `~/.config/monarch/backgrounds/<scheme>/`,
    seedé à l'install depuis les fonds livrés. *(à confirmer)*
  - Le hook applique aussi un fond (`ipc call wallpaper set <path> ""`) pour que
    l'écran change vraiment, pas seulement le picker. *(à confirmer)*
  - On garde `themes/<nom>/backgrounds/` ; on supprime le reste de `themes/`.

## Questions ouvertes

- [x] **Navigateur** : les deux. Firefox → natif (Pywalfox). Chromium → hook résiduel (`monarch-theme-apply`).
- [x] Chemin wallpaper **(b)** `~/.config/monarch/backgrounds/<scheme>/` (writable, seedé à l'install).
- [x] « Le fond change vraiment » au changement de thème : oui (`ipc call wallpaper set`).

## Mapping des 20 thèmes → schemes Noctalia

Built-in Noctalia dispo : Ayu, Catppuccin, Dracula, Eldritch, Gruvbox, Kanagawa,
Noctalia (default), Nord, Rose Pine, Tokyo Night.

**Utiliser le built-in (6)** : catppuccin, gruvbox, kanagawa, nord, rose-pine, tokyo-night.
> Note : les nuances du built-in Noctalia peuvent différer légèrement des couleurs Monarch actuelles.

**Écrire un scheme Material (14)** : catppuccin-latte, ethereal, everforest,
flexoki-light, hackerman, lumon, matte-black, miasma, monarch, osaka-jade,
retro-82, ristretto, vantablack, white.

**Thèmes clairs (variante `light`)** : catppuccin-latte, flexoki-light, rose-pine, white.

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
| Plymouth (boot) | résiduel — `monarch-theme-apply` |
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
- [x] Ajoutés au défaut : `niri`, `code` (= VSCode), `pywalfox`. IDs confirmés en VM.
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
- [ ] Light themes : à la sélection d'un scheme clair, le sélecteur/hook doit poser
      `colorSchemes.darkMode=false` (et inversement pour les dark). → Phase 5.

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
- [x] `config/kitty/kitty.conf` : `include themes/noctalia.conf`.
- [x] `config/ghostty/config` : `theme = noctalia`.
- [x] `config/alacritty/alacritty.toml` : `import = [ "~/.config/alacritty/themes/noctalia.toml" ]`.
- [x] `config/btop/btop.conf` : `color_theme = "noctalia"`.
      → le symlink `~/.config/btop/themes/current.theme` (créé par theme.sh) devient inutile
      → suppression en Phase 6 (`install/config/theme.sh`).

### Phase 4 — Wallpaper
- [ ] `config/noctalia/settings.json` : section `wallpaper` (`enabled`, `directory`,
      `transitionType`, `transitionDuration`, `automationEnabled`).
- [ ] Regrouper les fonds livrés (one-shot, repo) — garder `themes/<nom>/backgrounds/`.
- [ ] `monarch-theme-apply` : repointe `wallpaper.directory` vers le dossier du scheme
      courant (chemin (b)), avec garde d'idempotence + fallback si dossier absent +
      normalisation du nom (display name → kebab-case).
- [ ] `monarch-theme-apply` : `ipc call wallpaper set <fond> ""` pour appliquer.
- [ ] `monarch-menu` Background → délègue au picker Noctalia / IPC.
- [ ] Vérifier en VM : hot-reload de `wallpaper.directory` rafraîchit le picker.

### Phase 5 — Couche résiduelle (hooks)
- [ ] `hooks.colorGeneration = "monarch-theme-apply"` + `hooks.enabled = true` (défaut Monarch).
- [ ] `monarch-theme-apply` : plymouth (depuis scheme courant), RGB clavier, Chromium, wallpaper.
- [x] GTK/Qt dark/light : natif via `colorSchemes.syncGsettings=true` (plus de script gsettings).
- [ ] `monarch-theme-apply` pose `colorSchemes.darkMode` selon le scheme (light/dark per-scheme).
- [ ] Métadonnées par scheme hors couleurs (plymouth, RGB) : où les stocker.

### Phase 6 — Démantèlement + plomberie
- [ ] `rm` scripts `monarch-theme-*` : set, set-templates, set-foot, set-gnome,
      set-browser, set-vscode, set-obsidian, set-keyboard*, colors-from-alacritty,
      list, current, install, remove, update, refresh, bg-next, bg-set, bg-install.
- [ ] `rm` `default/themed/*.tpl`.
- [ ] `rm` `themes/*/` sauf `backgrounds/` (colors.toml, btop.theme, vscode.json,
      neovim.lua, icons.theme, keyboard.rgb, previews, light.mode).
- [ ] Éditer `bin/monarch` (groupe `theme` + aide).
- [ ] Éditer `bin/monarch-menu` (Style → Theme/Background).
- [ ] Éditer `default/niri/binds.kdl` (bind menu theme `Mod+Shift+Ctrl+Space`).
- [ ] Éditer `install/config/theme.sh` (bootstrap : initial theme, symlinks btop/noctalia).
- [ ] Éditer `default/pi/agent/extensions/monarch-system-theme.ts` (ce qu'il lit).
- [ ] `test/monarch-cli-test.sh` : retirer assertions `theme set/list/current`.
- [ ] Migration de nettoyage pour les installs existantes.
- [ ] MAJ `AGENTS.md` (section Upstream Sync / theming) + `default/monarch-skill/SKILL.md`.

### Phase 7 — Validation
- [ ] `bash test/monarch-cli-test.sh` vert.
- [ ] `bin/monarch commands --check` OK.
- [ ] En VM : changement de scheme → terminaux/btop/helix/vscode/niri/wallpaper/plymouth/RGB suivent.
- [ ] Screenshot de contrôle (`monarch capture screenshot fullscreen save`).

## Inconnus à valider en VM (récap)
- **Chemins de sortie des templates intégrés** (kitty/foot/ghostty/btop/helix) → pour Phase 3.
- `hooks.colorGeneration` se déclenche bien à chaque changement de scheme.
- Hot-reload de `settings.json` (`wallpaper.directory`) à chaud.
- Pas de boucle : `wallpaper set` ne régénère pas les couleurs (car `useWallpaperColors=false`).
- IDs de template pour vscode / firefox ; neovim/obsidian natifs ou non.
- Le bloc `terminal` des schemes est-il consommé par les templates terminaux (fidélité ANSI) ?
