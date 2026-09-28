# speckit-guard

Plugin Claude Code qui ajoute à SpecKit ce qui lui manque pour qu'un agent ne soit pas juge de son propre travail :

1. **`/speckit-tests`** : un sous-agent isolé écrit les tests d'acceptation à partir de la spec seule, avant l'implémentation, et prouve qu'ils échouent.
2. **Verrou** : pendant `/speckit-implement`, un hook empêche l'agent de modifier ces tests. Il doit faire évoluer le code, pas la cible.
3. **`/speckit-verify`** : contrôles mécaniques (intégrité des tests, suite complète, mutation testing si disponible), puis un relecteur en contexte vierge juge la conformité à la spec critère par critère.

## Flux

```
/speckit-specify → /speckit-plan → /speckit-tasks
/speckit-tests      tests d'acceptation rouges, commit de référence
/speckit-implement  inchangé, bute sur des tests qu'il ne contrôle pas
/speckit-verify     verdict PASS / FAIL, écarts ajoutés à tasks.md
```

## Installation

Le repo est aussi un marketplace de plugins. Une fois poussé sur un dépôt git :

```
/plugin marketplace add <owner>/<repo>
/plugin install speckit-guard@kolapsis
```

N'importe quelle URL git fonctionne à la place de `<owner>/<repo>`, et un chemin local aussi pour tester avant publication.

Prérequis : `jq` et `git`. Sans `jq`, le verrou reste fermé par sécurité.

## Activation

Le verrou ne s'active que dans les projets SpecKit (dossier `.specify/` présent). Ailleurs, le plugin ne fait rien.

Pour le cantonner à certains projets, active-le au niveau projet plutôt qu'utilisateur (`enabledPlugins` dans `.claude/settings.json` du projet).

## Règles du verrou

| Qui | Tests | Code de prod | `specs/` | Réglages du verrou |
|---|---|---|---|---|
| Agent principal | bloqué | autorisé | autorisé | bloqué |
| `test-writer` | autorisé | bloqué | autorisé | bloqué |
| `spec-reviewer` | bloqué | bloqué | bloqué | bloqué |

Chemins de test par défaut : `*_test.go`, `*.spec.*` / `*.test.*` (ts, tsx, js, mjs, vue), `__tests__/`, `e2e/`, `testdata/`. Pour les changer, créer `.specify/speckit-guard.env` :

```
TEST_RE='(^|/)tests/|_test\.go$'
```

Ce fichier est lui-même protégé contre les modifications de l'agent.

**Échappatoire humaine** : lancer la session avec `TESTS_UNLOCKED=1 claude` pour corriger un test à la main. L'agent ne peut pas modifier cette variable.

## Limites

- Le filtrage des commandes Bash est heuristique. Un agent déterminé peut écrire un fichier par un chemin détourné (script inline, par exemple). Le hook arrête les cas courants, pas un adversaire.
- **La vraie garantie est `/speckit-verify`** : il compare les tests au commit de référence avec `git diff`, indépendamment du hook. Pour aller plus loin, le même contrôle peut tourner en CI.
- Un test vert ne prouve pas l'intention. La qualité du résultat dépend d'abord de la précision des critères d'acceptation de la spec : traiter la section « Ambiguïtés » de `acceptance-tests.md` avant d'implémenter.
- Le mutation testing n'est lancé que si l'outil est déjà installé (`gremlins` pour Go, Stryker configuré pour le front).

## Développement

```
bash plugins/speckit-guard/tests/lock-tests.test.sh   # tests du hook
claude plugin validate .                               # manifestes
```
