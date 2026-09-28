# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Nature du dépôt

Marketplace de plugins Claude Code (`.claude-plugin/marketplace.json`, nom `kolapsis`) qui contient un seul plugin, `plugins/speckit-guard`. Il n'y a ni build ni dépendances : le plugin est fait de Markdown (commandes, agents), d'un `hooks.json` et d'un script bash. Tout le contenu (prompts, messages du hook, README) est en français.

## Commandes

```
bash plugins/speckit-guard/tests/lock-tests.test.sh   # tests du hook (nécessite jq)
claude plugin validate .                               # validation des manifestes
```

Il n'y a pas de CI. Le fichier de test n'a pas de filtre : pour isoler un cas, commenter les autres lignes `run` ou rejouer le JSON à la main :

```
printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":"/p/x_test.go"}}' \
  | CLAUDE_PROJECT_DIR=/p bash plugins/speckit-guard/scripts/lock-tests.sh; echo $?
```

(`/p/.specify/` doit exister, sinon le hook sort en 0 sans rien vérifier.)

## Architecture

Le plugin s'insère dans le flux SpecKit : `/speckit-tests` → `/speckit-implement` (SpecKit, inchangé) → `/speckit-verify`.

- `commands/speckit-tests.md` orchestre et délègue au sous-agent `test-writer`, puis fige les tests dans un commit dont le SHA est écrit dans `acceptance-tests.md` (ligne `Référence : <SHA>`).
- `commands/speckit-verify.md` relit ce SHA, fait les contrôles mécaniques (`git diff <SHA>..HEAD` sur les tests, suite complète, mutation testing si présent), puis délègue au sous-agent `spec-reviewer`. C'est la vraie garantie ; le hook n'est qu'une barrière heuristique.
- `scripts/lock-tests.sh`, branché en `PreToolUse` sur `Write|Edit|MultiEdit|NotebookEdit|Bash` : lit le JSON de l'outil sur stdin, **exit 2 = blocage** (message sur stderr), exit 0 = autorisé.

Couplages à garder en tête quand on modifie un morceau :

- Les noms `test-writer` et `spec-reviewer` sont codés en dur dans le `case "$agent"` du hook. Le hook retire le préfixe de plugin (`speckit-guard:test-writer` → `test-writer`). Renommer un agent dans son frontmatter sans toucher le hook casse le verrou.
- Les commandes transmettent volontairement le minimum aux sous-agents (chemins, SHA, résultats bruts) : l'isolement du contexte est le principe du plugin, ne pas y ajouter de résumé ou d'interprétation.
- Deux jeux de motifs de tests coexistent : `TEST_RE` (outils d'écriture, surchargeable via `.specify/speckit-guard.env`) et `TEST_BASH_RE` (commandes Bash, fixe). Un `TEST_RE` personnalisé ne s'applique donc pas au filtrage Bash.
- Le filtrage Bash ne s'active que si la commande matche `WRITE_OPS_RE`, après neutralisation de `2>&1` et `>/dev/null`.
- Le README décrit les règles du verrou (tableau agent × type de fichier) et les chemins de test par défaut : le tenir à jour si le hook change, ainsi que `version` dans `plugin.json`.
