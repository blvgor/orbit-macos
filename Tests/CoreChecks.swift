import Foundation
import CoreGraphics
import ImageIO

actor CompletionFlag { var value = false; func finish() { value = true } }

@main struct CoreChecks {
    static func main() async throws {
        let folder = URL(fileURLWithPath:CommandLine.arguments[1])
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let library = URL(fileURLWithPath:CommandLine.arguments[2])
        var checks:[[String:Any]] = []
        func record(_ name:String,_ passed:Bool,_ detail:String = "") { checks.append(["name":name,"passed":passed,"detail":detail]); print("\(passed ? "PASS" : "FAIL") \(name)") }
        func makeImage() -> CGImage {
            let width = 96, height = 64
            let c = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            c.clear(CGRect(x:0,y:0,width:width,height:height))
            c.setFillColor(CGColor(red:0.24,green:0.44,blue:0.7,alpha:1)); c.fill(CGRect(x:18,y:12,width:60,height:40))
            c.setFillColor(CGColor(red:0.9,green:0.2,blue:0.1,alpha:0.5)); c.fillEllipse(in:CGRect(x:36,y:20,width:40,height:30))
            return c.makeImage()!
        }
        func rgba(_ image:CGImage) -> [UInt8] {
            let context = CGContext(data:nil,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
            return Array(UnsafeBufferPointer(start:context.data!.assumingMemoryBound(to:UInt8.self),count:image.width*image.height*4))
        }
        let fixture = folder.appendingPathComponent("test ' quote ; $ image.png")
        let image = makeImage()
        let destination = CGImageDestinationCreateWithURL(fixture as CFURL,"public.png" as CFString,1,nil)!
        CGImageDestinationAddImage(destination,image,[kCGImagePropertyPNGDictionary:[kCGImagePropertyPNGDescription:String(repeating:"Orbit metadata fixture ",count:1000)]] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { fatalError("fixture") }
        let original = try Data(contentsOf:fixture)
        let runner = ChildProcessRunner()
        let engine = FileProcessor(runner:runner,webpLibrary:library)
        for action in [OrbitAction.png,.jpg,.webp,.avif,.pdf] {
            runner.reset()
            do {
                let result = try await engine.run(inputs:[fixture],action:action,update:{ _ in })
                let output = result.files[0]
                try ImageCodec.validate(output)
                let sourceUnchanged = try Data(contentsOf:fixture) == original
                record("\(action.label) actual encode and decode",result.files.count == 1 && output != fixture && sourceUnchanged,output.lastPathComponent)
                if action != .pdf {
                    let source = CGImageSourceCreateWithURL(output as CFURL,nil)!
                    let decoded = CGImageSourceCreateImageAtIndex(source,0,nil)!
                    record("\(action.label) keeps pixel dimensions",decoded.width == 96 && decoded.height == 64)
                    let actual = rgba(decoded), expected = rgba(image), pixel = (28*96+24)*4
                    record("\(action.label) keeps RGB channel order and color",(0..<3).allSatisfy { abs(Int(actual[pixel+$0])-Int(expected[pixel+$0])) < 25 })
                    if action == .jpg { record("JPG flattens transparent background to white",actual[0] > 245 && actual[1] > 245 && actual[2] > 245) }
                }
            } catch { record("\(action.label) actual encode and decode",false,error.localizedDescription) }
        }
        // The small fixture can finish between two 15ms window samples.
        // Include a deterministic larger image so the real codec is observed running.
        let largeFixture = folder.appendingPathComponent("window-observation.png")
        let largeContext = CGContext(data:nil,width:1024,height:768,bitsPerComponent:8,bytesPerRow:1024*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        let pixels = largeContext.data!.assumingMemoryBound(to:UInt8.self)
        var seed: UInt32 = 7919
        for pixel in 0..<(1024*768) {
            for channel in 0..<3 { seed = seed &* 1664525 &+ 1013904223; pixels[pixel*4+channel] = UInt8(truncatingIfNeeded:seed >> 24) }
            pixels[pixel*4+3] = 255
        }
        let largeDest = CGImageDestinationCreateWithURL(largeFixture as CFURL,"public.png" as CFString,1,nil)!
        CGImageDestinationAddImage(largeDest,largeContext.makeImage()!,nil)
        guard CGImageDestinationFinalize(largeDest) else { fatalError("Observation fixture") }
        runner.reset()
        let flag = CompletionFlag()
        let work = Task {
            do { let result = try await engine.run(inputs:[fixture,largeFixture],action:.optim,update:{ _ in }); await flag.finish(); return result }
            catch { await flag.finish(); throw error }
        }
        var visibleChildWindows = 0, childSamples = 0
        var observedProcesses = Set<Int32>()
        while !(await flag.value) {
            if let pid = runner.currentPID() {
                childSamples += 1
                observedProcesses.insert(pid)
                let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? []
                visibleChildWindows += windows.filter { ($0[kCGWindowOwnerPID as String] as? Int) == Int(pid) && ($0[kCGWindowLayer as String] as? Int) == 0 }.count
            }
            try await Task.sleep(for:.milliseconds(15))
        }
        do {
            let result = try await work.value
            record("Real ImageOptim finishes and output validates",result.files.count == 2)
            record("ImageOptim leaves original byte-for-byte intact",try Data(contentsOf:fixture) == original)
            record("Optimization never increases delivered byte size",result.outputBytes <= result.inputBytes,"\(result.inputBytes) → \(result.outputBytes)")
            let optimizedSource = CGImageSourceCreateWithURL(result.files[0] as CFURL,nil)!
            record("PNG optimization preserves rendered pixels",rgba(CGImageSourceCreateImageAtIndex(optimizedSource,0,nil)!) == rgba(image))
            record("Installed ImageOptim codec shows no visible window",childSamples > 0 && visibleChildWindows == 0,"\(childSamples) process samples, \(visibleChildWindows) visible windows; \(observedProcesses.count) owned codec processes")
        } catch { record("Real ImageOptim finishes and output validates",false,error.localizedDescription) }

        let pdf = folder.appendingPathComponent("two-pages.pdf")
        try ImageCodec.encode([image,image],action:.pdf,to:pdf,webpLibrary:library)
        let pdfBytes = try Data(contentsOf:pdf)
        runner.reset()
        let pages = try await engine.run(inputs:[pdf],action:.png,update:{ _ in })
        record("PDF exports every page",pages.files.count == 2 && pages.files.allSatisfy { $0.lastPathComponent.contains("-page-") })
        let pdfCopy = try await engine.run(inputs:[pdf],action:.pdf,update:{ _ in })
        record("PDF to PDF preserves vector original bytes",try Data(contentsOf:pdfCopy.files[0]) == pdfBytes)

        let jpg = folder.appendingPathComponent("orientation.jpg")
        let jpgDest = CGImageDestinationCreateWithURL(jpg as CFURL,"public.jpeg" as CFString,1,nil)!
        CGImageDestinationAddImage(jpgDest,image,[kCGImagePropertyOrientation:6] as CFDictionary); _ = CGImageDestinationFinalize(jpgDest)
        let rotated = try await engine.run(inputs:[jpg],action:.png,update:{ _ in })
        let rotatedSource = CGImageSourceCreateWithURL(rotated.files[0] as CFURL,nil)!
        let rotatedImage = CGImageSourceCreateImageAtIndex(rotatedSource,0,nil)!
        record("EXIF orientation becomes correct output pixels",rotatedImage.width == 64 && rotatedImage.height == 96)
        let optimizedJPEG = try await engine.run(inputs:[jpg],action:.optim,update:{ _ in })
        let jpegSource = CGImageSourceCreateWithURL(optimizedJPEG.files[0] as CFURL,nil)!
        let jpegProperties = CGImageSourceCopyPropertiesAtIndex(jpegSource,0,nil) as! [CFString:Any]
        record("Installed JPEG optimizer preserves EXIF orientation",jpegProperties[kCGImagePropertyOrientation] as? Int == 6 && optimizedJPEG.outputBytes <= optimizedJPEG.inputBytes)

        let gif = folder.appendingPathComponent("animated.gif")
        let gifDest = CGImageDestinationCreateWithURL(gif as CFURL,"com.compuserve.gif" as CFString,2,nil)!
        CGImageDestinationSetProperties(gifDest,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary)
        let frameInfo = [kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:0.2]] as CFDictionary
        CGImageDestinationAddImage(gifDest,image,frameInfo)
        let otherContext = CGContext(data:nil,width:96,height:64,bitsPerComponent:8,bytesPerRow:96*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        otherContext.setFillColor(CGColor(red:0.8,green:0.35,blue:0.2,alpha:1)); otherContext.fill(CGRect(x:0,y:0,width:96,height:64))
        CGImageDestinationAddImage(gifDest,otherContext.makeImage()!,frameInfo)
        guard CGImageDestinationFinalize(gifDest) else { fatalError("GIF fixture") }
        let gifBytes = try Data(contentsOf:gif)
        let optimizedGIF = try await engine.run(inputs:[gif],action:.optim,update:{ _ in })
        let gifSource = CGImageSourceCreateWithURL(optimizedGIF.files[0] as CFURL,nil)!
        let frameProperties = CGImageSourceCopyPropertiesAtIndex(gifSource,1,nil) as? [CFString:Any]
        let gifInfo = frameProperties?[kCGImagePropertyGIFDictionary] as? [CFString:Any]
        let gifUnchanged = try Data(contentsOf:gif) == gifBytes
        record("Installed GIF optimizer retains frames and timing",CGImageSourceGetCount(gifSource) == 2 && abs((gifInfo?[kCGImagePropertyGIFDelayTime] as? Double ?? 0)-0.2)<0.01 && gifUnchanged)

        let text = folder.appendingPathComponent("unsupported.txt"); try Data("untouched".utf8).write(to:text)
        do { _ = try await engine.run(inputs:[text],action:.optim,update:{ _ in }); record("Unsupported document is rejected",false) }
        catch { record("Unsupported document is rejected",try String(contentsOf:text,encoding:.utf8) == "untouched") }
        let bad = folder.appendingPathComponent("broken.png"); try Data("not PNG".utf8).write(to:bad)
        do { _ = try await engine.run(inputs:[bad],action:.png,update:{ _ in }); record("Corrupt input is rejected",false) }
        catch { record("Corrupt input is rejected",true) }
        let beforeBatch = Set(try FileManager.default.contentsOfDirectory(atPath:folder.path))
        do { _ = try await engine.run(inputs:[fixture,bad],action:.png,update:{ _ in }); record("Batch error cannot leave partial outputs",false) }
        catch { record("Batch error cannot leave partial outputs",Set(try FileManager.default.contentsOfDirectory(atPath:folder.path)) == beforeBatch) }
        let failingTools = folder.appendingPathComponent("failing-tools")
        try FileManager.default.createDirectory(at:failingTools,withIntermediateDirectories:true)
        let failing = failingTools.appendingPathComponent("oxipng")
        try Data("#!/bin/sh\nexit 7\n".utf8).write(to:failing); try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:failing.path)
        let failEngine = FileProcessor(runner:runner,optimizerTools:failingTools,webpLibrary:library)
        do { _ = try await failEngine.run(inputs:[fixture],action:.optim,update:{ _ in }); record("Failed optimizer cannot commit output",false) }
        catch { record("Failed optimizer cannot commit output",try Data(contentsOf:fixture) == original) }
        let sleeper = folder.appendingPathComponent("slow-optimizer")
        try Data("#!/bin/sh\nexec /bin/sleep 20\n".utf8).write(to:sleeper); try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:sleeper.path)
        runner.reset()
        let start = Date()
        do { try runner.run(sleeper,arguments:[],timeout:0.1); record("Timeout terminates only owned process",false) }
        catch { record("Timeout terminates only owned process",Date().timeIntervalSince(start)<5 && runner.currentPID() == nil) }
        runner.reset()
        let cancelStart = Date()
        let cancelWork = Task.detached { try runner.run(sleeper,arguments:[]) }
        while runner.currentPID() == nil { try await Task.sleep(for:.milliseconds(10)) }
        runner.cancel()
        do { try await cancelWork.value; record("Cancel stops owned process without committing",false) }
        catch is CancellationError { record("Cancel stops owned process without committing",Date().timeIntervalSince(cancelStart)<5 && runner.currentPID() == nil) }
        catch { record("Cancel stops owned process without committing",false,error.localizedDescription) }
        runner.reset()
        let missingEngine = FileProcessor(runner:runner,optimizerTools:folder.appendingPathComponent("missing"),webpLibrary:library)
        do { _ = try await missingEngine.run(inputs:[fixture],action:.optim,update:{ _ in }); record("Missing optimizer fails clearly",false) }
        catch { record("Missing optimizer fails clearly",error.localizedDescription.contains("не найден")) }
        let remaining = try FileManager.default.contentsOfDirectory(atPath:folder.path)
        record("Temporary work folders are cleaned on success and failure",!remaining.contains { $0.hasPrefix(".orbit-task-") })
        record("Original source survives all operations",try Data(contentsOf:fixture) == original)
        let report:[String:Any] = ["checks":checks,"passed":checks.allSatisfy { $0["passed"] as? Bool == true }]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:folder.deletingLastPathComponent().appendingPathComponent("core-checks.json"))
        if !(report["passed"] as! Bool) { exit(1) }
    }
}
