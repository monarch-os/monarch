# Audit d'écart Omarchy Quattro 4.0.0–4.0.2

## Conclusion

La migration Noctalia v5 couvre l'essentiel de l'expérience Quattro 4.0.0 et
reprend déjà plusieurs corrections de 4.0.1 et 4.0.2. Une nouvelle lecture des
tags met néanmoins en évidence des écarts qui n'étaient pas tous visibles dans
le précédent audit.

Les écarts actionnables sont, par ordre de priorité :

1. sécuriser la publication Plymouth/SDDM ;
2. désactiver les mots de passe SSH après validation d'une clé, puis réconcilier
   les installations où SSHD est déjà actif ;
3. cesser d'accorder le groupe `input`, retirer le sudoers `asdcontrol` sans
   argument contraint et retirer `cups-browsed` ;
4. porter la frontière de montage et les validations de la Windows VM ;
5. durcir les webapps et le quoting des helpers d'installation ;
6. borner `supergfxctl`, reconnaître les panneaux `LVDS` et réconcilier un
   ancien `wpa_supplicant` masqué ;
7. corriger la connexion Wi-Fi OWE et livrer réellement le cycle opt-in du
   Docker sans sudo que la branche documente déjà ;
8. restaurer les speaker tunings XPS et stabiliser le backend de mots de passe
   Chromium ainsi que la résolution du navigateur par défaut ;
9. restaurer la reprise contrôlée des mises à jour Pacman bloquées ;
10. ajouter l'acceptance sécurité sur arbre installé et le scanner de heredocs
   privilégiés ;
11. compléter le helper Apple Display (cache privé, retry, lecture et OSD).

Les points 1 à 5 confirment le premier audit. Les points 6 à 8 sont les apports
principaux de cette seconde passe sur les releases 4.0.x.

## Périmètre et méthode

Sources primaires locales :

- dernier stable avant Quattro : `v3.8.1@82f99928d` ;
- `v4.0.0@f0020448c` ;
- `v4.0.1@13f18b2cb` ;
- `v4.0.2@346e69e1c` ;
- cible Monarch : `origin/noctalia-v5@ff9f94293`.

Les plages relues sont `v3.8.1..v4.0.0` (784 commits de premier parent,
1 871 fichiers modifiés), `v4.0.0..v4.0.1` (35 commits, 120 fichiers) et
`v4.0.1..v4.0.2` (28 changements de premier parent, 167 fichiers). Les tags,
leurs commits, les diffs et le manuel embarqué sous `manual/` constituent les
sources de vérité ; les intitulés de PR ne sont utilisés qu'en complément du
code livré.

Chaque entrée est classée comme suit :

- **manquant actionnable** : propriété utile et transposable à Monarch ;
- **couvert/équivalent** : même propriété, éventuellement par Niri ou Noctalia ;
- **non applicable** : correctif propre au shell QML/Hyprland ou à du code absent ;
- **écart produit délibéré** : fonctionnalité connue que Monarch ne souhaite
  pas reconstruire aujourd'hui.

## 4.0.0 — Quattro

### Manquants actionnables

| Sujet | Source Quattro | État de `noctalia-v5` | Action |
|---|---|---|---|
| Détection GPU hybride bornée | `78d322484`, `bin/omarchy-hw-hybrid-gpu` | `bin/monarch-hw-hybrid-gpu` appelle encore `supergfxctl -s` sans délai maximal. Ce garde est exécuté par `trigger.hardware.hybrid-gpu` dans `default/monarch/monarch-menu.jsonc` : un daemon figé peut donc bloquer l'évaluation du menu. | Porter le `timeout --kill-after`, avec repli sur le comptage PCI. |
| Panneaux internes LVDS | `090574e3a`, helpers `omarchy-hyprland-monitor-*` | `bin/monarch-niri-monitor-internal`, `-internal-mirror`, `monarch-hw-recover-internal-monitor`, `monarch-hw-external-monitors` et une branche de `monarch-display-brightness` ne reconnaissent que `eDP`. | Centraliser la classification des connecteurs internes et couvrir au moins `eDP`, `LVDS` et les panneaux internes pertinents exposés par DRM/Niri. |
| Reprise d'une mise à jour bloquée | `864b0d050`, `5ca3030c5`, `bin/omarchy-update-system-pkgs-when-conflicted` | `bin/monarch-update-system-pkgs` exécute seulement `pacman -Syyu --noconfirm`. Il ne met pas en quarantaine transactionnelle les fichiers non possédés et ne redonne pas à l'utilisateur la décision sur un conflit de paquets. | Porter le rapport d'erreurs, la quarantaine hors des répertoires actifs, le rollback par trap et le retry explicitement marqué. |
| Réparation de `wpa_supplicant` masqué | `6fad76184`, migration `1786567036.sh` | `install/hardware/network.sh` désactive iwd mais ne démasque pas `wpa_supplicant`; aucune reconciliation ne répare les installations issues de l'ère iwd. | Ajouter une reconciliation idempotente, y compris le masque runtime et le redémarrage ciblé de NetworkManager si Wi-Fi est `unavailable`. |
| Speaker tuning XPS réellement installable | `aa9f0c54c`, `a466dcc04`, `bin/omarchy-audio-tuning`, `default/audio/tunings/dell-xps-2026/` | `install/hardware/speaker-tuning.sh` appelle `monarch-audio-tuning match`, mais ce helper et les assets/unités de tuning n'existent pas dans la branche. Le `if` échoue silencieusement : `lsp-plugins-lv2` n'est pas installé et aucun sink corrigé n'est créé. | Porter le helper, le service utilisateur, le graphe LV2 et les profils matériels, ou retirer le leaf mort si cette amélioration audio est rejetée. |
| Backend de secrets Chromium déterministe | `a1e0875eb`, `config/chromium-flags.conf`, migration `1784508556.sh` | Le flag Monarch n'a pas `--password-store=gnome-libsecret` et aucune reconciliation ne l'ajoute aux flags Chromium/Brave/Chrome/Edge existants. Le backend peut donc basculer vers `basic` et rendre cookies/login existants illisibles. | Épingler `gnome-libsecret` dans le défaut et réconcilier les fichiers existants seulement s'ils ne choisissent pas déjà explicitement un backend. |
| Fallback du navigateur par défaut | `659340334`, `bin/omarchy-launch-browser` | `monarch-launch-browser` consulte uniquement `xdg-settings get default-web-browser`, sans vider un éventuel `BROWSER` récursif et sans fallback `xdg-mime query default x-scheme-handler/https`. `monarch-launch-webapp` a la même hypothèse. | Centraliser la résolution du desktop-id, unset `BROWSER`, fallback HTTPS, valider l'Exec trouvé et réutiliser le helper pour browser/webapp. |

Le helper de reprise Pacman est complémentaire des protections déjà portées par
`55590ba42` et `e7c00ab34` : le verrou, le contrôle d'espace, le prune préalable,
l'inhibiteur et le hook ALPM empêchent des mises à jour dangereuses, mais ils ne
réparent pas une transaction légitime bloquée par un vestige non possédé.

### Couvert ou équivalent

| Domaine Quattro | Preuve côté Monarch |
|---|---|
| Shell intégré : barre orientable, launcher/menu, notifications, lock, OSD, clipboard, audio, Bluetooth et contrôle center | Noctalia v5 remplace le shell QML. La position de barre est portée par `21d1f49eb`; le menu déclaratif et sa navigation par `08cd750f1` et `699314fd1`. Les correctifs QML fins ne doivent pas être cherry-pickés. |
| Réseau et affichage | Les panneaux Monarch ont été portés dans `e0c08d596`, `caeab7218`, `95e039263` et `db6333294`. DDC/CI, échelle, on/off, taille du texte, Wi-Fi, DNS, QR et diagnostics sont présents. |
| Capture QR, sélection de région et webcam réellement capturable | `a979679ab`, `bin/monarch-capture-qr`, `bin/monarch-hw-webcam` et `c1d9b1a91`. Le QR reste marqué sensible dans le presse-papiers. |
| Agents, agent par défaut, consommation et diagnostic de crash | `0920b44b5`, `62d0e93ab`, `0b3e68b1a9` et `default/noctalia/plugins/monarch-agents/`. La branche accepte davantage d'agents que Quattro et lance Claude/Codex en auto-review. |
| Crash capture opt-in/out | `bin/monarch-toggle-crash-capture`, le garde de menu et `default/systemd/user/monarch-crash-watch.service` correspondent à `30f8f191c`. |
| Taildrop/Tailscale | `5c68ac265` fournit réception persistante, réservation de noms sans écrasement, notification ouvrable, envoi et gestion d'opérateur. |
| Rappels, batterie faible, météo à la demande et profils d'énergie | `bin/monarch-reminder`, `monarch-battery-monitor`, `monarch-weather-status` et les unités utilisateur couvrent les usages. |
| Sécurité de détection fingerprint | `bin/monarch-hw-fingerprint` contient les cas FPC/ELAN et exclut `usbfs` comme driver noyau, équivalents à `a9c159a1f` et `970ec26bb`. |
| Mises à jour transactionnelles | `55590ba42` et `e7c00ab34` portent garde Pacman, verrou, espace libre, prune avant snapshot et cycle d'inhibition. |
| Themes Quattro et bundles distants | Les palettes sont dans `config/noctalia/palettes`; `ba2cc50fc` ajoute des bundles schema-1, sans code, sans symlink, validés puis publiés atomiquement. `bin/monarch-theme-bundle` refuse options et transport helpers exécutables avant `git clone`. |
| Application templates | Noctalia rend les catalogues builtin/community; `ab04cf5bb` documente les templates locaux natifs. Monarch ne doit pas restaurer le renderer Quattro. |
| Windows VM de base | Installation, lancement RDP, attente du boot courant, contournement Kerberos et adaptation de l'échelle Niri sont présents dans `bin/monarch-windows-vm`; le durcissement 4.0.2 reste manquant. |
| Factory reset et provisionnement différé | `bin/monarch-system-factory-reset*`, `monarch-provision-owner` et `install/provisioning/` conservent ce flux, avec une architecture propre à l'ISO Monarch. |
| NVIDIA KMS | `etc/mkinitcpio.conf.d/monarch_hooks.conf` reprend la suppression conservatrice de `kms` uniquement sur une machine NVIDIA-only avec early KMS, issue de `ecd57bcee`. |

### Non applicables

- Les fixes de lifecycle Quickshell, hot reload, QObjects, tailles de surfaces,
  popup tray, drag de barre, `o.shell_succeeds()` et chemins Hyprland concernent
  exclusivement `shell/**/*.qml` ou l'API Hyprland de Quattro.
- Les races de notification, le décodage du clipboard, le calendrier et le
  chargement WebP de Quattro sont des bugs de son implémentation QML. Monarch
  délègue ces services au daemon Noctalia v5.
- Les correctifs de clamshell et de scaling qui réécrivent une règle Hyprland ne
  se transposent pas à Niri. Seule la classification matérielle `LVDS` reste
  portable et est donc classée actionnable plus haut.
- `omarchy-dev-font` sert la fonte d'icônes du shell Quattro. Les plugins Luau
  Monarch emploient les icônes et assets Noctalia.

### Écarts produit délibérés

- Le lifecycle complet des plugins Quattro (add/clone/edit/enable/disable/remove
  avec fallback vers le builtin) n'existe pas en Noctalia v5. Le panneau natif
  reste la source de vérité ; le clone éditable atomique demeure différé.
- Les panneaux Dropbox et Sunshine ne sont pas repris. Dropbox est différé et
  Sunshine reste un chantier indépendant.
- La météo et la fenêtre active ne sont pas des widgets par défaut; il n'y a pas
  de widget microphone dédié. L'audio natif Noctalia est conservé.
- Le cycle de format d'horloge et l'accès direct au fuseau depuis le widget ne
  sont pas portés. Monarch a explicitement rejeté les presets à secondes tant
  que Noctalia réveille toute la barre chaque seconde.
- L'architecture de shell et plugins QML utilisateur de Quattro reste hors scope.

## 4.0.1 — maintenance et backports sécurité

### Manquants actionnables

| Sujet | Source Quattro | État de `noctalia-v5` | Action |
|---|---|---|---|
| Wi-Fi OWE sans mot de passe | `8b979e0c4`, `shell/plugins/panels/network/Model.js` | `monarch-wifi-list` conserve bien `OWE` comme sécurité, mais `shared.isSecured()` ne considère ouvert que `"open"`; le panneau affiche donc un champ mot de passe et n'appelle pas directement `monarch-wifi-join`. | Traiter explicitement OWE comme chiffré sans credentials et tester l'absence de prompt. |
| Opt-in Docker sans sudo complet | `c0b593b34`, `7b8978081`, `c7af36d0a`, `bin/omarchy-sudo-docker`, `-setup-security-sudoless-docker`, `-remove-*` | Monarch ne met plus l'utilisateur dans `docker`, ce qui est correct. Mais `install/config/docker.sh`, `monarch-provision-owner` et les tests annoncent une commande opt-in qui n'existe pas; le menu n'expose aucun toggle et les consommateurs ne partagent pas de helper `sudo-docker`. | Soit porter le trio helper/setup/remove avec avertissement et reboot requis, soit supprimer toute promesse d'opt-in et corriger les messages Windows VM. |
| Sortie speedtest indépendante de la locale | `5c2fb68c0`, `shell/Ui/SpeedTestOverlay.qml` | `bin/monarch-network-speedtest` produit un protocole machine via `awk printf`, sans `LC_NUMERIC=C`; sous une locale à virgule il peut émettre `1,2`. Le plugin fait `tonumber(line)`, qui peut alors classer la mesure comme erreur. Son `string.format` de présentation dépend également de la locale du daemon, sans politique explicite. | Forcer une forme canonique à point sur stdout et tester une locale à virgule; localiser ensuite uniquement la présentation, si l'API Luau le permet. |
| Retrait du reset sudo | `7fa32bb98` | `bin/monarch-sudo-reset` existe toujours et exécute `su -c "faillock --reset --user $USER"`. Quattro a supprimé cette commande de session ordinaire. | Retirer la route et réconcilier l'ancien binaire packagé. |

### Couvert ou équivalent

| Changement 4.0.1 | Classement et preuve |
|---|---|
| FIDO2 sans staging prévisible (`13f18b2cb`) | **Couvert** par `2705406cf`, `bin/monarch-setup-security-fido2`, son remove sûr et leurs tests. |
| `PATH` privilégié du DNS (`c6d676f23`) et fallback polkit (`2487fbcce`) | **Couvert** par `2705406cf` et `bin/monarch-dns`. |
| Actions de notification comme argv (`286b8c2b1`) | **Couvert** par `0c8df39c4` et l'interface unifiée `monarch-notification-send --action`. |
| Réception Taildrop qui attend (`07adef8a5`) | **Couvert** : `tailscale file get --wait`, boucle persistante, staging et annonce dans `bin/monarch-tailscale-receive`. |
| Refus des git transport helpers (`e713ff316`, `b3028f9bd`) | **Équivalent** pour la seule surface distante Monarch : `monarch-theme-bundle` allowliste HTTPS/SSH/file/scp, place `--` avant l'URL et refuse `ext::`. L'autre consommateur upstream, plugin-add, est absent par décision produit. |
| Theme distant incapable d'exécuter du code (`f2a2973de`) | **Plus strict** : bundles déclaratifs, aucun exécutable/symlink/fichier hors schéma et dépôt `.git` supprimé après provenance. |
| Correctif psmouse non fatal (`2b1d3c460`) | **Couvert mot pour mot** dans `install/hardware/fix-synaptic-touchpad.sh`. |
| Windows VM : logs du boot courant et Kerberos (`84336759c`) | **Couvert** dans `bin/monarch-windows-vm`, adapté à l'échelle Niri. |
| Auto-review Claude/Codex (`5f0704a0f`) | **Couvert** dans `bin/monarch-agent` (`--permission-mode auto`, `--approve-for-me`). |
| Réparation `foot.ini` (`1867dcaa5`) | **Couvert pour le défaut** : vraie section `[text-bindings]`. La migration historique exacte n'est pas utile si la reconciliation v5 remplace seulement les fichiers qu'elle possède. |

### Non applicables ou écarts délibérés

- L'injection d'un nom USB dans du Lua (`2e989e35e`) et la correction
  `o.shell_succeeds()` sont Hyprland-only. Monarch ne persiste pas un nom de
  périphérique dans une source Luau/Niri.
- Le host Chromium yt-dlp et son titre vidéo (`64c5c02f5`) ont été retirés : la
  surface vulnérable n'existe plus.
- Les correctifs WebP, UTF-16 clipboard, calendrier et press-and-hold de la
  barre corrigent le shell QML Quattro, pas Noctalia v5. Le code précis du dial
  speedtest est lui aussi QML-only, mais l'invariant de locale révèle un bug
  distinct dans le protocole texte Monarch, classé actionnable plus haut.
- La correction `Clone Plugin` confirme un écart produit déjà accepté, pas un
  bug dans une commande Monarch existante.
- `mise-bin` est déjà la forme installée par la base Monarch; les wrappers
  `monarch-mise-install` protègent aussi leurs cibles et quotent package/binaire.

## 4.0.2 — vague de hardening

### Manquants actionnables

| Sujet | Source Quattro | État de `noctalia-v5` | Action |
|---|---|---|---|
| Publication Plymouth/SDDM | `bffc6a2a5`, `bin/omarchy-plymouth-*`, `refresh-plymouth`, `refresh-sddm` | `monarch-refresh-plymouth` copie récursivement depuis `${MONARCH_PATH}` sous sudo. `monarch-refresh-sddm` fait `rm -rf`/`cp -r` puis rend `theme.conf` et `logo.png` `0666`. Les outputs de l'unlock gallery sont donc modifiables par tout utilisateur et deviennent source d'une publication privilégiée. | Adopter une source validée, un staging root privé, des destinations fixes, des types/owners/modes vérifiés et un rename atomique. Garder la génération utilisateur séparée de la publication root. |
| SSHD key-only et migration | `ff4cf8afb`, `ebd648038`, `0e1ce609d`, `346e69e1c` | `monarch-setup-security-sshd` valide et installe les clés, mais n'écrit aucun drop-in désactivant `PasswordAuthentication`/`KbdInteractiveAuthentication`. Aucune reconciliation ne durcit un SSHD déjà installé. | Après clé effective : installer le drop-in, valider `sshd -t`, vérifier le résultat case-insensitive avec `sshd -T`, rollback si inefficace, reload. Réconcilier sans fermer un serveur password-only qui n'a aucune clé. |
| Groupe `input` global | `ff4cf8afb`, suppression de `install/hardware/input-group.sh` | Monarch conserve ce script, enregistre `input` au provisionnement et l'accorde au propriétaire. | Retirer le grant par défaut et sa reconciliation; accorder les accès spécifiques via udev/groupes minimaux pour les seuls outils qui en ont besoin. |
| Sudoers `asdcontrol` | `ff4cf8afb`, suppression de `etc/sudoers.d/omarchy-asdcontrol` | `%wheel ALL=(ALL) NOPASSWD: /usr/bin/asdcontrol` autorise tous les arguments. | Supprimer le grant générique. Si le sans-mot-de-passe est requis, publier un wrapper root à grammaire fermée et device validé. |
| `cups-browsed` | `51af7bf79`, puis retrait final `a73a312e1` | Monarch installe `cups-browsed`, l'active et livre `CreateRemotePrinters Yes`. Quattro a abandonné son premier sandboxing comme insuffisant et retire finalement le service. | Retirer paquet/config/service et nettoyer prudemment les queues `implicitclass` créées automatiquement. |
| Webapps | `be730884f`, `7678e5b0d`, `f8e35ec65` | `monarch-webapp-install` accepte tout schéma explicite, les `/` dans le nom, interpole directement les champs Desktop Entry et compose `Exec` comme source textuelle. L'icône téléchargée n'est pas vérifiée MIME. Remove reconstruit les chemins à partir du label. | Limiter à HTTP(S), valider le nom/path, sérialiser les valeurs Desktop Entry, préserver URL/argv, vérifier l'image et indexer le launcher réellement créé. |
| Windows VM mount boundary | `2421e76fb`, `bin/omarchy-windows-vm` et tests dédiés | Compose mutable dans `$HOME`, credentials extraits au grep, mounts directs, options faiblement validées, suppression récursive et absence de verrou. | Porter l'ensemble des propriétés 4.0.2 : résolution fiable du propriétaire, staging/config protégés, validation YAML/credentials, mounts bornés, sérialisation et migrations. |
| Quoting des install helpers | `47ce81ebc` | `monarch-install-app` et `monarch-install-and-launch` réinjectent encore `${packages}` brut dans une commande shell. | Découper la liste puis `%q` chaque argv, comme Quattro; appliquer aussi au nom/message. |
| Apple Display | `9c1ec524c` | Le helper Monarch redétecte à chaque appel et sait seulement écrire. Il manque cache privé sous `XDG_RUNTIME_DIR`, contrôle du character device, retry après hotplug, lecture courante, `--no-osd` et OSD. | Porter le helper, en même temps que la suppression du sudoers générique. |
| Acceptance sécurité et scanner privilégié | `cf3d69c38`, `6f8b62f04`, `f802ae107` | Les commits Monarch `8b36b9a3d` à `ff9f94293` nettoient les artefacts historiques, mais la suite ne contient ni scanner de heredocs privilégiés ni acceptance de l'arbre installé couvrant owners/modes/sudoers/services. | Ajouter les deux gardes. Exécuter l'acceptance sur ISO/VM installé, pas seulement contre le checkout. |

### Couvert ou équivalent

| Changement 4.0.2 | Classement et preuve |
|---|---|
| Chromium first-run/EULA (`159163bb1`) | **Couvert** : `install/config/theme-system.sh` écrit `distribution.require_eula=false` ainsi que les deux `color_scheme=0`. |
| Browser policy directories et trap (`da0fe6d89`, `3bb986724`) | **Couvert** par `977f0591a`, `install/helpers/browser-policy.sh`, `bin/monarch-theme-set-browser-policy` et la reconciliation `install/reconcile/browser-policy.sh`. |
| Signatures du dépôt (`294c38a2f`) | **Couvert** : `default/pacman/pacman.conf` impose `SigLevel = Required DatabaseOptional`; le `SigLevel = Never` restant est limité au bootstrap matériel avant installation des clés. |
| Sudoers timezone contraint (`1082b7864`) | **Couvert exactement** par `etc/sudoers.d/monarch-tzupdate`, regex à argument unique. |
| Codex usage 0.149 (`880605f22`) | **Couvert** par `3e1d8f4bb`. |
| Nettoyage des fichiers privilégiés historiques (`cf3d69c38`) | **Couvert fonctionnellement** par la chaîne Monarch `8b36b9a3d`, `164e50c3a`, `50ee0c758`, `823488f46`, `147a0bbdd`, `ff9f94293`. Monarch adopte les fichiers runtime possédés puis retire sudoers/udev/restes v4 avec des gardes de type et provenance. |
| Noms de thèmes interprétés par le shell (`521779b11`) | **Plus strict** pour les bundles : id, nom, chemins, type MIME, contenu et modes sont validés avant publication; aucun hook distant n'est autorisé. |

### Non applicables ou délibérés

- Le scanner de `Text.RichText`/chargements HTTP dans les notifications et les
  changements QML de `2645b82bc` visent le renderer Quattro. Les labels Luau de
  Noctalia ne sont pas ce code. Le garde générique reste intéressant seulement
  si Monarch se remet à rendre du rich text distant.
- Le fix du shim Copy URL (`92c8f8773`) est non applicable : l'extension et son
  host ont été retirés.
- Les très nombreux changements `shell/Ui/*.qml` de 4.0.2 sont des conséquences
  du hardening QML, pas une liste de composants à porter.
- Le canal `rc` et sa config Pacman (`07579f5e9`) sont un écart produit assumé :
  Monarch supporte `main|dev`.
- Le correctif de navigation de l'acceptance menu (`9aa0545c2`) ne change aucune
  fonctionnalité runtime Monarch.

## Migrations et reconciliation : synthèse

La nouvelle architecture de reconciliation de `4f6434e4f` est mieux adaptée à
Noctalia v5 qu'une copie des migrations timestampées de Quattro. Il faut donc
porter les **invariants**, pas les fichiers de migration :

| Invariant 4.0.x | État Monarch |
|---|---|
| FIDO2 atomique et DNS à `PATH` sûr | Couvert. |
| Browser policy root-owned et absence de contenus non fiables | Couvert. |
| Adoption/nettoyage des anciens fichiers sudoers/udev/runtime | Couvert par #191–#196. |
| Docker absent des groupes par défaut | Couvert, mais le flux opt-in annoncé est absent. |
| `input` absent des groupes par défaut | Manquant. |
| SSHD existant durci sans lockout | Manquant. |
| `cups-browsed` retiré et queues implicites nettoyées | Manquant. |
| Ancien masque `wpa_supplicant` retiré | Manquant. |
| Config Windows VM ancienne migrée vers une frontière protégée | Manquant. |
| Publication Plymouth/SDDM sans source utilisateur privilégiée | Manquant. |

## Découpage recommandé

Les changements devraient rester séparés pour conserver des frontières de
review nettes :

1. publication système Plymouth/SDDM ;
2. SSHD setup + reconciliation ;
3. posture matériel/service (`input`, `asdcontrol`, `cups-browsed`) ;
4. Windows VM ;
5. webapps ;
6. helpers d'installation ;
7. fiabilité hardware/réseau (`supergfxctl`, LVDS, OWE, wpa_supplicant) ;
8. speaker tuning XPS et résolution/secret-store browser ;
9. Docker opt-in ou suppression explicite de cette promesse ;
10. reprise Pacman ;
11. acceptance sécurité et scanner privilégié.

Ce rapport est une analyse statique. Aucune implémentation ni validation sur la
VM n'a été effectuée.
