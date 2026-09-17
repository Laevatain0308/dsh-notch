//
//  AppResources.swift
//  DshNotch
//
//  Where the idle clips are, in an application or in a development build.
//
//  SwiftPM generates an accessor that looks for its resource bundle beside the
//  executable and at the build directory it was compiled in. Neither survives
//  being packaged: an application keeps its resources in `Contents/Resources`,
//  and the build directory may not exist at all on the machine that runs it. So
//  this looks where an application keeps them first, and where a development
//  build does second.
//

import Foundation

/// The bundle that holds the overlay's own resources.
enum AppResources {
  /// The resource bundle, wherever this copy of the program keeps it.
  static let bundle: Bundle = {
    let name = "DshNotch_DshNotch.bundle"
    let candidates = [
      // An application: `Notch.app/Contents/Resources/…`
      Bundle.main.resourceURL?.appendingPathComponent(name),
      // A development build: the bundle sits beside the executable, which is
      // what `Bundle.main.bundleURL` is for a program that is not in one.
      Bundle.main.bundleURL.appendingPathComponent(name),
    ]
    for candidate in candidates {
      if let candidate, let bundle = Bundle(url: candidate) { return bundle }
    }
    // Nothing found is worth reporting rather than crashing: the overlay draws
    // without its idle clips, and everything else about it still works.
    FileHandle.standardError.write(Data("notch: could not find \(name); idle clips will be missing\n".utf8))
    return Bundle.main
  }()

  /// A resource inside that bundle.
  /// - Parameters:
  ///   - name: the file's name, without extension.
  ///   - extension: the file's extension.
  ///   - directory: the subdirectory it lives in.
  /// - Returns: the URL, or nothing when it is not there.
  static func url(_ name: String, _ extension: String, in directory: String) -> URL? {
    bundle.url(forResource: name, withExtension: `extension`, subdirectory: directory)
  }
}
