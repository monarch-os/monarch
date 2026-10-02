const element = id => document.getElementById(id);
let groups = [], offset = 0, hasMore = false, activeGroup = "", currentLink = "";
let groupGeneration = 0, detailGeneration = 0;
const directId = location.pathname.match(/^\/admin\/reports\/([a-f0-9]{64})$/)?.[1];

function node(tag, value, className) {
  const result = document.createElement(tag);
  if (value !== undefined) result.textContent = value;
  if (className) result.className = className;
  return result;
}

async function api(path) {
  const response = await fetch("/admin/api/" + path, { cache: "no-store" });
  if (response.status === 403 || response.redirected) throw new Error("Votre session a expiré. Rechargez cette page pour vous reconnecter.");
  if (response.status === 404) throw new Error("Ce rapport est indisponible ou a expiré.");
  if (!response.ok) throw new Error("Les rapports sont temporairement indisponibles. Vous pouvez actualiser.");
  return response.json();
}

function date(value) {
  return new Date(value).toLocaleString("fr-FR", { timeZone: "UTC", dateStyle: "short", timeStyle: "short" }) + " UTC";
}

function renderGroups() {
  const query = element("search").value.trim().toLowerCase();
  const children = groups.filter(group => [group.application, group.signal, group.package_version]
    .join(" ").toLowerCase().includes(query)).map(group => {
    const button = node("button", undefined, "group");
    button.type = "button";
    button.setAttribute("aria-pressed", String(activeGroup === group.fingerprint));
    const title = node("span", undefined, "group-title");
    title.append(node("strong", group.application), node("span", group.signal, "signal"));
    button.append(title, node("small", `${group.package_version || "Version inconnue"} · ${group.occurrences} occurrence(s)`),
      node("small", "Dernier signalement : " + date(group.last_received)));
    button.addEventListener("click", () => chooseGroup(group));
    return button;
  });
  if (!children.length) children.push(node("p", query ? "Aucun résultat sur cette page." : "Aucun rapport reçu.", "search muted"));
  element("groups").replaceChildren(...children);
}

async function loadGroups(selectFirst = false) {
  const generation = ++groupGeneration;
  element("status").textContent = "";
  element("refresh").disabled = true;
  element("previous").disabled = true;
  element("next").disabled = true;
  try {
    const data = await api("groups?offset=" + offset);
    if (generation !== groupGeneration) return;
    groups = data.groups;
    hasMore = data.hasMore;
    element("report-count").textContent = data.totals.reports;
    element("group-count").textContent = data.totals.groups;
    element("retention").textContent = `Conservation des rapports : ${data.retentionDays} jours.`;
    element("page-number").textContent = "Page " + (offset / 50 + 1);
    renderGroups();
    if (selectFirst && groups.length) await chooseGroup(groups[0]);
  } catch (error) {
    if (generation === groupGeneration) element("status").textContent = error.message;
  } finally {
    if (generation === groupGeneration) {
      element("refresh").disabled = false;
      element("previous").disabled = offset === 0;
      element("next").disabled = !hasMore;
    }
  }
}

async function chooseGroup(group) {
  const generation = ++detailGeneration;
  activeGroup = group.fingerprint;
  currentLink = "";
  element("report").hidden = true;
  element("detail-title").textContent = group.application;
  element("signal").textContent = group.signal;
  element("detail-status").textContent = "Chargement des rapports…";
  renderGroups();
  try {
    const data = await api("groups/" + group.fingerprint);
    if (generation !== detailGeneration) return;
    const options = data.reports.map(report => {
      const option = node("option", `${report.crash_date} · Monarch ${report.monarch_version}`);
      option.value = report.id;
      return option;
    });
    element("occurrence").replaceChildren(...options);
    element("occurrences").hidden = options.length <= 1;
    element("occurrence-count").textContent = `(${options.length} affichée(s))`;
    if (!options.length) throw new Error("Ce groupe ne contient plus de rapport disponible.");
    await showReport(data.reports[0].id, generation);
  } catch (error) {
    if (generation === detailGeneration) element("detail-status").textContent = error.message;
  }
}

async function showReport(id, generation = ++detailGeneration) {
  element("report").hidden = true;
  currentLink = "";
  element("detail-status").textContent = "Chargement du rapport…";
  try {
    const data = await api("reports/" + id);
    if (generation !== detailGeneration) return;
    const report = data.report;
    currentLink = data.url;
    element("detail-title").textContent = report.crash.application;
    element("signal").textContent = report.crash.signal;
    element("reference").textContent = data.reference;
    element("copy-link").textContent = "Copier le lien du crash";
    const rows = [["Date du crash", report.crash.date], ["Paquet", `${report.package.name} ${report.package.version}`],
      ["Monarch lors de la préparation", report.system.monarch], ["Noyau lors de la préparation", report.system.kernel],
      ["Architecture", report.system.architecture], ["Version du paquet relevée", report.package.source === "journal" ? "Lors du crash" : "Lors de la préparation"]];
    element("metadata").replaceChildren(...rows.map(([title, value]) => {
      const row = node("div"); row.append(node("dt", title), node("dd", value || "Inconnue")); return row;
    }));
    element("backtrace").textContent = report.backtrace.length ? report.backtrace.join("\n") : "Aucune backtrace enregistrée. Une analyse locale du dump mémoire peut être nécessaire.";
    element("trace-note").textContent = report.backtraceTruncated ? "Backtrace limitée à 120 lignes." : "";
    element("detail-status").textContent = "";
    element("retention").textContent = `Conservation des rapports : ${data.retentionDays} jours.`;
    element("report").hidden = false;
    history.replaceState(null, "", new URL(currentLink).pathname);
  } catch (error) {
    if (generation === detailGeneration) element("detail-status").textContent = error.message;
  }
}

element("search").addEventListener("input", renderGroups);
element("occurrence").addEventListener("change", () => showReport(element("occurrence").value));
element("previous").addEventListener("click", () => { offset = Math.max(0, offset - 50); loadGroups(); });
element("next").addEventListener("click", () => { offset += 50; loadGroups(); });
element("refresh").addEventListener("click", () => {
  loadGroups();
  const id = location.pathname.match(/^\/admin\/reports\/([a-f0-9]{64})$/)?.[1];
  if (id) showReport(id);
});
element("copy-link").addEventListener("click", async () => {
  try {
    await navigator.clipboard.writeText(currentLink);
    element("copy-link").textContent = "Lien copié";
  } catch {
    element("detail-status").textContent = "La copie a échoué. Vous pouvez copier l’adresse de cette page.";
  }
});
loadGroups(!directId);
if (directId) showReport(directId);
