// PopoutService.qml - routes settings requests into a deterministic test settings modal.
pragma Singleton
import QtQuick

QtObject {
    property var settingsModal: null

    function openSettingsWithTab(tabName, returnOrigin, reopen) {
        if (settingsModal)
            settingsModal.showWithTabName(tabName);
    }
}
