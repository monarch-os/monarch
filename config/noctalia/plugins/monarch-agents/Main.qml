import QtQuick
import Quickshell
import Quickshell.Io

// The data side of the agents plugin. All extraction lives behind
// monarch-agent-usage-update, which writes one JSON record per agent into the
// usage directory; this only discovers those records, watches them for
// changes, and re-runs the collectors on a cadence. The bar widget and the
// panel read `agents` from here and never touch disk formats themselves.
//
// Ported from Omarchy's shell/plugins/agents (MIT). Dropped along the way:
// the cross-device snapshot aggregation (off by default upstream) and the
// per-provider enable toggles, which have no UI here yet.
Item {
  id: root
  visible: false

  property var pluginApi: null

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string usageDir: (Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")) + "/monarch/agents/usage"

  // ------------------------------------------------------------- discovery

  property var agentIds: []
  property var agents: []
  property int dataRevision: 0

  Process {
    id: listProcess
    running: false
    command: ["find", root.usageDir, "-maxdepth", "1", "-name", "*.json", "-printf", "%f\n"]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyAgentListing(text)
    }
  }

  function rescanAgents() {
    if (!listProcess.running)
      listProcess.running = true;
  }

  function applyAgentListing(output) {
    var ids = [];
    var lines = String(output || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
      var name = lines[i].trim();
      if (name.slice(-5) === ".json")
        ids.push(name.slice(0, -5));
    }
    ids.sort();
    // Same list, same objects: reassigning the model would tear down every
    // FileView just to build identical ones.
    if (JSON.stringify(ids) !== JSON.stringify(agentIds))
      agentIds = ids;
  }

  Instantiator {
    id: agentInstantiator
    model: root.agentIds

    delegate: Agent {
      required property var modelData
      agentId: modelData
      path: root.usageDir + "/" + modelData + ".json"
      onRecordChanged: root.handleRecordsUpdated()
    }

    onObjectAdded: (index, object) => root.rebuildAgents()
    onObjectRemoved: (index, object) => root.rebuildAgents()
  }

  function rebuildAgents() {
    var result = [];
    for (var i = 0; i < agentInstantiator.count; i++) {
      var agent = agentInstantiator.objectAt(i);
      if (agent)
        result.push(agent);
    }
    agents = result;
    handleRecordsUpdated();
  }

  // Not named recordsChanged: QML already generates that signal for the
  // `records` property below, and a same-named function collides with it.
  function handleRecordsUpdated() {
    dataRevision++;
    scheduleLimitsRetry();
  }

  // A collector that could not reach its limits endpoint at all — typically
  // the seconds after login before the network is up — writes retryAdvised
  // into its record. Honor it with one sooner try instead of waiting out the
  // full refresh interval; a run that reaches the endpoint clears the flag.
  // Only the advising agents rerun, so an outage at one provider does not put
  // every other collector on a 30-second treadmill.
  property var retryAgentIds: []

  Timer {
    id: limitsRetry
    interval: 30000
    repeat: false
    onTriggered: root.runUpdate("limits", root.retryAgentIds)
  }

  function scheduleLimitsRetry() {
    var advising = [];
    for (var i = 0; i < agents.length; i++) {
      var record = agents[i] ? agents[i].record : null;
      if (record && record.retryAdvised === true)
        advising.push(String(record.id));
    }
    retryAgentIds = advising;
    if (advising.length > 0)
      limitsRetry.restart();
    else
      limitsRetry.stop();
  }

  Component.onCompleted: rescanAgents()

  // --------------------------------------------------------------- refresh

  readonly property int refreshIntervalSec: {
    var configured = Number(pluginApi && pluginApi.pluginSettings ? pluginApi.pluginSettings.refreshIntervalSec : 900);
    return Math.max(60, configured > 0 ? configured : 900);
  }

  property string pendingUpdateKind: ""

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.runUpdate("limits")
  }

  // Discovery is decoupled from collection. Upstream only rescans after its
  // own collector runs, so an agent configured mid-session stays invisible for
  // up to a full refresh interval — long enough to read as broken. A `find`
  // over one directory costs nothing, so poll for new records every minute and
  // let the expensive collector keep its 15-minute cadence. This is also what
  // picks up the run monarch-default-agent fires when an agent is first set.
  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: root.rescanAgents()
  }

  Process {
    id: updateProcess
    running: false
    onExited: {
      root.rescanAgents();
      if (root.pendingUpdateKind !== "") {
        var kind = root.pendingUpdateKind;
        root.pendingUpdateKind = "";
        root.runUpdate(kind);
      }
    }

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "")
        console.warn("monarch-agents", text.trim())
    }
  }

  function updateCommand(kind, agentIds) {
    var command = ["monarch-agent-usage-update"];
    if (kind === "force")
      command.push("--force");
    if (kind === "limits")
      command.push("--limits-only");
    if (agentIds) {
      for (var i = 0; i < agentIds.length; i++)
        command.push(agentIds[i]);
    }
    return command;
  }

  function runUpdate(kind, agentIds) {
    if (updateProcess.running) {
      // Collapse queued requests to one rerun; a forced refresh outranks the
      // cheaper kinds it might have been queued behind.
      if (kind === "force" || root.pendingUpdateKind === "")
        root.pendingUpdateKind = kind;
      return;
    }
    updateProcess.command = updateCommand(kind, agentIds);
    updateProcess.running = true;
  }

  function refresh() {
    runUpdate("force");
  }

  // ------------------------------------------------------------- accessors

  // Records the panel can actually draw, newest listing order.
  readonly property var records: {
    dataRevision; // re-evaluate whenever a file changes
    var out = [];
    for (var i = 0; i < agents.length; i++) {
      var record = agents[i] ? agents[i].record : null;
      if (record && record.ready === true)
        out.push(record);
    }
    return out;
  }

  // The single worst utilization across every window of every agent — what
  // the bar pill shows. -1 when nothing has reported a limit yet.
  readonly property real worstPercent: {
    var worst = -1;
    var list = records;
    for (var i = 0; i < list.length; i++) {
      var limits = list[i].limits || [];
      for (var j = 0; j < limits.length; j++) {
        var percent = Number(limits[j].percent);
        if (percent >= 0 && percent > worst)
          worst = percent;
      }
    }
    return worst;
  }
}
