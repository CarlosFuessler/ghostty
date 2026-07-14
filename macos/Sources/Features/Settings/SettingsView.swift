import SwiftUI
import Cocoa

// MARK: - Settings Window Controller
class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 350),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.center()
        window.isMovableByWindowBackground = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        
        self.init(window: window)
        window.delegate = self
        
        let appDelegate = NSApp.delegate as! AppDelegate
        window.contentView = NSHostingView(
            rootView: SettingsView()
                .environmentObject(appDelegate)
        )
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        window?.close()
    }
}

// MARK: - Keybind Presets
enum KeybindPreset: String, CaseIterable, Identifiable {
    case `default` = "Default (Ghostty Defaults)"
    case vim = "Vim Focus Navigation (Ctrl+Alt+HJKL)"
    case tmux = "Tmux Split Mode (Ctrl+a prefix)"
    
    var id: String { self.rawValue }
    
    var description: String {
        switch self {
        case .default:
            return "Uses standard split-pane shortcuts (e.g. Ctrl+Shift+O to split right, Ctrl+Shift+E to split down)."
        case .vim:
            return "Adds Vim-style focus navigation. Use Ctrl+Alt + H/J/K/L to navigate splits."
        case .tmux:
            return "Adds a Tmux-like modal mode. Press Ctrl+a to enter, HJKL to focus, Shift+HJKL to split, X to close. Escape/Enter exits."
        }
    }
}

// MARK: - Settings Manager
class SettingsManager {
    static let shared = SettingsManager()
    
    func getConfigFileURL() -> URL? {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let ghosttyDir = appSupportURL.appendingPathComponent("com.mitchellh.ghostty")
        
        let pathGhostty = ghosttyDir.appendingPathComponent("config.ghostty")
        if fileManager.fileExists(atPath: pathGhostty.path) {
            return pathGhostty
        }
        
        let pathConfig = ghosttyDir.appendingPathComponent("config")
        if fileManager.fileExists(atPath: pathConfig.path) {
            return pathConfig
        }
        
        return pathConfig
    }
    
    func readPreset() -> KeybindPreset {
        guard let url = getConfigFileURL(),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return .default
        }
        
        if content.contains("activate_key_table:window") {
            return .tmux
        } else if content.contains("ctrl+alt+h=goto_split:left") {
            return .vim
        }
        return .default
    }
    
    func savePreset(_ preset: KeybindPreset) {
        guard let url = getConfigFileURL() else { return }
        
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? "".write(to: url, atomically: true, encoding: .utf8)
        }
        
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        
        let lines = content.components(separatedBy: .newlines)
        var filteredLines: [String] = []
        var skippingPreset = false
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "# --- GHOSTTY PRESET START ---" {
                skippingPreset = true
                continue
            }
            if trimmed == "# --- GHOSTTY PRESET END ---" {
                skippingPreset = false
                continue
            }
            if skippingPreset {
                continue
            }
            filteredLines.append(line)
        }
        
        var newPresetContent = ""
        switch preset {
        case .default:
            break
        case .vim:
            newPresetContent = """
            # --- GHOSTTY PRESET START ---
            # Navigate splits using Ctrl+Alt + hjkl
            keybind = ctrl+alt+h=goto_split:left
            keybind = ctrl+alt+j=goto_split:down
            keybind = ctrl+alt+k=goto_split:up
            keybind = ctrl+alt+l=goto_split:right
            # --- GHOSTTY PRESET END ---
            """
        case .tmux:
            newPresetContent = """
            # --- GHOSTTY PRESET START ---
            # Tmux-style modal window management
            # Press Ctrl+a to enter "window" mode
            keybind = ctrl+a=activate_key_table:window

            # Navigate splits using hjkl
            keybind = window/h=goto_split:left
            keybind = window/j=goto_split:down
            keybind = window/k=goto_split:up
            keybind = window/l=goto_split:right

            # Split panes using Shift + HJKL (splits in that direction)
            keybind = window/shift+h=new_split:left
            keybind = window/shift+j=new_split:down
            keybind = window/shift+k=new_split:up
            keybind = window/shift+l=new_split:right

            # Exit window mode on Escape or Enter
            keybind = window/escape=deactivate_key_table
            keybind = window/enter=deactivate_key_table

            # Close focused split using 'x'
            keybind = window/x=close_surface
            keybind = chain=deactivate_key_table
            # --- GHOSTTY PRESET END ---
            """
        }
        
        var finalContent = filteredLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if !newPresetContent.isEmpty {
            finalContent += "\n\n" + newPresetContent
        }
        finalContent += "\n"
        
        try? finalContent.write(to: url, atomically: true, encoding: .utf8)
    }

    func readOpacity() -> Double {
        guard let url = getConfigFileURL(),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return 1.0
        }
        
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let parts = line.components(separatedBy: "=")
            if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "background-opacity" {
                if let val = Double(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) {
                    return val
                }
            }
        }
        return 1.0
    }
    
    func saveOpacity(_ opacity: Double) {
        guard let url = getConfigFileURL() else { return }
        
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? "".write(to: url, atomically: true, encoding: .utf8)
        }
        
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        let lines = content.components(separatedBy: .newlines)
        var newLines: [String] = []
        var found = false
        
        for line in lines {
            let parts = line.components(separatedBy: "=")
            if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "background-opacity" {
                newLines.append("background-opacity = \(String(format: "%.2f", opacity))")
                found = true
            } else {
                newLines.append(line)
            }
        }
        
        if !found {
            newLines.append("background-opacity = \(String(format: "%.2f", opacity))")
        }
        
        let finalContent = newLines.joined(separator: "\n")
        try? finalContent.write(to: url, atomically: true, encoding: .utf8)
    }
    
    func deleteOpacity() {
        guard let url = getConfigFileURL() else { return }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        
        let lines = content.components(separatedBy: .newlines)
        var newLines: [String] = []
        
        for line in lines {
            let parts = line.components(separatedBy: "=")
            if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "background-opacity" {
                continue
            }
            newLines.append(line)
        }
        
        let finalContent = newLines.joined(separator: "\n")
        try? finalContent.write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - Settings View (Simple macOS Style)
struct SettingsView: View {
    @EnvironmentObject private var appDelegate: AppDelegate
    
    @State private var selectedPreset: KeybindPreset = .default
    @State private var backgroundOpacity: Double = 1.0
    @State private var saveStatusMessage: String? = nil
    @State private var isLoaded: Bool = false
    
    var body: some View {
        TabView {
            // Tab 1: Keybind Presets
            Form {
                Section {
                    Picker("Keybind Preset:", selection: $selectedPreset) {
                        ForEach(KeybindPreset.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                    .pickerStyle(DefaultPickerStyle())
                    .frame(width: 320)
                    .onChange(of: selectedPreset) { newValue in
                        guard isLoaded else { return }
                        SettingsManager.shared.savePreset(newValue)
                        appDelegate.ghostty.reloadConfig()
                        triggerStatus("Preset saved!")
                    }
                    
                    Text(selectedPreset.description)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                } header: {
                    Text("Keyboard & Multiplexing Mode")
                }
                
                Section {
                    HStack {
                        Image(systemName: "terminal")
                            .font(.system(size: 14))
                            .foregroundColor(.accentColor)
                        Text("Searchable Command Palette is enabled (Cmd+Shift+P / Ctrl+Shift+P)")
                            .font(.system(size: 12))
                    }
                } header: {
                    Text("Command Palette")
                }
            }
            .padding()
            .tabItem {
                Label("Keybinds", systemImage: "keyboard")
            }
            
            // Tab 2: Appearance
            Form {
                Section {
                    HStack {
                        Slider(value: $backgroundOpacity, in: 0.15...1.0, step: 0.05)
                            .onChange(of: backgroundOpacity) { newValue in
                                guard isLoaded else { return }
                                SettingsManager.shared.saveOpacity(newValue)
                                appDelegate.ghostty.reloadConfig()
                            }
                        Text(String(format: "%.0f%%", backgroundOpacity * 100))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .frame(width: 40)
                    }
                } header: {
                    Text("Background Opacity")
                }
                
                Section {
                    Button("Use Theme Default Opacity") {
                        SettingsManager.shared.deleteOpacity()
                        appDelegate.ghostty.reloadConfig()
                        backgroundOpacity = 1.0
                        triggerStatus("Using Theme Default Opacity")
                    }
                    .foregroundColor(.red)
                } header: {
                    Text("Opacity Override Reset")
                }
                
                Section {
                    Text("To customize terminal theme colors, launch the Theme Picker in the terminal with Cmd+Shift+T, then press Tab.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Theme Editing")
                }
            }
            .padding()
            .tabItem {
                Label("Appearance", systemImage: "slider.horizontal.3")
            }
        }
        .frame(width: 500, height: 350)
        .overlay(
            VStack {
                Spacer()
                HStack {
                    if let message = saveStatusMessage {
                        Text(message)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.1))
                            .cornerRadius(4)
                    }
                    
                    Spacer()
                    
                    Button("Edit Config File") {
                        appDelegate.ghostty.openConfig()
                    }
                    .font(.system(size: 11))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        )
        .onAppear {
            selectedPreset = SettingsManager.shared.readPreset()
            backgroundOpacity = SettingsManager.shared.readOpacity()
            // Avoid triggering saves during initial state load
            DispatchQueue.main.async {
                isLoaded = true
            }
        }
    }
    
    private func triggerStatus(_ message: String) {
        saveStatusMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if saveStatusMessage == message {
                saveStatusMessage = nil
            }
        }
    }
}
