import Toybox.Lang;
import Toybox.WatchUi;

// Input mapping for the compass screen.
//   Tap, or Start/Enter button .. detail page of the aircraft you're facing
//   Swipe up .................... list of nearby aircraft
//   Back ........................ exit
class MainDelegate extends WatchUi.BehaviorDelegate {

    private var _model as PlaneModel;

    function initialize(model as PlaneModel) {
        BehaviorDelegate.initialize();
        _model = model;
    }

    function onSelect() as Boolean {
        return openDetail();
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        return openDetail();
    }

    private function openDetail() as Boolean {
        var f = _model.focusedPlane();
        if (f != null) {
            PlanesUi.pushDetail(_model, f);
        }
        return true;
    }

    function onSwipe(evt as WatchUi.SwipeEvent) as Boolean {
        if (evt.getDirection() == WatchUi.SWIPE_UP) {
            PlanesUi.pushList(_model);
            return true;
        }
        return false;
    }
}
