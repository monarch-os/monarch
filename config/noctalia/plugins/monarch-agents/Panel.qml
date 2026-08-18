import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

// The display side of agent usage: for each agent record, its plan, the
// percentage of each allowance already spent with the window's reset time,
// the last week of token totals, and the all-time per-model breakdown.
//
// Strictly a display. Everything here comes off the records Main.qml watches,
// so an agent gains a panel section by gaining a collector.
Item {
  id: root

  property var pluginApi: null

  readonly property var main: pluginApi ? pluginApi.mainInstance : null
  readonly property var records: main ? main.records : []

  readonly property int contentPreferredWidth: 420
  readonly property int contentPreferredHeight: Math.min(760, content.implicitHeight + Style.margin2L)

  implicitWidth: contentPreferredWidth
  implicitHeight: contentPreferredHeight

  function formatTokens(value) {
    var n = Number(value) || 0;
    if (n >= 1000000000)
      return (n / 1000000000).toFixed(1) + "B";
    if (n >= 1000000)
      return (n / 1000000).toFixed(1) + "M";
    if (n >= 1000)
      return Math.round(n / 1000) + "k";
    return String(n);
  }

  // "2026-08-17T02:59:59+00:00" -> "Mon 04:59", in local time. An unparseable
  // or absent value yields "", which the row then omits entirely.
  function formatReset(value) {
    var raw = String(value || "");
    if (raw === "")
      return "";
    var when = new Date(raw);
    if (isNaN(when.getTime()))
      return "";
    return Qt.formatDateTime(when, "ddd HH:mm");
  }

  function dayLabel(value) {
    var when = new Date(String(value || "") + "T00:00:00");
    if (isNaN(when.getTime()))
      return String(value || "");
    return Qt.formatDate(when, "ddd");
  }

  function severityColor(percent) {
    if (percent >= 0.9)
      return Color.mError;
    if (percent >= 0.75)
      return Color.mTertiary;
    return Color.mPrimary;
  }

  NScrollView {
    anchors.fill: parent
    anchors.margins: Style.marginL
    contentWidth: availableWidth

    ColumnLayout {
      id: content
      width: parent.width
      spacing: Style.marginL

      NText {
        Layout.fillWidth: true
        visible: root.records.length === 0
        text: "No agent usage recorded yet."
        color: Color.mOnSurfaceVariant
        wrapMode: Text.WordWrap
      }

      Repeater {
        model: root.records

        ColumnLayout {
          id: agentSection
          required property var modelData

          readonly property var record: modelData
          readonly property var limits: record.limits || []
          readonly property var recentDays: record.recentDays || []
          readonly property var modelUsage: record.modelUsage || ({})

          // Every bar in a chart is scaled to that chart's own busiest row, so
          // a quiet week still reads as a shape rather than four flat lines.
          readonly property real busiestDay: {
            var max = 0;
            for (var i = 0; i < recentDays.length; i++)
              max = Math.max(max, Number(recentDays[i].messageCount) || 0);
            return max;
          }

          readonly property var modelRows: {
            var rows = [];
            for (var name in modelUsage) {
              var bucket = modelUsage[name] || {};
              var total = (Number(bucket.inputTokens) || 0) + (Number(bucket.outputTokens) || 0) + (Number(bucket.cacheReadInputTokens) || 0) + (Number(bucket.cacheCreationInputTokens) || 0);
              if (total > 0)
                rows.push({
                  "name": name,
                  "total": total,
                  "input": Number(bucket.inputTokens) || 0,
                  "output": Number(bucket.outputTokens) || 0
                });
            }
            rows.sort(function (a, b) {
              return b.total - a.total;
            });
            return rows;
          }

          readonly property real heaviestModel: modelRows.length > 0 ? modelRows[0].total : 0

          Layout.fillWidth: true
          spacing: Style.marginM

          // ------------------------------------------------------------ hero

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginS

            NIcon {
              icon: "ai"
              pointSize: Style.fontSizeXXL
              color: Color.mPrimary
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 0

              NText {
                Layout.fillWidth: true
                text: String(agentSection.record.name || agentSection.record.id || "Agent")
                pointSize: Style.fontSizeL
                font.weight: Style.fontWeightSemiBold
              }

              NText {
                Layout.fillWidth: true
                text: {
                  var status = String(agentSection.record.usageStatusText || "");
                  if (status !== "")
                    return status;
                  return String(agentSection.record.tierLabel || "");
                }
                pointSize: Style.fontSizeS
                color: Color.mOnSurfaceVariant
                visible: text !== ""
              }
            }

            NText {
              text: {
                var prompts = Number(agentSection.record.todayPrompts) || 0;
                var tokens = root.formatTokens(agentSection.record.todayTotalTokens);
                return prompts + " today · " + tokens;
              }
              pointSize: Style.fontSizeS
              color: Color.mOnSurfaceVariant
            }
          }

          // ---------------------------------------------------------- limits

          NDivider {
            Layout.fillWidth: true
            visible: agentSection.limits.length > 0
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.marginS
            visible: agentSection.limits.length > 0

            Repeater {
              model: agentSection.limits

              ColumnLayout {
                required property var modelData
                readonly property real percent: Math.max(0, Number(modelData.percent) || 0)

                Layout.fillWidth: true
                spacing: Style.marginXXS

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.marginS

                  NText {
                    Layout.fillWidth: true
                    text: String(modelData.title || modelData.label || "")
                    pointSize: Style.fontSizeS
                  }

                  NText {
                    text: root.formatReset(modelData.resetsAt)
                    pointSize: Style.fontSizeXS
                    color: Color.mOnSurfaceVariant
                    visible: text !== ""
                  }

                  NText {
                    text: Math.round(percent * 100) + "%"
                    pointSize: Style.fontSizeS
                    font.weight: Style.fontWeightSemiBold
                    color: root.severityColor(percent)
                  }
                }

                NLinearGauge {
                  Layout.fillWidth: true
                  implicitHeight: Math.max(4, Style.marginS)
                  orientation: Qt.Horizontal
                  ratio: percent
                  fillColor: root.severityColor(percent)
                }
              }
            }
          }

          // --------------------------------------------------- tokens by day

          NDivider {
            Layout.fillWidth: true
            visible: agentSection.busiestDay > 0
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.marginXXS
            visible: agentSection.busiestDay > 0

            NText {
              text: "Tokens by day"
              pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
            }

            Repeater {
              model: agentSection.recentDays

              RowLayout {
                required property var modelData
                required property int index
                readonly property real tokens: Number(modelData.messageCount) || 0
                readonly property bool isToday: index === agentSection.recentDays.length - 1

                Layout.fillWidth: true
                spacing: Style.marginS

                NText {
                  Layout.preferredWidth: 34
                  text: root.dayLabel(modelData.date)
                  pointSize: Style.fontSizeXS
                  color: isToday ? Color.mOnSurface : Color.mOnSurfaceVariant
                  font.weight: isToday ? Style.fontWeightSemiBold : Style.fontWeightRegular
                }

                NLinearGauge {
                  Layout.fillWidth: true
                  implicitHeight: Math.max(4, Style.marginS)
                  orientation: Qt.Horizontal
                  ratio: agentSection.busiestDay > 0 ? tokens / agentSection.busiestDay : 0
                  fillColor: isToday ? Color.mPrimary : Color.mSecondary
                }

                NText {
                  Layout.preferredWidth: 46
                  horizontalAlignment: Text.AlignRight
                  text: root.formatTokens(tokens)
                  pointSize: Style.fontSizeXS
                  color: isToday ? Color.mOnSurface : Color.mOnSurfaceVariant
                }
              }
            }
          }

          // ------------------------------------------------- tokens by model

          NDivider {
            Layout.fillWidth: true
            visible: agentSection.modelRows.length > 0
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.marginXXS
            visible: agentSection.modelRows.length > 0

            NText {
              text: "Tokens by model"
              pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
            }

            Repeater {
              model: agentSection.modelRows

              RowLayout {
                required property var modelData

                Layout.fillWidth: true
                spacing: Style.marginS

                NText {
                  Layout.preferredWidth: 118
                  text: String(modelData.name || "")
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurfaceVariant
                  elide: Text.ElideMiddle
                }

                NLinearGauge {
                  Layout.fillWidth: true
                  implicitHeight: Math.max(4, Style.marginS)
                  orientation: Qt.Horizontal
                  ratio: agentSection.heaviestModel > 0 ? modelData.total / agentSection.heaviestModel : 0
                  fillColor: Color.mSecondary
                }

                NText {
                  Layout.preferredWidth: 46
                  horizontalAlignment: Text.AlignRight
                  text: root.formatTokens(modelData.total)
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurfaceVariant
                }
              }
            }
          }

          // ---------------------------------------------------------- footer

          RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Style.marginXS
            spacing: Style.marginS

            NText {
              Layout.fillWidth: true
              text: {
                var days = Number(agentSection.record.activeDays) || 0;
                var prompts = Number(agentSection.record.totalPrompts) || 0;
                return prompts + " prompts over " + days + " days";
              }
              pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
            }

            NText {
              text: String(agentSection.record.authHelpText || "")
              pointSize: Style.fontSizeXS
              color: Color.mError
              visible: String(agentSection.record.usageStatusText || "") !== ""
              wrapMode: Text.WordWrap
            }
          }
        }
      }

      NButton {
        Layout.fillWidth: true
        text: "Refresh"
        icon: "refresh"
        onClicked: if (root.main)
          root.main.refresh()
      }
    }
  }
}
