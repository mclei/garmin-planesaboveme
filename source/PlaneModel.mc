import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.Sensor;
import Toybox.Time;
import Toybox.WatchUi;

const OPENSKY_URL = "https://opensky-network.org/api/states/all";
// adsbdb.com (free, keyless): type by Mode-S address, route by callsign.
const ADSBDB_AIRCRAFT_URL = "https://api.adsbdb.com/v0/aircraft/";
const ADSBDB_CALLSIGN_URL = "https://api.adsbdb.com/v0/callsign/";

const MAX_PLANES = 30;

class PlaneModel {

    public var lat as Double?;
    public var lon as Double?;
    public var gpsQuality as Number;
    public var posApprox as Boolean;
    public var headingDeg as Float;

    public var planes as Array<Plane>;   // distance-sorted, full 360 deg
    public var targetPlane as Plane?;    // user-locked aircraft

    public var status as Number;
    public var errCode as Number;

    public var radiusM as Number;
    public var refreshSec as Number;

    private var _airPending as Boolean;
    private var _lastAirSec as Number;

    // adsbdb detail caches (resolved on demand for the focused aircraft)
    private var _type as Dictionary;       // icao24 -> compact type label ("" unknown)
    private var _route as Dictionary;      // callsign -> compact route label ("" unknown)
    private var _typeInfo as Dictionary;   // icao24 -> raw aircraft dict
    private var _routeInfo as Dictionary;  // callsign -> raw flightroute dict
    private var _metaPending as Boolean;
    private var _lastMetaSec as Number;
    private var _metaTypeKey as String?;
    private var _metaRouteKey as String?;

    function initialize() {
        lat = null;
        lon = null;
        gpsQuality = 0;
        posApprox = false;
        headingDeg = 0.0;
        planes = [] as Array<Plane>;
        targetPlane = null;
        status = STATUS_IDLE;
        errCode = 0;
        radiusM = 10000;
        refreshSec = 30;
        _airPending = false;
        _lastAirSec = 0;
        _type = {} as Dictionary;
        _route = {} as Dictionary;
        _typeInfo = {} as Dictionary;
        _routeInfo = {} as Dictionary;
        _metaPending = false;
        _lastMetaSec = 0;
        _metaTypeKey = null;
        _metaRouteKey = null;
        reloadSettings();
    }

    function start() as Void {
        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS,
                                      method(:onPosition));
        var info = Position.getInfo();
        if (info != null && info.position != null) {
            var deg = info.position.toDegrees();
            lat = deg[0].toDouble();
            lon = deg[1].toDouble();
            var q = (info.accuracy != null) ? info.accuracy as Number : 0;
            gpsQuality = q;
            posApprox = (q < Position.QUALITY_USABLE);
        }
    }

    function stop() as Void {
        Position.enableLocationEvents(Position.LOCATION_DISABLE,
                                      method(:onPosition));
    }

    function reloadSettings() as Void {
        radiusM = getNumProp("radiusMeters", 10000);
        if (radiusM < 1000) { radiusM = 1000; }
        if (radiusM > 20000) { radiusM = 20000; }
        refreshSec = getNumProp("refreshSec", 30);
        if (refreshSec < 15) { refreshSec = 15; }
    }

    private function getNumProp(key as String, def as Number) as Number {
        var v = null;
        try {
            v = Application.Properties.getValue(key);
        } catch (e) {
            v = null;
        }
        return (v instanceof Number) ? v : def;
    }

    // ---- position / heading ----

    function onPosition(info as Position.Info) as Void {
        if (info.position != null) {
            var deg = info.position.toDegrees();
            lat = deg[0].toDouble();
            lon = deg[1].toDouble();
            if (info.accuracy != null) {
                gpsQuality = info.accuracy as Number;
                if (gpsQuality >= Position.QUALITY_USABLE) { posApprox = false; }
            }
            updateGeometry();
        }
    }

    // Called ~5x/s from the view timer.
    function tick() as Void {
        var si = Sensor.getInfo();
        if (si != null && si.heading != null) {
            headingDeg = GeoUtils.normDeg(Math.toDegrees(si.heading).toFloat());
        }
        if (lat == null) { return; }
        var now = Time.now().value();
        maybeFetch(now);
        resolveFocused();
    }

    private function updateGeometry() as Void {
        if (lat == null) { return; }
        var la = lat as Double;
        var lo = lon as Double;
        for (var i = 0; i < planes.size(); i++) {
            var p = planes[i];
            p.distance = GeoUtils.distanceM(la, lo, p.lat, p.lon);
            p.bearing = GeoUtils.bearingDeg(la, lo, p.lat, p.lon);
        }
        var t = targetPlane;
        if (t != null) {
            t.distance = GeoUtils.distanceM(la, lo, t.lat, t.lon);
            t.bearing = GeoUtils.bearingDeg(la, lo, t.lat, t.lon);
        }
        GeoUtils.sortByDistance(planes);
    }

    // The aircraft featured on screen: locked target, else nearest within the
    // +-35 deg cone ahead, else nearest overall.
    function focusedPlane() as Plane? {
        if (targetPlane != null) { return targetPlane; }
        var best = null;
        var bestDist = 99999999.0;
        for (var i = 0; i < planes.size(); i++) {
            var p = planes[i];
            var d = GeoUtils.angleDiff(p.bearing, headingDeg);
            if (d < 0) { d = -d; }
            if (d <= 35.0 && p.distance < bestDist) {
                best = p;
                bestDist = p.distance;
            }
        }
        if (best == null && planes.size() > 0) {
            best = planes[0];
        }
        return best;
    }

    // ---- OpenSky (positions) ----

    private function maybeFetch(now as Number) as Void {
        if (_airPending || _metaPending) { return; }
        var since = now - _lastAirSec;
        if (status == STATUS_ERROR) {
            if (since >= 8) { fetch(now); }
        } else if (_lastAirSec == 0 || since >= refreshSec) {
            fetch(now);
        }
    }

    private function fetch(now as Number) as Void {
        _airPending = true;
        status = STATUS_LOADING;
        _lastAirSec = now;
        var la = lat as Double;
        var lo = lon as Double;
        var dLat = radiusM / 111320.0;
        var cosLat = Math.cos(Math.toRadians(la));
        if (cosLat < 0.05) { cosLat = 0.05; }
        var dLon = radiusM / (111320.0 * cosLat);
        var params = {
            "lamin" => (la - dLat).format("%.4f"),
            "lomin" => (lo - dLon).format("%.4f"),
            "lamax" => (la + dLat).format("%.4f"),
            "lomax" => (lo + dLon).format("%.4f")
        };
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        Communications.makeWebRequest(OPENSKY_URL, params, options,
                                      method(:onAirResponse));
    }

    function onAirResponse(code as Number, data as Dictionary or String or Null) as Void {
        _airPending = false;
        if (code == 200 && data instanceof Dictionary) {
            var fresh = [] as Array<Plane>;
            var states = data["states"];
            if (states instanceof Array) {
                for (var i = 0; i < states.size(); i++) {
                    if (fresh.size() >= MAX_PLANES) { break; }
                    var s = states[i];
                    if (!(s instanceof Array) || s.size() < 11) { continue; }
                    if (s[8] == true) { continue; }   // on the ground
                    var plat = numToD(s[6]);
                    var plon = numToD(s[5]);
                    if (plat == null || plon == null) { continue; }
                    var cs = "";
                    if (s[1] instanceof String) { cs = trim(s[1]); }
                    var icao = "";
                    if (s[0] instanceof String) { icao = trim(s[0]); }
                    var p = new Plane(cs, plat, plon, icao);
                    var alt = numToD(s[7]);
                    if (alt != null) { p.altM = alt.toNumber(); }
                    var vel = numToD(s[9]);
                    if (vel != null) { p.speedKmh = (vel * 3.6).toNumber(); }
                    var tr = numToD(s[10]);
                    if (tr != null) { p.track = tr.toFloat(); }
                    fresh.add(p);
                }
            }
            // keep the locked target across refreshes by matching icao24
            var keepTarget = null;
            var t = targetPlane;
            if (t != null) {
                for (var i = 0; i < fresh.size(); i++) {
                    if (fresh[i].icao24.equals(t.icao24)) { keepTarget = fresh[i]; break; }
                }
            }
            planes = fresh;
            targetPlane = keepTarget;
            status = STATUS_IDLE;
            errCode = 0;
            updateGeometry();
        } else {
            status = STATUS_ERROR;
            errCode = code;
        }
        WatchUi.requestUpdate();
    }

    // ---- adsbdb (type + route for the focused aircraft) ----

    function aircraftType(icao24 as String) as String? {
        if (icao24.length() == 0) { return null; }
        return _type.get(icao24);
    }

    function aircraftRoute(callsign as String) as String? {
        if (callsign.length() == 0) { return null; }
        return _route.get(callsign);
    }

    function aircraftInfo(icao24 as String) as Dictionary? {
        var v = _typeInfo.get(icao24);
        return (v instanceof Dictionary) ? v : null;
    }

    function flightInfo(callsign as String) as Dictionary? {
        var v = _routeInfo.get(callsign);
        return (v instanceof Dictionary) ? v : null;
    }

    private function resolveFocused() as Void {
        var f = focusedPlane();
        if (f != null) { resolvePlane(f); }
    }

    // Resolve type/route for a specific aircraft. Public so the detail page can
    // keep it progressing while the main view's timer is paused.
    function resolvePlane(f as Plane) as Void {
        if (_metaPending || _airPending) { return; }
        var now = Time.now().value();
        if (now - _lastMetaSec < 2) { return; }
        if (f.icao24.length() > 0 && _type.get(f.icao24) == null) {
            _metaPending = true;
            _lastMetaSec = now;
            _metaTypeKey = f.icao24;
            Communications.makeWebRequest(ADSBDB_AIRCRAFT_URL + f.icao24, {},
                                          metaOptions(), method(:onTypeResponse));
            return;
        }
        if (f.callsign.length() > 0 && _route.get(f.callsign) == null) {
            _metaPending = true;
            _lastMetaSec = now;
            _metaRouteKey = f.callsign;
            Communications.makeWebRequest(ADSBDB_CALLSIGN_URL + f.callsign, {},
                                          metaOptions(), method(:onRouteResponse));
        }
    }

    private function metaOptions() as Dictionary {
        return {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
    }

    function onTypeResponse(code as Number, data as Dictionary or String or Null) as Void {
        _metaPending = false;
        var key = _metaTypeKey;
        _metaTypeKey = null;
        if (key == null) { return; }
        var label = "";
        if (code == 200 && data instanceof Dictionary) {
            var resp = data["response"];
            if (resp instanceof Dictionary) {
                var ac = resp["aircraft"];
                if (ac instanceof Dictionary) {
                    label = buildTypeLabel(ac);
                    _typeInfo.put(key, ac);
                }
            }
        }
        _type.put(key, label);
        WatchUi.requestUpdate();
    }

    private function buildTypeLabel(ac as Dictionary) as String {
        var t = ac["icao_type"];
        if (!(t instanceof String) || t.length() == 0) { t = ac["type"]; }
        var label = "";
        var manuf = ac["manufacturer"];
        if (manuf instanceof String && manuf.length() > 0) { label = manuf; }
        if (t instanceof String && t.length() > 0) {
            label = (label.length() > 0) ? (label + " " + t) : t;
        }
        var owner = ac["registered_owner"];
        if (owner instanceof String && owner.length() > 0) {
            label = (label.length() > 0) ? (label + " - " + owner) : owner;
        }
        return label;
    }

    function onRouteResponse(code as Number, data as Dictionary or String or Null) as Void {
        _metaPending = false;
        var key = _metaRouteKey;
        _metaRouteKey = null;
        if (key == null) { return; }
        var label = "";
        if (code == 200 && data instanceof Dictionary) {
            var resp = data["response"];
            if (resp instanceof Dictionary) {
                var fr = resp["flightroute"];
                if (fr instanceof Dictionary) {
                    label = buildRouteLabel(fr);
                    _routeInfo.put(key, fr);
                }
            }
        }
        _route.put(key, label);
        WatchUi.requestUpdate();
    }

    private function buildRouteLabel(fr as Dictionary) as String {
        var origin = airportField(fr["origin"], "iata_code");
        var dest = fr["destination"];
        var dCode = airportField(dest, "iata_code");
        var dCity = airportField(dest, "municipality");
        var label = "";
        if (origin.length() > 0) { label = origin + " "; }
        label += "-> ";
        if (dCode.length() > 0) { label += dCode; }
        if (dCity.length() > 0) { label += " " + dCity; }
        return label;
    }

    function airportField(ap, field as String) as String {
        if (ap instanceof Dictionary) {
            var v = ap[field];
            if (v instanceof String) { return v; }
        }
        return "";
    }

    // ---- helpers ----

    private function numToD(v) as Double? {
        if (v instanceof Double) { return v; }
        if (v instanceof Float || v instanceof Number || v instanceof Long) {
            return v.toDouble();
        }
        return null;
    }

    private function trim(s as String) as String {
        var chars = s.toCharArray();
        var start = 0;
        var end = chars.size();
        while (start < end && chars[start] == ' ') { start++; }
        while (end > start && chars[end - 1] == ' ') { end--; }
        if (start == 0 && end == chars.size()) { return s; }
        return s.substring(start, end);
    }
}
