# Tempo Télé — prototype iOS v5

Application native iPhone en SwiftUI (iOS 17 minimum). Le code source est livré avec un projet Xcode.

## Nouveau dans la v5 : connexion TV LG UR73006LA (webOS 23)

Ce projet contient un **client expérimental SSAP / WebSocket sécurisé (`wss://TV:3001`)** pour communiquer avec une TV LG webOS 23 sur le même réseau local. La première association doit être acceptée sur l'écran du téléviseur. Le secret d'association et l'empreinte du certificat TLS de la TV sont conservés dans le **Trousseau iOS**, avec vérification de l'empreinte lors des connexions suivantes. Aucune connexion à un serveur distant n'est nécessaire.

Configuration :
1. Allumer la LG UR73006LA et connecter l'iPhone et la télévision au même Wi-Fi ou réseau local.
2. Sur la TV, relever son **adresse IPv4** dans les paramètres Réseau. Une adresse privée du type `192.168.1.50` est attendue. Si l'adresse change au fil du temps, réserver l'IP de la TV dans le routeur.
3. Dans Tempo Télé, ouvrir **Réglages > Télévision LG UR73006LA** et saisir l'adresse IP.
4. Appuyer sur **Associer la TV** puis accepter la demande d'accès à la télévision avec la télécommande physique. Autoriser l'accès au réseau local sur iOS si la permission est demandée.
5. Appuyer sur **Tester l’extinction**, confirmer et vérifier physiquement que le téléviseur s'est éteint.
6. Activer **Éteindre quand le crédit est épuisé**. L'app envoie alors la commande lors du passage à zéro du compteur, **seulement lorsqu'iOS permet à l'application de s'exécuter**.

Si la demande d'association n'apparaît pas, vérifier l'activation du contrôle par application mobile (« LG Connect Apps » ou réglage équivalent), la connexion réseau et l'adresse IP. En cas de réinitialisation de la TV, utiliser **Réinitialiser l’association LG**. Il est possible qu'une mise à jour webOS ou certaines configurations de réseau empêchent cette méthode non officielle de fonctionner.

**Limites très importantes** : une application iPhone ne peut pas garantir l'envoi d'une commande sur le réseau local pendant qu'elle est en arrière-plan, verrouillée ou fermée ; même en premier plan, l'envoi de la commande n'est pas une confirmation physique de l'arrêt. Le compteur TV doit être démarré/arrêté manuellement ; cette version ne mesure pas automatiquement l'état réel ou la durée de fonctionnement de la télévision. Enfin, une TV éteinte à distance peut être rallumée avec sa télécommande ; pour imposer un verrouillage, utiliser le **contrôle parental natif LG** (Paramètres > Général > Contrôle parental / Paramètres famille > Limite d'utilisation) et changer le code par défaut. Celui-ci définit des **plages horaires**, pas des crédits dynamiques avec bonus.

## Temps du week-end
- Dans **Réglages > Temps initial du week-end**, définir **séparément** le nombre de minutes initiales pour le samedi et pour le dimanche, par pas de 5 minutes (de 0 à 600 min par jour). Par défaut : **60 min samedi et 60 min dimanche**. Le total est calculé automatiquement ; un bouton permet de le répartir à parts égales.
- Le crédit de chaque jour est indépendant. Par exemple, **90 minutes le samedi et 30 minutes le dimanche** est un réglage possible. Le suivi utilise le quota propre à chaque jour et une limite journalière distincte du lundi au vendredi.
- Si vous passez de la version 3 à la version 4 sur le même iPhone sans supprimer l'application, le temps total du week-end enregistré dans la v3 est réparti entre les deux jours, puis librement modifiable.
- Les minutes déjà regardées sont déduites du solde de leur journée. Le solde inutilisé du samedi ne se reporte pas au dimanche.

## Minuteur des demandes
1. Saisir éventuellement la demande (par exemple « Ranger sa chambre »).
2. Appuyer sur **Lancer les 5 minutes** au moment de la demande.
3. Alerte sonore à 4 min 30 s (il reste 30 secondes), puis à 5 min, sous réserve des autorisations et réglages sonores iOS.
4. Appuyer sur **Elle a commencé — arrêter** dès le début de l'action (pas quand la tâche est terminée).
5. Résultat automatique :
   - temps de réaction **inférieur ou égal à 5 min** : +5 minutes de télévision ; bonus maximum **20 minutes par week-end** ;
   - temps de réaction **supérieur à 5 min** : retrait de **toute la durée entre la demande et le début de l'action**, à la seconde (par exemple 6 min 10 s = −6 min 10 s).
6. Les récompenses et retraits s'appliquent au week-end en cours ou à venir. Les demandes et le chronomètre restent enregistrés si l'app est fermée.

Les **bonus et pénalités sont répartis à parts égales** entre samedi et dimanche même si le crédit initial est différent. Par exemple, avec 90 minutes le samedi et 30 minutes le dimanche, un bonus total de 10 minutes et une pénalité totale de 12 minutes donnent respectivement 89 et 29 minutes disponibles. Le bonus maximum de 20 minutes ne limite pas les retraits. Le crédit restant affiché ne descend pas sous zéro. Les ajustements sont enregistrés par week-end.

## Installer sur un iPhone
1. Sur un Mac, installez Xcode depuis le Mac App Store.
2. Décompressez l'archive et ouvrez `TempoTele.xcodeproj`.
3. Dans Xcode : **TempoTele > Signing & Capabilities**, choisissez une équipe Apple et, si demandé, personnalisez le Bundle Identifier `com.example.tempotele`.
4. Branchez l'iPhone, sélectionnez-le dans Xcode et lancez **Run**.
5. Dans les **Réglages** de l'application, appuyez sur **Autoriser les notifications**. Autorisez les sons dans les réglages iOS.

## Limites
- Le client LG essaie d'éteindre la télévision sur le réseau local, sans garantir que la commande aboutisse. **Il ne peut pas verrouiller la télévision ni la maintenir éteinte**. Le lancement et l'arrêt des séances TV restent manuels.
- Les sons ne sont pas garantis en mode silencieux, Concentration, ni si les notifications sont désactivées. Une alerte audio interne fonctionne quand l'app est au premier plan.
- Les récompenses dépendent du moment où le parent arrête le chronomètre : l'app ne détecte pas physiquement le début de l'action.
- Pas encore de code parental ou de synchronisation entre plusieurs iPhone.
- Le projet n'a pas été compilé dans Xcode ni testé sur une LG ou un iPhone dans cet environnement. L'analyse syntaxique Swift et le format du projet ont été vérifiés. Tester l'association, le certificat et la commande sur un équipement réel.
