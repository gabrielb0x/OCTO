# Changelog

Les évolutions notables d'OCTO. Les numéros de version suivent [SemVer](https://semver.org/lang/fr/).

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
