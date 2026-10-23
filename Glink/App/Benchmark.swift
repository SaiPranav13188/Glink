import AppKit
import Darwin

/// `Glink --benchmark` measures the performance budgets from the plan in the real app, prints
/// the results as JSON, and quits. Numbers are medians over repeated runs.
@MainActor
enum Benchmark {
    static func run() {
        Task { @MainActor in
            var results: [String: Any] = [:]
            results["coldLaunchMs"] = launchMilliseconds()

            // Let the app scan, the store open and caches warm up, like a real first use.
            try? await Task.sleep(for: .seconds(2))

            results["hotkeyToPanelMs"] = await panelOpenMilliseconds(runs: 20)
            try? await Task.sleep(for: .seconds(1))   // let the last close animation finish
            results["keystrokeToResultsMs"] = await keystrokeMilliseconds()

            try? await Task.sleep(for: .seconds(1))
            results["memoryFootprintMB"] = footprintMegabytes()

            let data = try? JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
            print(String(decoding: data ?? Data(), as: UTF8.self))
            fflush(stdout)
            NSApp.terminate(nil)
        }
    }

    /// `--animation-benchmark`: drives the panel like a person would (open, type, arrow through
    /// results, ⌘K, close) with no measurement code in the way, for Instruments' Animation Hitches.
    static func runAnimationScript() {
        Task { @MainActor in
            let controller = PanelController.shared
            let model = controller.viewModel
            try? await Task.sleep(for: .seconds(2))
            for round in 0..<6 {
                controller.toggle()
                try? await Task.sleep(for: .milliseconds(400))
                for ch in ["s", "a", "f"] {
                    model.query += ch
                    try? await Task.sleep(for: .milliseconds(120))
                }
                for _ in 0..<4 {
                    model.moveSelection(1)
                    try? await Task.sleep(for: .milliseconds(150))
                }
                if round % 2 == 0 {
                    model.toggleActions()
                    try? await Task.sleep(for: .milliseconds(400))
                    model.closeActions()
                    try? await Task.sleep(for: .milliseconds(300))
                }
                model.query = ""
                try? await Task.sleep(for: .milliseconds(300))
                controller.hide()
                try? await Task.sleep(for: .milliseconds(500))
            }
            NSApp.terminate(nil)
        }
    }

    /// Process start → now (called at the end of applicationDidFinishLaunching).
    static func launchMilliseconds() -> Double {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        sysctl(&mib, 4, &info, &size, nil, 0)
        let start = info.kp_proc.p_starttime
        let started = Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000
        return ((Date().timeIntervalSince1970 - started) * 1000).rounded(toPlaces: 1)
    }

    /// Hotkey handler → panel ordered in, laid out and drawn (the window server shows it on the next frame).
    static func panelOpenMilliseconds(runs: Int) async -> [String: Double] {
        let controller = PanelController.shared
        var samples: [Double] = []
        for _ in 0..<runs {
            controller.hide()
            try? await Task.sleep(for: .milliseconds(250))
            let t0 = CACurrentMediaTime()
            controller.toggle()
            controller.panel.contentView?.layoutSubtreeIfNeeded()
            controller.panel.displayIfNeeded()
            samples.append((CACurrentMediaTime() - t0) * 1000)
            try? await Task.sleep(for: .milliseconds(150))
        }
        controller.hide()
        return summary(samples)
    }

    /// Typing one character → fast providers' results published (files stream in later by design).
    static func keystrokeMilliseconds() async -> [String: [String: Double]] {
        let engine = PanelController.shared.viewModel.engine
        var out: [String: [String: Double]] = [:]
        for query in ["s", "sa", "saf", "xc", "10 km to mi", "clip", "win", "settings"] {
            var samples: [Double] = []
            for _ in 0..<15 {
                let t0 = CACurrentMediaTime()
                var first: Double?
                await engine.search(query) { _ in
                    if first == nil { first = (CACurrentMediaTime() - t0) * 1000 }
                }
                if let first { samples.append(first) }
            }
            out[query] = summary(samples)
        }
        return out
    }

    /// Physical footprint — the "Memory" column in Activity Monitor.
    static func footprintMegabytes() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return -1 }
        return (Double(info.phys_footprint) / 1_048_576).rounded(toPlaces: 1)
    }

    static func summary(_ samples: [Double]) -> [String: Double] {
        let sorted = samples.sorted()
        guard !sorted.isEmpty else { return [:] }
        return ["median": sorted[sorted.count / 2].rounded(toPlaces: 2),
                "p90": sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.9))].rounded(toPlaces: 2),
                "max": sorted.last!.rounded(toPlaces: 2)]
    }
}

extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let p = pow(10, Double(places))
        return (self * p).rounded() / p
    }
}
