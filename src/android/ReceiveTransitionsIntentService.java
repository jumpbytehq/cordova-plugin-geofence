package com.cowbell.cordova.geofence;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;

import org.apache.http.HttpResponse;
import org.apache.http.NameValuePair;
import org.apache.http.client.ClientProtocolException;
import org.apache.http.client.HttpClient;
import org.apache.http.client.entity.UrlEncodedFormEntity;
import org.apache.http.client.methods.HttpPost;
import org.apache.http.impl.client.DefaultHttpClient;
import org.apache.http.message.BasicNameValuePair;

import android.app.IntentService;
import android.app.NotificationManager;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.preference.PreferenceManager;
import android.util.Log;

import com.google.android.gms.location.Geofence;
import com.google.android.gms.location.LocationClient;

public class ReceiveTransitionsIntentService extends IntentService {
    protected BeepHelper beepHelper;
    protected GeoNotificationNotifier notifier;
    protected GeoNotificationStore store;

    /**
     * Sets an identifier for the service
     */
    public ReceiveTransitionsIntentService() {
        super("ReceiveTransitionsIntentService");
        beepHelper = new BeepHelper();
        store = new GeoNotificationStore(this);
        Logger.setLogger(new Logger(GeofencePlugin.TAG, this, false));
    }

    /**
     * Handles incoming intents
     *
     * @param intent
     *            The Intent sent by Location Services. This Intent is provided
     *            to Location Services (inside a PendingIntent) when you call
     *            addGeofences()
     */
    @Override
    protected void onHandleIntent(Intent intent) {
        notifier = new GeoNotificationNotifier(
                (NotificationManager) this
                        .getSystemService(Context.NOTIFICATION_SERVICE),
                this);

        Logger logger = Logger.getLogger();
        // First check for errors
        if (LocationClient.hasError(intent)) {
            // Get the error code with a static method
            int errorCode = LocationClient.getErrorCode(intent);
            // Log the error
            logger.log(Log.ERROR,
                    "Location Services error: " + Integer.toString(errorCode));
            /*
             * You can also send the error code to an Activity or Fragment with
             * a broadcast Intent
             */
            /*
             * If there's no error, get the transition type and the IDs of the
             * geofence or geofences that triggered the transition
             */
        } else {
            // Get the type of transition (entry or exit)
            int transitionType = LocationClient.getGeofenceTransition(intent);
            if ((transitionType == Geofence.GEOFENCE_TRANSITION_ENTER)
                    || (transitionType == Geofence.GEOFENCE_TRANSITION_EXIT)) {
                logger.log(Log.DEBUG, "Geofence transition detected");
                List<Geofence> triggerList = LocationClient
                        .getTriggeringGeofences(intent);
                List<GeoNotification> geoNotifications = new ArrayList<GeoNotification>();
                for (Geofence fence : triggerList) {
                    String fenceId = fence.getRequestId();
                    GeoNotification geoNotification = store
                            .getGeoNotification(fenceId);

                    if (geoNotification != null) {
                        notifier.notify(
                                geoNotification.notification,
                                (transitionType == Geofence.GEOFENCE_TRANSITION_ENTER));
                        geoNotifications.add(geoNotification);
                    }
                }

                if (geoNotifications.size() > 0) {
                	SharedPreferences prefs = PreferenceManager.getDefaultSharedPreferences(this);
                	boolean isLoggedIn = prefs.getBoolean("isLoggedIn", false);
                	String serviceUrl = prefs.getString("serviceUrl", "");
                	String userId = prefs.getString("userId", "");
                	GeoNotification geoNotification = geoNotifications.get(0);
                	Log.d("RECEIVE_TRANSITION_INTENT_SERVICE", "getting preferences: isLoggedIn:"+ isLoggedIn + ", serverUrl:"+ serviceUrl + ", userId:"+ userId);
                	if(isLoggedIn) {
                    	// Create a new HttpClient and Post Header
                    	HttpClient httpclient = new DefaultHttpClient();
                    	HttpPost httppost = new HttpPost(serviceUrl);
                    	try {
                    	    // Add your data
                    	    List<NameValuePair> nameValuePairs = new ArrayList<NameValuePair>(2);
                    	    nameValuePairs.add(new BasicNameValuePair("userId", userId));
                    	    nameValuePairs.add(new BasicNameValuePair("storeId", geoNotification.id));
                    	    nameValuePairs.add(new BasicNameValuePair("lat", "" + geoNotification.latitude));
                    	    nameValuePairs.add(new BasicNameValuePair("long", "" + geoNotification.longitude));
                    	    nameValuePairs.add(new BasicNameValuePair("transitionType", geoNotification.transitionType == Geofence.GEOFENCE_TRANSITION_ENTER?"ENTER":"EXIT"));
                    	    httppost.setEntity(new UrlEncodedFormEntity(nameValuePairs));

                    	    // Execute HTTP Post Request
                    	    HttpResponse response = httpclient.execute(httppost);
                    	    Log.d("RECEIVE_TRANSITION_INTENT_SERVICE", response.toString());
                    	} catch (ClientProtocolException e) {
                    		e.printStackTrace();
                    	} catch (IOException e) {
                    	    e.printStackTrace();
                    	}
                	}
                	
                    GeofencePlugin.fireRecieveTransition(geoNotifications);
                }
            } else {
                logger.log(Log.ERROR, "Geofence transition error: "
                        + transitionType);
            }
        }
    }
}
