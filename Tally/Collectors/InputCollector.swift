import Foundation
import CoreGraphics
import AppKit
import os

private let logger = Logger(subsystem: "arthurmonnet.Tally", category: "InputCollector")

@MainActor
final class InputCollector {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var flushTimer: Timer?

    // In-memory counters — flushed to DB every 10 seconds
    private var counters: [String: Int64] = [:]
    private var floatCounters: [String: Double] = [:]

    // Live stats for instant UI updates
    private var liveStats: LiveStats?

    // Mouse tracking
    private var lastMousePosition: CGPoint?
    private var mouseEventCounter: Int = 0
    private let mouseEventSampleRate = 3  // Process every 3rd mouseMoved event

    // Launcher shortcut detection
    private var launcherKeycode: Int64 = 49  // space by default
    private var launcherModifier: CGEventFlags = .maskCommand

    private let pixelsToMeters: Double = 0.000264

    private let db = Database.shared

    func configure(launcherShortcut: String, liveStats: LiveStats? = nil) {
        self.liveStats = liveStats
        // Parse "cmd+space" style shortcuts
        let parts = launcherShortcut.lowercased().split(separator: "+")
        for part in parts {
            switch part {
            case "cmd", "command": launcherModifier = .maskCommand
            case "alt", "option": launcherModifier = .maskAlternate
            case "ctrl", "control": launcherModifier = .maskControl
            case "shift": launcherModifier = .maskShift
            case "space": launcherKeycode = 49
            default: break
            }
        }
    }

    private var accessibilityRetryTimer: Timer?

    func start() {
        // Silent check only — never trigger the system permission dialog here.
        // The onboarding AccessibilityView handles prompting the user.
        if AXIsProcessTrusted() {
            startEventTap()
        } else {
            logger.info("Accessibility permission not granted — staying dormant, polling every 3s")
            startAccessibilityPolling()
        }
    }

    private func startAccessibilityPolling() {
        accessibilityRetryTimer?.invalidate()
        accessibilityRetryTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [self] _ in
            MainActor.assumeIsolated {
                if AXIsProcessTrusted() {
                    self.accessibilityRetryTimer?.invalidate()
                    self.accessibilityRetryTimer = nil
                    logger.info("Accessibility permission granted — starting event tap")
                    self.startEventTap()
                }
            }
        }
    }

    private func startEventTap() {
        let mask: CGEventMask = (
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue) |
            (1 << CGEventType.mouseMoved.rawValue)
        )

        let callback: CGEventTapCallBack = { _, type, event, refcon -> Unmanaged<CGEvent>? in
            guard let refcon = refcon else { return Unmanaged.passRetained(event) }
            let collector = Unmanaged<InputCollector>.fromOpaque(refcon).takeUnretainedValue()

            MainActor.assumeIsolated {
                collector.handleEvent(type: type, event: event)
            }

            return Unmanaged.passRetained(event)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: refcon
        )

        guard let eventTap else {
            logger.error("Failed to create event tap")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        // Flush counters to DB every 10 seconds
        flushTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [self] _ in
            MainActor.assumeIsolated {
                self.flush()
            }
        }

        logger.info("Started")
    }

    func stop() {
        flush()

        accessibilityRetryTimer?.invalidate()
        accessibilityRetryTimer = nil

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        flushTimer?.invalidate()
        flushTimer = nil
        eventTap = nil
        runLoopSource = nil

        logger.info("Stopped")
    }

    private func handleEvent(type: CGEventType, event: CGEvent) {
        switch type {
        case .keyDown:
            increment("keystrokes")

            // Detect modifier combos
            let flags = event.flags
            if flags.contains(.maskCommand) {
                let keycode = event.getIntegerValueField(.keyboardEventKeycode)
                switch keycode {
                case 6:  increment("cmd_z")    // Z
                case 9:  increment("cmd_v")    // V (paste)
                         increment("paste")
                case 8:  increment("cmd_c")    // C (copy)
                         increment("copy")
                default: break
                }

                // Launcher shortcut detection
                if flags.contains(launcherModifier) && keycode == launcherKeycode {
                    increment("launcher_opens")
                }
            }

        case .leftMouseDown:
            increment("clicks_left")

        case .rightMouseDown:
            increment("clicks_right")

        case .scrollWheel:
            let deltaY = abs(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1))
            addFloat("scroll_distance_m", value: deltaY * pixelsToMeters)

        case .mouseMoved:
            mouseEventCounter += 1
            guard mouseEventCounter % mouseEventSampleRate == 0 else { break }

            let currentPos = event.location
            if let lastPos = lastMousePosition {
                let dx = currentPos.x - lastPos.x
                let dy = currentPos.y - lastPos.y
                let distancePx = sqrt(dx * dx + dy * dy)
                addFloat("mouse_distance_m", value: distancePx * pixelsToMeters)
            }
            lastMousePosition = currentPos

        default:
            // Handle tap disabled events (system may disable the tap)
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let eventTap {
                    CGEvent.tapEnable(tap: eventTap, enable: true)
                }
            }
        }
    }

    private func increment(_ key: String) {
        counters[key, default: 0] += 1
        liveStats?.increment(key)
    }

    private func addFloat(_ key: String, value: Double) {
        floatCounters[key, default: 0] += value
        liveStats?.addFloat(key, value: value)
    }

    private func flush() {
        guard !counters.isEmpty || !floatCounters.isEmpty else { return }

        var events: [(statKey: String, valueInt: Int64, valueFloat: Double)] = []

        for (key, value) in counters {
            events.append((statKey: key, valueInt: value, valueFloat: 0.0))
        }
        for (key, value) in floatCounters {
            events.append((statKey: key, valueInt: 0, valueFloat: value))
        }

        counters.removeAll()
        floatCounters.removeAll()

        do {
            try db.upsertEvents(events)
        } catch {
            logger.error("Failed to flush: \(error)")
        }
    }
}
