# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Nature du dépôt

Marketplace de plugins Claude Code (`.claude-plugin/marketplace.json`, nom `kolapsis`) qui contient un seul plugin, `plugins/speckit-guard`. Il n'y a ni build ni dépendances : le plugin est fait de Markdown (commandes, agents), d'un `hooks.json` et de deux scripts bash. Les prompts, les messages du hook et les manifestes sont en anglais ; les prompts demandent à Claude de parler la langue de l'utilisateur et d'écrire les fichiers générés dans la langue de `spec.md`. Le README existe en deux versions à garder synchronisées : `README.md` en anglais, `README.fr.md` en français.

## Commandes

```
bash plugins/speckit-guard/tests/lock-tests.test.sh      # tests du hook (nécessite jq)
bash plugins/speckit-guard/tests/count-criteria.test.sh  # tests du compteur de critères
claude plugin validate .                                  # validation des manifestes
```

Il n'y a pas de CI. Le fichier de test du hook n'a pas de filtre : pour isoler un cas, commenter les autres lignes `run` ou rejouer le JSON à la main :

```
printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":"/p/x_test.go"}}' \
  | CLAUDE_PROJECT_DIR=/p bash plugins/speckit-guard/scripts/lock-tests.sh; echo $?
```

(`/p/.specify/` doit exister, sinon le hook sort en 0 sans rien vérifier.)

## Architecture

Le plugin s'insère dans le flux SpecKit : `/speckit-tests` → `/speckit-implement` (SpecKit, inchangé, avec `/speckit-fix-test` au besoin) → `/speckit-verify`.

- `commands/speckit-tests.md` arrête d'abord une feature trop grosse (`scripts/count-criteria.sh`, plus de `MAX_CRITERIA` critères, 60 par défaut) et propose un découpage, puis crée un squelette d'interfaces (corps « not implemented ») pour que les tests compilent, délègue au sous-agent `test-writer`, puis fige les tests dans un commit dont le SHA est écrit dans `acceptance-tests.md` (ligne `Référence : <SHA>`).
- `commands/speckit-fix-test.md`, lancé pendant l'implémentation quand un test verrouillé est lui-même faux : relance `test-writer` en mode réparation (verdict FIXED / REFUSED / CONFLICT) et commite la correction seule, tracée dans la section « Amendments » d'`acceptance-tests.md`. Le message de blocage du hook renvoie vers cette commande.
- `commands/speckit-verify.md` tourne par user story (`US<n>`) puis en tour final. Il relit ce SHA et le point de contrôle du tour précédent, fait les contrôles mécaniques (`git log <SHA>..HEAD` sur les tests, où seuls les commits d'amendement sont admis ; tests de ce qui a changé depuis le point de contrôle ; suite complète au tour final seulement), puis délègue au sous-agent `spec-reviewer`, qui ne relance aucun test. C'est la vraie garantie ; le hook n'est qu'une barrière heuristique.
- `scripts/count-criteria.sh <spec.md> [limite]` : compte scénarios, cas limites, exigences terminales (un identifiant préfixe d'un autre, `MIG-01` devant `MIG-01a`, n'est pas compté) et critères de succès ; sort en 1 au-delà de la limite.
- `scripts/lock-tests.sh`, branché en `PreToolUse` sur `Write|Edit|MultiEdit|NotebookEdit|Bash` : lit le JSON de l'outil sur stdin, **exit 2 = blocage** (message sur stderr), exit 0 = autorisé.

Couplages à garder en tête quand on modifie un morceau :

- Les noms `test-writer` et `spec-reviewer` sont codés en dur dans le `case "$agent"` du hook. Le hook retire le préfixe de plugin (`speckit-guard:test-writer` → `test-writer`). Renommer un agent dans son frontmatter sans toucher le hook casse le verrou.
- Les commandes transmettent volontairement le minimum aux sous-agents (chemins, SHA, résultats bruts) : l'isolement du contexte est le principe du plugin, ne pas y ajouter de résumé ou d'interprétation.
- Le hook a deux modes. Mode « référence » : dès que la feature courante (branche, sinon `.specify/feature.json`) a une ligne `Reference: <SHA>` (ou l'ancienne forme `Référence :`, toujours lue), seuls les fichiers ajoutés par les commits de référence de toutes les features (`git show --name-only --diff-filter=A`, hors `specs/`) et les `acceptance-tests.md` sont verrouillés. Mode « motifs » : avant toute référence, ou si un SHA est introuvable, retour aux motifs de chemins. Le format de la ligne `Reference:` est partagé avec `speckit-tests.md` et `speckit-verify.md`. La ligne `Verified: <SHA> <portée> <verdict>` de `verification.md` est partagée entre `speckit-verify.md` et `spec-reviewer.md`.
- En mode « motifs », deux jeux de motifs coexistent : `TEST_RE` (outils d'écriture, surchargeable via `.specify/speckit-guard.env`) et `TEST_BASH_RE` (commandes Bash, fixe). Un `TEST_RE` personnalisé ne s'applique donc pas au filtrage Bash. Les tests du hook créent un vrai dépôt git temporaire pour couvrir le mode « référence ».
- Le filtrage Bash ne s'active que si la commande matche `WRITE_OPS_RE`, après neutralisation de `2>&1` et `>/dev/null`.
- Les deux README décrivent les règles du verrou (tableau agent × type de fichier) et les chemins de test par défaut : les tenir à jour si le hook change, ainsi que `version` dans `plugin.json`.
