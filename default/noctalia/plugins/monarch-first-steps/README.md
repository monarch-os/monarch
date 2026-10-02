# Premiers pas

Un guide facultatif pour découvrir Monarch, proposé une seule fois à la première
ouverture de session après une installation neuve.

## Ouvrir le guide

Dans **monarch-menu → Documentation → Premiers pas**, ou avec :

```bash
monarch setup first-steps
```

Le menu est accessible avec **Win + Alt + Espace**. Le guide reprend la dernière
étape visitée. Pour reprendre depuis l’accueil :

```bash
monarch setup first-steps reset
```

## Parcours

1. **Se repérer** : les raccourcis réellement configurés et leur liste complète.
2. **Choisir son style** : le sélecteur de thèmes existant et les fonds d’écran.
3. **Logiciels et outils cyber** : le catalogue général Software, le catalogue
   Software → Cyber et l’installation de Burp Suite, RF Swift et SecLists.

La documentation générale et le raccourci de monarch-menu restent visibles.
Caido et Exegol sont fournis avec Monarch. Fermer un panneau exploré ramène à
la même étape du guide.

Les installations démarrent au clic sur Installer, dans un terminal qui permet
de suivre leur progression. Burp Suite propose Community ou Pro. Les outils
présents affichent ✓ Installé ; une installation affiche En cours. Une seule
installation peut être lancée à la fois. Le verrou suit les processus de
l’installation ; après une interruption ou un redémarrage, un état périmé est
récupéré au prochain contrôle ou lancement. Les erreurs restent détaillées dans
le terminal.

Le guide reste ouvert au clic extérieur et avec Échap. La croix, Passer et
C’est parti le ferment. Le bureau reste utilisable autour du guide.

## Première session et état

`monarch-provision-user` prépare l’ouverture du guide uniquement lors de
l’initialisation d’un nouvel utilisateur. `monarch-provision-first-run`, lancé
par Niri au début de la session, l’ouvre après la configuration et l’activation
des plugins Noctalia.

Le guide attend un bureau disponible et déverrouillé. Son affichage est confirmé
par le plugin avant de consommer la première proposition. Si Noctalia n’est pas
prêt, si le bureau reste occupé ou si l’ouverture échoue, la proposition reste
en attente et est retentée à la session suivante sans refaire la configuration.

L’état est conservé dans `$XDG_STATE_HOME/monarch/first-steps`, soit
`~/.local/state/monarch/first-steps` par défaut :

- `pending` : première proposition en attente ;
- `shown` : guide déjà affiché, automatiquement ou manuellement ;
- `progress` : dernière étape visitée ;
- état et résultat de la dernière installation d’outil.

Fermer ou passer le guide n’efface pas le marqueur `shown`. La commande `reset`
relance la visite manuellement sans réactiver son ouverture au démarrage. Les
utilisateurs déjà configurés conservent l’accès dans le menu sans proposition
automatique lors d’une mise à jour.

```bash
monarch setup first-steps state
```

Le runtime installé peut rester en lecture seule : le guide utilise les plugins
livrés avec Monarch et écrit uniquement dans l’état utilisateur.

## Validation

Les tests isolés couvrent l’ouverture depuis la vraie étape de première session,
la proposition unique, la reprise manuelle, le verrouillage et l’indisponibilité
du bureau, les ouvertures non confirmées, les tentatives concurrentes et le
cycle des installations avec des installateurs de substitution.

Le rendu des cinq pages, les visites des panneaux existants et le comportement
des fermetures ont été vérifiés sur Noctalia 5.1.0 et Niri 26.04. Les installations
réelles utilisent les scripts Monarch existants.
