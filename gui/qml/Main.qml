import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import VictusSync

ApplicationWindow {
    id: win
    width: 540
    height: 720
    visible: true
    title: "Victus Sync"
    Material.theme: Material.Dark
    Material.accent: Material.Teal

    ConfigManager { id: cfg }

    readonly property var swatches: [
        "#ffffff", "#fff1d6", "#ffd9a8", "#ffb347", "#ff7a00", "#ff3b30",
        "#ff2d95", "#ff6bd6", "#bf5af2", "#7d4aff", "#3f51ff", "#0a84ff",
        "#32d4ff", "#00e0c6", "#30d158", "#7be04a", "#c8f03c", "#ffe600",
        "#ff9f9f", "#9fd8ff", "#a5f3c0", "#ffd6f0", "#d0c4ff", "#9aa0a6"
    ]
    // Frequency sliders work in log10 space so 20 Hz to 20 kHz feels even.
    readonly property real minLog: Math.log10(20)
    readonly property real maxLog: Math.log10(20000)

    function fmt(hz) {
        return hz >= 1000 ? (hz / 1000).toFixed(1) + " kHz" : Math.round(hz) + " Hz"
    }

    // A grid of colour swatches. Emits picked(colour) when one is clicked.
    component ColourGrid: GridLayout {
        id: g
        property string current: ""
        signal picked(string colour)
        columns: 6
        rowSpacing: 8
        columnSpacing: 8
        Repeater {
            model: win.swatches
            delegate: Rectangle {
                id: sw
                required property string modelData
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                radius: 8
                color: sw.modelData
                border.width: sw.modelData === g.current ? 3 : 1
                border.color: sw.modelData === g.current ? "white" : "#55ffffff"
                MouseArea {
                    anchors.fill: parent
                    onClicked: g.picked(sw.modelData)
                }
            }
        }
    }

    header: ToolBar {
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 12

            Label { text: "Light"; font.bold: true }
            Switch {
                checked: cfg.power
                onToggled: cfg.power = checked
            }
            Item { Layout.fillWidth: true }
            Label { text: "Music"; opacity: 0.7 }
            Repeater {
                model: [
                    { key: "auto", label: "Auto" },
                    { key: "on",   label: "On" },
                    { key: "off",  label: "Off" }
                ]
                delegate: Button {
                    required property var modelData
                    text: modelData.label
                    highlighted: cfg.music === modelData.key
                    onClicked: cfg.music = modelData.key
                }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        TabBar {
            id: tabs
            Layout.fillWidth: true
            TabButton { text: "Light" }
            TabButton { text: "Effects" }
            TabButton { text: "Music" }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabs.currentIndex

            // ---------- Light tab ----------
            ColumnLayout {
                spacing: 10
                Label { text: "Normal light (for work)"; font.pixelSize: 18; font.bold: true }
                RowLayout {
                    spacing: 8
                    Label { text: "Shows:"; opacity: 0.7 }
                    Button {
                        text: "Solid colour"
                        highlighted: cfg.base === "colour"
                        onClicked: cfg.base = "colour"
                    }
                    Button {
                        text: "Colour effect"
                        highlighted: cfg.base === "effect"
                        onClicked: cfg.base = "effect"
                    }
                }
                Label { text: "Colour"; opacity: 0.7 }
                ColourGrid {
                    Layout.fillWidth: true
                    current: cfg.colour
                    onPicked: (c) => { cfg.colour = c; cfg.base = "colour" }
                }
                Label { text: "Brightness: " + Math.round(bri.value) }
                Slider {
                    id: bri
                    Layout.fillWidth: true
                    from: 0; to: 255; stepSize: 1
                    value: cfg.brightness
                    onMoved: cfg.brightness = Math.round(value)
                }
                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    opacity: 0.6
                    text: "Music setting: Auto = music lighting while music plays, normal light otherwise. "
                        + "On = normal light always, even during music. Off = lights off."
                }
                Item { Layout.fillHeight: true }
            }

            // ---------- Effects tab ----------
            ColumnLayout {
                id: effectsPage
                property int sel: 0
                spacing: 10

                Label { text: "Colour effect (no music)"; font.pixelSize: 18; font.bold: true }
                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                    text: "The light holds each colour, then fades to the next, and loops. "
                        + "Select a step, then click a colour below."
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 8
                    Repeater {
                        model: cfg.effectColours
                        delegate: Rectangle {
                            id: step
                            required property int index
                            required property string modelData
                            width: 48; height: 40; radius: 8
                            color: step.modelData
                            border.width: step.index === effectsPage.sel ? 3 : 1
                            border.color: step.index === effectsPage.sel ? "white" : "#55ffffff"
                            MouseArea {
                                anchors.fill: parent
                                onClicked: effectsPage.sel = step.index
                            }
                        }
                    }
                    Button {
                        text: "+"
                        enabled: cfg.effectColours.length < 8
                        onClicked: cfg.addEffectColour()
                    }
                    Button {
                        text: "−"
                        enabled: cfg.effectColours.length > 2
                        onClicked: {
                            cfg.removeEffectColour(effectsPage.sel)
                            effectsPage.sel = Math.min(effectsPage.sel, cfg.effectColours.length - 1)
                        }
                    }
                }
                ColourGrid {
                    Layout.fillWidth: true
                    current: cfg.effectColours[effectsPage.sel] || ""
                    onPicked: (c) => cfg.setEffectColour(effectsPage.sel, c)
                }
                Label { text: "Hold each colour: " + holdSlider.value.toFixed(1) + " s" }
                Slider {
                    id: holdSlider
                    Layout.fillWidth: true
                    from: 0; to: 10; stepSize: 0.5
                    value: cfg.hold
                    onMoved: cfg.hold = value
                }
                Label { text: "Fade to next colour: " + fadeSlider.value.toFixed(1) + " s" }
                Slider {
                    id: fadeSlider
                    Layout.fillWidth: true
                    from: 0.5; to: 15; stepSize: 0.5
                    value: cfg.fade
                    onMoved: cfg.fade = value
                }
                Item { Layout.fillHeight: true }
            }

            // ---------- Music tab ----------
            ColumnLayout {
                spacing: 10
                Label { text: "Music light"; font.pixelSize: 18; font.bold: true }
                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                    text: "Each band reacts to sound inside its frequency range. Drag both ends."
                }
                Repeater {
                    model: [
                        { band: "bass",   label: "Bass (red)",    tint: "#ff6b6b" },
                        { band: "mid",    label: "Mid (green)",   tint: "#51cf66" },
                        { band: "treble", label: "Treble (blue)", tint: "#4dabf7" }
                    ]
                    delegate: ColumnLayout {
                        id: row
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 0

                        function push() {
                            cfg.setBand(modelData.band,
                                        Math.pow(10, rs.first.value),
                                        Math.pow(10, rs.second.value))
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Label { text: row.modelData.label; font.bold: true; color: row.modelData.tint }
                            Item { Layout.fillWidth: true }
                            Label {
                                text: win.fmt(Math.pow(10, rs.first.value)) + "  –  "
                                      + win.fmt(Math.pow(10, rs.second.value))
                                opacity: 0.8
                            }
                        }
                        RangeSlider {
                            id: rs
                            Layout.fillWidth: true
                            from: win.minLog
                            to: win.maxLog
                            Component.onCompleted: setValues(Math.log10(cfg.bandLow(row.modelData.band)),
                                                             Math.log10(cfg.bandHigh(row.modelData.band)))
                            first.onMoved: row.push()
                            second.onMoved: row.push()
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Label { text: "Music style" }
                    Item { Layout.fillWidth: true }
                    ComboBox {
                        model: ["bands", "pulse", "rainbow"]
                        currentIndex: model.indexOf(cfg.mode)
                        onActivated: cfg.mode = currentText
                    }
                }
                Label { text: "Beat threshold: " + sens.value.toFixed(2) + "  (lower = more beats)" }
                Slider {
                    id: sens
                    Layout.fillWidth: true
                    from: 1.1; to: 4.0
                    value: cfg.sensitivity
                    onMoved: cfg.sensitivity = value
                }
                Item { Layout.fillHeight: true }
            }
        }
    }
}
