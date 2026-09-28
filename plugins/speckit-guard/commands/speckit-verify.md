---
description: Vérifie l'implémentation d'une feature contre sa spec avec un relecteur en contexte vierge, après contrôles mécaniques (intégrité des tests, suite, mutation testing).
argument-hint: "[dossier de feature, ex. specs/003-user-auth]"
---

Objectif : juger si l'implémentation fait ce que la spec demande, pas seulement si les tests passent. Cette commande ne corrige rien, elle produit un verdict et une liste d'écarts.

Argument éventuel : $ARGUMENTS

## 1. Résoudre la feature et la référence

Résous le dossier de feature comme `/speckit-tests` (argument, puis `specs/<branche courante>/`, puis le `spec.md` le plus récent, sinon demande).

Lis le SHA de référence dans la ligne `Référence :` de `acceptance-tests.md`. S'il n'existe pas, arrête-toi : il faut d'abord lancer `/speckit-tests`.

## 2. Contrôles mécaniques (avant tout jugement)

1. **Intégrité des tests** : liste les fichiers de test ajoutés dans le commit de référence et vérifie avec `git diff <SHA>..HEAD` qu'aucun n'a changé. Si l'un a changé, le verdict est FAIL, quel que soit le reste.
2. **Suite complète** : lance toutes les commandes de test du projet. Relève le résultat.
3. **Mutation testing, si l'outil est déjà installé** (ne l'installe pas toi-même) :
   - Go : `gremlins` sur les paquets modifiés depuis la référence.
   - Front : Stryker, seulement s'il est configuré dans le projet.
   Relève le score et les mutants survivants dans le code modifié. Si aucun outil n'est disponible, note « mutation testing non exécuté ».

## 3. Déléguer au spec-reviewer

Lance le sous-agent `spec-reviewer` avec **uniquement** :
- le chemin du dossier de feature,
- le SHA de référence,
- les résultats bruts des contrôles mécaniques.

Ne lui transmets aucun résumé de l'implémentation ni ton avis : il doit juger à froid à partir de la spec et du diff.

## 4. Consigner

Écris `verification.md` dans le dossier de feature : date, SHA de `HEAD`, résultats mécaniques, puis le rapport du reviewer tel quel.

Si le verdict est FAIL ou s'il y a des critères PARTIEL ou ABSENT, ajoute à la fin de `tasks.md` une section « Remédiation (verify) » avec une tâche par écart.

## 5. Rendre la main

Donne le verdict global en une ligne, les écarts principaux, et ce que l'humain doit tester à la main. Ne corrige rien dans cette commande.
