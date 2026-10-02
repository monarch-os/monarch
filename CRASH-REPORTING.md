# Collecte des crashes Monarch

Recherche vérifiée le 2 octobre 2026, à partir de sources officielles.

## Recommandation

Le choix retenu pour Monarch est **Workers + D1 + R2 privé**, afin de regrouper la
collecte avec l'hébergement Cloudflare existant. Le service et sa procédure de
déploiement sont dans [services/crashes](services/crashes/README.md). L'historique,
l'aperçu et l'export restent disponibles localement ; chaque envoi centralisé
exige une confirmation. Le panneau et le tableau de bord sont implémentés et
testables localement ; le service reste à déployer. Chaque envoi retourne un
lien unique utilisable dans une issue GitHub, consultable par les mainteneurs
via Cloudflare Access pendant la durée de conservation du rapport.

Pour disposer immédiatement d'une plateforme avec recherche et alertes,
**GlitchTip hébergé gratuit** reste une alternative simple :
1 000 événements par mois, projets et membres illimités, hébergement européen
disponible. C'est une recommandation pour le volume initial, pas une estimation
du nombre de crashes des utilisateurs. [Tarifs GlitchTip](https://glitchtip.com/pricing/).

## Solutions

| Solution | Gratuité et limites vérifiées | Mise en œuvre pour Monarch |
| --- | --- | --- |
| GitHub Issues | Le signalement utilise le dépôt existant. Les pièces jointes texte/JSON sont acceptées jusqu'à 25 Mo ; celles d'un dépôt public sont accessibles sans authentification. | Ouvrir un brouillon, joindre le rapport exporté, laisser l'utilisateur publier. Pas de serveur de collecte à maintenir. |
| GlitchTip hébergé | 1 000 événements/mois ; projets et membres illimités. La réduction d'ingestion commence après le quota, puis le blocage est total à deux fois le quota. | Créer un projet Monarch et envoyer les rapports volontaires au format d'événement compatible Sentry. |
| GlitchTip sur notre infrastructure | Logiciel open source ; coût de serveur et d'exploitation à notre charge. PostgreSQL 14+, Docker Compose ou Helm ; 512 Mo de RAM recommandés par la documentation. | Adapté si l'on veut maîtriser l'hébergement ou dépasser le petit quota SaaS. Sauvegardes PostgreSQL, HTTPS, mises à jour et stockage restent à gérer. |
| Sentry Developer | 5 000 erreurs/mois ; un seul membre. Le plan reste gratuit après la migration de septembre 2026. L'augmentation de quota nécessite un plan payant. | Alternative hébergée valable pour un mainteneur seul ; moins pratique pour une équipe. |
| Sentry sponsorisé Open Source | Le programme existe ; les plans actuels incluent des fonctions Business. Admission et quotas doivent être confirmés auprès de Sentry. | Demander un sponsoring pour Monarch ; ne pas dépendre de son acceptation pour livrer l'historique local. |

Sources : [création d'issues et brouillon par URL](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/creating-an-issue#creating-an-issue-from-a-url-query),
[pièces jointes GitHub](https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/attaching-files),
[tarifs GlitchTip](https://glitchtip.com/pricing/),
[installation GlitchTip](https://glitchtip.com/documentation/install/),
[quotas Sentry Developer](https://sentry.zendesk.com/hc/en-us/articles/26206897429275-Changes-to-our-Developer-plan),
[limite d'un membre Sentry](https://sentry.zendesk.com/hc/en-us/articles/24593224064667),
[migration Sentry de septembre 2026](https://www.sentry.help/en/articles/16738709-changes-to-legacy-developer-plans-september-2026),
[augmentation du quota gratuit Sentry](https://www.sentry.help/en/articles/13964872-can-i-add-more-reserved-volumes-to-my-free-developer-plan),
[plans sponsorisés Sentry](https://www.sentry.help/en/articles/13964342-i-m-on-a-sponsored-open-source-non-profit-plan-but-don-t-see-business-features).

La page tarifaire Sentry n'a pas pu être chargée pendant la recherche. Les chiffres
Developer viennent du centre d'aide officiel ; l'article de septembre 2026
confirme que les quotas d'erreurs et de pièces jointes restent inchangés. Les
quotas exacts d'un sponsoring restent à vérifier dans l'offre proposée.

Sentry peut aussi être hébergé sur notre infrastructure, avec davantage de
ressources : son contrôle d'installation actuel demande quatre cœurs et 14 000 Mo
disponibles pour Docker ; le profil `errors-only` demande deux cœurs et 7 000 Mo.
Cela représente une exploitation plus importante que GlitchTip pour ce besoin.
[Contrôle officiel des ressources](https://github.com/getsentry/self-hosted/blob/master/install/_min-requirements.sh).

## Rapport de crash et dump mémoire

GlitchTip accepte les SDK compatibles Sentry. Pour Monarch, il faut convertir le
rapport local en événement : application, signal, versions, architecture,
backtrace et contexte sélectionné. Le format JSON du rapport n'est pas un protocole
d'ingestion universel ; un adaptateur doit créer l'événement attendu et gérer les
réponses réseau. [Intégration GlitchTip](https://glitchtip.com/sdkdocs/).

Les SDK natifs de Sentry et GlitchTip s'initialisent dans le code de l'application.
Ils utilisent notamment Breakpad ou Crashpad. Les traces lisibles nécessitent les
symboles de debug correspondants. GlitchTip documente l'envoi de symboles ELF,
dSYM et PDB. Cette compatibilité ne signifie pas que l'on peut envoyer n'importe
quel core ELF de `systemd-coredump` et obtenir automatiquement son analyse.
[SDK natif GlitchTip](https://glitchtip.com/sdkdocs/native/),
[SDK natif Sentry](https://github.com/getsentry/sentry-native).

Le chemin proposé pour les applications déjà installées est donc : extraction
locale de la backtrace, prévisualisation, puis transfert volontaire du rapport.
Le dump mémoire complet reste un fichier distinct : son contenu et sa taille
justifient un choix explicite et un stockage dédié si sa réception est ajoutée.
Les pièces jointes publiques GitHub ne conviennent pas à une collecte privée de
ces dumps. [Visibilité des pièces jointes GitHub](https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/attaching-files).

## Branchement ultérieur à GlitchTip

1. Créer l'organisation et un projet `monarch-desktop`, puis récupérer son DSN.
2. Conserver la collecte locale sans dépendance réseau ; ajouter un transport
   volontaire après la prévisualisation.
3. Envoyer le contexte approuvé sous forme d'événement, avec version Monarch,
   application, version du paquet et signal comme champs structurés.
4. Dédupliquer les envois locaux et limiter leur fréquence pour protéger le quota.
5. Vérifier dans GlitchTip le regroupement, les alertes et les champs reçus avant
   d'activer ce transport pour les utilisateurs.

La création du projet, le DSN et les alertes sont décrits dans la
[documentation GlitchTip](https://glitchtip.com/documentation/error-tracking/).
La conversion de rapport, la déduplication et le transport sont des choix
d'implémentation proposés pour Monarch, pas des fonctions déjà livrées.
