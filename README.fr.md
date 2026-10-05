# speckit-guard

[![Licence : Apache 2.0](https://img.shields.io/badge/licence-Apache%202.0-blue.svg)](LICENSE)

**Un agent de code ne devrait pas être juge de son propre travail.**

speckit-guard est un plugin [Claude Code](https://docs.claude.com/en/docs/claude-code) pour [GitHub Spec Kit](https://github.com/github/spec-kit). Il fait écrire les tests d'acceptation à partir de la spec avant qu'une ligne de code existe, les verrouille pendant `/speckit-implement`, puis fait vérifier l'implémentation contre la spec, critère par critère, par un relecteur en contexte vierge.

[English version](README.md)

## Le problème

Avec Spec Kit, l'agent qui implémente une feature écrit aussi ses tests et décide lui-même quand elle est terminée. Quand un test échoue, le chemin le plus court vers le vert consiste souvent à modifier le test plutôt que le code. Le flux par défaut ne contient aucune étape qui le vérifie, donc « tous les tests passent » ne dit pas grand-chose sur le respect de la spec.

## Ce que speckit-guard ajoute

1. **`/speckit-tests`** : un sous-agent isolé (`test-writer`) lit seulement la spec, écrit les tests d'acceptation avant l'implémentation et prouve qu'ils échouent. Les tests sont commités, et ce commit devient la référence.
2. **Un verrou sur les tests** : pendant `/speckit-implement`, un hook `PreToolUse` empêche l'agent de modifier ces tests. Il doit faire évoluer le code, pas la cible.
3. **`/speckit-verify`** : d'abord des contrôles mécaniques (`git diff` des tests par rapport au commit de référence, suite complète, mutation testing si un outil est installé), puis un sous-agent `spec-reviewer`, qui n'a jamais vu le raisonnement de l'implémenteur, juge chaque critère d'acceptation OK, PARTIEL ou ABSENT. Les écarts sont ajoutés à `tasks.md` comme tâches de remédiation.

## Flux

```
/speckit-specify → /speckit-plan → /speckit-tasks    Spec Kit, inchangé
/speckit-tests      tests d'acceptation rouges, commit de référence
/speckit-implement  Spec Kit, inchangé, bute sur des tests qu'il ne contrôle pas
/speckit-verify     verdict PASS / FAIL, écarts ajoutés à tasks.md
```

Quand l'agent qui implémente essaie de modifier un test verrouillé, le hook bloque l'appel d'outil et lui explique pourquoi :

```
speckit-guard: tests/e2e/login.spec.ts est un test d'acceptation verrouillé.
Fais évoluer le code, pas les tests. Si un test te semble faux ou contradictoire
avec la spec, arrête-toi et signale-le à l'humain.
```

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

### Langages

Les commandes laissent l'agent détecter et lancer les commandes de test du projet, donc le flux ne dépend pas d'un langage. Deux points sont plus spécifiques :

- Les motifs de verrouillage par défaut visent les fichiers de test Go et JavaScript/TypeScript. Ils ne servent qu'avant l'existence du commit de référence et peuvent être changés (voir plus bas).
- Le mutation testing n'est lancé que si l'outil est déjà installé : `gremlins` pour Go, Stryker pour le front s'il est configuré. Le plugin ne les installe jamais.

## Règles du verrou

| Qui | Tests verrouillés | Autres tests | Code de prod | `specs/` | Réglages du verrou |
|---|---|---|---|---|---|
| Agent principal | bloqué | autorisé | autorisé | autorisé, sauf `acceptance-tests.md` | bloqué |
| `test-writer` | autorisé | autorisé | bloqué | autorisé | bloqué |
| `spec-reviewer` | bloqué | bloqué | bloqué | bloqué | bloqué |

**Quels tests sont verrouillés.** Dès que la feature courante (branche `NNN-nom`, sinon `.specify/feature.json`) a une ligne `Référence : <SHA>` dans son `acceptance-tests.md`, le verrou porte sur les fichiers ajoutés par les commits de référence de toutes les features, et sur les `acceptance-tests.md` eux-mêmes. Les tests unitaires que l'implémentation écrit restent libres.

Tant que la feature courante n'a pas de référence (pendant `/speckit-tests`), ou si une référence est introuvable dans l'historique, le verrou retombe sur des motifs de chemins. Par défaut : `*_test.go`, `*.spec.*` / `*.test.*` (ts, tsx, js, mjs, vue), `__tests__/`, `e2e/`, `testdata/`. Pour les changer, créer `.specify/speckit-guard.env` :

```
TEST_RE='(^|/)tests/|_test\.go$'
```

Ce fichier est lui-même protégé contre les modifications de l'agent. Ce réglage ne concerne que les outils d'écriture de fichiers : les commandes Bash sont filtrées avec un jeu de motifs fixe.

**Échappatoire humaine** : lancer la session avec `TESTS_UNLOCKED=1 claude` pour corriger un test à la main. L'agent ne peut pas modifier cette variable.

## Limites

- Le filtrage des commandes Bash est heuristique. Un agent déterminé peut écrire un fichier par un chemin détourné (script inline, par exemple). Le hook arrête les cas courants, pas un adversaire.
- **La vraie garantie est `/speckit-verify`** : il compare les tests au commit de référence avec `git diff`, indépendamment du hook. Le même contrôle peut tourner en CI.
- Un test vert ne prouve pas l'intention. La qualité du résultat dépend d'abord de la précision des critères d'acceptation de la spec : traiter la section « Ambiguïtés » de `acceptance-tests.md` avant d'implémenter.

## Développement

```
bash plugins/speckit-guard/tests/lock-tests.test.sh   # tests du hook (nécessite jq)
claude plugin validate .                               # validation des manifestes
```

## Licence

[Apache 2.0](LICENSE)
