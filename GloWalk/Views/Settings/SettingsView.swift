import SwiftUI
import CoreData

struct SettingsView: View {
    @StateObject private var prefs = UserPreferences.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Color.gloBlackSurface.ignoresSafeArea()
                Form {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("起始亮度").font(.gloBody(14)).foregroundColor(.white)
                            Slider(value: $prefs.defaultBrightness, in: 0.3...1.0, step: 0.05)
                                .tint(.gloGold)
                        }
                    } header: {
                        Text("照明偏好").font(.gloBody(12)).foregroundColor(.white.opacity(0.4))
                    }

                    Section {
                        Toggle("自动到达检测", isOn: $prefs.enableWiFiArrival)
                            .tint(.gloGold)
                            .font(.gloBody(14)).foregroundColor(.white)
                    } header: {
                        Text("安全到达").font(.gloBody(12)).foregroundColor(.white.opacity(0.4))
                    }

                    Section {
                        NavigationLink {
                            PermissionsView()
                        } label: {
                            Text("权限与隐私").font(.gloBody(14)).foregroundColor(.white)
                        }
                        Button("清除步行记录") { clearData() }
                            .font(.gloBody(14)).foregroundColor(.red)
                    } header: {
                        Text("数据").font(.gloBody(12)).foregroundColor(.white.opacity(0.4))
                    }

                    Section {
                        HStack {
                            Text("版本 1.0 · 随行路灯").font(.gloBody(13))
                            Spacer()
                        }
                        .foregroundColor(.white.opacity(0.4))
                        Text("踽踽独行，脚下有光")
                            .font(.gloBody(14)).foregroundColor(.gloGold)
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                        .font(.gloBody(14)).foregroundColor(.gloGold)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func clearData() {
        let ctx = PersistenceController.shared.container.viewContext
        let req: NSFetchRequest<NSFetchRequestResult> = WalkSession.fetchRequest()
        _ = try? ctx.execute(NSBatchDeleteRequest(fetchRequest: req))
        PersistenceController.shared.save()
    }
}

struct PermissionsView: View {
    var body: some View {
        ZStack {
            Color.gloBlackSurface.ignoresSafeArea()
            Text("权限管理")
                .font(.gloBody(14)).foregroundColor(.white)
        }
        .navigationTitle("权限与隐私")
    }
}
