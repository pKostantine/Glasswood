import Cocoa
import AVFoundation
import AVKit
import QuartzCore

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Design tokens
// ─────────────────────────────────────────────────────────────────────────────

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
                  green:  CGFloat((hex >>  8) & 0xff) / 255,
                  blue:   CGFloat( hex        & 0xff) / 255,
                  alpha:  alpha)
    }
}

/// Amber linen palette, pulled from the autumn footage: the ground is warm but
/// low-chroma so the photography still carries the colour.
enum C {
    static let paper     = NSColor(hex: 0xF5E2CB)   // warm sand, ~33° hue
    static let paperDeep = NSColor(hex: 0xEDD5B8)
    static let ink       = NSColor(hex: 0x2A2018)
    static let inkSoft   = NSColor(hex: 0x6B5C4A)
    static let inkFaint  = NSColor(hex: 0x91806C)
    static let moss      = NSColor(hex: 0x3F7C58)
    static let ember     = NSColor(hex: 0xC26A2C)
    static let hairline  = NSColor(hex: 0x2A2018, alpha: 0.13)
}

enum F {
    /// Rounded system face for display type — softer, less corporate.
    static func display(_ s: CGFloat, _ w: NSFont.Weight = .bold) -> NSFont {
        let base = NSFont.systemFont(ofSize: s, weight: w)
        if #available(macOS 11.0, *),
           let d = base.fontDescriptor.withDesign(.rounded),
           let f = NSFont(descriptor: d, size: s) { return f }
        return base
    }
    static func ui(_ s: CGFloat, _ w: NSFont.Weight = .regular) -> NSFont {
        NSFont.systemFont(ofSize: s, weight: w)
    }
}

func makeLabel(_ text: String, _ font: NSFont, _ color: NSColor) -> NSTextField {
    let l = NSTextField(labelWithString: text)
    l.font = font
    l.textColor = color
    l.lineBreakMode = .byTruncatingTail
    l.maximumNumberOfLines = 1
    return l
}

/// Applies letter-spacing, which plain `stringValue` can't express.
func setTracked(_ field: NSTextField, _ text: String, _ tracking: CGFloat) {
    field.attributedStringValue = NSAttributedString(string: text, attributes: [
        .font: field.font ?? F.ui(11),
        .foregroundColor: field.textColor ?? C.ink,
        .kern: tracking
    ])
}

func symbol(_ name: String, _ size: CGFloat, _ weight: NSFont.Weight = .semibold) -> NSImage? {
    guard #available(macOS 11.0, *),
          let img = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
    let out = img.withSymbolConfiguration(
        NSImage.SymbolConfiguration(pointSize: size, weight: weight)) ?? img
    out.isTemplate = true
    return out
}

func textShadow(_ opacity: CGFloat, _ blur: CGFloat) -> NSShadow {
    let s = NSShadow()
    s.shadowColor      = NSColor.black.withAlphaComponent(opacity)
    s.shadowBlurRadius = blur
    s.shadowOffset     = NSSize(width: 0, height: -1)
    return s
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Primitives
// ─────────────────────────────────────────────────────────────────────────────

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// A one-directional gradient veil, used to keep type legible over photography.
final class ScrimView: NSView {
    enum Edge { case bottom, top }
    var edge: Edge = .bottom
    var strength: CGFloat = 0.80 { didSet { needsDisplay = true } }

    var allowsWindowDrag = true
    override var mouseDownCanMoveWindow: Bool { allowsWindowDrag }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let dark = NSColor(hex: 0x140F0A, alpha: strength)
        let mid  = NSColor(hex: 0x140F0A, alpha: strength * 0.28)
        let none = NSColor(hex: 0x140F0A, alpha: 0)
        let g = NSGradient(colors: [dark, mid, none], atLocations: [0, 0.55, 1], colorSpace: .sRGB)
        g?.draw(in: bounds, angle: edge == .bottom ? 90 : 270)
    }
}

/// Layer-backed image host that fills its bounds (no letterboxing) and can
/// cross-fade or scale without re-laying anything out.
final class ImageLayerView: NSView {
    private let host = CALayer()
    private var zoom: CGFloat = 1

    /// The hero image doubles as a window drag handle; copies inside controls must not.
    var allowsWindowDrag = true
    override var mouseDownCanMoveWindow: Bool { allowsWindowDrag }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        host.contentsGravity = .resizeAspectFill
        host.masksToBounds   = true
        host.backgroundColor = NSColor(hex: 0x2A2118).cgColor
        layer?.addSublayer(host)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        host.transform     = CATransform3DIdentity
        host.frame         = bounds
        host.contentsScale = window?.backingScaleFactor ?? 2
        host.transform     = CATransform3DMakeScale(zoom, zoom, 1)
        CATransaction.commit()
    }

    func setImage(_ image: NSImage?, animated: Bool = false) {
        if animated {
            let t = CATransition()
            t.type     = .fade
            t.duration = 0.55
            host.add(t, forKey: "contents")
        }
        // CGImage rather than NSImage: NSImage-backed layer contents don't
        // survive `CALayer.render(in:)` and offscreen compositing.
        var rect = CGRect(origin: .zero, size: image?.size ?? .zero)
        host.contents = image?.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    /// Colour shown before an image is set (and behind transparent ones).
    var placeholderColor: NSColor = NSColor(hex: 0x2A2118) {
        didSet { host.backgroundColor = placeholderColor.cgColor }
    }

    func setZoom(_ value: CGFloat) {
        guard value != zoom else { return }
        zoom = value
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.32)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        host.transform = CATransform3DMakeScale(value, value, 1)
        CATransaction.commit()
    }
}

/// Small capsule of tracked, uppercase type — "NOW PLAYING", scene counts.
final class TagView: NSView {
    private let label = NSTextField(labelWithString: "")

    private var textWidth: CGFloat = 0

    init(_ text: String, fill: NSColor, ink: NSColor) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = fill.cgColor
        label.font              = F.ui(9.5, .heavy)
        label.textColor         = ink
        label.usesSingleLineMode = true
        label.cell?.lineBreakMode = .byClipping
        addSubview(label)
        setText(text)
    }
    required init?(coder: NSCoder) { fatalError() }

    var fittingWidth: CGFloat { textWidth + 22 }

    func setText(_ text: String) {
        setTracked(label, text, 0.9)
        label.sizeToFit()
        textWidth = ceil(label.frame.width)
        needsLayout = true
        invalidateIntrinsicContentSize()
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        label.frame = NSRect(x: 11, y: (bounds.height - 14) / 2, width: textWidth, height: 14)
    }
}

/// Quiet "this one is live" mark: three bars breathing inside a frosted disc.
/// Reads as playback without shouting a label over the photography.
final class LiveBadge: NSView {

    override var mouseDownCanMoveWindow: Bool { false }

    private var bars: [CALayer] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(hex: 0x140F0A, alpha: 0.52).cgColor
        layer?.borderWidth     = 1
        layer?.borderColor     = NSColor.white.withAlphaComponent(0.28).cgColor
        for _ in 0..<3 {
            let l = CALayer()
            l.backgroundColor = NSColor.white.cgColor
            l.cornerRadius    = 1.25
            l.anchorPoint     = CGPoint(x: 0.5, y: 0)   // grow upward from the base
            layer?.addSublayer(l)
            bars.append(l)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let bw: CGFloat = 2.5, gap: CGFloat = 3.5, h: CGFloat = 11
        let total = bw * 3 + gap * 2
        let x0    = (bounds.width - total) / 2
        let yBase = (bounds.height - h) / 2
        for (i, l) in bars.enumerated() {
            l.bounds   = CGRect(x: 0, y: 0, width: bw, height: h)
            l.position = CGPoint(x: x0 + CGFloat(i) * (bw + gap) + bw / 2, y: yBase)
        }
        CATransaction.commit()
        startBars()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window == nil ? stopBars() : startBars()
    }

    private func startBars() {
        guard window != nil else { return }
        for (i, l) in bars.enumerated() where l.animation(forKey: "eq") == nil {
            let a = CABasicAnimation(keyPath: "transform.scale.y")
            a.fromValue      = 0.30
            a.toValue        = 1.0
            a.duration       = 0.55 + Double(i) * 0.18
            a.autoreverses   = true
            a.repeatCount    = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            l.add(a, forKey: "eq")
        }
    }

    private func stopBars() { bars.forEach { $0.removeAnimation(forKey: "eq") } }
}

/// Pill-shaped action button with hover + press feedback.
final class PillButton: NSView {
    enum Kind { case solid, glass, ink, quiet }

    var onClick: (() -> Void)?

    override var mouseDownCanMoveWindow: Bool { false }

    private let kind: Kind
    private let iconView = NSImageView()
    private let label    = NSTextField(labelWithString: "")
    private var tracker: NSTrackingArea?
    private var hovered = false { didSet { restyle() } }
    private var pressed = false { didSet { restyle() } }

    init(title: String, systemImage: String?, kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true

        if let name = systemImage, let img = symbol(name, 12.5, .bold) {
            iconView.image = img
            addSubview(iconView)
        }
        label.font               = F.ui(13, .semibold)
        label.usesSingleLineMode = true
        label.cell?.lineBreakMode = .byClipping
        addSubview(label)
        setTitle(title, systemImage: systemImage)
    }
    required init?(coder: NSCoder) { fatalError() }

    private var textWidth: CGFloat = 0

    var fittingWidth: CGFloat {
        textWidth + (iconView.image != nil ? 23 : 0) + 38
    }

    func setTitle(_ t: String, systemImage: String?) {
        label.stringValue = t
        label.sizeToFit()
        textWidth = ceil(label.frame.width)
        if let name = systemImage { iconView.image = symbol(name, 12.5, .bold) }
        needsLayout = true
        restyle()
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        var x: CGFloat = 18
        if iconView.image != nil {
            iconView.frame = NSRect(x: x, y: (bounds.height - 14) / 2, width: 14, height: 14)
            x += 23
        }
        label.frame = NSRect(x: x, y: (bounds.height - 17) / 2, width: textWidth, height: 17)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracker { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeInActiveApp],
                               owner: self)
        addTrackingArea(t); tracker = t
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func mouseEntered(with e: NSEvent) { hovered = true }
    override func mouseExited(with e: NSEvent)  { hovered = false; pressed = false }
    override func mouseDown(with e: NSEvent)    { pressed = true }
    override func mouseUp(with e: NSEvent) {
        pressed = false
        if bounds.contains(convert(e.locationInWindow, from: nil)) { onClick?() }
    }

    private func restyle() {
        switch kind {
        case .solid:
            let a: CGFloat = pressed ? 0.86 : (hovered ? 1.0 : 0.95)
            layer?.backgroundColor = NSColor.white.withAlphaComponent(a).cgColor
            layer?.borderWidth = 0
            label.textColor        = C.ink
            iconView.contentTintColor = C.ember
        case .glass:
            let a: CGFloat = pressed ? 0.34 : (hovered ? 0.26 : 0.15)
            layer?.backgroundColor = NSColor.white.withAlphaComponent(a).cgColor
            layer?.borderWidth     = 1
            layer?.borderColor     = NSColor.white.withAlphaComponent(hovered ? 0.55 : 0.34).cgColor
            label.textColor        = .white
            iconView.contentTintColor = .white
        case .ink:
            let a: CGFloat = pressed ? 0.78 : (hovered ? 1.0 : 0.9)
            layer?.backgroundColor = C.ink.withAlphaComponent(a).cgColor
            layer?.borderWidth     = 0
            label.textColor        = C.paper
            iconView.contentTintColor = C.paper
        case .quiet:
            let a: CGFloat = pressed ? 0.17 : (hovered ? 0.12 : 0.07)
            layer?.backgroundColor = C.ink.withAlphaComponent(a).cgColor
            layer?.borderWidth     = 0
            label.textColor        = C.ink
            iconView.contentTintColor = C.inkSoft
        }
    }
}

/// Round icon button for the transport bar.
final class IconButton: NSView {
    var onClick: (() -> Void)?
    var isOn = true { didSet { restyle() } }
    var toolTipText: String = "" { didSet { toolTip = toolTipText } }

    override var mouseDownCanMoveWindow: Bool { false }

    private let iconView = NSImageView()
    private var onName: String
    private var offName: String
    private let prominent: Bool
    private let overlay: Bool
    private var tracker: NSTrackingArea?
    private var hovered = false { didSet { restyle() } }

    init(on: String, off: String? = nil, prominent: Bool = false, overlay: Bool = false) {
        self.onName    = on
        self.offName   = off ?? on
        self.prominent = prominent
        self.overlay   = overlay
        super.init(frame: .zero)
        wantsLayer = true
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)
        restyle()
    }
    required init?(coder: NSCoder) { fatalError() }

    func setSymbols(on: String, off: String) {
        onName = on; offName = off; restyle()
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        let s: CGFloat = prominent ? 17 : 15
        iconView.frame = NSRect(x: (bounds.width - s) / 2, y: (bounds.height - s) / 2, width: s, height: s)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracker { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeInActiveApp],
                               owner: self)
        addTrackingArea(t); tracker = t
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func mouseEntered(with e: NSEvent) { hovered = true }
    override func mouseExited(with e: NSEvent)  { hovered = false }
    override func mouseUp(with e: NSEvent) {
        if bounds.contains(convert(e.locationInWindow, from: nil)) { onClick?() }
    }

    private func restyle() {
        iconView.image = symbol(isOn ? onName : offName, prominent ? 15 : 13.5, .semibold)
        if overlay {
            layer?.backgroundColor    = NSColor(hex: 0x140F0A, alpha: hovered ? 0.82 : 0.55).cgColor
            layer?.borderWidth        = 1
            layer?.borderColor        = NSColor.white.withAlphaComponent(0.30).cgColor
            iconView.contentTintColor = .white
        } else if prominent {
            layer?.backgroundColor    = C.ink.withAlphaComponent(hovered ? 1.0 : 0.9).cgColor
            iconView.contentTintColor = C.paper
        } else {
            layer?.backgroundColor    = isOn
                ? C.ink.withAlphaComponent(hovered ? 0.12 : 0.07).cgColor
                : C.ember.withAlphaComponent(hovered ? 0.26 : 0.18).cgColor
            iconView.contentTintColor = isOn ? C.inkSoft : C.ember
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Scene model
// ─────────────────────────────────────────────────────────────────────────────

struct Scene: Decodable {
    let id: String
    let title: String
    let video: String
    let thumb: String

    var videoURL: URL? {
        Bundle.main.url(forResource: (video as NSString).deletingPathExtension,
                        withExtension: "mp4", subdirectory: "scenes")
    }
    var thumbImage: NSImage? {
        guard let u = Bundle.main.url(forResource: (thumb as NSString).deletingPathExtension,
                                      withExtension: "jpg", subdirectory: "scenes") else { return nil }
        return NSImage(contentsOf: u)
    }
    var isAvailable: Bool { videoURL != nil }
}

enum SceneLibrary {
    static let all: [Scene] = {
        guard let url = Bundle.main.url(forResource: "manifest", withExtension: "json",
                                        subdirectory: "scenes"),
              let data = try? Data(contentsOf: url),
              let s = try? JSONDecoder().decode([Scene].self, from: data)
        else { return [] }
        return s.filter { $0.isAvailable }
    }()

    static func index(of id: String) -> Int? { all.firstIndex { $0.id == id } }
    static func scene(_ id: String) -> Scene? { all.first { $0.id == id } }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Wallpaper window
// ─────────────────────────────────────────────────────────────────────────────

final class WallpaperWindow: NSWindow {

    /// One video layer. Two of these live in the window and cross-fade, so a
    /// scene change dissolves rather than cutting, and the very first scene
    /// rises out of the window's black background.
    private final class Slot {
        let view = AVPlayerView()
        var player: AVPlayer?
        var loop: NSObjectProtocol?
        var status: NSKeyValueObservation?
        var boundary: Any?

        init() {
            view.controlsStyle    = .none
            view.videoGravity     = .resizeAspectFill
            view.autoresizingMask = [.width, .height]
            view.alphaValue       = 0
        }

        func teardown() {
            if let l = loop { NotificationCenter.default.removeObserver(l) }
            loop   = nil
            status = nil
            if let b = boundary, let p = player { p.removeTimeObserver(b) }
            boundary = nil
            player?.pause()
            player      = nil
            view.player = nil
        }
    }

    /// Long enough to read as a dissolve, short enough not to feel sluggish.
    static let fadeDuration: TimeInterval = 0.85

    /// How early the loop dissolve starts, relative to the end of the clip.
    private let loopLead: TimeInterval = 1.2
    private var currentURL: URL?

    private var front = Slot()
    private var back  = Slot()
    private var generation = 0

    private var videoEnabled = true
    private var audioEnabled = true
    private var vol: Float    = 0.7
    private var paused        = false

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless,
                   backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level              = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        isOpaque           = true
        backgroundColor    = .black
        ignoresMouseEvents = true
        hasShadow          = false

        for slot in [front, back] {
            slot.view.frame = contentView!.bounds
            contentView!.addSubview(slot.view)
        }
    }

    deinit {
        front.teardown()
        back.teardown()
    }

    // MARK: Playback

    func play(url: URL) {
        generation += 1
        let g = generation
        currentURL = url

        back.teardown()
        back.view.alphaValue = 0
        contentView?.addSubview(back.view, positioned: .above, relativeTo: front.view)

        let item = AVPlayerItem(url: url)
        let p    = AVPlayer(playerItem: item)
        p.isMuted = !audioEnabled
        p.volume  = vol
        back.player      = p
        back.view.player = p

        // Safety net only: the loop normally happens via the boundary observer
        // below, well before the clip actually runs out.
        back.loop = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak p] _ in p?.seek(to: .zero); p?.play() }

        // Hold the fade until there are actual frames to show, otherwise the
        // dissolve reveals an empty layer before the video catches up.
        back.status = item.observe(\.status, options: [.initial, .new]) { [weak self] it, _ in
            guard it.status == .readyToPlay else { return }
            DispatchQueue.main.async { self?.reveal(generation: g) }
        }

        if !paused { p.play() }
    }

    private func reveal(generation g: Int) {
        guard g == generation, back.player != nil else { return }
        back.status = nil

        let target: CGFloat = videoEnabled ? 1 : 0

        // Only the incoming layer fades. Fading the outgoing one out at the same
        // time leaves both partly transparent mid-dissolve, so the window's black
        // background shows through between them — a measured 25% luminance dip
        // that reads as a black flash. Holding the outgoing layer opaque
        // underneath keeps the composite at full brightness throughout.
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration       = WallpaperWindow.fadeDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            back.view.animator().alphaValue = target
        }, completionHandler: { [weak self] in
            guard let self = self, g == self.generation else { return }
            self.front.teardown()
            swap(&self.front, &self.back)
            // The retired layer sits below the new one at full alpha; clear it so
            // hiding the video layer later reveals the desktop, not a stale frame.
            self.back.view.alphaValue = 0
            self.installLoopTrigger()
        })
    }

    /// Near the end of the clip, dissolve into a fresh copy playing from the
    /// top. The loop point then reads as one continuous take rather than a cut
    /// back to black while the player re-seeks.
    private func installLoopTrigger() {
        guard let p = front.player, let item = p.currentItem else { return }
        let duration = CMTimeGetSeconds(item.duration)
        guard duration.isFinite, duration > loopLead + 1 else { return }

        let mark = CMTime(seconds: duration - loopLead, preferredTimescale: 600)
        front.boundary = p.addBoundaryTimeObserver(
            forTimes: [NSValue(time: mark)], queue: .main
        ) { [weak self] in
            guard let self = self, let url = self.currentURL else { return }
            self.play(url: url)
        }
    }

    /// Fades everything out, then reports back so the caller can drop the window.
    func fadeOut(_ done: @escaping () -> Void) {
        generation += 1
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration       = WallpaperWindow.fadeDuration * 0.7
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().alphaValue = 0
        }, completionHandler: {
            self.front.teardown()
            self.back.teardown()
            done()
        })
    }

    // MARK: Controls

    func setPaused(_ p: Bool) {
        paused = p
        for slot in [front, back] { p ? slot.player?.pause() : slot.player?.play() }
    }

    func setVideoEnabled(_ on: Bool) {
        videoEnabled = on
        if on {
            // Opaque black again, so cross-fades composite against a solid ground.
            isOpaque        = true
            backgroundColor = .black
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration       = 0.45
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            front.view.animator().alphaValue = on ? 1 : 0
        }, completionHandler: { [weak self] in
            guard let self = self, !self.videoEnabled else { return }
            // Drop the black backing so the user's own wallpaper shows through.
            // Audio keeps playing underneath.
            self.isOpaque        = false
            self.backgroundColor = .clear
        })
    }

    func setAudioEnabled(_ on: Bool) {
        audioEnabled = on
        for slot in [front, back] { slot.player?.isMuted = !on }
    }

    func setVolume(_ v: Float) {
        vol = max(0, min(1, v))
        for slot in [front, back] { slot.player?.volume = vol }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Hero
// ─────────────────────────────────────────────────────────────────────────────

final class HeroView: NSView {

    var onSet:     (() -> Void)?
    var onShuffle: (() -> Void)?
    var onQueue:   (() -> Void)?
    var onClear:   (() -> Void)?

    private let image     = ImageLayerView()
    private let bottom    = ScrimView()
    private let top       = ScrimView()
    private let eyebrow   = NSTextField(labelWithString: "")
    private let titleLbl  = makeLabel("", F.display(52, .bold), .white)
    private let blurbLbl  = makeLabel("", F.ui(15, .medium), NSColor.white.withAlphaComponent(0.86))
    private let setBtn    = PillButton(title: "Set as wallpaper", systemImage: "sparkles", kind: .solid)
    private let shuffleBtn = PillButton(title: "Shuffle", systemImage: "shuffle", kind: .glass)
    private let queueBtn   = PillButton(title: "Add to Up Next", systemImage: "text.append", kind: .glass)
    private let clearBtn   = PillButton(title: "Clear wallpaper", systemImage: "xmark", kind: .glass)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(hex: 0x2A2118).cgColor

        addSubview(image)

        top.edge = .top; top.strength = 0.34
        addSubview(top)

        bottom.edge = .bottom; bottom.strength = 0.88
        addSubview(bottom)

        eyebrow.font      = F.ui(11, .heavy)
        eyebrow.textColor = NSColor.white.withAlphaComponent(0.72)
        setTracked(eyebrow, "GLASSWOOD  ·  LIVING WALLPAPER", 1.6)
        addSubview(eyebrow)

        titleLbl.shadow = textShadow(0.45, 14)
        blurbLbl.shadow = textShadow(0.40, 8)
        addSubview(titleLbl)
        addSubview(blurbLbl)

        setBtn.onClick     = { [weak self] in self?.onSet?() }
        shuffleBtn.onClick = { [weak self] in self?.onShuffle?() }
        queueBtn.onClick   = { [weak self] in self?.onQueue?() }
        clearBtn.onClick   = { [weak self] in self?.onClear?() }
        addSubview(setBtn)
        addSubview(shuffleBtn)
        addSubview(queueBtn)
        addSubview(clearBtn)
    }
    required init?(coder: NSCoder) { fatalError() }

    private var shownID: String?

    func show(scene: Scene?, isPlaying: Bool, count: Int) {
        let animated = shownID != nil && shownID != scene?.id
        shownID = scene?.id

        image.setImage(scene?.thumbImage, animated: animated)
        titleLbl.stringValue = scene?.title ?? "Nothing to show yet"
        blurbLbl.stringValue = scene == nil
            ? "No scenes were bundled with this copy of Glasswood."
            : "Five quiet minutes, looping behind everything you do."

        // Status belongs in the eyebrow, not in a button that stops being one.
        let eyebrowText: String
        if isPlaying            { eyebrowText = "NOW ON YOUR DESKTOP" }
        else if count == 0      { eyebrowText = "GLASSWOOD" }
        else                    { eyebrowText = "GLASSWOOD  ·  \(count) LIVING SCENES" }
        eyebrow.textColor = isPlaying
            ? NSColor.white.withAlphaComponent(0.95)
            : NSColor.white.withAlphaComponent(0.72)
        setTracked(eyebrow, eyebrowText, 1.6)

        setBtn.isHidden     = scene == nil
        shuffleBtn.isHidden = count < 2
        queueBtn.isHidden   = scene == nil
        clearBtn.isHidden   = !isPlaying
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        image.frame  = bounds
        top.frame    = NSRect(x: 0, y: h - 110, width: w, height: 110)
        bottom.frame = NSRect(x: 0, y: 0, width: w, height: min(h, 300))

        let x: CGFloat = 44
        let btnH: CGFloat = 42
        var bx = x
        for b in [setBtn, shuffleBtn, queueBtn, clearBtn] where !b.isHidden {
            b.frame = NSRect(x: bx, y: 40, width: b.fittingWidth, height: btnH)
            bx += b.fittingWidth + 12
        }

        blurbLbl.frame = NSRect(x: x, y: 40 + btnH + 20, width: w - x * 2, height: 22)
        titleLbl.frame = NSRect(x: x - 2, y: 40 + btnH + 46, width: w - x * 2, height: 64)
        eyebrow.frame  = NSRect(x: x, y: 40 + btnH + 118, width: w - x * 2, height: 16)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Scene card
// ─────────────────────────────────────────────────────────────────────────────

final class SceneCard: NSView {

    override var mouseDownCanMoveWindow: Bool { false }

    let scene: Scene
    var onClick: ((Scene) -> Void)?
    var onQueue: ((Scene) -> Void)?

    private let clip     = NSView()
    private let image    = ImageLayerView()
    private let scrim    = ScrimView()
    private let titleLbl = makeLabel("", F.display(17, .semibold), .white)
    private let live     = LiveBadge()
    private let queueBtn = IconButton(on: "plus", overlay: true)
    private let glyph    = NSImageView()
    private let glyphBg  = NSView()
    private var tracker: NSTrackingArea?

    var isSelected = false { didSet { restyle() } }
    private var hovered = false { didSet { restyle() } }

    init(scene: Scene) {
        self.scene = scene
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds  = false
        layer?.shadowColor    = NSColor(hex: 0x2A2118).cgColor
        layer?.shadowOffset   = CGSize(width: 0, height: -4)

        clip.wantsLayer          = true
        clip.layer?.cornerRadius = 18
        clip.layer?.masksToBounds = true
        clip.layer?.borderWidth  = 0
        addSubview(clip)

        image.allowsWindowDrag = false
        image.setImage(scene.thumbImage)
        clip.addSubview(image)

        scrim.edge = .bottom
        scrim.strength = 0.86
        scrim.allowsWindowDrag = false
        clip.addSubview(scrim)

        titleLbl.stringValue = scene.title
        titleLbl.shadow      = textShadow(0.5, 6)
        clip.addSubview(titleLbl)

        live.isHidden = true
        clip.addSubview(live)

        queueBtn.toolTipText = "Add to Up Next"
        queueBtn.alphaValue  = 0
        queueBtn.onClick     = { [weak self] in
            guard let self = self else { return }
            self.onQueue?(self.scene)
        }
        clip.addSubview(queueBtn)

        glyphBg.wantsLayer = true
        glyphBg.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.92).cgColor
        glyphBg.alphaValue = 0
        clip.addSubview(glyphBg)

        glyph.image = symbol("play.fill", 15, .bold)
        glyph.contentTintColor = C.ink
        glyph.alphaValue = 0
        clip.addSubview(glyph)

        restyle()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        clip.frame  = bounds
        image.frame = clip.bounds
        scrim.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height * 0.62)
        titleLbl.frame = NSRect(x: 16, y: 15, width: bounds.width - 32, height: 22)

        live.frame     = NSRect(x: 15, y: bounds.height - 41, width: 26, height: 26)
        queueBtn.frame = NSRect(x: bounds.width - 15 - 28, y: bounds.height - 43,
                                width: 28, height: 28)

        let g: CGFloat = 46
        glyphBg.frame = NSRect(x: (bounds.width - g) / 2, y: (bounds.height - g) / 2 + 8,
                               width: g, height: g)
        glyphBg.layer?.cornerRadius = g / 2
        glyph.frame = NSRect(x: (bounds.width - 16) / 2 + 1, y: (bounds.height - 16) / 2 + 8,
                             width: 16, height: 16)

        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: 18, cornerHeight: 18,
                                   transform: nil)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracker { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeInActiveApp],
                               owner: self)
        addTrackingArea(t); tracker = t
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func mouseEntered(with e: NSEvent) { hovered = true }
    override func mouseExited(with e: NSEvent)  { hovered = false }
    override func mouseUp(with e: NSEvent) {
        if bounds.contains(convert(e.locationInWindow, from: nil)) { onClick?(scene) }
    }

    private func restyle() {
        live.isHidden = !isSelected

        clip.layer?.borderWidth = isSelected ? 3 : 0
        clip.layer?.borderColor = C.moss.cgColor

        let lifted = hovered || isSelected
        layer?.shadowOpacity = lifted ? 0.26 : 0.13
        layer?.shadowRadius  = lifted ? 20 : 10
        image.setZoom(hovered ? 1.06 : 1.0)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            glyphBg.animator().alphaValue  = hovered && !isSelected ? 1 : 0
            glyph.animator().alphaValue    = hovered && !isSelected ? 1 : 0
            queueBtn.animator().alphaValue = hovered ? 1 : 0
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Transport bar
// ─────────────────────────────────────────────────────────────────────────────

final class PlayBar: NSView {

    override var mouseDownCanMoveWindow: Bool { false }

    var onPlayPause: ((Bool) -> Void)?
    var onVideo:     ((Bool) -> Void)?
    var onAudio:     ((Bool) -> Void)?
    var onVolume:    ((Float) -> Void)?
    var onPrev:      (() -> Void)?
    var onNext:      (() -> Void)?
    var onClear:     (() -> Void)?
    var onQueue:     (() -> Void)?

    private let glass    = NSVisualEffectView()
    private let tint     = NSView()
    private let thumb    = ImageLayerView()
    private let titleLbl = makeLabel("Nothing playing", F.display(14, .semibold), C.ink)
    private let subLbl   = makeLabel("Pick a scene to begin", F.ui(11.5, .medium), C.inkFaint)
    private let prevBtn  = IconButton(on: "backward.end.fill")
    private let playBtn  = IconButton(on: "pause.fill", off: "play.fill", prominent: true)
    private let nextBtn  = IconButton(on: "forward.end.fill")
    private let videoBtn = IconButton(on: "photo.fill", off: "photo")
    private let audioBtn = IconButton(on: "speaker.wave.2.fill", off: "speaker.slash.fill")
    private let clearBtn = IconButton(on: "stop.fill")
    private let queueBtn = IconButton(on: "list.bullet")
    private let slider   = NSSlider()

    private(set) var isPaused = false
    private(set) var videoOn  = true
    private(set) var audioOn  = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds  = false
        layer?.shadowColor    = NSColor(hex: 0x2A2118).cgColor
        layer?.shadowOpacity  = 0.20
        layer?.shadowRadius   = 22
        layer?.shadowOffset   = CGSize(width: 0, height: -6)

        glass.material    = .popover
        glass.blendingMode = .withinWindow
        glass.state       = .active
        glass.wantsLayer  = true
        glass.layer?.cornerRadius  = 22
        glass.layer?.masksToBounds = true
        addSubview(glass)

        tint.wantsLayer = true
        tint.layer?.backgroundColor = C.paperDeep.withAlphaComponent(0.55).cgColor
        glass.addSubview(tint)

        thumb.wantsLayer          = true
        thumb.layer?.cornerRadius = 11
        thumb.layer?.masksToBounds = true
        thumb.placeholderColor    = NSColor(hex: 0x2A2018, alpha: 0.08)
        thumb.allowsWindowDrag    = false
        glass.addSubview(thumb)

        glass.addSubview(titleLbl)
        glass.addSubview(subLbl)

        prevBtn.toolTipText  = "Previous scene"
        nextBtn.toolTipText  = "Next scene"
        playBtn.toolTipText  = "Play / pause"
        videoBtn.toolTipText = "Show or hide the video layer"
        audioBtn.toolTipText = "Mute or unmute"
        clearBtn.toolTipText = "Clear the wallpaper and return to your desktop"
        queueBtn.toolTipText = "Up Next"

        prevBtn.onClick  = { [weak self] in self?.onPrev?() }
        nextBtn.onClick  = { [weak self] in self?.onNext?() }
        playBtn.onClick  = { [weak self] in self?.togglePlay() }
        videoBtn.onClick = { [weak self] in self?.toggleVideo() }
        audioBtn.onClick = { [weak self] in self?.toggleAudio() }
        clearBtn.onClick = { [weak self] in self?.onClear?() }
        queueBtn.onClick = { [weak self] in self?.onQueue?() }
        [prevBtn, playBtn, nextBtn, videoBtn, audioBtn, clearBtn, queueBtn]
            .forEach { glass.addSubview($0) }

        slider.minValue = 0
        slider.maxValue = 1
        slider.floatValue = 0.7
        slider.controlSize = .small
        slider.trackFillColor = C.moss
        slider.target = self
        slider.action = #selector(volumeChanged)
        slider.toolTip = "Volume"
        glass.addSubview(slider)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        glass.frame = bounds
        tint.frame  = bounds
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: 22, cornerHeight: 22,
                                   transform: nil)

        let h = bounds.height
        thumb.frame    = NSRect(x: 16, y: (h - 46) / 2, width: 78, height: 46)
        titleLbl.frame = NSRect(x: 106, y: h / 2 + 1,  width: 200, height: 19)
        subLbl.frame   = NSRect(x: 106, y: h / 2 - 18, width: 200, height: 16)

        let cy = (h - 34) / 2
        var x = bounds.width - 20 - 118            // volume slider
        slider.frame = NSRect(x: x, y: (h - 20) / 2, width: 118, height: 20)

        x -= 12 + 34; queueBtn.frame = NSRect(x: x, y: cy, width: 34, height: 34)
        x -= 8  + 34; clearBtn.frame = NSRect(x: x, y: cy, width: 34, height: 34)
        x -= 8  + 34; audioBtn.frame = NSRect(x: x, y: cy, width: 34, height: 34)
        x -= 8  + 34; videoBtn.frame = NSRect(x: x, y: cy, width: 34, height: 34)

        x -= 20 + 34; nextBtn.frame  = NSRect(x: x, y: cy, width: 34, height: 34)
        x -= 6  + 40; playBtn.frame  = NSRect(x: x, y: (h - 40) / 2, width: 40, height: 40)
        x -= 6  + 34; prevBtn.frame  = NSRect(x: x, y: cy, width: 34, height: 34)
    }

    func update(scene: Scene?, hasLibrary: Bool) {
        thumb.setImage(scene?.thumbImage, animated: true)
        titleLbl.stringValue = scene?.title ?? "Nothing playing"
        subLbl.stringValue   = scene == nil
            ? "Pick a scene to begin"
            : (isPaused ? "Paused" : "Looping on every display")
        let live = scene != nil
        playBtn.isOn = live && !isPaused
        [playBtn, videoBtn, audioBtn, clearBtn].forEach { $0.alphaValue = live ? 1 : 0.4 }
        [prevBtn, nextBtn].forEach { $0.alphaValue = hasLibrary ? 1 : 0.4 }
        slider.isEnabled = live
    }

    func setVolume(_ v: Float) { slider.floatValue = v }
    func setVideo(_ on: Bool)  { videoOn = on; videoBtn.isOn = on }
    func setAudio(_ on: Bool)  { audioOn = on; audioBtn.isOn = on }

    func togglePlay() {
        isPaused.toggle()
        playBtn.isOn = !isPaused
        onPlayPause?(isPaused)
    }
    func toggleVideo() { videoOn.toggle(); videoBtn.isOn = videoOn; onVideo?(videoOn) }
    func toggleAudio() { audioOn.toggle(); audioBtn.isOn = audioOn; onAudio?(audioOn) }

    @objc private func volumeChanged() { onVolume?(slider.floatValue) }
}

/// Small segmented control: a sliding pill over a tinted track.
final class SegmentedPills: NSView {

    override var mouseDownCanMoveWindow: Bool { false }

    var onSelect: ((Int) -> Void)?
    private(set) var selectedIndex = 0

    private let track  = NSView()
    private let thumb  = NSView()
    private var labels: [NSTextField] = []

    init(titles: [String]) {
        super.init(frame: .zero)
        wantsLayer = true

        track.wantsLayer = true
        track.layer?.backgroundColor = C.ink.withAlphaComponent(0.08).cgColor
        addSubview(track)

        thumb.wantsLayer = true
        thumb.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.94).cgColor
        thumb.layer?.shadowColor   = NSColor(hex: 0x2A2018).cgColor
        thumb.layer?.shadowOpacity = 0.16
        thumb.layer?.shadowRadius  = 4
        thumb.layer?.shadowOffset  = CGSize(width: 0, height: -1)
        addSubview(thumb)

        for t in titles {
            let l = makeLabel(t, F.ui(11, .semibold), C.inkSoft)
            l.alignment = .center
            addSubview(l)
            labels.append(l)
        }
        restyle()
    }
    required init?(coder: NSCoder) { fatalError() }

    private var segmentWidth: CGFloat {
        labels.isEmpty ? 0 : bounds.width / CGFloat(labels.count)
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        track.frame = bounds
        track.layer?.cornerRadius = h / 2

        let w = segmentWidth
        for (i, l) in labels.enumerated() {
            l.frame = NSRect(x: CGFloat(i) * w, y: (h - 14) / 2, width: w, height: 14)
        }
        thumb.frame = NSRect(x: CGFloat(selectedIndex) * w + 2, y: 3, width: max(0, w - 4), height: h - 6)
        thumb.layer?.cornerRadius = (h - 6) / 2
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func mouseUp(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        guard bounds.contains(p), segmentWidth > 0 else { return }
        let i = max(0, min(labels.count - 1, Int(p.x / segmentWidth)))
        guard i != selectedIndex else { return }
        select(i, animated: true)
        onSelect?(i)
    }

    func select(_ i: Int, animated: Bool) {
        guard labels.indices.contains(i) else { return }
        selectedIndex = i
        let w = segmentWidth
        let target = NSRect(x: CGFloat(i) * w + 2, y: 3, width: max(0, w - 4), height: bounds.height - 6)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration       = 0.20
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                thumb.animator().frame = target
            }
        } else {
            thumb.frame = target
        }
        restyle()
    }

    private func restyle() {
        for (i, l) in labels.enumerated() {
            l.textColor = i == selectedIndex ? C.ink : C.inkFaint
            l.font      = F.ui(11, i == selectedIndex ? .bold : .semibold)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Up Next
// ─────────────────────────────────────────────────────────────────────────────

final class QueueRow: NSView {

    override var mouseDownCanMoveWindow: Bool { false }

    var position: Int
    var onPlay:      ((Int) -> Void)?
    var onRemove:    ((Int) -> Void)?
    var onDragBegin: ((QueueRow) -> Void)?
    var onDragMove:  ((QueueRow, CGFloat) -> Void)?
    var onDragEnd:   ((QueueRow) -> Void)?

    private let posLbl    = makeLabel("", F.ui(11, .heavy), C.inkFaint)
    private let grip      = NSImageView()
    private let thumb     = ImageLayerView()
    private let titleLbl  = makeLabel("", F.display(13.5, .semibold), C.ink)
    private let removeBtn = IconButton(on: "xmark")
    private var tracker: NSTrackingArea?
    private var hovered = false { didSet { restyle() } }

    private var mouseDownAt: NSPoint = .zero
    private var isDragging = false

    init(position: Int, scene: Scene) {
        self.position = position
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        toolTip = "Click to play · drag to reorder"

        posLbl.stringValue = String(format: "%02d", position + 1)
        posLbl.alignment   = .center
        addSubview(posLbl)

        grip.image = symbol("line.3.horizontal", 12, .semibold)
        grip.contentTintColor = C.inkFaint
        grip.alphaValue = 0
        addSubview(grip)

        thumb.wantsLayer           = true
        thumb.layer?.cornerRadius  = 8
        thumb.layer?.masksToBounds = true
        thumb.placeholderColor     = NSColor(hex: 0x2A2018, alpha: 0.08)
        thumb.allowsWindowDrag     = false
        thumb.setImage(scene.thumbImage)
        addSubview(thumb)

        titleLbl.stringValue = scene.title
        addSubview(titleLbl)

        removeBtn.toolTipText = "Remove from Up Next"
        removeBtn.alphaValue  = 0
        removeBtn.onClick     = { [weak self] in
            guard let self = self else { return }
            self.onRemove?(self.position)
        }
        addSubview(removeBtn)
        restyle()
    }
    required init?(coder: NSCoder) { fatalError() }

    func setNumber(_ n: Int) {
        position = n
        posLbl.stringValue = String(format: "%02d", n + 1)
    }

    /// Raised appearance while the row is being dragged.
    func setLifted(_ lifted: Bool) {
        layer?.masksToBounds  = false
        layer?.shadowColor    = NSColor(hex: 0x2A2018).cgColor
        layer?.shadowOpacity  = lifted ? 0.24 : 0
        layer?.shadowRadius   = lifted ? 14 : 0
        layer?.shadowOffset   = CGSize(width: 0, height: -3)
        layer?.backgroundColor = lifted
            ? C.paper.withAlphaComponent(0.98).cgColor
            : C.ink.withAlphaComponent(hovered ? 0.06 : 0).cgColor
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        posLbl.frame    = NSRect(x: 8, y: (h - 14) / 2, width: 24, height: 14)
        grip.frame      = NSRect(x: 12, y: (h - 14) / 2, width: 16, height: 14)
        thumb.frame     = NSRect(x: 36, y: (h - 38) / 2, width: 64, height: 38)
        titleLbl.frame  = NSRect(x: 110, y: (h - 18) / 2, width: max(0, bounds.width - 110 - 40), height: 18)
        removeBtn.frame = NSRect(x: bounds.width - 36, y: (h - 28) / 2, width: 28, height: 28)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracker { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeInActiveApp],
                               owner: self)
        addTrackingArea(t); tracker = t
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func mouseEntered(with e: NSEvent) { hovered = true }
    override func mouseExited(with e: NSEvent)  { if !isDragging { hovered = false } }

    override func mouseDown(with e: NSEvent) {
        mouseDownAt = e.locationInWindow
        isDragging  = false
    }

    override func mouseDragged(with e: NSEvent) {
        let dy = e.locationInWindow.y - mouseDownAt.y
        if !isDragging && abs(dy) > 3 {
            isDragging = true
            onDragBegin?(self)
        }
        if isDragging { onDragMove?(self, dy) }
    }

    override func mouseUp(with e: NSEvent) {
        if isDragging {
            isDragging = false
            onDragEnd?(self)
            hovered = bounds.contains(convert(e.locationInWindow, from: nil))
        } else if bounds.contains(convert(e.locationInWindow, from: nil)) {
            onPlay?(position)
        }
    }

    private func restyle() {
        layer?.backgroundColor = C.ink.withAlphaComponent(hovered ? 0.06 : 0).cgColor
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            removeBtn.animator().alphaValue = hovered ? 1 : 0
            grip.animator().alphaValue      = hovered ? 1 : 0
            posLbl.animator().alphaValue    = hovered ? 0 : 1
        }
    }
}

/// Slide-over list of what plays after the current scene, with a dwell timer
/// and drag-to-reorder.
final class QueuePanel: NSView {

    override var mouseDownCanMoveWindow: Bool { false }

    var onPlay:     ((Int) -> Void)?
    var onRemove:   ((Int) -> Void)?
    var onClearAll: (() -> Void)?
    var onClose:    (() -> Void)?
    var onDwell:    ((Int) -> Void)?
    /// New order expressed as original indices, e.g. [2, 0, 1].
    var onReorder:  (([Int]) -> Void)?

    static let dwellTitles  = ["Off", "5", "10", "15", "30", "60", "90"]
    static let dwellMinutes: [Int?] = [nil, 5, 10, 15, 30, 60, 90]

    private let glass    = NSVisualEffectView()
    private let tint     = NSView()
    private let titleLbl = makeLabel("Up Next", F.display(18, .bold), C.ink)
    private let subLbl   = makeLabel("", F.ui(11.5, .medium), C.inkFaint)
    private let closeBtn = IconButton(on: "xmark")
    private let clearBtn = IconButton(on: "trash")
    private let dwellCap = NSTextField(labelWithString: "")
    private let pills    = SegmentedPills(titles: QueuePanel.dwellTitles)
    private let rule     = NSView()
    private let scroll   = NSScrollView()
    private let doc      = FlippedView()
    private let emptyLbl = makeLabel("Nothing lined up yet.", F.display(14, .semibold), C.inkSoft)
    private let hintLbl  = makeLabel("Hover any scene and hit + to queue it.", F.ui(12), C.inkFaint)

    private var rows: [QueueRow] = []
    private var visualOrder: [QueueRow] = []
    private var dragging: QueueRow?
    private var dragOriginY: CGFloat = 0

    private let headerH: CGFloat = 152
    private let rowH: CGFloat    = 58

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.shadowColor   = NSColor(hex: 0x2A2018).cgColor
        layer?.shadowOpacity = 0.24
        layer?.shadowRadius  = 26
        layer?.shadowOffset  = CGSize(width: -4, height: -4)

        glass.material     = .popover
        glass.blendingMode = .withinWindow
        glass.state        = .active
        glass.wantsLayer   = true
        glass.layer?.cornerRadius  = 22
        glass.layer?.masksToBounds = true
        addSubview(glass)

        tint.wantsLayer = true
        tint.layer?.backgroundColor = C.paper.withAlphaComponent(0.80).cgColor
        glass.addSubview(tint)

        glass.addSubview(titleLbl)
        glass.addSubview(subLbl)

        closeBtn.toolTipText = "Hide Up Next"
        closeBtn.onClick     = { [weak self] in self?.onClose?() }
        glass.addSubview(closeBtn)

        clearBtn.toolTipText = "Empty the queue"
        clearBtn.onClick     = { [weak self] in self?.onClearAll?() }
        glass.addSubview(clearBtn)

        dwellCap.font      = F.ui(9.5, .heavy)
        dwellCap.textColor = C.inkFaint
        setTracked(dwellCap, "TIMER  ·  MINUTES PER SCENE", 1.0)
        glass.addSubview(dwellCap)

        pills.onSelect = { [weak self] i in self?.onDwell?(i) }
        glass.addSubview(pills)

        rule.wantsLayer = true
        rule.layer?.backgroundColor = C.hairline.cgColor
        glass.addSubview(rule)

        scroll.hasVerticalScroller = true
        scroll.drawsBackground     = false
        scroll.autohidesScrollers  = true
        scroll.documentView        = doc
        glass.addSubview(scroll)

        glass.addSubview(emptyLbl)
        glass.addSubview(hintLbl)
    }
    required init?(coder: NSCoder) { fatalError() }

    func setDwellIndex(_ i: Int) {
        guard i != pills.selectedIndex else { return }
        pills.select(i, animated: false)
    }

    func setQueue(_ scenes: [Scene], dwell: Int?) {
        rows.forEach { $0.removeFromSuperview() }
        rows.removeAll()
        for (i, sc) in scenes.enumerated() {
            let r = QueueRow(position: i, scene: sc)
            r.onPlay      = { [weak self] i in self?.onPlay?(i) }
            r.onRemove    = { [weak self] i in self?.onRemove?(i) }
            r.onDragBegin = { [weak self] row in self?.beginDrag(row) }
            r.onDragMove  = { [weak self] row, dy in self?.updateDrag(row, dy: dy) }
            r.onDragEnd   = { [weak self] row in self?.endDrag(row) }
            doc.addSubview(r)
            rows.append(r)
        }
        visualOrder = rows

        let waiting = scenes.isEmpty
            ? "The current scene keeps looping"
            : (scenes.count == 1 ? "1 scene waiting" : "\(scenes.count) scenes waiting")
        let cadence = dwell.map { " · every \($0) min" } ?? " · timer off"
        subLbl.stringValue = waiting + (scenes.isEmpty ? "" : cadence)

        emptyLbl.isHidden   = !scenes.isEmpty
        hintLbl.isHidden    = !scenes.isEmpty
        clearBtn.alphaValue = scenes.isEmpty ? 0.35 : 1
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    // MARK: Drag to reorder

    private func beginDrag(_ row: QueueRow) {
        dragging    = row
        dragOriginY = row.frame.origin.y
        doc.addSubview(row, positioned: .above, relativeTo: nil)
        row.setLifted(true)
    }

    private func updateDrag(_ row: QueueRow, dy: CGFloat) {
        guard dragging === row else { return }
        // The document view is flipped, so dragging the mouse up lowers y.
        var f = row.frame
        f.origin.y = max(0, min(CGFloat(rows.count - 1) * rowH, dragOriginY - dy))
        row.frame = f

        let target  = max(0, min(rows.count - 1, Int((f.midY / rowH).rounded(.down))))
        guard let current = visualOrder.firstIndex(where: { $0 === row }), current != target
        else { return }
        visualOrder.remove(at: current)
        visualOrder.insert(row, at: target)
        layoutRows(animated: true, skipping: row)
    }

    private func endDrag(_ row: QueueRow) {
        guard dragging === row else { return }
        dragging = nil
        row.setLifted(false)
        layoutRows(animated: true, skipping: nil)
        let permutation = visualOrder.map { $0.position }
        for (i, r) in visualOrder.enumerated() { r.setNumber(i) }
        rows = visualOrder
        onReorder?(permutation)
    }

    private func layoutRows(animated: Bool, skipping: QueueRow?) {
        let w = scroll.contentSize.width
        for (i, r) in visualOrder.enumerated() where r !== skipping {
            let f = NSRect(x: 0, y: CGFloat(i) * rowH, width: w, height: rowH)
            guard r.frame != f else { continue }
            if animated {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration       = 0.18
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    r.animator().frame = f
                }
            } else {
                r.frame = f
            }
        }
    }

    override func layout() {
        super.layout()
        glass.frame = bounds
        tint.frame  = bounds
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: 22, cornerHeight: 22,
                                   transform: nil)

        let W = bounds.width, H = bounds.height
        titleLbl.frame = NSRect(x: 20, y: H - 40, width: 190, height: 24)
        subLbl.frame   = NSRect(x: 20, y: H - 60, width: W - 40, height: 16)
        closeBtn.frame = NSRect(x: W - 42, y: H - 44, width: 30, height: 30)
        clearBtn.frame = NSRect(x: W - 78, y: H - 44, width: 30, height: 30)

        dwellCap.frame = NSRect(x: 20, y: H - 92, width: W - 40, height: 14)
        pills.frame    = NSRect(x: 20, y: H - 126, width: W - 40, height: 28)
        rule.frame     = NSRect(x: 20, y: H - 142, width: W - 40, height: 1)

        scroll.frame = NSRect(x: 8, y: 12, width: W - 16, height: max(0, H - headerH - 12))
        layoutRows(animated: false, skipping: dragging)
        doc.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width,
                           height: max(CGFloat(rows.count) * rowH, scroll.contentSize.height))

        emptyLbl.frame = NSRect(x: 20, y: H - headerH - 44, width: W - 40, height: 20)
        hintLbl.frame  = NSRect(x: 20, y: H - headerH - 66, width: W - 40, height: 18)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Library screen
// ─────────────────────────────────────────────────────────────────────────────

final class LibraryViewController: NSViewController {

    weak var app: AppDelegate?

    private let scrollView = NSScrollView()
    private let doc        = FlippedView()
    private let hero       = HeroView()
    private let sectionLbl = makeLabel("The Collection", F.display(21, .bold), C.ink)
    private let blurbLbl   = makeLabel("Click any scene to send it behind your desktop.",
                                       F.ui(13, .regular), C.inkSoft)
    private let countTag   = TagView("", fill: NSColor(hex: 0x241F19, alpha: 0.07), ink: C.inkSoft)
    private let rule       = NSView()
    private let emptyLbl   = makeLabel("", F.ui(13.5, .medium), C.inkFaint)
    let playBar            = PlayBar()
    let queuePanel         = QueuePanel()
    private(set) var queueVisible = false
    private var cards: [SceneCard] = []

    private let heroH:   CGFloat = 430
    private let barH:    CGFloat = 76
    private let barPad:  CGFloat = 20
    private let inset:   CGFloat = 44
    private let gap:     CGFloat = 20
    private let minCard: CGFloat = 268

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1120, height: 780))
        view.wantsLayer = true
        view.layer?.backgroundColor = C.paper.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground     = false
        scrollView.autohidesScrollers  = true
        scrollView.documentView        = doc
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0,
                                                bottom: barH + barPad * 2, right: 0)
        view.addSubview(scrollView)

        hero.onSet     = { [weak self] in self?.app?.playHeroScene() }
        hero.onShuffle = { [weak self] in self?.app?.shuffle() }
        hero.onClear   = { [weak self] in self?.app?.clearWallpaper() }
        hero.onQueue   = { [weak self] in self?.app?.enqueueHeroScene() }
        doc.addSubview(hero)

        doc.addSubview(sectionLbl)
        doc.addSubview(blurbLbl)
        doc.addSubview(countTag)

        rule.wantsLayer = true
        rule.layer?.backgroundColor = C.hairline.cgColor
        doc.addSubview(rule)

        for s in SceneLibrary.all {
            let c = SceneCard(scene: s)
            c.onClick = { [weak self] sc in self?.app?.selectScene(sc) }
            c.onQueue = { [weak self] sc in self?.app?.enqueue(sc) }
            doc.addSubview(c)
            cards.append(c)
        }

        emptyLbl.stringValue = "No scenes are bundled with this build. Run ./prep.sh, then ./build.sh."
        emptyLbl.isHidden = !cards.isEmpty
        doc.addSubview(emptyLbl)

        playBar.onPlayPause = { [weak self] p in self?.app?.setPaused(p); self?.refresh() }
        playBar.onVideo     = { [weak self] v in self?.app?.videoOn = v }
        playBar.onAudio     = { [weak self] a in self?.app?.audioOn = a }
        playBar.onVolume    = { [weak self] v in self?.app?.volume  = v }
        playBar.onPrev      = { [weak self] in self?.app?.step(-1) }
        playBar.onNext      = { [weak self] in self?.app?.step(+1) }
        playBar.onClear     = { [weak self] in self?.app?.clearWallpaper() }
        playBar.onQueue     = { [weak self] in self?.toggleQueue() }

        queuePanel.alphaValue = 0
        queuePanel.onPlay     = { [weak self] i in self?.app?.playFromQueue(at: i) }
        queuePanel.onRemove   = { [weak self] i in self?.app?.removeFromQueue(at: i) }
        queuePanel.onClearAll = { [weak self] in self?.app?.clearQueue() }
        queuePanel.onClose    = { [weak self] in self?.setQueueVisible(false, animated: true) }
        queuePanel.onDwell    = { [weak self] i in self?.app?.setDwellIndex(i) }
        queuePanel.onReorder  = { [weak self] p in self?.app?.reorderQueue(p) }
        view.addSubview(queuePanel)

        view.addSubview(playBar)

        refresh()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let W = view.bounds.width, H = view.bounds.height

        scrollView.frame = NSRect(x: 0, y: 0, width: W, height: H)
        playBar.frame    = NSRect(x: barPad, y: barPad, width: max(0, W - barPad * 2), height: barH)
        queuePanel.frame = queuePanelFrame(visible: queueVisible)

        hero.frame = NSRect(x: 0, y: 0, width: W, height: heroH)

        let headerY = heroH + 40
        sectionLbl.frame = NSRect(x: inset, y: headerY, width: 320, height: 26)
        let tagW = countTag.fittingWidth
        countTag.frame   = NSRect(x: W - inset - tagW, y: headerY + 4, width: tagW, height: 20)
        blurbLbl.frame   = NSRect(x: inset, y: headerY + 32, width: W - inset * 2, height: 20)
        rule.frame       = NSRect(x: inset, y: headerY + 66, width: max(0, W - inset * 2), height: 1)

        let usable = W - inset * 2
        let cols   = max(1, min(cards.isEmpty ? 1 : cards.count,
                                Int((usable + gap) / (minCard + gap))))
        let cardW  = (usable - gap * CGFloat(cols - 1)) / CGFloat(cols)
        let cardH  = (cardW * 0.62).rounded()
        let top    = headerY + 96

        for (i, c) in cards.enumerated() {
            let r = i / cols, col = i % cols
            c.frame = NSRect(x: inset + CGFloat(col) * (cardW + gap),
                             y: top + CGFloat(r) * (cardH + gap),
                             width: cardW, height: cardH)
        }

        emptyLbl.frame = NSRect(x: inset, y: top, width: usable, height: 22)

        let rows = cards.isEmpty ? 0 : Int(ceil(Double(cards.count) / Double(cols)))
        let docH = cards.isEmpty ? top + 60
                                 : top + CGFloat(rows) * (cardH + gap) + 24
        doc.frame = NSRect(x: 0, y: 0, width: W, height: max(docH, scrollView.bounds.height))
    }

    // MARK: Up Next

    private func queuePanelFrame(visible: Bool) -> NSRect {
        let W = view.bounds.width, H = view.bounds.height
        let pw: CGFloat = 360
        let bottom = barPad * 2 + barH
        return NSRect(x: visible ? W - barPad - pw : W + 16,
                      y: bottom, width: pw, height: max(0, H - bottom - barPad))
    }

    func toggleQueue() { setQueueVisible(!queueVisible, animated: true) }

    func setQueueVisible(_ visible: Bool, animated: Bool) {
        queueVisible = visible
        let target = queuePanelFrame(visible: visible)
        guard animated else {
            queuePanel.frame = target
            queuePanel.alphaValue = visible ? 1 : 0
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration       = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            queuePanel.animator().frame      = target
            queuePanel.animator().alphaValue = visible ? 1 : 0
        }
    }

    func refreshQueue() {
        queuePanel.setDwellIndex(app?.dwellIndex ?? 0)
        queuePanel.setQueue(app?.queueScenes ?? [], dwell: app?.dwellMinutes)
    }

    func refresh() {
        let cur     = app?.currentScene ?? ""
        let current = SceneLibrary.scene(cur)
        cards.forEach { $0.isSelected = ($0.scene.id == cur) }

        hero.show(scene: current ?? SceneLibrary.all.first,
                  isPlaying: current != nil,
                  count: SceneLibrary.all.count)

        let n = SceneLibrary.all.count
        countTag.setText(n == 1 ? "1 SCENE" : "\(n) SCENES")
        countTag.isHidden = n == 0
        playBar.update(scene: current, hasLibrary: SceneLibrary.all.count > 1)
        refreshQueue()
        view.needsLayout = true
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Menu bar player
// ─────────────────────────────────────────────────────────────────────────────

/// The compact player that lives in the popover under the menu bar icon.
/// Flipped so everything lays out top-down.
final class MenuBarPlayerView: NSView {

    var onPrev:       (() -> Void)?
    var onNext:       (() -> Void)?
    var onPlayPause:  (() -> Void)?
    var onVideo:      (() -> Void)?
    var onAudio:      (() -> Void)?
    var onVolume:     ((Float) -> Void)?
    var onOpen:       (() -> Void)?
    var onClear:      (() -> Void)?

    override var isFlipped: Bool { true }

    private let art      = ImageLayerView()
    private let scrim    = ScrimView()
    private let titleLbl = makeLabel("Nothing playing", F.display(18, .bold), .white)
    private let subLbl   = makeLabel("Pick a scene in Glasswood",
                                     F.ui(11.5, .medium), NSColor.white.withAlphaComponent(0.85))
    private let prevBtn  = IconButton(on: "backward.end.fill")
    private let playBtn  = IconButton(on: "pause.fill", off: "play.fill", prominent: true)
    private let nextBtn  = IconButton(on: "forward.end.fill")
    private let videoBtn = IconButton(on: "photo.fill", off: "photo")
    private let audioBtn = IconButton(on: "speaker.wave.2.fill", off: "speaker.slash.fill")
    private let slider   = NSSlider()
    private let rule     = NSView()
    private let upLbl    = NSTextField(labelWithString: "")
    private var upRows: [NSTextField] = []
    private let openBtn  = PillButton(title: "Open Glasswood", systemImage: "macwindow", kind: .ink)
    private let clearBtn = PillButton(title: "Clear", systemImage: "xmark", kind: .quiet)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = C.paper.cgColor

        art.placeholderColor = NSColor(hex: 0x2A2118)
        addSubview(art)
        scrim.edge = .bottom
        scrim.strength = 0.88
        addSubview(scrim)

        titleLbl.shadow = textShadow(0.5, 8)
        subLbl.shadow   = textShadow(0.45, 6)
        addSubview(titleLbl)
        addSubview(subLbl)

        prevBtn.onClick  = { [weak self] in self?.onPrev?() }
        nextBtn.onClick  = { [weak self] in self?.onNext?() }
        playBtn.onClick  = { [weak self] in self?.onPlayPause?() }
        videoBtn.onClick = { [weak self] in self?.onVideo?() }
        audioBtn.onClick = { [weak self] in self?.onAudio?() }
        [prevBtn, playBtn, nextBtn, videoBtn, audioBtn].forEach { addSubview($0) }

        prevBtn.toolTipText  = "Previous scene"
        nextBtn.toolTipText  = "Next scene"
        videoBtn.toolTipText = "Show or hide the video layer"
        audioBtn.toolTipText = "Mute or unmute"

        slider.minValue    = 0
        slider.maxValue    = 1
        slider.floatValue  = 0.7
        slider.controlSize = .small
        slider.trackFillColor = C.moss
        slider.target = self
        slider.action = #selector(volumeChanged)
        addSubview(slider)

        rule.wantsLayer = true
        rule.layer?.backgroundColor = C.hairline.cgColor
        addSubview(rule)

        upLbl.font      = F.ui(9.5, .heavy)
        upLbl.textColor = C.inkFaint
        setTracked(upLbl, "UP NEXT", 1.0)
        addSubview(upLbl)

        for _ in 0..<3 {
            let l = makeLabel("", F.ui(12, .medium), C.inkSoft)
            addSubview(l)
            upRows.append(l)
        }

        openBtn.onClick  = { [weak self] in self?.onOpen?() }
        clearBtn.onClick = { [weak self] in self?.onClear?() }
        addSubview(openBtn)
        addSubview(clearBtn)
    }
    required init?(coder: NSCoder) { fatalError() }

    private var shownID: String?

    func render(scene: Scene?, isPaused: Bool, videoOn: Bool, audioOn: Bool,
                volume: Float, queue: [Scene], hasLibrary: Bool) {
        let animated = shownID != nil && shownID != scene?.id
        shownID = scene?.id
        art.setImage(scene?.thumbImage, animated: animated)

        titleLbl.stringValue = scene?.title ?? "Nothing playing"
        subLbl.stringValue   = scene == nil
            ? "Pick a scene in Glasswood"
            : (isPaused ? "Paused" : "Looping on every display")

        let live = scene != nil
        playBtn.isOn        = live && !isPaused
        videoBtn.isOn       = videoOn
        audioBtn.isOn       = audioOn
        slider.floatValue   = volume
        slider.isEnabled    = live
        [playBtn, videoBtn, audioBtn].forEach { $0.alphaValue = live ? 1 : 0.4 }
        [prevBtn, nextBtn].forEach { $0.alphaValue = hasLibrary ? 1 : 0.4 }
        clearBtn.isHidden = !live

        for (i, row) in upRows.enumerated() {
            if i < queue.count {
                row.stringValue = String(format: "%02d   ", i + 1) + queue[i].title
                row.textColor   = C.inkSoft
            } else if i == 0 {
                row.stringValue = "Nothing lined up"
                row.textColor   = C.inkFaint
            } else {
                row.stringValue = ""
            }
        }
        if queue.count > 3 {
            upRows[2].stringValue = "and \(queue.count - 2) more"
            upRows[2].textColor   = C.inkFaint
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let W = bounds.width

        art.frame   = NSRect(x: 0, y: 0, width: W, height: 170)
        scrim.frame = NSRect(x: 0, y: 80, width: W, height: 90)
        titleLbl.frame = NSRect(x: 18, y: 112, width: W - 36, height: 24)
        subLbl.frame   = NSRect(x: 18, y: 140, width: W - 36, height: 16)

        let cluster: CGFloat = 34 + 14 + 44 + 14 + 34
        var x = (W - cluster) / 2
        prevBtn.frame = NSRect(x: x, y: 191, width: 34, height: 34); x += 34 + 14
        playBtn.frame = NSRect(x: x, y: 186, width: 44, height: 44); x += 44 + 14
        nextBtn.frame = NSRect(x: x, y: 191, width: 34, height: 34)

        audioBtn.frame = NSRect(x: 20, y: 246, width: 30, height: 30)
        slider.frame   = NSRect(x: 58, y: 252, width: W - 58 - 68, height: 20)
        videoBtn.frame = NSRect(x: W - 50, y: 246, width: 30, height: 30)

        rule.frame  = NSRect(x: 20, y: 294, width: W - 40, height: 1)
        upLbl.frame = NSRect(x: 20, y: 308, width: W - 40, height: 14)
        for (i, row) in upRows.enumerated() {
            row.frame = NSRect(x: 20, y: 330 + CGFloat(i) * 22, width: W - 40, height: 18)
        }

        openBtn.frame  = NSRect(x: 20, y: 406, width: openBtn.fittingWidth, height: 34)
        clearBtn.frame = NSRect(x: W - 20 - clearBtn.fittingWidth, y: 406,
                                width: clearBtn.fittingWidth, height: 34)
    }

    @objc private func volumeChanged() { onVolume?(slider.floatValue) }
}

/// Owns the status item and the popover it opens.
final class MenuBarPlayer {

    let content = MenuBarPlayerView(frame: NSRect(x: 0, y: 0, width: 320, height: 452))

    private let statusItem: NSStatusItem
    private let popover = NSPopover()

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let holder = NSViewController()
        holder.view = content
        popover.contentViewController = holder
        popover.contentSize = NSSize(width: 320, height: 452)
        popover.behavior    = .transient
        popover.animates    = true

        if let b = statusItem.button {
            b.image = symbol("flame", 15, .medium)
            b.image?.isTemplate = true
            b.toolTip = "Glasswood"
            b.target  = self
            b.action  = #selector(toggle(_:))
        }
    }

    func setPlaying(_ playing: Bool) {
        statusItem.button?.image = symbol(playing ? "flame.fill" : "flame", 15, .medium)
        statusItem.button?.image?.isTemplate = true
    }

    func close() { if popover.isShown { popover.performClose(nil) } }

    @objc private func toggle(_ sender: Any?) {
        guard let b = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - App delegate
// ─────────────────────────────────────────────────────────────────────────────

private enum Key {
    static let scene  = "gw.scene"
    static let volume = "gw.volume"
    static let video  = "gw.video"
    static let audio  = "gw.audio"
    static let queue  = "gw.queue"
    static let dwell  = "gw.dwell"
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    var videoOn = true {
        didSet { walls.forEach { $0.setVideoEnabled(videoOn) }
                 UserDefaults.standard.set(videoOn, forKey: Key.video) }
    }
    var audioOn = true {
        didSet { walls.forEach { $0.setAudioEnabled(audioOn) }
                 UserDefaults.standard.set(audioOn, forKey: Key.audio) }
    }
    var volume: Float = 0.7 {
        didSet { walls.forEach { $0.setVolume(volume) }
                 UserDefaults.standard.set(volume, forKey: Key.volume) }
    }
    private(set) var currentScene = ""
    private(set) var isPaused     = false

    /// Scene ids waiting to play, in order. Empty means the current clip loops.
    private(set) var queue: [String] = []
    var queueScenes: [Scene] { queue.compactMap { SceneLibrary.scene($0) } }

    /// How long a scene holds before the queue advances. nil = one full clip.
    private(set) var dwellMinutes: Int?
    private var dwellTimer: Timer?
    var dwellIndex: Int {
        QueuePanel.dwellMinutes.firstIndex(where: { $0 == dwellMinutes }) ?? 0
    }

    private var window: NSWindow!
    private var vc: LibraryViewController!
    private var walls: [WallpaperWindow] = []
    private var menuBar: MenuBarPlayer?
    private var dwellMenuItems: [NSMenuItem] = []

    // MARK: Launch

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSWindow.allowsAutomaticWindowTabbing = false
        buildMenu()

        let d = UserDefaults.standard
        if d.object(forKey: Key.volume) != nil { volume  = d.float(forKey: Key.volume) }
        if d.object(forKey: Key.video)  != nil { videoOn = d.bool(forKey: Key.video) }
        if d.object(forKey: Key.audio)  != nil { audioOn = d.bool(forKey: Key.audio) }

        vc = LibraryViewController()
        vc.app = self

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 780),
                          styleMask: [.titled, .closable, .miniaturizable,
                                      .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title                       = "Glasswood"
        window.titlebarAppearsTransparent  = true
        window.titleVisibility             = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor             = C.paper
        window.appearance                  = NSAppearance(named: .aqua)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.minSize                     = NSSize(width: 860, height: 620)
        window.contentViewController       = vc
        window.isReleasedWhenClosed        = false
        window.delegate                    = self
        window.setFrameAutosaveName("GlasswoodMainWindow")
        if window.frame.width < 860 { window.setContentSize(NSSize(width: 1120, height: 780)) }
        window.center()
        window.makeKeyAndOrderFront(nil)

        vc.playBar.setVideo(videoOn)
        vc.playBar.setAudio(audioOn)
        vc.playBar.setVolume(volume)

        queue = (d.stringArray(forKey: Key.queue) ?? []).filter { SceneLibrary.scene($0) != nil }
        if d.object(forKey: Key.dwell) != nil {
            let m = d.integer(forKey: Key.dwell)
            dwellMinutes = QueuePanel.dwellMinutes.contains(m) ? m : nil
        }
        updateDwellMenu()

        let bar = MenuBarPlayer()
        bar.content.onPrev      = { [weak self] in self?.step(-1) }
        bar.content.onNext      = { [weak self] in self?.step(+1) }
        bar.content.onPlayPause = { [weak self] in self?.vc?.playBar.togglePlay() }
        bar.content.onVideo     = { [weak self] in self?.vc?.playBar.toggleVideo() }
        bar.content.onAudio     = { [weak self] in self?.vc?.playBar.toggleAudio() }
        bar.content.onVolume    = { [weak self] v in
            guard let self = self else { return }
            self.volume = v
            self.vc?.playBar.setVolume(v)
        }
        bar.content.onOpen      = { [weak self, weak bar] in
            bar?.close()
            self?.showMainWindow(nil)
        }
        bar.content.onClear     = { [weak self] in self?.clearWallpaper() }
        menuBar = bar

        // Pick up where the last session left off.
        if let last = SceneLibrary.scene(d.string(forKey: Key.scene) ?? "") {
            selectScene(last)
        } else {
            syncUI()
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged(_:)),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows f: Bool) -> Bool {
        if !f { showMainWindow(nil) }
        return true
    }

    // MARK: Playback

    /// Push the current state out to the window, the queue panel and the menu bar.
    private func syncUI() {
        vc?.refresh()
        menuBar?.setPlaying(!currentScene.isEmpty && !isPaused)
        menuBar?.content.render(scene: SceneLibrary.scene(currentScene),
                                isPaused: isPaused,
                                videoOn: videoOn,
                                audioOn: audioOn,
                                volume: volume,
                                queue: queueScenes,
                                hasLibrary: SceneLibrary.all.count > 1)
    }

    // MARK: Up Next

    private func persistQueue() { UserDefaults.standard.set(queue, forKey: Key.queue) }

    func enqueue(_ scene: Scene) {
        queue.append(scene.id)
        persistQueue()
        syncUI()
    }

    func enqueueHeroScene() {
        if let s = SceneLibrary.scene(currentScene) ?? SceneLibrary.all.first { enqueue(s) }
    }

    func removeFromQueue(at i: Int) {
        guard queue.indices.contains(i) else { return }
        queue.remove(at: i)
        persistQueue()
        syncUI()
    }

    func setDwellIndex(_ i: Int) {
        guard QueuePanel.dwellMinutes.indices.contains(i) else { return }
        dwellMinutes = QueuePanel.dwellMinutes[i]
        if let m = dwellMinutes { UserDefaults.standard.set(m, forKey: Key.dwell) }
        else { UserDefaults.standard.removeObject(forKey: Key.dwell) }
        restartDwellTimer()
        updateDwellMenu()
        syncUI()
    }

    /// Measures the hold from the moment the current scene started.
    private func restartDwellTimer() {
        dwellTimer?.invalidate()
        dwellTimer = nil
        guard let minutes = dwellMinutes, !currentScene.isEmpty else { return }
        dwellTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes) * 60,
                                          repeats: false) { [weak self] _ in
            self?.advanceFromQueue()
        }
    }

    func reorderQueue(_ permutation: [Int]) {
        let old = queue
        guard permutation.count == old.count,
              Set(permutation) == Set(old.indices) else { return }
        queue = permutation.map { old[$0] }
        persistQueue()
        syncUI()
    }

    func clearQueue() {
        queue.removeAll()
        persistQueue()
        syncUI()
    }

    /// Jump straight to a queued scene, dropping whatever sat in front of it.
    func playFromQueue(at i: Int) {
        guard queue.indices.contains(i), let s = SceneLibrary.scene(queue[i]) else { return }
        queue.removeFirst(i + 1)
        persistQueue()
        selectScene(s)
    }

    /// Called when a clip reaches its end on the primary display.
    private func advanceFromQueue() {
        guard !queue.isEmpty else {
            // Nothing queued: the scene keeps looping. Re-arm so that adding
            // something later still advances on schedule.
            restartDwellTimer()
            return
        }
        let next = queue.removeFirst()
        persistQueue()
        if let s = SceneLibrary.scene(next) { selectScene(s) }
        else { advanceFromQueue() }
    }

    func selectScene(_ scene: Scene) {
        guard let url = scene.videoURL else { return }
        currentScene = scene.id
        UserDefaults.standard.set(scene.id, forKey: Key.scene)

        // Reuse the existing windows: each one dissolves from the outgoing
        // scene into the new one. Only the first scene of a session comes up
        // out of black.
        ensureWalls()
        walls.forEach { $0.play(url: url) }
        restartDwellTimer()
        syncUI()
    }

    /// One wallpaper window per screen, rebuilt only when the displays change.
    private func ensureWalls() {
        guard walls.count != NSScreen.screens.count else { return }
        walls.forEach { $0.orderOut(nil) }
        walls.removeAll()
        for screen in NSScreen.screens {
            let w = WallpaperWindow(screen: screen)
            w.setVideoEnabled(videoOn)
            w.setAudioEnabled(audioOn)
            w.setVolume(volume)
            w.orderBack(nil)
            walls.append(w)
        }
    }

    @objc private func screensChanged(_ n: Notification) {
        guard let scene = SceneLibrary.scene(currentScene) else { return }
        walls.forEach { $0.orderOut(nil) }
        walls.removeAll()
        selectScene(scene)
    }

    func playHeroScene() {
        if let s = SceneLibrary.scene(currentScene) ?? SceneLibrary.all.first { selectScene(s) }
    }

    func step(_ delta: Int) {
        guard !SceneLibrary.all.isEmpty else { return }
        let n = SceneLibrary.all.count
        let i = SceneLibrary.index(of: currentScene) ?? -1
        let next = ((i + delta) % n + n) % n
        selectScene(SceneLibrary.all[next])
    }

    func shuffle() {
        guard SceneLibrary.all.count > 1 else { return }
        var pick = currentScene
        while pick == currentScene, let s = SceneLibrary.all.randomElement() { pick = s.id }
        if let s = SceneLibrary.scene(pick) { selectScene(s) }
    }

    func setPaused(_ p: Bool) {
        isPaused = p
        walls.forEach { $0.setPaused(p) }
        syncUI()
    }

    // MARK: Menu actions

    @objc func showMainWindow(_ sender: Any?) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func menuPlayPause(_ sender: Any?) { vc?.playBar.togglePlay() }
    @objc func menuNext(_ sender: Any?)      { step(+1) }
    @objc func menuPrev(_ sender: Any?)      { step(-1) }
    @objc func menuShuffle(_ sender: Any?)   { shuffle() }
    @objc func menuToggleVideo(_ sender: Any?) { vc?.playBar.toggleVideo() }
    @objc func menuToggleAudio(_ sender: Any?) { vc?.playBar.toggleAudio() }
    @objc func menuVolumeUp(_ sender: Any?)   { volume = min(1, volume + 0.1); vc?.playBar.setVolume(volume) }
    @objc func menuVolumeDown(_ sender: Any?) { volume = max(0, volume - 0.1); vc?.playBar.setVolume(volume) }

    /// Fades the wallpaper away and hands the desktop back.
    func clearWallpaper() {
        let leaving = walls
        walls.removeAll()
        leaving.forEach { w in w.fadeOut { w.orderOut(nil) } }
        currentScene = ""
        dwellTimer?.invalidate()
        dwellTimer = nil
        UserDefaults.standard.removeObject(forKey: Key.scene)
        syncUI()
    }

    @objc func menuStop(_ sender: Any?)        { clearWallpaper() }
    @objc func menuEnqueue(_ sender: Any?)     { enqueueHeroScene() }
    @objc func menuToggleQueue(_ sender: Any?) { showMainWindow(nil); vc?.toggleQueue() }
    @objc func menuClearQueue(_ sender: Any?)  { clearQueue() }
    @objc func menuSetDwell(_ sender: Any?) {
        guard let mi = sender as? NSMenuItem else { return }
        setDwellIndex(mi.tag)
    }

    private func updateDwellMenu() {
        for (i, mi) in dwellMenuItems.enumerated() {
            mi.state = (i == dwellIndex) ? .on : .off
        }
    }

    @objc func menuAbout(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Glasswood",
            .credits: NSAttributedString(
                string: "Living wallpaper for quiet desktops.\n\(SceneLibrary.all.count) scenes, looping on every display.",
                attributes: [.font: F.ui(11.5), .foregroundColor: NSColor.secondaryLabelColor])
        ])
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Menu bar

    private func item(_ title: String, _ action: Selector?, _ key: String = "",
                      _ mods: NSEvent.ModifierFlags? = nil, target: AnyObject? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        if let m = mods { i.keyEquivalentModifierMask = m }
        if let t = target { i.target = t }
        return i
    }

    private func buildMenu() {
        let main = NSMenu()

        // App
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(title: "Glasswood"); appItem.submenu = appMenu
        appMenu.addItem(item("About Glasswood", #selector(menuAbout(_:)), "", nil, target: self))
        appMenu.addItem(.separator())
        let services = NSMenu(title: "Services")
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        servicesItem.submenu = services
        appMenu.addItem(servicesItem)
        NSApp.servicesMenu = services
        appMenu.addItem(.separator())
        appMenu.addItem(item("Hide Glasswood", #selector(NSApplication.hide(_:)), "h"))
        appMenu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)),
                             "h", [.command, .option]))
        appMenu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Quit Glasswood", #selector(NSApplication.terminate(_:)), "q"))

        // Edit
        let editItem = NSMenuItem(); main.addItem(editItem)
        let editMenu = NSMenu(title: "Edit"); editItem.submenu = editMenu
        editMenu.addItem(item("Undo", Selector(("undo:")), "z"))
        editMenu.addItem(item("Redo", Selector(("redo:")), "z", [.command, .shift]))
        editMenu.addItem(.separator())
        editMenu.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        editMenu.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        editMenu.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        editMenu.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))

        // Scene
        let sceneItem = NSMenuItem(); main.addItem(sceneItem)
        let sceneMenu = NSMenu(title: "Scene"); sceneItem.submenu = sceneMenu
        sceneMenu.addItem(item("Play / Pause", #selector(menuPlayPause(_:)), " ", [], target: self))
        sceneMenu.addItem(.separator())
        sceneMenu.addItem(item("Next Scene", #selector(menuNext(_:)), "\u{2192}", [.command], target: self))
        sceneMenu.addItem(item("Previous Scene", #selector(menuPrev(_:)), "\u{2190}", [.command], target: self))
        sceneMenu.addItem(item("Shuffle", #selector(menuShuffle(_:)), "r", [.command], target: self))
        sceneMenu.addItem(.separator())
        sceneMenu.addItem(item("Add to Up Next", #selector(menuEnqueue(_:)), "d", [.command], target: self))
        sceneMenu.addItem(item("Show Up Next", #selector(menuToggleQueue(_:)), "u", [.command], target: self))
        sceneMenu.addItem(item("Clear Up Next", #selector(menuClearQueue(_:)), "", nil, target: self))

        let dwellItem = NSMenuItem(title: "Stay on Each Scene", action: nil, keyEquivalent: "")
        let dwellMenu = NSMenu(title: "Stay on Each Scene")
        dwellMenuItems = []
        for (i, m) in QueuePanel.dwellMinutes.enumerated() {
            let t = m.map { "\($0) minutes" } ?? "Timer off"
            let mi = item(t, #selector(menuSetDwell(_:)), "", nil, target: self)
            mi.tag = i
            dwellMenu.addItem(mi)
            dwellMenuItems.append(mi)
        }
        dwellItem.submenu = dwellMenu
        sceneMenu.addItem(dwellItem)
        updateDwellMenu()
        sceneMenu.addItem(.separator())
        sceneMenu.addItem(item("Toggle Video Layer", #selector(menuToggleVideo(_:)), "v",
                               [.command, .shift], target: self))
        sceneMenu.addItem(item("Mute / Unmute", #selector(menuToggleAudio(_:)), "m",
                               [.command, .shift], target: self))
        sceneMenu.addItem(item("Volume Up", #selector(menuVolumeUp(_:)), "\u{2191}", [.command], target: self))
        sceneMenu.addItem(item("Volume Down", #selector(menuVolumeDown(_:)), "\u{2193}", [.command], target: self))
        sceneMenu.addItem(.separator())
        sceneMenu.addItem(item("Clear Wallpaper", #selector(menuStop(_:)), "", nil, target: self))

        // View
        let viewItem = NSMenuItem(); main.addItem(viewItem)
        let viewMenu = NSMenu(title: "View"); viewItem.submenu = viewMenu
        viewMenu.addItem(item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)),
                              "f", [.control, .command]))

        // Window
        let winItem = NSMenuItem(); main.addItem(winItem)
        let winMenu = NSMenu(title: "Window"); winItem.submenu = winMenu
        winMenu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        winMenu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        winMenu.addItem(item("Close", #selector(NSWindow.performClose(_:)), "w"))
        winMenu.addItem(.separator())
        winMenu.addItem(item("Glasswood Library", #selector(showMainWindow(_:)), "0",
                             [.command], target: self))
        winMenu.addItem(.separator())
        winMenu.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        NSApp.windowsMenu = winMenu

        NSApp.mainMenu = main
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Entry point
// ─────────────────────────────────────────────────────────────────────────────

let app      = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
