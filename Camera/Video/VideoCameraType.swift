//
//  VideoCameraType.swift
//
//  Created by Bradley French on 7/3/19.
//  Copyright © 2019 Bradley French. All rights reserved.
//
import AVFoundation

enum CameraType {
    case back(Bool)
    case front(Bool)
    
    func captureDevice() -> AVCaptureDevice {
        let devices: [AVCaptureDevice]
        switch self {
        case .front(let requireDepth):
            var deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInTrueDepthCamera]
            if !requireDepth {
                deviceTypes.append(.builtInWideAngleCamera)
            }
            devices = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: .video, position: .front).devices
        case .back(let requireDepth):
            var deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInDualCamera]
            if !requireDepth {
                deviceTypes.append(contentsOf: [.builtInWideAngleCamera, .builtInTelephotoCamera])
            }
            devices = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: .video, position: .back).devices
        }
        guard let device = devices.first else {
            return AVCaptureDevice.default(for: .video)!
        }
        return device
    }
}
