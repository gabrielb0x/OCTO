# Changelog

Les évolutions notables d'OCTO. Les numéros de version suivent [SemVer](https://semver.org/lang/fr/).

## [1.6.0] – 2026-09-16

### Ajouté

- **La recherche trouve enfin tous tes chats.** La barre de recherche de la barre latérale interroge aussi ton compte ChatGPT (`conversations/search`), qui cherche **dans les messages** et pas seulement dans les titres : les chats jamais ouverts sur cet iPhone remontent donc eux aussi, avec **le passage qui correspond** sous leur titre. Ce qui est déjà sur l'appareil s'affiche immédiatement, le compte répond juste après, et ouvrir un résultat ajoute le chat à l'historique et télécharge ses messages.
- **Appareils connectés** (Réglages → Sécurité et connexion → Appareils, ou depuis Confidentialité) : tous les appareils connectés à ton compte ChatGPT (`accounts/sessions`), avec leur système, la ville et le pays de leur dernière connexion, quand c'était, et les apps qui s'en servent (ChatGPT Web, Codex, l'app iOS…). Celui que tu tiens est marqué. En dessous, l'état de ta double authentification, de tes clés d'accès, de tes codes d'authentification et des alertes de connexion (`accounts/security_settings/info`, `accounts/mfa_info`). De quoi repérer une connexion qui n'est pas la tienne.
- **Ce que tes fichiers occupent dans ton compte**, dans Réglages → Stockage (`files/library/storage/usage`) : à côté de la place prise par OCTO sur l'iPhone, ChatGPT dit combien ses images, ses fichiers texte et le reste occupent dans ton compte, et sur combien.
- Les nouvelles adresses (`conversations/search`, `accounts/sessions`, `accounts/security_settings/info`, `accounts/mfa_info`, `files/library/storage/usage`) rejoignent les **raccourcis de la console** du mode développeur.

## [1.5.1] – 2026-09-16

### Modifié

- Le bouton **« Mettre à niveau » passe à gauche**, juste à côté du bouton qui ouvre les chats, comme dans l'app ChatGPT, au lieu du centre de la barre du haut.
- **Envoyer un message avec le bouton range le clavier**, et la conversation revient en bas sur la question qui vient d'être posée. La touche Retour, elle, garde le clavier pour enchaîner.

### Corrigé

- Après l'envoi d'un message, la conversation pouvait rester décalée : elle se replace une fois le clavier parti.

## [1.5.0] – 2026-09-16

### Ajouté

- **E-mail et numéro de téléphone masqués dans les Réglages**, au choix dans Confidentialité → Tes informations : toujours affichés, **affichés d'une pression** (ils repassent derrière les points au bout de 30 secondes), **masqués pendant l'enregistrement, la recopie ou le partage de l'écran** — pratique en live — ou **jamais affichés**. Seules la première lettre, l'extension du domaine et les deux derniers chiffres restent visibles, et le masquage vaut aussi pour le nom du compte quand c'est l'adresse e-mail, dans la barre latérale comme en haut des Réglages et dans Sécurité et connexion.
- **Bouton « Mettre à niveau »** en haut de l'écran pour les comptes sans abonnement, comme dans l'app ChatGPT : il ouvre la page Abonnement. Il **se désactive** dans Réglages → Apparence → Écran d'accueil.
- **Suggestions en liste** comme sur l'accueil de l'app ChatGPT (Créer une image, Écrire ou modifier, Rechercher sur le Web), au choix en pastilles de verre comme avant, et **salutation « Comment puis-je t'aider ? » optionnelle**.

### Modifié

- **Barre de saisie** : le bouton + rejoint la capsule de verre, comme dans l'app ChatGPT, et la question devient « Demander à ChatGPT ».
- L'accueil d'un nouveau chat est vide par défaut, comme dans l'app ChatGPT ; la salutation se rallume dans Apparence.
- « Afficher les suggestions » quitte Général pour la nouvelle section **Écran d'accueil** d'Apparence, où Général renvoie désormais.

## [1.4.0] – 2026-09-15

### Ajouté

- **Des réponses qui arrivent mot par mot, en fondu** : chaque mot de ChatGPT apparaît à son tour et se révèle en douceur, à un rythme plus calme qu'avant. La vitesse (lente, normale, rapide ou instantanée) se choisit dans Réglages → Apparence, avec un aperçu en direct.
- **Détection des mises à jour** : OCTO regarde sur GitHub Releases s'il existe une version plus récente (au plus toutes les 6 heures, sans aucun identifiant) et te la propose avec ses nouveautés, un bouton « Installer avec AltStore » ou « SideStore » et le téléchargement de l'IPA. La vérification se lance aussi à la main dans À propos et se coupe dans Confidentialité.
- **Page Confidentialité** :
  - les liens des réponses et des sources s'ouvrent, se copient et se partagent **sans traceurs** (`utm_source=chatgpt.com`, `fbclid`, `gclid`…) ;
  - le texte copié **reste sur l'iPhone** (pas de presse-papiers universel) et peut s'effacer tout seul après 1, 5 ou 15 minutes ;
  - les **claviers tiers sont bloqués** dans OCTO ;
  - les chats sont **masqués pendant l'enregistrement, la recopie ou le partage de l'écran**, et dans le sélecteur d'apps par défaut ;
  - **chats temporaires par défaut** au choix, et chats retirés de l'iPhone après 1 jour, 1 semaine ou 1 mois (sauf les chats épinglés) ;
  - la liste des **serveurs contactés** depuis l'ouverture d'OCTO, comptés sur l'appareil.
- **Page Apparence** : couleurs d'accentuation violet, rouge et menthe, plus **une couleur de ton choix** ; taille du texte des chats ; police (système, arrondie, serif ou monospace) ; retour à la ligne dans les blocs de code ; vibrations pendant que ChatGPT écrit. Et dans Général : **envoyer avec la touche Retour**.
- **Dictée par ChatGPT** : le micro enregistre ta voix, puis `backend-api/transcribe` l'écrit, comme la dictée de l'app ChatGPT (niveau du micro, minuteur, annuler ou valider). L'enregistrement est effacé de l'iPhone juste après. Si ChatGPT n'y arrive pas, l'iPhone la transcrit lui-même. La dictée entièrement sur l'appareil reste au choix dans Voix.
- **Gestion des données** : « Améliorer le modèle pour tout le monde » affiche **le vrai réglage de ton compte** et **se désactive depuis OCTO**, avec la même requête que le site (`settings/account_user_setting`), tout comme l'inclusion des enregistrements audio et vidéo et le réglage équivalent de Codex. OCTO relit le compte après chaque changement pour montrer ce qui a vraiment été enregistré.
- **Vérification de l'âge** : la page montre comment ChatGPT traite l'âge de ton compte (`settings/is_adult`) et explique, sources à l'appui, pourquoi il vaut mieux **ne pas faire la vérification**.

### Modifié

- **Abonnement** : sans abonnement actif, plus de date d'expiration, de facturation ni de lieu d'achat. ChatGPT garde les dates d'un ancien abonnement terminé, qui s'affichaient à tort.
- Les chats, pièces jointes et données du compte enregistrés sur l'iPhone sont **illisibles tant que l'appareil est verrouillé**, fichiers existants compris.
- La session réseau ne garde plus rien sur le disque : les cookies ne vivent que le temps d'un lancement et sont effacés à la déconnexion.
- Les envois de fichiers, comme les enregistrements de dictée, n'apparaissent pas dans le journal réseau du mode développeur.

### Corrigé

- « Améliorer le modèle pour tout le monde » pouvait s'afficher activé alors qu'il était désactivé dans le compte : OCTO lisait la politique du compte (`data_usage_for_training`) au lieu de ton choix (`training_allowed`).

### Retiré

- La page Contrôle parental.

## [1.3.0] – 2026-09-15

### Ajouté

- **Tes limites d'utilisation ChatGPT, lues en direct depuis ton compte** : OCTO appelle `conversation/init` sur `chatgpt.com/backend-api`, exactement comme le site quand il ouvre un nouveau chat, et affiche dans Abonnement combien de **Deep Research**, de **générations d'images**, d'**envois de fichiers** et de **réflexion avancée** il te reste, avec la date de réinitialisation de chaque limite.

### Précisions

- Ces fonctionnalités (Deep Research, images, fichiers…) tournent sur les serveurs de ChatGPT : OCTO montre seulement ce qu'il te reste, comme sur le site. Les réponses aux messages écrits dans OCTO passent toujours par le backend Codex de ton forfait et restent sur l'appareil. Poster un message dans un chat de `chatgpt.com` (`/f/conversation`) demande une preuve de travail « sentinel » et un défi Cloudflare Turnstile que seule la page web officielle sait produire ; ce n'est donc pas fait, et rien n'est envoyé à un service d'analyse.

## [1.2.0] – 2026-09-15

### Ajouté

- **Réglages organisés comme l'app ChatGPT** : Personnaliser ChatGPT (Personnalisation, Mémoire, Plugins), Compte (adresse e-mail, numéro de téléphone, abonnement, restaurer les achats, vérification de l'âge), Thème, Paramètres de l'application (Général, Notifications, Voix, Contrôle parental, Protection, Sécurité et connexion, Contrôle à distance, Stockage, Gestion des données, Gestion des publicités) et Aide (signaler un problème, centre d'assistance, À propos).
- **Thème Système, Clair ou Sombre** et **couleur d'accentuation** (bleu, vert, jaune, rose, orange) pour tes messages et le bouton d'envoi.
- **Abonnement** : forfait, date de renouvellement, lieu d'achat et limites d'utilisation. « Restaurer les achats » recharge ton forfait depuis ton compte.
- **Protection** : verrouillage par Face ID (ou code) avec un délai au choix, et contenu masqué dans le sélecteur d'apps.
- **Notifications** quand ChatGPT a fini de répondre alors qu'OCTO est en arrière-plan, avec ou sans aperçu.
- **Voix** : choix de la voix de lecture parmi celles de l'appareil, écoute d'un exemple et délai avant l'envoi en mode vocal.
- **Stockage** : place prise par les chats, les pièces jointes et le compte, et suppression des chats téléchargés.
- **Sécurité et connexion** : méthode de connexion, état de la session et actualisation des jetons.
- **Signaler un problème** ouvre une issue GitHub pré-remplie, avec les infos de l'appareil si tu le veux.
- **Mode développeur**, activé en touchant 8 fois de suite le numéro de build dans À propos : inspecteur réseau (en-têtes, corps, événements du streaming, commande cURL, jetons masqués), journal d'événements, console API en lecture seule, session et claims des jetons, données du compte, modèles, fichiers et préférences, overlay de performances (FPS, mémoire, CPU), détails techniques sous les messages, Markdown brut, texte sans lissage, animations ralenties, simulation de forfait et de pannes, et export d'un rapport de diagnostic.
- Un message « Le chat a bien été supprimé » confirme la suppression d'un chat, une fois qu'elle est faite dans ton compte.
- Toucher la version, en bas des réglages ou dans À propos, affiche les nouveautés.
- Chaque version est publiée dans les [Releases](https://github.com/gabrielb0x/OCTO/releases) avec son IPA.

### Modifié

- **Sans abonnement ChatGPT, le sélecteur de modèle est masqué**, comme dans l'app officielle : le titre affiche « ChatGPT » et le modèle du forfait est utilisé, avec son niveau de réflexion par défaut.
- La mémoire a sa propre page, avec la place utilisée par les souvenirs.

### Corrigé

- **Tirer pour actualiser la liste des chats ne provoque plus d'erreur** : SwiftUI annulait la synchronisation dès que la liste se mettait à jour, et la requête échouait avec « annulé ». La même correction s'applique aux réglages, à la mémoire et aux chats archivés.
- Quitter un chat pendant le téléchargement de ses messages n'affiche plus d'erreur.

## [1.1.0] – 2026-09-15

### Ajouté

- **Ton compte ChatGPT dans l'app** : la liste de tes chats et tes projets vient de ton compte, et chaque chat s'ouvre avec ses messages, sa réflexion et ses sources. Les chats sont gardés sur l'appareil pour s'ouvrir instantanément, même hors ligne.
- Renommer ou supprimer un chat le fait aussi dans ton compte. Les chats archivés sont consultables et désarchivables dans Réglages → Gestion des données.
- **Réglages venant du compte** : nom, e-mail, photo de profil, instructions personnalisées, personnalité (style de base et caractéristiques), mémoire et souvenirs enregistrés. Les instructions et la personnalité se modifient depuis l'app et sont enregistrées dans ton compte.
- Tes instructions personnalisées, ta personnalité et tes souvenirs accompagnent les messages que tu écris dans OCTO.
- **Écran « Nouveautés »** avec icône, affiché une fois au premier lancement après une mise à jour.

### Modifié

- L'assistant se présente comme **ChatGPT** et non plus comme OCTO.
- **Réponses plus fluides** : le texte s'affiche à un rythme régulier au lieu d'arriver par paquets, et les dernières lettres apparaissent en fondu.
- **Plus de défilement automatique** pendant que ChatGPT écrit : ta question remonte en haut de l'écran et la réponse s'écrit en dessous.
- **Barre de saisie en Liquid Glass** : bouton + rond séparé et capsule en verre interactive.
- Animation du texte de l'écran de connexion plus fluide : lettres en fondu et point qui glisse avec le texte.

### Retiré

- La connexion avec une clé API OpenAI, mise de côté pour l'instant. Une clé enregistrée par la version 1.0 est effacée du trousseau.

### Limites connues

- Les réponses aux messages écrits dans OCTO passent toujours par le backend Codex de ton forfait : ces messages restent sur l'appareil et n'apparaissent pas sur chatgpt.com. Dans un chat venant du compte, une mention indique où ils commencent.
- Les images des chats du compte s'affichent comme des vignettes vides : leurs fichiers restent dans le compte.

## [1.0.0] – 2026-09-14

Première version : connexion avec ChatGPT (client OAuth de Codex CLI ou code d'appareil) ou avec une clé API, interface calquée sur l'app ChatGPT en Liquid Glass, réponses en streaming avec Markdown, choix du modèle et du niveau de réflexion, recherche web, pièces jointes, dictée, mode vocal, historique local, chats temporaires et limites d'utilisation.
