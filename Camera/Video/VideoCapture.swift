//
//  VideoCapture.swift
//  Camera
//
//  Created by Bradley French on 7/3/19.
//  Copyright © 2019 Bradley French. All rights reserved.
//
import AVFoundation
import Foundation
import UIKit

struct VideoSpec {
    var fps: Int32?
    var size: CGSize?
}

typealias ImageBufferHandler = (CVPixelBuffer, CMTime, CVPixelBuffer?) -> Void
typealias SynchronizedDataBufferHandler = (CVPixelBuffer, AVDepthData?, AVMetadataObject?) -> Void

extension AVCaptureDevice {
    func printDepthFormats() {
        formats.forEach { (format) in
            let depthFormats = format.supportedDepthDataFormats
            if depthFormats.count > 0 {
                print("format: \(format), supported depth formats: \(depthFormats)")
            }
        }
    }
}

class VideoCapture: NSObject {
    
    private let captureSession = AVCaptureSession()
    private var videoDevice: AVCaptureDevice!
    private var videoConnection: AVCaptureConnection!
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    let dataOutputQueue = DispatchQueue(label: "video data queue",
                                        qos: .userInitiated,
                                        attributes: [],
                                        autoreleaseFrequency: .workItem)
    
    var imageBufferHandler: ImageBufferHandler?
    var syncedDataBufferHandler: SynchronizedDataBufferHandler?
    
    private var dataOutputSynchronizer: AVCaptureDataOutputSynchronizer!
    
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let audioDataOutput = AVCaptureAudioDataOutput()
    private let depthDataOutput = AVCaptureDepthDataOutput()
    private let metadataOutput = AVCaptureMetadataOutput()
    
    private var cameraMode:CameraMode!
    private var videoWriter:AVAssetWriter!
    private var videoWriterInput:AVAssetWriterInput!
    private var audioWriterInput:AVAssetWriterInput!
    private var isRecording:Bool = false
    private var sessionAtSourceTime:CMTime!
    private var videoURL:URL!
    
    init(cameraMode: CameraMode, cameraType: CameraType, preferredSpec: VideoSpec?, previewContainer: CALayer?)
    {
        super.init()
        
        self.cameraMode = cameraMode
        
        captureSession.beginConfiguration()
        
        captureSession.sessionPreset = AVCaptureSession.Preset.photo
        
        setupCaptureVideoDevice(with: cameraType)
        
        // setup preview
        if let previewContainer = previewContainer {
            let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer.frame = previewContainer.bounds
            previewLayer.contentsGravity = CALayerContentsGravity.resizeAspectFill
            previewLayer.videoGravity = .resizeAspectFill
            previewContainer.insertSublayer(previewLayer, at: 0)
            self.previewLayer = previewLayer
        }
        
        // setup outputs
        do {
            // video output
            videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            
            videoDataOutput.setSampleBufferDelegate(self, queue: dataOutputQueue)
            guard captureSession.canAddOutput(videoDataOutput) else { fatalError() }
            captureSession.addOutput(videoDataOutput)
            videoConnection = videoDataOutput.connection(with: .video)
            
            // depth output
            guard captureSession.canAddOutput(depthDataOutput) else { fatalError() }
            captureSession.addOutput(depthDataOutput)
            depthDataOutput.setDelegate(self, callbackQueue: dataOutputQueue)
            depthDataOutput.isFilteringEnabled = false
            guard let connection = depthDataOutput.connection(with: .depthData) else { fatalError() }
            connection.isEnabled = true
            
            // metadata output
            guard captureSession.canAddOutput(metadataOutput) else { fatalError() }
            captureSession.addOutput(metadataOutput)
            if metadataOutput.availableMetadataObjectTypes.contains(.face) {
                metadataOutput.metadataObjectTypes = [.face]
            }
            
            // synchronize outputs
            dataOutputSynchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [videoDataOutput, depthDataOutput, metadataOutput])
            dataOutputSynchronizer.setDelegate(self, queue: dataOutputQueue)
            
            // Setup Writer
            do {
                let outputFileLocation = videoFileLocation()
                videoWriter = try AVAssetWriter(outputURL: outputFileLocation, fileType: AVFileType.mov)
                
                // add video input
                videoWriterInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: [
                    AVVideoCodecKey : AVVideoCodecType.h264,
                    AVVideoWidthKey : 720,
                    AVVideoHeightKey : 1280,
                    AVVideoCompressionPropertiesKey : [
                        AVVideoAverageBitRateKey : 2300000,
                    ],
                    ])
                
                videoWriterInput.expectsMediaDataInRealTime = true
                
                if videoWriter.canAdd(videoWriterInput) {
                    videoWriter.add(videoWriterInput)
                    print("video input added")
                } else {
                    print("no input added")
                }
                
                // add audio input
                audioWriterInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: nil)
                
                audioWriterInput.expectsMediaDataInRealTime = true
                
                if videoWriter.canAdd(audioWriterInput!) {
                    videoWriter.add(audioWriterInput!)
                    print("audio input added")
                }
                
            } catch let error {
                debugPrint(error.localizedDescription)
            }
        }
        
        setupConnections(with: cameraType)
        
        captureSession.commitConfiguration()
    }
    
    func canWrite() -> Bool {
        print("Recording: \(isRecording) -- VWIsNil: \(videoWriter != nil) -- status: \(videoWriter.status)")
        return isRecording && videoWriter != nil && videoWriter?.status == .writing
    }
    
    
    //video file location method
    func videoFileLocation() -> URL {
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] as NSString
        let videoOutputUrl = URL(fileURLWithPath: documentsPath.appendingPathComponent("videoFile")).appendingPathExtension("mov")
        do {
            if FileManager.default.fileExists(atPath: videoOutputUrl.path) {
                try FileManager.default.removeItem(at: videoOutputUrl)
                print("file removed")
            }
        } catch {
            print(error)
        }
        
        return videoOutputUrl
    }
    
    private func setupCaptureVideoDevice(with cameraType: CameraType) {
        
        videoDevice = cameraType.captureDevice()
        print("selected video device: \(String(describing: videoDevice))")
        
        videoDevice.selectDepthFormat()
        
        captureSession.inputs.forEach { (captureInput) in
            captureSession.removeInput(captureInput)
        }
        let videoDeviceInput = try! AVCaptureDeviceInput(device: videoDevice)
        guard captureSession.canAddInput(videoDeviceInput) else { fatalError() }
        captureSession.addInput(videoDeviceInput)
    }
    
    private func setupConnections(with cameraType: CameraType) {
        videoConnection = videoDataOutput.connection(with: .video)!
        let depthConnection = depthDataOutput.connection(with: .depthData)
        switch cameraType {
        case .front:
            videoConnection.isVideoMirrored = true
            depthConnection?.isVideoMirrored = true
        default:
            break
        }
        videoConnection.videoOrientation = .portrait
        depthConnection?.videoOrientation = .portrait
    }
    
    func startCapture() {
        print("\(self.classForCoder)/" + #function)
        if captureSession.isRunning {
            print("already running")
            return
        }
        captureSession.startRunning()
    }
    
    func stopCapture() {
        print("\(self.classForCoder)/" + #function)
        if !captureSession.isRunning {
            print("already stopped")
            return
        }
        captureSession.stopRunning()
    }
    
    func resizePreview() {
        if let previewLayer = previewLayer {
            guard let superlayer = previewLayer.superlayer else {return}
            previewLayer.frame = superlayer.bounds
        }
    }
    
    func changeCamera(with cameraType: CameraType) {
        let wasRunning = captureSession.isRunning
        if wasRunning {
            captureSession.stopRunning()
        }
        captureSession.beginConfiguration()
        
        setupCaptureVideoDevice(with: cameraType)
        setupConnections(with: cameraType)
        
        captureSession.commitConfiguration()
        
        if wasRunning {
            captureSession.startRunning()
        }
    }
    
    func setDepthFilterEnabled(_ enabled: Bool) {
        depthDataOutput.isFilteringEnabled = enabled
    }
    
    func setCameraMode(cameraMode: CameraMode) {
        self.cameraMode = cameraMode
    }
    
    func isVideoRecording() -> Bool {
        return isRecording
    }
    
    func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        sessionAtSourceTime = nil
        videoWriter.startWriting()
        print(isRecording)
        print(videoWriter)
        if videoWriter.status == .writing {
            print("status writing")
        } else if videoWriter.status == .failed {
            print("status failed")
        } else if videoWriter.status == .cancelled {
            print("status cancelled")
        } else if videoWriter.status == .unknown {
            print("status unknown")
        } else {
            print("status completed")
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        videoWriterInput.markAsFinished()
        print("marked as finished")
        videoWriter.finishWriting {
            
        }
        print("finished writing \(videoWriter.outputURL)")
        videoURL = videoWriter.outputURL
        captureSession.stopRunning()
    }
    
    func getVideoURL() -> URL {
        return videoURL
    }
}

extension VideoCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        //        print("\(self.classForCoder)/" + #function)
    }
    
    // synchronizer使ってる場合は呼ばれない
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if let imageBufferHandler = imageBufferHandler, connection == videoConnection
        {
            guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { fatalError() }
            
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            imageBufferHandler(imageBuffer, timestamp, nil)
        }
    }
}

extension VideoCapture: AVCaptureDepthDataOutputDelegate {
    
    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didDrop depthData: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection, reason: AVCaptureOutput.DataDroppedReason) {
        print("\(self.classForCoder)/\(#function)")
    }
    
    // synchronizer使ってる場合は呼ばれない
    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection) {
        print("\(self.classForCoder)/\(#function)")
    }
}

extension VideoCapture: AVCaptureDataOutputSynchronizerDelegate {
    
    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer, didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        
        guard let syncedVideoData = synchronizedDataCollection.synchronizedData(for: videoDataOutput) as? AVCaptureSynchronizedSampleBufferData else { return }
        guard !syncedVideoData.sampleBufferWasDropped else {
            print("dropped video:\(syncedVideoData)")
            return
        }
        let videoSampleBuffer = syncedVideoData.sampleBuffer
        print(videoSampleBuffer)
        
        let syncedDepthData = synchronizedDataCollection.synchronizedData(for: depthDataOutput) as? AVCaptureSynchronizedDepthData
        var depthData = syncedDepthData?.depthData
        if let syncedDepthData = syncedDepthData, syncedDepthData.depthDataWasDropped {
            print("dropped depth:\(syncedDepthData)")
            depthData = nil
        }
        
        // 顔のある位置のしきい値を求める
        let syncedMetaData = synchronizedDataCollection.synchronizedData(for: metadataOutput) as? AVCaptureSynchronizedMetadataObjectData
        var face: AVMetadataObject? = nil
        if let firstFace = syncedMetaData?.metadataObjects.first {
            face = videoDataOutput.transformedMetadataObject(for: firstFace, connection: videoConnection)
        }
        guard let imagePixelBuffer = CMSampleBufferGetImageBuffer(videoSampleBuffer) else { fatalError() }
        
        syncedDataBufferHandler?(imagePixelBuffer, depthData, face)
        
        /*
         if self.cameraMode == CameraMode.video {
         let writable = canWrite()
         
         if writable, sessionAtSourceTime == nil {
         // start writing
         sessionAtSourceTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
         videoWriter.startSession(atSourceTime: sessionAtSourceTime)
         print("Writing")
         }
         
         if output == videoDataOutput {
         connection.videoOrientation = .portrait
         
         if connection.isVideoMirroringSupported {
         connection.isVideoMirrored = true
         }
         }
         
         if writable,
         output == videoDataOutput,
         (videoWriterInput.isReadyForMoreMediaData) {
         // write video buffer
         videoWriterInput.append(sampleBuffer)
         //print("video buffering")
         } else if writable,
         output == audioDataOutput,
         (audioWriterInput.isReadyForMoreMediaData) {
         // write audio buffer
         audioWriterInput?.append(sampleBuffer)
         //print("audio buffering")
         }
         }*/
    }
}
