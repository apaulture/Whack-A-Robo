//
//  ViewController.swift
//  TestAR
//
//  Created by Real on 8/6/19.
//  Copyright © 2019 Real. All rights reserved.
//


import RealityKit
import ARKit
import SceneKit
import UIKit
import MultipeerConnectivity
import AVFoundation

class ViewController: UIViewController {
    var moleCount = 15, score = 0
    let slotCount = 16
    var audioPlayer = AVAudioPlayer()
    let coachingOverlay = ARCoachingOverlayView()
    
    @IBOutlet var arView: ARView!
    @IBOutlet weak var molesLabel: UILabel!
    @IBOutlet weak var scoreLabel: UILabel!
    @IBOutlet weak var upperControlsView: UIView!
    
    var multipeerSession: MultipeerSession!
    
    @IBAction func onTap(_ sender: UITapGestureRecognizer) {
        
        let tapLocation = sender.location(in: arView)
        
        // returns the closest entity at location of tap
        if let mole = arView.entity(at: tapLocation)
        {
            var moleTransform = mole.transform // store original transform values
            moleTransform.scale = [0,0.1,0]
            
            // Animation playback controller
            let animationController = mole.move(
                to: moleTransform,
                relativeTo: mole.parent,
                duration: 0.1,
                timingFunction: .easeIn)
            
            score += 1
            updateScore()
            
            moleCount -= 1
            updateMoles()
            
            audioPlayer.play()
        }
    }
    
    func updateScore()
    {
        self.scoreLabel.text = "Points: \(score)"
    }
    
    func updateMoles()
    {
        self.molesLabel.text = "Robots: \(moleCount)"
    }
    
    // View load starts here
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCoachingOverlay()
        
        // Sound handler
        let whacked = Bundle.main.path(forResource: "whacked", ofType: "mp3")
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: whacked!))
        }
        catch {
            print("Audio file not found!")
        }
        
        multipeerSession = MultipeerSession(receivedDataHandler: receivedData)
        
        // Labels handler
        self.molesLabel.layer.cornerRadius = 12
        self.molesLabel.clipsToBounds = true
        self.scoreLabel.layer.cornerRadius = 12.0
        self.scoreLabel.clipsToBounds = true
        self.molesLabel.text = "Robots: \(moleCount)"
        
        // Setup configuration for collaborative session
        let config = ARWorldTrackingConfiguration()
        config.isCollaborationEnabled = true
        config.planeDetection = [.horizontal]
        arView.session.run(config) // arView --> session or scene --> run or add anchors
        
        // Game anchor
        let gameAnchor = AnchorEntity(plane: .horizontal)
        arView.scene.addAnchor(gameAnchor)
        
        // Set up mesh, material, and collider properties of the game board
        let planeMesh = MeshResource.generatePlane(width: 0.55, depth: 0.55, cornerRadius: 0.035)
        let boardMaterial = SimpleMaterial(color: .init(red: 0.18, green: 0.18, blue: 0.25, alpha: 0.97), roughness: 0.2, isMetallic: true)
        let gameBoard = ModelEntity(mesh: planeMesh, materials: [boardMaterial])
        
        gameBoard.position = [0,0,0]
        gameAnchor.addChild(gameBoard)
        
        // Create empty array of slot and model entities
        var slots: [ModelEntity] = [], moles: [ModelEntity] = []
        
        // Fill array with x number of slots, moles
        for _ in 1...slotCount
        {
            let slotModel = ModelEntity(mesh: .generateSphere(radius: 0.035), materials: [SimpleMaterial(color: .init(red: 0.3, green: 0.7, blue: 0.9, alpha: 1.0), roughness: 0.2, isMetallic: true)])
            slotModel.position = [0,0.01,0]
            slotModel.transform.scale = [1,0.02,1]
            slots.append(slotModel)
        }
        
        let moleModel = try! ModelEntity.loadModel(named: "toy_robot_vintage")
        moleModel.generateCollisionShapes(recursive: true)
        
        for _ in 1...moleCount
        {
//            let mole = ModelEntity(mesh: .generateBox(size: 0.05, cornerRadius: 0), materials: [SimpleMaterial(color: .red, roughness: 0.2, isMetallic: true)])
//            mole.generateCollisionShapes(recursive: true)
            
            // TEST
            let cloneModel = moleModel.clone(recursive: true)
            moles.append(cloneModel)
            
        }

        // Render slots to board
        for (i,slot) in slots.enumerated()
        {
            let x = Float(i % 4) - 1.5
            let z = Float(i / 4) - 1.5

            slot.position = [x * 0.1, 0.01, z * 0.1]

            gameBoard.addChild(slot)
        }
        
        // Generate random times
        var randomTimes: [Double] = []
        var timesToAdd = moleCount // for readability purposes
        while (timesToAdd != 0)
        {
            randomTimes.append(Double.random(in: 0...30))
//            print("Added: \(randomTimes) with \(timesToAdd) left") -- for debug
            timesToAdd -= 1
        }
        
        print("Moles total: \(moles.count) and times: \(randomTimes.count)")
        
        
        // Render moles at different times ranging from 0 to 20
        for var i in stride(from: 1, to: randomTimes.count, by: 1)
        {
            let randomSlot = Int.random(in: 1...slotCount - 1)
            DispatchQueue.main.asyncAfter(deadline: .now() + randomTimes[i]) {
                if (slots[randomSlot].children.isEmpty)
                {
                    moles[i].position = [0,0.05,0]
                    
                    moles[i].transform.scale = [0.005,0.3,0.005]
                    slots[randomSlot].addChild(moles[i])
                    
                    print("\(i) added")
                }
                else
                {
                    print("Slot \(i) has a mole on it!")
                    i += 1 // add counter
                    
                    // can take average of time in randomTimes array then add average time if slot has mole on it to extend time
                }
            }
        }
        
        // End of viewDidLoad
    }
    
    // Not original code
    var mapProvider: MCPeerID?
    
    func receivedData(_ data: Data, from peer: MCPeerID) {
        
        do {
            if let worldMap = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data) {
                // Run the session with the received world map.
                let configuration = ARWorldTrackingConfiguration()
                configuration.planeDetection = .horizontal
                configuration.initialWorldMap = worldMap
                arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
                
                // Remember who provided the map for showing UI feedback.
                mapProvider = peer
            }
            else
            if let anchor = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARAnchor.self, from: data) {
                // Add anchor to the session, ARSCNView delegate adds visible content.
                arView.session.add(anchor: anchor)
            }
            else {
                print("unknown data recieved from \(peer)")
            }
        } catch {
            print("can't decode data recieved from \(peer)")
        }
    }
}



// Degree to rad extension
extension Float
{
    var toRad: Float { return self / 180 * .pi }
}
