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

struct ToolButton: View {
    let icon: String; let isSelected: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 18)).foregroundColor(isSelected ? .white : .primary).frame(width: 44, height: 44).background(ZStack {
                if isSelected { Circle().fill(Color.accentColor).shadow(color: Color.accentColor.opacity(0.4), radius: 8, y: 4) }
                else { Circle().fill(Color.white.opacity(0.05)) }
            }).overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 0.5))
        }.buttonStyle(.plain).animation(.spring(), value: isSelected)
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
                            Divider()
                            Button("Custom Location... (Cmd+S)") { saveVideo() }
                        } label: {
                            Label("Save Video...", systemImage: "arrow.down.doc.fill").padding()
                        }.buttonStyle(.borderedProminent)
                        
                        Button(action: { captureManager.lastVideoUrl = nil }) {
                            Label("Discard", systemImage: "trash").foregroundColor(.red).padding()
                        }.buttonStyle(.bordered)
                    }.padding(.bottom, 24)
                }
            }
            else if let img = captureManager.screenshot {
                GeometryReader { geo in
                    let scale = min(geo.size.width / img.size.width, geo.size.height / img.size.height) * zoomScale
                    ZStack {
                        Image(nsImage: img).resizable()
                        InteractiveDrawingView(elements: $elements, currentTool: $currentTool, currentColor: $currentColor, currentLineWidth: $currentLineWidth, cropRect: $cropRect, pixelatedNSImage: pixelatedImage)
                    }
                    .frame(width: img.size.width, height: img.size.height).scaleEffect(scale).frame(width: geo.size.width, height: geo.size.height)
                    .gesture(MagnificationGesture()
                        .onChanged { value in
                            let newScale = baseZoomScale * value
                            zoomScale = max(0.5, min(4.0, newScale))
                        }
                        .onEnded { _ in baseZoomScale = zoomScale })
                }
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
                            Image(systemName: "magnifyingglass"); Slider(value: $zoomScale, in: 0.5...4.0).frame(width: 80)
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
                            .help("Start New Capture")
                            
                            Divider().frame(height: 24).padding(.horizontal, 4)
                            
                            ForEach(DrawingTool.allCases, id: \.self) { tool in ToolButton(icon: tool.rawValue, isSelected: currentTool == tool) { currentTool = tool } }
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
                                    }.buttonStyle(.plain)
                                }
                                
                                Menu {
                                    Button(action: copyToClipboard) {
                                        Label("Copy to Clipboard (Cmd+C)", systemImage: "doc.on.clipboard")
                                    }
                                    
                                    Divider()
                                    
                                    Button("Save to Desktop (Cmd+D)") { saveToSuggested(directory: .desktopDirectory) }
                                    Button("Save to Downloads (Cmd+L)") { saveToSuggested(directory: .downloadsDirectory) }
                                    Button("Custom Location... (Cmd+S)") { saveToFile() }

                                } label: {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 30, weight: .bold))
                                        .foregroundColor(.green)
                                }
                                .menuStyle(.borderlessButton)
                                .frame(width: 38)
                            }
                        }.padding(.bottom, 8)
                    }.padding(.horizontal, 16).background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 32)).shadow(radius: 20).padding(.bottom, 24)
                }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "viewfinder.circle.fill")
                        .font(.system(size: 80, weight: .ultraLight))
                        .foregroundColor(.accentColor)
                        .symbolRenderingMode(.hierarchical)
                    
                    Text("ThiScreen Ready")
                        .font(.system(size: 32, weight: .bold))
                    
                    Text("Capture anything. Annotate everything.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Cmd+Shift+S: Capture Screenshot", systemImage: "camera")
                        Label("Cmd+Shift+R: Record Video", systemImage: "video")
                        Label("Cmd+Shift+A: Entire Screen", systemImage: "macwindow")
                        Divider().padding(.vertical, 4)
                        Label("Cmd+Z: Undo Drawing / Reset Crop", systemImage: "arrow.uturn.backward")
                        Label("Cmd+D: Save to Desktop", systemImage: "desktopcomputer")
                        Label("Cmd+L: Save to Downloads", systemImage: "arrow.down.circle")
                    }
                    .padding()
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(12)
                    
                    Button("Start First Capture") {
                        captureManager.takeScreenshot()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
            }
        }
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
    }
    
    func saveVideoTo(directory: FileManager.SearchPathDirectory) {
        guard let url = captureManager.lastVideoUrl else { return }
        let dir = FileManager.default.urls(for: directory, in: .userDomainMask).first!
        let dest = dir.appendingPathComponent("ThiScreen_Recording_\(Int(Date().timeIntervalSince1970)).mov")
        try? FileManager.default.copyItem(at: url, to: dest)
        NSWorkspace.shared.activateFileViewerSelecting([dest])
    }
    
    func saveToSuggested(directory: FileManager.SearchPathDirectory) {
        if captureManager.lastVideoUrl != nil {
            saveVideoTo(directory: directory)
            return
        }
        guard let finalImage = generateFinalImage() else { return }
        let dir = FileManager.default.urls(for: directory, in: .userDomainMask).first!
        let url = dir.appendingPathComponent("ThiScreen_\(Int(Date().timeIntervalSince1970)).png")
        if let data = finalImage.tiffRepresentation, let rep = NSBitmapImageRep(data: data), let pngData = rep.representation(using: .png, properties: [:]) {
            try? pngData.write(to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
    
    func saveVideo() {
        guard let url = captureManager.lastVideoUrl else { return }
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.quickTimeMovie]
        savePanel.nameFieldStringValue = "ThiScreen_Recording_\(Int(Date().timeIntervalSince1970)).mov"
        savePanel.begin { res in
            if res == .OK, let dest = savePanel.url {
                try? FileManager.default.copyItem(at: url, to: dest)
                NSWorkspace.shared.activateFileViewerSelecting([dest])
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
            saveVideo()
            return
        }
        guard let finalImage = generateFinalImage() else { return }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = "ThiScreen_\(Int(Date().timeIntervalSince1970)).png"
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                if let data = finalImage.tiffRepresentation, let rep = NSBitmapImageRep(data: data), let pngData = rep.representation(using: .png, properties: [:]) {
                    try? pngData.write(to: url)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        }
    }
}

struct ActionButton: View {
    let systemName: String; let action: () -> Void; var disabled: Bool = false
    var body: some View { Button(action: action) { Image(systemName: systemName).font(.system(size: 14)).foregroundColor(.primary.opacity(disabled ? 0.3 : 0.8)).frame(width: 32, height: 32).background(Circle().fill(.white.opacity(0.05))) }.buttonStyle(.plain).disabled(disabled) }
}
