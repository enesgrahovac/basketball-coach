import SwiftUI
import AVFoundation
import Foundation

struct CameraRecorder: UIViewControllerRepresentable {
    var onRecordingComplete: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> CameraRecorderViewController {
        let controller = CameraRecorderViewController()
        controller.onRecordingComplete = onRecordingComplete
        controller.onDismiss = { dismiss() }
        return controller
    }
    
    func updateUIViewController(_ uiViewController: CameraRecorderViewController, context: Context) {}
}

class CameraRecorderViewController: UIViewController {
    var onRecordingComplete: ((URL) -> Void)?
    var onDismiss: (() -> Void)?
    
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureMovieFileOutput?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var recordingTimer: Timer?
    private var countdownTimer: Timer?
    private var recordingTimeLeft: Int = 15
    private var countdownTimeLeft: Int = 3
    private var isRecording = false
    private var isCountingDown = false
    private var wasCancelled = false
    
    // UI Elements
    private lazy var previewView: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var recordButton: UIButton = {
        let button = UIButton(type: .custom)
        button.backgroundColor = .red
        button.layer.cornerRadius = 35
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(recordButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var cancelButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Cancel", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .medium)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(cancelButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var timerLabel: UILabel = {
        let label = UILabel()
        label.textColor = .white
        label.font = .systemFont(ofSize: 24, weight: .bold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var countdownLabel: UILabel = {
        let label = UILabel()
        label.textColor = .white
        label.font = .systemFont(ofSize: 72, weight: .bold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()
    
    private lazy var instructionLabel: UILabel = {
        let label = UILabel()
        label.text = "Tap to start recording (15 seconds)"
        label.textColor = .white
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupCamera()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopRecording()
        captureSession?.stopRunning()
    }
    
    private func setupUI() {
        view.backgroundColor = .black
        
        view.addSubview(previewView)
        view.addSubview(recordButton)
        view.addSubview(cancelButton)
        view.addSubview(timerLabel)
        view.addSubview(countdownLabel)
        view.addSubview(instructionLabel)
        
        NSLayoutConstraint.activate([
            // Preview view
            previewView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -120),
            
            // Record button
            recordButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            recordButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            recordButton.widthAnchor.constraint(equalToConstant: 70),
            recordButton.heightAnchor.constraint(equalToConstant: 70),
            
            // Cancel button
            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            cancelButton.centerYAnchor.constraint(equalTo: recordButton.centerYAnchor),
            
            // Timer label
            timerLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            timerLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            // Countdown label
            countdownLabel.centerXAnchor.constraint(equalTo: previewView.centerXAnchor),
            countdownLabel.centerYAnchor.constraint(equalTo: previewView.centerYAnchor),
            
            // Instruction label
            instructionLabel.bottomAnchor.constraint(equalTo: recordButton.topAnchor, constant: -20),
            instructionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
        
        updateTimerLabel()
    }
    
    private func setupCamera() {
        guard let captureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("Failed to get camera device")
            return
        }
        
        guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
            print("Failed to get audio device")
            return
        }
        
        do {
            let captureSession = AVCaptureSession()
            captureSession.sessionPreset = .high
            
            // Video input
            let videoInput = try AVCaptureDeviceInput(device: captureDevice)
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
            }
            
            // Audio input
            let audioInput = try AVCaptureDeviceInput(device: audioDevice)
            if captureSession.canAddInput(audioInput) {
                captureSession.addInput(audioInput)
            }
            
            // Movie file output
            let movieOutput = AVCaptureMovieFileOutput()
            if captureSession.canAddOutput(movieOutput) {
                captureSession.addOutput(movieOutput)
                
                // Set maximum recording duration
                movieOutput.maxRecordedDuration = CMTime(seconds: 15, preferredTimescale: 1)
            }
            
            self.captureSession = captureSession
            self.videoOutput = movieOutput
            
            // Setup preview layer
            let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer.videoGravity = .resizeAspectFill
            self.previewLayer = previewLayer
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                previewLayer.frame = self.previewView.bounds
                self.previewView.layer.addSublayer(previewLayer)
            }
            
            DispatchQueue.global(qos: .userInitiated).async {
                captureSession.startRunning()
            }
            
        } catch {
            print("Error setting up camera: \(error)")
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = previewView.bounds
    }
    
    @objc private func recordButtonTapped() {
        if isRecording {
            // User tapped to stop recording - this is completion, not cancellation
            stopRecording()
        } else {
            startCountdown()
        }
    }
    
    @objc private func cancelButtonTapped() {
        wasCancelled = true
        stopRecording()
        onDismiss?()
    }
    
    private func startCountdown() {
        isCountingDown = true
        countdownTimeLeft = 3
        countdownLabel.isHidden = false
        instructionLabel.isHidden = true
        recordButton.isEnabled = false
        
        updateCountdownLabel()
        
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            
            self.countdownTimeLeft -= 1
            
            if self.countdownTimeLeft <= 0 {
                timer.invalidate()
                self.countdownLabel.isHidden = true
                self.startRecording()
            } else {
                self.updateCountdownLabel()
            }
        }
    }
    
    private func updateCountdownLabel() {
        countdownLabel.text = "\(countdownTimeLeft)"
        
        // Add animation
        countdownLabel.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.5) {
            self.countdownLabel.transform = .identity
        }
    }
    
    private func startRecording() {
        guard let videoOutput = videoOutput, !isRecording else { return }
        
        isCountingDown = false
        isRecording = true
        recordingTimeLeft = 15
        wasCancelled = false  // Reset cancellation flag
        
        // Update UI
        recordButton.backgroundColor = .systemBlue
        recordButton.isEnabled = true
        instructionLabel.text = "Recording... Tap to stop"
        instructionLabel.isHidden = false
        cancelButton.setTitle("Cancel", for: .normal)
        
        // Create temporary file URL
        let tempDir = NSTemporaryDirectory()
        let fileName = "basketball_recording_\(UUID().uuidString).mov"
        let fileURL = URL(fileURLWithPath: tempDir).appendingPathComponent(fileName)
        
        // Start recording
        videoOutput.startRecording(to: fileURL, recordingDelegate: self)
        
        // Start timer
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            
            self.recordingTimeLeft -= 1
            self.updateTimerLabel()
            
            if self.recordingTimeLeft <= 0 {
                self.stopRecording()
            }
        }
        
        updateTimerLabel()
    }
    
    private func stopRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        countdownTimer?.invalidate()
        countdownTimer = nil
        
        if isRecording {
            videoOutput?.stopRecording()
        }
        
        isRecording = false
        isCountingDown = false
        
        // Reset UI
        recordButton.backgroundColor = .red
        recordButton.isEnabled = true
        instructionLabel.text = "Tap to start recording (15 seconds)"
        instructionLabel.isHidden = false
        countdownLabel.isHidden = true
        cancelButton.setTitle("Cancel", for: .normal)
        recordingTimeLeft = 15
        updateTimerLabel()
    }
    
    private func updateTimerLabel() {
        if isRecording {
            timerLabel.text = "Recording: \(recordingTimeLeft)s"
            timerLabel.textColor = .red
        } else {
            timerLabel.text = "Ready to record"
            timerLabel.textColor = .white
        }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate
extension CameraRecorderViewController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        
        if let error = error {
            print("Recording error: \(error)")
            // Clean up the file if it was created
            try? FileManager.default.removeItem(at: outputFileURL)
            return
        }
        
        // Only proceed if the recording wasn't cancelled
        if wasCancelled {
            print("Recording was cancelled, cleaning up file at: \(outputFileURL)")
            // Clean up the recorded file since user cancelled
            try? FileManager.default.removeItem(at: outputFileURL)
            return
        }
        
        print("Recording finished successfully at: \(outputFileURL)")
        
        DispatchQueue.main.async { [weak self] in
            self?.onRecordingComplete?(outputFileURL)
        }
    }
}
