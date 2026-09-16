import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

SettingRow {
    id: tune

    property real value: 0
    property real from: 0
    property real to: 1
    property real stepSize: 0.01
    property string suffix
    property int decimals: 2
    property bool pendingCommit: false
    signal committed(real value)

    function applyPending() {
        if (!pendingCommit)
            return
        pendingCommit = false
        committed(slider.value)
    }

    spacing: 0

    RowLayout {
        Layout.fillWidth: true
        PlasmaComponents.Label {
            Layout.fillWidth: true
            text: tune.markedLabel
            textFormat: Text.StyledText
            elide: Text.ElideRight
            opacity: 0.85
        }
        PlasmaComponents.Label {
            text: Number(slider.value).toFixed(tune.decimals) + tune.suffix
            font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
        }
    }
    QQC2.Slider {
        id: slider
        Layout.fillWidth: true
        wheelEnabled: false
        from: tune.from
        to: tune.to
        stepSize: tune.stepSize
        value: tune.value
        onMoved: {
            tune.pendingCommit = true
            commitTimer.restart()
        }
        onPressedChanged: if (!pressed) {
            commitTimer.stop()
            tune.applyPending()
        }
        QQC2.ToolTip.visible: hovered && tune.help !== ""
        QQC2.ToolTip.delay: 450
        QQC2.ToolTip.text: tune.tip
        MouseArea {
            anchors.fill: parent
            z: 1000
            acceptedButtons: Qt.NoButton
            onWheel: function(wheel) { root.scrollMenu(wheel) }
        }
    }
    Timer {
        id: commitTimer
        interval: 100
        onTriggered: tune.applyPending()
    }
}
