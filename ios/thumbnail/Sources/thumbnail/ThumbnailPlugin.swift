import Flutter
import UIKit

/// Registers the Pigeon host API for the thumbnail engine.
public class ThumbnailPlugin: NSObject, FlutterPlugin, ThumbnailHostApi {
  private let extractor = Extractor()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = ThumbnailPlugin()
    ThumbnailHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
  }

  func extract(request: ExtractRequest, completion: @escaping (Result<ExtractResult, Error>) -> Void) {
    extractor.extract(request: request, completion: completion)
  }

  func cancel(requestId: String) throws {
    extractor.cancel(requestId: requestId)
  }
}
