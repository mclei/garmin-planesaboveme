import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class PlanesApp extends Application.AppBase {

    private var _model as PlaneModel?;

    function initialize() {
        AppBase.initialize();
    }

    function getModel() as PlaneModel {
        if (_model == null) {
            _model = new PlaneModel();
        }
        return _model as PlaneModel;
    }

    function onStart(state as Dictionary?) as Void {
        getModel().start();
    }

    function onStop(state as Dictionary?) as Void {
        getModel().stop();
    }

    function onSettingsChanged() as Void {
        getModel().reloadSettings();
        WatchUi.requestUpdate();
    }

    function getInitialView() {
        var model = getModel();
        return [new MainView(model), new MainDelegate(model)];
    }
}
