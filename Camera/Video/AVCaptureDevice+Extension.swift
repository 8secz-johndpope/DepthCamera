//
//  AVCaptureDevice+Extension.swift
//
//  Created by Bradley French on 7/3/19.
//  Copyright © 2019 Bradley French. All rights reserved.
//
import AVFoundation

extension AVCaptureDevice {
    private func formatWithHighestResolution(_ availableFormats: [AVCaptureDevice.Format]) -> AVCaptureDevice.Format?
    {
        var maxWidth: Int32 = 0
        var selectedFormat: AVCaptureDevice.Format?
        for format in availableFormats {
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let width = dimensions.width
            if width >= maxWidth {
                maxWidth = width
                selectedFormat = format
            }
        }
        return selectedFormat
    }
    
    func selectDepthFormat() {
        let availableFormats = formats.filter { format -> Bool in
            let validDepthFormats = format.supportedDepthDataFormats.filter{ depthFormat in
                return CMFormatDescriptionGetMediaSubType(depthFormat.formatDescription) == kCVPixelFormatType_DepthFloat32
            }
            return validDepthFormats.count > 0
        }
        guard let selectedFormat = formatWithHighestResolution(availableFormats) else { fatalError() }
        
        let depthFormats = selectedFormat.supportedDepthDataFormats
        print(depthFormats)
        let depth32formats = depthFormats.filter {
            CMFormatDescriptionGetMediaSubType($0.formatDescription) == kCVPixelFormatType_DepthFloat32
        }
        guard !depth32formats.isEmpty else { fatalError() }
        let selectedDepthFormat = depth32formats.max(by: {
            CMVideoFormatDescriptionGetDimensions($0.formatDescription).width
                < CMVideoFormatDescriptionGetDimensions($1.formatDescription).width
        })!
        
        print("selected format: \(selectedFormat), depth format: \(selectedDepthFormat)")
        try! lockForConfiguration()
        activeFormat = selectedFormat
        activeDepthDataFormat = selectedDepthFormat
        unlockForConfiguration()
    }
}
