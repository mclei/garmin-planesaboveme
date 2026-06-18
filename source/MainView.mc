import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Timer;
import Toybox.WatchUi;

const PLANE_COLOR = 0x00FFFF; // cyan

// Compass screen: rotating ring, every aircraft as a triangle (rotated to its
// ground track), and the aircraft you are facing shown large.
class MainView extends WatchUi.View {

    private var _model as PlaneModel;
    private var _timer as Timer.Timer?;

    function initialize(model as PlaneModel) {
        View.initialize();
        _model = model;
        _timer = null;
    }

    function onShow() as Void {
        var t = new Timer.Timer();
        t.start(method(:onTick), 200, true);
        _timer = t;
    }

    function onHide() as Void {
        var t = _timer;
        if (t != null) { t.stop(); _timer = null; }
    }

    function onTick() as Void {
        _model.tick();
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;
        var ring = ((w < h) ? w : h) / 2 - 10;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        drawCompassRing(dc, cx, cy, ring);

        if (_model.lat == null) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy - 12, Graphics.FONT_MEDIUM,
                        WatchUi.loadResource(Rez.Strings.WaitGps),
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.drawText(cx, cy + 18, Graphics.FONT_XTINY,
                        WatchUi.loadResource(Rez.Strings.Subtitle),
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            drawStatus(dc, cx, cy, ring, w, h);
            return;
        }

        drawPlaneDots(dc, cx, cy, ring);

        var f = _model.focusedPlane();
        if (f != null) {
            drawFocused(dc, cx, cy, ring, f);
        } else {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy, Graphics.FONT_SMALL,
                        WatchUi.loadResource(Rez.Strings.NoPlanes),
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        drawStatus(dc, cx, cy, ring, w, h);
    }

    private function drawCompassRing(dc as Dc, cx as Number, cy as Number,
                                     ring as Number) as Void {
        var hdg = _model.headingDeg;
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawCircle(cx, cy, ring);
        dc.setPenWidth(1);
        var labels = ["N", "E", "S", "W"];
        for (var deg = 0; deg < 360; deg += 45) {
            var a = Math.toRadians(GeoUtils.normDeg((deg - hdg).toFloat()));
            var sx = Math.sin(a);
            var sy = Math.cos(a);
            if (deg % 90 == 0) {
                var lx = cx + (ring - 18) * sx;
                var ly = cy - (ring - 18) * sy;
                dc.setColor((deg == 0) ? Graphics.COLOR_RED : Graphics.COLOR_LT_GRAY,
                            Graphics.COLOR_TRANSPARENT);
                dc.drawText(lx.toNumber(), ly.toNumber(), Graphics.FONT_TINY,
                            labels[deg / 90],
                            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            } else {
                dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
                var x1 = cx + (ring - 8) * sx;
                var y1 = cy - (ring - 8) * sy;
                var x2 = cx + ring * sx;
                var y2 = cy - ring * sy;
                dc.drawLine(x1.toNumber(), y1.toNumber(),
                            x2.toNumber(), y2.toNumber());
            }
        }
    }

    private function drawPlaneDots(dc as Dc, cx as Number, cy as Number,
                                   ring as Number) as Void {
        var hdg = _model.headingDeg;
        var list = _model.planes;
        var n = list.size();
        if (n > 30) { n = 30; }
        for (var i = n - 1; i >= 0; i--) {
            var p = list[i];
            var rr = p.distance / _model.radiusM.toFloat();
            if (rr > 1.0) { rr = 1.0; }
            rr = Math.sqrt(rr).toFloat();
            var rpx = (ring - 28) * rr;
            var a = Math.toRadians(GeoUtils.normDeg(p.bearing - hdg));
            var x = cx + rpx * Math.sin(a);
            var y = cy - rpx * Math.cos(a);
            dc.setColor(PLANE_COLOR, Graphics.COLOR_TRANSPARENT);
            var tr = (p.track != null) ? p.track as Float : 0.0;
            drawTriangle(dc, x.toFloat(), y.toFloat(),
                         GeoUtils.normDeg(tr - hdg), 9.0);
        }
    }

    private function drawFocused(dc as Dc, cx as Number, cy as Number,
                                 ring as Number, f as Plane) as Void {
        var hdg = _model.headingDeg;
        var rel = GeoUtils.angleDiff(f.bearing, hdg);
        var absRel = (rel < 0) ? -rel : rel;

        // direction arrow toward the aircraft
        var col = Graphics.COLOR_LT_GRAY;
        if (absRel <= 20.0) {
            col = Graphics.COLOR_GREEN;
        } else if (absRel <= 60.0) {
            col = Graphics.COLOR_YELLOW;
        }
        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        drawTriangle(dc, cx.toFloat(), (cy - ring * 0.45).toFloat(),
                     GeoUtils.normDeg(rel), ring * 0.17);

        if (_model.targetPlane != null) {
            dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy - (ring * 0.36).toNumber(), Graphics.FONT_XTINY,
                        "LOCKED",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        var maxW = (ring * 1.8).toNumber();
        var route = _model.aircraftRoute(f.callsign);
        var type = _model.aircraftType(f.icao24);

        // callsign
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - (ring * 0.22).toNumber(), Graphics.FONT_TINY,
                    fitText(dc, f.label(), Graphics.FONT_TINY, maxW),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // destination / route
        var routeText = (route == null) ? "resolving..."
                      : (route.length() == 0 ? "route n/a" : route);
        var shownRoute = fitText(dc, routeText, Graphics.FONT_SMALL, maxW);
        var routeY = cy - (ring * 0.04).toNumber();
        dc.setColor(PLANE_COLOR, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, routeY, Graphics.FONT_SMALL, shownRoute,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        // Green "H" marks a route corrected via the hexdb.io fallback.
        if (_model.routeIsCorrected(f.callsign)) {
            var rtw = dc.getTextWidthInPixels(shownRoute, Graphics.FONT_SMALL);
            dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx + rtw / 2 + 8, routeY, Graphics.FONT_XTINY, "H",
                        Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        // altitude
        var altText = (f.altM >= 0) ? (f.altM.toString() + " m") : "alt ?";
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + (ring * 0.15).toNumber(), Graphics.FONT_SMALL, altText,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // type
        var typeText = (type == null) ? "" : (type.length() == 0 ? "type n/a" : type);
        if (typeText.length() > 0) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy + (ring * 0.34).toNumber(), Graphics.FONT_XTINY,
                        fitText(dc, typeText, Graphics.FONT_XTINY, maxW),
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        // speed + distance
        var line = "";
        if (f.speedKmh >= 0) { line += f.speedKmh.toString() + " km/h"; }
        if (line.length() > 0) { line += "  "; }
        line += GeoUtils.formatDistance(f.distance);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + (ring * 0.50).toNumber(), Graphics.FONT_XTINY,
                    fitText(dc, line, Graphics.FONT_XTINY, maxW),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawStatus(dc as Dc, cx as Number, cy as Number,
                                ring as Number, w as Number, h as Number) as Void {
        var hdg = _model.headingDeg;
        var approx = (_model.posApprox && _model.lat != null) ? "~" : "";
        var s = approx + hdg.toNumber().toString() + " " + GeoUtils.cardinal(hdg) + " | ";
        if (_model.lat == null) {
            s += "no fix";
        } else if (_model.status == STATUS_LOADING) {
            s += WatchUi.loadResource(Rez.Strings.Loading);
        } else if (_model.status == STATUS_ERROR) {
            s += "err " + _model.errCode.toString();
        } else {
            s += _model.planes.size().toString() + " aircraft";
        }
        var bottomMargin = h - (cy + ring);
        var sy = (bottomMargin >= 20) ? (cy + ring + bottomMargin / 2)
                                      : (cy + ring - 18);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, sy, Graphics.FONT_XTINY, s,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Filled triangle pointing at angleDeg (0 = up, clockwise), centered on x,y
    private function drawTriangle(dc as Dc, x as Float, y as Float,
                                  angleDeg as Float, size as Float) as Void {
        var a = Math.toRadians(angleDeg);
        var s = Math.sin(a);
        var c = Math.cos(a);
        var pts = [
            [0.0, -size],
            [0.62 * size, 0.55 * size],
            [0.0, 0.22 * size],
            [-0.62 * size, 0.55 * size]
        ];
        var poly = [] as Array< Array<Number> >;
        for (var i = 0; i < pts.size(); i++) {
            var px = pts[i][0];
            var py = pts[i][1];
            poly.add([
                (x + px * c - py * s).toNumber(),
                (y + px * s + py * c).toNumber()
            ]);
        }
        dc.fillPolygon(poly);
    }

    private function fitText(dc as Dc, text as String, font as Graphics.FontType,
                             maxW as Number) as String {
        if (dc.getTextWidthInPixels(text, font) <= maxW) {
            return text;
        }
        var t = text;
        while (t.length() > 2
               && dc.getTextWidthInPixels(t + "..", font) > maxW) {
            t = t.substring(0, t.length() - 1);
        }
        return t + "..";
    }
}
