import QtQuick
import qs.services

// погода в баре: иконка и температура; клик — вкладка погоды
BarText {
    signal openWeather

    visible: Weather.configured && !!Weather.current
    text: Weather.current ? `${Weather.info(Weather.current.code, Weather.current.isDay).icon} ${Weather.current.temp}°` : ""
    onClicked: openWeather()
}
