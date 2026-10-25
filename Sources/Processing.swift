import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Darwin

enum OrbitAction: String, CaseIterable, Sendable {
    case png, webp, avif, optim, pdf, jpg
    var label: String { self == .optim ? "OPT" : rawValue.uppercased() }
    var title: String { self == .optim ? "Оптимизировать через ImageOptim" : "Конвертировать в \(label)" }
    var angle: Double { Double(Self.allCases.firstIndex(of: self)!) * .pi / 3 }
}

enum OrbitFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

struct JobResult: Sendable {
    let files: [URL]
    let inputBytes: Int64
    let outputBytes: Int64
}

// Only the runner's own child process is terminated. No app-name-based kills.
final class ChildProcessRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var stopped = false
    private var expired = false
    func currentPID() -> pid_t? { lock.lock(); defer { lock.unlock() }; return process?.isRunning == true ? process?.processIdentifier : nil }
    func reset() { lock.lock(); stopped = false; expired = false; lock.unlock() }
    func cancel() {
        lock.lock(); stopped = true; let child = process; lock.unlock()
        terminate(child)
    }
    private func terminate(_ child: Process?) {
        guard let child, child.isRunning else { return }
        child.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        }
    }
    func check() throws {
        lock.lock(); let cancelled = stopped; lock.unlock()
        if cancelled { throw CancellationError() }
    }
    func run(_ executable: URL, arguments: [String], timeout: TimeInterval = 300) throws {
        try check()
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw OrbitFailure.message("Инструмент ImageOptim не найден. Проверьте установку ImageOptim в папке «Программы».")
        }
        let child = Process()
        child.executableURL = executable
        child.arguments = arguments
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        child.standardInput = FileHandle.nullDevice
        lock.lock(); process = child; lock.unlock()
        defer { lock.lock(); process = nil; lock.unlock() }
        try child.run()
        lock.lock(); let cancelled = stopped; lock.unlock()
        if cancelled { terminate(child) }
        let timeoutWork = DispatchWorkItem { [weak self, weak child] in
            guard let self, let child, child.isRunning else { return }
            self.lock.lock(); self.expired = true; self.lock.unlock()
            self.terminate(child)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWork)
        child.waitUntilExit()
        timeoutWork.cancel()
        try check()
        lock.lock(); let timedOut = expired; lock.unlock()
        if timedOut { throw OrbitFailure.message("ImageOptim не завершился за 5 минут. Оригинал сохранён.") }
        if child.terminationStatus != 0 { throw OrbitFailure.message("ImageOptim завершился с ошибкой. Оригинал сохранён.") }
    }
}

enum ImageCodec {
    static let limit = 100_000_000 // Pixel-memory limit, unrelated to interface dimensions.
    static func readable(_ url: URL) -> Bool {
        if url.pathExtension.lowercased() == "pdf" { return CGPDFDocument(url as CFURL) != nil }
        return CGImageSourceCreateWithURL(url as CFURL, nil) != nil
    }
    static func optimizable(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let type = CGImageSourceGetType(source) as String? else { return false }
        return ["public.png", "public.jpeg", "com.compuserve.gif"].contains(type)
    }
    static func images(_ url: URL) throws -> [CGImage] {
        if url.pathExtension.lowercased() == "pdf" {
            guard let pdf = CGPDFDocument(url as CFURL), !pdf.isEncrypted, pdf.numberOfPages > 0 else { throw OrbitFailure.message("Не удалось прочитать PDF.") }
            var result: [CGImage] = []
            var remainingPixels = limit
            for i in 1...pdf.numberOfPages {
                guard let page = pdf.page(at: i) else { throw OrbitFailure.message("Не удалось прочитать страницу PDF.") }
                let box = page.getBoxRect(.mediaBox)
                let width = Int(ceil(box.width * 2)), height = Int(ceil(box.height * 2))
                guard width > 0, height > 0, width <= remainingPixels / height,
                      let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width*4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw OrbitFailure.message("Изображение слишком большое для обработки.") }
                remainingPixels -= width * height
                context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0,y: 0,width: width,height: height))
                context.concatenate(page.getDrawingTransform(.mediaBox, rect: CGRect(x: 0,y: 0,width: width,height: height), rotate: 0, preserveAspectRatio: true))
                context.drawPDFPage(page)
                guard let image = context.makeImage() else { throw OrbitFailure.message("Не удалось отрисовать PDF.") }
                result.append(image)
            }
            return result
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw OrbitFailure.message("Поддерживаются изображения и PDF. Этот документ пока не поддерживается.") }
        guard CGImageSourceGetCount(source) == 1 else { throw OrbitFailure.message("Для анимации выберите OPT. Конвертация не должна потерять кадры.") }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        guard width > 0, height > 0, width <= limit / height else { throw OrbitFailure.message("Изображение слишком большое для обработки.") }
        // ImageIO applies EXIF orientation while creating the full-size image.
        let options: [CFString:Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: max(width,height)]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw OrbitFailure.message("Не удалось прочитать изображение.") }
        return [image]
    }
    static func encode(_ images: [CGImage], action: OrbitAction, to url: URL, webpLibrary: URL) throws {
        if action == .pdf {
            var box = CGRect(x: 0,y: 0,width: images[0].width,height: images[0].height)
            guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { throw OrbitFailure.message("Не удалось создать PDF.") }
            for image in images {
                var rect = CGRect(x: 0,y: 0,width: image.width,height: image.height)
                let data = Data(bytes: &rect, count: MemoryLayout<CGRect>.size)
                context.beginPDFPage([kCGPDFContextMediaBox as String:data] as CFDictionary)
                context.draw(image, in: rect); context.endPDFPage()
            }
            context.closePDF(); return
        }
        guard let image = images.first else { throw OrbitFailure.message("В файле нет изображения.") }
        if action == .webp { try writeWebP(image, url: url, library: webpLibrary); return }
        let type = action == .jpg ? "public.jpeg" : action == .avif ? "public.avif" : "public.png"
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil) else { throw OrbitFailure.message("Эта версия macOS не умеет сохранять \(action.label).") }
        var rendered = image
        if action == .jpg {
            guard let c = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width*4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw OrbitFailure.message("Недостаточно памяти для JPG.") }
            c.setFillColor(CGColor(gray: 1,alpha: 1)); c.fill(CGRect(x: 0,y: 0,width: image.width,height: image.height)); c.draw(image, in: CGRect(x: 0,y: 0,width: image.width,height: image.height))
            guard let opaque = c.makeImage() else { throw OrbitFailure.message("Не удалось создать JPG.") }; rendered = opaque
        }
        CGImageDestinationAddImage(destination, rendered, [kCGImageDestinationLossyCompressionQuality:0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw OrbitFailure.message("Не удалось сохранить \(action.label).") }
    }
    static func writeWebP(_ image: CGImage, url: URL, library: URL) throws {
        guard image.width <= 16383, image.height <= 16383 else { throw OrbitFailure.message("WebP поддерживает изображения до 16383 пикселей по стороне.") }
        guard let handle = dlopen(library.path, RTLD_NOW | RTLD_LOCAL) else { throw OrbitFailure.message("Не удалось загрузить встроенный кодек WebP.") }
        defer { dlclose(handle) }
        typealias Encode = @convention(c) (UnsafePointer<UInt8>?, Int32, Int32, Int32, Float, UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?) -> Int
        typealias Free = @convention(c) (UnsafeMutableRawPointer?) -> Void
        guard let symbol = dlsym(handle,"WebPEncodeRGBA"), let freeSymbol = dlsym(handle,"WebPFree") else { throw OrbitFailure.message("Кодек WebP повреждён.") }
        let encode = unsafeBitCast(symbol,to:Encode.self), free = unsafeBitCast(freeSymbol,to:Free.self)
        let width = image.width, height = image.height, stride = width*4
        var bytes = [UInt8](repeating:0,count:stride*height)
        try bytes.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data:raw.baseAddress, width:width,height:height,bitsPerComponent:8,bytesPerRow:stride,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { throw OrbitFailure.message("Недостаточно памяти для WebP.") }
            context.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
        }
        for i in Swift.stride(from:0,to:bytes.count,by:4) {
            let alpha = Int(bytes[i+3])
            if alpha > 0 && alpha < 255 { for c in 0..<3 { bytes[i+c] = UInt8(min(255,(Int(bytes[i+c])*255 + alpha/2)/alpha)) } }
        }
        var output: UnsafeMutablePointer<UInt8>?
        let count = bytes.withUnsafeBufferPointer { encode($0.baseAddress,Int32(width),Int32(height),Int32(stride),90,&output) }
        guard count > 0, let output else { throw OrbitFailure.message("Не удалось сохранить WebP.") }
        defer { free(output) }
        try Data(bytes:output,count:count).write(to:url,options:.withoutOverwriting)
    }
    static func validate(_ url: URL, expectedFrames: Int? = nil, expectedSize: CGSize? = nil) throws {
        let size = (try url.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? 0
        guard size > 0 else { throw OrbitFailure.message("Обработка создала пустой файл.") }
        if url.pathExtension.lowercased() == "pdf" {
            guard let pdf = CGPDFDocument(url as CFURL), pdf.numberOfPages > 0 else { throw OrbitFailure.message("Созданный PDF не читается.") }; return
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL,nil), CGImageSourceGetCount(source) > 0 else { throw OrbitFailure.message("Результат не читается. Оригинал сохранён.") }
        for index in 0..<CGImageSourceGetCount(source) {
            guard CGImageSourceCreateImageAtIndex(source,index,nil) != nil else { throw OrbitFailure.message("Кадр результата не читается. Оригинал сохранён.") }
        }
        if let expectedFrames, CGImageSourceGetCount(source) != expectedFrames { throw OrbitFailure.message("Оптимизатор изменил число кадров. Оригинал сохранён.") }
        if let expectedSize {
            let properties = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any]
            guard properties?[kCGImagePropertyPixelWidth] as? Int == Int(expectedSize.width),
                  properties?[kCGImagePropertyPixelHeight] as? Int == Int(expectedSize.height) else {
                throw OrbitFailure.message("Оптимизатор изменил размер изображения. Оригинал сохранён.")
            }
        }
    }
}

actor FileProcessor {
    let runner: ChildProcessRunner
    let optimizerTools: URL
    let webpLibrary: URL
    init(runner: ChildProcessRunner, optimizerTools: URL = URL(fileURLWithPath:"/Applications/ImageOptim.app/Contents/Frameworks/ImageOptimGPL.framework/Resources"), webpLibrary: URL) {
        self.runner = runner; self.optimizerTools = optimizerTools; self.webpLibrary = webpLibrary
    }
    func run(inputs: [URL], action: OrbitAction, update: @Sendable (Double) -> Void) throws -> JobResult {
        let fm = FileManager.default
        guard !inputs.isEmpty else { throw OrbitFailure.message("Сначала выберите файл.") }
        var folders: [URL] = [], staged: [(URL,URL)] = [], committed: [URL] = []
        var inputBytes: Int64 = 0
        defer { for folder in folders { try? fm.removeItem(at:folder) } }
        do {
            for (i,input) in inputs.enumerated() {
                try runner.check()
                let values = try input.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey])
                guard values.isRegularFile == true else { throw OrbitFailure.message("Выберите файлы, а не папку.") }
                inputBytes += Int64(values.fileSize ?? 0)
                let parent = input.deletingLastPathComponent()
                let work = parent.appendingPathComponent(".orbit-task-" + UUID().uuidString,isDirectory:true)
                try fm.createDirectory(at:work,withIntermediateDirectories:false); folders.append(work)
                update(Double(i)/Double(inputs.count)*0.88 + 0.02)
                if action == .optim {
                    guard ImageCodec.optimizable(input) else { throw OrbitFailure.message("ImageOptim обрабатывает PNG, JPG и GIF. Выберите другой формат для этого файла.") }
                    let source = CGImageSourceCreateWithURL(input as CFURL,nil)!
                    let frameCount = CGImageSourceGetCount(source)
                    let properties = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any]
                    let size = CGSize(width:properties?[kCGImagePropertyPixelWidth] as? Int ?? 0,height:properties?[kCGImagePropertyPixelHeight] as? Int ?? 0)
                    let temp = work.appendingPathComponent(input.lastPathComponent)
                    try fm.copyItem(at:input,to:temp)
                    // The installed GUI briefly orders its nib window on screen before hiding.
                    // Its bundled CLI codecs have no window code and never launch that GUI.
                    switch CGImageSourceGetType(source) as String? {
                    case "public.png":
                        // Keep color, orientation and animation chunks; discard text metadata.
                        try runner.run(optimizerTools.appendingPathComponent("oxipng"),arguments:["-o","1","--preserve","--keep","cICP,iCCP,sRGB,pHYs,acTL,fcTL,fdAT,eXIf,gAMA,cHRM",temp.path])
                    case "public.jpeg":
                        try runner.run(optimizerTools.appendingPathComponent("jpegoptim"),arguments:["--preserve","--strip-none","--all-progressive",temp.path])
                    case "com.compuserve.gif":
                        try runner.run(optimizerTools.appendingPathComponent("gifsicle"),arguments:["--batch","--optimize=3",temp.path])
                    default: throw OrbitFailure.message("Этот формат не поддерживает оптимизацию.")
                    }
                    try ImageCodec.validate(temp,expectedFrames:frameCount,expectedSize:size)
                    // Optimization must never increase the delivered file's byte size.
                    let outputSize = (try temp.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? 0
                    if outputSize > (values.fileSize ?? 0) { try fm.removeItem(at:temp); try fm.copyItem(at:input,to:temp) }
                    let destination = parent.appendingPathComponent(input.deletingPathExtension().lastPathComponent + "-optimized." + input.pathExtension)
                    staged.append((temp,destination))
                } else if action == .pdf && input.pathExtension.lowercased() == "pdf" {
                    let temp = work.appendingPathComponent(input.lastPathComponent)
                    try fm.copyItem(at:input,to:temp); try ImageCodec.validate(temp)
                    staged.append((temp,parent.appendingPathComponent(input.lastPathComponent)))
                } else {
                    let images = try ImageCodec.images(input)
                    let groups = action == .pdf ? [images] : images.map { [$0] }
                    for (page,group) in groups.enumerated() {
                        try runner.check()
                        let suffix = groups.count > 1 ? "-page-\(page+1)" : ""
                        let name = input.deletingPathExtension().lastPathComponent + suffix + "." + action.rawValue
                        let temp = work.appendingPathComponent(name)
                        try ImageCodec.encode(group,action:action,to:temp,webpLibrary:webpLibrary)
                        try ImageCodec.validate(temp)
                        staged.append((temp,parent.appendingPathComponent(name)))
                    }
                }
                update(Double(i+1)/Double(inputs.count)*0.88)
            }
            try runner.check()
            for (temp,desired) in staged {
                try runner.check()
                var counter = 1
                var destination = desired
                while fm.fileExists(atPath:destination.path) { counter += 1
                    destination = desired.deletingLastPathComponent().appendingPathComponent(desired.deletingPathExtension().lastPathComponent + " \(counter)." + desired.pathExtension)
                }
                try fm.moveItem(at:temp,to:destination); committed.append(destination)
            }
            let outputBytes = try committed.reduce(Int64(0)) { $0 + Int64(try $1.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0) }
            update(1)
            return JobResult(files:committed,inputBytes:inputBytes,outputBytes:outputBytes)
        } catch {
            for url in committed { try? fm.removeItem(at:url) }
            throw error
        }
    }
}
