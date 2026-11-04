// coTs window: list, note, new note and settings. Data comes from the Rust side,
// which runs the `cots` CLI; nothing here touches files directly.
"use strict";

const { invoke } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;

const $ = (id) => document.getElementById(id);
const state = {
  data: { notes: [], folders: [], root: "" },
  loaded: false,
  folder: null,
  filter: null,
  query: "",
  openId: null,
  view: "list",
};

// MARK: - Helpers

// Dots and bars use the bright hue; topic names use a darker shade in light mode so the
// text stays readable (≥ 4.5:1) on white.
const PALETTE = {
  blue: ["#0a84ff", "#0a66d6"], purple: ["#bf5af2", "#8e3bbf"], pink: ["#ff375f", "#c4204a"], red: ["#ff453a", "#c4271c"],
  orange: ["#ff9f0a", "#b25000"], yellow: ["#ffd60a", "#8a6d00"], green: ["#30d158", "#1a7f37"], teal: ["#40c8e0", "#0a6f85"],
  indigo: ["#5e5ce6", "#4b49c9"], mint: ["#63e6be", "#00796b"], brown: ["#ac8e68", "#7a5c3a"], gray: ["#8e8e93", "#636366"],
};
PALETTE.grey = PALETTE.gray;
const NAMES = ["blue", "purple", "pink", "red", "orange", "yellow", "green", "teal", "indigo", "mint", "brown", "gray"];
const dark = window.matchMedia("(prefers-color-scheme: dark)");

function color(name, forText = false) {
  if (!name) return null;
  const n = name.toLowerCase();
  if (PALETTE[n]) return PALETTE[n][forText && !dark.matches ? 1 : 0];
  return /^#?[0-9a-f]{6}$/.test(n) ? (n.startsWith("#") ? n : `#${n}`) : null;
}

// Same hash as the macOS app, so a project has the same color on both.
function topicColorName(topic) {
  let hash = 5381;
  for (const ch of topic.toLowerCase()) hash = (((hash << 5) >>> 0) + hash + ch.codePointAt(0)) >>> 0;
  return NAMES[hash % (NAMES.length - 1)];
}
const topicColor = (topic, forText) => color(topicColorName(topic), forText);

const REVIEW_CLASS = { pending: "status-pending", approved: "status-approved", changes: "status-changes", rejected: "status-rejected" };
const reviewOf = (note) => (note.style === "plan" ? note.meta.review?.status || "pending" : null);

function relative(seconds) {
  const diff = Date.now() / 1000 - seconds;
  if (diff < 60) return t("now");
  if (diff < 3600) return t("minutesAgo", Math.floor(diff / 60));
  const date = new Date(seconds * 1000);
  const today = new Date();
  if (date.toDateString() === today.toDateString()) return date.toLocaleTimeString(LANG, { hour: "2-digit", minute: "2-digit" });
  const yesterday = new Date(today);
  yesterday.setDate(today.getDate() - 1);
  if (date.toDateString() === yesterday.toDateString()) return t("yesterday");
  return date.toLocaleDateString(LANG, { day: "numeric", month: "short", year: date.getFullYear() === today.getFullYear() ? undefined : "numeric" });
}

const fullDate = (seconds) => new Date(seconds * 1000).toLocaleString(LANG, { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" });

// Children written as `condition && node` leave false/undefined behind; drop them.
const present = (...nodes) => nodes.flat().filter((n) => n != null && n !== false);

function el(tag, props = {}, ...children) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(props)) {
    if (value == null || value === false) continue;
    if (key === "class") node.className = value;
    else if (key.startsWith("on")) node.addEventListener(key.slice(2), value);
    else node.setAttribute(key, value === true ? "" : value);
  }
  node.append(...present(...children));
  return node;
}

let toastTimer;
function toast(message, kind = "info") {
  $("toast-text").textContent = String(message);
  $("toast").className = `toast ${kind}`;
  $("toast").setAttribute("role", kind === "error" ? "alert" : "status");
  $("toast").hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => ($("toast").hidden = true), kind === "error" ? 8000 : 2500);
}
const showError = (error) => toast(error, "error");

async function act(command, args) {
  try {
    const result = await invoke(command, args);
    if (!$("toast").classList.contains("info")) $("toast").hidden = true;
    await reload();
    return result;
  } catch (error) {
    showError(error);
    throw error;
  }
}

// MARK: - Data

let loading = null;
async function reload() {
  // Coalesce: events during a load trigger one more load, never several in parallel.
  if (loading) { loading.again = true; return loading.promise; }
  loading = { again: false };
  loading.promise = (async () => {
    do {
      loading.again = false;
      try {
        state.data = await invoke("load");
        state.loaded = true;
        state.error = null;
      } catch (error) {
        state.error = String(error);
      }
      render();
    } while (loading.again);
    loading = null;
  })();
  return loading.promise;
}

function visibleNotes() {
  const q = state.query.trim().toLowerCase();
  return state.data.notes.filter((note) => {
    const status = note.meta.status || "read";
    if (state.folder && note.folder !== state.folder) return false;
    if (state.filter === "archived") { if (status !== "archived") return false; }
    else if (status === "archived") return false;
    if (state.filter === "unread" && status !== "unread") return false;
    if (state.filter === "pending" && !["pending", "changes"].includes(reviewOf(note))) return false;
    if (!q) return true;
    return [note.title, note.meta.summary, note.meta.topic, ...(note.meta.tags || []), note.body]
      .some((text) => text && text.toLowerCase().includes(q));
  });
}

// MARK: - Views

function show(view) {
  state.view = view;
  for (const name of ["list", "detail", "new", "settings"]) $(`${name}-view`).hidden = name !== view;
  $("back").hidden = view === "list";
  if (view === "list") {
    const last = state.openId && document.querySelector(`.note[data-id="${CSS.escape(state.openId)}"]`);
    state.openId = null;
    (last || $("search")).focus();
  } else {
    $("back").focus();
  }
}

function render() {
  const unread = state.data.notes.filter((n) => n.meta.status === "unread").length;
  $("unread").hidden = unread === 0;
  $("unread").textContent = unread;
  $("unread").setAttribute("aria-label", `${unread} ${t("unread").toLowerCase()}`);
  renderFolders();
  renderList();
  if (state.view === "detail") {
    const note = state.data.notes.find((n) => n.id === state.openId);
    if (note) renderDetail(note); else show("list");
  }
}

function renderFolders() {
  const chip = (name, label) => el("button", {
    class: state.folder === name ? "on" : null,
    "aria-pressed": String(state.folder === name),
    onclick: () => { state.folder = name; render(); },
  }, label);
  $("folders").replaceChildren(
    chip(null, t("all")),
    ...state.data.folders.map((f) => chip(f.name, f.unread ? `${folderTitle(f)} · ${f.unread}` : folderTitle(f))),
  );
  for (const button of $("filters").children) {
    const on = button.dataset.filter === state.filter;
    button.classList.toggle("on", on);
    button.setAttribute("aria-pressed", String(on));
  }
}

function renderList() {
  const notes = visibleNotes();
  $("notes").replaceChildren(...notes.map(row));
  const failed = state.error && !state.loaded;
  $("empty").hidden = notes.length > 0 && !failed;
  $("empty-text").textContent = failed
    ? `${t("loadFailed")} ${state.error}`
    : state.data.notes.length ? t("noMatches") : state.loaded ? t("noNotes") : "";
  $("retry").hidden = !failed;
}

function row(note) {
  const review = reviewOf(note);
  const topic = note.meta.topic;
  const bar = color(note.meta.display?.color) || (topic ? topicColor(topic) : "var(--line)");
  const unread = note.meta.status === "unread";
  return el("li", {},
    el("button", { class: `note${unread ? " unread" : ""}`, "data-id": note.id, style: `--bar:${bar}`, onclick: () => openNote(note.id) },
      el("span", { class: "title" }, note.meta.display?.pinned && el("span", { class: "pin", title: t("pinned") }, "📌 "), note.title),
      el("span", { class: "date" }, relative(note.date)),
      unread && el("span", { class: "unread-dot", role: "img", "aria-label": t("unreadDot") }),
      el("span", { class: "sub" },
        topic && el("span", { class: "topic", style: `color:${topicColor(topic, true)}` }, topic),
        review && el("span", { class: REVIEW_CLASS[review] }, t(review) || review),
        note.tasks > 0 && el("span", { class: "tag" }, note.tasks === 1 ? t("tasksOne") : t("tasksMany", note.tasks)),
        note.meta.summary && el("span", { class: "summary" }, note.meta.summary))));
}

async function openNote(id) {
  const note = state.data.notes.find((n) => n.id === id);
  if (!note) return;
  state.openId = id;
  state.shown = null;
  show("detail");
  await renderDetail(note);
  $("detail-view").scrollTop = 0;
  if (note.meta.status === "unread") act("set_status", { id, status: "read" }).catch(() => {});
}

let renderGeneration = 0;
async function renderDetail(note) {
  // A reload while the note is open repaints it only if it changed, so a comment being
  // typed and the scroll position survive agents writing elsewhere.
  const signature = JSON.stringify([note.body, note.meta]);
  if (state.shown === signature) return;
  const generation = ++renderGeneration;
  const html = await invoke("render", { markdown: note.body });
  if (generation !== renderGeneration) return; // A newer render started meanwhile.
  const typed = document.querySelector(".review textarea")?.value || "";
  state.shown = signature;

  const status = note.meta.status || "read";
  const review = reviewOf(note);
  const body = el("div", { class: "body" });
  body.innerHTML = html; // Raw HTML in notes is escaped on the Rust side.

  // Each open box carries its source line; ticking marks exactly that task.
  body.querySelectorAll("input[type=checkbox][data-line]:not([checked])").forEach((box) => {
    box.setAttribute("aria-label", box.parentElement.textContent.trim());
    box.addEventListener("click", (e) => {
      e.preventDefault();
      act("check", { id: note.id, line: Number(box.dataset.line) }).catch(() => {});
    });
  });
  body.querySelectorAll("a[href]").forEach((a) => a.addEventListener("click", (e) => {
    e.preventDefault();
    invoke("open_url", { url: a.getAttribute("href") }).catch(showError);
  }));

  const actionLabel = { copy: "actionCopy", open_url: "actionOpenURL", open_file: "actionOpenFile", reveal: "actionReveal" };
  const actions = (note.meta.actions || []).map((action) => el("button", {
    onclick: () => runAction(action),
  }, action.label || (actionLabel[action.type] ? t(actionLabel[action.type]) : action.type)));
  const pinned = note.meta.display?.pinned;

  $("detail").replaceChildren(...present(
    el("h2", { tabindex: -1 }, note.title),
    el("div", { class: "meta" },
      el("time", { datetime: new Date(note.date * 1000).toISOString() }, fullDate(note.date)),
      note.meta.topic && el("span", { class: "topic", style: `color:${topicColor(note.meta.topic, true)}` }, note.meta.topic),
      note.meta.source && el("span", {}, note.meta.source === "user" ? t("byYou") : t("by", note.meta.source)),
      review && el("span", { class: REVIEW_CLASS[review] }, t(review)),
      ...(note.meta.tags || []).map((tag) => el("span", { class: "tag" }, `#${tag}`))),
    note.meta.summary && el("p", { class: "lead" }, note.meta.summary),
    actions.length > 0 && el("div", { class: "row" }, actions),
    body,
    note.meta.ai && el("details", { class: "ai" }, el("summary", {}, t("aiContext")),
      el("pre", {}, JSON.stringify(note.meta.ai, null, 2))),
    el("div", { class: "row" },
      el("button", { onclick: () => act("set_status", { id: note.id, status: status === "unread" ? "read" : "unread" }) },
        status === "unread" ? t("markRead") : t("markUnread")),
      el("button", { onclick: () => act("set_pinned", { id: note.id, pinned: !pinned }) }, pinned ? t("unpin") : t("pin")),
      el("button", { onclick: () => act("set_status", { id: note.id, status: status === "archived" ? "read" : "archived" }) },
        status === "archived" ? t("unarchive") : t("archive")),
      el("button", { onclick: () => navigator.clipboard.writeText(note.id).then(() => toast(t("copied"))) }, t("copyId")),
      el("button", { onclick: () => invoke("reveal", { path: note.path }).catch(showError) }, t("reveal"))),
    el("div", { class: "row danger-row" },
      el("button", { class: "reject", onclick: () => trashNote(note) }, t("trash"))),
    // Like the Mac app: decide after reading, with the decision bar pinned at the bottom.
    review && reviewBox(note, review, typed),
  ));
}

async function trashNote(note) {
  if (!window.confirm(t("trashConfirm", note.title))) return;
  try {
    await invoke("trash", { path: note.path });
    show("list");
    await reload();
  } catch (error) {
    showError(error);
  }
}

function reviewBox(note, review, typed) {
  const decided = review !== "pending";
  if (decided) {
    return el("div", { class: "review" },
      note.meta.review?.comment && el("p", {}, el("strong", {}, `${t("comment")} `), note.meta.review.comment),
      el("div", { class: "row end" }, el("button", { onclick: () => act("review", { id: note.id, status: "pending" }) }, t("reopen"))));
  }
  const comment = el("textarea", { placeholder: t("commentPlaceholder"), "aria-label": t("commentPlaceholder") });
  comment.value = typed;
  const decide = (status) => {
    if (status === "changes" && !comment.value.trim()) { comment.focus(); return showError(t("commentNeeded")); }
    act("review", { id: note.id, status, comment: comment.value }).catch(() => {});
  };
  return el("div", { class: "review" }, comment,
    el("div", { class: "row" },
      el("button", { class: "reject", onclick: () => decide("rejected") }, t("reject")),
      el("button", { class: "changes", onclick: () => decide("changes") }, t("requestChanges")),
      el("span", { class: "spacer" }),
      el("button", { class: "approve", onclick: () => decide("approved") }, t("approve"))));
}

function runAction(action) {
  switch (action.type) {
    case "copy": return navigator.clipboard.writeText(action.text || action.url || action.path || "").then(() => toast(t("copied")));
    case "open_url": return invoke("open_url", { url: action.url }).catch(showError);
    case "open_file": return invoke("open_path", { path: action.path }).catch(showError);
    case "reveal": return invoke("reveal", { path: action.path }).catch(showError);
    case "run": return navigator.clipboard.writeText(action.command || "").then(() => toast(t("commandCopied")));
    default: return showError(t("unknownAction", action.type));
  }
}

// MARK: - New note

function newNote() {
  const folders = state.data.folders.length ? state.data.folders : [{ name: "code-notes", title: "Code notes" }];
  $("new-folder").replaceChildren(...folders.map((f) => el("option", { value: f.name, selected: f.name === (state.folder || "code-notes") }, folderTitle(f))));
  $("new-title").value = "";
  $("new-body").value = "";
  show("new");
  $("new-title").focus();
}

$("new-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const id = await act("add_note", { folder: $("new-folder").value, title: $("new-title").value, body: $("new-body").value }).catch(() => null);
  if (id) openNote(id);
});

// Leaving a form with text typed asks first.
function canLeave() {
  if (state.view === "new" && ($("new-title").value.trim() || $("new-body").value.trim())) return window.confirm(t("discardNote"));
  const comment = document.querySelector(".review textarea");
  if (state.view === "detail" && comment?.value.trim()) return window.confirm(t("discardComment"));
  return true;
}

function goBack() {
  if (!canLeave()) return;
  show("list");
  render();
}

// MARK: - Settings

async function openSettings() {
  if (!canLeave()) return;
  show("settings");
  renderSettings(await invoke("settings"));
}

function renderSettings(s) {
  const status = (ok, okText = t("installed"), noText = t("notInstalled")) =>
    el("span", { class: ok ? "ok" : "no" }, ok ? `✓ ${okText}` : noText);
  $("settings").replaceChildren(...present(
    el("label", { class: "setting" }, el("span", {}, t("startAtLogin")),
      el("input", { type: "checkbox", checked: s.autostart, onchange: (e) => invoke("set_autostart", { on: e.target.checked }).catch(showError) })),
    el("div", { class: "setting" },
      el("div", {}, t("notesFolder"), el("small", {}, s.root)),
      el("button", { onclick: () => invoke("open_path", { path: s.root }).catch(showError) }, t("open"))),
    el("h3", {}, t("forAgents")),
    el("div", { class: "setting" },
      el("div", {}, "CLI ", el("code", {}, "cots"), el("small", {}, t("cliHelp"))),
      status(s.cli, t("installed"), t("notFound"))),
    ...(s.integrations || []).map((i) => el("div", { class: "setting" },
      el("div", {}, i.title, i.location && el("small", {}, i.location)),
      status(i.installed))),
    ...(s.errors || []).map((e) => el("p", { class: "status-rejected" }, e)),
    el("div", { class: "row end" },
      el("button", { onclick: async () => renderSettings(await invoke("reinstall")) }, t("reinstall"))),
    el("small", { class: "no" }, `coTs ${s.version}`),
  ));
}

// MARK: - Wiring

document.documentElement.lang = LANG;
document.querySelectorAll("[data-label]").forEach((b) => { b.setAttribute("aria-label", t(b.dataset.label)); b.title = t(b.dataset.label); });
document.querySelectorAll("[data-text]").forEach((n) => (n.textContent = t(n.dataset.text)));
for (const button of $("filters").children) button.textContent = t({ unread: "unread", pending: "toReview", archived: "archived" }[button.dataset.filter]);
$("search").placeholder = t("search");
$("search").setAttribute("aria-label", t("search"));
$("retry").textContent = t("retry");

$("back").addEventListener("click", goBack);
$("new").addEventListener("click", () => { if (canLeave()) newNote(); });
$("new-cancel").addEventListener("click", goBack);
$("open-settings").addEventListener("click", openSettings);
$("close").addEventListener("click", () => invoke("hide"));
$("retry").addEventListener("click", reload);
$("toast-close").addEventListener("click", () => ($("toast").hidden = true));
$("search").addEventListener("input", (e) => { state.query = e.target.value; renderList(); });
$("filters").addEventListener("click", (e) => {
  const filter = e.target.dataset?.filter;
  if (!filter) return;
  state.filter = state.filter === filter ? null : filter;
  render();
});
// Arrow keys move between notes.
$("notes").addEventListener("keydown", (e) => {
  if (e.key !== "ArrowDown" && e.key !== "ArrowUp") return;
  const rows = [...$("notes").querySelectorAll(".note")];
  const i = rows.indexOf(document.activeElement);
  const next = rows[i + (e.key === "ArrowDown" ? 1 : -1)];
  if (next) { e.preventDefault(); next.focus(); }
});
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape") {
    if (state.view !== "list") goBack(); else invoke("hide");
  } else if (e.ctrlKey && e.key.toLowerCase() === "n") {
    e.preventDefault();
    if (canLeave()) newNote();
  } else if (e.ctrlKey && e.key.toLowerCase() === "f") {
    e.preventDefault();
    if (state.view !== "list" && !canLeave()) return;
    show("list");
    $("search").focus();
  }
});
dark.addEventListener("change", render);

invoke("set_language", { lang: LANG }).catch(() => {});
listen("notes-changed", reload);
listen("new-note", () => { if (canLeave()) newNote(); });
listen("open-settings", openSettings);
reload();
