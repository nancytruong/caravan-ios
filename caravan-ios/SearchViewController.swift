//
//  SearchTableViewController.swift
//  caravan-ios
//
//  Created by Nancy on 2/15/17.
//  Copyright © 2017 Nancy. All rights reserved.
//

import UIKit
import Mapbox
import MapboxDirections
import MapboxNavigation
import MapboxGeocoder
import FirebaseDatabase
import FirebaseAuth

class SearchViewController: UIViewController {
    
    var geocoder: Geocoder!
    var directions: Directions!
    var searchResults: [GeocodedPlacemark] = []
    var retRoutes: [Route] = []
    var retRoute: Route?
    
    var locationManager: CLLocationManager!
    var locValue: CLLocationCoordinate2D!
    
    @IBOutlet weak var searchText: UITextField!
    @IBOutlet weak var tableView: UITableView!
    
    var ref: FIRDatabaseReference!
    var appDelegate: AppDelegate!
    
    var routeDict = Dictionary<String, Any>()
    
    deinit {
        self.ref.child("rooms").removeAllObservers()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        print("before target")
        searchText.addTarget(self, action: #selector(searchTextChanged(_:)), for: UIControlEvents.editingChanged)
        print("added target")
        
        //mapboxGeocoder(queryText: "Cal Poly")
        //tableView.reloadData()
        
        if CLLocationManager.locationServicesEnabled() {
            locationManager.delegate = self
            locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            locationManager.startUpdatingLocation()
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func mapboxGeocoder(queryText: String) {
        let options = ForwardGeocodeOptions(query: queryText)
        options.allowedISOCountryCodes = ["US"]
        //options.focalLocation = locationManager.location
        options.allowedScopes = [.address, .pointOfInterest]
        
        let _ = geocoder.geocode(options,
                         completionHandler: { placemarks, attribution, error in
                            if let unwrapped = placemarks {
                                print("got new results");
                                self.searchResults = unwrapped
                            } else {
                                self.searchResults = []
                            }
                            self.tableView.reloadData()
        })
    }

}

extension SearchViewController: UITextFieldDelegate {
    func searchTextChanged(_ textField: UITextField) {
        mapboxGeocoder(queryText: (textField.text ?? ""))
    }
}

extension SearchViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        locValue = (manager.location?.coordinate)!
    }
}

extension SearchViewController: UITableViewDataSource, UITableViewDelegate {
    // MARK: - Table view data source
    
    func numberOfSections(in tableView: UITableView) -> Int {
        // #warning Incomplete implementation, return the number of sections
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // #warning Incomplete implementation, return the number of rows
        return 5
    }
    
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        // Configure the cell...
        print("want to change the cell")
        if (indexPath.row < searchResults.count) {
            cell.textLabel?.text = searchResults[indexPath.row].qualifiedName
        } else {
            cell.textLabel?.text = ""
        }
        return cell
     }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let cell = tableView.cellForRow(at: indexPath)
        // have to configure options and get the directions
        let waypoints = [
            Waypoint(
                coordinate: locValue,
                name: "Current Location"
            ),
            Waypoint(
                coordinate: searchResults[indexPath.row].location.coordinate,
                name: searchResults[indexPath.row].qualifiedName
            ),
            ]
        
        let options = RouteOptions(waypoints: waypoints, profileIdentifier: MBDirectionsProfileIdentifier.automobile)
        options.includesSteps = true
        options.includesAlternativeRoutes = true;
        
        _ = directions.calculate(options) { (waypoints, routes, error) in
            guard error == nil else {
                print("Error calculating directions: \(error!)")
                return
            }
            
            //sending route object to firebase
            var stepsDict = [Dictionary<String, Any>]()
            var legsDict = [Dictionary<String, Any>]()
            var intersectionsDict = [Dictionary<String, Any>]()
            
            var legDict = Dictionary<String, Any>()
            var legSourceDict = Dictionary<String, Any>()
            var legDestinationDict = Dictionary<String, Any>()
            var stepDict = Dictionary<String, Any>()
            var intersectionDict = Dictionary<String, Any>()
            var maneuverDict = Dictionary<String, Any>()
            
            var approachLanes: [String] = []
            
            if let route = routes?.first, let leg = route.legs.first {
                
                self.retRoute = route

                for leg in route.legs {
                    legDict["distance"] = leg.distance
                    legDict["summary"] = leg.name
                    legDict["duration"] = leg.expectedTravelTime
                    legDict["description"] = leg.description
    
                    legDict["profileIdentifier"] = leg.profileIdentifier

                    legSourceDict["name"] = leg.source.name
                    legSourceDict["location"] = [leg.source.coordinate.latitude, leg.source.coordinate.longitude]
                    legDestinationDict["name"] = leg.destination.name
                    legDestinationDict["location"] = [leg.destination.coordinate.latitude, leg.destination.coordinate.longitude]
                    
                    legDict["source"] = legSourceDict
                    legDict["destination"] = legDestinationDict
                    
                    for step in leg.steps {
                        stepDict["codes"] = step.codes ?? [""]
                        stepDict["coordinateCount"] = step.coordinateCount
                        
                        var temp: [[CLLocationDegrees]] = []
                        for coord in step.coordinates! {
                            temp.append([coord.latitude, coord.longitude])
                        }
                        stepDict["coordinates"] = temp
                        
                        stepDict["geometry"] = ["type": "Point",
                                                "coordinates": temp]
                        
                        stepDict["description"] = step.description
                        stepDict["destinationCodes"] = step.destinationCodes ?? [""]
                        stepDict["destinations"] = step.destinations ?? [""]
                        stepDict["distance"] = step.distance
                        
                        stepDict["instructions"] = step.instructions
                        stepDict["finalHeading"] = step.finalHeading
                        
                        maneuverDict["location"] = [step.maneuverLocation.latitude, step.maneuverLocation.longitude]
                        maneuverDict["type"] = step.maneuverType?.description
                        maneuverDict["modifier"] = step.maneuverDirection?.description
                        stepDict["maneuver"] = maneuverDict
                        
                        stepDict["name"] = step.names?.first ?? ""
                        stepDict["mode"] = step.transportType?.description
                      
                        
                        for intersection in step.intersections! {
                            
                            if let lanes = intersection.approachLanes {
                                for lane in lanes {
                                    approachLanes.append(lane.indications.description)
                                }
                            }
                            intersectionDict["approachLanes"] = approachLanes
                            approachLanes.removeAll()
                            intersectionDict["bearings"] = intersection.headings //[CLLocationDirection]
                            
                            var output: [Int] = [];
                            var args = intersection.usableApproachLanes?.makeIterator();
                            while let arg = args?.next() {
                                output.append(arg)
                            }
                            
                            if output.count > 0 {
                                intersectionDict["usableApproachLanes"] = output
                            }
                            else {
                                intersectionDict["usableApproachLanes"] = [-1]
                            }
                            
                            var output2: [Int] = [];
                            var args2 = intersection.outletIndexes.makeIterator();
                            while let arg = args2.next() {
                                output2.append(arg)
                            }
                            intersectionDict["entry"] = output2
                            
                            intersectionDict["location"] = [intersection.location.latitude, intersection.location.longitude]
                            
                            intersectionsDict.append(intersectionDict)
                            intersectionDict.removeAll()
                        }
                        stepDict["intersections"] = intersectionsDict
                        
                        stepsDict.append(stepDict)
                        stepDict.removeAll()
                    }
                    legDict["steps"] = stepsDict
                    stepsDict.removeAll()
                    legsDict.append(legDict)
                    legDict.removeAll()
                    
                }
                
                self.routeDict["duration"] = route.expectedTravelTime
                self.routeDict["distance"] = route.distance
                self.routeDict["profileIdentifier"] = route.profileIdentifier
                
                var temp: [[CLLocationDegrees]] = []
                for coord in route.coordinates! {
                    temp.append([coord.latitude, coord.longitude])
                }
                self.routeDict["coordinates"] = temp
                
                var coordinateArray: [[CLLocationDegrees]] = []
                for coord in route.coordinates! {
                    coordinateArray.append([coord.latitude, coord.longitude])
                }
                self.routeDict["geometry"] = ["type": "Point",
                                       "coordinates": coordinateArray]
                
                self.routeDict["legs"] = legsDict
                
            }
            
        
            //let userId = self.appDelegate.user?.uid
            //self.ref.child("users").child(userId!).child("route").setValue(routeDict)
            
            
            
            
            //TESTING INITIALIZING ROUTES FROM INFO I HAVE
            //first, convert route dict "routeDict" to json
            
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: self.routeDict, options: .prettyPrinted)
                // here "jsonData" is the dictionary encoded in JSON data
                
                let decoded = try JSONSerialization.jsonObject(with: jsonData, options: [])
                // here "decoded" is of type `Any`, decoded from JSON data
                
                
                // you can now cast it with the right type
                if var dictFromJSON = decoded as? [String:Any] {
                    // use dictFromJSON
                    
                    //print("changing the coord in steps")
                    //print(((((dictFromJSON["legs"] as! NSArray)[0] as! [String: Any])["steps"] as! NSArray)[0] as! [String:Any])["coordinates"])
                    
                    let newRoute : Route = Route.init(json: dictFromJSON, waypoints: waypoints! , profileIdentifier: MBDirectionsProfileIdentifier.automobile)
                    //print("COORDS")
                    //print(newRoute.coordinates ?? "nonee")
                    //let viewController = NavigationUI.routeViewController(for: newRoute, directions: self.directions)
                    //self.present(viewController, animated: true, completion: nil)
                }
            } catch {
                print(error.localizedDescription)
            }
            
            if ((routes?.count)! >= 2) {
                self.retRoutes = routes!;
                self.performSegue(withIdentifier: "showRouteSelection", sender: self)
            } else {
                self.performSegue(withIdentifier: "showPreview", sender: self)
                //ref.observe(<#T##eventType: FIRDataEventType##FIRDataEventType#>, with: <#T##(FIRDataSnapshot) -> Void#>)
                self.ref.observe(FIRDataEventType.value,
                            with: {(snapshot) in
                                print("hello")
                            })
            }
        }
        
        //print(cell?.textLabel?.text)
        //print("search results: " + searchResults[indexPath.row].qualifiedName)
        //print(searchResults[indexPath.row].location.coordinate)
    }
    
    // MARK: - Navigation
    
    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
        print("preparing for segue");
        
        if segue.identifier == "showRouteSelection" {
            let controller = segue.destination as! RouteSelectionViewController
            
            controller.ref = ref
            controller.appDelegate = appDelegate
            controller.locationManager = locationManager
            controller.directions = directions
            controller.geocoder = geocoder
            controller.locValue = self.locValue
            print("set the routes")
            controller.routes = retRoutes
        }
        
        if segue.identifier == "showPreview" {
            let controller = segue.destination as! PreviewViewController
            
            controller.ref = ref
            controller.appDelegate = appDelegate
            controller.locationManager = locationManager
            controller.directions = directions
            controller.geocoder = geocoder
            controller.routeDict = routeDict
            controller.route = retRoute
        }
    }
}
