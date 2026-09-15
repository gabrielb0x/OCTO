<p align="center">
  <img src="logo.png" width="120" alt="Logo OCTO">
</p>

<h1 align="center">OCTO</h1>

<p align="center">
  Un client ChatGPT open source pour iOS 26, sans télémétrie, qui reprend l'interface de l'app ChatGPT avec les composants Liquid Glass d'Apple.<br>
  <em>An open-source, telemetry-free ChatGPT client for iOS, built with Apple's Liquid Glass.</em>
</p>

---

## 📱 Aperçu

| Connexion | Nouveau chat | Conversation |
|:---:|:---:|:---:|
| <img src="docs/screenshots/welcome.png" width="250" alt="Écran de connexion"> | <img src="docs/screenshots/home.png" width="250" alt="Nouveau chat avec suggestions"> | <img src="docs/screenshots/chat.png" width="250" alt="Conversation avec du code"> |
| **Barre latérale** | **Mode vocal** | **Chat supprimé** |
| <img src="docs/screenshots/sidebar.png" width="250" alt="Barre latérale avec l'historique"> | <img src="docs/screenshots/voice.png" width="250" alt="Mode vocal"> | <img src="docs/screenshots/deleteToast.png" width="250" alt="Confirmation de suppression d'un chat"> |
| **Réglages** | **Paramètres de l'application** | **À propos** |
| <img src="docs/screenshots/settings.png" width="250" alt="Réglages"> | <img src="docs/screenshots/settingsApp.png" width="250" alt="Paramètres de l'application"> | <img src="docs/screenshots/about.png" width="250" alt="À propos"> |
| **Forfait Free** | **Thème clair** | **Nouveautés** |
| <img src="docs/screenshots/freePlan.png" width="250" alt="Nouveau chat sans sélecteur de modèle"> | <img src="docs/screenshots/lightChat.png" width="250" alt="Conversation en thème clair avec accent bleu"> | <img src="docs/screenshots/whatsNew.png" width="250" alt="Écran des nouveautés"> |
| **Mode développeur** | **Inspecteur réseau** | **Détails des messages** |
| <img src="docs/screenshots/developer.png" width="250" alt="Mode développeur"> | <img src="docs/screenshots/network.png" width="250" alt="Inspecteur réseau"> | <img src="docs/screenshots/messageDetails.png" width="250" alt="Détails techniques sous les messages"> |

Ces captures sont prises automatiquement sur un simulateur iPhone 17 Pro par le workflow [`screenshots.yml`](.github/workflows/screenshots.yml), avec un compte et des chats de démonstration.

## ✨ Fonctionnalités

- **Connexion avec ton compte ChatGPT** (Free, Plus, Pro, Business…) via OAuth, comme la CLI officielle et open source [Codex](https://github.com/openai/codex), ou avec un code d'appareil.
- **Tes chats et tes projets viennent de ton compte** : chaque chat s'ouvre avec ses messages, sa réflexion et ses sources. Renommer ou supprimer un chat le fait aussi dans ton compte, avec une confirmation, et les chats archivés restent consultables.
- **Interface calquée sur l'app ChatGPT**, construite avec les composants **Liquid Glass** natifs d'iOS 26 : barres d'outils en verre, barre de saisie en capsule de verre avec bouton + séparé, menus, boutons `.glass` et feuilles système.
- **Réglages organisés comme ChatGPT** : Personnalisation, Mémoire, Plugins, compte (e-mail, téléphone, abonnement, restaurer les achats), thème et couleur d'accentuation, Général, Notifications, Voix, Protection, Sécurité et connexion, Stockage, Gestion des données et Aide.
- **Thème Système, Clair ou Sombre** et couleurs d'accentuation de ChatGPT.
- **Réponses en streaming fluides** : le texte s'affiche à un rythme régulier avec un léger fondu, sans que le chat défile tout seul. Rendu Markdown (titres, listes, tableaux, citations) et blocs de code colorés avec bouton « Copier ».
- **Choix du modèle et du niveau de réflexion** depuis le titre du chat, avec le catalogue de modèles de ton compte. Comme dans ChatGPT, le sélecteur n'apparaît qu'avec un abonnement.
- **Mode vocal** : parle à ChatGPT et écoute sa réponse, lue à voix haute phrase par phrase avec la voix de ton choix. La reconnaissance vocale se fait sur l'appareil.
- **Protection** : verrouillage par Face ID et contenu masqué dans le sélecteur d'apps.
- **Notifications** quand une réponse se termine alors qu'OCTO est en arrière-plan.
- **Résumé de la réflexion**, **recherche web** avec sources, **pièces jointes** (photos, appareil photo, fichiers texte), **dictée** et **lecture à voix haute**.
- **Chats temporaires** qui ne laissent aucune trace, et suivi des **limites d'utilisation** de ton forfait.
- **Mode développeur** complet (voir plus bas) et **écran « Nouveautés »** après chaque mise à jour (voir le [CHANGELOG](CHANGELOG.md)).
- Interface en français et en anglais.

## 🔒 Confidentialité

- **Aucune télémétrie**, aucun outil d'analyse, **aucune dépendance tierce**.
- Les requêtes partent **directement de ton iPhone vers OpenAI** (`auth.openai.com` et `chatgpt.com`). Aucun serveur intermédiaire.
- Les jetons de connexion sont stockés dans le **trousseau iOS**. Ta photo de profil n'est demandée avec ta session que si elle est hébergée sur `chatgpt.com`.
- Les chats de ton compte sont téléchargés et gardés **sur l'appareil**. Les messages que tu écris dans OCTO sont envoyés avec `store: false` et restent sur l'appareil.
- Le mode vocal et la dictée utilisent la reconnaissance vocale d'Apple **sur l'appareil** quand elle est disponible.
- « Signaler un problème » ne joint que les versions d'OCTO et d'iOS, le modèle de l'appareil et la langue, et seulement si tu le laisses activé.

## 📲 Installation

OCTO n'est pas sur l'App Store. Chaque version est publiée dans les [Releases](https://github.com/gabrielb0x/OCTO/releases) avec un **IPA non signé** (`OCTO-x.y.z.ipa`) :

1. Télécharge l'IPA de la dernière release. Les builds de chaque commit sont aussi dans l'onglet [Actions](https://github.com/gabrielb0x/OCTO/actions) (artefact `OCTO-unsigned-ipa`).
2. Installe-le avec un outil de sideloading qui signe l'app avec ton identifiant Apple, par exemple [AltStore](https://altstore.io), [SideStore](https://sidestore.io) ou [Sideloadly](https://sideloadly.io).

OCTO nécessite **iOS 26** ou une version plus récente.

## 🔑 Connexion et compte

- **Continuer avec ChatGPT** ouvre la page de connexion officielle d'OpenAI dans une feuille Safari sécurisée. OCTO utilise le même client OAuth public (PKCE) que Codex CLI et reçoit la redirection sur `localhost:1455`, directement sur l'appareil.
- **Se connecter avec un code** : saisis le code affiché sur `auth.openai.com/codex/device` depuis n'importe quel appareil. Si besoin, active l'autorisation par code d'appareil pour Codex dans les paramètres de sécurité de ChatGPT.
- La connexion avec une clé API OpenAI n'est plus proposée pour l'instant.

Avec la même session, OCTO lit ton compte sur `chatgpt.com/backend-api` : profil, abonnement, réglages, instructions personnalisées, personnalité, mémoire, chats et projets. Tes instructions et ta personnalité peuvent être modifiées depuis Réglages → Personnalisation. Les réglages propres aux apps officielles (plugins, contrôle parental, vérification de l'âge, contrôle à distance, publicités) expliquent ce qu'ils font et ouvrent ChatGPT.

Les réponses sont générées par le backend Codex de ton forfait et décomptées de ses **limites d'utilisation Codex** (visibles dans Réglages → Abonnement). Les messages écrits dans OCTO ne sont donc pas ajoutés à tes chats sur chatgpt.com : ils restent sur l'appareil, et une mention l'indique dans les chats venant du compte.

## 🧪 Mode développeur

Dans Réglages → Aide → À propos, **touche 8 fois de suite le numéro de build**. Une section « Développeur » apparaît alors dans les réglages :

- **Inspecteur réseau** : chaque requête avec son statut, sa durée, sa taille, ses en-têtes, ses corps (JSON indenté), les événements du streaming et une commande cURL. Les jetons, cookies et codes OAuth sont masqués, et rien n'est enregistré sur le disque ni envoyé.
- **Journal d'événements** : synchronisations, jetons, réponses, erreurs détaillées, filtrable et partageable.
- **Console API** en lecture seule sur `chatgpt.com/backend-api`, avec des raccourcis.
- **Inspecteurs** : session et claims des jetons, données du compte et de l'abonnement, modèles, fichiers les plus lourds, préférences, appareil et build.
- **Affichage** : overlay de performances (FPS, mémoire, CPU), détails techniques sous chaque message, Markdown brut, texte sans lissage, animations ralenties.
- **Simulation** : forfait Free, Go, Plus ou Pro, sélecteur de modèle forcé, pannes (hors ligne, blocage Cloudflare, erreur serveur, réponse coupée, délai de connexion).
- **Actions** : synchroniser, actualiser le compte, actualiser ou faire expirer les jetons, notification de test, nouveautés, cache des modèles, et **export d'un rapport de diagnostic**.

## 🛠️ Compiler

Prérequis : macOS avec **Xcode 26** et [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
open OCTO.xcodeproj
```

Tests du module `OCTOCore` (ils tournent aussi sous Linux) :

```bash
cd Packages/OCTOCore
swift test
```

### Captures d'écran

Le drapeau de compilation `OCTO_DEMO` ajoute des scènes de démonstration (`welcome`, `home`, `chat`, `sidebar`, `voice`, `settings`, `settingsApp`, `about`, `developer`, `network`, `deleteToast`, `freePlan`, `lightChat`, `messageDetails`, `whatsNew`), sans réseau ni trousseau. Il n'est jamais présent dans l'IPA.

```bash
xcodebuild build -project OCTO.xcodeproj -scheme OCTO -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/DerivedData \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG OCTO_DEMO'
Scripts/take-screenshots.sh build/DerivedData/Build/Products/Debug-iphonesimulator/OCTO.app build/screenshots
python3 Scripts/frame-screenshots.py build/screenshots docs/screenshots
```

### GitHub Actions

- [`build.yml`](.github/workflows/build.yml), à chaque push :
  - **Core tests** : `swift test` sur `OCTOCore`.
  - **Build iOS app** : génère le projet avec XcodeGen, compile en Release sans signature sur `macos-26` et publie l'artefact `OCTO-unsigned-ipa`.
  - **Publish release** : pour un tag `v*` (par exemple `git tag v1.2.0 && git push origin v1.2.0`), crée une release GitHub avec l'IPA `OCTO-1.2.0.ipa` et la section correspondante du CHANGELOG.
- [`screenshots.yml`](.github/workflows/screenshots.yml), quand l'app change : lance les scènes de démonstration sur un simulateur iPhone 17 Pro, ajoute un cadre d'iPhone et enregistre les images dans `docs/screenshots`.

## 🧱 Architecture

```
OCTO/                  App SwiftUI
├── App/               Point d'entrée, AppModel, notes de version et scènes de démonstration
├── Services/          Connexion OAuth et trousseau, compte ChatGPT, streaming, stockage, voix,
│   └── Developer/     notifications, Face ID, toasts ; enregistreur réseau et journal du mode développeur
├── Features/          Onboarding, Main, Sidebar, Chat, Voice, Markdown, Settings, Developer, WhatsNew
├── DesignSystem/      Thème clair et sombre, composants Liquid Glass
└── Resources/         Icônes, logo et traductions
Packages/OCTOCore/     Logique Swift testée : protocole OpenAI, SSE, compte ChatGPT (chats, réglages,
                       abonnement), forfaits, masquage des identifiants, Markdown, rythme du texte
Scripts/               Captures d'écran sur simulateur et cadre d'iPhone
docs/screenshots/      Captures utilisées par ce README
project.yml            Définition du projet XcodeGen
```

## ⚠️ Avertissement

OCTO est un projet indépendant, **ni affilié ni approuvé par OpenAI**. « ChatGPT » et « OpenAI » sont des marques d'OpenAI. L'app est destinée à un usage personnel et non commercial : tu restes responsable du respect des [conditions d'utilisation d'OpenAI](https://openai.com/policies/terms-of-use).

## 📄 Licence

[MIT](LICENSE) © 2026 Gabriel B.
