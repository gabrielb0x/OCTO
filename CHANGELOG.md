# Changelog

Les évolutions notables d'OCTO. Les numéros de version suivent [SemVer](https://semver.org/lang/fr/).

## [2.0.0] – 2026-09-19

### Modifié

- **La barre d'onglets prend ta couleur.** Avec la disposition en barre d'onglets, l'onglet affiché prend la couleur d'accentuation choisie dans **Réglages → Apparence** (bleu, violet, ta couleur…). Avec la couleur par défaut, rien ne change. Seule la barre se colore : les écrans gardent leurs couleurs habituelles.
- **Le sélecteur de modèle passe à gauche.** Le modèle, son niveau de réflexion et sa vitesse se choisissent à gauche de la barre du haut, comme un titre sans bulle de verre, juste après le bouton qui ouvre tes chats (et l'étincelle « Mettre à niveau » quand elle est là), au lieu du centre.
- **Des captures d'écran bien plus rapides** (pour qui travaille sur OCTO). Un push ne capture plus que les six écrans du README au lieu des 35 scènes ; la galerie complète est refaite à chaque changement de version, et d'autres scènes se demandent dans le message du commit (`[screenshots: usage, telemetry]`, ou `[screenshots: all]`) ou en lançant le workflow à la main. L'app de démonstration est compilée optimisée, chaque scène n'attend que le temps dont elle a besoin (1,2 s pour un écran simple au lieu de 3,5 s), l'app est relancée en un seul appel, et la durée de chaque scène est notée dans une annotation.

## [1.11.0] – 2026-09-19

### Ajouté

- **Ton utilisation de Codex, en graphiques.** **Réglages → Utilisation de Codex** (aussi depuis Abonnement) montre d'abord ce qui compte : une **estimation des messages qu'il te reste**, puis une jauge de ce qu'il reste de ta limite (verte, orange quand elle baisse, rouge vers la fin) avec sa date de réinitialisation. En dessous : les **tokens utilisés sur la période** et une **estimation des tokens restants**, un graphique des **tokens de chaque jour** sur deux semaines (touche une barre pour voir le jour), le total depuis le début et ton jour le plus chargé, et chaque limite de ton forfait quand il en a plusieurs.
- **Comment c'est calculé.** Les tokens de chaque jour viennent de Codex lui-même (`wham/profiles/me`, l'adresse que lit la CLI Codex) et comptent toutes les apps Codex de ton compte. Codex ne dit que la part de chaque limite déjà utilisée : OCTO en déduit la taille de la limite d'après les tokens utilisés sur la même période, puis le nombre de messages restants d'après **la taille moyenne des messages de tes chats** — la question, tout le chat qui la précède et la réponse. Les réponses écrites dans OCTO arrivent avec le décompte exact de Codex ; les autres sont estimées d'après leur longueur. La page dit sur combien de réponses l'estimation repose.
- **La jauge suit chaque réponse.** Codex renvoie où en sont tes limites avec chaque réponse (`x-codex-primary-used-percent`…, et l'événement `codex.rate_limits`) : OCTO les lit au passage, sans requête de plus, et la ligne « Utilisation de Codex » des réglages affiche ce qu'il reste.
- **Modifier ton profil.** Un **crayon sur ta photo**, en haut des Réglages, ouvre « Modifier le profil », comme dans ChatGPT : ta **photo** (bibliothèque ou appareil photo, recadrée en carré), ton **nom affiché** et ton **nom d'utilisateur**, enregistrés dans ton compte avec les requêtes de l'écran de ChatGPT (`calpico/chatgpt/profile/{id}`, `…/username`, `calpico/chatgpt/profile_files`). Les réglages affichent ton nom affiché et ton `@nom d'utilisateur`. Si ChatGPT refuse un nom d'utilisateur (déjà pris, caractères non autorisés), son message s'affiche et ce qui a déjà été enregistré le reste.
- **La télémétrie est bloquée.** OCTO n'en a jamais envoyé, et refuse maintenant **toute requête vers les adresses de télémétrie** de ChatGPT et de Codex avant qu'elle ne quitte l'iPhone, dans toutes ses sessions réseau et dans celle du système : le service d'événements de ChatGPT (`chatgpt.com/ces/…` : `ces/v1/rgstr`, `ces/statsc/flush`, `ces/v1/telemetry/intake`), Statsig (`api.oaistatsig.com/v1/sdk_exception`, `ab.chatgpt.com`…), les rapports de latence (`backend-api/lat/r`), les statistiques de la CLI Codex (`codex/analytics-events`), Datadog, Sentry, Segment et Google Analytics. **Réglages → Confidentialité → Télémétrie bloquée** liste toutes ces adresses et ce qui aurait tenté de les joindre depuis l'ouverture d'OCTO.
- **Retirer l'e-mail et le téléphone des réglages.** **Confidentialité → E-mail et numéro de téléphone** propose « Retirés des réglages » : leurs lignes disparaissent complètement des Réglages, et ils restent masqués partout ailleurs.

### Corrigé

- **Le bouton pour redescendre en bas d'un chat** ne se pose plus sur la barre de message : il flotte juste au-dessus.
- **Plus de clavier coincé sur l'accueil.** Sur un nouveau chat, le clavier ne se rangeait qu'en envoyant un message — et avec la barre d'onglets, cachée derrière lui, on ne pouvait plus changer d'onglet. Glisser vers le bas ou toucher l'espace vide le range maintenant, et un chat court glisse toujours pour le ranger aussi.
- Une limite de 30 jours (celle du forfait gratuit) s'appelle maintenant « Limite mensuelle », et non plus « Limite hebdomadaire ».

## [1.10.0] – 2026-09-18

### Ajouté

- **Une nouvelle disposition, avec une barre d'onglets en bas.** **Réglages → Disposition** propose, à côté de la barre latérale de l'app ChatGPT (qui reste la disposition par défaut), une **barre d'onglets Liquid Glass** : Chats, Accueil et Réglages, plus un bouton de recherche rond au bout de la barre. Choisir la barre d'onglets fait apparaître ses options : les onglets à y mettre (Accueil, Chats, Projets, Comptes, Réglages) et leur ordre, le bouton de recherche, l'onglet sur lequel OCTO s'ouvre, et la barre qui se réduit quand tu fais défiler un chat. Accueil reste toujours : c'est là que tu écris. Sans onglet Chats, le bouton en haut à gauche ouvre tes chats dans une feuille ; sans onglet Réglages, ta photo en haut des chats y mène.
- **Savoir d'où vient chaque chat.** Dans la liste, le logo de ChatGPT marque les chats de ton compte ChatGPT, et un terminal ceux écrits avec **Codex** dans OCTO, qui n'existent que sur cet iPhone. Garder le doigt sur un chat le rappelle aussi. Ça se désactive dans Réglages → Disposition.
- **N'afficher que les chats ChatGPT, ou que les chats Codex.** Le bouton de filtre au bout du champ de recherche (ou en haut de l'onglet Chats) garde un seul type de chats, et un bandeau le rappelle avec « Tout afficher ». Le choix est gardé.
- **Les photos de profil des autres comptes.** Réglages → Comptes montre la photo de chaque compte connecté, et plus seulement celle du compte utilisé : d'abord celle que son dossier a gardée, puis une photo à jour une fois par jour. Elle est téléchargée sans aucun jeton, ou avec la session de ce compte-là quand elle est hébergée sur chatgpt.com, et par une session réseau à part, sans cookies, pour que rien ne relie deux comptes.
- **Le sélecteur de modèle suit l'API de Codex.** Il liste les modèles que le catalogue de Codex (`codex/models`) donne à ton forfait — **y compris le forfait gratuit** : GPT-6-Astra, GPT-5.6 Sol, Terra et Luna, GPT-5.5 — avec leur description. OCTO **vérifie les modèles disponibles** : ceux que le catalogue réserve à d'autres forfaits (`available_in_plans`) sont écartés, et si Codex refuse un modèle à l'envoi d'un message, il quitte le sélecteur et la question repart aussitôt avec le meilleur modèle restant, en te le disant.
- **La vitesse des réponses.** Le menu du modèle propose les vitesses de Codex pour ce modèle (Standard, Rapide, Ultra-rapide), envoyées comme le fait Codex (`service_tier`). Les vitesses rapides consomment davantage ton forfait ; s'il ne les inclut pas, la réponse arrive quand même, à la vitesse habituelle.
- **Réglages → Général → Modèle par défaut** liste les modèles proposés à ton forfait avec leur description, leurs niveaux de réflexion et leurs vitesses, ceux qui ne sont pas inclus, et un bouton pour vérifier à nouveau auprès de Codex.

### Modifié

- **Plus de « ChatGPT » au milieu de la barre du haut d'une conversation** : il y a le sélecteur de modèle, ou rien quand Codex ne propose qu'un modèle. Avec le sélecteur au milieu, « Mettre à niveau » ne garde que son étincelle, pour que tout tienne.
- Le mode vocal affiche le modèle qui répond.
- OCTO se présente à Codex en version 0.155.0, la dernière de la CLI.
- Le README ne montre plus que les captures principales ; les autres restent dans `docs/screenshots`.

## [1.9.0] – 2026-09-16

### Ajouté

- **Plusieurs comptes ChatGPT, et on passe de l'un à l'autre.** **Réglages → Comptes** liste les comptes connectés sur cet iPhone, avec leur photo, leur adresse et leur forfait ; une pression suffit pour changer. « Ajouter un compte » ouvre la page de connexion de ChatGPT **sans les cookies du compte déjà connecté** — sinon ChatGPT rendait le même compte sans jamais demander lequel tu voulais — et la connexion par code marche aussi. Se reconnecter à un compte déjà présent le met à jour au lieu de l'ajouter deux fois.
- **Chaque compte garde ses propres chats.** Les conversations, les pièces jointes et les données du compte vivent dans un dossier par compte (`Accounts/<compte>/`), donc changer de compte ne mélange jamais deux historiques. Les jetons aussi ont chacun leur entrée dans le trousseau : ajouter un compte ne touche pas à celui d'à côté. Le compte déjà connecté avant la 1.9 est déplacé dans son dossier au premier lancement, sans rien perdre.
- **Changer de compte depuis la liste des chats** : garde le doigt sur ton nom en bas du panneau, et choisis un autre compte, « Comptes » ou « Réglages ».
- **Gestion des publicités, pour de vrai.** L'écran ne se contente plus de renvoyer vers ChatGPT : **Publicités personnalisées** et **Historique des publicités** sont des interrupteurs lus et modifiés dans ton compte (`bazaar_personalization_enabled`, `bazaar_history_enabled`).
- **Supprimer tes données publicitaires.** Un bouton efface le profil publicitaire que ChatGPT construit pour ton compte (`DELETE bazaar/profile`), avec une confirmation. C'est définitif.
- **Rester en gratuit, sans publicités.** Pour un compte sans abonnement, un interrupteur échange les publicités contre **moins de messages par jour** (`free_ads_opt_out`). C'est réversible à tout moment.
- **Les réglages de mémoire deviennent modifiables.** « Référencer les souvenirs enregistrés » et « Référencer l'historique des chats » étaient affichés en lecture seule ; ce sont maintenant des interrupteurs enregistrés directement dans ton compte ChatGPT (`sunshine`, `moonshine`).
- `bazaar/profile` rejoint les **raccourcis de la console** du mode développeur.

### Modifié

- **Le rouge est vraiment rouge.** Les lignes qui défont quelque chose — « Se déconnecter », « Supprimer tous les chats », « Retirer les chats téléchargés », « Supprimer les données publicitaires », « Désactiver le mode développeur », « Copier le jeton d'accès » — portent un rouge plus saturé, en demi-gras, et **toute la ligne** est teintée de rouge au lieu du seul texte.
- **Se déconnecter ne te renvoie plus forcément à l'écran de connexion** : s'il te reste un autre compte, OCTO bascule dessus, et la confirmation le dit. Déconnecter un compte révoque sa session et oublie ce qu'OCTO avait téléchargé de lui ; ses chats restent dans ton compte ChatGPT.
- L'adresse e-mail d'un compte dans la liste des comptes suit **Confidentialité → Ton adresse et ton numéro** : masquée derrière des points comme partout ailleurs.

## [1.8.0] – 2026-09-16

### Ajouté

- **Les forfaits ChatGPT, comme dans son app.** « Mettre à niveau » n'ouvre plus la page Abonnement : il affiche l'écran des forfaits — le sélecteur **Go / Plus**, le tableau qui compare le forfait au compte gratuit (modèle de base, modèles avancés, limites étendues pour les messages et les chargements, création d'images avancée avec Thinking, mémoire étendue, Codex et Deep Research, accès en exclusivité aux nouveautés) et le bouton de mise à niveau en bas.
- **Les prix affichés sont les vrais.** OCTO lit la tarification de ChatGPT pour ton pays (`checkout_pricing_config/configs/{pays}`, l'adresse que le site interroge avant d'afficher ses forfaits) : le prix mensuel apparaît dans ta monnaie et dans ta langue, avec le prix par mois en paiement annuel quand le forfait le propose. **Go n'apparaît que là où ChatGPT le vend.** Les prix sont gardés avec le compte, donc l'écran s'ouvre déjà rempli la fois suivante.
- **OCTO ne vend rien et n'encaisse rien** : le bouton ouvre ChatGPT, qui s'occupe du paiement, et l'écran le dit. On y arrive aussi depuis **Réglages → Abonnement → « Voir les forfaits »**.
- **Supprimer un souvenir.** Dans **Réglages → Mémoire**, balaie un souvenir (ou garde le doigt dessus) pour le supprimer de ton compte ChatGPT. Une confirmation montre le souvenir concerné, la ligne disparaît tout de suite, et OCTO relit ce qui reste pour que la jauge de mémoire suive. C'est l'appel que fait l'écran Mémoire de ChatGPT, pas une suppression locale : le souvenir quitte vraiment ton compte.
- **Supprimer un chat archivé.** Dans **Réglages → Gestion des données → Chats archivés**, un chat se désarchive comme avant, et se supprime aussi : balaie (ou garde le doigt dessus), confirme, et il quitte ton compte ChatGPT comme l'appareil.
- La nouvelle adresse `checkout_pricing_config/configs/{pays}` rejoint les **raccourcis de la console** du mode développeur.

### Modifié

- **Le bouton « Mettre à niveau » sous ton compte dans les réglages est parti.** Cette pastille de verre sous ton nom alourdissait la première page des réglages ; l'offre reste là où ChatGPT la met, en haut du chat, et dans la page Abonnement.

## [1.7.0] – 2026-09-16

### Ajouté

- **Glisser vers la droite n'importe où dans le chat ouvre tes chats.** Plus besoin de viser le bord de l'écran ni le bouton en haut à gauche : le geste marche sur toute la conversation, comme dans l'app ChatGPT, et glisser vers la gauche referme le panneau. Un glissement est jugé une seule fois, au départ : faire défiler la conversation ou un bloc de code ne déclenche plus le panneau par accident.
- **Création d'images.** « Créer une image » apparaît dans le menu + de la barre de message et dans le menu du modèle, avec une pastille dans la barre quand c'est activé, et la suggestion « Créer une image » de l'accueil l'active toute seule. OCTO demande alors l'outil d'images à l'API Responses du **backend Codex de ton forfait**, et l'image arrive dans la conversation, gardée avec le chat comme une photo envoyée. **Le backend Codex ne propose que les outils des clients Codex** : s'il refuse l'outil, OCTO repose la question sans lui, te répond quand même avec des mots et te le dit, au lieu de faire échouer la réponse.

### Modifié

- **Les réglages ne se répètent plus.** Les lignes qui ne faisaient que renvoyer ailleurs sont parties : « Écran d'accueil » dans Général (c'était Apparence), la section « Ton compte ChatGPT » dans Confidentialité (Appareils, Gestion des données et Vérification de l'âge sont déjà dans Sécurité et connexion et dans la première page), le raccourci Dictée de Confidentialité (il est dans Voix), « Couleur d'accentuation » en double avec Apparence, « Masquer le contenu dans le sélecteur d'apps » en double entre Protection et Confidentialité, et l'adresse e-mail comme « Se déconnecter » en double dans Sécurité et connexion. Chaque réglage vit maintenant à un seul endroit.
- **Quand le texte d'une ligne est rouge, son icône l'est aussi** : « Se déconnecter », « Supprimer tous les chats », « Retirer les chats téléchargés », « Désactiver le mode développeur » et « Copier le jeton d'accès ». iOS ne colorait que le texte et laissait l'icône dans la couleur d'accentuation.

### Corrigé

- **La dictée sur l'appareil vérifie enfin si tu l'as désactivée sur ton iPhone.** iOS signale la dictée coupée dans Réglages → Général → Clavier comme une *restriction*, et aucune demande d'autorisation ne la rétablit : OCTO le dit clairement, propose d'ouvrir les Réglages, et l'écran Voix affiche l'avertissement avant même d'essayer, réactualisé au retour des Réglages. Le mode vocal, qui écoute avec la même reconnaissance, dit la même chose.

## [1.6.1] – 2026-09-16

### Corrigé

- Dans **Appareils**, le titre de la liste affichait « Connexion le » : en anglais, il portait le même nom que la date de dernière connexion de Sécurité et connexion, et héritait donc de sa traduction. Il dit maintenant « Appareils connectés ».

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
