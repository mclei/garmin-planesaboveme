import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

// Scrollable detail page for one aircraft: full route, type, operator,
// registration, altitude/speed/track. Start toggles a lock on this aircraft.
class DetailView extends WatchUi.View {

    private var _model as PlaneModel;
    private var _plane as Plane;
    private var _scroll as Number;
    private var _maxScroll as Number;
    private var _timer as Timer.Timer?;

    function initialize(model as PlaneModel, plane as Plane) {
        View.initialize();
        _model = model;
        _plane = plane;
        _scroll = 0;
        _maxScroll = 0;
        _timer = null;
    }

    function onShow() as Void {
        var t = new Timer.Timer();
        t.start(method(:onTick), 500, true);
        _timer = t;
        onTick();
    }

    function onHide() as Void {
        var t = _timer;
        if (t != null) { t.stop(); _timer = null; }
    }

    function onTick() as Void {
        _model.resolvePlane(_plane);
        var typeDone = (_plane.icao24.length() == 0)
                     || (_model.aircraftType(_plane.icao24) != null);
        var routeDone = (_plane.callsign.length() == 0)
                      || (_model.aircraftRoute(_plane.callsign) != null);
        if (typeDone && routeDone) {
            var t = _timer;
            if (t != null) { t.stop(); _timer = null; }
        }
        WatchUi.requestUpdate();
    }

    function scrollBy(dy as Number) as Void {
        _scroll += dy;
        if (_scroll > _maxScroll) { _scroll = _maxScroll; }
        if (_scroll < 0) { _scroll = 0; }
        WatchUi.requestUpdate();
    }

    function toggleTarget() as Void {
        if (_model.targetPlane == _plane) {
            _model.targetPlane = null;
        } else {
            _model.targetPlane = _plane;
        }
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var margin = (w * 0.08).toNumber();
        var maxW = w - 2 * margin;

        var blocks = buildBlocks();

        var total = 8;
        for (var i = 0; i < blocks.size(); i++) {
            var fh = dc.getFontHeight(blocks[i][1]);
            total += wrapText(dc, blocks[i][0], blocks[i][1], maxW).size() * fh + 2;
        }
        total += 8;
        _maxScroll = total - h;
        if (_maxScroll < 0) { _maxScroll = 0; }
        if (_scroll > _maxScroll) { _scroll = _maxScroll; }

        var y = 8 - _scroll;
        for (var i = 0; i < blocks.size(); i++) {
            var font = blocks[i][1];
            var fh = dc.getFontHeight(font);
            var lines = wrapText(dc, blocks[i][0], font, maxW);
            for (var j = 0; j < lines.size(); j++) {
                if (y + fh > 0 && y < h) {
                    dc.setColor(blocks[i][2], Graphics.COLOR_TRANSPARENT);
                    dc.drawText(margin, y, font, lines[j], Graphics.TEXT_JUSTIFY_LEFT);
                }
                y += fh + 2;
            }
        }

        if (_maxScroll > 0) {
            var barH = (h * h) / total;
            if (barH < 16) { barH = 16; }
            var pos = ((h - barH) * _scroll) / _maxScroll;
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(w - 4, pos, 3, barH);
        }

        // Fixed lock badge (top-right), drawn over the scrolling content so the
        // lock state is visible immediately when START toggles it.
        drawLockBadge(dc, w);
    }

    // Always-visible badge showing whether this aircraft is the locked target.
    private function drawLockBadge(dc as Dc, w as Number) as Void {
        var locked = (_model.targetPlane == _plane);
        var txt = locked ? "LOCKED" : "UNLOCKED";
        var font = Graphics.FONT_XTINY;
        var tw = dc.getTextWidthInPixels(txt, font);
        var fh = dc.getFontHeight(font);
        var bw = tw + 12;
        var bh = fh + 4;
        var bx = w - bw - 8;
        var by = 4;
        // Mask the content underneath so the badge stays legible.
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillRectangle(bx - 2, by - 2, bw + 4, bh + 4);
        if (locked) {
            dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(bx, by, bw, bh, 4);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        } else {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawRoundedRectangle(bx, by, bw, bh, 4);
        }
        dc.drawText(bx + 6, by + 2, font, txt, Graphics.TEXT_JUSTIFY_LEFT);
    }

    private function buildBlocks() as Array {
        var b = [] as Array;
        b.add([_plane.label(), Graphics.FONT_MEDIUM, Graphics.COLOR_WHITE]);

        var fr = _model.flightInfo(_plane.callsign);
        if (fr != null) {
            addField(b, "From", airportLine(fr["origin"]));
            addField(b, "To", airportLine(fr["destination"]));
        } else if (_plane.callsign.length() == 0) {
            b.add(["No callsign", Graphics.FONT_XTINY, Graphics.COLOR_DK_GRAY]);
        } else if (_model.aircraftRoute(_plane.callsign) == null) {
            b.add(["Resolving route...", Graphics.FONT_XTINY, Graphics.COLOR_DK_GRAY]);
        } else {
            b.add(["Route unknown", Graphics.FONT_XTINY, Graphics.COLOR_DK_GRAY]);
        }
        b.add(["", Graphics.FONT_XTINY, Graphics.COLOR_BLACK]);

        var ac = _model.aircraftInfo(_plane.icao24);
        if (ac != null) {
            var type = tagStr(ac, "type");
            var manuf = tagStr(ac, "manufacturer");
            if (manuf.length() > 0) { type = manuf + " " + type; }
            addField(b, "Type", type);
            addField(b, "ICAO type", tagStr(ac, "icao_type"));
            addField(b, "Operator", tagStr(ac, "registered_owner"));
            addField(b, "Reg.", tagStr(ac, "registration"));
            addField(b, "Country", tagStr(ac, "registered_owner_country_name"));
        } else if (_plane.icao24.length() > 0
                   && _model.aircraftType(_plane.icao24) == null) {
            b.add(["Resolving type...", Graphics.FONT_XTINY, Graphics.COLOR_DK_GRAY]);
        }
        b.add(["", Graphics.FONT_XTINY, Graphics.COLOR_BLACK]);

        if (_plane.altM >= 0) {
            addField(b, "Altitude", _plane.altM.toString() + " m");
        }
        if (_plane.speedKmh >= 0) {
            addField(b, "Speed", _plane.speedKmh.toString() + " km/h");
        }
        if (_plane.track != null) {
            addField(b, "Track", (_plane.track as Float).toNumber().toString() + " deg");
        }
        addField(b, "Distance", GeoUtils.formatDistance(_plane.distance)
                 + " " + GeoUtils.cardinal(_plane.bearing));

        b.add(["", Graphics.FONT_XTINY, Graphics.COLOR_BLACK]);
        var locked = (_model.targetPlane == _plane) ? "locked" : "not locked";
        b.add(["START: lock/unlock (" + locked + ")",
               Graphics.FONT_XTINY, Graphics.COLOR_DK_GRAY]);
        b.add(["Swipe / buttons to scroll, BACK to close",
               Graphics.FONT_XTINY, Graphics.COLOR_DK_GRAY]);
        return b;
    }

    private function addField(b as Array, label as String, value as String) as Void {
        if (value == null || value.length() == 0) { return; }
        b.add([label + ": " + value, Graphics.FONT_XTINY, Graphics.COLOR_WHITE]);
    }

    private function tagStr(d as Dictionary, key as String) as String {
        var v = d[key];
        return (v instanceof String) ? v : "";
    }

    private function airportLine(ap) as String {
        if (!(ap instanceof Dictionary)) { return ""; }
        var city = tagStr(ap, "municipality");
        var iata = tagStr(ap, "iata_code");
        var name = tagStr(ap, "name");
        var s = (city.length() > 0) ? city : name;
        if (iata.length() > 0) {
            s = (s.length() > 0) ? (s + " (" + iata + ")") : iata;
        }
        return s;
    }

    private function wrapText(dc as Dc, text as String, font as Graphics.FontType,
                              maxW as Number) as Array<String> {
        var out = [] as Array<String>;
        if (text.length() == 0) { out.add(""); return out; }
        var words = splitSpaces(text);
        var line = "";
        for (var i = 0; i < words.size(); i++) {
            var trial = (line.length() == 0) ? words[i] : (line + " " + words[i]);
            if (dc.getTextWidthInPixels(trial, font) <= maxW) {
                line = trial;
            } else {
                if (line.length() > 0) { out.add(line); }
                line = words[i];
            }
        }
        if (line.length() > 0) { out.add(line); }
        if (out.size() == 0) { out.add(""); }
        return out;
    }

    private function splitSpaces(s as String) as Array<String> {
        var out = [] as Array<String>;
        var chars = s.toCharArray();
        var cur = "";
        for (var i = 0; i < chars.size(); i++) {
            if (chars[i] == ' ') {
                if (cur.length() > 0) { out.add(cur); cur = ""; }
            } else {
                cur += chars[i].toString();
            }
        }
        if (cur.length() > 0) { out.add(cur); }
        return out;
    }
}

class DetailDelegate extends WatchUi.BehaviorDelegate {

    private var _view as DetailView;

    function initialize(view as DetailView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onSwipe(evt as WatchUi.SwipeEvent) as Boolean {
        var d = evt.getDirection();
        if (d == WatchUi.SWIPE_UP) { _view.scrollBy(80); return true; }
        if (d == WatchUi.SWIPE_DOWN) { _view.scrollBy(-80); return true; }
        return false;
    }

    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        var k = evt.getKey();
        if (k == WatchUi.KEY_DOWN) { _view.scrollBy(80); return true; }
        if (k == WatchUi.KEY_UP) { _view.scrollBy(-80); return true; }
        return false;
    }

    function onNextPage() as Boolean { _view.scrollBy(160); return true; }
    function onPreviousPage() as Boolean { _view.scrollBy(-160); return true; }

    function onSelect() as Boolean { _view.toggleTarget(); return true; }
}
