---
description: Fait écrire les tests d'acceptation de la feature par un sous-agent isolé, avant l'implémentation, prouve qu'ils échouent et les fige dans un commit de référence.
argument-hint: "[dossier de feature, ex. specs/003-user-auth]"
---

Objectif : produire les tests d'acceptation de la feature **avant** `/speckit-implement`, écrits par un sous-agent qui ne voit que la spec. Ces tests deviennent la cible verrouillée de l'implémentation.

Argument éventuel : $ARGUMENTS

## 1. Résoudre la feature

Dans cet ordre :
1. Le dossier passé en argument.
2. `specs/<branche git courante>/`.
3. Le dossier `specs/*/` dont le `spec.md` est le plus récent.

Si rien ne correspond, ou si le choix est ambigu, demande à l'humain. Vérifie que `spec.md` existe. Si `acceptance-tests.md` existe déjà, demande s'il faut compléter ou repartir de zéro.

## 2. État de départ

- L'arbre git doit être propre, sinon demande à l'humain de commiter ou ranger avant.
- Détecte les commandes de test du projet (par exemple `go test ./...`, et le script de test du front s'il existe) et lance la suite. Si elle est déjà rouge, arrête-toi et signale-le : on ne peut pas prouver le rouge des nouveaux tests sur une base cassée.

## 3. Déléguer au test-writer

Lance le sous-agent `test-writer` avec **uniquement** :
- le chemin du dossier de feature,
- les chemins de `spec.md`, `plan.md` et `contracts/` s'ils existent,
- les commandes de test détectées.

Ne lui transmets ni ton interprétation de la spec, ni d'idée d'implémentation. Son isolement est tout l'intérêt de l'étape.

Tu ne peux pas écrire les tests toi-même : le verrou du projet t'en empêche.

## 4. Contrôler son travail

- `acceptance-tests.md` existe et chaque critère de la spec y apparaît, en test ou en « Non couverts ».
- Relance toi-même chaque test listé : tous doivent échouer. Un test qui passe est signalé à l'humain.
- Recherche les tests désactivés (skip, todo, only) dans les fichiers ajoutés.
- Seuls des fichiers de test et des fichiers de `specs/` ont changé (`git status`).

## 5. Figer la référence

Commite les tests et `acceptance-tests.md` seuls, avec un message de la forme `test(<feature>): tests d'acceptation (rouges)`. Ajoute ensuite en tête de `acceptance-tests.md` une ligne `Référence : <SHA court>` et commite-la. C'est ce SHA que `/speckit-verify` utilisera.

## 6. Rendre la main

Résumé court :
- critères couverts / total,
- non couverts et ambiguïtés à trancher (en priorité, car une ambiguïté non tranchée produira un code conforme aux tests mais à côté de l'intention),
- les deux ou trois tests à relire en premier.

Rappelle que les tests sont maintenant verrouillés et que la suite est `/speckit-implement`, puis `/speckit-verify`.
