/* ==========================================================================
   DIRECTA — base común de los módulos (Dashboard y Memoria Anual)
   No llama a ninguna IA: solo lee lo que el backend ya guardó.
   ========================================================================== */
const LS = {font:"directa_font_scale", theme:"directa_theme", doc:"directa_doc_activo"};
/* Modo embebido: el módulo se muestra DENTRO del panel (index.html), que pone el menú lateral,
   el tema y el tamaño de letra. Aquí no se dibuja barra superior propia. */
const PARAMS = new URLSearchParams(location.search);
const EMBED = PARAMS.get("embed") === "1";
if(EMBED) document.documentElement.classList.add("embed");
const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));
const esc = s => String(s ?? "").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
function lsGet(k, def){ try{ const v = localStorage.getItem(k); return v === null ? def : v; }catch(e){ return def; } }
function lsSet(k, v){ try{ localStorage.setItem(k, v); }catch(e){} }
function lsGetJSON(k, def){ try{ const v = localStorage.getItem(k); return v ? JSON.parse(v) : def; }catch(e){ return def; } }
function lsSetJSON(k, v){ try{ localStorage.setItem(k, JSON.stringify(v)); }catch(e){} }

/* ---------- tema y tamaño de letra (mismas claves que index.html) ---------- */
function aplicarTema(t){ document.documentElement.setAttribute("data-theme", t); lsSet(LS.theme, t); }
function toggleTheme(){ aplicarTema(document.documentElement.getAttribute("data-theme") === "dark" ? "light" : "dark"); }
function aplicarFuente(scale){
  scale = Math.round(Math.max(0.8, Math.min(1.4, scale)) * 100) / 100;
  document.documentElement.style.setProperty("--font-scale", scale);
  lsSet(LS.font, String(scale));
  return scale;
}
function cambiarFuente(delta){
  const nuevo = aplicarFuente((parseFloat(lsGet(LS.font, "1")) || 1) + delta * 0.1);
  toast(`Tamaño de letra: ${Math.round(nuevo * 100)}%`);
}
(function initTema(){
  let t = EMBED && /^(dark|light)$/.test(PARAMS.get("theme") || "") ? PARAMS.get("theme") : lsGet(LS.theme, null);
  if(t !== "dark" && t !== "light") t = (window.matchMedia && matchMedia("(prefers-color-scheme: light)").matches) ? "light" : "dark";
  document.documentElement.setAttribute("data-theme", t);
  aplicarFuente(EMBED && parseFloat(PARAMS.get("font")) ? parseFloat(PARAMS.get("font")) : (parseFloat(lsGet(LS.font, "1")) || 1));
})();

/* El panel (ventana madre) avisa cuando cambian el tema o el tamaño de letra. */
window.addEventListener("message", ev => {
  if(!EMBED || ev.source !== window.parent) return;
  const d = ev.data;
  if(!d) return;
  if(d.directa === "setdoc"){ if(typeof window.alCambiarDoc === "function") window.alCambiarDoc(String(d.id || "")); return; }
  if(d.directa === "refresh"){ if(typeof window.alRefrescar === "function") window.alRefrescar(); return; }
  if(d.directa !== "prefs") return;
  if(d.theme === "dark" || d.theme === "light") document.documentElement.setAttribute("data-theme", d.theme);
  const f = parseFloat(d.font);
  if(f > 0.5 && f < 2) document.documentElement.style.setProperty("--font-scale", Math.round(f * 100) / 100);
});
/* Avisa al panel qué documento se está mirando (para que Chat/Resultados usen el mismo). */
function avisarDoc(id){
  if(EMBED && window.parent !== window && id && id !== "__todos__") window.parent.postMessage({directa: "doc", id: String(id)}, "*");
}
/* Documento inicial: el que manda el panel o, si no, el último guardado. */
function docInicial(){ return lsGet(LS.doc, null) || (EMBED && PARAMS.get("doc")) || null; }

function toast(msg, err){
  let el = $("#toastRoot");
  if(!el){ el = document.createElement("div"); el.id = "toastRoot"; document.body.appendChild(el); }
  el.innerHTML = `<div class="toast" role="${err ? "alert" : "status"}">${esc(msg)}</div>`;
  clearTimeout(toast._t);
  toast._t = setTimeout(() => { el.innerHTML = ""; }, err ? 4500 : 2600);
}

/* ---------- conexión con el backend ---------- */
let API = "";
async function responde(base){
  try{
    const ctl = new AbortController();
    const t = setTimeout(() => ctl.abort(), 2500);
    const r = await fetch(base + "/api/agentes", {signal: ctl.signal});
    clearTimeout(t);
    return r.ok;
  }catch(e){ return false; }
}
async function resolverAPI(){
  /* Dentro del panel la dirección del servidor ya viene confirmada: no se vuelve a probar. */
  if(EMBED && PARAMS.get("api")){ API = String(PARAMS.get("api")).replace(/\/+$/, ""); return true; }
  const candidatos = [PARAMS.get("api"), window.DIRECTA_API, /^https?:/.test(location.origin) ? location.origin : null, "http://localhost:8000"]
    .filter(Boolean).map(s => String(s).replace(/\/+$/, ""));
  for(const c of [...new Set(candidatos)]){ if(await responde(c)){ API = c; return true; } }
  API = candidatos[0] || "http://localhost:8000";
  return false;
}
async function getJSON(ruta){
  const r = await fetch(API + ruta);
  if(!r.ok) throw new Error("El servidor respondió " + r.status);
  return r.json();
}
function enlace(pagina){
  const api = PARAMS.get("api") || window.DIRECTA_API;
  return pagina + (api ? "?api=" + encodeURIComponent(api) : "");
}

/* ---------- barra superior ---------- */
const ICO_CHECK = '<svg viewBox="0 0 24 24"><path d="M5 12l5 5L20 7"/></svg>';
const ICO_SUN = '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M2 12h2M20 12h2M5 5l1.5 1.5M17.5 17.5L19 19M19 5l-1.5 1.5M6.5 17.5L5 19"/></svg>';
function barraSuperior(activa){
  /* Sin menú horizontal: la navegación está en el menú lateral del panel. */
  return `<a class="skip" href="#contenido">Saltar al contenido</a>`;
}

/* ---------- tooltip único (texto siempre con textContent) ---------- */
(function initTip(){
  const tip = document.createElement("div");
  tip.id = "tip"; tip.setAttribute("role", "tooltip");
  document.addEventListener("DOMContentLoaded", () => document.body.appendChild(tip));
  let actual = null;
  function mostrar(el, ev){
    const txt = el.getAttribute("data-tip");
    if(!txt) return;
    tip.textContent = txt;
    tip.classList.add("on");
    const r = el.getBoundingClientRect();
    const px = ev && ev.clientX != null && ev.type !== "focusin" ? ev.clientX : r.left + r.width / 2;
    const py = ev && ev.clientY != null && ev.type !== "focusin" ? ev.clientY : r.top;
    const w = tip.offsetWidth, h = tip.offsetHeight;
    let x = Math.min(Math.max(8, px - w / 2), innerWidth - w - 8);
    let y = py - h - 14; if(y < 8) y = py + 18;
    tip.style.left = x + "px"; tip.style.top = y + "px";
  }
  document.addEventListener("pointermove", ev => {
    const el = ev.target.closest && ev.target.closest("[data-tip]");
    if(el){ actual = el; mostrar(el, ev); } else if(actual){ actual = null; tip.classList.remove("on"); }
  });
  document.addEventListener("focusin", ev => { const el = ev.target.closest && ev.target.closest("[data-tip]"); if(el) mostrar(el, ev); });
  document.addEventListener("focusout", () => tip.classList.remove("on"));
  document.addEventListener("scroll", () => tip.classList.remove("on"), true);
})();

/* ---------- utilidades de dominio ---------- */
const SEV = ["crítica", "alta", "media", "baja"];
const SEV_CLS = {"crítica":"crit", "alta":"high", "media":"med", "baja":"low"};
const SEV_LABEL = {"crítica":"Crítica", "alta":"Alta", "media":"Media", "baja":"Baja"};
const BANDA_TXT = {ok:"Sin observaciones", leve:"Menor atención", revision:"Requiere revisión", serio:"Observaciones serias", critico:"Observaciones críticas",
                   sin_analizar:"Sin analizar", sin_info:"Sin información relevante", sin_datos:"Sin datos"};
const pillSev = sv => `<span class="pill ${SEV_CLS[sv]}"><i class="glyph g-${SEV_CLS[sv]}"></i>${esc(SEV_LABEL[sv].toUpperCase())}</span>`;
const nombreDoc = d => d ? (d.titulo || d.nombre_archivo || d.nombre || String(d.id)) : "";
function descargar(nombre, texto, tipo){
  const blob = texto instanceof Blob ? texto : new Blob([texto], {type: tipo || "text/plain;charset=utf-8"});
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob); a.download = nombre;
  document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
}

/* Descarga directa de un PDF que arma el servidor (sin ventana de impresión). */
async function descargarPdf(ruta, cuerpo, nombreArchivo, boton){
  const txt = boton ? boton.textContent : "";
  if(boton){ boton.disabled = true; boton.textContent = "Generando PDF…"; }
  try{
    const r = await fetch(API + ruta, {method: "POST", headers: {"Content-Type": "application/json"}, body: JSON.stringify(cuerpo || {})});
    if(!r.ok){
      let msg = "El servidor respondió " + r.status;
      try{ const j = await r.json(); if(j && j.error) msg = j.error; }catch(e){}
      throw new Error(msg);
    }
    descargar(nombreArchivo, await r.blob(), "application/pdf");
    toast("PDF descargado");
  }catch(e){
    toast("No se pudo generar el PDF: " + e.message, true);
  }finally{
    if(boton){ boton.disabled = false; boton.textContent = txt; }
  }
}

async function cargarDocumentos(){
  const r = await getJSON("/api/documentos");
  return r.documentos || [];
}
function selectorDocumentos(docs, activo, opciones){
  opciones = opciones || {};
  const ops = (opciones.todos ? `<option value="__todos__" ${activo === "__todos__" ? "selected" : ""}>Todos los documentos</option>` : "") +
    docs.map(d => `<option value="${esc(d.id)}" ${d.id === activo ? "selected" : ""}>${esc(nombreDoc(d))}${d.analisis_count ? "" : " (sin análisis)"}</option>`).join("");
  return `<label>${esc(opciones.etiqueta || "Documento")}<select class="field" id="${esc(opciones.id || "selDoc")}" aria-label="${esc(opciones.etiqueta || "Documento")}">${ops}</select></label>`;
}

/* ==========================================================================
   MEMORIA ANUAL — capítulos de la NCG 461 con evidencia en los documentos
   ========================================================================== */
const LS_MEM = "directa_memoria_v1";
const ESTADOS_CAP = [["pend", "Pendiente"], ["curso", "En redacción"], ["listo", "Listo"]];
const M = {docs: [], fuente: "__todos__", data: null, cap: null, mem: lsGetJSON(LS_MEM, {caps: {}}), error: null, cargando: false, backendOk: true};
const capMem = id => (M.mem.caps[id] = M.mem.caps[id] || {estado: "pend", notas: "", revisados: {}});
const saveMem = () => lsSetJSON(LS_MEM, M.mem);
const estCls = e => ({pend: "est-pend", curso: "est-curso", listo: "est-listo"}[e] || "est-pend");
const estTxt = e => (ESTADOS_CAP.find(x => x[0] === e) || ESTADOS_CAP[0])[1];

async function iniciar(){
  document.body.insertAdjacentHTML("afterbegin", barraSuperior("memoria"));
  $("#raiz").innerHTML = `<div class="wrap" id="contenido" tabindex="-1">
    <div class="head"><div><h1>Memoria Anual</h1><p>Arma la memoria capítulo por capítulo, siguiendo la estructura de la NCG 461 de la CMF. Para cada capítulo ves qué evidencia hay en tus documentos y qué señalaron los agentes.</p></div>
      <div class="no-print"><label class="chk-pdf" style="display:flex;gap:6px;align-items:center;font-size:calc(12px * var(--font-scale));margin-bottom:6px"><input type="checkbox" id="soloMarcados" checked> En el PDF, solo los temas que marqué</label><button class="btn ghost sm" id="btnPdf">Descargar PDF</button></div></div>
    <div class="filters" id="filtros"></div><div id="aviso"></div><div id="cuerpo"></div></div>`;
  $("#btnPdf").addEventListener("click", ev => exportarPdf(ev.currentTarget));
  M.backendOk = await resolverAPI();
  await cargarDocs();
}
async function cargarDocs(){
  try{ M.docs = await cargarDocumentos(); M.backendOk = true; M.error = null; }catch(e){ M.backendOk = false; M.error = e.message; }
  pintarFiltros();
  if(M.backendOk) await cargarCobertura(); else pintar();
}
function pintarFiltros(){
  $("#filtros").innerHTML = selectorDocumentos(M.docs, M.fuente, {etiqueta: "Buscar evidencia en", todos: true}) +
    `<button class="btn ghost sm no-print" id="btnRec" title="Vuelve a leer los datos guardados">Actualizar datos</button>`;
  $("#selDoc")?.addEventListener("change", e => { M.fuente = e.target.value; cargarCobertura(); });
  $("#btnRec")?.addEventListener("click", () => { M.forzar = true; cargarDocs(); });
}
async function cargarCobertura(){
  if(!M.docs.length){ M.data = null; pintar(); return; }
  M.cargando = true; pintar();
  try{
    const partes = [];
    if(M.fuente !== "__todos__") partes.push("docs=" + encodeURIComponent(M.fuente));
    if(M.forzar) partes.push("refrescar=1");
    M.forzar = false;
    const r = await getJSON("/api/memoria/cobertura" + (partes.length ? "?" + partes.join("&") : ""));
    if(!r.ok) throw new Error(r.error || "No se pudo leer la cobertura");
    M.data = r; M.error = null; M.backendOk = true;
    if(!M.cap || !r.capitulos.find(c => c.id === M.cap)) M.cap = r.capitulos[0].id;
  }catch(e){ M.error = e.message; M.data = null; M.backendOk = false; }
  M.cargando = false; pintar();
}

/* ---------- pintura ---------- */
const icoEv = n => n === "fuerte" ? '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12l5 5L20 7"/></svg>' : n === "debil" ? '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 12h12"/></svg>' : '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 7l10 10M17 7L7 17"/></svg>';
const evTxt = n => n === "fuerte" ? "Con evidencia" : n === "debil" ? "Evidencia débil" : "Sin evidencia";
function pintar(){
  const aviso = $("#aviso"), cuerpo = $("#cuerpo");
  if(!M.backendOk && !M.data){
    aviso.innerHTML = `<div class="aviso err" role="alert"><div><b>No se pudo conectar con el servidor.</b><br>Revisa que el backend esté encendido y vuelve a intentar. ${esc(M.error || "")}<br><button class="btn sm" style="margin-top:8px" onclick="cargarDocs()">Reintentar</button></div></div>`;
    cuerpo.innerHTML = ""; return;
  }
  aviso.innerHTML = "";
  if(!M.docs.length){ cuerpo.innerHTML = `<div class="card empty"><h3>Todavía no hay documentos</h3><p>Sube un documento (por ejemplo, la memoria del año anterior) en el Panel y aquí aparecerá la evidencia por capítulo.</p><a class="btn" href="${esc(enlace("index.html"))}">Ir al Panel</a></div>`; return; }
  if(M.cargando && !M.data){ cuerpo.innerHTML = `<div class="card empty" aria-busy="true">Buscando evidencia…</div>`; return; }
  if(!M.data){ cuerpo.innerHTML = `<div class="card empty"><h3>No se pudo leer la información</h3><p>${esc(M.error || "")}</p></div>`; return; }
  const d = M.data, r = d.resumen;
  const listos = d.capitulos.filter(c => capMem(c.id).estado === "listo").length;
  const revisados = d.capitulos.reduce((s, c) => s + c.temas.filter(t => capMem(c.id).revisados[t.id]).length, 0);
  cuerpo.className = M.cargando ? "loading" : "";
  cuerpo.innerHTML = `
    <div class="aviso" role="note"><div><b>Cómo leer esto.</b> ${esc(d.aviso)} <span class="faint">${esc(d.referencia)}</span></div></div>
    <div class="kp-row" aria-label="Resumen">
      <div class="kpi"><span class="l">Capítulos listos</span><span class="v" id="kpListos">${listos}<small>/${d.capitulos.length}</small></span></div>
      <div class="kpi"><span class="l">Temas con evidencia</span><span class="v">${r.fuertes}<small>/${r.temas_total}</small></span></div>
      <div class="kpi"><span class="l">Con evidencia débil</span><span class="v">${r.debiles}</span></div>
      <div class="kpi"><span class="l">Sin evidencia</span><span class="v">${r.sin_evidencia}</span></div>
    </div>
    <div class="layout">
      <nav class="caps" aria-label="Capítulos">${d.capitulos.map(listaCap).join("")}</nav>
      <section id="detalle" aria-live="polite">${detalleCap(d.capitulos.find(c => c.id === M.cap))}</section>
    </div>`;
}
function listaCap(c){
  const e = capMem(c.id).estado, pct = Math.round(c.con_evidencia / c.total_temas * 100);
  return `<button class="cap" data-cap="${esc(c.id)}" ${M.cap === c.id ? 'aria-current="true"' : ""}>
    <span class="nr">${c.numero}</span><b>${esc(c.titulo)}</b>
    <span class="meta"><span>${c.con_evidencia} de ${c.total_temas} temas con evidencia</span></span>
    <span class="meta"><span class="meter" style="width:80px" role="img" aria-label="${pct}% de los temas con evidencia"><i class="band-leve" style="width:${pct}%"></i></span><span class="pill ${estCls(e)}" id="est-${esc(c.id)}">${esc(estTxt(e))}</span></span></button>`;
}
function detalleCap(c){
  if(!c) return "";
  const m = capMem(c.id), unico = M.data.fuentes.length === 1;
  const temas = c.temas.map(t => {
    const pgs = t.paginas.map(p => `<span class="pg">${unico ? "" : esc(p.doc) + " · "}pág. ${esc(p.pagina ?? "?")}</span>`).join("");
    const mas = t.n_paginas > t.paginas.length ? `<span class="pg">+${t.n_paginas - t.paginas.length} más</span>` : "";
    return `<div class="tema">
      <input type="checkbox" id="rv-${esc(t.id)}" data-tema="${esc(t.id)}" ${m.revisados[t.id] ? "checked" : ""} title="Marca el tema como revisado; si dejas activada la opción del PDF, solo los marcados se incluyen" aria-label="Marcar como revisado: ${esc(t.nombre)}">
      <div><div class="tt"><label for="rv-${esc(t.id)}"><b>${esc(t.nombre)}</b></label><span class="ev ${t.nivel}">${icoEv(t.nivel)}${evTxt(t.nivel)}</span></div>
        ${t.paginas.length ? `<div class="pgs">${pgs}${mas}</div>` : ""}
        ${t.fragmento ? `<details class="snip"><summary>Ver fragmento</summary><blockquote>${esc(t.fragmento.texto)}<br><span class="faint">${esc(t.fragmento.doc)} · pág. ${esc(t.fragmento.pagina ?? "?")}</span></blockquote></details>` : ""}</div></div>`;
  }).join("");
  const ags = c.agentes.length ? c.agentes.map(a => `<div class="ag"><div class="nm">${esc(a.nombre)}
      ${!a.analizado ? '<span class="pill neutral">Sin analizar</span>' : a.score != null ? `<span class="pill neutral">Puntaje ${a.score}</span>` : `<span class="pill neutral">${a.senales.length} señal${a.senales.length === 1 ? "" : "es"}</span>`}</div>
      ${a.senales.length ? a.senales.slice(0, 6).map(s => `<div class="mini-sig">${pillSev(s.severidad)}<span><b>${esc(s.titulo)}</b>${unico ? "" : ` <span class="faint">· ${esc(s.doc)}</span>`}</span></div>`).join("") + (a.senales.length > 6 ? `<div class="faint mini-sig">… y ${a.senales.length - 6} más (ver el Dashboard)</div>` : "")
        : `<div class="faint mini-sig">${a.analizado ? "Sin señales para este tema." : "Este agente no tiene análisis guardado para los documentos elegidos."}</div>`}</div>`).join("")
    : `<p class="faint">Este capítulo no tiene un agente asociado.</p>`;
  return `
    <div class="card">
      <div class="det-head"><div><p class="eyebrow">Capítulo ${c.numero} de ${M.data.capitulos.length}</p><h2>${esc(c.titulo)}</h2></div>
        <label class="no-print" style="font-size:calc(12px * var(--font-scale));color:var(--text3);display:flex;flex-direction:column;gap:3px">Estado del capítulo
          <select class="field" id="selEst" aria-label="Estado del capítulo">${ESTADOS_CAP.map(([v, l]) => `<option value="${v}" ${m.estado === v ? "selected" : ""}>${l}</option>`).join("")}</select></label></div>
      <p class="muted" style="margin:0 0 14px">${esc(c.descripcion)}</p>
      <h3 class="eyebrow">Temas que pide la norma</h3>
      <div>${temas}</div>
    </div>
    <div class="card"><h3 class="eyebrow">Lo que dicen los agentes relacionados</h3>${ags}</div>
    <div class="card"><h3 class="eyebrow" style="display:flex;align-items:center">Notas de redacción <span class="save" id="saveMsg" role="status"></span></h3>
      <label class="sr" for="notas">Notas de redacción del capítulo</label>
      <div class="no-print chips" style="margin:0 0 8px"><button class="btn ghost sm" id="btnSug" data-act="sugerir">Sugerir borrador con IA</button><span class="faint" id="sugMsg" role="status" style="font-size:calc(12px * var(--font-scale))">Usa solo la evidencia ya encontrada: una consulta corta por capítulo.</span></div>
      <div id="sugBox"></div>
      <textarea class="field" id="notas" placeholder="Escribe aquí el borrador, pendientes o a quién pedirle cada dato. Se guarda en este navegador.">${esc(m.notas)}</textarea></div>`;
}

/* ---------- eventos ---------- */
document.addEventListener("click", ev => {
  const b = ev.target.closest("[data-cap]"); if(!b || !M.data) return;
  M.cap = b.dataset.cap;
  $$(".cap").forEach(x => x.toggleAttribute("aria-current", false));
  $$(".cap").forEach(x => { if(x.dataset.cap === M.cap) x.setAttribute("aria-current", "true"); else x.removeAttribute("aria-current"); });
  $("#detalle").innerHTML = detalleCap(M.data.capitulos.find(c => c.id === M.cap)); pintarSug(M.cap);
  if(matchMedia("(max-width:980px)").matches) $("#detalle").scrollIntoView({behavior: "smooth", block: "start"});
});
document.addEventListener("change", ev => {
  const t = ev.target; if(!M.data) return;
  if(t.id === "selEst"){
    capMem(M.cap).estado = t.value; saveMem();
    const p = $(`#est-${CSS.escape(M.cap)}`); if(p){ p.className = "pill " + estCls(t.value); p.textContent = estTxt(t.value); }
    const kp = $("#kpListos"); if(kp) kp.innerHTML = `${M.data.capitulos.filter(c => capMem(c.id).estado === "listo").length}<small>/${M.data.capitulos.length}</small>`;
  }else if(t.dataset && t.dataset.tema){
    const rv = capMem(M.cap).revisados; if(t.checked) rv[t.dataset.tema] = true; else delete rv[t.dataset.tema]; saveMem();
  }
});
let _tn = null;
document.addEventListener("input", ev => {
  if(ev.target.id !== "notas") return;
  capMem(M.cap).notas = ev.target.value;
  clearTimeout(_tn);
  _tn = setTimeout(() => { saveMem(); const s = $("#saveMsg"); if(s){ s.textContent = "Guardado"; setTimeout(() => { if(s) s.textContent = ""; }, 1500); } }, 350);
});


M.sug = {};
function pintarSug(cap){
  const box = $("#sugBox"); if(!box) return;
  const r = M.sug[cap];
  if(!r){ box.innerHTML = ""; return; }
  const pend = (r.pendientes || []).map(p => `<li><b>${esc(p.dato)}</b>${p.quien ? ` <span class="faint">— ${esc(p.quien)}</span>` : ""}</li>`).join("");
  box.innerHTML = `<div class="sugcard" role="region" aria-label="Borrador sugerido">
    <p class="eyebrow">Borrador sugerido · revísalo antes de usarlo</p>
    <div class="sugtxt">${esc(r.texto).replace(/\n\n/g, "</p><p>").replace(/^/, "<p>").replace(/$/, "</p>")}</div>
    ${pend ? `<p class="eyebrow" style="margin-top:10px">Por completar</p><ul class="sugpend">${pend}</ul>` : ""}
    <div class="chips no-print" style="margin-top:10px"><button class="btn sm" data-act="usar-sug">Usar en mis notas</button><button class="btn ghost sm" data-act="descartar-sug">Descartar</button></div></div>`;
}
document.addEventListener("click", async ev => {
  const u = ev.target.closest("[data-act=usar-sug]");
  if(u && M.data){
    const r = M.sug[M.cap]; if(!r) return;
    const mem = capMem(M.cap), previo = (mem.notas || "").trim();
    const pend = (r.pendientes || []).map(p => "- " + p.dato + (p.quien ? " (" + p.quien + ")" : "")).join("\n");
    mem.notas = (previo ? previo + "\n\n" : "") + r.texto + (pend ? "\n\nPor completar:\n" + pend : "");
    saveMem(); const ta = $("#notas"); if(ta) ta.value = mem.notas;
    delete M.sug[M.cap]; pintarSug(M.cap); const m = $("#sugMsg"); if(m) m.textContent = "Agregado a tus notas. Edítalo a tu gusto."; return;
  }
  if(ev.target.closest("[data-act=descartar-sug]")){ delete M.sug[M.cap]; pintarSug(M.cap); return; }
  const b = ev.target.closest("[data-act=sugerir]"); if(!b || !M.data) return;
  const msg = $("#sugMsg"), cap = M.cap;
  b.disabled = true; msg.textContent = "Preparando borrador…";
  try{
    const r = await fetch(API + "/api/memoria/sugerir", {method: "POST", headers: {"Content-Type": "application/json"}, body: JSON.stringify({capitulo: cap, docs: M.fuente === "__todos__" ? "" : M.fuente})}).then(x => x.json());
    if(!r.ok) throw new Error(r.error || "Sin respuesta");
    M.sug[cap] = r;
    if(M.cap === cap){ pintarSug(cap); msg.textContent = r.cache ? "Borrador listo (sin nueva consulta a la IA)." : "Borrador listo."; }
  }catch(e){ msg.textContent = "No se pudo sugerir: " + e.message; }
  finally{ b.disabled = false; }
});
/* ---------- exportar ---------- */
function exportarPdf(boton){
  if(!M.data){ toast("Todavía no hay datos para exportar", true); return; }
  descargarPdf("/api/memoria/pdf", {docs: M.fuente, caps: M.mem.caps, solo_marcados: !!($("#soloMarcados") && $("#soloMarcados").checked)}, "Esquema_Memoria_Anual.pdf", boton);
}
window.alCambiarDoc = id => {
  if(!id || M.fuente === "__todos__" || id === M.fuente) return;
  if(!M.docs.find(d => d.id === id)){ M.forzar = true; return cargarDocs(); }
  M.fuente = id; pintarFiltros(); cargarCobertura();
};
window.alRefrescar = () => { M.forzar = true; return cargarDocs(); };
document.addEventListener("DOMContentLoaded", iniciar);
