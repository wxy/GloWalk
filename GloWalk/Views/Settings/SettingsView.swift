import SwiftUI
import CoreData
import AVFoundation
import CoreLocation

struct SettingsView: View {
    @StateObject private var prefs = UserPreferences.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showClearConfirm = false
    @State private var clearDone = false
    @State private var taglineSeed = 0

    var body: some View {
        NavigationView {
            ZStack {
                Color.gloBlackSurface.ignoresSafeArea()
                Form {
                    Section { languageSection } header: { sectionHeader(L10n.settingsLanguage) }
                    Section { brightnessSection } header: { sectionHeader(L10n.settingsLighting) }
                    Section { arrivalSection } header: { sectionHeader(L10n.settingsArrival) }
                    Section { dataSection } header: { sectionHeader(L10n.settingsData) }
                    Section { taglineSection } header: { sectionHeader(Text("")) }
                    Section {
                        HStack {
                            Text(L10n.settingsVersion).font(.gloBody(14)).foregroundColor(.white.opacity(0.5))
                            Spacer()
                            Text(L10n.settingsVersionValue).font(.gloBody(13)).foregroundColor(.white.opacity(0.3))
                        }
                    } header: { sectionHeader(L10n.settingsAbout) }
                }
            }
            .navigationTitle(L10n.settingsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.settingsDone) { dismiss() }.font(.gloBody(14)).foregroundColor(.gloGold)
                }
            }
        }
        .preferredColorScheme(.dark)
        .alert(L10n.settingsClearTitle, isPresented: $showClearConfirm) {
            Button(L10n.settingsCancel, role: .cancel) {}
            Button(L10n.settingsClear, role: .destructive) { clearData() }
        } message: { Text(L10n.settingsClearMessage) }
    }

    // MARK: - Sections

    private var languageSection: some View {
        Picker(L10n.settingsLanguage, selection: $prefs.language) {
            Text(L10n.settingsFollowSystem).tag("system")
            Text("English").tag("en")
            Text("中文").tag("zh-Hans")
        }
        .font(.gloBody(14)).foregroundColor(.white)
    }

    private var brightnessSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.settingsDefaultBrightness).font(.gloBody(14)).foregroundColor(.white)
            Slider(value: $prefs.defaultBrightness, in: 0.3...1.0, step: 0.05).tint(.gloGold)
        }
    }

    private var arrivalSection: some View {
        Toggle(L10n.settingsAutoArrival, isOn: $prefs.enableWiFiArrival)
            .tint(.gloGold).font(.gloBody(14)).foregroundColor(.white)
    }

    private var dataSection: some View {
        Group {
            NavigationLink { PermissionsView() } label: {
                Text(L10n.settingsPermissions).font(.gloBody(14)).foregroundColor(.white)
            }
            Button(action: { showClearConfirm = true }) {
                HStack {
                    Text(L10n.settingsClearRecords).font(.gloBody(14)).foregroundColor(.red)
                    Spacer()
                    if clearDone { Text(L10n.settingsCleared).font(.gloBody(12)).foregroundColor(.gloGold) }
                }
            }
        }
    }

    private var taglineSection: some View {
        let _ = taglineSeed  // force refresh when seed changes
        let t = Tagline.random()
        return VStack(spacing: 8) {
            Text("\u{201C}\(t.localizedPhrase)\u{201D}")
                .font(.gloHeadline(14)).foregroundColor(.gloGold)
                .multilineTextAlignment(.center)
            Text(t.localizedExplanation)
                .font(.gloBody(11)).foregroundColor(.white.opacity(0.35))
                .multilineTextAlignment(.center)
            Button(action: { taglineSeed += 1 }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 10))
                    Text(L10n.settingsRefreshTagline).font(.gloBody(10))
                }
                .foregroundColor(.gloGold.opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func sectionHeader(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.gloBody(12)).foregroundColor(.white.opacity(0.4))
    }
    private func sectionHeader(_ text: Text) -> some View {
        text.font(.gloBody(12)).foregroundColor(.white.opacity(0.4))
    }

    private func clearData() {
        let ctx = PersistenceController.shared.container.viewContext
        let req: NSFetchRequest<NSFetchRequestResult> = WalkSession.fetchRequest()
        _ = try? ctx.execute(NSBatchDeleteRequest(fetchRequest: req))
        PersistenceController.shared.save()
        clearDone = true
        Haptic.medium()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { clearDone = false }
    }
}

// MARK: - Permissions

struct PermissionsView: View {
    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var locationStatus: CLAuthorizationStatus = CLLocationManager().authorizationStatus

    var body: some View {
        ZStack {
            Color.gloBlackSurface.ignoresSafeArea()
            List {
                permCard(icon: "camera.fill", title: L10n.permissionsCamera,
                         granted: cameraStatus == .authorized,
                         statusTextKey: statusText(cameraStatus),
                         features: [L10n.permissionsCameraFeature1, L10n.permissionsCameraFeature2],
                         action: { openSettings() })
                permCard(icon: "location.fill", title: L10n.permissionsLocation,
                         granted: locationStatus == .authorizedWhenInUse || locationStatus == .authorizedAlways,
                         statusTextKey: statusText(locationStatus),
                         features: [L10n.permissionsLocationFeature1, L10n.permissionsLocationFeature2, L10n.permissionsLocationFeature3],
                         action: { openSettings() })
            }
            .listStyle(.plain)
        }
        .navigationTitle(L10n.settingsPermissions)
        .onAppear {
            cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
            locationStatus = CLLocationManager().authorizationStatus
        }
    }

    private func permCard(icon: String, title: LocalizedStringKey, granted: Bool,
                          statusTextKey: LocalizedStringKey,
                          features: [LocalizedStringKey], action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon).foregroundColor(granted ? .green : .red)
                Text(title).font(.gloBody(14)).foregroundColor(.white)
                Spacer()
                Text(statusTextKey).font(.gloBody(11))
                    .foregroundColor(granted ? .green.opacity(0.7) : .red.opacity(0.5))
            }
            ForEach(Array(features.enumerated()), id: \.offset) { _, f in
                (Text("· ") + Text(f))
                    .font(.gloBody(11)).foregroundColor(.white.opacity(0.5))
            }
            Button(L10n.permissionsOpenSettings) { action() }
                .font(.gloBody(11)).foregroundColor(.gloGold)
        }
        .padding(.vertical, 6)
        .listRowBackground(Color.gloBlackCard)
    }

    private func statusText(_ s: AVAuthorizationStatus) -> LocalizedStringKey {
        switch s {
        case .authorized: return L10n.permissionsAuthorized
        case .denied: return L10n.permissionsDenied
        case .notDetermined: return L10n.permissionsNotDetermined
        default: return L10n.permissionsRestricted
        }
    }
    private func statusText(_ s: CLAuthorizationStatus) -> LocalizedStringKey {
        switch s {
        case .authorizedAlways, .authorizedWhenInUse: return L10n.permissionsAuthorized
        case .denied: return L10n.permissionsDenied
        case .notDetermined: return L10n.permissionsNotDetermined
        default: return L10n.permissionsRestricted
        }
    }
    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
