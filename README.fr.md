<div align="center">

<img src="Sources/PromptPanel/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" alt="PromptPanel 项目快贴 — gestionnaire de prompts et lanceur de snippets natif macOS" width="128" height="128" />

# PromptPanel | 项目快贴

### Gestionnaire de prompts / lanceur de snippets natif macOS pour ChatGPT, Claude, Cursor, Copilot, VS Code et le Terminal

### Native macOS prompt manager and snippet launcher for ChatGPT, Claude, Cursor, Copilot, VS Code, and Terminal.

PromptPanel（项目快贴）est un **gestionnaire de prompts macOS**, un **lanceur de prompts IA** et un **lanceur de snippets de code** local-first. Appuyez sur un raccourci global, recherchez dans votre **Prompt library / snippet library** locale, puis collez des prompts, code snippets, templates et instructions réutilisables dans **ChatGPT, Claude, Cursor, Copilot, VS Code, le Terminal, le navigateur ou n'importe quel champ de saisie**.

PromptPanel is a local-first **macOS prompt manager**, **AI prompt launcher**, and **snippet launcher**. It is built for developers and AI power users who reuse multiline prompts, coding templates, project context blocks, terminal commands, and reply snippets across apps.

[![Release: v1.4.0](https://img.shields.io/badge/Release-v1.4.0-blue.svg)](CHANGELOG.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform: macOS 14+](https://img.shields.io/badge/Platform-macOS%2014%2B-lightgrey.svg)](https://www.apple.com/macos)
[![Swift 5.10](https://img.shields.io/badge/Swift-5.10-orange.svg)](https://swift.org)
[![Apple Silicon & Intel](https://img.shields.io/badge/Arch-Apple%20Silicon%20%26%20Intel-blue.svg)](#installation)
[![Local-first · No cloud](https://img.shields.io/badge/Local--first-No%20cloud-brightgreen.svg)](#confidentialité--données)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-success.svg)](.github/CONTRIBUTING.md)

[English](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md) · [**Français**](README.fr.md) · [Deutsch](README.de.md)

[FAQ](docs/FAQ.md) · [Documentation](docs/README.md) · [LLM index](llms.txt) · [Journal des modifications](CHANGELOG.md) · [Contribuer](.github/CONTRIBUTING.md)

</div>

---

## Comprendre en 30 secondes / 30-Second Summary

| Dimension / Field | Explication / Answer |
| --- | --- |
| Ce que c'est / What it is | Un macOS Prompt manager and snippet launcher open source et local-first, qui invoque un panneau natif via un raccourci global pour rechercher et coller du texte réutilisable. |
| Problème résolu / Problem solved | Éviter aux utilisateurs intensifs de ChatGPT, Claude, Cursor, Copilot, VS Code et du Terminal de fouiller sans cesse leurs notes ou de recopier le même system prompt, contexte de projet ou template de commande. |
| Pour qui / Audience | Utilisateurs intensifs d'IA, développeurs, Prompt engineers, rédacteurs techniques, PM, consultants et développeurs indépendants qui doivent isoler leur prompt library par projet. |
| Fonctions clés / Core features | Raccourci global, recherche instantanée, isolation par projet, `Universal / projet universel`, filtrage par `#tag`, priorité au presse-papiers, collage automatique via Accessibility, journal d'exécution, import/export JSON/Markdown. |
| Pile technique / Tech stack | Swift 5.10, AppKit `NSPanel`, SwiftUI, SQLite/GRDB, KeyboardShortcuts, Sparkle 2, Swift Package Manager. |
| Démarrage rapide / Quick start | `git clone` -> `./scripts/build-app.sh` -> `open dist/PromptPanel.app`. Après octroi de la permission Accessibility au premier lancement, le collage automatique fonctionne ; sans elle, la copie vers le presse-papiers reste possible. |
| Cas d'usage typiques / Use cases | Role prompt ChatGPT/Claude, contexte de projet Cursor, checklist de revue de PR, snippet de commande Terminal, template de notes de réunion, template de réponse propre à un client. |
| Langue de l'interface / UI language | **L'interface de l'application est actuellement uniquement en chinois simplifié** (`CFBundleDevelopmentRegion = zh-Hans` ; aucune ressource de localisation ni sélecteur de langue dans l'app). La documentation est disponible en 8 langues et `README.md` fournit un tableau de correspondance chinois→anglais des libellés de l'interface. Le contenu des prompts que vous stockez peut être dans n'importe quelle langue. |
| Limites / Limits | Uniquement macOS 14+ ; interface uniquement en chinois simplifié ; pas de binaire notarisé dans la Release actuelle ; pas de synchronisation cloud, pas de collaboration d'équipe, pas de version Windows/Linux ; pas de modèles à variables ; le collage automatique dépend de la permission Accessibility de macOS. |

## Captures d'écran / Screenshots

<table>
  <tr>
    <td width="50%"><img src="docs/ui-qa/latest/panel-light.png" alt="Panneau rapide PromptPanel — recherche de prompts par raccourci global sur macOS, thème clair" /></td>
    <td width="50%"><img src="docs/ui-qa/latest/panel-dark.png" alt="Panneau rapide PromptPanel — lanceur de prompts IA pour ChatGPT et Claude, thème sombre" /></td>
  </tr>
  <tr>
    <td align="center"><sub>Panneau rapide (clair) — raccourci → recherche → Entrée</sub></td>
    <td align="center"><sub>Panneau rapide (sombre) — lanceur portrait 560 × 700</sub></td>
  </tr>
  <tr>
    <td width="50%"><img src="docs/ui-qa/latest/library-dark.png" alt="Bibliothèque PromptPanel — bibliothèque locale de prompts SQLite avec projets, tags et aperçu" /></td>
    <td width="50%"><img src="docs/ui-qa/latest/settings-dark.png" alt="Réglages PromptPanel — raccourci, thème, permissions, sauvegarde et import/export" /></td>
  </tr>
  <tr>
    <td align="center"><sub>Bibliothèque (内容库) — projets, entrées, aperçu</sub></td>
    <td align="center"><sub>Réglages (设置) — raccourci, thème, permissions, maintenance</sub></td>
  </tr>
</table>

<sub>Capturé avec `./scripts/capture-ui-qa.sh`. L'interface de l'app est uniquement en chinois simplifié.</sub>

## Qu'est-ce que PromptPanel ? / What is PromptPanel?

**PromptPanel（项目快贴）** est un **outil de gestion de prompts macOS** et un **snippet launcher** open source et natif. Il est conçu autour d'un flux de travail IA très court : dans n'importe quelle application au premier plan, appuyez sur un raccourci, recherchez dans votre bibliothèque de prompts locale, appuyez sur `Enter`, le contenu est d'abord écrit dans le presse-papiers du système, puis collé automatiquement dans le champ de saisie actif au mieux. Aucun compte, aucune synchronisation cloud, aucune télémétrie : les données essentielles restent sur votre propre Mac.

In English: **PromptPanel is a native macOS prompt manager, AI prompt launcher, and local-first snippet manager** for people who reuse prompts and templates across ChatGPT, Claude, Cursor, Copilot, VS Code, Terminal, browsers, and other macOS text fields.

Si vous recherchez **gestion de prompts ChatGPT macOS**, **bibliothèque de prompts Claude**, **gestionnaire de snippets de code Cursor**, **bibliothèque de prompts local-first**, **macOS global hotkey paste tool**, **Raycast Snippets alternative for AI prompts** ou **open-source TextExpander alternative for multiline prompts**, PromptPanel répond exactement à ce besoin : transformer vos instructions IA, snippets de code et contextes de projet répétitifs en un panneau rapide local, consultable et auditable.

## Ça vous parle ?

PromptPanel exists because the same five problems show up every day for anyone working with LLMs:

- You retype the same **role / system prompt** ("you are a senior staff engineer…") into a fresh ChatGPT or Claude chat ten times a day.
- You keep a Notes app or scratchpad full of **AI prompts and code-review checklists** and `⌘+F` your way through it.
- You finally find the right prompt and the **paste fails silently** because focus moved or the app blocked synthetic keystrokes.
- Your **Cursor / Copilot project context block** is in one file, the **terminal command snippet** in another, and the **PR-review prompt** in a third — none searchable from one place.
- You won't put a real client brief or proprietary architecture into a **cloud prompt manager**, so you end up with no prompt manager at all.

PromptPanel collapses all of that into a single, sub-second loop with a local SQLite file you fully own.

## Pourquoi PromptPanel ?

La plupart des « prompt managers » sont soit des extensions de navigateur (verrouillées sur un seul site), soit des outils de snippets génériques qui n'ont pas été conçus pour le flux de travail IA. PromptPanel est construit spécifiquement autour d'une seule boucle courte :

> **raccourci → recherche → entrée → le contenu arrive dans le champ de saisie actif**

Tout le reste sert à rendre cette boucle rapide, prévisible et jamais susceptible de perdre du contenu.

| Vous voulez… | PromptPanel vous offre |
|---|---|
| Une bibliothèque de prompts qui fonctionne **dans toutes les applications**, pas seulement un site web | Raccourci global, panneau natif macOS, fonctionne dans n'importe quel champ de texte |
| **Une boucle native à faible latence** — objectif inférieur à la seconde entre la frappe et la saisie | Cible < 300 ms du raccourci à la mise au point, < 80 ms de rafraîchissement de la recherche, < 250 ms d'exécution |
| **Une isolation par projet** pour que les prompts du client A ne fuitent pas vers le client B | Projets de premier ordre + un projet `Universal` intégré pour le contenu partagé |
| **Aucun verrouillage cloud** pour les prompts sensibles | SQLite local. Zéro appel réseau pour les fonctions essentielles. Vos données tiennent dans un seul fichier qui vous appartient |
| **Un collage automatique qui n'échoue pas en silence** | Collage automatique d'abord, repli sur le presse-papiers toujours — et un toast clair si le collage a été bloqué |
| **Un fonctionnement 100 % clavier** | Invoquer → taper → touches fléchées → Enter. La souris n'est jamais nécessaire |
| Un logiciel open source que vous pouvez auditer, forker et en qui vous fier | Licence MIT, Swift pur, aucune télémétrie |

## À qui s'adresse-t-il ?

- **Utilisateurs intensifs de ChatGPT / Claude / Gemini** qui réutilisent les mêmes définitions de rôle, contraintes de format de sortie et blocs de contexte
- **Utilisateurs de Cursor / Copilot / Aider** qui collent les mêmes résumés d'architecture et checklists de revue
- **Développeurs** qui tapent à répétition des ébauches de messages de commit, templates de revue de code, commandes de terminal, snippets de triage d'erreurs
- **Indie hackers et consultants** jonglant entre plusieurs projets clients avec des chartes de style et des règles de ton différentes
- **Rédacteurs techniques et PM** qui maintiennent des réponses réutilisables, des mises à jour de statut et des trames de spécifications

Si « je copie-colle le même prompt multiligne vingt fois par jour » vous décrit, cet outil a été écrit pour vous.

## Fonctionnalités

### Cœur (v1.0)

- 🔥 **Raccourci global** — invoquez le panneau depuis n'importe quelle application au premier plan, raccourci configurable
- ⚡ **Moins de 300 ms jusqu'à la saisie** — basé sur `NSPanel`, sans Electron, sans runtime web, sans démarrage à froid
- 🔍 **Recherche instantanée** sur le titre et le corps, sans étape de validation
- 🗂️ **Projets** — isolez les prompts par client, dépôt ou contexte ; le projet `Universal` est toujours visible
- 📋 **Collage automatique avec repli presse-papiers** — utilise `CGEvent` pour envoyer ⌘V, se rabat proprement si la permission Accessibility est absente
- 🎯 **Priorité au clavier** — touches fléchées pour naviguer, Enter pour exécuter, Esc pour fermer
- 📌 **Épinglage et tri par frecency** — épinglez ce qui doit rester en haut ; le reste est classé par `nombre_d_utilisations × 2^(-jours_d_inactivité / 90)`, de sorte que ce que vous utilisez souvent remonte tout seul et que ce que vous n'utilisez plus redescend
- 🌗 **Thème clair / sombre / système**
- 🪶 **Résident dans la barre de menus** — discret jusqu'à ce que vous l'invoquiez
- 🚀 **Lancement à l'ouverture de session** via `SMAppService`
- 🔐 **Dégradation consciente des permissions** — sans Accessibility, vous conservez la copie en une touche et un indice clair dans l'interface
- 📝 **Contenu multiligne** — corps de templates complets, aucune limite de longueur de stockage
- 📊 **Journal d'exécution** pour diagnostiquer les échecs de collage
- 🔄 **Mise à jour manuelle via GitHub Releases** (la mise à jour automatique Sparkle est intégrée mais désactivée par défaut ; le mainteneur l'activera une fois qu'un flux appcast signé sera hébergé)

### Ce qu'il ne fait explicitement *pas* (limites du projet)

Par conception, PromptPanel n'ajoutera **jamais** de synchronisation cloud, de collaboration d'équipe ou d'orchestration de workflows complexes. Il ne s'agit pas de fonctionnalités « pour plus tard » — elles sont hors périmètre pour toujours. L'outil est un utilitaire mono-utilisateur, purement local, et c'est là tout l'intérêt. Voir [PRD §4.2](docs/项目快贴-PRD.md) pour la justification.

## Comment ça fonctionne ?

```
   ┌──────────────┐    hotkey     ┌──────────────┐    select    ┌──────────────┐
   │  any app     │  ──────────►  │ PromptPanel  │  ──────────► │  clipboard   │
   │ (ChatGPT,    │   (global)    │  NSPanel     │   (Enter)    │   (write)    │
   │  Claude,     │               │              │              └──────┬───────┘
   │  Cursor…)    │ ◄──────────── │              │                     │
   └──────────────┘  paste / focus└──────────────┘                     │
          ▲                         restored                            │
          └────────── CGEvent ⌘V (Accessibility permission) ◄───────────┘
                          fallback: clipboard only + toast
```

1. Vous appuyez sur le raccourci configuré (la bibliothèque `KeyboardShortcuts` le capture à l'échelle du système).
2. PromptPanel place un `NSPanel` au-dessus de la fenêtre active, met le champ de recherche au point, et affiche les entrées du projet courant plus celles du projet `Universal`, triées par épinglage → score frecency → récence → nombre d'utilisations.
3. Vous tapez pour filtrer (en direct, sans validation), utilisez les flèches pour choisir, appuyez sur `Enter`.
4. Le contenu sélectionné est **toujours** d'abord écrit dans le presse-papiers du système (c'est la garantie — le presse-papiers n'échoue jamais en silence).
5. Le panneau se masque, l'application précédente reprend la mise au point, et PromptPanel synthétise un `⌘V` via `CGEvent`. Si la permission Accessibility est absente ou si l'application cible bloque les événements synthétiques, un toast vous indique « Copié — appuyez sur ⌘V pour coller ».
6. L'exécution est journalisée localement afin que vous puissiez diagnostiquer plus tard tout problème de collage propre à une application.

Cette séparation — **le presse-papiers comme garantie, le collage automatique en meilleur effort** — est la décision de conception la plus importante du projet.

## Installation

> **Prérequis système :** macOS 14 (Sonoma) ou version ultérieure. Apple Silicon et Intel sont tous deux pris en charge.

### Option A — Compiler depuis les sources (voie actuelle en pré-version)

```bash
# 1. Clone
git clone https://github.com/tytsxai/PromptPanel.git
cd PromptPanel

# 2. Build the .app bundle (signed ad-hoc by default)
./scripts/build-app.sh

# 3. Move it into Applications (or run from dist/)
open dist/PromptPanel.app
```

Prérequis pour la compilation :

- Xcode 15+ avec le SDK macOS 14
- Chaîne d'outils Swift 5.10 (`xcrun swift --version`)

### Option B — Version signée et notarisée

Les GitHub Releases ne contiennent actuellement que des notes de version portant sur les sources et la documentation ; aucun binaire notarisé n'y est encore attaché. Tant que la chaîne de notarisation Developer ID n'est pas complète, compilez localement avec `./scripts/build-app.sh`.

### Configuration au premier lancement

1. **Accordez la permission Accessibility** lorsque la demande apparaît. macOS s'en sert pour autoriser les frappes synthétiques `⌘V`. Sans elle, PromptPanel copie tout de même de façon fiable dans le presse-papiers ; il vous suffit de coller manuellement.
2. **Définissez votre raccourci** dans `设置 → 偏好 → 快捷键 → 呼出面板`. La valeur par défaut actuelle est `⌥2` ; choisissez un autre raccourci s'il entre en conflit avec votre configuration.
3. **Créez un projet** ou commencez à ajouter des entrées à `Universal`.

## Démarrage rapide

En supposant que l'app est compilée et lancée (icône visible dans la barre de menus) :

```text
1. Fenêtre principale → 内容库 (Bibliothèque) → ajoutez votre première entrée :
   titre "review", corps = votre prompt de revue de code, étiquettes facultatives
2. ⌥2              → le panneau apparaît, focus sur le champ de recherche
3. tapez "review"  → filtre jusqu'à votre prompt de revue de code
4. ↵               → le contenu est copié, puis collé dans le champ actif
5. (le panneau se ferme) → vous continuez à travailler
```

### Syntaxe de recherche dans le panneau / Search syntax

| Vous tapez | Ce qui se passe |
|---|---|
| `review` | Correspondance **par préfixe via FTS5 de SQLite** sur le titre et le contenu de l'entrée |
| `code rev` | Chaque jeton séparé par des espaces est un terme de préfixe, combinés avec ET |
| `#sql` | Filtre sur les entrées portant l'étiquette `sql` ; le jeton `#tag` est retiré de la requête textuelle |
| `#sql migrate` | Filtre d'étiquette `sql` **et** correspondance textuelle `migrate` |
| *(vide)* | Parcourt le projet courant plus `Universal`, trié par épinglage → frecency → récence → nombre d'utilisations |

Remarques : seul le premier jeton `#tag` sert de filtre d'étiquette, et la correspondance est exacte et sensible à la casse (`#SQL` ne correspondra pas à une étiquette `sql`) ; les résultats sont plafonnés à 100 lignes ; la correspondance textuelle est par préfixe, donc un terme pris au milieu d'un mot (ou d'une suite CJK sans espaces) ne correspondra pas.

Vous pouvez changer de projet actif depuis l'intérieur du panneau sans ouvrir la fenêtre principale — au clavier uniquement, sans détour. `⌘1`–`⌘9` exécutent directement les neuf premières lignes ; `⌘C` copie sans coller ; `⌘P` épingle le panneau ; `Esc` le ferme.

## Configuration

| Réglage | Emplacement | Notes |
|---|---|---|
| Raccourci global | `设置 → 偏好 → 快捷键 → 呼出面板` | Un seul raccourci. Comportement de bascule : la même touche ferme |
| Thème | `设置 → 偏好 → 外观 → 主题` | Clair / sombre / suivre le système |
| Lancement à l'ouverture de session | `设置 → 偏好 → 权限与启动` | Utilise `SMAppService` |
| Canal de mise à jour | GitHub Releases (manuel) | Sparkle 2 est intégré mais désactivé tant qu'un appcast signé n'est pas hébergé ; abonnez-vous aux notifications de version et remplacez le `.app` |
| Emplacement de la base de données | `~/Library/Application Support/PromptPanel/promptpanel.db` | SQLite mono-fichier, facile à sauvegarder |
| Journaux | `~/Library/Logs/PromptPanel/` | Inspectés via la « Runtime Health » de la fenêtre principale |

## Confidentialité & données

- **Local-first par définition.** Vos prompts résident dans un unique fichier SQLite sur votre Mac. L'application ne fait aucun POST de votre contenu où que ce soit.
- **Aucune télémétrie.** Aucun SDK d'analytics, aucun point de terminaison de métriques, aucun service de rapport de crash.
- **L'accès réseau** est nul dans la version actuelle. Sparkle est fourni mais le flux de mise à jour n'est pas configuré, donc aucun appel sortant n'a lieu, sauf si une future version embarque un appcast.
- **Aucun compte.** Il n'y a rien où se connecter.
- **Open source.** Auditez `Sources/PromptPanel/Core/` pour vérifier tout ce qui précède.

Si vos prompts contiennent des informations propriétaires — architecture interne, briefs clients, contexte soumis à un NDA — c'est exactement la propriété que vous recherchez.

## Comment PromptPanel se compare-t-il aux alternatives ?

> Une orientation rapide, pas un dénigrement. Ces outils sont bons dans ce qu'ils font.

| | **PromptPanel** | TextExpander | Espanso | Raycast Snippets | Alfred Snippets | Extensions de prompts pour navigateur |
|---|:---:|:---:|:---:|:---:|:---:|:---:|
| Open source | ✅ MIT | ❌ | ✅ GPLv3 | Partiel | ❌ | variable |
| Natif macOS (sans Electron / runtime web) | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| Fonctionne dans toute application (pas seulement le navigateur) | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| Interface panneau de recherche rapide (pas seulement des chaînes de déclenchement) | ✅ | partiel | ❌ | ✅ | ✅ | variable |
| Isolation par projet / contexte | ✅ de premier ordre | groupes | dossiers | dossiers | dossiers | rare |
| Flux 100 % clavier | ✅ | partiel | ✅ | ✅ | ✅ | variable |
| Option 100 % locale / sans cloud | ✅ par défaut | optionnelle, les paliers payants poussent vers le cloud | ✅ | compte requis | ✅ | généralement cloud |
| Gratuit | ✅ | $$$ | ✅ | freemium | nécessite Powerpack | variable |
| Conçu spécifiquement autour du flux de travail des prompts IA | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ mais navigateur uniquement |

**En résumé :** si vous vivez uniquement dans le navigateur, une extension de navigateur convient. Si vous vivez dans Cursor/VS Code/Terminal/Slack/partout, il vous faut quelque chose de natif et basé sur un panneau. Parmi les options natives basées sur un panneau, PromptPanel est celle qui est open source et taillée pour les prompts IA.

## Exemples de flux de travail

Des façons concrètes dont les gens utilisent PromptPanel au quotidien — elles font aussi office de questions « comment faire pour... » de longue traîne auxquelles PromptPanel est conçu pour répondre.

- **Lancer une nouvelle conversation ChatGPT / Claude avec votre role / system prompt standard.** Raccourci → tapez `role` → Enter. Fini de retaper « You are a senior staff engineer who... » pour la 200e fois.
- **Insérer un bloc de contexte de projet Cursor / Copilot dans un nouveau fichier.** Stockez une seule fois un bloc de plusieurs paragraphes « voici l'architecture, les conventions et les contraintes » ; collez-le dans toute nouvelle session Cursor en une frappe.
- **Coller une checklist de revue de code dans un brouillon de PR.** La longue liste à puces vit dans PromptPanel ; un raccourci l'ajoute à la description d'une PR GitHub.
- **Déclencher une commande de terminal répétitive avec la combinaison de flags exacte.** `kubectl get pods --context=prod --namespace=… -o jsonpath=…` — tapée une fois, stockée, invoquée par une courte chaîne de recherche.
- **Insérer un template de notes de réunion dans Notion / Obsidian / Apple Notes.** Le même template à chaque standup du lundi → un raccourci, zéro copier-coller depuis un bloc-notes.
- **Envoyer un template de réponse service client / commercial dans Slack ou par e-mail.** Un ton différent par template, choisi depuis un panneau de recherche rapide plutôt que dans un dossier de notes.
- **Basculer entre des projets aux jeux de prompts isolés.** Chaque groupe de projet conserve ses propres role prompts, snippets et templates pour que le contexte ne déborde jamais d'un client à l'autre.

## Pile technique

- **Langage :** Swift 5.10
- **Interface :** AppKit (`NSPanel`, `NSStatusItem`) + SwiftUI
- **Stockage :** SQLite via [GRDB.swift](https://github.com/groue/GRDB.swift)
- **Raccourci :** [sindresorhus/KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (Carbon Hot Key sous le capot)
- **Collage automatique :** `CGEvent` synthétisant ⌘V après restauration de la mise au point
- **Élément d'ouverture de session :** `SMAppService`
- **Mise à jour :** [Sparkle 2](https://sparkle-project.org/)
- **Distribution :** Developer ID + notarisation Apple (pas de Mac App Store)
- **Compilation :** Swift Package Manager — aucun projet Xcode requis

Voir [docs/技术选型.md](docs/技术选型.md) pour le journal de décision complet.

## Structure du projet

```
PromptPanel/
├── Sources/PromptPanel/
│   ├── App/              # AppDelegate, AppState, lifecycle
│   ├── Core/
│   │   ├── Database/     # SQLite open / migrate / recover
│   │   ├── Repositories/ # Project, Entry, Settings, Log
│   │   ├── Services/     # PanelService, ExecuteService, SearchService…
│   │   ├── Diagnostics/  # Hotkey-to-focus timing
│   │   └── Utils/
│   ├── Integrations/     # Clipboard, Paste (CGEvent), Tray, Hotkey, Updater
│   ├── Features/
│   │   ├── Panel/        # QuickPanelView + ViewModel — the hero feature
│   │   └── MainWindow/   # Library + Settings
│   └── Resources/        # Info.plist, entitlements, AppIcon, Assets
├── Tests/PromptPanelTests/
├── frontend-draft/       # UI source-of-truth (HTML/JSX mockups)
├── scripts/              # build-app.sh, notarize, release readiness, restore
├── docs/                 # public architecture, FAQ, PRD, release, ops, handoff docs
├── .github/              # contribution, security, conduct, issue/PR templates, CI
├── llms.txt              # short AI-search / LLM-readable project index
├── codemeta.json         # structured open-source software metadata
└── Package.swift         # SwiftPM package definition
```

## Documentation

L'ensemble de la documentation publique fait partie du dépôt :

- [Index de la documentation](docs/README.md)
- [FAQ](docs/FAQ.md)
- [PRD produit](docs/项目快贴-PRD.md)
- [Présentation du projet](docs/项目介绍.md)
- [Architecture](docs/架构说明.md)
- [Modules et logique de base](docs/关键模块与核心逻辑.md)
- [Contrat d'API et de fonctionnalités](docs/API与功能说明.md)
- [Configuration](docs/配置说明.md)
- [Déploiement](docs/部署说明.md)
- [Normes de développement](docs/开发规范.md)
- [Exemples d'utilisation](docs/使用示例.md)
- [Exploitation et dépannage](docs/运维与排错指南.md)
- [Guide de transfert au mainteneur](docs/接手维护指南.md)
- [Matrice de synchronisation docs/code](docs/文档与代码同步矩阵.md)
- [Publication et récupération](docs/生产发布与恢复手册.md)
- [Feuille de route et guide de contribution](docs/路线图与贡献指南.md)
- [Recherche IA et découvrabilité](docs/ai-search-discoverability.md)
- [Contexte LLM complet](docs/ai-search/llms-full.txt)
- [Métadonnées de recherche JSON-LD](docs/search-metadata.schema.jsonld)
- [Contribuer](.github/CONTRIBUTING.md)
- [Sécurité](.github/SECURITY.md)
- [Métadonnées logicielles CodeMeta](codemeta.json)

Pour les moteurs de réponse et les outils IA conscients du dépôt, commencez par [llms.txt](llms.txt) ou par la version étendue [llms-full.txt](docs/ai-search/llms-full.txt).

## Recherche et découvrabilité par l'IA

PromptPanel conserve les surfaces classiques de SEO et de GEO dans le dépôt afin que les utilisateurs et les moteurs de réponse puissent identifier le projet avec précision :

- `README.md` et `README.zh-CN.md` fournissent le résumé de landing-page destiné aux humains et les captures d'écran actuelles.
- [llms.txt](llms.txt) est l'index court lisible par l'IA pour les outils conscients du dépôt.
- [docs/ai-search/llms-full.txt](docs/ai-search/llms-full.txt) est le contexte étendu pour moteurs de réponse, avec des réponses de style FAQ.
- [codemeta.json](codemeta.json) et [Schema.org JSON-LD](docs/search-metadata.schema.jsonld) décrivent l'application pour les catalogues de logiciels, les robots d'indexation et la future publication d'un site de documentation.
- [Recherche IA et découvrabilité](docs/ai-search-discoverability.md) définit la formulation canonique, la carte des intentions de recherche et la checklist de maintenance.

## Feuille de route

PromptPanel suit une feuille de route **délibérément réduite**. Le PRD liste les éléments explicitement écartés pour toujours (synchronisation cloud, équipes, orchestration de workflows). Dans le périmètre :

- [x] v1.0 — chaîne principale complète : raccourci → recherche → exécution, projets, repli presse-papiers, clair/sombre, élément d'ouverture de session, Sparkle, scripts de signature et de notarisation
- [x] Import et export JSON / Markdown, avec sauvegarde automatique avant import
- [ ] « Répéter la dernière entrée » en un geste
- [ ] Templates avec variables (style `{{name}}`) — uniquement si cela peut être ajouté sans ralentir la chaîne principale

Voir [docs/路线图与贡献指南.md](docs/路线图与贡献指南.md) pour les règles de priorisation, [CHANGELOG.md](CHANGELOG.md) pour ce qui a été livré, et les [issues](https://github.com/tytsxai/PromptPanel/issues) pour la planification publique.

## Questions fréquentes

Pour une FAQ plus complète, voir [FAQ.md](docs/FAQ.md). Les incontournables :

### PromptPanel est-il gratuit ?

Oui. Licence MIT. Pas de palier payant, pas de plafond d'utilisation, pas de compte.

### Fonctionne-t-il avec Apple Silicon (M1/M2/M3/M4) ?

Oui — la version est compilée en binaire universel (arm64 + x86_64), elle s'exécute donc nativement sur les Mac Apple Silicon comme Intel sous macOS 14+.

### Envoie-t-il mes prompts où que ce soit ?

Non. La version actuelle ne fait aucun appel réseau. Sparkle est fourni mais le flux de mise à jour n'est pas configuré dans cette build, donc aucun trafic sortant n'a lieu. Le contenu de vos prompts ne quitte jamais votre Mac.

### Pourquoi demande-t-il la permission Accessibility ?

Pour synthétiser une frappe `⌘V` après que le panneau s'est masqué et que votre application précédente a repris la mise au point. Sans cette permission, l'application fonctionne tout de même — elle s'arrête simplement à l'étape du presse-papiers et vous affiche un toast « appuyez sur ⌘V pour coller ».

### Ajouterez-vous la synchronisation cloud / le partage d'équipe / les workflows ?

Non, délibérément. Ceux-ci sont listés comme **non-objectifs permanents** dans le [PRD §4.2](docs/项目快贴-PRD.md). L'identité du produit est « mono-utilisateur, purement local, rapide ». Ajouter l'un d'eux changerait la nature même du produit.

### Pourquoi pas Electron / Tauri ?

Les chemins les plus critiques de ce produit (timing du raccourci global, restauration de la mise au point, injection de frappes synthétiques, flux de permission Accessibility) relèvent de l'intégration au système macOS. Une coque multiplateforme ajoute de la latence et de l'indirection sans apporter aucune fonctionnalité qui compte pour ce produit. Voir [docs/技术选型.md](docs/技术选型.md) pour le raisonnement complet.

### Comment signaler un bug ou demander une fonctionnalité ?

Ouvrez une issue : <https://github.com/tytsxai/PromptPanel/issues>. Merci d'utiliser les templates — ils nous éviteront à tous deux des allers-retours.

### Comment importer mes prompts existants depuis un autre outil ?

Utilisez `Settings → Maintenance → Import JSON` pour les transferts complets de bibliothèque PromptPanel, ou `Import MD` pour les collections de prompts en Markdown. Les imports créent automatiquement d'abord une sauvegarde locale de la base de données. `Export JSON` est idéal pour une migration sans perte ; `Export MD` est idéal pour un partage relisible.

## Contribuer

Les PR sont les bienvenues — merci de lire d'abord [CONTRIBUTING.md](.github/CONTRIBUTING.md). Deux règles peu évidentes :

1. **Les changements d'interface doivent s'aligner sur `frontend-draft/`.** Ce répertoire est la source de vérité pour le visuel ; ne livrez pas une vue Swift qui contredit le mockup JSX.
2. **Restez dans le périmètre du PRD.** Si une proposition pousse le produit vers le cloud / les équipes / les workflows, c'est un « non » quelle que soit la qualité de son implémentation. Ce n'est pas du gatekeeping — c'est la raison pour laquelle l'outil est rapide et digne de confiance.

## Remerciements

PromptPanel repose sur :

- [GRDB.swift](https://github.com/groue/GRDB.swift) par Gwendal Roué
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) par Sindre Sorhus
- [Sparkle](https://github.com/sparkle-project/Sparkle) par l'équipe Sparkle

…et la communauté Swift / AppKit au sens large, dont la documentation et les réponses Stack Overflow ont rendu possibles les chemins d'intégration système.

## Licence

[MIT](LICENSE) © 2026 tytsxai et les contributeurs de PromptPanel.

---

<sub>**Mots-clés** (pour que vous puissiez réellement trouver ce projet quand vous cherchez) : macOS prompt manager · AI prompt launcher · ChatGPT prompt manager macOS · Claude prompt library · Cursor snippet manager · Copilot prompt template launcher · open-source TextExpander alternative · Espanso alternative · Raycast snippets alternative · Alfred snippet replacement · global hotkey paste macOS · local-first prompt library · offline AI prompt storage · native Swift NSPanel app · AI workflow productivity tool · prompt template manager macOS · snippet launcher macOS · keyboard-first prompt picker · LLM prompt library Mac · prompt engineering toolkit macOS · Cursor prompt manager · fast local prompt launcher for AI · NDA-safe prompt storage · gestionnaire de prompts macOS · lanceur de snippets macOS · bibliothèque de prompts local-first · outil de collage par raccourci global · alternative open source à TextExpander.</sub>

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=tytsxai/PromptPanel&type=Date)](https://www.star-history.com/#tytsxai/PromptPanel&Date)
