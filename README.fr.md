# speckit-guard

[![Licence : Apache 2.0](https://img.shields.io/badge/licence-Apache%202.0-blue.svg)](LICENSE)

**Un agent de code ne devrait pas être juge de son propre travail.**

speckit-guard est un plugin [Claude Code](https://docs.claude.com/en/docs/claude-code) pour [GitHub Spec Kit](https://github.com/github/spec-kit). Il fait écrire les tests d'acceptation à partir de la spec avant qu'une ligne de code existe, les verrouille pendant `/speckit-implement`, puis fait vérifier l'implémentation contre la spec, critère par critère, par un relecteur en contexte vierge.

[English version](README.md)

## Le problème

Avec Spec Kit, l'agent qui implémente une feature écrit aussi ses tests et décide lui-même quand elle est terminée. Quand un test échoue, le chemin le plus court vers le vert consiste souvent à modifier le test plutôt que le code. Le flux par défaut ne contient aucune étape qui le vérifie, donc « tous les tests passent » ne dit pas grand-chose sur le respect de la spec.

## Ce que speckit-guard ajoute

1. **`/speckit-tests`** : une feature qui a trop de critères d'acceptation (plus de 60 par défaut) est d'abord arrêtée, avec une proposition de découpage selon ses user stories. Ensuite, un squelette des interfaces prévues est d'abord créé pour que les tests compilent. Ensuite, un sous-agent isolé (`test-writer`) lit seulement la spec, écrit les tests d'acceptation avant l'implémentation et prouve qu'ils échouent à l'exécution. Il signale aussi les contradictions avec les specs des autres features. Les tests sont commités, et ce commit devient la référence.
2. **Un verrou sur les tests** : pendant `/speckit-implement`, un hook `PreToolUse` empêche l'agent de modifier ces tests. Il doit faire évoluer le code, pas la cible. Si un test verrouillé est lui-même faux, `/speckit-fix-test` le fait réparer par le `test-writer` et enregistre la modification comme un amendement, sans arrêter le run.
3. **`/speckit-verify`** : d'abord des contrôles mécaniques (aucune modification des tests depuis le commit de référence en dehors des amendements, tests de ce qui a changé depuis le tour précédent), puis un sous-agent `spec-reviewer`, qui n'a jamais vu le raisonnement de l'implémenteur, juge chaque critère d'acceptation OK, PARTIAL ou MISSING. La commande tourne une fois par user story (`/speckit-verify US2`), puis un tour final lance la suite complète et ne juge que ce qui reste. Les écarts sont ajoutés à `tasks.md` comme tâches de remédiation.

## Flux

Lancer `/speckit-tests` pour une feature juste avant de l'implémenter, une fois fusionnées les features dont elle dépend, et pas pour toutes les features à l'avance : des tests écrits trop tôt reposent sur des interfaces que les implémentations précédentes peuvent encore changer.

```
/speckit-specify → /speckit-plan → /speckit-tasks    Spec Kit, inchangé
/speckit-tests      tests d'acceptation rouges, commit de référence
/speckit-implement  Spec Kit, inchangé, bute sur des tests qu'il ne contrôle pas
  /speckit-fix-test   seulement si un test verrouillé est lui-même faux
  /speckit-verify US<n>  après chaque user story : ses critères, le diff depuis le dernier tour
/speckit-verify     tour final : suite complète, ce qui reste, PASS / FAIL, écarts ajoutés à tasks.md
```

Chaque tour de `/speckit-verify` commence sa section de `verification.md` par `Verified: <SHA> <portée> <verdict>`. Le tour suivant ne lance que les tests de ce qui a changé depuis ce SHA et ne fait lire au `spec-reviewer` que ce diff, ce qui garde un tour court même sur une grosse feature.

Quand l'agent qui implémente essaie de modifier un test verrouillé, le hook bloque l'appel d'outil et lui explique pourquoi :

```
speckit-guard: tests/e2e/login.spec.ts is a locked acceptance test. Change the code,
not the tests. If the test itself is broken (compile error, fixture, typo) or contradicts
the spec, run /speckit-guard:speckit-fix-test tests/e2e/login.spec.ts; a subagent that
cannot run it reports the raw failure to its caller.
```

Ce message s'adresse à l'agent, qui le reformule ensuite pour l'utilisateur.

## Une feature par session, avec Escouade

Enchaîner plusieurs features dans une même session fait grossir le contexte à chaque feature, jusqu'à coûter plus cher que le travail lui-même. Une session neuve par feature coûte moins et garde les revues précises. [Escouade](https://github.com/guillaume-gagnaire/escouade) (1.7 ou plus) le fait sur un Kanban : un ticket par feature, chacun exécuté par son propre agent Claude Code dans son propre worktree, avec l'avancement sur le tableau et les questions de l'agent relayées dans la fenêtre.

Spec Kit et le hook retrouvent la feature courante par le nom de la branche : un ticket doit donc tourner sur la branche de la feature, pas sur la branche `escouade/<clé>` d'Escouade.

1. Créer les specs avant, dans une session normale : `/speckit-specify` par feature crée la branche `NNN-nom` et `specs/NNN-nom/`. Remettre ensuite le dossier du projet sur `main` : une branche extraite là ne peut pas être donnée à un worktree.
2. Réglages du tableau (Réglages › Kanban, ou `set_board` par le serveur MCP) : branche cible `main`, stratégie `merge` pour que le commit de référence reste joignable depuis `main` par son SHA (le hook et `/speckit-verify` le cherchent ainsi), un ticket à la fois, pilote auto.
3. Un ticket par feature, champ « Branche » du formulaire sur la branche de la feature, chaque ticket après le précédent. Description :

```
Feature specs/043-public-surfaces-hardening, sur sa branche.
Commence par git merge main. Puis, dans l'ordre : /speckit-plan, /speckit-tasks,
/speckit-guard:speckit-tests, /speckit-implement, /speckit-guard:speckit-verify.
Si verify ajoute des tâches de remédiation, implémente-les et relance verify.
```

Critères d'acceptation utiles : `acceptance-tests.md` a une ligne `Reference:`, et le dernier rapport de `/speckit-verify` n'a aucun critère MISSING.

Un ticket attend que ceux qui le précèdent soient validés, et la validation est un clic dans la fenêtre ou `approve_ticket` par le serveur MCP. Pour une nuit sans surveillance, une petite session avec le serveur MCP d'Escouade peut faire `wait_ticket` sur chaque ticket et le valider quand il se pose ; son contexte reste petit puisqu'elle ne fait que relayer le tableau. Le `git merge main` au début de chaque ticket rapporte la feature précédente et les tests qu'elle a verrouillés.

## Installation

Le dépôt est un marketplace de plugins, nommé `kolapsis`. Dans Claude Code :

```
/plugin marketplace add https://github.com/kOlapsis/speckit-guard.git
/plugin install speckit-guard@kolapsis
```

Pour tester une modification avant publication, un chemin local vers un clone du dépôt fonctionne aussi à la place de l'URL.

### Prérequis

- Claude Code.
- Un projet initialisé avec Spec Kit (dossier `.specify/` présent). Ailleurs, le plugin ne fait rien.
- `git` et `jq`. Sans `jq`, le verrou reste fermé par sécurité. Si le commit de référence est absent de l'historique (clone superficiel), le verrou retombe sur les motifs de chemins.

Pour cantonner le plugin à certains projets, active-le au niveau projet plutôt qu'utilisateur (`enabledPlugins` dans `.claude/settings.json` du projet).

### Langages de programmation

Les commandes laissent l'agent détecter et lancer les commandes de test du projet, donc le flux ne dépend pas d'un langage. Un point est plus spécifique :

- Les motifs de verrouillage par défaut visent les fichiers de test Go et JavaScript/TypeScript. Ils ne servent qu'avant l'existence du commit de référence et peuvent être changés (voir plus bas).

## Règles du verrou

| Qui | Tests verrouillés | Autres tests | Code de prod | `specs/` | Réglages du verrou |
|---|---|---|---|---|---|
| Agent principal | bloqué | autorisé | autorisé | autorisé, sauf `acceptance-tests.md` | bloqué |
| `test-writer` | autorisé | autorisé | bloqué | autorisé | bloqué |
| `spec-reviewer` | bloqué | bloqué | bloqué | bloqué | bloqué |

**Quels tests sont verrouillés.** Dès que la feature courante (branche `NNN-nom`, sinon `.specify/feature.json`) a une ligne `Reference: <SHA>` dans son `acceptance-tests.md`, le verrou porte sur les fichiers ajoutés par les commits de référence de toutes les features, et sur les `acceptance-tests.md` eux-mêmes. L'ancienne forme `Référence : <SHA>` reste reconnue. Les tests unitaires que l'implémentation écrit restent libres.

Tant que la feature courante n'a pas de référence (pendant `/speckit-tests`), ou si une référence est introuvable dans l'historique, le verrou retombe sur des motifs de chemins. Par défaut : `*_test.go`, `*.spec.*` / `*.test.*` (ts, tsx, js, mjs, vue), `__tests__/`, `e2e/`, `testdata/`. Pour les changer, créer `.specify/speckit-guard.env` :

```
TEST_RE='(^|/)tests/|_test\.go$'
```

Ce fichier est lui-même protégé contre les modifications de l'agent. Ce réglage ne concerne que les outils d'écriture de fichiers : les commandes Bash sont filtrées avec un jeu de motifs fixe.

Le même fichier fixe la limite de taille contrôlée par `/speckit-tests` (scénarios, cas limites, exigences terminales et critères de succès de `spec.md`) :

```
MAX_CRITERIA=60
```

**Réparer un test verrouillé** : `/speckit-fix-test <fichier de test>` transmet l'échec au `test-writer`, sans le diagnostic de l'implémenteur. Le `test-writer` corrige le test s'il est faux (FIXED), refuse s'il est conforme à la spec (REFUSED), ou note la question si deux specs se contredisent (CONFLICT). Une correction est commitée seule et listée dans la section « Amendments » d'`acceptance-tests.md` ; `/speckit-verify` fait vérifier par le `spec-reviewer` qu'aucun amendement n'a affaibli un test.

**Échappatoire humaine** : lancer la session avec `TESTS_UNLOCKED=1 claude` pour corriger un test à la main. L'agent ne peut pas modifier cette variable.

## Limites

- Le filtrage des commandes Bash est heuristique. Un agent déterminé peut écrire un fichier par un chemin détourné (script inline, par exemple). Le hook arrête les cas courants, pas un adversaire.
- **La vraie garantie est `/speckit-verify`** : il vérifie avec `git log` et `git diff` que les tests n'ont changé depuis le commit de référence que par des amendements, indépendamment du hook. Le même contrôle peut tourner en CI.
- Un test vert ne prouve pas l'intention. La qualité du résultat dépend d'abord de la précision des critères d'acceptation de la spec : traiter la section des ambiguïtés de la spec dans `acceptance-tests.md` avant d'implémenter.

## Développement

```
bash plugins/speckit-guard/tests/lock-tests.test.sh      # tests du hook (nécessite jq)
bash plugins/speckit-guard/tests/count-criteria.test.sh  # tests du compteur de critères
claude plugin validate .                                  # validation des manifestes
```

## Licence

[Apache 2.0](LICENSE)
