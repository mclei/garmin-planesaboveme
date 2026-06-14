import Toybox.Lang;
import Toybox.WatchUi;

module PlanesUi {

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
        WatchUi.pushView(menu, new PlaneListDelegate(model, list), WatchUi.SLIDE_LEFT);
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
}
