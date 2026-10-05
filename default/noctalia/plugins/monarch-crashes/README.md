# Crashes

Ouvrir **monarch-menu → System → Crashes** (`Win + Alt + Espace`), ou lancer :

```bash
monarch crash history
```

Le panneau affiche les 100 derniers crashes enregistrés par `systemd-coredump`
pour l'utilisateur courant, du plus récent au plus ancien. **Détails** montre le
signal et la disponibilité du dump ; **Préparer le rapport** affiche son contenu,
puis **Exporter** enregistre exactement l'aperçu dans un fichier texte privé dans
`${XDG_STATE_HOME:-~/.local/state}/monarch/crashes/reports/`.

Lorsque la collecte est configurée et disponible, **Envoyer à Monarch** ouvre
une confirmation indiquant la destination et la durée de conservation.
**Confirmer l'envoi** transmet le rapport consulté. Après réception, **Copier
le lien du crash** permet de joindre son lien unique à un ticket GitHub. Le lien
reste disponible à la réouverture du panneau ; sa consultation est réservée
aux mainteneurs authentifiés avec Cloudflare Access.

Le rapport contient l'application, la date UTC, le signal, les versions et la
backtrace enregistrée dans le journal. Les versions du système sont celles au
moment de la préparation ; la version du paquet vient du crash lorsqu'elle est
disponible, sinon du paquet actuellement installé. La backtrace est limitée à
120 lignes et les chemins personnels courants y sont masqués. Vérifier le contenu
avant de le partager.

Le dump mémoire, l'environnement, la ligne de commande et les journaux généraux
sont exclus. Aucun rapport n'est envoyé automatiquement. Le bouton **Ouvrir le
rapport** permet de le consulter dans une application locale pour le joindre
ensuite à un signalement.

Le système peut conserver un événement après suppression du dump mémoire. Le
panneau l'affiche toujours ; une backtrace absente ne signifie pas qu'aucun crash
n'a eu lieu. Les exceptions de scripts sans core dump, les arrêts normaux et les
processus tués par manque de mémoire ne sont pas couverts par cet historique.

Les notifications restent désactivables avec **Actions → Toggle → Crash Capture**
ou `monarch toggle crash-capture`. Ce réglage contrôle les notifications, pas la
conservation des événements par systemd. Sans agent IA, une notification ouvre
l'historique ; avec un agent configuré, elle propose l'analyse existante.

## Ligne de commande

```bash
monarch crash history list
monarch crash history list --json
monarch crash history report '<id>'
monarch crash history report '<id>' --json
monarch crash history export '<id>'
```

L'identifiant combine le démarrage, le PID et la date du crash pour distinguer
les événements lorsque le système réutilise un PID. `list --json` retourne
`crashes`, `limit` et `hasMore` ; `export` retourne le chemin du fichier en JSON.
Les erreurs d'accès au journal sont signalées et ne produisent pas un faux
historique vide.

Le panneau utilise `export '<id>' --stdin` pour conserver le texte prévisualisé,
même si le journal tourne entre la préparation et l'export. Cette option accepte
un rapport texte de 64 Kio maximum ; sans elle, `export` prépare un nouveau rapport.

Le service de collecte, son tableau de bord et sa procédure de déploiement
sont dans le dépôt [monarch-crashes](https://forge.cloud.y0no.fr/Monarch/monarch-crashes).

## Envoi volontaire

Le client conserve un aperçu figé et privé avant l'envoi. Il est utilisable
indépendamment du panneau :

```bash
monarch crash submit status
monarch crash submit prepare '<id>' | jq -r .text
monarch crash submit send '<id>' --confirm 'https://crashes.monarchlinux.com'
monarch crash submit copy '<id>'
```

`prepare` conserve la même version du rapport lors des réouvertures. L'envoi
ne relit pas le journal. La réponse contient une référence `MCR-…` et une URL ; les essais
après une erreur réseau utilisent la même clé pour éviter les doublons. Après
réception, le client conserve la référence et le lien et ne renvoie plus ce crash.
`copy` copie le lien dans le presse-papiers sans requête réseau.

La destination passée après `--confirm` doit correspondre à la configuration
courante. Le panneau transmet celle qu'il affiche et refuse l'envoi si elle a
changé depuis sa vérification. En ligne de commande, `--confirm` sans destination
confirme l'envoi à la destination actuellement configurée.

La collecte distante reste désactivée dans les defaults tant que le service
Cloudflare n'a pas été déployé et testé. Son URL se configure dans
`~/.config/monarch/crash-reporting.json` :

```json
{"endpoint":"https://crashes.monarchlinux.com"}
```

Le client exige HTTPS, ne suit pas les redirections et n'envoie aucun token
Cloudflare. Les rapports et références sont conservés localement dans
`${XDG_STATE_HOME:-~/.local/state}/monarch/crashes/submissions/`, avec les mêmes
permissions privées que les exports. La conservation distante est annoncée
par le service ; elle ne supprime pas ces fichiers locaux.
Une fois le rapport distant purgé, son lien indique qu'il est indisponible ou
a expiré. Un lien dans un ticket GitHub ne prolonge pas cette conservation.

Pour la recette locale uniquement, `MONARCH_CRASH_ENDPOINT=http://127.0.0.1:8787`
avec `MONARCH_CRASH_ALLOW_LOCAL=1` permet d'utiliser le Worker local. La procédure
mainteneur est documentée dans le dépôt
[monarch-crashes](https://forge.cloud.y0no.fr/Monarch/monarch-crashes).
