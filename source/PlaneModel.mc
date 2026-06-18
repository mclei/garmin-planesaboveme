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
// hexdb.io (free, keyless): used only to correct an adsbdb route that looks
// stale. Returns the current ICAO pairing ("LKPR-EGPH") plus per-airport detail.
const HEXDB_ROUTE_URL = "https://hexdb.io/api/v1/route/icao/";
const HEXDB_AIRPORT_URL = "https://hexdb.io/api/v1/airport/icao/";

const MAX_PLANES = 30;

// A callsign->route mapping (adsbdb) is treated as stale when the aircraft sits
// well off the direct origin->destination corridor: detour = dist(plane,origin)
// + dist(plane,dest) - dist(origin,dest). Stale if detour exceeds the larger of
// a fixed floor and a fraction of the direct distance.
const ROUTE_STALE_DETOUR_M = 200000.0;  // 200 km floor
const ROUTE_STALE_FRACTION = 0.5;

// Compass smoothing: ignore heading jitter smaller than the deadband, and ease
// toward larger (real) changes so the display doesn't twitch with magnetometer
// noise.
const HEADING_DEADBAND = 2.0;  // degrees
const HEADING_SMOOTH = 0.5;    // 0..1 fraction moved toward a new reading

class PlaneModel {

    public var lat as Double?;
    public var lon as Double?;
    public var gpsQuality as Number;
    public var posApprox as Boolean;
    public var headingDeg as Float;
    private var _haveHeading as Boolean;

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

    // hexdb stale-route fallback state
    private var _routeStaleChecked as Dictionary;  // callsign -> Bool (decided)
    private var _routeCorrected as Dictionary;     // callsign -> Bool (via hexdb)
    private var _hexKey as String?;                // callsign being corrected
    private var _hexOrigIcao as String?;
    private var _hexDestIcao as String?;
    private var _hexOrigAp as Dictionary?;
    private var _hexDestAp as Dictionary?;

    function initialize() {
        lat = null;
        lon = null;
        gpsQuality = 0;
        posApprox = false;
        headingDeg = 0.0;
        _haveHeading = false;
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
        _routeStaleChecked = {} as Dictionary;
        _routeCorrected = {} as Dictionary;
        _hexKey = null;
        _hexOrigIcao = null;
        _hexDestIcao = null;
        _hexOrigAp = null;
        _hexDestAp = null;
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
            var raw = GeoUtils.normDeg(Math.toDegrees(si.heading).toFloat());
            if (!_haveHeading) {
                headingDeg = raw;          // first reading: take it as-is (no startup sweep)
                _haveHeading = true;
            } else {
                var diff = GeoUtils.angleDiff(raw, headingDeg);
                if (diff > HEADING_DEADBAND || diff < -HEADING_DEADBAND) {
                    headingDeg = GeoUtils.normDeg(headingDeg + diff * HEADING_SMOOTH);
                }
            }
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

    // True when this callsign's route was replaced by the hexdb.io fallback
    // because adsbdb's pairing looked stale. Drives the on-screen indicator.
    function routeIsCorrected(callsign as String) as Boolean {
        if (callsign.length() == 0) { return false; }
        return _routeCorrected.get(callsign) != null;
    }

    // True once the route is fully resolved, including the staleness check and
    // any hexdb correction. The detail page polls this so it keeps ticking until
    // a corrected route has landed.
    function routeSettled(callsign as String) as Boolean {
        if (callsign.length() == 0) { return true; }
        if (_route.get(callsign) == null) { return false; }      // adsbdb pending
        if (_routeStaleChecked.get(callsign) == null) { return false; }
        if (_hexKey != null && _hexKey.equals(callsign)) { return false; }
        return true;
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
            return;
        }
        // adsbdb route is present: verify it isn't a stale callsign pairing and,
        // if it is, replace it with hexdb.io's current route.
        resolveStaleRoute(f, now);
    }

    // Drives the hexdb fallback one request per call (serialised via the same
    // _metaPending gate as the adsbdb lookups). Only kicks in when adsbdb's
    // route puts the aircraft well off the corridor between its airports.
    private function resolveStaleRoute(f as Plane, now as Number) as Void {
        var cs = f.callsign;
        if (cs.length() == 0) { return; }
        if (_hexKey != null) {
            if (!_hexKey.equals(cs)) { return; }   // busy correcting another flight
            if (_hexOrigIcao != null && _hexOrigAp == null) {
                _metaPending = true;
                _lastMetaSec = now;
                Communications.makeWebRequest(HEXDB_AIRPORT_URL + _hexOrigIcao, {},
                                              metaOptions(), method(:onHexOriginResponse));
                return;
            }
            if (_hexDestIcao != null && _hexDestAp == null) {
                _metaPending = true;
                _lastMetaSec = now;
                Communications.makeWebRequest(HEXDB_AIRPORT_URL + _hexDestIcao, {},
                                              metaOptions(), method(:onHexDestResponse));
            }
            return;
        }
        if (_routeStaleChecked.get(cs) != null) { return; }  // decided already
        _routeStaleChecked.put(cs, true);
        var fr = _routeInfo.get(cs);
        if (!(fr instanceof Dictionary) || !isRouteStale(f, fr)) { return; }
        // Stale -> look up the current route from hexdb.io.
        _hexKey = cs;
        _hexOrigIcao = null;
        _hexDestIcao = null;
        _hexOrigAp = null;
        _hexDestAp = null;
        _metaPending = true;
        _lastMetaSec = now;
        Communications.makeWebRequest(HEXDB_ROUTE_URL + cs, {},
                                      metaOptions(), method(:onHexRouteResponse));
    }

    // True when the aircraft is too far off the direct origin->dest corridor for
    // the adsbdb route to plausibly be this flight's actual route.
    private function isRouteStale(f as Plane, fr as Dictionary) as Boolean {
        var o = fr["origin"];
        var d = fr["destination"];
        if (!(o instanceof Dictionary) || !(d instanceof Dictionary)) { return false; }
        var olat = numToD(o["latitude"]);
        var olon = numToD(o["longitude"]);
        var dlat = numToD(d["latitude"]);
        var dlon = numToD(d["longitude"]);
        if (olat == null || olon == null || dlat == null || dlon == null) {
            return false;
        }
        var dpo = GeoUtils.distanceM(f.lat, f.lon, olat, olon);
        var dpd = GeoUtils.distanceM(f.lat, f.lon, dlat, dlon);
        var dod = GeoUtils.distanceM(olat, olon, dlat, dlon);
        var tol = ROUTE_STALE_DETOUR_M;
        if (dod * ROUTE_STALE_FRACTION > tol) { tol = dod * ROUTE_STALE_FRACTION; }
        return (dpo + dpd - dod) > tol;
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

    // ---- hexdb.io stale-route correction ----

    function onHexRouteResponse(code as Number, data as Dictionary or String or Null) as Void {
        _metaPending = false;
        if (_hexKey == null) { return; }
        var route = null;
        if (code == 200 && data instanceof Dictionary && data["route"] instanceof String) {
            route = data["route"] as String;
        }
        var eps = (route != null) ? hexEndpoints(route) : null;
        if (eps == null) {
            _hexKey = null;          // hexdb couldn't help; keep adsbdb's route
        } else {
            _hexOrigIcao = eps[0];
            _hexDestIcao = eps[1];
        }
        WatchUi.requestUpdate();
    }

    function onHexOriginResponse(code as Number, data as Dictionary or String or Null) as Void {
        _metaPending = false;
        if (_hexKey == null) { return; }
        _hexOrigAp = hexAirport(code, data, _hexOrigIcao);
        finishHexIfReady();
        WatchUi.requestUpdate();
    }

    function onHexDestResponse(code as Number, data as Dictionary or String or Null) as Void {
        _metaPending = false;
        if (_hexKey == null) { return; }
        _hexDestAp = hexAirport(code, data, _hexDestIcao);
        finishHexIfReady();
        WatchUi.requestUpdate();
    }

    // Once both endpoints are resolved, reshape them into the adsbdb flightroute
    // structure and overwrite the cached route, so the views render unchanged.
    private function finishHexIfReady() as Void {
        if (_hexKey == null || _hexOrigAp == null || _hexDestAp == null) { return; }
        var fr = { "origin" => _hexOrigAp, "destination" => _hexDestAp };
        _routeInfo.put(_hexKey, fr);
        _route.put(_hexKey, buildRouteLabel(fr));
        _routeCorrected.put(_hexKey, true);
        _hexKey = null;
        _hexOrigIcao = null;
        _hexDestIcao = null;
        _hexOrigAp = null;
        _hexDestAp = null;
    }

    // "LKPR-EGPH" (or "A-B-C") -> [firstICAO, lastICAO]; null if unparseable.
    private function hexEndpoints(route as String) as Array<String>? {
        var chars = route.toCharArray();
        var first = -1;
        var last = -1;
        for (var i = 0; i < chars.size(); i++) {
            if (chars[i] == '-') {
                if (first < 0) { first = i; }
                last = i;
            }
        }
        if (first < 0) { return null; }
        var o = route.substring(0, first);
        var d = route.substring(last + 1, route.length());
        if (o == null || d == null || o.length() == 0 || d.length() == 0) {
            return null;
        }
        return [o, d];
    }

    // Build an adsbdb-shaped airport dict from a hexdb airport response. Always
    // returns a dict (falling back to the ICAO code) so From/To still shows.
    private function hexAirport(code as Number, data as Dictionary or String or Null,
                                icao as String?) as Dictionary {
        var name = "";
        var iata = "";
        var region = "";
        if (code == 200 && data instanceof Dictionary) {
            if (data["airport"] instanceof String) { name = data["airport"] as String; }
            if (data["iata"] instanceof String) { iata = data["iata"] as String; }
            if (data["region_name"] instanceof String) { region = data["region_name"] as String; }
        }
        return {
            "iata_code" => iata,
            "icao_code" => (icao != null) ? icao : "",
            "municipality" => "",
            "name" => name,
            "country_name" => region
        };
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
