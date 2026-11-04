// Strings for the window, in the system language (Spanish or English), with the same
// wording as the macOS app. `t("key", value)` fills `{0}`.
"use strict";

const STRINGS = {
  es: {
    back: "Volver", newNote: "Nueva nota", settings: "Ajustes", hide: "Ocultar", search: "Buscar",
    all: "Todas", unread: "Sin leer", toReview: "Por revisar", archived: "Archivadas",
    noMatches: "Nada por aquí con estos filtros.",
    noNotes: "Todavía no hay notas. Pide a tu agente «guarda en cots» o crea una con ＋.",
    loadFailed: "No se pudieron leer tus notas.", retry: "Reintentar",
    now: "ahora", minutesAgo: "hace {0} min", yesterday: "ayer",
    pending: "Por revisar", approved: "Aprobado", changes: "Cambios pedidos", rejected: "Rechazado",
    tasksOne: "1 pendiente", tasksMany: "{0} pendientes", pinned: "Fijada", unreadDot: "Sin leer",
    byYou: "por ti", by: "por {0}",
    markRead: "Marcar como leída", markUnread: "Marcar como no leída", pin: "Fijar", unpin: "Desfijar",
    archive: "Archivar", unarchive: "Desarchivar", copyId: "Copiar id para IAs", copied: "Copiado",
    reveal: "Mostrar en el Explorador", trash: "Mover a la papelera",
    trashConfirm: "¿Mover «{0}» a la Papelera de reciclaje?", aiContext: "Contexto IA",
    commentPlaceholder: "Comentario para la IA (obligatorio para pedir cambios)", commentNeeded: "Escribe qué cambiar.",
    approve: "Aprobar", requestChanges: "Pedir cambios", reject: "Rechazar", reopen: "Reabrir", comment: "Comentario:",
    actionCopy: "Copiar", actionOpenURL: "Abrir enlace", actionOpenFile: "Abrir archivo", actionReveal: "Mostrar en el Explorador",
    commandCopied: "Comando copiado: pégalo en tu terminal.", unknownAction: "Acción desconocida: {0}",
    folder: "Carpeta", title: "Título", body: "Contenido (Markdown)", cancel: "Cancelar", create: "Crear",
    discardNote: "¿Descartar la nota sin guardarla?", discardComment: "¿Descartar el comentario?",
    startAtLogin: "Abrir al iniciar sesión", notesFolder: "Carpeta de notas", open: "Abrir",
    forAgents: "Integración con IAs", installed: "Instalado", notInstalled: "No instalado", notFound: "No encontrado",
    cliHelp: "En el PATH de tu usuario; abre una terminal nueva para usarlo.", reinstall: "Reinstalar integraciones",
    close: "Cerrar",
  },
  en: {
    back: "Back", newNote: "New note", settings: "Settings", hide: "Hide", search: "Search",
    all: "All", unread: "Unread", toReview: "To review", archived: "Archived",
    noMatches: "Nothing here with these filters.",
    noNotes: "No notes yet. Ask your agent to “save in cots” or create one with ＋.",
    loadFailed: "Couldn't read your notes.", retry: "Try again",
    now: "now", minutesAgo: "{0} min ago", yesterday: "yesterday",
    pending: "To review", approved: "Approved", changes: "Changes requested", rejected: "Rejected",
    tasksOne: "1 to do", tasksMany: "{0} to do", pinned: "Pinned", unreadDot: "Unread",
    byYou: "by you", by: "by {0}",
    markRead: "Mark as read", markUnread: "Mark as unread", pin: "Pin", unpin: "Unpin",
    archive: "Archive", unarchive: "Unarchive", copyId: "Copy id for AIs", copied: "Copied",
    reveal: "Show in Explorer", trash: "Move to Recycle Bin",
    trashConfirm: "Move “{0}” to the Recycle Bin?", aiContext: "AI context",
    commentPlaceholder: "Comment for the AI (required to request changes)", commentNeeded: "Say what to change.",
    approve: "Approve", requestChanges: "Request changes", reject: "Reject", reopen: "Reopen", comment: "Comment:",
    actionCopy: "Copy", actionOpenURL: "Open link", actionOpenFile: "Open file", actionReveal: "Show in Explorer",
    commandCopied: "Command copied: paste it in your terminal.", unknownAction: "Unknown action: {0}",
    folder: "Folder", title: "Title", body: "Content (Markdown)", cancel: "Cancel", create: "Create",
    discardNote: "Discard this note without saving it?", discardComment: "Discard the comment?",
    startAtLogin: "Open at login", notesFolder: "Notes folder", open: "Open",
    forAgents: "AI integration", installed: "Installed", notInstalled: "Not installed", notFound: "Not found",
    cliHelp: "On your user's PATH; open a new terminal to use it.", reinstall: "Reinstall integrations",
    close: "Close",
  },
};

const LANG = (navigator.language || "es").toLowerCase().startsWith("es") ? "es" : "en";
const TEXT = STRINGS[LANG];

function t(key, value) {
  const text = TEXT[key] ?? STRINGS.es[key] ?? key;
  return value === undefined ? text : text.replace("{0}", value);
}

// Built-in folders get a translated title unless the user renamed them.
const FOLDER_TITLES = { es: { "code-notes": "Notas de código", plans: "Planes" }, en: { "code-notes": "Code notes", plans: "Plans" } };
function folderTitle(folder) {
  const builtIn = { "code-notes": "Code notes", plans: "Plans" }[folder.name];
  return builtIn && folder.title === builtIn ? FOLDER_TITLES[LANG][folder.name] : folder.title;
}
