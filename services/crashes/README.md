# Collecte des crashs Monarch

Worker Cloudflare pour les rapports volontairement envoyés depuis Monarch.
R2 conserve le JSON filtré ; D1 indexe les occurrences et les regroupe par
application, signal, version du paquet et les huit premières frames. Ce
regroupement reste une indication : des backtraces absentes ou incomplètes
peuvent rassembler des causes différentes.

L'API, le tableau de bord et l'envoi depuis le panneau Monarch sont implémentés.
Le service reste à déployer ; la collecte est désactivée dans les defaults.

## Développement local

Node.js 22 ou plus récent :

```bash
cd services/crashes
npm ci
npm run db:local
npm run dev
```

Le serveur écoute uniquement sur `127.0.0.1:8787`. L'environnement `local`
autorise le tableau de bord sur une adresse de boucle locale ; cette exception
ne fonctionne pas avec un nom de domaine public. D1 et R2 restent locaux.

```bash
npm test
npm run test:integration
npm run check:deploy -- --env=''
```

Le test d'intégration lance un Worker isolé sur le port 18787, migre une base D1
temporaire, utilise R2 local et vérifie l'envoi depuis le véritable client Bash.
Les exemples et les fixtures sont synthétiques. Il n'envoie rien à Cloudflare.

## API

| Route | Accès | Résultat |
|---|---|---|
| `GET /v1/status` | Public | Disponibilité, schéma et durée de conservation |
| `POST /v1/reports` | Public, limité | Référence `MCR-…` et lien unique du rapport |
| `GET /admin/` | Mainteneurs | Tableau de bord avec groupes et détails |
| `GET /admin/reports/<id>` | Mainteneurs | Page d'une occurrence, partageable dans un ticket |
| `GET /admin/api/groups?offset=0` | Mainteneurs | 50 groupes et totaux |
| `GET /admin/api/groups/<fingerprint>` | Mainteneurs | 50 derniers rapports du groupe |
| `GET /admin/api/reports/<id>` | Mainteneurs | Rapport détaillé |

L'envoi exige `Content-Type: application/json` et `Idempotency-Key`, un UUID v4
aléatoire conservé avec l'aperçu local. Une nouvelle tentative du même envoi
renvoie la même référence et le même lien ; réutiliser sa clé avec un contenu différent est
refusé. Deux envois distincts au contenu identique restent deux occurrences.
Le corps est limité à 64 Kio, y compris sans `Content-Length`.

La réponse contient `reference` et `url`. Le chemin du lien utilise le SHA-256
complet de la clé d'envoi aléatoire, tandis que la référence courte sert à
l'affichage. Le bouton **Copier le lien du crash** conserve cette URL après
réouverture du panneau, sans renvoyer le rapport.

Partager le lien dans une issue GitHub ne rend pas son contenu public : la page,
ses fichiers et les API de consultation exigent Cloudflare Access. Le Worker
s'exécute avant les assets et vérifie le JWT avant de les servir. Après la purge,
la page affiche que le rapport est indisponible ou a expiré ; joindre son lien
à un ticket ne prolonge pas sa conservation.

Le serveur accepte uniquement le schéma du rapport Monarch et rejette les
champs supplémentaires. Il n'effectue aucune symbolication de dump mémoire.
Les chemins masqués côté client ne garantissent pas l'absence de toute donnée
personnelle : l'utilisateur doit consulter le rapport avant de confirmer.

## Déploiement

Les ressources sont déclarées dans `monarch-iac/crashes.tf` : bucket privé sans
`r2.dev`, expiration R2, base D1 et application Access couvrant `/admin` et ses
sous-chemins. Aucun token Cloudflare n'est distribué avec Monarch.

1. Dans `monarch-iac`, renseigner `crash_collection` avec `enabled = true`, le
   domaine d'équipe `…cloudflareaccess.com` et les adresses des mainteneurs.
   Le jeton Terraform doit autoriser R2, D1 et Access Apps/Policies. Utiliser le
   workflow habituel de plan, revue puis application manuelle.
2. Exporter uniquement la sortie non secrète dédiée :

   ```bash
   terraform output -json crash_collection > /tmp/monarch-crash-infrastructure.json
   ```

3. Dans `services/crashes`, préparer la configuration :

   ```bash
   node scripts/configure.js /tmp/monarch-crash-infrastructure.json
   npx wrangler deploy --config wrangler.production.json --dry-run
   npx wrangler d1 migrations apply monarch-crashes --remote --config wrangler.production.json
   npx wrangler deploy --config wrangler.production.json
   ```

   `wrangler.production.json` est ignoré par Git. La réception est désactivée
   au premier déploiement. Le domaine proposé est `crashes.monarchlinux.com` ;
   Wrangler crée son domaine Worker après validation de l'infrastructure.
   `workers.dev` et les URL de prévisualisation restent désactivés.
4. Vérifier qu'un mainteneur peut se connecter à `/admin/`, que l'API de lecture
   refuse un client sans JWT et que `/v1/status` annonce `enabled: false`.
   Le Worker vérifie la signature, l'émetteur, l'audience et l'expiration du
   JWT Access ; un simple en-tête d'adresse e-mail n'accorde aucun accès.
5. Passer `vars.INGEST_ENABLED` à `"true"`, redéployer, puis faire un envoi
   synthétique et vérifier sa réception avant d'activer l'URL dans les defaults
   Monarch. Aucun crash réel n'est nécessaire pour la recette du service.

La recette locale ne valide pas la connexion Access réelle ni les quotas du
compte. L'application Access suppose qu'une méthode de connexion est déjà
configurée dans Cloudflare Zero Trust.

## Limites et conservation

- Dix tentatives par minute et par IP via le binding Rate Limiting. Ce compteur
  est distribué par site Cloudflare ; il ne constitue pas une limite globale.
- Mille réservations d'envoi par jour UTC, avec compteur D1 atomique partagé.
  Les échecs de stockage et certains essais simultanés consomment une réservation.
  Les requêtes invalides et les nouvelles tentatives d'un envoi déjà reçu ne
  consomment pas ce budget. Une fois atteint, la collecte répond `429`.
- Les rapports actifs sont conservés 30 jours par défaut. Une tâche horaire
  supprime jusqu'à 500 rapports expirés et envois inachevés ; R2 possède aussi
  une règle d'expiration. La suppression physique peut être différée et les
  mécanismes de récupération du fournisseur ont leur propre durée de rétention.
- Aucun IP, identifiant d'installation, environnement, ligne de commande ou
  dump mémoire n'est ajouté au rapport. Cloudflare traite les IP pour le réseau,
  Access et la limitation de débit. L'observabilité Worker est désactivée.
- Les quotas gratuits dépendent de l'utilisation totale du compte. Le budget
  applicatif ne garantit pas une facture nulle et ne protège pas des requêtes
  invalides très nombreuses qui consomment le quota Workers.

Une panne entre l'écriture R2 et la confirmation D1 laisse une entrée `pending`
qui expire après une heure. L'objet est supprimé avant l'index ; une suppression
échouée reste donc à retenter. Pour suspendre les nouveaux envois, désactiver
`INGEST_ENABLED` et redéployer en conservant les tâches de purge.

Références : [Workers](https://developers.cloudflare.com/workers/platform/limits/),
[R2](https://developers.cloudflare.com/r2/pricing/),
[D1](https://developers.cloudflare.com/d1/platform/pricing/),
[Rate Limiting](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/),
[JWT Access](https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/authorization-cookie/validating-json/).
