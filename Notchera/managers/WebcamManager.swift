import AVFoundation
import SwiftUI

class WebcamManager: NSObject, ObservableObject {
    static let shared = WebcamManager()

    @Published var previewLayer: AVCaptureVideoPreviewLayer? {
        didSet {
            objectWillChange.send()
        }
    }

    private var captureSession: AVCaptureSession?
    @Published var isSessionRunning: Bool = false {
        didSet {
            objectWillChange.send()
        }
    }

    @Published var authorizationStatus: AVAuthorizationStatus = .notDetermined {
        didSet {
            objectWillChange.send()
        }
    }

    @Published var cameraAvailable: Bool = false {
        didSet {
            objectWillChange.send()
        }
    }

    private let sessionQueue = DispatchQueue(label: "Notchera.WebcamManager.SessionQueue", qos: .userInitiated)

    private var isCleaningUp: Bool = false

    enum WebcamError: Error, LocalizedError {
        case deviceUnavailable
        case accessDenied
        case configurationFailed(String)

        var errorDescription: String? {
            switch self {
            case .deviceUnavailable:
                "No camera devices available"
            case .accessDenied:
                "Camera access denied"
            case let .configurationFailed(message):
                "Camera configuration failed: \(message)"
            }
        }
    }

    override private init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(deviceWasDisconnected), name: .AVCaptureDeviceWasDisconnected, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(deviceWasConnected), name: .AVCaptureDeviceWasConnected, object: nil)
        checkCameraAvailability()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)

        if let session = captureSession {
            if session.isRunning {
                session.stopRunning()
            }
        }
        captureSession = nil

        previewLayer = nil
    }

    func checkAndRequestVideoAuthorization() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        DispatchQueue.main.async {
            self.authorizationStatus = status
        }

        switch status {
        case .authorized:
            checkCameraAvailability()
        case .notDetermined:
            requestVideoAccess()
        case .denied, .restricted:
            NSLog("Camera access denied or restricted")
        @unknown default:
            NSLog("Unknown authorization status")
        }
    }

    private func requestVideoAccess() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                self?.authorizationStatus = granted ? .authorized : .denied
                if granted {
                    self?.checkCameraAvailability()
                }
            }
        }
    }

    func checkCameraAvailability() {
        let availableDevices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        ).devices

        let hasAvailableDevices = !availableDevices.isEmpty

        DispatchQueue.main.async {
            self.cameraAvailable = hasAvailableDevices
        }
    }

    private func setupCaptureSession(completion: @escaping (Bool) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self else {
                completion(false)
                return
            }

            cleanupExistingSession()

            let session = AVCaptureSession()

            do {
                let discoverySession = AVCaptureDevice.DiscoverySession(
                    deviceTypes: [.external, .builtInWideAngleCamera],
                    mediaType: .video,
                    position: .unspecified
                )

                guard let videoDevice = discoverySession.devices.first else {
                    NSLog("No video devices available")
                    DispatchQueue.main.async {
                        self.isSessionRunning = false
                        self.cameraAvailable = false
                    }
                    completion(false)
                    return
                }

                NSLog("Using camera: \(videoDevice.localizedName)")

                try videoDevice.lockForConfiguration()
                defer { videoDevice.unlockForConfiguration() }

                let videoInput = try AVCaptureDeviceInput(device: videoDevice)
                guard session.canAddInput(videoInput) else {
                    throw NSError(domain: "Notchera.WebcamManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot add video input"])
                }

                session.beginConfiguration()
                session.sessionPreset = .high
                session.addInput(videoInput)

                let videoOutput = AVCaptureVideoDataOutput()
                videoOutput.setSampleBufferDelegate(nil, queue: nil)
                if session.canAddOutput(videoOutput) {
                    session.addOutput(videoOutput)
                }
                session.commitConfiguration()

                captureSession = session

                DispatchQueue.main.async {
                    self.cameraAvailable = true
                    let previewLayer = AVCaptureVideoPreviewLayer(session: session)
                    previewLayer.videoGravity = .resizeAspectFill
                    self.previewLayer = previewLayer

                    completion(true)
                }

                NSLog("Capture session setup completed successfully")
            } catch {
                NSLog("Failed to setup capture session: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isSessionRunning = false
                    self.cameraAvailable = false
                    self.previewLayer = nil
                }
                completion(false)
            }
        }
    }

    private func cleanupExistingSession() {
        if let existingSession = captureSession {
            if existingSession.isRunning {
                existingSession.stopRunning()
            }

            existingSession.beginConfiguration()

            for input in existingSession.inputs {
                existingSession.removeInput(input)
            }
            for output in existingSession.outputs {
                existingSession.removeOutput(output)
            }

            existingSession.commitConfiguration()
            captureSession = nil

            DispatchQueue.main.async {
                self.previewLayer = nil
            }
        }
    }

    @objc private func deviceWasDisconnected(notification _: Notification) {
        NSLog("Camera device was disconnected")
        sessionQueue.async { [weak self] in
            guard let self else { return }
            stopSession()
            DispatchQueue.main.async {
                self.cameraAvailable = false
            }
        }
    }

    @objc private func deviceWasConnected(notification _: Notification) {
        NSLog("Camera device was connected")
        sessionQueue.async { [weak self] in
            guard let self else { return }
            checkCameraAvailability()
        }
    }

    private func updateSessionState() {
        let isRunning = captureSession?.isRunning ?? false
        DispatchQueue.main.async {
            self.isSessionRunning = isRunning
        }
    }

    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            if captureSession == nil {
                setupCaptureSession { success in
                    if success {
                        self.startRunningCaptureSession()
                    }
                }
            } else {
                startRunningCaptureSession()
            }
        }
    }

    private func startRunningCaptureSession() {
        sessionQueue.async { [weak self] in
            guard let self, let session = captureSession, !session.isRunning else {
                return
            }

            session.startRunning()

            updateSessionState()

            NSLog("Capture session started successfully")
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            DispatchQueue.main.async {
                self.isSessionRunning = false
            }

            cleanupExistingSession()

            NSLog("Capture session stopped and cleaned up")
        }
    }
}
