//
//  ContentView.swift
//  Simple Timer
//
//  Created by Tony Newpower on 4/21/26.
//

import SwiftUI
import AVFoundation
import AudioToolbox
import Combine
import UserNotifications
import UIKit

struct ContentView: View {
    @StateObject private var viewModel = TimerViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()
                
                HStack(spacing: 12) {
                    presetButton(
                        title: "30s",
                        isSelected: viewModel.selectedPreset == "30s"
                    ) {
                        viewModel.setPreset(seconds: 30, label: "30s")
                    }

                    presetButton(
                        title: "15m",
                        isSelected: viewModel.selectedPreset == "15m"
                    ) {
                        viewModel.setPreset(minutes: 15, label: "15m")
                    }

                    presetButton(
                        title: "30m",
                        isSelected: viewModel.selectedPreset == "30m"
                    ) {
                        viewModel.setPreset(minutes: 30, label: "30m")
                    }
                }
                .padding(.horizontal)

                if viewModel.isRunning || viewModel.isPaused {
                    ZStack {
                        Circle()
                            .stroke(Color(.systemGray5), lineWidth: 18)

                        Circle()
                            .trim(from: 0, to: viewModel.smoothProgress)
                            .stroke(
                                viewModel.isPaused ? Color.orange : Color.blue,
                                style: StrokeStyle(lineWidth: 18, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.05), value: viewModel.smoothProgress)

                        VStack(spacing: 10) {
                            Text(viewModel.timeRemainingString)
                                .font(.system(size: 48, weight: .semibold, design: .rounded))
                                .monospacedDigit()

                            Text(viewModel.isPaused ? "Paused" : "Timer")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                    }
                    .frame(width: 300, height: 300)
                } else {
                    HStack(spacing: 0) {
                        Picker("Hours", selection: $viewModel.selectedHours) {
                            ForEach(0..<24, id: \.self) { hour in
                                Text("\(hour) hr").tag(hour)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)

                        Picker("Minutes", selection: $viewModel.selectedMinutes) {
                            ForEach(0..<60, id: \.self) { minute in
                                Text("\(minute) min").tag(minute)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)

                        Picker("Seconds", selection: $viewModel.selectedSeconds) {
                            ForEach(0..<60, id: \.self) { second in
                                Text("\(second) sec").tag(second)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)
                    }
                    .frame(height: 180)
                }

                Spacer()

                HStack(spacing: 20) {
                    Button(role: .destructive) {
                        viewModel.cancelTimer()
                    } label: {
                        Text(viewModel.isRunning || viewModel.isPaused ? "Cancel" : "Clear")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray5))
                            .clipShape(Capsule())
                    }
                    .disabled(!viewModel.canClearOrCancel)

                    Button {
                        if viewModel.isRunning {
                            viewModel.pauseTimer()
                        } else if viewModel.isPaused {
                            viewModel.resumeTimer()
                        } else {
                            viewModel.startTimer()
                        }
                    } label: {
                        Text(viewModel.primaryButtonTitle)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(viewModel.primaryButtonColor)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                    .disabled(!viewModel.canStartOrControl)
                }
                .padding(.horizontal)
                .padding(.bottom, 28)
            }
            .padding()
            .navigationTitle("Timer")
            .alert("Time’s Up", isPresented: $viewModel.showingFinishedAlert) {
                Button("OK") {
                    viewModel.stopAlarm()
                }
            } message: {
                Text("Your timer has finished.")
            }
            .onChange(of: scenePhase) { _, newPhase in
                viewModel.updateScenePhase(newPhase)
            }
            .onAppear {
                viewModel.updateScenePhase(scenePhase)
                viewModel.handleAppLaunchState()
            }
           /* .onDisappear {
                viewModel.stopAlarm()
            }*/
        }
    }
    
    @ViewBuilder
    private func presetButton(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    isSelected ? Color.blue : Color(.systemGray5)
                )
                .foregroundStyle(
                    isSelected ? .white : .primary
                )
                .clipShape(Capsule())
        }
    }
}

final class TimerViewModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var selectedHours: Int = 0
    @Published var selectedMinutes: Int = 1
    @Published var selectedSeconds: Int = 0
    @Published var timeRemaining: Int = 60
    @Published var isRunning: Bool = false
    @Published var isPaused: Bool = false
    @Published var showingFinishedAlert: Bool = false
    @Published private(set) var initialDuration: Int = 60
    @Published var smoothProgress: CGFloat = 1.0
    @Published var selectedPreset: String? = nil

    private var timer: Timer?
    private var player: AVAudioPlayer?
    private var endDate: Date?
    private var currentScenePhase: ScenePhase = .active

    private let notificationCenter = UNUserNotificationCenter.current()
    private let timerNotificationID = "simple_timer_notification"

    var totalSelectedSeconds: Int {
        (selectedHours * 3600) + (selectedMinutes * 60) + selectedSeconds
    }

    var progress: CGFloat {
        guard initialDuration > 0 else { return 0 }
        return CGFloat(timeRemaining) / CGFloat(initialDuration)
    }

    var timeRemainingString: String {
        let hours = timeRemaining / 3600
        let minutes = (timeRemaining % 3600) / 60
        let seconds = timeRemaining % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    var primaryButtonTitle: String {
        if isRunning { return "Pause" }
        if isPaused { return "Resume" }
        return "Start"
    }

    var primaryButtonColor: Color {
        if isRunning { return .orange }
        return .green
    }

    var canStartOrControl: Bool {
        if isRunning || isPaused { return true }
        return totalSelectedSeconds > 0
    }

    var canClearOrCancel: Bool {
        isRunning || isPaused || totalSelectedSeconds > 0
    }
    
    override init() {
        super.init()
    }

    func startTimer() {
        guard totalSelectedSeconds > 0 else { return }

        stopExistingTimer()
        stopAlarm()
        cancelScheduledNotification()

        let duration = totalSelectedSeconds
        initialDuration = duration
        timeRemaining = duration
        smoothProgress = 1.0
        endDate = Date().addingTimeInterval(TimeInterval(duration))

        isRunning = true
        isPaused = false

        scheduleNotification(after: duration)
        startTicking()
        persistState()
    }

    func pauseTimer() {
        guard let endDate else { return }

        timeRemaining = max(Int(ceil(endDate.timeIntervalSinceNow)), 0)
        smoothProgress = initialDuration > 0
            ? CGFloat(Double(timeRemaining) / Double(initialDuration))
            : 0
        self.endDate = nil

        stopExistingTimer()
        cancelScheduledNotification()

        isRunning = false
        isPaused = true
        persistState()
    }

    func resumeTimer() {
        guard timeRemaining > 0 else { return }

        stopExistingTimer()
        stopAlarm()
        cancelScheduledNotification()

        endDate = Date().addingTimeInterval(TimeInterval(timeRemaining))
        initialDuration = max(initialDuration, timeRemaining)

        isRunning = true
        isPaused = false

        scheduleNotification(after: timeRemaining)
        startTicking()
        persistState()
    }

    func cancelTimer() {
        stopExistingTimer()
        stopAlarm()
        cancelScheduledNotification()

        isRunning = false
        isPaused = false
        endDate = nil
        timeRemaining = totalSelectedSeconds
        initialDuration = max(totalSelectedSeconds, 1)
        
        smoothProgress = totalSelectedSeconds > 0 ? 1.0 : 0

        clearPersistedState()
    }

    func handleAppLaunchState() {
        restoreStateIfNeeded()
    }

    private func startTicking() {
        stopExistingTimer()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.updateTimeRemaining()
        }
    }

    private func updateTimeRemaining() {
        guard let endDate else { return }

        let secondsLeft = max(endDate.timeIntervalSinceNow, 0)

        if secondsLeft <= 0 {
            timeRemaining = 0
            smoothProgress = 0
            finishTimer()
        } else {
            timeRemaining = Int(ceil(secondsLeft))
            smoothProgress = initialDuration > 0
                ? CGFloat(secondsLeft / Double(initialDuration))
                : 0
            persistState()
        }
    }

    private func finishTimer() {
        stopExistingTimer()
        endDate = nil
        isRunning = false
        isPaused = false
        timeRemaining = 0
        smoothProgress = 0

        clearPersistedState()

        if currentScenePhase == .active {
            cancelScheduledNotification()
            showingFinishedAlert = true
            playAlarm()
        }
    }
    
    private func stopExistingTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func playAlarm() {
        configureAlarmAudioSession()

        guard let soundURL = Bundle.main.url(forResource: "ping", withExtension: "caf") else {
            print("Foreground alarm file not found")
            return
        }

        do {
            player = try AVAudioPlayer(contentsOf: soundURL)
            player?.delegate = self
            player?.numberOfLoops = 2   // 3 plays total
            player?.prepareToPlay()
            player?.play()
        } catch {
            print("Foreground alarm failed: \(error)")
        }
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        stopAlarm()
    }

    func stopAlarm() {
        player?.stop()
        player = nil

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            print("Audio session deactivation failed: \(error)")
        }
    }

    private func scheduleNotification(after seconds: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Time’s Up"
        content.body = "Your timer has finished."
        content.sound = UNNotificationSound(named: UNNotificationSoundName("ping.caf"))

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(max(seconds, 1)),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: timerNotificationID,
            content: content,
            trigger: trigger
        )

        notificationCenter.add(request) { error in
            if let error = error {
                print("Notification add error:", error)
            } else {
                print("Scheduled notification with sound")
            }
        }
        
        notificationCenter.getPendingNotificationRequests { requests in
            for request in requests {
                print("Pending ID:", request.identifier)
                print("Pending sound:", String(describing: request.content.sound))
            }
        }
    }

    private func cancelScheduledNotification() {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [timerNotificationID])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [timerNotificationID])
    }

    private func persistState() {
        UserDefaults.standard.set(timeRemaining, forKey: "timer_timeRemaining")
        UserDefaults.standard.set(initialDuration, forKey: "timer_initialDuration")
        UserDefaults.standard.set(isRunning, forKey: "timer_isRunning")
        UserDefaults.standard.set(isPaused, forKey: "timer_isPaused")
        UserDefaults.standard.set(endDate, forKey: "timer_endDate")
    }

    private func clearPersistedState() {
        UserDefaults.standard.removeObject(forKey: "timer_timeRemaining")
        UserDefaults.standard.removeObject(forKey: "timer_initialDuration")
        UserDefaults.standard.removeObject(forKey: "timer_isRunning")
        UserDefaults.standard.removeObject(forKey: "timer_isPaused")
        UserDefaults.standard.removeObject(forKey: "timer_endDate")
    }
    
    func updateScenePhase(_ phase: ScenePhase) {
        currentScenePhase = phase
    }

    private func configureAlarmAudioSession() {
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            print("Audio session setup failed: \(error)")
        }
    }
    
    func setPreset(hours: Int = 0, minutes: Int = 0, seconds: Int = 0, label: String) {
        stopExistingTimer()
        stopAlarm()
        cancelScheduledNotification()

        selectedHours = hours
        selectedMinutes = minutes
        selectedSeconds = seconds

        let total = (hours * 3600) + (minutes * 60) + seconds
        timeRemaining = total
        initialDuration = max(total, 1)
        smoothProgress = total > 0 ? 1.0 : 0

        isRunning = false
        isPaused = false
        endDate = nil

        selectedPreset = label

        clearPersistedState()
    }

    private func restoreStateIfNeeded() {
        let savedIsRunning = UserDefaults.standard.bool(forKey: "timer_isRunning")
        let savedIsPaused = UserDefaults.standard.bool(forKey: "timer_isPaused")
        let savedTimeRemaining = UserDefaults.standard.integer(forKey: "timer_timeRemaining")
        let savedInitialDuration = UserDefaults.standard.integer(forKey: "timer_initialDuration")
        let savedEndDate = UserDefaults.standard.object(forKey: "timer_endDate") as? Date

        initialDuration = max(savedInitialDuration, 1)

        if savedIsRunning, let savedEndDate {
            let remaining = max(Int(ceil(savedEndDate.timeIntervalSinceNow)), 0)

            if remaining > 0 {
                timeRemaining = remaining
                endDate = savedEndDate
                isRunning = true
                isPaused = false
                startTicking()
            } else {
                timeRemaining = 0
                finishTimer()
            }
        } else if savedIsPaused {
            timeRemaining = max(savedTimeRemaining, 0)
            isRunning = false
            isPaused = true
            endDate = nil
        } else {
            timeRemaining = max(savedTimeRemaining, 60)
        }
    }
}
