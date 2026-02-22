import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Draws numbered bounding boxes over a screenshot image.
/// Uses a single high-contrast red for all boxes — proven to maximise
/// recognition by vision-language models (Set-of-Mark, OmniParser).
/// Element classification lives in the JSON output, not in box color.
enum ScreenAnnotator {

  struct AnnotatedElement {
    let box: Int
    let frame: CGRect // in device points
    let label: String
  }

  // MARK: - Annotation color

  /// Bright red (#FF0000) — highest saliency across diverse UI backgrounds.
  private static let boxColor = CGColor(red: 1, green: 0, blue: 0, alpha: 1)
  private static let boxFill = CGColor(red: 1, green: 0, blue: 0, alpha: 0.10)
  private static let badgeColor = NSColor(red: 0.85, green: 0.05, blue: 0.05, alpha: 1)
  private static let badgeBorder = CGColor(red: 1, green: 1, blue: 1, alpha: 1)

  /// Annotate a screenshot PNG with numbered bounding boxes.
  static func annotate(
    imagePath: String,
    elements: [AnnotatedElement],
    deviceSize: (width: Double, height: Double),
    outputPath: String
  ) throws {
    let url = URL(fileURLWithPath: imagePath)
    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
    else {
      throw AnnotatorError.failedToLoadImage(imagePath)
    }

    let imageWidth = cgImage.width
    let imageHeight = cgImage.height

    let scaleX = Double(imageWidth) / deviceSize.width
    let scaleY = Double(imageHeight) / deviceSize.height

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
      data: nil,
      width: imageWidth,
      height: imageHeight,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      throw AnnotatorError.failedToCreateContext
    }

    // Flip to top-left origin so element coordinates map directly
    ctx.translateBy(x: 0, y: Double(imageHeight))
    ctx.scaleBy(x: 1, y: -1)

    // Draw original image — temporarily undo the flip so the image renders right-side up.
    ctx.saveGState()
    ctx.translateBy(x: 0, y: Double(imageHeight))
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
    ctx.restoreGState()

    // Drawing parameters scaled to image resolution
    let strokeWidth = max(3.0 * scaleX, 3.0)
    let badgeRadius = max(14.0 * scaleX, 16.0)
    let fontSize = max(13.0 * scaleX, 15.0)

    for element in elements {
      let rect = CGRect(
        x: element.frame.origin.x * scaleX,
        y: element.frame.origin.y * scaleY,
        width: element.frame.size.width * scaleX,
        height: element.frame.size.height * scaleY
      )

      // Bounding box
      ctx.setStrokeColor(boxColor)
      ctx.setLineWidth(strokeWidth)
      ctx.stroke(rect)

      // Semi-transparent fill
      ctx.setFillColor(boxFill)
      ctx.fill(rect)

      // Numbered badge at top-left corner
      let badgeCenterX = rect.origin.x + badgeRadius + 2
      let badgeCenterY = rect.origin.y + badgeRadius + 2
      let badgeRect = CGRect(
        x: badgeCenterX - badgeRadius,
        y: badgeCenterY - badgeRadius,
        width: badgeRadius * 2,
        height: badgeRadius * 2
      )

      // Badge background
      ctx.setFillColor(badgeColor.cgColor)
      ctx.fillEllipse(in: badgeRect)

      // White border for contrast on dark/red backgrounds
      ctx.setStrokeColor(badgeBorder)
      ctx.setLineWidth(max(2.0 * scaleX, 2.0))
      ctx.strokeEllipse(in: badgeRect)

      // Number text (white, bold)
      let numberString = "\(element.box)" as NSString
      let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.boldSystemFont(ofSize: fontSize),
        .foregroundColor: NSColor.white,
      ]
      let textSize = numberString.size(withAttributes: attributes)
      let textOrigin = CGPoint(
        x: badgeCenterX - textSize.width / 2,
        y: badgeCenterY - textSize.height / 2
      )

      let nsContext = NSGraphicsContext(cgContext: ctx, flipped: true)
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = nsContext
      numberString.draw(at: textOrigin, withAttributes: attributes)
      NSGraphicsContext.restoreGraphicsState()
    }

    // Write output PNG
    guard let outputImage = ctx.makeImage() else {
      throw AnnotatorError.failedToCreateOutput
    }

    let outputURL = URL(fileURLWithPath: outputPath) as CFURL
    guard let destination = CGImageDestinationCreateWithURL(
      outputURL, UTType.png.identifier as CFString, 1, nil
    ) else {
      throw AnnotatorError.failedToWriteOutput(outputPath)
    }
    CGImageDestinationAddImage(destination, outputImage, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw AnnotatorError.failedToWriteOutput(outputPath)
    }
  }

  // MARK: - Build annotated elements from ScreenAnalysis

  static func buildElements(from analysis: ScreenAnalysis) -> [AnnotatedElement] {
    var elements: [AnnotatedElement] = []
    var box = 1

    for tab in analysis.tabs {
      elements.append(AnnotatedElement(
        box: box,
        frame: CGRect(
          x: Double(tab.tapX) - 30, y: Double(tab.tapY) - 20,
          width: 60, height: 40
        ),
        label: tab.label
      ))
      box += 1
    }

    for el in analysis.navigation + analysis.actions + analysis.destructive + analysis.disabled {
      elements.append(annotatedElement(from: el, box: box))
      box += 1
    }

    return elements
  }

  private static func annotatedElement(
    from el: ScreenAnalysis.ClassifiedElement, box: Int
  ) -> AnnotatedElement {
    AnnotatedElement(
      box: box,
      frame: CGRect(
        x: Double(el.tapX) - Double(el.width) / 2,
        y: Double(el.tapY) - Double(el.height) / 2,
        width: Double(el.width),
        height: Double(el.height)
      ),
      label: el.name
    )
  }

  // MARK: - State Persistence

  /// Entry in the box mapping file — maps box number to tap coordinates.
  struct BoxEntry: Codable {
    let box: Int
    let label: String
    let tapX: Int
    let tapY: Int
  }

  /// Persist the box→coordinate mapping so `tap --box N` can use it.
  static func saveBoxMapping(_ elements: [AnnotatedElement], to path: String) throws {
    let entries = elements.map { el in
      BoxEntry(
        box: el.box,
        label: el.label,
        tapX: Int(el.frame.midX),
        tapY: Int(el.frame.midY)
      )
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(entries)
    let dir = (path as NSString).deletingLastPathComponent
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    try data.write(to: URL(fileURLWithPath: path))
  }

  /// Load a previously saved box mapping.
  static func loadBoxMapping(from path: String) throws -> [BoxEntry] {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    return try JSONDecoder().decode([BoxEntry].self, from: data)
  }

  /// Default path for the box mapping state file.
  static var defaultMappingPath: String {
    let dir = ProjectConfig.journalsDirectory()
    return (dir as NSString).appendingPathComponent("last-explore-boxes.json")
  }

  /// Default path for the annotated screenshot.
  static var defaultScreenshotPath: String {
    let dir = ProjectConfig.journalsDirectory()
    return (dir as NSString).appendingPathComponent("last-explore.png")
  }

  // MARK: - Errors

  enum AnnotatorError: Error, LocalizedError {
    case failedToLoadImage(String)
    case failedToCreateContext
    case failedToCreateOutput
    case failedToWriteOutput(String)

    var errorDescription: String? {
      switch self {
      case .failedToLoadImage(let path): "Failed to load image: \(path)"
      case .failedToCreateContext: "Failed to create graphics context"
      case .failedToCreateOutput: "Failed to create output image"
      case .failedToWriteOutput(let path): "Failed to write output: \(path)"
      }
    }
  }
}
