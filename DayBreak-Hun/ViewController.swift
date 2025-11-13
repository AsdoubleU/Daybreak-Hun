import UIKit
import SwiftUI
import Combine
import CoreBluetooth
import CoreMotion
import Foundation
import CoreHaptics

let motionManager = CMMotionManager()

class ViewController: UIViewController, CBPeripheralManagerDelegate {
    
    @IBOutlet var imgLogo: UIImageView!
    @IBOutlet var imgFrame: UIImageView!
    @IBOutlet var lblSystem: UILabel!
    
    private var peripheralManager: CBPeripheralManager!
    private var transferCharacteristic: CBMutableCharacteristic!
    private var hapticEngine: CHHapticEngine?
    
    let TRANSFER_SERVICE_UUID = CBUUID(string: "A4F5C001-A42A-4340-91B0-C2C9034E45B9")
    let TRANSFER_CHARACTERISTIC_UUID = CBUUID(string: "A4F5C002-A42A-4340-91B0-C2C9034E45B9")
    
    private var dataStorage: Data?
    private var notifyTimer: Timer?
    private var sampleCounter: Float = 0.0
    
    private var mode: UInt8?
    private var vibration: Float?
    private var command: [Float]?
    private var mode_flag: Bool?
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        self.command = [0, 0, 0, 0, 0, 0]
        
        imgLogo.image = UIImage(named: "HRRLabLogo.png")
        imgFrame.image = UIImage(named: "Frame.png")
        lblSystem.text = "The system is not connected yet!"
        
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        
        let left_x: CGFloat
        let left_y: CGFloat
        let right_x: CGFloat
        let right_y: CGFloat
        
        if UIDevice.current.userInterfaceIdiom == .pad { left_x = 50; left_y = -50; right_x = -50; right_y = -50; } // iPad layout
        else { left_x = 106; left_y = -260; right_x = -106; right_y = -40; } // iPhone layout
        
        let joystickViewLeft = JoystickView(onJoystickChange: { [weak self] x, y in self?.handleJoystickInputLeft(x: x, y: y) })
                
        let hostingControllerLeft = UIHostingController(rootView: joystickViewLeft)
        addChild(hostingControllerLeft)
        view.addSubview(hostingControllerLeft.view)
                
        hostingControllerLeft.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingControllerLeft.view.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: left_x),
            hostingControllerLeft.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: left_y),
            hostingControllerLeft.view.widthAnchor.constraint(equalToConstant: JOYSTICK_SIZE),
            hostingControllerLeft.view.heightAnchor.constraint(equalToConstant: JOYSTICK_SIZE)
        ])
        hostingControllerLeft.didMove(toParent: self)
                
        let joystickViewRight = JoystickView(onJoystickChange: { [weak self] x, y in self?.handleJoystickInputRight(x: x, y: y)})
                
        let hostingControllerRight = UIHostingController(rootView: joystickViewRight)
        addChild(hostingControllerRight)
        view.addSubview(hostingControllerRight.view)

        hostingControllerRight.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingControllerRight.view.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: right_x),
            hostingControllerRight.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: right_y),
            hostingControllerRight.view.widthAnchor.constraint(equalToConstant: JOYSTICK_SIZE),
            hostingControllerRight.view.heightAnchor.constraint(equalToConstant: JOYSTICK_SIZE)
        ])
        hostingControllerRight.didMove(toParent: self)
        
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            hapticEngine = try CHHapticEngine()
            try hapticEngine?.start()
        }
        catch { print("Haptic Engine Error: \(error.localizedDescription)") }

    }

    private func handleJoystickInputLeft(x: Float, y: Float)
    {
        self.command?[0] = y
        self.command?[1] = -x
    }
    
    private func handleJoystickInputRight(x: Float, y: Float)
    {
        self.command?[2] = y
        self.command?[5] = -x
    }
    
    private func setupService()
    {
        transferCharacteristic = CBMutableCharacteristic(type: TRANSFER_CHARACTERISTIC_UUID, properties: [.read, .write, .notify],
            value: nil, permissions: [.readable, .writeable] )
        
        let transferService = CBMutableService(type: TRANSFER_SERVICE_UUID, primary: true)
        transferService.characteristics = [transferCharacteristic]
        peripheralManager.add(transferService)
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager)
    {
        switch peripheral.state
        {
        case .poweredOn:
            print("Bluetooth on!")
            setupService()
        case .poweredOff:
            print("Bluetooth off!")
            peripheral.stopAdvertising()
        case .unauthorized:
            print("Access denied.")
        case .unsupported:
            print("BLE Peripheral unsupported device.")
        default:
            print("Unknown Bluetooth state: \(peripheral.state.rawValue)")
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?)
    {
        if peripheralManager.isAdvertising { peripheralManager.stopAdvertising() }
        let advertisementData: [String: Any] = [CBAdvertisementDataServiceUUIDsKey: [TRANSFER_SERVICE_UUID], CBAdvertisementDataLocalNameKey: "Daybreak-Hun"]
        peripheralManager.startAdvertising(advertisementData)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest)
    {
        guard let commandArray = self.command else {
            self.peripheralManager.respond(to: request, withResult: .invalidOffset)
            return
        }

        var dataToSend = Data()
                    
        commandArray.forEach { f in
            var littleEndianPattern = f.bitPattern.littleEndian
            dataToSend.append(Data(bytes: &littleEndianPattern, count: MemoryLayout<UInt32>.size))
        }

        if request.characteristic.uuid == transferCharacteristic.uuid {
            if request.offset > dataToSend.count {
                self.peripheralManager.respond(to: request, withResult: .invalidOffset)
                return
            }
            request.value = dataToSend.subdata(in: request.offset..<dataToSend.count)
            self.peripheralManager.respond(to: request, withResult: .success)
        }
        else { self.peripheralManager.respond(to: request, withResult: .readNotPermitted) }
            
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest])
    {
        
        for request in requests {
            if request.characteristic.uuid == transferCharacteristic.uuid, let data = request.value, data.count == 8 {
                
                (mode, vibration) = data.withUnsafeBytes {
                    ptr -> (UInt8, Float) in
                    let basePointer = ptr.baseAddress!
                    let mode = basePointer.assumingMemoryBound(to: UInt8.self).pointee
                    let floatBitPattern = (basePointer + MemoryLayout<UInt8>.size).assumingMemoryBound(to: UInt32.self).pointee
                    let correctedBitPattern = floatBitPattern.littleEndian
                    let vibration = Float(bitPattern: correctedBitPattern)
                    return (mode, vibration)
                }
                
                // Save mode
                if mode == 0 { lblSystem.text = "[Mode]INIT" }
                else if mode == 1 { lblSystem.text = "[Mode] GRAVITYCOMPENSATION" }
                else if mode == 2 { lblSystem.text = "[Mode] HOMING" }
                else if mode == 3 { lblSystem.text = "[Mode] TASK SPACE TRANSITION" }
                else if mode == 4 { lblSystem.text = "[Mode] TASK SPACE CONTROL" }
                else if mode == 5 { lblSystem.text = "[Mode] WHOLE BODY TRANSITION" }
                else if mode == 6 { lblSystem.text = "[Mode] WHOLE BODY CONTROL STAND" }
                else if mode == 7 { lblSystem.text = "[Mode] WHOLE BODY CONTROL WALKING" }
                else if mode == 8 { lblSystem.text = "[Mode] UNIFIED LOCOMOTION TRIPOD" }
                else if mode == 9 { lblSystem.text = "[Mode] UNIFIED LOCOMOTION RIPPLE" }
                else if mode == 10 { lblSystem.text = "[Mode] UNIFIED LOCOMOTION WAVE" }
                else if mode == 11 { lblSystem.text = "[Mode] INVERSE KINEMATICS" }
                else if mode == 12 { lblSystem.text = "[Mode] IK WALKING PATTERN" }
                else if mode == 13 { lblSystem.text = "[Mode] FINISH" }
                else { lblSystem.text = "Invalid SThexa Mode! Please Update!" }
                
                // IMU sensor
                if mode == 6 {
                    if motionManager.isDeviceMotionAvailable {
                        
                        motionManager.deviceMotionUpdateInterval = 0.1
                        motionManager.startDeviceMotionUpdates(to: OperationQueue.main) { (data, error) in
                            
                            guard let data = data, error == nil else { return }
                            
                            let attitude = data.attitude
                            self.command?[3] = Float(attitude.roll)
                            self.command?[4] = Float(attitude.pitch)
                            // let yaw = attitude.yaw * 180 / .pi

                            // print(String(format: "Roll: %.2f°, Pitch: %.2f°, Yaw: %.2f°", roll, pitch, yaw))
                        }
                    }
                    else { print("IMU unsupported device!") }
                }
                else {
                    command?[3] = 0
                    command?[4] = 0
                    motionManager.stopDeviceMotionUpdates()
                }
                
                // Vibration
                
                if (self.vibration ?? 0.0) <= 0 { return }
                var events = [CHHapticEvent]()
                        
                let intensityParam = CHHapticEventParameter(parameterID: .hapticIntensity, value: (self.vibration ?? 0.0))
                let sharpnessParam = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.1)
                        
                // let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensityParam, sharpnessParam], relativeTime: 0)
                let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [intensityParam, sharpnessParam],relativeTime: 0, duration: 0.5)
                events.append(event)
                        
                do {
                    let pattern = try CHHapticPattern(events: events, parameters: [])
                    let player = try hapticEngine?.makePlayer(with: pattern)
                    try player?.start(atTime: 0)
                }
                catch { print("Failed to play haptic: \(error.localizedDescription)") }
                
                peripheralManager.respond(to: requests.first!, withResult: .success)

            }
            else { peripheralManager.respond(to: requests.first!, withResult: .invalidAttributeValueLength) }
            
        }
        
        peripheralManager.respond(to: requests.first!, withResult: .success)
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic)
    {
        notifyTimer?.invalidate()
            notifyTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                
                guard let self = self, let commandArray = self.command else { return }
                let isModeUpdate = self.mode_flag ?? false
                
                self.sampleCounter += 0.1

                var dataToSend = Data()
                commandArray.forEach
                { f in var littleEndianPattern = f.bitPattern.littleEndian
                    dataToSend.append(Data(bytes: &littleEndianPattern, count: MemoryLayout<UInt32>.size)) }

                if !self.peripheralManager.updateValue(dataToSend, for: self.transferCharacteristic, onSubscribedCentrals: nil) { print("Failed to send datas") }
                if isModeUpdate {
                    self.command?[0] = 0
                    self.mode_flag = false
                }
            }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic)
    {
        notifyTimer?.invalidate()
        notifyTimer = nil
        lblSystem.text = "The system is not connected yet!"
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didRetrievePeripherals peripherals: [CBPeripheral])
    {
        notifyTimer?.invalidate()
        notifyTimer = nil
        lblSystem.text = "The system is not connected yet!"
    }
    
    @IBAction func updateMode(_ sender: Any) {
        self.mode_flag = true
        self.command?[0] = 100
    }
}
