//
//  GeofencePlugin.swift
//  ionic-geofence
//
//  Created by tomasz on 07/10/14.
//
//

import Foundation

let TAG = "GeofencePlugin"
let iOS8 = floor(NSFoundationVersionNumber) > floor(NSFoundationVersionNumber_iOS_7_1)
let iOS7 = floor(NSFoundationVersionNumber) <= floor(NSFoundationVersionNumber_iOS_7_1)

func log(message: String){
    #if DEBUG
       NSLog("%@ - %@", TAG, message)
    #endif
}

var GeofencePluginWebView: UIWebView?

@objc(HWPGeofencePlugin) class GeofencePlugin : CDVPlugin {
    let geoNotificationManager = GeoNotificationManager()
    let priority = DISPATCH_QUEUE_PRIORITY_DEFAULT

    func initialize(command: CDVInvokedUrlCommand) {
        log("Plugin initialization");
        //let faker = GeofenceFaker(manager: geoNotificationManager)
        //faker.start()
        GeofencePluginWebView = self.webView

        if iOS8 {
            promptForNotificationPermission()
        }
        var pluginResult = CDVPluginResult(status: CDVCommandStatus_OK)
        commandDelegate.sendPluginResult(pluginResult, callbackId: command.callbackId)
    }

    func promptForNotificationPermission() {
        UIApplication.sharedApplication().registerUserNotificationSettings(UIUserNotificationSettings(
            forTypes: UIUserNotificationType.Sound | UIUserNotificationType.Alert | UIUserNotificationType.Badge,
            categories: nil
            )
        )
    }

    func addOrUpdate(command: CDVInvokedUrlCommand) {
        dispatch_async(dispatch_get_global_queue(priority, 0)) {
            // do some task
            for geo in command.arguments {
                self.geoNotificationManager.addOrUpdateGeoNotification(JSON(geo))
            }
            dispatch_async(dispatch_get_main_queue()) {
                var pluginResult = CDVPluginResult(status: CDVCommandStatus_OK)
                self.commandDelegate.sendPluginResult(pluginResult, callbackId: command.callbackId)
            }
        }
    }

    func getWatched(command: CDVInvokedUrlCommand) {
        dispatch_async(dispatch_get_global_queue(priority, 0)) {
            var watched = self.geoNotificationManager.getWatchedGeoNotifications()!
            let watchedJsonString = watched.description
            dispatch_async(dispatch_get_main_queue()) {
                var pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAsString: watchedJsonString)
                self.commandDelegate.sendPluginResult(pluginResult, callbackId: command.callbackId)
            }
        }
    }

    func remove(command: CDVInvokedUrlCommand) {
        dispatch_async(dispatch_get_global_queue(priority, 0)) {
            for id in command.arguments {
                self.geoNotificationManager.removeGeoNotification(id as String)
            }
            dispatch_async(dispatch_get_main_queue()) {
                var pluginResult = CDVPluginResult(status: CDVCommandStatus_OK)
                self.commandDelegate.sendPluginResult(pluginResult, callbackId: command.callbackId)
            }
        }
    }

    func removeAll(command: CDVInvokedUrlCommand) {
        dispatch_async(dispatch_get_global_queue(priority, 0)) {
            self.geoNotificationManager.removeAllGeoNotifications()
            dispatch_async(dispatch_get_main_queue()) {
                var pluginResult = CDVPluginResult(status: CDVCommandStatus_OK)
                self.commandDelegate.sendPluginResult(pluginResult, callbackId: command.callbackId)
            }
        }
    }

    class func fireReceiveTransition(geoNotification: JSON) {
        var mustBeArray = [JSON]()
        mustBeArray.append(geoNotification)
        let js = "setTimeout('geofence.receiveTransition(" + mustBeArray.description + ")',0)";
        if (GeofencePluginWebView != nil) {
            GeofencePluginWebView!.stringByEvaluatingJavaScriptFromString(js);
        }
    }
}

// class for faking crossing geofences
class GeofenceFaker {
    let priority = DISPATCH_QUEUE_PRIORITY_DEFAULT
    let geoNotificationManager: GeoNotificationManager

    init(manager: GeoNotificationManager) {
        geoNotificationManager = manager
    }

    func start() {
         dispatch_async(dispatch_get_global_queue(priority, 0)) {
            while (true) {
                log("FAKER")
                let notify = arc4random_uniform(4)
                if notify == 0 {
                    log("FAKER notify chosen, need to pick up some region")
                    var geos = self.geoNotificationManager.getWatchedGeoNotifications()!
                    if geos.count > 0 {
                        //WTF Swift??
                        let index = arc4random_uniform(UInt32(geos.count))
                        var geo = geos[Int(index)]
                        let id = geo["id"].asString!
                        dispatch_async(dispatch_get_main_queue()) {
                            if let region = self.geoNotificationManager.getMonitoredRegion(id) {
                                log("FAKER Trigger didEnterRegion")
                                self.geoNotificationManager.locationManager(
                                    self.geoNotificationManager.locationManager,
                                    didEnterRegion: region
                                )
                            }
                        }
                    }
                }
                NSThread.sleepForTimeInterval(3);
            }
         }
    }

    func stop() {

    }
}

class GeoNotificationManager : NSObject, CLLocationManagerDelegate {
    let locationManager = CLLocationManager()
    let store = GeoNotificationStore()

    override init() {
        log("GeoNotificationManager init")
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        
        println("total monitored regions:\(locationManager.monitoredRegions.count)")
        // added
        //if(store.getTotalGeoNotifications() >= 20) {
            locationManager.startMonitoringSignificantLocationChanges()
        //}
       
        if (!CLLocationManager.locationServicesEnabled()) {
            log("Location services is not enabled")
        } else {
            log("Location services enabled")
        }
        if iOS8 {
            locationManager.requestAlwaysAuthorization()
        }

        if (!CLLocationManager.isMonitoringAvailableForClass(CLRegion)) {
            log("Geofencing not available")
        }
    }
    
    
    func haversine(lat1:Double, lon1:Double, lat2:Double, lon2:Double, radius:Double) -> Double {
        let lat1rad = lat1 * M_PI/180
        let lon1rad = lon1 * M_PI/180
        let lat2rad = lat2 * M_PI/180
        let lon2rad = lon2 * M_PI/180
        
        let dLat = lat2rad - lat1rad
        let dLon = lon2rad - lon1rad
        let a = sin(dLat/2) * sin(dLat/2) + sin(dLon/2) * sin(dLon/2) * cos(lat1rad) * cos(lat2rad)
        let c = 2 * asin(sqrt(a))
        let R = 6372.8
        
        return radius * c
    }

    func addOrUpdateGeoNotification(geoNotification: JSON) {
        log("GeoNotificationManager addOrUpdate")

        if (!CLLocationManager.locationServicesEnabled()) {
            log("Locationservices is not enabled")
        }

        var location = CLLocationCoordinate2DMake(
            geoNotification["latitude"].asDouble!,
            geoNotification["longitude"].asDouble!
        )
        log("AddOrUpdate geo: \(geoNotification)")
        var radius = geoNotification["radius"].asDouble! as CLLocationDistance
        //let uuid = NSUUID().UUIDString
        let id = geoNotification["id"].asString

        var region = CLCircularRegion(
            circularRegionWithCenter: location,
            radius: radius,
            identifier: id
        )
        region.notifyOnEntry = geoNotification["transitionType"].asInt == 1 ? true: false
        region.notifyOnExit = geoNotification["transitionType"].asInt == 2 ? true: false
        //store
        store.addOrUpdate(geoNotification)
        locationManager.startMonitoringForRegion(region)

        if(store.getTotalGeoNotifications() >= 20) {
            // added for monitoring more than 20
            locationManager.startMonitoringSignificantLocationChanges()
            //log("location added to DB but not monitered only 20 can be monitered at a time")
        }
    }

    func getWatchedGeoNotifications() -> [JSON]? {
        return store.getAll()
    }

    func getMonitoredRegion(id: String) -> CLRegion? {
        for object in locationManager.monitoredRegions {
            let region = object as CLRegion

            if (region.identifier == id) {
                return region
            }
        }
        return nil
    }

    func removeGeoNotification(id: String) {
        store.remove(id)
        var region = getMonitoredRegion(id)
        if (region != nil) {
            log("Stoping monitoring region \(id)")
            locationManager.stopMonitoringForRegion(region)
        }
    }

    func removeAllGeoNotifications() {
        store.clear()
        for object in locationManager.monitoredRegions {
            let region = object as CLRegion
            log("Stoping monitoring region \(region.identifier)")
            locationManager.stopMonitoringForRegion(region)
        }
    }
    
    func removeAllGeoNotificationsListeners() {
        for object in locationManager.monitoredRegions {
            let region = object as CLRegion
            log("Stoping monitoring region \(region.identifier)")
            locationManager.stopMonitoringForRegion(region)
        }
    }
    
    func monitorBest20(distances:[Double:Int]) {
        // add monitor for first 20 sortedBy distance
        if let allRegions = store.getAll() {
            var i = 0
            for (k,v) in Array(distances).sorted({$0.0 < $1.0}) {
                if i < 20 {
                    addOrUpdateGeoNotification(allRegions[v])
                }
                i++
               // println("\(k):\(v)")
            }
        }
        log("monitoring best 20")
        println("total monitored regions:\(locationManager.monitoredRegions.count)")
    }
    
    func getDistancesArray(coordinate: CLLocationCoordinate2D) -> [Double:Int] {
        var distances = [Double:Int]()

        if let allRegions = store.getAll() {
            for (index,region) in enumerate(allRegions) {
                let lat = region["latitude"].asDouble!
                let lng = region["longitude"].asDouble!
                let radius = region["radius"].asDouble!
                let distance = haversine(coordinate.latitude, lon1: coordinate.longitude, lat2: lat, lon2: lng, radius: radius)
                distances[distance] = index
                //log("distance:\(distance)")
            }
        }
        return distances
    }

    func locationManager(manager: CLLocationManager!, didUpdateLocations locations: [AnyObject]!) {
        log("update location called")
        // select best 20 here
        let monitoredRegions = locationManager.monitoredRegions
        println("total monitored regions:\(monitoredRegions.count)")
        // remove all notification first
        removeAllGeoNotificationsListeners()
        var locationArray = locations as Array
        var locationObj = locationArray.last as CLLocation
        var coord = locationObj.coordinate
        // calculate distance
        var distances = getDistancesArray(coord)
        monitorBest20(distances)
    }

    func locationManager(manager: CLLocationManager!, didFailWithError error: NSError!) {
        log("fail with error: \(error)")
    }

    func locationManager(manager: CLLocationManager!, didFinishDeferredUpdatesWithError error: NSError!) {
        log("deferred fail error: \(error)")
    }

    func locationManager(manager: CLLocationManager!, didEnterRegion region: CLRegion!) {
        log("Entering region \(region.identifier)")
        // send id to keystone service here
        let isLoggedIn = NSUserDefaults.standardUserDefaults().boolForKey("isLoggedIn")
        let serviceUrl = NSUserDefaults.standardUserDefaults().stringForKey("serviceUrl")
        log("isLoggedIn:\(isLoggedIn)")
        log("serviceUrl:\(serviceUrl)")
        if isLoggedIn {
            if let userId = NSUserDefaults.standardUserDefaults().stringForKey("userId") {
                let lat = (region as CLCircularRegion).center.latitude
                let lng = (region as CLCircularRegion).center.longitude
                let radius = (region as CLCircularRegion).radius
                
                let strLat = NSNumber(double: lat).stringValue
                let strLng = NSNumber(double: lng).stringValue
                let strRadius = NSNumber(double: radius).stringValue
                
                log("strLat:\(strLat)")
                log("strLng:\(strLng)")
                log("strRadius:\(strRadius)")

                var params = ["userId": userId, "storeId": region.identifier, "latitude":strLat, "longitude": strLng, "radius":strRadius] as Dictionary<String, String>
                if(serviceUrl != nil) {
                    post(params, url: serviceUrl!)
                } else {
                    log("serviceUrl not found in preference not updating checkin")
                }
            } else {
                log("userId not found in preference not updation checkin")
            }
        }
        handleTransition(region)
    }

    func locationManager(manager: CLLocationManager!, didExitRegion region: CLRegion!) {
        log("Exiting region \(region.identifier)")
        handleTransition(region)
    }

    func locationManager(manager: CLLocationManager!, didStartMonitoringForRegion region: CLRegion!) {
        let lat = (region as CLCircularRegion).center.latitude
        let lng = (region as CLCircularRegion).center.longitude
        let radius = (region as CLCircularRegion).radius

        log("Starting monitoring for region \(region) lat \(lat) lng \(lng)")
    }

    func locationManager(manager: CLLocationManager, didDetermineState state: CLRegionState, forRegion region: CLRegion) {
        log("State for region " + region.identifier)
    }

    func locationManager(manager: CLLocationManager, monitoringDidFailForRegion region: CLRegion!, withError error: NSError!) {
        log("Monitoring region " + region.identifier + " failed " + error.description)
    }

    func handleTransition(region: CLRegion!) {
        if let geo = store.findById(region.identifier) {
            notifyAbout(geo)
            GeofencePlugin.fireReceiveTransition(geo)
        }
    }

    func notifyAbout(geo: JSON) {
        log("Creating notification")
        var notification = UILocalNotification()
        notification.timeZone = NSTimeZone.defaultTimeZone()
        var dateTime = NSDate()
        notification.fireDate = dateTime
        notification.soundName = UILocalNotificationDefaultSoundName
        notification.alertBody = geo["notification"]["text"].asString!
        UIApplication.sharedApplication().scheduleLocalNotification(notification)
    }

    // added custom
    
    func post(params : Dictionary<String, String>, url : String) {
        var request = NSMutableURLRequest(URL: NSURL(string: url)!)
        var session = NSURLSession.sharedSession()
        request.HTTPMethod = "POST"
        
        var err: NSError?
        request.HTTPBody = NSJSONSerialization.dataWithJSONObject(params, options: nil, error: &err)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        
        var task = session.dataTaskWithRequest(request, completionHandler: {data, response, error -> Void in
            //println("Response: \(response)")
            var strData = NSString(data: data, encoding: NSUTF8StringEncoding)
            //println("Body: \(strData)")
            var err: NSError?
            var json = NSJSONSerialization.JSONObjectWithData(data, options: .MutableLeaves, error: &err) as? NSDictionary
            
            // Did the JSONObjectWithData constructor return an error? If so, log the error to the console
            if(err != nil) {
                println(err!.localizedDescription)
                let jsonStr = NSString(data: data, encoding: NSUTF8StringEncoding)
                println("Error could not parse JSON: '\(jsonStr)'")
            }
            else {
                // The JSONObjectWithData constructor didn't return an error. But, we should still
                // check and make sure that json has a value using optional binding.
                if let parseJSON = json {
                    // Okay, the parsedJSON is here, let's get the value for 'success' out of it
                    var success = parseJSON["status"] as? Bool
                    log("Status: \(success)")
                }
                else {
                    // Woa, okay the json object was nil, something went worng. Maybe the server isn't running?
                    let jsonStr = NSString(data: data, encoding: NSUTF8StringEncoding)
                    println("Error could not parse JSON: \(jsonStr)")
                }
            }
        })
        task.resume()
    }
}

class GeoNotificationStore {
    init() {
        createDBStructure()
    }

    func createDBStructure() {
        let (tables, err) = SD.existingTables()

        if (err != nil) {
            log("Cannot fetch sqlite tables: \(err)")
            return
        }

        if (tables.filter { $0 == "GeoNotifications" }.count == 0) {
            if let err = SD.executeChange("CREATE TABLE GeoNotifications (ID TEXT PRIMARY KEY, Data TEXT)") {
                //there was an error during this function, handle it here
                log("Error while creating GeoNotifications table: \(err)")
            } else {
                //no error, the table was created successfully
                log("GeoNotifications table was created successfully")
            }
        }
    }

    func addOrUpdate(geoNotification: JSON) {
        if (findById(geoNotification["id"].asString!) != nil) {
            update(geoNotification)
        }
        else {
            add(geoNotification)
        }
    }

    func add(geoNotification: JSON) {
        let id = geoNotification["id"].asString!
        let err = SD.executeChange("INSERT INTO GeoNotifications (Id, Data) VALUES(?, ?)",
            withArgs: [id, geoNotification.description])

        if err != nil {
            log("Error while adding \(id) GeoNotification: \(err)")
        }
    }

    func update(geoNotification: JSON) {
        let id = geoNotification["id"].asString!
        let err = SD.executeChange("UPDATE GeoNotifications SET Data = ? WHERE Id = ?",
            withArgs: [geoNotification.description, id])

        if err != nil {
            log("Error while adding \(id) GeoNotification: \(err)")
        }
    }

    func findById(id: String) -> JSON? {
        let (resultSet, err) = SD.executeQuery("SELECT * FROM GeoNotifications WHERE Id = ?", withArgs: [id])

        if err != nil {
            //there was an error during the query, handle it here
            log("Error while fetching \(id) GeoNotification table: \(err)")
            return nil
        } else {
            if (resultSet.count > 0) {
                return JSON(string: resultSet[0]["Data"]!.asString()!)
            }
            else {
                return nil
            }
        }
    }

    func getAll() -> [JSON]? {
        let (resultSet, err) = SD.executeQuery("SELECT * FROM GeoNotifications")
        
        if err != nil {
            //there was an error during the query, handle it here
            log("Error while fetching from GeoNotifications table: \(err)")
            return nil
        } else {
            var results = [JSON]()
            for row in resultSet {
                if let data = row["Data"]?.asString() {
                    results.append(JSON(string: data))
                }
            }
            return results
        }
    }
    
    func getTotalGeoNotifications() -> Int {
        let (resultSet, err) = SD.executeQuery("SELECT * FROM GeoNotifications")
        return resultSet.count
    }

    func remove(id: String) {
        let err = SD.executeChange("DELETE FROM GeoNotifications WHERE Id = ?", withArgs: [id])

        if err != nil {
            log("Error while removing \(id) GeoNotification: \(err)")
        }
    }

    func clear() {
        let err = SD.executeChange("DELETE FROM GeoNotifications")

        if err != nil {
            log("Error while deleting all from GeoNotifications: \(err)")
        }
    }
}
