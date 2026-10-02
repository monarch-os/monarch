# Premiers pas — POC

Question : un petit guide facultatif, proposé une seule fois lorsque le bureau
est prêt, permet-il de découvrir Monarch sans devoir chercher dans son menu ?

Ce prototype reste sur la branche `prototype/first-steps-pr`. Il ne constitue pas
une intégration de production au premier démarrage.

## Essayer

Depuis ce worktree, dans une session Monarch avec Noctalia :

```bash
bin/monarch-dev-first-steps-prototype
```

Le lanceur charge le plugin local, ajoute une entrée temporaire
**Documentation → Premiers pas**, puis simule une première connexion.
Il affiche le guide quand Noctalia est disponible, déverrouillé et sans autre
panneau actif. Les couleurs suivent la palette de la session.

Le parcours contient :

1. **Se repérer** : `monarch-menu` avec **Win + Alt + Espace**, les raccourcis
   réellement configurés, puis leur liste complète.
2. **Choisir son style** : le sélecteur de thèmes existant.
3. **Logiciels et outils cyber** : le catalogue général Software, le catalogue
   Software → Cyber et l’installation de Burp Suite, RF Swift et SecLists.

Un accès à la documentation générale et le rappel du raccourci de
`monarch-menu` restent visibles pendant toute la visite. Caido et Exegol sont
présentés comme des outils fournis avec Monarch.

Fermer un écran exploré rouvre le guide à la même étape. Les boutons Retour et
Continuer permettent aussi de suivre la visite sans ouvrir ces écrans.
Chaque bouton Installer ouvre l’installateur Monarch existant dans un terminal.
Burp Suite propose le choix Community ou Pro. Les outils déjà présents affichent
un statut ✓ Installé. Une seule installation peut être lancée à
la fois, avec son état En cours, puis Installé après vérification. Un échec est
signalé dans le guide ; le détail reste dans le terminal.

L’installation démarre uniquement au clic sur Installer. Les écrans du catalogue
et du sélecteur conservent leurs actions Monarch habituelles.

Le panneau est persistant : les clics extérieurs, Échap et l’ouverture d’un autre
panneau ne le ferment pas. La croix, Passer et C’est parti le ferment.
Le bureau reste utilisable autour du guide.

## Rejouer et retirer

```bash
bin/monarch-dev-first-steps-prototype demo        # Rejouer l’accueil
bin/monarch-dev-first-steps-prototype first-login # Ne rien afficher si déjà proposé
bin/monarch-dev-first-steps-prototype open        # Reprendre depuis le menu
bin/monarch-dev-first-steps-prototype state       # État du POC en JSON
bin/monarch-dev-first-steps-prototype reset       # Réinitialiser le premier passage
bin/monarch-dev-first-steps-prototype cleanup     # Retirer le plugin et son entrée
```

L’état est stocké uniquement dans `.prototype-first-steps/` dans le worktree,
ignoré par Git. Aucun marqueur de provisioning réel n’est utilisé. Aucun
autostart n’est ajouté à la session locale. La commande `first-login` constitue
le point d’entrée à essayer avant un éventuel branchement à la première session.

Le plugin chargé est un lien vers ce worktree. `cleanup` retire uniquement ce
lien et le fragment de menu ajouté par le POC, en conservant le reste du fichier
d’extension. Il faut nettoyer le POC avant de supprimer le worktree.

## Résultats

Vérifiés sur Noctalia 5.1.0 et Niri 26.04 :

- affichage natif et rendu des couleurs de la session ;
- navigation entre les trois étapes et fin de la visite ;
- ouverture des raccourcis, des thèmes, du catalogue général Software et de
  Software → Cyber, puis retour au guide à la même étape ;
- clics extérieurs conservant le panneau ouvert ;
- Échap avec le focus dans le panneau conservant le guide ouvert ;
- fermeture par un clic sur la croix ;
- Passer empêchant une nouvelle proposition automatique ;
- présence du guide dans Documentation et retrait de cette entrée par `cleanup` ;
- détection des trois outils installés et affichage de leur statut ;
- lancement d’une installation, exclusion des doublons, fin et échec avec des
  installateurs de substitution dans un répertoire de test ;
- accueil, trois étapes et fin de visite visibles sans défilement dans le
  panneau de 560 × 470 ;
- raccourcis sur une ligne, avec le nom à gauche et la combinaison à droite ;
- cartes compactes, statuts Installé, documentation et navigation aux mêmes
  emplacements sur toutes les pages.

Les téléchargements et installations réels restent ceux des scripts existants.
Ils n’ont pas été exécutés pour tester le POC : les trois outils sont déjà
présents sur la session de validation.

Noctalia conserve les options du panneau lors d’un simple `config-reload`.
Le lanceur désactive puis réactive le plugin pour appliquer les changements de
manifest. Un test Wayland reproduisait la fermeture au clic extérieur avant
cette réactivation ; le même test passe après correction. Le mode persistant
permet aussi de conserver le panneau avec Échap.

La première connexion est simulée sur la session locale. Une installation
neuve et le branchement au provisioning restent à valider si ce parcours est
retenu. Le choix du contenu et du rythme de la visite reste à essayer.

Le POC confirme la faisabilité d’un guide natif facultatif, persistant et
accessible depuis le menu, qui réutilise les catalogues et installateurs
existants. Son intérêt pour la découverte du bureau reste à évaluer à l’usage.

## Maquette

[Canvas Superdesign](https://superdesign.dev/teams/35f182a2-b52e-47f7-bea6-9b67f6099aef/projects/8e87a43a-86ba-4205-8f23-cdfbf044f818?node=draft-variant-0db6ae1d-9b9f-4073-a5c9-294eaf3c53b5).
La maquette sert de référence visuelle. Le POC à évaluer est le panneau natif.
