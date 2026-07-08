import SwiftUI
import AppKit
import CoreGraphics
import ServiceManagement
import Combine

class JigglerManager: ObservableObject {
    @Published var isActive = false {
        didSet { manageTimer() }
    }
    
    @Published var startMovingAfter: Double = 5.0
    @Published var moveEvery: Double = 5.0
    
    private var timer: Timer?
    private var expectedPos: CGPoint = .zero
    private var idleSeconds: Double = 0
    private var secondsSinceLastJiggle: Double = 0
    private var isJiggling: Bool = false
    
    func manageTimer() {
        timer?.invalidate()
        if isActive {
            idleSeconds = 0
            secondsSinceLastJiggle = 0
            isJiggling = false
            
            if let loc = CGEvent(source: nil)?.location {
                expectedPos = loc
            }
            
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.checkIdleAndJiggle()
            }
        }
    }
    
    private func checkIdleAndJiggle() {
        if isJiggling { return }
        
        guard let currentLoc = CGEvent(source: nil)?.location else { return }
        
        let dx = abs(currentLoc.x - expectedPos.x)
        let dy = abs(currentLoc.y - expectedPos.y)
        
        if dx > 2 || dy > 2 {
            idleSeconds = 0
            secondsSinceLastJiggle = 0
            expectedPos = currentLoc
            return
        }
        
        idleSeconds += 1.0
        
        if idleSeconds == startMovingAfter {
            performCenteredJiggle()
            secondsSinceLastJiggle = 0.0
        } else if idleSeconds > startMovingAfter {
            secondsSinceLastJiggle += 1.0
            
            if secondsSinceLastJiggle >= moveEvery {
                performCenteredJiggle()
                secondsSinceLastJiggle = 0.0
            }
        }
    }
    
    private func performCenteredJiggle() {
        guard let startLoc = CGEvent(source: nil)?.location else { return }
        
        isJiggling = true
        
        let screenWidth = NSScreen.main?.frame.width ?? 1920
        let screenHeight = NSScreen.main?.frame.height ?? 1080
        
        let minX = screenWidth / 4
        let maxX = minX * 3
        let minY = screenHeight / 4
        let maxY = minY * 3
        
        let rawTargetX = startLoc.x + CGFloat.random(in: -400...400)
        let rawTargetY = startLoc.y + CGFloat.random(in: -400...400)
        
        let targetX = max(minX, min(rawTargetX, maxX))
        let targetY = max(minY, min(rawTargetY, maxY))
        let targetLoc = CGPoint(x: targetX, y: targetY)
        
        DispatchQueue.global(qos: .userInteractive).async {
            let steps = 60
            let duration: Double = 1.0
            let sleepTime = duration / Double(steps)
            
            for step in 1...steps {
                let t = CGFloat(step) / CGFloat(steps)
                let currentX = startLoc.x + (targetLoc.x - startLoc.x) * t
                let currentY = startLoc.y + (targetLoc.y - startLoc.y) * t
                let currentLoc = CGPoint(x: currentX, y: currentY)
                
                if let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: currentLoc, mouseButton: .left) {
                    moveEvent.post(tap: .cghidEventTap)
                }
                Thread.sleep(forTimeInterval: sleepTime)
            }
            
            DispatchQueue.main.async {
                if let finalLoc = CGEvent(source: nil)?.location {
                    self.expectedPos = finalLoc
                }
                self.isJiggling = false
            }
        }
    }
}

struct ContentView: View {
    @StateObject var manager = JigglerManager()
    
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    
    let startAfterOptions: [Double] = [5, 10, 30, 60, 300]
    let moveEveryOptions: [Double] = [1, 2, 5, 10, 20]
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Circle()
                    .fill(manager.isActive ? Color.green : Color.red)
                    .frame(width: 12, height: 12)
                
                Toggle("Mouse Jiggler", isOn: $manager.isActive)
                    .toggleStyle(.switch)
                    .font(.title2.bold())
            }
            
            Divider()
            
            Form {
                Picker("Start Moving After", selection: $manager.startMovingAfter) {
                    ForEach(startAfterOptions, id: \.self) { val in
                        Text(formatTime(val)).tag(val)
                    }
                }
                .onChange(of: manager.startMovingAfter) { _ in resetTimer() }
                
                Picker("Move Every", selection: $manager.moveEvery) {
                    ForEach(moveEveryOptions, id: \.self) { val in
                        Text(formatTime(val)).tag(val)
                    }
                }
                .onChange(of: manager.moveEvery) { _ in resetTimer() }
            }
            
            Divider()
            
            Toggle("Mac açılışında otomatik başlat", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        // Print komutu temizlendi
                    }
                }
                .font(.footnote)
            
            Text(manager.isActive ? "Aktif: Fare ekran ortasında süzülecek." : "Duraklatıldı")
                .font(.footnote)
                .foregroundColor(.gray)
            
            Button("Uygulamadan Çık") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(20)
        .frame(width: 320)
    }
    
    func resetTimer() {
        if manager.isActive {
            manager.manageTimer()
        }
    }
    
    func formatTime(_ seconds: Double) -> String {
        if seconds >= 60 {
            return "\(Int(seconds / 60)) min"
        } else {
            return "\(Int(seconds)) sec"
        }
    }
}

@main
struct JigglerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        MenuBarExtra("Jiggler", systemImage: "cursorarrow") {
            ContentView()
        }
        .menuBarExtraStyle(.window)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
        AXIsProcessTrustedWithOptions(options)
    }
}
