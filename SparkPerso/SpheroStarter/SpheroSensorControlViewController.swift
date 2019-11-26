//
//  SensorControlViewController.swift
//  SparkPerso
//
//  Created by AL on 01/09/2019.
//  Copyright © 2019 AlbanPerli. All rights reserved.
//

import UIKit
import simd
import AVFoundation
import SocketIO

class SpheroSensorControlViewController: UIViewController {
    
    struct dataValueForm : Codable {
        let values:[[Double]]
    }
    struct ListDataValues:Codable {
        let element:[String:dataValueForm]
    }
    
    enum Classes:Int {
        case Horizontal,Vague,Cercle,Vertical
        
        func neuralNetResponse() -> [Double] {
            switch self {
            case .Horizontal: return [1.0,0.0,0.0,0.0]
            case .Vague: return [0.0,1.0,0.0,0.0]
            case .Cercle: return [0.0,0.0,1.0,0.0]
            case .Vertical: return [0.0,0.0,0.0,1.0]
            }
        }
        
    }
    
    var neuralNet:FFNN? = nil
    let managerFile = FileManager.default
    //33 Good %
    let fileName = "example34"
    let fileNameNeural = "neuralTestOui34"
    
    @IBOutlet weak var gyroChart: GraphView!
    @IBOutlet weak var acceleroChart: GraphView!
    var movementData = [Classes:[[Double]]]()
    var movementDataArray = [Int:dataValueForm]()
    var selectedClass = Classes.Horizontal
    var isRecording = false
    var isPredicting = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        
        if let existNeural = FFNN.fromFile(fileNameNeural) {
            neuralNet = existNeural
            
            if let listMovement = readJson() {
                for movement in listMovement.element {
                    print(movement.key)
                    switch movement.key {
                    case "Horizontal":
                        movementData[.Horizontal] = movement.value.values
                        break
                    case "Vague":
                        movementData[.Vague] = movement.value.values
                        break
                    case "Cercle":
                        movementData[.Cercle] = movement.value.values
                        break
                    case "Vertical":
                        movementData[.Vertical] = movement.value.values
                        break
                    default:
                        print("error")
                    }
                }
            }
        } else {
            print("nothing")
            neuralNet = FFNN(inputs: 3600, hidden: 20, outputs: 4, learningRate: 0.3, momentum: 0.2, weights: nil, activationFunction: .Sigmoid, errorFunction: .default(average: true))
            movementData[.Horizontal] = []
            movementData[.Vague] = []
            movementData[.Cercle] = []
            movementData[.Vertical] = []
        }
        
        var currentAccData = [Double]()
        var currentGyroData = [Double]()
        
        let utterance = AVSpeechUtterance(string: "Kon'nichiwa genkidesu ka?")
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        utterance.rate = 0.4
        
        let synthesizer = AVSpeechSynthesizer()
        synthesizer.speak(utterance)
        
        SharedToyBox.instance.bolt?.sensorControl.enable(sensors: SensorMask.init(arrayLiteral: .accelerometer,.gyro))
        SharedToyBox.instance.bolt?.sensorControl.interval = 1
        SharedToyBox.instance.bolt?.setStabilization(state: SetStabilization.State.off)
        SharedToyBox.instance.bolt?.sensorControl.onDataReady = { data in
            DispatchQueue.main.async {
                
                if self.isRecording || self.isPredicting {
                    if let acceleration = data.accelerometer?.filteredAcceleration {
                        // PAS BIEN!!!
                        currentAccData.append(contentsOf: [acceleration.x!, acceleration.y!, acceleration.z!])
                        
                        let dataToDisplay: double3 = [acceleration.x!, acceleration.y!, acceleration.z!]
                        self.acceleroChart.add(dataToDisplay)
                    }
                    
                    if let gyro = data.gyro?.rotationRate {
                        // TOUJOURS PAS BIEN!!!
                        let rotationRate: double3 = [Double(gyro.x!)/2000.0, Double(gyro.y!)/2000.0, Double(gyro.z!)/2000.0]
                        currentGyroData.append(contentsOf: [Double(gyro.x!), Double(gyro.y!), Double(gyro.z!)])
                        self.gyroChart.add(rotationRate)
                    }
                    
                    if currentAccData.count+currentGyroData.count >= 3600 {
                        print("Data ready for network!")
                        if self.isRecording {
                            self.isRecording = false
                            
                            // Normalisation
                            let minAcc = currentAccData.min()!
                            let maxAcc = currentAccData.max()!
                            let normalizedAcc = currentAccData.map { ($0 - minAcc) / (maxAcc - minAcc) }
                            
                            let minGyr = currentGyroData.min()!
                            let maxGyr = currentGyroData.max()!
                            let normalizedGyr = currentGyroData.map { ($0 - minGyr) / (maxGyr - minGyr) }
                            var normalizedGyrAcc = normalizedAcc+normalizedGyr
                            self.checkBeforeSave(normalizedGyrAcc: normalizedGyrAcc)
                            
                            currentAccData = []
                            currentGyroData = []
                            normalizedGyrAcc = []
                        }
                        if self.isPredicting {
                            self.isPredicting = false
                            
                            // Normalisation
                            let minAcc = currentAccData.min()!
                            let maxAcc = currentAccData.max()!
                            let normalizedAcc = currentAccData.map { Float(($0 - minAcc) / (maxAcc - minAcc)) }
                            let minGyr = currentGyroData.min()!
                            let maxGyr = currentGyroData.max()!
                            let normalizedGyr = currentGyroData.map { Float(($0 - minGyr) / (maxGyr - minGyr)) }
                            
                            var normalizedGyrAcc = normalizedAcc+normalizedGyr
                            if self.checkIfMoved(values: normalizedGyrAcc) {
                                print("Player not moved")
                            } else {
                                print("Player moved")
                            }
                            
                            let prediction = try! self.neuralNet?.update(inputs: normalizedGyrAcc)
                            
                            let index = prediction?.index(of: (prediction?.max()!)!)! // [0.89,0.03,0.14]
                            
                            
                            let recognizedClass = Classes(rawValue: index!)!
                            print(recognizedClass)
                            print(prediction!)
                            
                            var str = "Da to omou "
                            switch recognizedClass {
                            case .Horizontal: str = str+"Horizontal!"
                            case .Vague: str = str+"Vague!"
                            case .Cercle: str = str+"Cercle!"
                            case .Vertical: str = str+"Vertical!"
                            }
                            let utterance = AVSpeechUtterance(string: str)
                            utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
                            utterance.rate = 0.4
                            
                            let synthesizer = AVSpeechSynthesizer()
                            synthesizer.speak(utterance)
                            currentAccData = []
                            currentGyroData = []
                            normalizedGyrAcc = []
                        }
                    }
                }
            }
        }
        
    }
    
    
    @IBAction func trainButtonClicked(_ sender: Any) {
        
        trainNetwork()
        
    }
    
    
    @IBAction func predictButtonClicked(_ sender: Any) {
        self.isPredicting = true
    }
    
    func checkBeforeSave(normalizedGyrAcc:[Double]) {
        let dialogMessage = UIAlertController(title: "Confirm", message: "Are you sure you want to save this?", preferredStyle: .alert)
        
        // Create OK button with action handler
        let ok = UIAlertAction(title: "Yes", style: .default, handler: { (action) -> Void in
            print("Ok button tapped")
            self.movementData[self.selectedClass]?.append(normalizedGyrAcc)
        })
        
        // Create Cancel button with action handlder
        let cancel = UIAlertAction(title: "No", style: .cancel) { (action) -> Void in
            print("Cancel button tapped")
        }
        
        //Add OK and Cancel button to dialog message
        dialogMessage.addAction(ok)
        dialogMessage.addAction(cancel)
        
        // Present dialog message to user
        self.present(dialogMessage, animated: true, completion: nil)
    }
    
    func trainNetwork() {
        
        // --------------------------------------
        // TRAINING
        // --------------------------------------
        for i in 0...40 {
            print(i)
            if let selectedClass = movementData.randomElement(),
                let input = selectedClass.value.randomElement(){
                let expectedResponse = selectedClass.key.neuralNetResponse()
                
                let floatInput = input.map{ Float($0) }
                let floatRes = expectedResponse.map{ Float($0) }
                
                try! neuralNet?.update(inputs: floatInput) // -> [0.23,0.67,0.99]
                try! neuralNet?.backpropagate(answer: floatRes)
                
            }
        }
        
        // --------------------------------------
        // VALIDATION
        // --------------------------------------
        for k in movementData.keys {
            print("Inference for \(k)")
            let values = movementData[k]!
            for v in values {
                let floatInput = v.map{ Float($0) }
                let prediction = try! neuralNet?.update(inputs:floatInput)
                print(prediction!)
            }
        }
        
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(true)
        SharedToyBox.instance.bolt?.sensorControl.disable()
    }
    
    @IBAction func segementedControlChanged(_ sender: UISegmentedControl) {
        let index = sender.selectedSegmentIndex
        if let s  = Classes(rawValue: index){
            selectedClass = s
        }
    }
    
    @IBAction func saveInFile(_ sender: Any) {
        
        print("write in file")
        
        createNeural()
        createJson()
        
    }
    
    func createNeural() {
        let fileManager = FileManager.default
        do {
            let documentDirectory = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor:nil, create:false)
            let fileURL = documentDirectory.appendingPathComponent(fileNameNeural)
            neuralNet?.write(fileURL)
            
        } catch {
            print(error)
        }
    }
    
    func createJson() {
            
           var listOfValues = [String:dataValueForm]()
          
            for (index,value) in movementData {
               listOfValues["\(index)"] = dataValueForm(values: value)
           }
           
           let list = ListDataValues(element: listOfValues)
     
           do {
               let fileURL = try FileManager.default
                   .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                   .appendingPathComponent(fileName)
               
               try JSONEncoder().encode(list)
                   .write(to: fileURL)
           } catch {
               print(error)
           }
           
       }
    
    func checkIfMoved(values:[Float]) -> Bool {
        
        let arrayNew = values.suffix(1800)
        let count = Set(arrayNew).count
        print(count)
        if count <= 100 {
            return true
        } else {
            return false
        }
    }
    
    
    func readJson() -> ListDataValues? {
        
        do {
            let fileURL = try FileManager.default
                .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
                .appendingPathComponent(fileName)
            
            let jsonString = try String(contentsOf: fileURL, encoding: .utf8)
            let dataObj = (jsonString).data(using: .utf8)!
            let listValues = try! JSONDecoder().decode(ListDataValues.self, from: dataObj)
            
            return listValues
        } catch {
            print(error)
            return nil
        }
    }
    
    @IBAction func startButtonClicked(_ sender: Any) {
        isRecording = true
    }
    
}
