import AppKit
import ApplicationServices

extension NSScreen {
    /// 返回 AX 坐标系下的可用工作区（扣除菜单栏和 Dock）
    func axVisibleFrame() -> CGRect {
        guard let primaryScreen = NSScreen.screens.first else { return visibleFrame }
        let primaryHeight = primaryScreen.frame.height

        let axX = visibleFrame.origin.x
        let axY = primaryHeight - (visibleFrame.origin.y + visibleFrame.height)

        return CGRect(x: axX, y: axY, width: visibleFrame.width, height: visibleFrame.height)
    }
}

class WindowManager {
    // 存储窗口原始位置，用于"最大化 ↔ 还原"切换
    private var savedFrames: [CFHashCode: CGRect] = [:]

    private enum SnapCycleState {
        case half
        case third
        case twoThirds
    }

    private var leftCycleState: [CFHashCode: SnapCycleState] = [:]
    private var rightCycleState: [CFHashCode: SnapCycleState] = [:]

    private func getFocusedWindow() -> AXUIElement? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        var windowValue: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &windowValue
        )
        guard result == .success, let window = windowValue else { return nil }
        return (window as! AXUIElement)
    }

    private func getCurrentFrame(of window: AXUIElement) -> CGRect? {
        var posValue: AnyObject?
        var sizeValue: AnyObject?

        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success
        else { return nil }

        var point = CGPoint.zero
        var size = CGSize.zero
        guard let pVal = posValue, let sVal = sizeValue,
              CFGetTypeID(pVal) == AXValueGetTypeID(),
              CFGetTypeID(sVal) == AXValueGetTypeID(),
              AXValueGetValue(pVal as! AXValue, .cgPoint, &point),
              AXValueGetValue(sVal as! AXValue, .cgSize, &size)
        else { return nil }

        return CGRect(origin: point, size: size)
    }

    private func getScreenForWindow(_ window: AXUIElement) -> NSScreen? {
        guard let frame = getCurrentFrame(of: window) else { return NSScreen.main }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0

        // 将窗口中心点从 AX 坐标转回 Cocoa 坐标来匹配屏幕
        let centerX = frame.origin.x + frame.width / 2.0
        let centerCocoaY = primaryHeight - (frame.origin.y + frame.height / 2.0)
        let cocoaCenter = NSPoint(x: centerX, y: centerCocoaY)

        return NSScreen.screens.first(where: { $0.frame.contains(cocoaCenter) }) ?? NSScreen.main
    }

    private func moveAndResize(window: AXUIElement, to frame: CGRect) {
        var position = CGPoint(x: frame.origin.x, y: frame.origin.y)
        var size = CGSize(width: frame.width, height: frame.height)

        // 三步法：先设尺寸 → 再设位置 → 再次确认尺寸（防止边界钳位导致展开失败）
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
        if let posValue = AXValueCreate(.cgPoint, &position) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        }
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
    }

    private func isApproximatelyEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat) -> Bool {
        return abs(a.origin.x - b.origin.x) <= tolerance &&
               abs(a.origin.y - b.origin.y) <= tolerance &&
               abs(a.width - b.width) <= tolerance &&
               abs(a.height - b.height) <= tolerance
    }

    func snapLeft() {
        guard let window = getFocusedWindow(),
              let screen = getScreenForWindow(window) else { return }
        let area = screen.axVisibleFrame()
        let halfW = floor(area.width / 2.0)
        let thirdW = floor(area.width / 3.0)
        let twoThirdsW = floor(area.width * 2.0 / 3.0)

        let leftHalf = CGRect(x: area.origin.x, y: area.origin.y, width: halfW, height: area.height)
        let leftThird = CGRect(x: area.origin.x, y: area.origin.y, width: thirdW, height: area.height)
        let leftTwoThirds = CGRect(x: area.origin.x, y: area.origin.y, width: twoThirdsW, height: area.height)

        let windowHash = CFHash(window)
        let currentFrame = getCurrentFrame(of: window)

        // 状态循环顺序：左一半 (1/2) -> 左三分之一 (1/3) -> 左三分之二 (2/3) -> 左一半 (1/2)
        let nextTarget: CGRect
        let nextState: SnapCycleState

        if let frame = currentFrame, isApproximatelyEqual(frame, leftHalf, tolerance: 10) {
            nextTarget = leftThird
            nextState = .third
        } else if let frame = currentFrame, isApproximatelyEqual(frame, leftThird, tolerance: 10) {
            nextTarget = leftTwoThirds
            nextState = .twoThirds
        } else if let frame = currentFrame, isApproximatelyEqual(frame, leftTwoThirds, tolerance: 10) {
            nextTarget = leftHalf
            nextState = .half
        } else if let frame = currentFrame, abs(frame.origin.x - area.origin.x) <= 10, let lastState = leftCycleState[windowHash] {
            // 边缘吸附容错（应对部分应用 minSize 限制无法缩小到精确 1/3 时，依然能稳定向前循环）
            switch lastState {
            case .half:
                nextTarget = leftThird
                nextState = .third
            case .third:
                nextTarget = leftTwoThirds
                nextState = .twoThirds
            case .twoThirds:
                nextTarget = leftHalf
                nextState = .half
            }
        } else {
            // 初始吸附到左半屏
            nextTarget = leftHalf
            nextState = .half
        }

        leftCycleState[windowHash] = nextState
        rightCycleState.removeValue(forKey: windowHash)
        moveAndResize(window: window, to: nextTarget)
    }

    func snapRight() {
        guard let window = getFocusedWindow(),
              let screen = getScreenForWindow(window) else { return }
        let area = screen.axVisibleFrame()
        let halfW = floor(area.width / 2.0)
        let thirdW = floor(area.width / 3.0)
        let twoThirdsW = floor(area.width * 2.0 / 3.0)

        let rightHalf = CGRect(x: area.origin.x + (area.width - halfW), y: area.origin.y, width: halfW, height: area.height)
        let rightThird = CGRect(x: area.origin.x + (area.width - thirdW), y: area.origin.y, width: thirdW, height: area.height)
        let rightTwoThirds = CGRect(x: area.origin.x + (area.width - twoThirdsW), y: area.origin.y, width: twoThirdsW, height: area.height)

        let windowHash = CFHash(window)
        let currentFrame = getCurrentFrame(of: window)

        // 状态循环顺序：右一半 (1/2) -> 右三分之一 (1/3) -> 右三分之二 (2/3) -> 右一半 (1/2)
        let nextTarget: CGRect
        let nextState: SnapCycleState

        if let frame = currentFrame, isApproximatelyEqual(frame, rightHalf, tolerance: 10) {
            nextTarget = rightThird
            nextState = .third
        } else if let frame = currentFrame, isApproximatelyEqual(frame, rightThird, tolerance: 10) {
            nextTarget = rightTwoThirds
            nextState = .twoThirds
        } else if let frame = currentFrame, isApproximatelyEqual(frame, rightTwoThirds, tolerance: 10) {
            nextTarget = rightHalf
            nextState = .half
        } else if let frame = currentFrame, abs((frame.origin.x + frame.width) - (area.origin.x + area.width)) <= 10, let lastState = rightCycleState[windowHash] {
            // 边缘吸附容错（应对部分应用 minSize 限制无法缩小到精确 1/3 时，依然能稳定向前循环）
            switch lastState {
            case .half:
                nextTarget = rightThird
                nextState = .third
            case .third:
                nextTarget = rightTwoThirds
                nextState = .twoThirds
            case .twoThirds:
                nextTarget = rightHalf
                nextState = .half
            }
        } else {
            // 初始吸附到右半屏
            nextTarget = rightHalf
            nextState = .half
        }

        rightCycleState[windowHash] = nextState
        leftCycleState.removeValue(forKey: windowHash)
        moveAndResize(window: window, to: nextTarget)
    }

    func toggleMaximize() {
        guard let window = getFocusedWindow(),
              let screen = getScreenForWindow(window),
              let currentFrame = getCurrentFrame(of: window) else { return }

        let area = screen.axVisibleFrame()
        let windowHash = CFHash(window)

        if isApproximatelyEqual(currentFrame, area, tolerance: 4) {
            // 已最大化 → 还原
            if let saved = savedFrames[windowHash] {
                moveAndResize(window: window, to: saved)
                savedFrames.removeValue(forKey: windowHash)
            }
        } else {
            // 未最大化 → 保存当前位置并最大化
            savedFrames[windowHash] = currentFrame
            moveAndResize(window: window, to: area)
        }
        leftCycleState.removeValue(forKey: windowHash)
        rightCycleState.removeValue(forKey: windowHash)
    }
}
