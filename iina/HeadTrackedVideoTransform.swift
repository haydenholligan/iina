//
//  HeadTrackedVideoTransform.swift
//  iina
//
//  Prototype support for using AirPods head pose to transform the video surface.
//

import Cocoa
import CoreMotion

struct HeadTrackedVideoAngles: Equatable {
  let yaw: CGFloat
  let pitch: CGFloat
  let roll: CGFloat

  func clamped(to limit: CGFloat) -> HeadTrackedVideoAngles {
    HeadTrackedVideoAngles(
      yaw: yaw.clamped(to: -limit...limit),
      pitch: pitch.clamped(to: -limit...limit),
      roll: roll.clamped(to: -limit...limit)
    )
  }
}

struct HeadTrackedVideoTransform {
  static let defaultMaximumRotation = CGFloat.pi / 2

  static func transform(for angles: HeadTrackedVideoAngles,
                        in bounds: CGSize? = nil,
                        keepsTextLevel: Bool = true) -> CATransform3D {
    let roll = angles.roll.clamped(to: -defaultMaximumRotation...defaultMaximumRotation)
    let direction: CGFloat = keepsTextLevel ? -1 : 1
    let rotation = direction * roll
    let scale = scaleToFitRotatedRect(in: bounds, rotation: rotation)

    var transform = CATransform3DMakeScale(scale, scale, 1)
    transform = CATransform3DRotate(transform, rotation, 0, 0, 1)
    return transform
  }

  private static func scaleToFitRotatedRect(in bounds: CGSize?, rotation: CGFloat) -> CGFloat {
    guard let bounds = bounds, bounds.width > 0, bounds.height > 0 else { return 1 }
    let sinTheta = abs(sin(rotation))
    let cosTheta = abs(cos(rotation))
    let rotatedWidth = bounds.width * cosTheta + bounds.height * sinTheta
    let rotatedHeight = bounds.width * sinTheta + bounds.height * cosTheta
    return min(bounds.width / rotatedWidth, bounds.height / rotatedHeight, 1)
  }

  static func angles(from attitude: CMAttitude, relativeTo referenceAttitude: CMAttitude) -> HeadTrackedVideoAngles {
    let relativeAttitude = attitude.copy() as! CMAttitude
    relativeAttitude.multiply(byInverseOf: referenceAttitude)
    return HeadTrackedVideoAngles(
      yaw: CGFloat(relativeAttitude.yaw),
      pitch: CGFloat(relativeAttitude.pitch),
      roll: CGFloat(relativeAttitude.roll)
    )
  }
}

@available(macOS 14.0, *)
final class AirPodsHeadTrackedVideoController: NSObject, CMHeadphoneMotionManagerDelegate {
  private let motionManager = CMHeadphoneMotionManager()
  private var referenceAttitude: CMAttitude?
  private let applyAngles: (HeadTrackedVideoAngles?) -> Void
  private let log: (String, Logger.Level) -> Void

  init(applyAngles: @escaping (HeadTrackedVideoAngles?) -> Void, log: @escaping (String, Logger.Level) -> Void) {
    self.applyAngles = applyAngles
    self.log = log
    super.init()
    motionManager.delegate = self
  }

  var isRunning: Bool {
    motionManager.isDeviceMotionActive
  }

  func start() {
    guard motionManager.isDeviceMotionAvailable else {
      log("AirPods head tracking unavailable", .warning)
      return
    }

    referenceAttitude = nil
    motionManager.startConnectionStatusUpdates()
    motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
      guard let self = self else { return }
      if let error = error {
        self.log("AirPods head tracking failed: \(error.localizedDescription)", .warning)
        return
      }
      guard let attitude = motion?.attitude else { return }

      if self.referenceAttitude == nil {
        self.referenceAttitude = attitude.copy() as? CMAttitude
      }
      guard let referenceAttitude = self.referenceAttitude else { return }

      let angles = HeadTrackedVideoTransform.angles(from: attitude, relativeTo: referenceAttitude)
      self.applyAngles(angles)
    }
    log("AirPods head tracking started", .verbose)
  }

  func stop() {
    motionManager.stopDeviceMotionUpdates()
    motionManager.stopConnectionStatusUpdates()
    referenceAttitude = nil
    applyAngles(nil)
    log("AirPods head tracking stopped", .verbose)
  }

  func recenter() {
    referenceAttitude = motionManager.deviceMotion?.attitude.copy() as? CMAttitude
  }

  func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
    log("Head-tracking headphones connected", .verbose)
  }

  func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
    log("Head-tracking headphones disconnected", .warning)
    applyAngles(nil)
  }
}
