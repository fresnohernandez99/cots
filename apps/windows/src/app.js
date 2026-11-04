// coTs window: list, note, new note and settings. Data comes from the Rust side,
// which runs the `cots` CLI; nothing here touches files directly.
"use strict";

const { invoke } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;

const $ = (id) => document.getElementById(id);
const state = {
  data: { notes: [], folders: [], root: "" },
  folder: null,
  filter: null,
  query: "",
  openId: null,
  view: "list",
};

// MARK: - Helpers

const PALETTE = {
  blue: "#0a84ff", purple: "#bf5af2", pink: "#ff375f", red: "#ff453a", orange: "#ff9f0a", yellow: "#ffd60a",
  green: "#30d158", teal: "#40c8e0", indigo: "#5e5ce6", mint: "#63e6be", brown: "#ac8e68", gray: "#8e8e93", grey: "#8e8e93",
};
const NAMES = ["blue", "purple", "pink", "red", "orange", "yellow", "green", "teal", "indigo", "mint", "brown", "gray"];

function color(name) {
  if (!name) return null;
  const n = name.toLowerCase();
  if (PALETTE[n]) return PALETTE[n];
  return /^#?[0-9a-f]{6}$/.test(n) ? (n.startsWith("#") ? n : `#${n}`) : null;
}

// Same hash as the macOS app, so a project has the same color on both.
function topicColor(topic) {
  let hash = 5381;
  for (const ch of topic.toLowerCase()) hash = (((hash << 5) >>> 0) + hash + ch.codePointAt(0)) >>> 0;
  return PALETTE[NAMES[hash % (NAMES.length - 1)]];
}

const REVIEW = {
  pending: ["Por revisar", "status-pending"],
  approved: ["Aprobado", "status-approved"],
  changes: ["Cambios pedidos", "status-changes"],
  rejected: ["Rechazado", "status-rejected"],
};

function reviewOf(note) {
  return note.style === "plan" ? note.meta.review?.status || "pending" : null;
}

function relative(seconds) {
  const diff = Date.now() / 1000 - seconds;
  if (diff < 60) return "ahora";
  if (diff < 3600) return `hace ${Math.floor(diff / 60)} min`;
  const date = new Date(seconds * 1000);
  const today = new Date();
  if (date.toDateString() === today.toDateString()) return date.toLocaleTimeString("es", { hour: "2-digit", minute: "2-digit" });
  const yesterday = new Date(today);
  yesterday.setDate(today.getDate() - 1);
  if (date.toDateString() === yesterday.toDateString()) return "ayer";
  return date.toLocaleDateString("es", { day: "numeric", month: "short", year: date.getFullYear() === today.getFullYear() ? undefined : "numeric" });
}

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

let errorTimer;
function showError(message) {
  $("error").textContent = String(message);
  $("error").hidden = false;
  clearTimeout(errorTimer);
  errorTimer = setTimeout(() => ($("error").hidden = true), 6000);
}

async function act(command, args) {
  try {
    const result = await invoke(command, args);
    $("error").hidden = true;
    await reload();
    return result;
  } catch (error) {
    showError(error);
    throw error;
  }
}

// MARK: - Data

async function reload() {
  try {
    state.data = await invoke("load");
  } catch (error) {
    showError(error);
    return;
  }
  render();
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
  if (view === "list") state.openId = null;
}

function render() {
  const unread = state.data.notes.filter((n) => n.meta.status === "unread").length;
  $("unread").hidden = unread === 0;
  $("unread").textContent = unread;
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
    onclick: () => { state.folder = name; render(); },
  }, label);
  $("folders").replaceChildren(
    chip(null, "Todas"),
    ...state.data.folders.map((f) => chip(f.name, f.unread ? `${f.title} · ${f.unread}` : f.title)),
  );
  for (const button of $("filters").children) button.classList.toggle("on", button.dataset.filter === state.filter);
}

function renderList() {
  const notes = visibleNotes();
  $("notes").replaceChildren(...notes.map(row));
  $("empty").hidden = notes.length > 0;
  $("empty").textContent = state.data.notes.length
    ? "Nada por aquí con estos filtros."
    : "Todavía no hay notas. Pide a tu agente “guarda en cots” o crea una con ＋.";
}

function row(note) {
  const review = reviewOf(note);
  const topic = note.meta.topic;
  const dot = color(note.meta.display?.color) || (topic ? topicColor(topic) : "var(--line)");
  return el("li", {
    class: `note${note.meta.status === "unread" ? " unread" : ""}`,
    tabindex: 0,
    onclick: () => openNote(note.id),
    onkeydown: (e) => { if (e.key === "Enter") openNote(note.id); },
  },
  el("span", { class: "dot", style: `background:${dot}` }),
  el("span", { class: "title" }, note.meta.display?.pinned ? "📌 " : "", note.title),
  el("span", { class: "date" }, relative(note.date)),
  el("span", { class: "sub" },
    topic && el("span", { class: "topic", style: `color:${topicColor(topic)}` }, topic),
    review && el("span", { class: REVIEW[review]?.[1] }, REVIEW[review]?.[0] || review),
    note.tasks > 0 && el("span", { class: "tag" }, `${note.tasks} pendiente${note.tasks === 1 ? "" : "s"}`),
    note.meta.summary && el("span", { class: "summary" }, note.meta.summary)));
}

async function openNote(id) {
  const note = state.data.notes.find((n) => n.id === id);
  if (!note) return;
  state.openId = id;
  show("detail");
  await renderDetail(note);
  $("detail-view").scrollTop = 0;
  if (note.meta.status === "unread") act("set_status", { id, status: "read" }).catch(() => {});
}

async function renderDetail(note) {
  const html = await invoke("render", { markdown: note.body });
  const status = note.meta.status || "read";
  const review = reviewOf(note);
  const body = el("div", { class: "body" });
  body.innerHTML = html; // Raw HTML in notes is escaped on the Rust side.

  // Ticking a box marks that task done in the file. Open boxes map, in order, to the
  // note's open tasks; ticked ones stay as they are.
  [...body.querySelectorAll("input[type=checkbox]:not(:checked)")].forEach((box) => {
    box.disabled = false;
    box.addEventListener("click", (e) => {
      e.preventDefault();
      const task = box.parentElement.textContent.trim();
      act("check", { id: note.id, task }).catch(() => {});
    });
  });
  body.querySelectorAll("a[href]").forEach((a) => a.addEventListener("click", (e) => {
    e.preventDefault();
    invoke("open_url", { url: a.getAttribute("href") }).catch(showError);
  }));

  const actions = (note.meta.actions || []).map((action) => el("button", {
    onclick: () => runAction(action),
  }, action.label || { copy: "Copiar", open_url: "Abrir enlace", open_file: "Abrir archivo", reveal: "Mostrar en carpeta" }[action.type] || action.type));

  $("detail").replaceChildren(...present(
    el("h2", {}, note.title),
    el("div", { class: "meta" },
      el("span", {}, relative(note.date)),
      note.meta.topic && el("span", { class: "topic", style: `color:${topicColor(note.meta.topic)}` }, note.meta.topic),
      note.meta.source && el("span", {}, `por ${note.meta.source}`),
      review && el("span", { class: REVIEW[review][1] }, REVIEW[review][0]),
      ...(note.meta.tags || []).map((t) => el("span", { class: "tag" }, `#${t}`))),
    note.meta.summary && el("p", { class: "lead" }, note.meta.summary),
    review && reviewBox(note, review),
    actions.length > 0 && el("div", { class: "row" }, actions),
    body,
    note.meta.ai && el("details", { class: "ai" }, el("summary", {}, "Contexto para IAs"),
      el("pre", {}, JSON.stringify(note.meta.ai, null, 2))),
    el("div", { class: "row" },
      el("button", { onclick: () => act("set_status", { id: note.id, status: status === "unread" ? "read" : "unread" }) },
        status === "unread" ? "Marcar como leída" : "Marcar como no leída"),
      el("button", { onclick: () => act("set_pinned", { id: note.id, pinned: !note.meta.display?.pinned }) },
        note.meta.display?.pinned ? "Desfijar" : "Fijar"),
      el("button", { onclick: () => act("set_status", { id: note.id, status: status === "archived" ? "read" : "archived" }) },
        status === "archived" ? "Desarchivar" : "Archivar"),
      el("button", { onclick: () => navigator.clipboard.writeText(note.id) }, "Copiar id para IAs"),
      el("button", { onclick: () => invoke("reveal", { path: note.path }).catch(showError) }, "Mostrar en carpeta"),
      el("button", { class: "reject", onclick: async () => { await act("trash", { id: note.id }); show("list"); } }, "Papelera")),
  ));
}

function reviewBox(note, review) {
  const comment = el("textarea", { placeholder: "Comentario para el agente (opcional; obligatorio para pedir cambios)" });
  const decide = (status) => {
    if (status === "changes" && !comment.value.trim()) { comment.focus(); return showError("Escribe qué cambiar."); }
    act("review", { id: note.id, status, comment: comment.value }).catch(() => {});
  };
  const decided = review !== "pending";
  return el("div", { class: "review" },
    decided && note.meta.review?.comment && el("div", {}, el("strong", {}, "Comentario: "), note.meta.review.comment),
    decided
      ? el("div", { class: "row" }, el("button", { onclick: () => act("review", { id: note.id, status: "pending" }) }, "Volver a pendiente"))
      : [comment, el("div", { class: "row" },
          el("button", { class: "approve", onclick: () => decide("approved") }, "Aprobar"),
          el("button", { class: "changes", onclick: () => decide("changes") }, "Pedir cambios"),
          el("button", { class: "reject", onclick: () => decide("rejected") }, "Rechazar"))]);
}

function runAction(action) {
  switch (action.type) {
    case "copy": return navigator.clipboard.writeText(action.text || action.url || action.path || "");
    case "open_url": return invoke("open_url", { url: action.url }).catch(showError);
    case "open_file": return invoke("open_path", { path: action.path }).catch(showError);
    case "reveal": return invoke("reveal", { path: action.path }).catch(showError);
    case "run": return navigator.clipboard.writeText(action.command || "").then(() => showError("Comando copiado: pégalo en tu terminal."));
    default: return showError(`Acción desconocida: ${action.type}`);
  }
}

// MARK: - New note

function newNote() {
  const folders = state.data.folders.length ? state.data.folders : [{ name: "code-notes", title: "code-notes" }];
  $("new-folder").replaceChildren(...folders.map((f) => el("option", { value: f.name, selected: f.name === (state.folder || "code-notes") }, f.title)));
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

// MARK: - Settings

async function openSettings() {
  show("settings");
  renderSettings(await invoke("settings"));
}

function renderSettings(s) {
  const autostart = el("input", { type: "checkbox", checked: s.autostart, onchange: (e) => invoke("set_autostart", { on: e.target.checked }).catch(showError) });
  $("settings").replaceChildren(...present(
    el("div", { class: "setting" }, el("div", {}, "Abrir al iniciar sesión"), autostart),
    el("div", { class: "setting" },
      el("div", {}, "Carpeta de notas", el("small", {}, s.root)),
      el("button", { onclick: () => invoke("open_path", { path: s.root }).catch(showError) }, "Abrir")),
    el("h3", {}, "Para tus agentes"),
    ...(s.integrations || []).map((i) => el("div", { class: "setting" },
      el("div", {}, i.title, i.location && el("small", {}, i.location)),
      el("span", { class: i.installed ? "ok" : "no" }, i.installed ? "✓ Instalado" : "No instalado"))),
    el("div", { class: "setting" },
      el("div", {}, "CLI ", el("code", {}, "cots"), el("small", {}, "En el PATH de tu usuario; abre una terminal nueva para usarlo.")),
      el("span", { class: "ok" }, "✓")),
    ...(s.errors || []).map((e) => el("p", { class: "status-rejected" }, e)),
    el("div", { class: "row end" },
      el("button", { onclick: async () => renderSettings(await invoke("reinstall")) }, "Reinstalar integraciones")),
    el("small", { class: "no" }, `coTs ${s.version}`),
  ));
}

// MARK: - Wiring

$("back").addEventListener("click", () => { show("list"); render(); });
$("new").addEventListener("click", newNote);
$("new-cancel").addEventListener("click", () => show("list"));
$("open-settings").addEventListener("click", openSettings);
$("close").addEventListener("click", () => invoke("hide"));
$("search").addEventListener("input", (e) => { state.query = e.target.value; renderList(); });
$("filters").addEventListener("click", (e) => {
  const filter = e.target.dataset?.filter;
  if (!filter) return;
  state.filter = state.filter === filter ? null : filter;
  render();
});
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape") {
    if (state.view !== "list") { show("list"); render(); } else invoke("hide");
  } else if (e.ctrlKey && e.key.toLowerCase() === "n") {
    e.preventDefault();
    newNote();
  } else if (e.ctrlKey && e.key.toLowerCase() === "f") {
    e.preventDefault();
    show("list");
    $("search").focus();
  }
});

listen("notes-changed", reload);
listen("new-note", newNote);
listen("open-settings", openSettings);
reload();
