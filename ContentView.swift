import SwiftUI
import Charts

struct ContentView: View {
    @EnvironmentObject private var manager: TelevisionManager
    @EnvironmentObject private var remote: LGTVRemote
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var choreTitle = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    weekendBudget
                    choreTimer
                    televisionControls
                    lgTVControls
                    historyChart
                    Text("La commande LG est déclenchée lorsque le temps mesuré par l’application atteint zéro, uniquement si iOS laisse l’application fonctionner. L’application ne peut pas empêcher le rallumage de la TV.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Tempo Télé")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Réglages", systemImage: "gearshape") { showSettings = true }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .onAppear { checkAndCutOff() }
            .onChange(of: manager.hasReachedLimit) { _, reached in
                if reached { checkAndCutOff() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { manager.refresh(); checkAndCutOff() }
            }
        }
    }

    private func checkAndCutOff() {
        guard remote.automaticPowerOff, remote.paired,
              manager.isRunning, manager.hasReachedLimit else { return }
        Task { await remote.turnOff() }
    }

    private var lgTVControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("LG UR73006LA", systemImage: "tv")
                .font(.headline)
            Text(remote.paired ? "Associée au réseau local" : "Non associée — ouvrez les réglages pour connecter la TV")
                .font(.subheadline)
            Text(remote.status).font(.caption).foregroundStyle(.secondary)
            Toggle("Extinction automatique en fin de crédit", isOn: $remote.automaticPowerOff)
                .disabled(!remote.paired)
            Button("Configurer la connexion LG", systemImage: "network") { showSettings = true }
            Text("L’iPhone et la télévision doivent être sur le même réseau. L’extinction automatique n’est pas garantie en arrière-plan et ne constitue pas un verrouillage parental.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    private var weekendBudget: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Budget du week-end", systemImage: "calendar")
                .font(.headline)
            Text(manager.weekendDateDescription)
                .font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                dayBudget("Samedi", initial: manager.saturdayInitialSeconds,
                          allowed: manager.saturdayAllowedSeconds,
                          remaining: manager.saturdayRemainingSeconds,
                          used: manager.saturdayUsedSeconds)
                dayBudget("Dimanche", initial: manager.sundayInitialSeconds,
                          allowed: manager.sundayAllowedSeconds,
                          remaining: manager.sundayRemainingSeconds,
                          used: manager.sundayUsedSeconds)
            }
            HStack {
                budgetFigure("Prévu", value: "\(manager.weekendLimitMinutes) min")
                Spacer()
                budgetFigure("Bonus", value: "+\(manager.weekendEarnedBonusMinutes) min", color: .green)
                Spacer()
                budgetFigure("Pénalités", value: "−\(roundedMinutes(manager.weekendPenaltySeconds))", color: .orange)
            }
            Divider()
            Button("Modifier le temps initial", systemImage: "pencil") {
                showSettings = true
            }
            .font(.subheadline)
            Text("Temps initial configurable pour chaque jour. Bonus et pénalités répartis à 50/50. Aucun report de minutes entre samedi et dimanche.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Bonus maximum : 20 min par week-end (\(manager.weekendEarnedBonusMinutes)/20 obtenues).")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    private func dayBudget(_ day: String, initial: TimeInterval, allowed: TimeInterval,
                           remaining: TimeInterval, used: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(day).font(.headline)
            Text("Initial : \(duration(initial))")
                .font(.caption2).foregroundStyle(.secondary)
            Text(duration(remaining))
                .font(.title3.bold()).monospacedDigit().minimumScaleFactor(0.7)
            Text("restant").font(.caption).foregroundStyle(.secondary)
            ProgressView(value: min(1, used / max(1, allowed)))
                .tint(.teal)
            Text("Crédit ajusté : \(duration(allowed))")
                .font(.caption2).foregroundStyle(.secondary)
            Text("Utilisé : \(duration(used))")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private func budgetFigure(_ label: String, value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).foregroundStyle(color)
        }
    }

    private var choreTimer: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Une demande à faire", systemImage: "timer")
                .font(.headline)
            if manager.isChoreRunning {
                Text(manager.activeChoreTitle).font(.subheadline)
                Text(clock(manager.choreElapsed))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(manager.choreElapsed > 300 ? .orange : .primary)
                if manager.choreElapsed < 270 {
                    Text("Bonus +5 min si elle commence avant 5:00.")
                } else if manager.choreElapsed <= 300 {
                    Label("Il reste \(Int(max(0, 300 - manager.choreElapsed))) secondes !", systemImage: "bell.fill")
                        .foregroundStyle(.orange)
                } else {
                    Text("Délai dépassé : le temps total écoulé sera retiré du crédit TV.")
                        .foregroundStyle(.orange)
                }
                Button {
                    manager.finishChore()
                } label: {
                    Label("Elle a commencé — arrêter", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent).tint(.teal)
            } else {
                TextField("Ex. : ranger sa chambre", text: $choreTitle)
                    .textFieldStyle(.roundedBorder)
                Button {
                    manager.startChore(title: choreTitle)
                    choreTitle = ""
                } label: {
                    Label("Lancer les 5 minutes", systemImage: "play.circle.fill")
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                Text("Une alerte sonore est prévue à 4 min 30 s. Le compteur continue après 5 min tant que vous n’avez pas appuyé sur « Elle a commencé ».")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !manager.weekendRecords.isEmpty {
                Divider()
                Text("Dernières demandes pour ce week-end").font(.subheadline.bold())
                ForEach(Array(manager.weekendRecords.prefix(5))) { record in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(record.title).font(.subheadline)
                            Text("Temps de réaction : \(clock(record.elapsedSeconds))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(record.adjustmentSeconds > 0 ? "+\(Int(record.adjustmentSeconds / 60)) min" :
                            record.adjustmentSeconds < 0 ? "−\(roundedMinutes(-record.adjustmentSeconds))" : "+0 min")
                            .font(.subheadline.bold())
                            .foregroundStyle(record.adjustmentSeconds < 0 ? .orange : .green)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    private var televisionControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Télévision", systemImage: "tv")
                .font(.headline)
            if !manager.isWeekend {
                Text("Aujourd’hui : \(duration(manager.remainingSeconds)) disponibles sur \(manager.dailyLimitMinutes) min.")
                    .font(.subheadline)
            } else {
                Text("Temps restant aujourd’hui : \(duration(manager.remainingSeconds)) (crédit ajusté du jour : \(duration(manager.todayAllowedSeconds))).")
                    .font(.subheadline)
            }
            Button {
                manager.isRunning ? manager.stop() : manager.start()
            } label: {
                Label(manager.isRunning ? "Arrêter la télévision" : "Démarrer la télévision",
                      systemImage: manager.isRunning ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(manager.isRunning ? .orange : .teal)
            .disabled(!manager.isRunning && manager.hasReachedLimit)
            if manager.hasReachedLimit {
                Label("Crédit télévision épuisé", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.orange).font(.caption)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    private var historyChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Télévision : 7 derniers jours").font(.headline)
            Chart {
                ForEach((0..<7).reversed(), id: \.self) { offset in
                    if let day = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) {
                        BarMark(x: .value("Jour", day, unit: .day),
                                y: .value("Minutes", manager.secondsUsed(on: day) / 60))
                            .foregroundStyle(.teal.gradient)
                    }
                }
            }
            .frame(height: 150)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
    }
}

func duration(_ seconds: TimeInterval) -> String {
    let total = Int(max(0, seconds))
    let minutes = total / 60
    let remainingSeconds = total % 60
    let basic = String(format: "%d h %02d min", minutes / 60, minutes % 60)
    return remainingSeconds == 0 ? basic : "\(basic) \(remainingSeconds) s"
}

func clock(_ seconds: TimeInterval) -> String {
    let total = Int(max(0, seconds))
    return String(format: "%02d:%02d", total / 60, total % 60)
}

func roundedMinutes(_ seconds: TimeInterval) -> String {
    let minutes = Int(seconds) / 60
    let remainder = Int(seconds) % 60
    return remainder == 0 ? "\(minutes) min" : "\(minutes) min \(remainder) s"
}
