import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var manager: TelevisionManager
    @EnvironmentObject private var remote: LGTVRemote
    @State private var showPowerConfirmation = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Profil") {
                    TextField("Prénom", text: $manager.childName)
                }
                Section("Temps initial du week-end") {
                    Stepper(value: $manager.saturdayInitialMinutes, in: 0...600, step: 5) {
                        HStack {
                            Text("Samedi")
                            Spacer()
                            Text("\(manager.saturdayInitialMinutes) min")
                                .monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    Stepper(value: $manager.sundayInitialMinutes, in: 0...600, step: 5) {
                        HStack {
                            Text("Dimanche")
                            Spacer()
                            Text("\(manager.sundayInitialMinutes) min")
                                .monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Total initial", value: "\(manager.weekendLimitMinutes) min")
                    Button("Répartir le total à parts égales") {
                        let total = manager.weekendLimitMinutes
                        manager.saturdayInitialMinutes = (total / 10) * 5
                        manager.sundayInitialMinutes = total - manager.saturdayInitialMinutes
                    }
                    Text("Réglez le crédit de départ de chaque jour par tranches de 5 minutes. Les bonus et pénalités sont partagés à 50/50, même si les crédits initiaux sont différents. Aucun report d’un jour sur l’autre.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Du lundi au vendredi") {
                    Stepper(value: $manager.dailyLimitMinutes, in: 15...240, step: 5) {
                        Text("\(manager.dailyLimitMinutes) minutes par jour")
                    }
                    Text("Les récompenses et pénalités des demandes s’appliquent au week-end, pas au temps des jours de semaine.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Règles des demandes") {
                    Text("Début dans les 5 minutes : +5 min, maximum +20 min par week-end.")
                    Text("Début après 5 minutes : retrait du temps total écoulé entre la demande et le début de l’action.")
                    Text("Le temps de réaction est calculé à la seconde. Appuyez sur « Elle a commencé » dès qu’elle débute.")
                }
                Section("Télévision LG UR73006LA (webOS 23)") {
                    TextField("Adresse IP de la télévision", text: $remote.ipAddress)
                        .keyboardType(.decimalPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button(remote.isBusy ? "Connexion en cours…" : "Associer la TV") {
                        Task { await remote.pair() }
                    }
                    .disabled(remote.isBusy)
                    Toggle("Éteindre quand le crédit est épuisé", isOn: $remote.automaticPowerOff)
                        .disabled(!remote.paired)
                    Button("Tester l’extinction") { showPowerConfirmation = true }
                        .disabled(!remote.paired || remote.isBusy)
                    Button("Réinitialiser l’association LG", role: .destructive) { remote.forgetPairing() }
                        .disabled(remote.isBusy)
                    Text(remote.status).font(.footnote).foregroundStyle(.secondary)
                    Text("Allumez la TV, reliez l’iPhone au même Wi-Fi, saisissez l’IP trouvée dans Paramètres > Réseau sur la TV, puis acceptez la demande d’association sur l’écran du téléviseur. L’application communique en local via webOS.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Alertes sonores") {
                    Button("Autoriser les notifications") { manager.requestNotifications() }
                    Text("Alerte à 4 min 30 s, puis à 5 min. Pour être prévenu quand l’app est en arrière-plan ou verrouillée, autorisez les notifications et le son dans les réglages iOS. Le mode silencieux ou Concentration peut limiter les sons.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Text("Crédits et historique restent sur l’iPhone. Les identifiants LG sont protégés dans le trousseau iOS. La commande peut éteindre la TV, mais ne peut ni bloquer le rallumage, ni fonctionner de façon garantie en arrière-plan.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .confirmationDialog("Éteindre la télévision LG maintenant ?", isPresented: $showPowerConfirmation) {
                Button("Envoyer la commande d’extinction", role: .destructive) {
                    Task { await remote.turnOff() }
                }
            } message: { Text("La télévision va recevoir une commande d’extinction. Il s’agit d’un test.") }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Terminé") { dismiss() } } }
        }
    }
}
