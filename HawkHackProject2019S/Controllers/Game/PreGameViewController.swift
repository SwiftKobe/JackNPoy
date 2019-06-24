//
//  PreGameViewController.swift
//  HawkHackProject2019S
//
//  Created by Samuel Folledo on 3/30/19.
//  Copyright © 2019 Samuel Folledo. All rights reserved.
//

import UIKit
import FirebaseDatabase

protocol MatchesTableViewCellDelegate {
	func segueWithGameUid(withGame game: Game)
	func removeGame(withGame game: Game, indexPath: IndexPath)
}

class PreGameViewController: UIViewController {
	
	//MARK: IBOutlets
	@IBOutlet weak var helloLabel: UILabel!
	@IBOutlet weak var emailTextField: UITextField!
	@IBOutlet weak var topButton: UIButton!
	@IBOutlet weak var matchesTableView: UITableView!
	
	
	//MARK: Properties
	var game = Game.sharedInstance
	var users = [User]()
	
	var opponentUID: String?
	var gameSessionID: String?
	
	var matches = [Game]()
	
	
	//MARK: Lifecycle
	override func viewDidLoad() {
		super.viewDidLoad()
		
		let tap = UITapGestureRecognizer(target: self, action: #selector(tapToDismiss(tap:)))
		self.view.addGestureRecognizer(tap)
		
		matchesTableView.register(UINib(nibName: "MatchesTableViewCell", bundle: nil), forCellReuseIdentifier: "matchesCell")
		matchesTableView.delegate = self
		matchesTableView.dataSource = self
		matchesTableView.tableFooterView = UIView(frame: .zero)
		
		fetchUsers()
		
		disableButton(button: topButton)
		
		if isUserLoggedIn() {
			incomingRequest()
		}
	}
	
	
	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		
		if User.currentUser() == nil {
			helloLabel.text = "Please login or register in order to play a game"
			disableButton(button: topButton)
		} else {
			helloLabel.text = "Hello \(User.currentUser()!.name). Enter the email you would like to play against and click the invite button."
			enableButton(button: topButton)
		}
		
	}
	
	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		switch segue.identifier {
		case "preGameToGameSegue":
			guard let game: Game = sender as? Game else { return }
			//			print("game uid to segue is \(game.gameId)")
			let gameVC: CurrentGameViewController = segue.destination as! CurrentGameViewController
			gameVC.game = game
			
		default:
			break
		}
	}
	
	
	
	//MARK: IBActions
	@IBAction func topButtonTapped(_ sender: Any) {
		sendRequest()
	}
	
	
	//MARK: Methods for sending requests
	func sendRequest() {
		let userId = User.currentId()
        emailTextField.resignFirstResponder()
        
		guard let opponentEmail = self.emailTextField.text?.trimmedString() else { return }
		
		if opponentEmail.isValidEmail && opponentEmail != "" {
			var opponentUid: String = ""
			for user in users { //go through each users and find email that matches our textfield
				if user.email == opponentEmail {
					opponentUid = user.userID //this givesUID us the user that matches with the email we typed
					break
				} else { continue }
			}
//            print("OpponentUid = \(opponentUid)")
			if opponentUid == "" { return }
			
			fetchOpponentUserWith(opponentUid: opponentUid) { (opponentUser) in
				guard let opponentUser = opponentUser else { return }
				
				DispatchQueue.main.async { //is needed or it will create 2 requests
					let opponentDic = opponentUserToDictionaryFrom(user: opponentUser)
//                    print("OpponentDic is \(opponentDic)")
					//					print("OPPONENTDIC FROM SEND REQUEST IS \(opponentDic)")
					guard let user = User.currentUser() else { return }
					var gameValues: [String: AnyObject] = [kPLAYER1ID : userId, kPLAYER1EMAIL: user.email, kPLAYER1NAME: user.name, kPLAYER1AVATARURL: user.avatarURL, kPLAYER1HP: 100, kPLAYER2HP: 100 ] as [String: AnyObject] //values of our currentUser
					
					opponentDic.forEach {gameValues[$0] = $1} //combine each element in opponentDic to our values before we send the request
					
					self.sendRequestWithProperties(gameValues, to: opponentUid)
				}
				
			}
		}
	}
	
	func sendRequestWithProperties(_ properties: [String: AnyObject], to opponentUid: String) {
		//start game session reference with properties/values
		let ref = firDatabase.child(kGAMESESSIONS)
		let gameReference = ref.childByAutoId()
		guard let gameId: String = gameReference.key else { return }
		let timeStamp: Int = Int(Date().timeIntervalSince1970)
		
		
        var gameValues: [String: AnyObject] = [kCREATEDAT: timeStamp, kUPDATEDAT: timeStamp, kGAMESESSIONS: gameId] as [String: AnyObject] //values for our game session on top of each users's infos
		
		properties.forEach {gameValues[$0] = $1}
        print("Game values is created. Recommended to also save this in Core Data \(gameValues)")
		gameReference.updateChildValues(gameValues) { (error, ref) in //update our values in our reference
			if let error = error {
				Service.presentAlert(on: self, title: "Error", message: error.localizedDescription); return
			} else {
				
				//after updating our GAMESESSION's values, we will now create a reference to GAMESESSION's ids for our user's USERTOGAMESESSIONS
				guard let user = User.currentUser() else { return }
				let currentUserGameRef = firDatabase.child(kUSERTOGAMESESSIONS).child(user.userID).child(opponentUid)
				
				currentUserGameRef.updateChildValues([gameId: 1], withCompletionBlock: { (error, ref) in
					if let error = error {
						Service.presentAlert(on: self, title: "Firebase Error", message: error.localizedDescription); return
					} else {
						
						let opponentUserGameRef = firDatabase.child(kUSERTOGAMESESSIONS).child(opponentUid).child(user.userID)
						opponentUserGameRef.updateChildValues([gameId: 1], withCompletionBlock: { (error, ref) in
							if let error = error  {
								Service.presentAlert(on: self, title: "Error", message: error.localizedDescription); return
							} else {
								print("Creating opponent user's game reference was successful")
								
							}
						})
					}
				})
			}
		}
	}
	
	
	
	
	//MARK: Methods for incoming Requests
	func incomingRequest() {
		//		var properties: [String: AnyObject]?
		let requestReference = firDatabase.child(kUSERTOGAMESESSIONS).child(User.currentId()) //MISSING OPPONENT'S UID before we can access the game session id
		requestReference.observe(.value, with: { (snapshot) in
			
            guard let snapshot = snapshot.children.allObjects as? [DataSnapshot] else { print("No requests found"); return }
//            guard let snapshot = snapshot.value as? NSDictionary else { print("no requests found"); return }
            print(snapshot)
			for snap in snapshot { //each snap in snapshot is a dictionary //snap.key is the opponentUID and snap.value is the gameSessionId : 1
				guard let gameSessionUids = snap.value as? [String: AnyObject] else { print("snap.value cannot be found"); return } //snap.value = gameSessionId : 1 //has to be converted to [String: AnyObject] in order to get the snap.value properly
				self.gameUidsToGame(gameUidDictionary: gameSessionUids)
				
				
			}
		}, withCancel: nil)
	}
	
	func gameUidsToGame(gameUidDictionary: [String: AnyObject]) {
		//		print("\n\n\nKeys are\(gameUidDictionary.keys)\nValues are\(gameUidDictionary.values)\n\n\n")
        self.matches.removeAll()
		for key in gameUidDictionary.keys {
			
			fetchGameWith(gameSessionId: key, completion: { (game) in
				DispatchQueue.main.async {
//                    self.matches.removeAll()
                    
					guard let game = game else { return }
                    print("Fetched game found = \(game.gameId)")
					
					self.matches.append(game)
					self.matchesTableView.reloadData()
				}
			})
		}
		
	}
	
	
//MARK: Helper private methods
	private func fetchUsers() {
		let ref = firDatabase.child(kUSERS)
		ref.observe(.childAdded, with: { (snapshot) in
//            print("user found and snapshot is \(snapshot)")
			guard let userDic = snapshot.value as? [String: Any] else { return }
//            print("snapshot.value is \(userDic)")
            
            let user = User(_userID: snapshot.key, _name: userDic[kNAME]! as! String, _email: userDic[kEMAIL]! as! String, _experience: userDic[kEXPERIENCES]! as! Int, _level: userDic[kLEVEL]! as! Int)
            print("You can save other users here in Core Data")
            
//            let user = User(_dictionary: userDic)
//            user.name = userDic[kNAME]!
//            user.email = userDic[kEMAIL]!
//            user.userID = snapshot.key
			
			self.users.append(user)
		}, withCancel: nil)
//        print("Users \(users)")
	}
	
	@objc func tapToDismiss(tap: UITapGestureRecognizer) {
		self.view.endEditing(true)
	}
	
	private func disableButton(button: UIButton) {
		button.alpha = 0.2
		button.isEnabled = false
	}
	private func enableButton(button: UIButton) {
		button.alpha = 1
		button.isEnabled = true
	}
	
	
	
	
	
	
}



extension PreGameViewController: UITableViewDelegate, UITableViewDataSource {
	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return matches.count
	}
	
	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		tableView.rowHeight = 70 //PB ep78 22mins assign the height same as what we have in the xib
		let cell = tableView.dequeueReusableCell(withIdentifier: "matchesCell", for: indexPath) as! MatchesTableViewCell //PB ep78 23-24mins after we get the item, initiate our cell
		
		let match = matches[indexPath.row]
		cell.indexPath = indexPath
		cell.setCellData(game: match)
		cell.delegate = self
        
		return cell
	}
	
	
	
	//MatchesTableViewCellDelegate Methods
	func segueWithGameUid(withGame game: Game) {
		self.performSegue(withIdentifier: "preGameToGameSegue", sender: game)
	}
}

extension PreGameViewController: MatchesTableViewCellDelegate {
	func removeGame(withGame game: Game, indexPath: IndexPath) {
		game.deleteGame(game: game) { (error) in
			if let error = error {
                Service.presentAlert(on: self, title: "Error Removing Game", message: error)
			} else {
				self.matches.remove(at: indexPath.row)
				self.matchesTableView.reloadData()
			 }
		}
	}
}
