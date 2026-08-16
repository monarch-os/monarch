import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.Commons
import qs.Services.UI
import qs.Widgets

// The bar button: the mark of the agent in use, clicking through to the panel.
// No percentage — the numbers live in the tooltip and the panel.
//
// Self-hiding: a machine that has never run a coding agent has no usage
// record, so there is nothing to name and the button collapses out of the bar
// rather than sitting there pointing at nothing.
NIconButton {
  id: root

  property ShellScreen screen
  property var pluginApi: null

  // Widget properties passed from BarWidgetLoader for per-instance settings
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  readonly property var main: pluginApi ? pluginApi.mainInstance : null
  readonly property var records: main ? main.records : []
  readonly property bool hasData: records.length > 0

  // Past the threshold the mark is tinted red. Below it the mark keeps its own
  // brand colors — the bar carries no number, so this is the only at-a-glance
  // warning that an allowance is nearly spent.
  readonly property real warningThreshold: {
    var configured = Number(pluginApi && pluginApi.pluginSettings ? pluginApi.pluginSettings.warningThreshold : 0.9);
    return (configured > 0 && configured <= 1) ? configured : 0.9;
  }
  readonly property real worst: main ? main.worstPercent : -1
  readonly property bool overThreshold: worst >= warningThreshold

  // The mark of the first agent that reported. Agents that ship a white mark
  // carry an `assets/<id>-light.svg` twin for light themes.
  readonly property string agentId: hasData ? String(records[0].id || "") : ""
  readonly property url markSource: {
    if (agentId === "")
      return "";
    var variant = (Settings.data.colorSchemes.darkMode === false) ? "-light" : "";
    return Qt.resolvedUrl("assets/" + agentId + variant + ".svg");
  }

  visible: hasData
  implicitWidth: hasData ? buttonSize : 0

  // The glyph only shows while the mark is unavailable — an agent whose mark
  // this plugin does not ship still earns a button.
  icon: markImage.status === Image.Ready ? "" : "ai"
  baseSize: Style.getCapsuleHeightForScreen(screen?.name)
  applyUiScale: false
  customRadius: Style.radiusL
  colorBg: Style.capsuleColor
  colorFg: overThreshold ? Color.mError : Color.mOnSurface
  colorBgHover: Color.mHover
  colorFgHover: Color.mOnHover
  colorBorder: Style.capsuleBorderColor
  colorBorderHover: Style.capsuleBorderColor
  tooltipDirection: BarService.getTooltipDirection(screen?.name)

  IconImage {
    id: markImage
    anchors.centerIn: parent
    width: root.buttonSize * 0.6
    height: width
    source: root.markSource
    visible: status === Image.Ready
    smooth: true
    asynchronous: true

    // Noctalia's own app-icon colorize shader, the same one the Control Center
    // uses to tint a distro logo. Enabled only past the threshold, so the mark
    // renders untouched the rest of the time.
    layer.enabled: root.overThreshold
    layer.effect: ShaderEffect {
      property color targetColor: !root.hovering ? Color.mError : Color.mOnHover
      property real colorizeMode: 2.0

      fragmentShader: Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/appicon_colorize.frag.qsb")
    }
  }

  onClicked: {
    if (root.pluginApi && root.pluginApi.togglePanel)
      root.pluginApi.togglePanel(root.screen, this);
  }

  onRightClicked: {
    if (root.main)
      root.main.refresh();
  }

  tooltipText: {
    if (!root.main)
      return "";
    var lines = [];
    for (var i = 0; i < root.records.length; i++) {
      var record = root.records[i];
      var plan = String(record.tierLabel || "");
      lines.push(String(record.name || record.id) + (plan !== "" ? " · " + plan : ""));
      var limits = record.limits || [];
      for (var j = 0; j < limits.length; j++) {
        var percent = Number(limits[j].percent);
        if (percent >= 0)
          lines.push("  " + String(limits[j].title || limits[j].label || "") + ": " + Math.round(percent * 100) + "%");
      }
    }
    return lines.join("\n");
  }
}
