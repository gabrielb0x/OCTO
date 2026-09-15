# Changelog

Les évolutions notables d'OCTO. Les numéros de version suivent [SemVer](https://semver.org/lang/fr/).

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
