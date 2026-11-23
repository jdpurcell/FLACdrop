import SwiftUI
import UniformTypeIdentifiers

struct FileFailure: Identifiable {
    let id = UUID()
    let filename: String
    let message: String
}

@MainActor
final class EncodingModel: ObservableObject {
    @Published var running = false
    @Published var current = 0
    @Published var total = 0
    @Published var fraction = 0.0
    @Published var filename = ""
    @Published var failures: [FileFailure] = []
    @Published var showFailures = false
    @Published var showSuccess = false
    @Published var succeeded = 0

    func start(_ urls: [URL], options: EncodingOptions) {
        guard !running, !urls.isEmpty else { return }
        let urls = naturallySortedFiles(urls)
        running = true
        failures = []
        succeeded = 0
        total = urls.count
        Task {
            for (index, url) in urls.enumerated() {
                current = index + 1
                filename = url.lastPathComponent
                fraction = 0
                let error: String? = await Task.detached(priority: .userInitiated) {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    do {
                        var lastUpdate = Date.distantPast
                        try encodeFile(url, options: options) { value in
                            let now = Date()
                            if value == 1 || now.timeIntervalSince(lastUpdate) >= 0.01 {
                                lastUpdate = now
                                Task { @MainActor in
                                    if self.running && self.current == index + 1 {
                                        self.fraction = value
                                    }
                                }
                            }
                        }
                        return nil
                    } catch { return error.localizedDescription }
                }.value
                if let error { failures.append(FileFailure(filename: url.lastPathComponent, message: error)) }
                else { succeeded += 1 }
            }
            running = false
            fraction = 0
            if failures.isEmpty { showSuccess = true } else { showFailures = true }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct FLACdropApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = EncodingModel()
    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appInfo) {
                Button("About FLACdrop") {
                    NSApp.orderFrontStandardAboutPanel(options: [.version: ""])
                }
            }
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: EncodingModel
    @AppStorage("compressionLevel") private var compression = 8
    @AppStorage("verifyEncoding") private var verify = true
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 10) {
                Image(systemName: "waveform.badge.plus").font(.system(size: 32)).foregroundStyle(.secondary)
                Text("Drop files here").font(.title2)
                Text("Mono or stereo • PCM or Apple Lossless").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).frame(height: 160)
            .background(targeted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(targeted ? Color.accentColor : Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [6])))
            .dropDestination(for: URL.self) { urls, _ in
                guard !model.running else { return false }
                let files = urls.filter(\.isFileURL)
                guard !files.isEmpty else { return false }
                model.start(files, options: EncodingOptions(compression: UInt32(min(8, max(0, compression))), verify: verify))
                return true
            } isTargeted: { targeted = $0 && !model.running }
            HStack(spacing: 20) {
                HStack(spacing: 8) {
                    Text("Compression level")
                    Picker("Compression level", selection: $compression) {
                        ForEach(0...8, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 56)
                }
                Toggle("Verify encoded audio", isOn: $verify)
                    .toggleStyle(.checkbox)
            }.disabled(model.running)
            if model.running {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.filename).lineLimit(1).truncationMode(.middle).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Text("File \(model.current) of \(model.total):").monospacedDigit()
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.secondary.opacity(0.2))
                                Capsule().fill(Color.accentColor)
                                    .frame(width: geometry.size.width * min(1, max(0, model.fraction)))
                            }
                        }
                            .frame(height: 6)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Encoding progress")
                            .accessibilityValue("\(Int(model.fraction * 100)) percent")
                            .transaction { transaction in
                                transaction.animation = nil
                            }
                        Text("\(Int(model.fraction * 100))%").monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                }
            }
        }
        .padding(24).frame(width: 440)
        .alert("All files encoded successfully.", isPresented: $model.showSuccess) { Button("OK", role: .cancel) {} }
        .sheet(isPresented: $model.showFailures) {
            VStack(alignment: .leading, spacing: 16) {
                Text("\(model.succeeded) of \(model.total) files encoded successfully.").font(.headline)
                Text("The following files failed:")
                Table(model.failures) {
                    TableColumn("Filename", value: \.filename).width(min: 150, ideal: 190)
                    TableColumn("Error", value: \.message)
                }.frame(minHeight: 180)
                HStack { Spacer(); Button("OK") { model.showFailures = false }.keyboardShortcut(.defaultAction) }
            }.padding(24).frame(width: 700, height: 350)
        }
    }
}
