# Tempo Télé — installation avec Windows (sans Mac)

Cette archive contient la version 5 (gestion du temps TV et connexion expérimentale LG UR73006LA), un icône iOS et un fichier `codemagic.yaml` avec deux parcours :

- **1 - Vérifier la compilation** : un Mac distant compile l’application pour simulateur, sans code signing. C’est un test technique : **il n’installe rien sur l’iPhone**. Compte Apple Developer payant non requis.
- **2 - Installer avec TestFlight** : nécessite un abonnement Apple Developer Program actif (99 USD/an, montant local variable), un identifiant d’application unique enregistré et une clé API App Store Connect. La compilation n’a pas encore été testée.

## 1 — Mettre le code sur GitHub (depuis Windows)

1. Aller sur https://github.com/ et ouvrir un compte si nécessaire.
2. Cliquer sur `New repository`. Nom : `TempoTele-iOS`. Choisir **Private**. Créer le dépôt sans fichier README initial pour simplifier.
3. Extraire le ZIP sur Windows. Dans `TempoTele`, repérer `TempoTele.xcodeproj`, `TempoTele` (dossier du code), `codemagic.yaml` et ce guide.
4. Dans GitHub, cliquer `uploading an existing file` ou `Add file > Upload files`, et déposer le **contenu** du dossier `TempoTele` (pas le ZIP lui-même). Vérifier que `codemagic.yaml` est **à la racine** du dépôt et pas dans un sous-dossier.
5. Valider le dépôt avec `Commit changes`.

Ne publier ni mot de passe Apple, ni clé `.p8` dans GitHub.

## 2 — Vérifier gratuitement la compilation

1. Aller sur https://codemagic.io/ et ouvrir un compte **individuel**.
2. Cliquer sur `Add application`, connecter GitHub et sélectionner `TempoTele-iOS`.
3. Choisir le projet iOS natif ; scanner le fichier `codemagic.yaml` si demandé.
4. Sélectionner le workflow **1 - Vérifier la compilation**, puis `Start new build`.
5. Lire le journal de build. Succès = projet compilé pour simulateur ; échec = récupérer les lignes d’erreur Swift/Xcode.

Le compte individuel Codemagic propose actuellement 500 minutes de compilation macOS M2 gratuites par mois. Cela ne remplace pas la signature Apple pour installer sur iPhone.

## 3 — Préparer TestFlight

Un titulaire majeur du compte Apple Developer doit réaliser cette partie (règle Apple d’âge légal de majorité).

1. S’inscrire à https://developer.apple.com/programs/enroll/ (abonnement annuel).
2. Choisir un identifiant de bundle unique, par exemple `fr.nomdefamille.tempotele` (à vérifier). Dans **deux fichiers**, remplacer `com.example.tempotele` par cet identifiant :
   - `TempoTele.xcodeproj/project.pbxproj` (2 occurrences),
   - `codemagic.yaml` (dans `bundle_identifier`; le commentaire n’est pas nécessaire).
3. Dans le portail Apple Developer, enregistrer le **Bundle ID** choisi dans Certificates, Identifiers & Profiles.
4. Dans https://appstoreconnect.apple.com/, créer une nouvelle fiche `Tempo Télé` (plateforme iOS) avec le même Bundle ID ; compléter les informations demandées.
5. Dans App Store Connect > Users and Access > Integrations > App Store Connect API, créer une clé API dédiée avec les autorisations appropriées (`App Manager`) et récupérer son `.p8`, son Key ID et l’Issuer ID. Ne pas partager cette clé dans un chat ou sur GitHub.
6. Dans Codemagic, sous Team integrations > Developer Portal, connecter cette clé sous le nom **`tempotele_key`**.
7. Dans Codemagic, sous Code signing identities, créer/téléverser un **certificat Apple Distribution** et un **profil App Store** correspondant au Bundle ID. Suivre https://docs.codemagic.io/yaml-code-signing/signing-ios/ .
8. Depuis Codemagic, choisir le workflow **2 - Installer sur iPhone via TestFlight**, puis `Start new build`. Il produit et téléverse une version iOS signée vers App Store Connect, sans publication publique sur l’App Store.
9. Sur App Store Connect > Tempo Télé > TestFlight, affecter le build à un groupe interne et ajouter le compte du testeur autorisé, puis accepter l’invitation sur iPhone depuis TestFlight.
10. Sur l’iPhone, télécharger TestFlight depuis l’App Store, ouvrir l’invitation reçue et toucher Installer. Si le build n’apparaît pas, vérifier son traitement et les informations demandées par Apple dans App Store Connect.

**Important** : les builds TestFlight sont des versions bêta à durée de vie limitée (90 jours). Pour une app utilisée durablement, prévoir une distribution pérenne.

## 4 — Tester sur iPhone et LG

- Sur iPhone : autoriser les notifications et le réseau local.
- Dans Tempo Télé : régler les minutes samedi/dimanche ; lancer une demande et vérifier les alertes à 4 min 30.
- Activer la TV LG UR73006LA sur le même réseau et saisir son adresse IP dans les réglages de Tempo Télé ; accepter l’association sur la télévision et tester l’extinction.
- La fonction LG est **expérimentale** et n’a pas été testée physiquement. Même associée, la TV peut être rallumée. L’app iPhone ne peut pas garantir une extinction quand elle est fermée ou en arrière-plan : ce n’est pas un véritable verrou parental.

## Liens officiels
- https://docs.codemagic.io/yaml-quick-start/building-a-native-ios-app/
- https://docs.codemagic.io/yaml-publishing/app-store-connect/
- https://developer.apple.com/testflight/
