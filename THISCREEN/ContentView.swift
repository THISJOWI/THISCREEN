import SwiftUI
import UniformTypeIdentifiers
import AVKit

enum DrawingTool: String, CaseIterable {
    case select = "cursorarrow"
    case pen = "scribble"
    case arrow = "arrow.up.right"
    case rectangle = "square"
    case oval = "circle"
    case pixelate = "square.grid.3x3.fill"
    case text = "textformat"
    case crop = "crop"

    var displayName: String {
        switch self {
        case .select: return "Seleccionar"
        case .pen: return "Lápiz"
        case .arrow: return "Flecha"
        case .rectangle: return "Rectángulo"
        case .oval: return "Óvalo"
        case .pixelate: return "Pixelar"
        case .text: return "Texto"
        case .crop: return "Recortar"
        }
    }

    var shortcutKey: String {
        switch self {
        case .select: return "V"
        case .pen: return "P"
        case .arrow: return "A"
        case .rectangle: return "R"
        case .oval: return "O"
        case .pixelate: return "X"
        case .text: return "T"
        case .crop: return "K"
        }
    }
}

struct DrawnElement: Identifiable, Equatable {
    let id: UUID
    var tool: DrawingTool
    var color: Color
    var lineWidth: CGFloat
    var points: [CGPoint]
    var startPoint: CGPoint?
    var endPoint: CGPoint?
    var text: String = ""
    
    init(id: UUID = UUID(), tool: DrawingTool, color: Color, lineWidth: CGFloat, points: [CGPoint] = [], startPoint: CGPoint? = nil, endPoint: CGPoint? = nil, text: String = "") {
        self.id = id; self.tool = tool; self.color = color; self.lineWidth = lineWidth
        self.points = points; self.startPoint = startPoint; self.endPoint = endPoint; self.text = text
    }

    mutating func translate(by translation: CGSize) {
        if let start = startPoint { startPoint = CGPoint(x: start.x + translation.width, y: start.y + translation.height) }
        if let end = endPoint { endPoint = CGPoint(x: end.x + translation.width, y: end.y + translation.height) }
        points = points.map { CGPoint(x: $0.x + translation.width, y: $0.y + translation.height) }
    }
}

struct InteractiveDrawingView: View {
    @Binding var elements: [DrawnElement]
    @Binding var currentTool: DrawingTool
    @Binding var currentColor: Color
    @Binding var currentLineWidth: CGFloat
    @Binding var cropRect: CGRect?
    var pixelatedNSImage: NSImage? = nil
    
    @State private var currentElement: DrawnElement?
    @State private var selectedElementID: UUID?
    @State private var dragStartPoint: CGPoint?
    @State private var textInputLocation: CGPoint? = nil
    @State private var textInputBuffer: String = ""
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        ZStack {
            Canvas { context, size in
                 let resolvedPixelated: GraphicsContext.ResolvedImage? = pixelatedNSImage.map { context.resolve(Image(nsImage: $0)) }
                 for element in elements {
                     var ctx = context
                     if element.id == selectedElementID { ctx.addFilter(.shadow(color: .blue.opacity(0.8), radius: 8)) }
                     drawElement(context: ctx, element: element, size: size, resolvedPixelated: resolvedPixelated)
                 }
                 if let currentElement = currentElement {
                     drawElement(context: context, element: currentElement, size: size, resolvedPixelated: resolvedPixelated)
                 }
                 if let crop = cropRect, (currentTool == .crop) {
                     context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.4)))
                     context.blendMode = .destinationOut
                     context.fill(Path(crop), with: .color(.black))
                     context.blendMode = .normal
                     context.stroke(Path(crop), with: .color(.white), lineWidth: 1.5)
                 }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if currentTool == .text { return }
                        if currentTool == .select {
                            if dragStartPoint == nil { findElementAt(value.startLocation) }
                            if let selectedID = selectedElementID, let index = elements.firstIndex(where: { $0.id == selectedID }) {
                                let translation = CGSize(width: value.translation.width - (dragStartPoint?.x ?? 0), height: value.translation.height - (dragStartPoint?.y ?? 0))
                                elements[index].translate(by: translation)
                                dragStartPoint = CGPoint(x: value.translation.width, y: value.translation.height)
                            }
                            return
                        }
                        if currentTool == .crop {
                            let start = value.startLocation
                            let end = value.location
                            cropRect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(start.x - end.x), height: abs(start.y - end.y))
                            return
                        }
                        if currentElement == nil {
                            currentElement = DrawnElement(tool: currentTool, color: currentColor, lineWidth: currentLineWidth, points: [value.location], startPoint: value.location, endPoint: value.location)
                        } else {
                            if currentTool == .pen || currentTool == .pixelate { currentElement?.points.append(value.location) }
                            else { currentElement?.endPoint = value.location }
                        }
                    }
                    .onEnded { value in
                        if currentTool == .select { dragStartPoint = nil; return }
                        if currentTool == .text { 
                            textInputLocation = value.location
                            textInputBuffer = ""
                            return 
                        }
                        if currentTool == .crop { return }
                        if let newElement = currentElement { withAnimation { elements.append(newElement) } }
                        currentElement = nil
                    }
            )
            
            if let location = textInputLocation {
                TextField("...", text: $textInputBuffer, onCommit: {
                    if !textInputBuffer.isEmpty { 
                        elements.append(DrawnElement(tool: .text, color: currentColor, lineWidth: max(currentLineWidth * 3, 20), startPoint: location, text: textInputBuffer)) 
                    }
                    textInputLocation = nil; textInputBuffer = ""; isTextFieldFocused = false
                })
                .focused($isTextFieldFocused)
                .textFieldStyle(.plain)
                .font(.system(size: max(currentLineWidth * 3, 20), weight: .bold))
                .foregroundColor(currentColor)
                .padding(8)
                .background(.ultraThinMaterial.opacity(0.8))
                .cornerRadius(8)
                .frame(width: 400)
                .position(location)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isTextFieldFocused = true
                    }
                }
            }
        }
        .background(
            Group {
                Button("") { deleteSelectedElement() }.keyboardShortcut(.delete, modifiers: [])
                Button("") { deleteSelectedElement() }.keyboardShortcut("x", modifiers: [.command])
                Button("") { deleteSelectedElement() }.keyboardShortcut(.init("\u{7F}"), modifiers: []) 
            }
            .opacity(0)
        )
    }
    
    private func deleteSelectedElement() {
        if let selectedID = selectedElementID { withAnimation { elements.removeAll(where: { $0.id == selectedID }); selectedElementID = nil } }
    }
    
    private func findElementAt(_ point: CGPoint) {
        for element in elements.reversed() {
            let start = element.startPoint ?? .zero; let end = element.endPoint ?? .zero
            let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: max(abs(start.x - end.x), 20), height: max(abs(start.y - end.y), 20))
            if element.tool == .pen || element.tool == .pixelate {
                for p in element.points { if hypot(p.x - point.x, p.y - point.y) < 20 { selectedElementID = element.id; return } }
            } else if rect.insetBy(dx: -20, dy: -20).contains(point) { selectedElementID = element.id; return }
        }
        selectedElementID = nil
    }

    func drawElement(context: GraphicsContext, element: DrawnElement, size: CGSize, resolvedPixelated: GraphicsContext.ResolvedImage?) {
        var localContext = context; let start = element.startPoint ?? .zero; let end = element.endPoint ?? .zero
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(start.x - end.x), height: abs(start.y - end.y))
        var path = Path()
        switch element.tool {
        case .pen, .pixelate:
            guard let first = element.points.first else { return }
            path.move(to: first); for p in element.points.dropFirst() { path.addLine(to: p) }
        case .rectangle: path.addRect(rect)
        case .oval: path.addEllipse(in: rect)
        case .arrow:
            path.move(to: start); path.addLine(to: end)
            let angle = atan2(end.y - start.y, end.x - start.x); let len: CGFloat = 20 + element.lineWidth * 2
            let p1 = CGPoint(x: end.x - len * cos(angle - .pi/6), y: end.y - len * sin(angle - .pi/6))
            let p2 = CGPoint(x: end.x - len * cos(angle + .pi/6), y: end.y - len * sin(angle + .pi/6))
            var head = Path(); head.move(to: end); head.addLine(to: p1); head.move(to: end); head.addLine(to: p2)
            localContext.stroke(head, with: .color(element.color), style: StrokeStyle(lineWidth: element.lineWidth, lineCap: .round, lineJoin: .round))
        case .text:
            localContext.draw(Text(element.text).font(.system(size: element.lineWidth, weight: .bold)).foregroundColor(element.color), at: start)
            return
        default: break
        }
        if element.tool == .pixelate {
            if let pix = resolvedPixelated {
                let mask = path.strokedPath(StrokeStyle(lineWidth: element.lineWidth * 4, lineCap: .round, lineJoin: .round))
                localContext.clip(to: mask); localContext.draw(pix, in: CGRect(origin: .zero, size: size)); return
            }
        }
        localContext.stroke(path, with: .color(element.color), style: StrokeStyle(lineWidth: element.lineWidth, lineCap: .round, lineJoin: .round))
    }
}

// MARK: - Custom Tooltip

struct ToolTooltip: View {
    let name: String
    let shortcut: String

    var body: some View {
        HStack(spacing: 6) {
            Text(name)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white)

            Text(shortcut)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(.white.opacity(0.2), lineWidth: 0.5)
                        )
                )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.5))
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white.opacity(0.12), lineWidth: 0.5)
            }
        )
        .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
    }
}

// MARK: - Tool Button

struct ToolButton: View {
    let tool: DrawingTool
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false
    let onHoverChange: (Bool) -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: tool.rawValue)
                .font(.system(size: 18))
                .foregroundColor(isSelected ? .white : .primary)
                .frame(width: 44, height: 44)
                .background(ZStack {
                    if isSelected {
                        Circle().fill(Color.accentColor)
                            .shadow(color: Color.accentColor.opacity(0.4), radius: 8, y: 4)
                    } else {
                        Circle().fill(isHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.05))
                    }
                })
                .overlay(Circle().stroke(Color.white.opacity(isHovered ? 0.25 : 0.1), lineWidth: 0.5))
                .scaleEffect(isHovered ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
        .animation(.easeOut(duration: 0.1), value: isHovered)
        .onHover { hovering in 
            isHovered = hovering 
            onHoverChange(hovering)
        }
    }
}

struct AppState: Equatable {
    var screenshot: NSImage?
    var elements: [DrawnElement]
}

struct ContentView: View {
    @EnvironmentObject var captureManager: CaptureManager
    
    @State private var elements: [DrawnElement] = []
    @State private var redoStack: [DrawnElement] = []
    @State private var historyStack: [AppState] = [] 
    @State private var currentTool: DrawingTool = .arrow
    @State private var currentColor: Color = .red
    @State private var currentLineWidth: CGFloat = 8.0
    @State private var zoomScale: CGFloat = 1.0
    @State private var baseZoomScale: CGFloat = 1.0
    @State private var pixelatedImage: NSImage? = nil 
    @State private var cropRect: CGRect? = nil
    
    // UI Local States
    @State private var includeMic: Bool = false
    @State private var showClicks: Bool = true
    @State private var player: AVPlayer? = nil
    @State private var ignoreChanges: Bool = false
    @State private var hoveredTool: DrawingTool? = nil
    @State private var showRecordingTooltip: Bool = false
    @State private var showSaveTooltip: Bool = false
    @State private var showCaptureTooltip: Bool = false
    
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            
            if let url = captureManager.lastVideoUrl {
                VStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(.black).overlay(
                            VideoPlayer(player: player)
                                .onAppear {
                                    player = AVPlayer(url: url)
                                    player?.play()
                                }
                        ).clipShape(RoundedRectangle(cornerRadius: 12)).padding(20)
                    }
                    
                    HStack(spacing: 20) {
                        Menu {
                            Button("Save to Desktop (Cmd+D)") { saveToSuggested(directory: .desktopDirectory) }
                            Button("Save to Downloads (Cmd+L)") { saveToSuggested(directory: .downloadsDirectory) }
                            Button("Save to Documents") { saveVideoTo(directory: .documentDirectory) }
                            Button("Save to Movies") { saveVideoTo(directory: .moviesDirectory) }
                            Divider()
                            Button("Custom Location... (Cmd+S)") { saveVideoWithDialog() }
                        } label: {
                            Label("Save Video...", systemImage: "arrow.down.doc.fill").padding()
                        }.buttonStyle(.borderedProminent)
                        .help("Choose where to save the recording")

                        Button(action: { captureManager.lastVideoUrl = nil }) {
                            Label("Discard", systemImage: "trash").foregroundColor(.red).padding()
                        }.buttonStyle(.bordered)
                    }.padding(.bottom, 24)
                }
            }
            else if let img = captureManager.screenshot {
                GeometryReader { geo in
                    let scale = min(geo.size.width / (img.size.width + 40), geo.size.height / (img.size.height + 150)) * zoomScale
                    ZStack {
                        Image(nsImage: img)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                        InteractiveDrawingView(elements: $elements, currentTool: $currentTool, currentColor: $currentColor, currentLineWidth: $currentLineWidth, cropRect: $cropRect, pixelatedNSImage: pixelatedImage)
                    }
                    .frame(width: img.size.width, height: img.size.height)
                    .scaleEffect(scale)
                    .position(x: geo.size.width / 2, y: (geo.size.height - 100) / 2)
                    .gesture(MagnificationGesture()
                        .onChanged { value in
                            let newScale = baseZoomScale * value
                            zoomScale = max(0.25, min(5.0, newScale))
                        }
                        .onEnded { _ in baseZoomScale = zoomScale })
                    
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                VStack {
                    Spacer()
                    VStack(spacing: 8) {
                        if currentTool == .crop || captureManager.isRecording {
                            HStack(spacing: 12) {
                                Toggle(isOn: $includeMic) { Label("Mic", systemImage: includeMic ? "mic.fill" : "mic.slash.fill") }.toggleStyle(.button).clipShape(Capsule())
                                Toggle(isOn: $showClicks) { Label("Clicks", systemImage: showClicks ? "cursorarrow.click.2" : "cursorarrow") }.toggleStyle(.button).clipShape(Capsule())
                                Divider().frame(height: 16)
                                Text(captureManager.isRecording ? "🔴 RECORDING..." : "Drag to select area and apply").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(captureManager.isRecording ? .red : .secondary)
                            }.padding(.top, 8).transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        HStack {
                            Image(systemName: "magnifyingglass"); Slider(value: $zoomScale, in: 0.25...5.0).frame(width: 80)
                            Divider().frame(height: 16).padding(.horizontal, 4)
                            Image(systemName: "line.diagonal"); Slider(value: $currentLineWidth, in: 2...60).frame(width: 80)
                        }.padding(.top, captureManager.isRecording || currentTool == .crop ? 0 : 8)
                        
                        HStack(spacing: 6) {
                            Button(action: { captureManager.takeScreenshot() }) {
                                Image(systemName: "camera.viewfinder")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.accentColor)
                                    .frame(width: 44, height: 44)
                                    .background(Circle().fill(Color.white.opacity(0.1)))
                            }
                            .buttonStyle(.plain)
                            .onHover { showCaptureTooltip = $0 }
                            
                            Divider().frame(height: 24).padding(.horizontal, 4)
                            
                            ForEach(DrawingTool.allCases, id: \.self) { tool in
                                ToolButton(tool: tool, isSelected: currentTool == tool, action: { currentTool = tool }, onHoverChange: { isHovered in 
                                    if isHovered { hoveredTool = tool }
                                    else if hoveredTool == tool { hoveredTool = nil }
                                })
                            }
                            Divider().frame(height: 24).padding(.horizontal, 2)
                            ColorPicker("", selection: $currentColor).labelsHidden()
                            Divider().frame(height: 24).padding(.horizontal, 2)
                            
                            // History and Save Toolbar
                            HStack(spacing: 8) {
                                ActionButton(systemName: "arrow.uturn.backward", action: undo, disabled: elements.isEmpty && historyStack.isEmpty)
                                
                                if !captureManager.isRecording {
                                    HStack(spacing: 12) {
                                        if currentTool == .crop {
                                            Button(action: applyCrop) { 
                                                Image(systemName: "checkmark.seal.fill")
                                                    .foregroundColor(.orange)
                                                    .font(.system(size: 24)) 
                                            }
                                            .buttonStyle(.plain)
                                            .keyboardShortcut(.return, modifiers: [])
                                        }
                                        
                                        Menu {
                                            Button(action: { captureManager.startRecording(mode: .entireScreen, includeMic: includeMic, showClicks: showClicks) }) {
                                                Label("Record Entire Screen", systemImage: "macwindow")
                                            }
                                            Button(action: { captureManager.startRecording(mode: .selectedArea, includeMic: includeMic, showClicks: showClicks) }) {
                                                Label("Record Selected Area", systemImage: "rectangle.dashed.badge.record")
                                            }
                                        } label: {
                                            Image(systemName: "video.fill")
                                                .foregroundColor(.red)
                                                .font(.system(size: 22))
                                        }
                                        .menuStyle(.borderlessButton)
                                        .frame(width: 32)
                                    }
                                } else {
                                    Button(action: { captureManager.stopRecording() }) { 
                                        ZStack { 
                                            Circle().fill(.red).frame(width: 44, height: 44)
                                            RoundedRectangle(cornerRadius: 2).fill(.white).frame(width: 14, height: 14) 
                                        }.shadow(color: .red.opacity(0.4), radius: 10) 
                                    }
                                    .buttonStyle(.plain)
                                    .onHover { showRecordingTooltip = $0 }
                                }
                                
                                Menu {
                                    Button(action: copyToClipboard) {
                                        Label("Copy to Clipboard (Cmd+C)", systemImage: "doc.on.clipboard")
                                    }

                                    Divider()

                                    Button("Save to Desktop (Cmd+D)") { saveToSuggested(directory: .desktopDirectory) }
                                    Button("Save to Downloads (Cmd+L)") { saveToSuggested(directory: .downloadsDirectory) }
                                    Button("Save to Documents") { saveToSuggested(directory: .documentDirectory) }
                                    Button("Save to Pictures") { saveToSuggested(directory: .picturesDirectory) }

                                    Divider()

                                    Button("Custom Location... (Cmd+S)") { saveToFile() }

                                } label: {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 30, weight: .bold))
                                        .foregroundColor(.green)
                                }
                                .menuStyle(.borderlessButton)
                                .onHover { showSaveTooltip = $0 }
                                .frame(width: 38)
                            }
                        }.padding(.bottom, 8)
                    .padding(.horizontal, 16)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 32))
                    .shadow(radius: 20)
                    .padding(.bottom, 24)
                }
            // GLOBAL TOOLTIPS (Above everything else)
            VStack {
                Spacer()
                ZStack {
                    if let tool = hoveredTool {
                        ToolTooltip(name: tool.displayName, shortcut: tool.shortcutKey)
                            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 4)), removal: .opacity))
                    }
                    if showCaptureTooltip {
                        ToolTooltip(name: "Nueva Captura", shortcut: "⌘⇧S")
                            .transition(.opacity)
                    }
                    if showRecordingTooltip {
                        ToolTooltip(name: "Detener Grabación", shortcut: "⌘⇧T")
                            .transition(.opacity)
                    }
                    if showSaveTooltip {
                        ToolTooltip(name: "Finalizar y Guardar", shortcut: "Menu")
                            .transition(.opacity)
                    }
                }
                .padding(.bottom, 110) // Positioned above the toolbar
            }
            .allowsHitTesting(false)
            .zIndex(2000)
        }

            } else { // Close of if-let img
                VStack(spacing: 16) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 64, weight: .ultraLight))
                        .foregroundColor(.accentColor.opacity(0.8))
                        .symbolRenderingMode(.hierarchical)
                    
                    Text("Ready for Capture")
                        .font(.system(size: 24, weight: .medium, design: .rounded))
                        .foregroundColor(.primary.opacity(0.8))
                    
                    Text("Use your hotkeys or the menu bar icon.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        // MARK: Drawing tool keyboard shortcuts
        .background(
            Group {
                // Tool selection shortcuts (active only when a screenshot is loaded)
                Button("") { currentTool = .select }
                    .keyboardShortcut("v", modifiers: [])
                Button("") { currentTool = .pen }
                    .keyboardShortcut("p", modifiers: [])
                Button("") { currentTool = .arrow }
                    .keyboardShortcut("a", modifiers: [])
                Button("") { currentTool = .rectangle }
                    .keyboardShortcut("r", modifiers: [])
                Button("") { currentTool = .oval }
                    .keyboardShortcut("o", modifiers: [])
                Button("") { currentTool = .pixelate }
                    .keyboardShortcut("x", modifiers: [])
                Button("") { currentTool = .text }
                    .keyboardShortcut("t", modifiers: [])
                Button("") { currentTool = .crop }
                    .keyboardShortcut("k", modifiers: [])
                Button("") { undo() }
                    .keyboardShortcut("z", modifiers: [.command])
                Button("") { WindowManager.shared.hide() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .opacity(0)
        )
        .onChange(of: captureManager.screenshot) {
            if ignoreChanges { return }
            
            withAnimation {
                self.elements.removeAll()
                self.redoStack.removeAll()
                self.historyStack.removeAll()
                self.zoomScale = 1.0
                if let newImg = captureManager.screenshot {
                    self.pixelatedImage = createPixelatedNSImage(from: newImg)
                    self.captureManager.lastVideoUrl = nil
                } else {
                    self.pixelatedImage = nil
                }
                self.cropRect = nil
            }
            // Show the editor window sized to fit the captured screenshot
            if let img = captureManager.screenshot {
                WindowManager.shared.showFitting(image: img)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TriggerShowWindow"))) { _ in
            WindowManager.shared.show()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TriggerUndo"))) { _ in
            withAnimation { undo() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TriggerCopy"))) { _ in
            copyToClipboard()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TriggerSave"))) { _ in
            saveToFile()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TriggerSaveToDesktop"))) { _ in
            saveToSuggested(directory: .desktopDirectory)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TriggerSaveToDownloads"))) { _ in
            saveToSuggested(directory: .downloadsDirectory)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TriggerAutoSaveVideo"))) { _ in
            // Automatically show save dialog when video recording finishes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                saveVideoWithDialog()
            }
        }
    }
    
    func saveVideoTo(directory: FileManager.SearchPathDirectory) {
        guard let url = captureManager.lastVideoUrl else { return }
        let dir = FileManager.default.urls(for: directory, in: .userDomainMask).first!

        // Use formatted timestamp for better readability
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let dest = dir.appendingPathComponent("ThiScreen_Recording_\(timestamp).mov")

        do {
            try FileManager.default.copyItem(at: url, to: dest)
            NSWorkspace.shared.activateFileViewerSelecting([dest])
        } catch {
            print("Error saving video to \(directory): \(error)")
        }
    }
    
    func saveToSuggested(directory: FileManager.SearchPathDirectory) {
        if captureManager.lastVideoUrl != nil {
            saveVideoTo(directory: directory)
            return
        }
        guard let finalImage = generateFinalImage() else { return }
        let dir = FileManager.default.urls(for: directory, in: .userDomainMask).first!

        // Use formatted timestamp for better readability
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let url = dir.appendingPathComponent("ThiScreen_\(timestamp).png")

        do {
            if let data = finalImage.tiffRepresentation, let rep = NSBitmapImageRep(data: data), let pngData = rep.representation(using: .png, properties: [:]) {
                try pngData.write(to: url)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        } catch {
            print("Error saving image to \(directory): \(error)")
        }
    }
    
    func saveVideo() {
        saveVideoWithDialog()
    }

    func saveVideoWithDialog() {
        guard let url = captureManager.lastVideoUrl else { return }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.quickTimeMovie]
        savePanel.canCreateDirectories = true

        // Set default filename with timestamp
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        savePanel.nameFieldStringValue = "ThiScreen_Recording_\(timestamp).mov"

        // Set default directory to Movies
        if let moviesURL = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first {
            savePanel.directoryURL = moviesURL
        }

        savePanel.begin { res in
            if res == .OK, let dest = savePanel.url {
                do {
                    try FileManager.default.copyItem(at: url, to: dest)
                    NSWorkspace.shared.activateFileViewerSelecting([dest])
                } catch {
                    print("Error saving video: \(error)")
                }
            }
        }
    }
    
    func createPixelatedNSImage(from image: NSImage) -> NSImage? {
        guard let tiff = image.tiffRepresentation, let ciImg = CIImage(data: tiff) else { return nil }
        let filter = CIFilter(name: "CIPixellate"); filter?.setValue(ciImg, forKey: kCIInputImageKey); filter?.setValue(35.0, forKey: kCIInputScaleKey) 
        let context = CIContext(options: [.workingColorSpace: NSNull()]); 
        let output = filter?.outputImage ?? ciImg
        guard let cgImg = context.createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cgImg, size: image.size)
    }
    
    func applyCrop() {
        guard let img = captureManager.screenshot, let crop = cropRect else { return }
        
        historyStack.append(AppState(screenshot: captureManager.screenshot, elements: elements))
        
        let targetSize = crop.size
        let renderer = ImageRenderer(content: ZStack {
            Image(nsImage: img).resizable()
            InteractiveDrawingView(elements: .constant(elements), currentTool: .constant(.arrow), currentColor: .constant(.red), currentLineWidth: .constant(8.0), cropRect: .constant(nil), pixelatedNSImage: pixelatedImage)
        }.frame(width: img.size.width, height: img.size.height).offset(x: -crop.midX + img.size.width/2, y: -crop.midY + img.size.height/2).frame(width: targetSize.width, height: targetSize.height).clipped())
        if let cgImage = renderer.cgImage {
            ignoreChanges = true
            let newScreenshot = NSImage(cgImage: cgImage, size: targetSize)
            withAnimation {
                captureManager.screenshot = newScreenshot
                self.elements.removeAll()
                self.redoStack.removeAll()
                self.pixelatedImage = createPixelatedNSImage(from: newScreenshot)
                self.cropRect = nil
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { ignoreChanges = false }
        }
    }

    func undo() { 
        if let lastElement = elements.popLast() { redoStack.append(lastElement) } 
        else if let lastState = historyStack.popLast() { 
            ignoreChanges = true
            captureManager.screenshot = lastState.screenshot
            elements = lastState.elements
            pixelatedImage = captureManager.screenshot.map { createPixelatedNSImage(from: $0) } ?? nil 
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { ignoreChanges = false }
        }
    }

    @MainActor
    private func generateFinalImage() -> NSImage? {
        guard let img = captureManager.screenshot else { return nil }
        
        let renderer = ImageRenderer(content: ZStack {
            Image(nsImage: img).resizable()
            InteractiveDrawingView(elements: .constant(elements), currentTool: .constant(.arrow), currentColor: .constant(.red), currentLineWidth: .constant(8.0), cropRect: .constant(nil), pixelatedNSImage: pixelatedImage)
        }.frame(width: img.size.width, height: img.size.height))
        
        if let cgImage = renderer.cgImage {
            return NSImage(cgImage: cgImage, size: img.size)
        }
        return nil
    }

    @MainActor
    func copyToClipboard() {
        guard let finalImage = generateFinalImage() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([finalImage])
    }

    @MainActor
    func saveToFile() {
        if captureManager.lastVideoUrl != nil {
            saveVideoWithDialog()
            return
        }
        guard let finalImage = generateFinalImage() else { return }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.canCreateDirectories = true

        // Set default filename with formatted timestamp
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        savePanel.nameFieldStringValue = "ThiScreen_\(timestamp).png"

        // Set default directory to Pictures
        if let picturesURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first {
            savePanel.directoryURL = picturesURL
        }

        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    if let data = finalImage.tiffRepresentation, let rep = NSBitmapImageRep(data: data), let pngData = rep.representation(using: .png, properties: [:]) {
                        try pngData.write(to: url)
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                } catch {
                    print("Error saving image: \(error)")
                }
            }
        }
    }
}

struct ActionButton: View {
    let systemName: String; let action: () -> Void; var disabled: Bool = false
    var body: some View { Button(action: action) { Image(systemName: systemName).font(.system(size: 14)).foregroundColor(.primary.opacity(disabled ? 0.3 : 0.8)).frame(width: 32, height: 32).background(Circle().fill(.white.opacity(0.05))) }.buttonStyle(.plain).disabled(disabled) }
}

// MARK: - Mouse Wheel Zoom Support
//
// Uses a local NSEvent monitor to capture scroll wheel events for zooming.
// This approach avoids all layout recursion issues since no custom NSView
// with tracking areas is involved.

struct MouseWheelZoomModifier: ViewModifier {
    @Binding var zoomScale: CGFloat
    @Binding var baseZoomScale: CGFloat
    
    @State private var monitor: Any? = nil

    func body(content: Content) -> some View {
        content
            .onAppear {
                // Install a local event monitor for scroll wheel events
                monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                    let delta = event.scrollingDeltaY
                    guard delta != 0 else { return event }
                    
                    // Use a comfortable zoom speed factor
                    let zoomFactor: CGFloat = 0.015
                    let newZoom = zoomScale + (delta * zoomFactor)
                    let clampedZoom = max(0.25, min(5.0, newZoom))
                    
                    zoomScale = clampedZoom
                    baseZoomScale = clampedZoom
                    
                    // Return nil to consume the event (prevent scroll bounce)
                    return nil
                }
            }
            .onDisappear {
                if let monitor = monitor {
                    NSEvent.removeMonitor(monitor)
                }
                monitor = nil
            }
    }
}

extension View {
    func mouseWheelZoom(zoomScale: Binding<CGFloat>, baseZoomScale: Binding<CGFloat>) -> some View {
        self.modifier(MouseWheelZoomModifier(zoomScale: zoomScale, baseZoomScale: baseZoomScale))
    }
}

