# Recette sur Mac cible

**État de cette livraison source** — Les essais interactifs et la compilation native restent à effectuer. Aucune compatibilité par application n’a été constatée depuis le poste Windows de développement.

## Commencer par les cinq applications

Installer l’app dans Applications. Noter la version de macOS, la puce, le micro et la version de chaque application. Dans chaque ligne, essayer le service avec le champ vide, avec le curseur au milieu d’un texte et avec une sélection. Pour chaque cas, noter « direct », « sous Services », « menu application seulement » ou « absent ». Essayer ensuite le raccourci dans les mêmes conditions.

| Application et champ | Clic droit vide | Clic droit avec texte | Clic droit sélection | Raccourci | Insertion / révisions / final |
|---|---|---|---|---|---|
| Notes, corps d’une note | À tester | À tester | À tester | À tester | À tester |
| TextEdit, document RTF | À tester | À tester | À tester | À tester | À tester |
| Safari, textarea puis éditeur enrichi | À tester | À tester | À tester | À tester | À tester |
| Chrome, textarea puis éditeur enrichi | À tester | À tester | À tester | À tester | À tester |
| Messages, brouillon non envoyé | À tester | À tester | À tester | À tester | À tester |

Pour Safari et Chrome, ouvrir le fichier local [Champs.html](Tests/Champs.html). Dans Messages, garder le brouillon et cliquer uniquement sur **Terminer**.

1. Saisir « Avant 👋 et après ». Placer le curseur après l’emoji. Dicter « je prends le train demain », marquer une pause, puis ajouter « à huit heures ». Observer les mots pendant la parole et les corrections. Contrôler que les deux extrémités du texte restent intactes et que les mots n’apparaissent qu’une fois.
2. Sélectionner « Avant 👋 » puis lancer la même dictée. Vérifier que la sélection est conservée dans le texte, suivie de la dictée. Dans TextEdit, mettre le suffixe en gras et vérifier son style après plusieurs corrections.
3. Cliquer sur **Terminer** au milieu d’une phrase. Vérifier l’arrêt du micro, la finalisation, la fermeture du panneau, le retour immédiat à la saisie et l’absence d’envoi.
4. Relancer, puis cliquer dans un deuxième champ de la même app pendant une hypothèse provisoire. Refaire avec une autre application, avec une frappe manuelle, puis avec un déplacement du curseur pendant une pause. Le texte visible doit rester en place et aucun résultat tardif ne doit aller dans l’autre champ.
5. Répéter avec un champ vide. Si le clic droit manque, consigner son absence même si le raccourci réussit. Si l’hôte refuse l’écriture, vérifier le message et l’absence d’activité micro.

## Autorisations, audio et affichage

| Essai | Résultat à constater | État |
|---|---|---|
| Accessibilité et Microphone, refus puis autorisation | Explication française, ouverture du bon réglage, reprise depuis le champ | À tester |
| Modèle français absent, puis installé | « Préparation de la dictée française », puis transcription après coupure du Wi-Fi et relance de l’app | À tester |
| Champ protégé ou non éditable | Message bref, aucun échantillon capturé et aucune écriture | À tester |
| Changement de micro ou débranchement | Arrêt propre, nouvelle session possible | À tester |
| Silence puis voix forte | Onde liée au niveau sonore, redevient plate dans le silence | À tester |
| Panneau sur écran secondaire ou en plein écran | Panneau lisible dans la zone visible, app hôte toujours active | À tester |
| Clair, sombre, Réduire les animations et VoiceOver | Bouton nommé, texte lisible, niveau discret en mode réduit | À tester |
| Deux déclenchements rapides, fin pendant préparation | Une seule session, micro libéré, aucun résultat tardif | À tester |
| Raccourci modifié, conflit et relance de l’app | Nouveau choix mémorisé, conflit signalé, précédent raccourci disponible | À tester |
| DMG de distribution sur un autre Mac | Glisser dans Applications, vérification Gatekeeper, lancement, dictée et désinstallation | À tester |
