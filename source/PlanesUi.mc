import Toybox.Lang;
import Toybox.WatchUi;

module PlanesUi {

    const RADIUS_VALUES = [2000, 5000, 10000, 15000, 20000];   // m
    const INTERVAL_VALUES = [15, 30, 60, 120];                 // s

    // Main menu: nearby list, refresh, the two settings (also in the phone
    // settings) and About.
    function pushMainMenu(model as PlaneModel) as Void {
        var menu = new WatchUi.Menu2({ :title => WatchUi.loadResource(Rez.Strings.MenuTitle) });
        menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.MenuNearby) as String,
            null, :nearby, null));
        menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.MenuRefresh) as String,
            null, :refresh, null));
        menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.MenuRadius) as String,
            radiusLabel(model.radiusM), :radius, null));
        menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.MenuInterval) as String,
            model.refreshSec.toString() + " s", :interval, null));
        menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.MenuAbout) as String,
            null, :about, null));
        // Opened by the right-edge swipe -> slide in from the right.
        WatchUi.pushView(menu, new MainMenuDelegate(model), WatchUi.SLIDE_LEFT);
    }

    function radiusLabel(m as Number) as String {
        return (m / 1000).toString() + " km";
    }

    // List of values; the cursor starts on the current one.
    function pushChoice(model as PlaneModel, id as Symbol) as Void {
        var radius = id == :radius;
        var values = radius ? RADIUS_VALUES : INTERVAL_VALUES;
        var cur = radius ? model.radiusM : model.refreshSec;
        var menu = new WatchUi.Menu2({ :title => WatchUi.loadResource(
            radius ? Rez.Strings.MenuRadius : Rez.Strings.MenuInterval) });
        var focus = 0;
        for (var i = 0; i < values.size(); i++) {
            var v = values[i];
            menu.addItem(new WatchUi.MenuItem(radius ? radiusLabel(v) : v.toString() + " s", null, i, null));
            if (v == cur) { focus = i; }
        }
        menu.setFocus(focus);
        WatchUi.pushView(menu, new ChoiceDelegate(model, id, values), WatchUi.SLIDE_LEFT);
    }

    function pushList(model as PlaneModel) as Void {
        var list = model.planes;
        var menu = new WatchUi.Menu2({
            :title => WatchUi.loadResource(Rez.Strings.MenuNearby)
        });
        if (list.size() == 0) {
            menu.addItem(new WatchUi.MenuItem(
                WatchUi.loadResource(Rez.Strings.NoPlanes) as String, null, -1, null));
        }
        var n = list.size();
        if (n > 30) { n = 30; }
        for (var i = 0; i < n; i++) {
            var p = list[i];
            var sub = GeoUtils.formatDistance(p.distance)
                    + " " + GeoUtils.cardinal(p.bearing);
            if (p.altM >= 0) { sub += " | " + p.altM.toString() + " m"; }
            menu.addItem(new WatchUi.MenuItem(p.label(), sub, i, null));
        }
        // Opened by the swipe-up gesture -> slide up from the bottom.
        WatchUi.pushView(menu, new PlaneListDelegate(model, list), WatchUi.SLIDE_UP);
    }

    function pushDetail(model as PlaneModel, plane as Plane) as Void {
        var v = new DetailView(model, plane);
        WatchUi.pushView(v, new DetailDelegate(v), WatchUi.SLIDE_LEFT);
    }
}

class PlaneListDelegate extends WatchUi.Menu2InputDelegate {

    private var _model as PlaneModel;
    private var _items as Array<Plane>;

    function initialize(model as PlaneModel, items as Array<Plane>) {
        Menu2InputDelegate.initialize();
        _model = model;
        _items = items;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id instanceof Number && id >= 0 && id < _items.size()) {
            PlanesUi.pushDetail(_model, _items[id]);
        }
    }

    // Reverse of the slide-up it opened with.
    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class MainMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _model as PlaneModel;

    function initialize(model as PlaneModel) {
        Menu2InputDelegate.initialize();
        _model = model;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :nearby) {
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            PlanesUi.pushList(_model);
        } else if (id == :refresh) {
            _model.refreshNow();
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        } else if (id == :radius || id == :interval) {
            PlanesUi.pushChoice(_model, id as Symbol);
        } else if (id == :about) {
            WatchUi.pushView(new AboutView(), new WatchUi.BehaviorDelegate(), WatchUi.SLIDE_LEFT);
        }
    }

    // Reverse of the slide-left it opened with.
    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

// Applies the chosen value and reopens the main menu so it shows the new value.
class ChoiceDelegate extends WatchUi.Menu2InputDelegate {

    private var _model as PlaneModel;
    private var _id as Symbol;
    private var _values as Array<Number>;

    function initialize(model as PlaneModel, id as Symbol, values as Array<Number>) {
        Menu2InputDelegate.initialize();
        _model = model;
        _id = id;
        _values = values;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var v = _values[item.getId() as Number];
        _model.setNumProp(_id == :radius ? "radiusMeters" : "refreshSec", v);
        if (_id == :radius) { _model.refreshNow(); }   // new area -> fetch now
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);      // choice list
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);      // old main menu
        PlanesUi.pushMainMenu(_model);
    }
}
