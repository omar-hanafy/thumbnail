import Flutter
import UIKit

/// Registers the Pigeon host API for the thumbnail engine.
public class ThumbnailPlugin: NSObject, FlutterPlugin, ThumbnailHostApi {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = ThumbnailPlugin()
    ThumbnailHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
  }

  func extract(request: ExtractRequest, completion: @escaping (Result<ExtractResult, Error>) -> Void) {
    completion(
      .failure(
        PigeonError(
          code: "extractionFailed",
          message: "iOS extractor not implemented yet",
          details: nil
        )
      )
    )
  }

  func cancel(requestId: String) throws {
    // Implemented alongside the extractor.
  }
}
