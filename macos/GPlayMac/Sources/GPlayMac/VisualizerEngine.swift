import SwiftUI

struct VisualizerPreset: Identifiable, Hashable {
    enum Mode: String, Hashable {
        case spectralBars
        case liquidWave
        case pulseRing
        case warpGrid
        case starTunnel
    }

    let id: String
    let title: String
    let symbol: String
    let mode: Mode

    var palette: [Color] {
        switch mode {
        case .spectralBars:
            return [.cyan, .gAccent, .purple]
        case .liquidWave:
            return [.gMint, .cyan, .gAccent]
        case .pulseRing:
            return [.purple, .gAccent, .cyan]
        case .warpGrid:
            return [.indigo, .purple, .cyan]
        case .starTunnel:
            return [.cyan, .white, .purple]
        }
    }

    static let all: [VisualizerPreset] = [
        VisualizerPreset(id: "spectral-bars", title: "Spectral", symbol: "chart.bar.fill", mode: .spectralBars),
        VisualizerPreset(id: "liquid-wave", title: "Liquid", symbol: "waveform.path", mode: .liquidWave),
        VisualizerPreset(id: "pulse-ring", title: "Ring", symbol: "circle.hexagongrid.fill", mode: .pulseRing),
        VisualizerPreset(id: "warp-grid", title: "Warp", symbol: "grid", mode: .warpGrid),
        VisualizerPreset(id: "star-tunnel", title: "Tunnel", symbol: "sparkles", mode: .starTunnel),
    ]
}

struct VisualizerSignal {
    let bass: CGFloat
    let mid: CGFloat
    let treble: CGFloat
    let beat: CGFloat
    let spectrum: [CGFloat]
    let waveform: [CGFloat]
    let seed: CGFloat

    static func make(
        track: Track?,
        wallTime: TimeInterval,
        playhead: Double,
        isPlaying: Bool,
        bins: Int = 96
    ) -> VisualizerSignal {
        let seedValue = stableSeed(track?.id ?? "vantabeat-idle")
        let seed = CGFloat(seedValue % 10_000) / 10_000
        let motion = isPlaying ? CGFloat(wallTime) : CGFloat(wallTime) * 0.18
        let trackTime = CGFloat(playhead.isFinite ? playhead : 0)
        let t = motion + trackTime * 0.12 + seed * 12
        let drive: CGFloat = isPlaying ? 1 : 0.26

        let bass = clamp(0.28 + 0.58 * abs(sinValue(t * 1.18 + seed * 7)), 0, 1) * drive
        let mid = clamp(0.24 + 0.52 * abs(sinValue(t * 1.73 + seed * 11)), 0, 1) * drive
        let treble = clamp(0.18 + 0.60 * abs(sinValue(t * 2.47 + seed * 17)), 0, 1) * drive
        let beat = clamp(pow(bass, 1.7) * 0.86 + abs(sinValue(t * 3.2)) * 0.14, 0, 1)

        var spectrum: [CGFloat] = []
        var waveform: [CGFloat] = []
        spectrum.reserveCapacity(bins)
        waveform.reserveCapacity(bins)

        for index in 0..<bins {
            let x = CGFloat(index) / CGFloat(max(1, bins - 1))
            let low = pow(1 - x, 2.4) * bass
            let center = exp(-pow((x - 0.48) * 3.4, 2)) * mid
            let high = pow(x, 1.7) * treble
            let ripple = 0.5 + 0.5 * sinValue(t * 2.3 + x * 19 + seed * 9)
            let shimmer = 0.5 + 0.5 * sinValue(t * 6.2 + x * 41)
            let spectralValue = clamp(0.08 + low + center * 0.75 + high * 0.62 + ripple * 0.15 + shimmer * 0.06, 0, 1)
            spectrum.append(spectralValue)

            let wave = sinValue(x * .pi * 4 + t * 2.1)
                + 0.48 * sinValue(x * .pi * 9 + t * 1.33 + seed * 8)
                + 0.24 * sinValue(x * .pi * 19 - t * 2.7)
            let envelope = 0.36 + spectralValue * 0.62
            waveform.append(clamp(wave * envelope / 1.72, -1, 1))
        }

        return VisualizerSignal(
            bass: bass,
            mid: mid,
            treble: treble,
            beat: beat,
            spectrum: spectrum,
            waveform: waveform,
            seed: seed
        )
    }

    private static func stableSeed(_ value: String) -> Int {
        var hash = 5381
        for scalar in value.unicodeScalars {
            hash = ((hash << 5) &+ hash) &+ Int(scalar.value)
        }
        return abs(hash)
    }
}

enum VisualizerRenderer {
    static func draw(
        preset: VisualizerPreset,
        signal: VisualizerSignal,
        context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval
    ) {
        drawBackground(context: &context, size: size, signal: signal, palette: preset.palette)

        switch preset.mode {
        case .spectralBars:
            drawSpectralBars(context: &context, size: size, signal: signal, palette: preset.palette)
        case .liquidWave:
            drawLiquidWave(context: &context, size: size, signal: signal, palette: preset.palette, time: time)
        case .pulseRing:
            drawPulseRing(context: &context, size: size, signal: signal, palette: preset.palette, time: time)
        case .warpGrid:
            drawWarpGrid(context: &context, size: size, signal: signal, palette: preset.palette, time: time)
        case .starTunnel:
            drawStarTunnel(context: &context, size: size, signal: signal, palette: preset.palette, time: time)
        }
    }

    private static func drawBackground(
        context: inout GraphicsContext,
        size: CGSize,
        signal: VisualizerSignal,
        palette: [Color]
    ) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.025, green: 0.028, blue: 0.035)))

        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 72 + signal.beat * 34))
            let glowSize = min(size.width, size.height) * (0.72 + signal.beat * 0.18)
            let centerA = CGPoint(x: size.width * (0.28 + signal.mid * 0.08), y: size.height * 0.38)
            let centerB = CGPoint(x: size.width * 0.76, y: size.height * (0.62 - signal.treble * 0.08))
            layer.fill(
                Path(ellipseIn: CGRect(x: centerA.x - glowSize / 2, y: centerA.y - glowSize / 2, width: glowSize, height: glowSize)),
                with: .color(palette[0].opacity(0.18 + signal.bass * 0.16))
            )
            layer.fill(
                Path(ellipseIn: CGRect(x: centerB.x - glowSize / 2, y: centerB.y - glowSize / 2, width: glowSize, height: glowSize)),
                with: .color(palette[2].opacity(0.14 + signal.treble * 0.18))
            )
        }
    }

    private static func drawSpectralBars(
        context: inout GraphicsContext,
        size: CGSize,
        signal: VisualizerSignal,
        palette: [Color]
    ) {
        let count = 72
        let spacing: CGFloat = 4
        let barWidth = max(3, (size.width - CGFloat(count - 1) * spacing) / CGFloat(count))
        let baseline = size.height * 0.56
        let reflectionBase = size.height * 0.59
        let maxHeight = size.height * 0.48

        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 8 + signal.beat * 10))
            for index in 0..<count {
                let value = sample(signal.spectrum, index: index, count: count)
                let height = max(8, value * maxHeight)
                let x = CGFloat(index) * (barWidth + spacing)
                let y = baseline - height
                let color = colorRamp(palette, CGFloat(index) / CGFloat(count - 1))
                let rect = CGRect(x: x, y: y, width: barWidth, height: height)
                layer.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(color.opacity(0.54)))
            }
        }

        for index in 0..<count {
            let value = sample(signal.spectrum, index: index, count: count)
            let height = max(8, value * maxHeight)
            let x = CGFloat(index) * (barWidth + spacing)
            let y = baseline - height
            let color = colorRamp(palette, CGFloat(index) / CGFloat(count - 1))
            let rect = CGRect(x: x, y: y, width: barWidth, height: height)
            context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(color.opacity(0.74 + value * 0.24)))

            let reflectionHeight = height * 0.36
            let reflection = CGRect(x: x, y: reflectionBase, width: barWidth, height: reflectionHeight)
            context.fill(Path(roundedRect: reflection, cornerRadius: barWidth / 2), with: .color(color.opacity(0.10 + value * 0.09)))
        }
    }

    private static func drawLiquidWave(
        context: inout GraphicsContext,
        size: CGSize,
        signal: VisualizerSignal,
        palette: [Color],
        time: TimeInterval
    ) {
        let centerY = size.height * 0.5
        let amplitude = size.height * (0.18 + signal.mid * 0.16)

        for layerIndex in 0..<4 {
            var path = Path()
            let phase = CGFloat(time) * (0.58 + CGFloat(layerIndex) * 0.12) + signal.seed * 9
            let offset = CGFloat(layerIndex - 1) * size.height * 0.06
            let steps = 140

            for index in 0...steps {
                let x = CGFloat(index) / CGFloat(steps) * size.width
                let sampleIndex = Int(CGFloat(index) / CGFloat(steps) * CGFloat(signal.waveform.count - 1))
                let wave = signal.waveform[sampleIndex]
                let secondary = sinValue(CGFloat(index) * 0.18 + phase)
                let y = centerY + offset + wave * amplitude + secondary * amplitude * 0.22
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }

            let color = palette[layerIndex % palette.count]
            context.stroke(path, with: .color(color.opacity(0.36 + signal.beat * 0.18)), lineWidth: 2.0 + CGFloat(layerIndex) * 1.2)
        }
    }

    private static func drawPulseRing(
        context: inout GraphicsContext,
        size: CGSize,
        signal: VisualizerSignal,
        palette: [Color],
        time: TimeInterval
    ) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let baseRadius = min(size.width, size.height) * (0.20 + signal.bass * 0.035)
        let count = 160

        for ring in 0..<3 {
            var path = Path()
            let ringOffset = CGFloat(ring) * 34
            for index in 0...count {
                let progress = CGFloat(index) / CGFloat(count)
                let angle = progress * .pi * 2
                let sampleValue = sample(signal.spectrum, index: index, count: count)
                let pulse = sinValue(angle * CGFloat(3 + ring) + CGFloat(time) * (1.6 + CGFloat(ring) * 0.4))
                let radius = baseRadius + ringOffset + sampleValue * min(size.width, size.height) * 0.14 + pulse * 12
                let point = CGPoint(
                    x: center.x + cosValue(angle) * radius,
                    y: center.y + sinValue(angle) * radius
                )
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            context.stroke(
                path,
                with: .color(palette[ring % palette.count].opacity(0.40 - CGFloat(ring) * 0.08 + signal.beat * 0.18)),
                lineWidth: 2.4 - CGFloat(ring) * 0.3
            )
        }
    }

    private static func drawWarpGrid(
        context: inout GraphicsContext,
        size: CGSize,
        signal: VisualizerSignal,
        palette: [Color],
        time: TimeInterval
    ) {
        let rows = 14
        let cols = 18
        let warp = 18 + signal.beat * 34
        let t = CGFloat(time) * (0.5 + signal.bass * 0.5) + signal.seed * 10

        for row in 0...rows {
            var path = Path()
            for col in 0...cols {
                let xNorm = CGFloat(col) / CGFloat(cols)
                let yNorm = CGFloat(row) / CGFloat(rows)
                let x = xNorm * size.width
                let y = yNorm * size.height
                let dx = sinValue(yNorm * .pi * 4 + t + xNorm * 2) * warp
                let dy = cosValue(xNorm * .pi * 4 - t + yNorm * 3) * warp * 0.62
                let point = CGPoint(x: x + dx, y: y + dy)
                if col == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            context.stroke(path, with: .color(palette[row % palette.count].opacity(0.22)), lineWidth: 1)
        }

        for col in 0...cols {
            var path = Path()
            for row in 0...rows {
                let xNorm = CGFloat(col) / CGFloat(cols)
                let yNorm = CGFloat(row) / CGFloat(rows)
                let x = xNorm * size.width
                let y = yNorm * size.height
                let dx = sinValue(yNorm * .pi * 4 + t + xNorm * 2) * warp
                let dy = cosValue(xNorm * .pi * 4 - t + yNorm * 3) * warp * 0.62
                let point = CGPoint(x: x + dx, y: y + dy)
                if row == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            context.stroke(path, with: .color(Color.white.opacity(0.08 + signal.treble * 0.08)), lineWidth: 1)
        }
    }

    private static func drawStarTunnel(
        context: inout GraphicsContext,
        size: CGSize,
        signal: VisualizerSignal,
        palette: [Color],
        time: TimeInterval
    ) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let count = 180
        let speed = CGFloat(time) * (0.06 + signal.bass * 0.08)

        for index in 0..<count {
            let angle = seededNoise(index, salt: 7, seed: signal.seed) * .pi * 2
            let lane = seededNoise(index, salt: 19, seed: signal.seed)
            let depth = fract(seededNoise(index, salt: 31, seed: signal.seed) - speed)
            let radius = pow(1 - depth, 2.1) * min(size.width, size.height) * (0.72 + lane * 0.18)
            let x = center.x + cosValue(angle) * radius
            let y = center.y + sinValue(angle) * radius
            let opacity = clamp((1 - depth) * (0.18 + signal.treble * 0.7), 0.04, 0.9)
            let dotSize = max(1.2, (1 - depth) * 4.8 + signal.beat * 2.2)
            let color = colorRamp(palette, lane)
            let rect = CGRect(x: x - dotSize / 2, y: y - dotSize / 2, width: dotSize, height: dotSize)
            context.fill(Path(ellipseIn: rect), with: .color(color.opacity(opacity)))

            if signal.beat > 0.42 {
                var streak = Path()
                streak.move(to: CGPoint(x: x, y: y))
                streak.addLine(to: CGPoint(x: x + cosValue(angle) * 18 * signal.beat, y: y + sinValue(angle) * 18 * signal.beat))
                context.stroke(streak, with: .color(color.opacity(opacity * 0.35)), lineWidth: 1)
            }
        }
    }

    private static func sample(_ values: [CGFloat], index: Int, count: Int) -> CGFloat {
        guard !values.isEmpty else {
            return 0
        }
        let sourceIndex = min(values.count - 1, max(0, Int(CGFloat(index) / CGFloat(max(1, count - 1)) * CGFloat(values.count - 1))))
        return values[sourceIndex]
    }

    private static func colorRamp(_ colors: [Color], _ progress: CGFloat) -> Color {
        if progress < 0.34 {
            return colors[0]
        }
        if progress < 0.68 {
            return colors[min(1, colors.count - 1)]
        }
        return colors[min(2, colors.count - 1)]
    }

    private static func seededNoise(_ index: Int, salt: Int, seed: CGFloat) -> CGFloat {
        var value = UInt64(index &* 1_103_515_245 &+ salt &* 12_345 &+ Int(seed * 100_000))
        value ^= value >> 13
        value &*= 1_274_126_177
        value ^= value >> 16
        return CGFloat(value % 10_000) / 10_000
    }
}

func sinValue(_ value: CGFloat) -> CGFloat {
    CGFloat(sin(Double(value)))
}

func cosValue(_ value: CGFloat) -> CGFloat {
    CGFloat(cos(Double(value)))
}

func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
    min(max(value, lower), upper)
}

func fract(_ value: CGFloat) -> CGFloat {
    value - floor(value)
}
