# ClickToSpeak

Utilitaire de dictée locale en français pour Mac Apple Silicon, macOS 26 ou ultérieur. La [notice](NOTICE.txt) décrit l’installation, les autorisations et le raccourci.

## Construire sur Mac

Ouvrir `ClickToSpeak.xcodeproj` dans Xcode 26 ou ultérieur et choisir le schéma **ClickToSpeak**, destination **My Mac**. Pour générer les deux livrables avec le SDK macOS sélectionné par `xcode-select`, exécuter depuis le dossier du projet :

```sh
bash scripts/distribution.sh local
```

Le script exécute les tests de régression de l’édition UTF-16, compile en Release arm64 et vérifie la signature et l’intégrité de l’image disque. Chaque exécution crée un sous-dossier distinct de `dist/` contenant `ClickToSpeak.app` et `ClickToSpeak.dmg`. Le mode local utilise une signature ad hoc pour les essais sur la machine de compilation. Faire les essais avec une seule copie installée dans Applications pour que Services et les autorisations désignent le même bundle.

Le workflow manuel **Compiler ClickToSpeak** reproduit la construction sur un runner macOS 26 si le projet est placé dans un dépôt GitHub. Son archive contient l’app compressée avec ses permissions et le DMG de test. Les essais interactifs dans les applications hôtes se font sur le Mac cible.

## Distribuer à des tiers

Le trousseau du Mac de publication doit contenir le certificat **Developer ID Application**, sa clé privée et un profil d’identifiants `notarytool`. Définir `DEVELOPER_ID` avec le nom exact de l’identité et `NOTARY_PROFILE` avec le nom du profil du trousseau. Lancer :

```sh
bash scripts/distribution.sh distribution
```

Ce mode signe l’app avec le runtime renforcé, soumet l’app puis le DMG à Apple, agrafe les tickets et vérifie les deux produits avant de les déposer dans `dist/`. La signature locale et la version de distribution ont des identités différentes pour les autorisations macOS.

## Vérifier le parcours

Commencer par [la recette sur Mac](VALIDATION.md). Elle distingue l’apparition du clic droit de la capacité d’écrire, y compris lorsqu’un champ vide ne propose aucun service. Le raccourci appelle le même contrôleur. Le service n’exige aucune donnée du presse-papiers.

L’édition utilise les plages UTF-16 et les attributs d’Accessibilité `AXSelectedTextRange` et `AXSelectedText`. Un document dont l’hôte n’expose pas la sélection et son remplacement apparaît comme indisponible. L’app contrôle le focus, la sélection et le contenu entre les opérations d’Accessibilité. Ces opérations interprocessus sont distinctes et macOS ne fournit pas de transaction atomique pour les grouper.

Les échantillons du micro et le texte de travail restent en mémoire pendant la session. `SpeechTranscriber` livre les hypothèses provisoires et les phrases finalisées. Le réglage du raccourci est la seule préférence enregistrée par l’app.
