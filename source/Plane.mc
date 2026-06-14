import Toybox.Lang;

// Fetch status
const STATUS_IDLE = 0;
const STATUS_LOADING = 1;
const STATUS_ERROR = 2;

// One aircraft (airplane, helicopter, ... - anything broadcasting ADS-B).
class Plane {
    public var callsign as String;  // flight id, e.g. "DLH4AB"
    public var lat as Double;
    public var lon as Double;
    public var icao24 as String;    // Mode-S address (key for type lookup)
    public var altM as Number;      // altitude in metres, -1 if unknown
    public var speedKmh as Number;  // ground speed in km/h, -1 if unknown
    public var track as Float?;     // ground track, degrees true
    public var distance as Float;   // metres from current position
    public var bearing as Float;    // degrees true, 0..360

    function initialize(aCallsign as String, aLat as Double, aLon as Double,
                        aIcao as String) {
        callsign = aCallsign;
        lat = aLat;
        lon = aLon;
        icao24 = aIcao;
        altM = -1;
        speedKmh = -1;
        track = null;
        distance = 0.0;
        bearing = 0.0;
    }

    function label() as String {
        return (callsign.length() > 0) ? callsign : "Aircraft";
    }
}
