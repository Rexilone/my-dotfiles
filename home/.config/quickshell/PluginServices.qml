import QtQuick
import Quickshell
import qs.services

// фоновые части включённых плагинов (service в plugin.json)
Scope {
    Instantiator {
        model: Plugins.servicePlugins

        delegate: LazyLoader {
            required property var modelData
            active: true
            source: Plugins.url(modelData, modelData.service)
            onItemChanged: if (item && "plugin" in item) item.plugin = Plugins.api(modelData)
        }
    }
}
