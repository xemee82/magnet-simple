import AppKit
import ApplicationServices
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var authStatusMenuItem: NSMenuItem?
    private var launchAtLoginMenuItem: NSMenuItem?
    private var authTimer: Timer?
    private let hotKeyManager = HotKeyManager()
    private let windowManager = WindowManager()
    private var isAuthorized = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconUrl = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let appIcon = NSImage(contentsOf: iconUrl) {
            NSApp.applicationIconImage = appIcon
        }
        setupStatusBar()
        setupHotKeys()
        checkAndStartAuthPolling()
    }

    func applicationWillTerminate(_ notification: Notification) {
        authTimer?.invalidate()
        authTimer = nil
        hotKeyManager.unregisterAll()
    }

    // MARK: - 辅助功能权限管理
    private func checkAndStartAuthPolling() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString
        let options = [promptKey: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)

        if trusted {
            handleAuthorizationSuccess()
        } else {
            updateAuthStatusMenu(isGranted: false)
            // 启动定时轮询检测，使用 .common 模式防止被菜单跟踪事件阻塞
            let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] t in
                guard let self = self else { return }
                if AXIsProcessTrusted() {
                    t.invalidate()
                    self.authTimer = nil
                    self.handleAuthorizationSuccess()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.authTimer = timer
        }
    }

    private func handleAuthorizationSuccess() {
        isAuthorized = true
        updateAuthStatusMenu(isGranted: true)
        hotKeyManager.registerAll()
    }

    private func updateAuthStatusMenu(isGranted: Bool) {
        DispatchQueue.main.async {
            if isGranted {
                self.authStatusMenuItem?.isHidden = true
            } else {
                self.authStatusMenuItem?.isHidden = false
                self.authStatusMenuItem?.title = "⚠️ Accessibility Permission Required (Click to Open)"
            }
        }
    }

    @objc private func openAccessibilitySettings() {
        if AXIsProcessTrusted() {
            handleAuthorizationSuccess()
            return
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - 全局热键
    private func setupHotKeys() {
        hotKeyManager.onAction = { [weak self] action in
            guard let self = self, self.isAuthorized else { return }
            switch action {
            case .leftHalf:
                self.windowManager.snapLeft()
            case .rightHalf:
                self.windowManager.snapRight()
            case .maximize:
                self.windowManager.toggleMaximize()
            }
        }
    }

    // MARK: - 菜单栏 Status Item
    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = createMagnetStatusBarIcon()
        }

        let menu = NSMenu()
        menu.delegate = self

        let titleItem = NSMenuItem(title: "MagnetSimple", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        let authItem = NSMenuItem(
            title: "⚠️ Accessibility Permission Required…",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        authItem.target = self
        authItem.isHidden = true
        menu.addItem(authItem)
        self.authStatusMenuItem = authItem

        menu.addItem(NSMenuItem.separator())

        let leftItem = NSMenuItem(title: "⌃⌥← Left Snap (Cycle ½, ⅓, ⅔)", action: #selector(menuSnapLeft), keyEquivalent: "")
        leftItem.target = self
        menu.addItem(leftItem)

        let rightItem = NSMenuItem(title: "⌃⌥→ Right Snap (Cycle ½, ⅓, ⅔)", action: #selector(menuSnapRight), keyEquivalent: "")
        rightItem.target = self
        menu.addItem(rightItem)

        let maxItem = NSMenuItem(title: "⌃⌥↩ Toggle Maximize", action: #selector(menuToggleMaximize), keyEquivalent: "")
        maxItem.target = self
        menu.addItem(maxItem)

        menu.addItem(NSMenuItem.separator())

        let launchItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin(_:)),
            keyEquivalent: ""
        )
        launchItem.target = self
        menu.addItem(launchItem)
        self.launchAtLoginMenuItem = launchItem

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(
            title: "Quit MagnetSimple",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        statusItem.menu = menu
    }

    @objc private func menuSnapLeft() {
        guard isAuthorized else { return }
        windowManager.snapLeft()
    }

    @objc private func menuSnapRight() {
        guard isAuthorized else { return }
        windowManager.snapRight()
    }

    @objc private func menuToggleMaximize() {
        guard isAuthorized else { return }
        windowManager.toggleMaximize()
    }

    // MARK: - 开机自启动管理
    @objc func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSLog("[AppDelegate] Toggle launch at login error: %@", error.localizedDescription)
            if service.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        }
    }

    // MARK: - NSMenuDelegate
    func menuNeedsUpdate(_ menu: NSMenu) {
        if !isAuthorized && AXIsProcessTrusted() {
            handleAuthorizationSuccess()
        }
        launchAtLoginMenuItem?.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
    }

    // MARK: - 矢量马蹄形磁铁图标生成
    private func createMagnetStatusBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()

            let path = NSBezierPath()
            let centerX: CGFloat = 9.0
            let centerY: CGFloat = 7.5
            let outerR: CGFloat = 6.5
            let innerR: CGFloat = 3.2

            // 外轮廓左侧顶部
            path.move(to: NSPoint(x: centerX - outerR, y: 16.5))
            // 直线向下至圆弧起始点
            path.line(to: NSPoint(x: centerX - outerR, y: centerY))
            // 底部外侧半圆弧 (Cocoa flipped=false 下逆时针为顺时针走底部)
            path.appendArc(withCenter: NSPoint(x: centerX, y: centerY), radius: outerR, startAngle: 180, endAngle: 0, clockwise: false)
            // 直线向上至右侧顶部
            path.line(to: NSPoint(x: centerX + outerR, y: 16.5))
            // 右臂顶部平头
            path.line(to: NSPoint(x: centerX + innerR, y: 16.5))
            // 直线向下至内侧圆弧起始点
            path.line(to: NSPoint(x: centerX + innerR, y: centerY))
            // 底部内侧半圆弧
            path.appendArc(withCenter: NSPoint(x: centerX, y: centerY), radius: innerR, startAngle: 0, endAngle: 180, clockwise: true)
            // 左臂顶部平头
            path.line(to: NSPoint(x: centerX - innerR, y: 16.5))
            path.close()
            path.fill()

            // 切割磁极顶端凹槽（透明细缝，区分磁极头部）
            NSGraphicsContext.current?.compositingOperation = .clear
            let gapY: CGFloat = 11.8
            let gapH: CGFloat = 1.4
            NSRect(x: 1.5, y: gapY, width: 5.5, height: gapH).fill()
            NSRect(x: 11.0, y: gapY, width: 5.5, height: gapH).fill()

            return true
        }
        image.isTemplate = true
        return image
    }
}

