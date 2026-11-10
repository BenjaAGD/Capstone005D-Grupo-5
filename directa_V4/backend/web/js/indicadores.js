const LS = {font:"directa_font_scale", theme:"directa_theme", doc:"directa_doc_activo"};
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

function avisarDoc(id){
  if(EMBED && window.parent !== window && id && id !== "__todos__") window.parent.postMessage({directa: "doc", id: String(id)}, "*");
}

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
  return `<a class="skip" href="#contenido">Saltar al contenido</a>`;
}

/* ---------- tooltip ---------- */
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

const LS_IND = "directa_indicadores_propios_v1";
const LS_AJ = "directa_indicadores_ajustes_v1";
const ESTADOS_SOL = [["pendiente", "Pendiente"], ["curso", "En curso"], ["hecho", "Hecha"]];
const SEM_TXT = {verde: "En meta", amarillo: "Atención", rojo: "Fuera de meta", sin_dato: "Sin dato"};
const SEM_CLS = {verde: "low", amarillo: "med", rojo: "crit", sin_dato: "neutral"};
const arr = v => Array.isArray(v) ? v : [];
const obj = v => (v && typeof v === "object" && !Array.isArray(v)) ? v : {};
const I = {
  docs: [], docId: null, sug: null, cargando: false, error: null, errorSug: null, backendOk: true,
  propios: arr(lsGetJSON(LS_IND, [])), ajustes: obj(lsGetJSON(LS_AJ, {})), form: null,
};
const saveProp = () => lsSetJSON(LS_IND, I.propios);
const saveAj = () => lsSetJSON(LS_AJ, I.ajustes);
const claveAj = id => `${I.docId}|${id}`;
const ajusteDe = id => obj(I.ajustes[claveAj(id)]);

function semaforo(valor, meta, limite, dir){
  const v = parseFloat(valor), m = parseFloat(meta);
  let l = parseFloat(limite);
  if(Number.isNaN(v) || Number.isNaN(m)) return "sin_dato";
  if(Number.isNaN(l)) l = m;
  if(dir === "menor") return v <= m ? "verde" : (v <= l ? "amarillo" : "rojo");
  return v >= m ? "verde" : (v >= l ? "amarillo" : "rojo");
}
const num = x => { const n = parseFloat(x); return Number.isNaN(n) ? null : n; };
const fmtNum = x => { const n = num(x); return n === null ? "—" : (Number.isInteger(n) ? String(n) : String(Math.round(n * 100) / 100)); };
const pillSem = e => `<span class="pill ${SEM_CLS[e]}">${e === "sin_dato" ? "" : `<i class="glyph g-${SEM_CLS[e]}"></i>`}${esc(SEM_TXT[e].toUpperCase())}</span>`;
const hoyIso = () => new Date().toISOString().slice(0, 10);

/* ---------- carga ---------- */
async function iniciar(){
  document.body.insertAdjacentHTML("afterbegin", barraSuperior("indicadores"));
  $("#raiz").innerHTML = `<div class="wrap" id="contenido" tabindex="-1">
    <div class="head"><div><h1>Indicadores</h1><p>Los números clave para el Gerente General: cómo vamos (KPI), qué nos puede salir mal (KRI) y qué hacemos al respecto (soluciones).</p></div>
      <div class="no-print chips">
        <button class="btn" data-act="nuevo">+ Agregar indicador</button>
        <button class="btn ghost sm" data-act="pdf" id="btnPdf">Descargar PDF</button>
        <button class="btn ghost sm" data-act="export">Guardar copia</button>
        <button class="btn ghost sm" data-act="import">Cargar copia</button>
        <input type="file" id="fileImp" accept="application/json,.json" class="sr" aria-label="Cargar copia de indicadores">
      </div></div>
    <div class="filters" id="filtros"></div><div id="aviso"></div><div id="cuerpo"></div></div>`;
  $("#fileImp").addEventListener("change", importarCopia);
  I.backendOk = await resolverAPI();
  await cargarDocs();
}
async function cargarDocs(){
  try{
    I.docs = await cargarDocumentos();
    I.backendOk = true; I.error = null;
    const guardado = docInicial();
    const conAnalisis = I.docs.filter(d => d.analisis_count > 0);
    I.docId = (I.docs.find(d => d.id === guardado) || conAnalisis[0] || I.docs[0] || {}).id || null;
  }catch(e){ I.backendOk = false; I.error = e.message; }
  pintarFiltros();
  if(I.docId) await cargarSugeridos(); else pintar();
}
async function cargarSugeridos(){
  I.cargando = true; I.errorSug = null; pintar();
  try{
    const r = await getJSON("/api/indicadores/sugeridos/" + encodeURIComponent(I.docId) + (I.forzar ? "?refrescar=1" : "")); I.forzar = false;
    if(!r.ok) throw new Error(r.error || "No se pudieron calcular los indicadores");
    I.sug = r;
  }catch(e){ I.sug = null; I.errorSug = e.message; }
  I.cargando = false; pintar();
}
function pintarFiltros(){
  $("#filtros").innerHTML = (EMBED ? "" : selectorDocumentos(I.docs, I.docId, {etiqueta: "Documento para los indicadores sugeridos"})) +
    `<button class="btn ghost sm no-print" id="btnRec" title="Vuelve a leer los datos guardados">Actualizar datos</button>`;
  $("#selDoc")?.addEventListener("change", e => { I.docId = e.target.value; lsSet(LS.doc, I.docId); avisarDoc(I.docId); cargarSugeridos(); });
  $("#btnRec")?.addEventListener("click", () => I.docs.length ? cargarSugeridos() : cargarDocs());
}

/* ---------- datos combinados ---------- */
function todosLosIndicadores(){
  const auto = I.sug ? arr(I.sug.indicadores).map(i => ({...i, origen: "auto"})) : [];
  const propios = I.propios.map(p => ({...p, origen: "propio", soluciones: [], como: "",
    estado: semaforo(p.valor, p.meta, p.limite, p.direccion)}));
  return [...auto, ...propios];
}

/* ---------- piezas ---------- */
function pintar(){
  const aviso = $("#aviso"), cuerpo = $("#cuerpo");
  if(!I.backendOk && !I.sug){
    aviso.innerHTML = `<div class="aviso warn" role="alert"><div><b>No se pudo conectar con el servidor.</b> Los indicadores sugeridos no están disponibles, pero puedes ver y editar los tuyos. ${esc(I.error || "")}
      <br><button class="btn sm" style="margin-top:8px" onclick="cargarDocs()">Reintentar</button></div></div>`;
  }else if(I.errorSug){
    aviso.innerHTML = `<div class="aviso warn" role="status"><div><b>No se pudieron calcular los indicadores sugeridos para este documento.</b> ${esc(I.errorSug)}</div></div>`;
  }else if(I.backendOk && !I.docs.length){
    aviso.innerHTML = `<div class="aviso" role="status"><div>Todavía no hay documentos analizados, así que no hay indicadores sugeridos. Puedes agregar los tuyos con el botón de arriba.</div></div>`;
  }else aviso.innerHTML = "";
  const todos = todosLosIndicadores();
  cuerpo.className = I.cargando ? "loading" : "";
  cuerpo.innerHTML = secResumen(todos) + (I.form ? formIndicador(I.form) : "") + secTipo("KPI", todos) + secTipo("KRI", todos);
}
function secResumen(todos){
  const c = {rojo: 0, amarillo: 0, verde: 0, sin_dato: 0};
  todos.forEach(i => { c[i.estado] = (c[i.estado] || 0) + 1; });
  const k = (e, cls, txt) => `<div class="kpi"><div class="l"><i class="glyph g-${cls}"></i>${esc(txt)}</div><div class="v">${c[e]}</div></div>`;
  return `<section class="sec" aria-label="Resumen" style="margin-top:0"><div class="grid kpis">${k("rojo", "crit", "Fuera de meta")}${k("amarillo", "med", "En atención")}${k("verde", "low", "En meta")}
    <div class="kpi"><div class="l">Indicadores en total</div><div class="v">${todos.length}</div></div></div></section>`;
}
function secTipo(tipo, todos){
  const lista = todos.filter(i => i.tipo === tipo).sort((a, b) => ["rojo", "amarillo", "sin_dato", "verde"].indexOf(a.estado) - ["rojo", "amarillo", "sin_dato", "verde"].indexOf(b.estado));
  const t = tipo === "KPI" ? ["KPI — ¿Cómo vamos?", "Indicadores de desempeño: miden si estamos cumpliendo las metas."]
                           : ["KRI — ¿Qué nos puede salir mal?", "Indicadores de riesgo: avisan cuando nos acercamos a un problema."];
  return `<section class="sec" aria-labelledby="h-${tipo}"><h2 id="h-${tipo}">${t[0]}</h2><p class="sub">${t[1]}</p>` +
    (lista.length ? `<div class="ind-grid">${lista.map(tarjeta).join("")}</div>`
                  : `<div class="card empty" style="padding:16px"><p style="margin:0">Aún no hay ${tipo} para mostrar. Agrega uno con "+ Agregar indicador".</p></div>`) + `</section>`;
}
function textoMeta(i){
  const u = i.unidad || "";
  const m = `${i.direccion === "menor" ? "≤" : "≥"} ${fmtNum(i.meta)}${u}`;
  const lim = num(i.limite) === null ? "" : ` · Rojo si ${i.direccion === "menor" ? ">" : "<"} ${fmtNum(i.limite)}${u}`;
  return `Meta: ${m}${lim}`;
}
function barraInd(i){
  const v = parseFloat(i.valor), m = parseFloat(i.meta), l = (i.limite === null || i.limite === "" || i.limite === undefined) ? NaN : parseFloat(i.limite);
  if(isNaN(v) || isNaN(m)) return "";
  const menor = (i.direccion || (i.tipo === "KRI" ? "menor" : "mayor")) === "menor";
  const max = Math.max(v, m, isNaN(l) ? 0 : l, 1) * 1.25, p = x => Math.max(0, Math.min(100, x / max * 100));
  const lim = isNaN(l) ? m : l;
  let zonas;
  if(menor) zonas = [[0, p(m), "var(--low)"], [p(m), p(lim), "var(--med)"], [p(lim), 100, "var(--high)"]];
  else zonas = [[0, p(lim), "var(--high)"], [p(lim), p(m), "var(--med)"], [p(m), 100, "var(--low)"]];
  const z = zonas.filter(a => a[1] > a[0]).map(a => `<i style="left:${a[0]}%;width:${a[1] - a[0]}%;background:${a[2]}"></i>`).join("");
  return `<div class="bul" role="img" aria-label="Valor ${esc(fmtNum(v))}, meta ${esc(fmtNum(m))}"><div class="bz">${z}</div><b style="left:${p(v)}%"></b><u style="left:${p(m)}%"></u></div>
    <div class="bul-l"><span>Valor actual</span><span>Meta</span></div>`;
}
function tarjeta(i){
  const auto = i.origen === "auto";
  const src = auto ? "aj" : "pro";
  const a = auto ? ajusteDe(i.id) : i;
  const estSol = auto ? (a.estado || "pendiente") : (i.estado_solucion || "pendiente");
  const sugeridas = auto ? (i.soluciones.length
      ? `<ul class="sol-list">${i.soluciones.map(s => `<li>${esc(s)}</li>`).join("")}</ul>`
      : (i.estado === "verde" ? `<p class="faint" style="margin:0">En meta: no requiere acción por ahora.</p>` : `<p class="faint" style="margin:0">Sin solución sugerida: escribe la tuya abajo.</p>`)) : "";
  const propia = auto ? `<button class="btn ghost sm no-print" type="button" data-act="ia-sol" data-id="${esc(i.id)}" style="margin-bottom:6px">Sugerir solución con IA</button><label class="fld">Mi solución (opcional)<textarea class="field sm-ta" data-src="aj" data-id="${esc(i.id)}" data-f="solucion" rows="2">${esc(a.solucion || "")}</textarea></label>`
                      : (i.solucion ? `<p class="sol-txt">${esc(i.solucion)}</p>` : `<p class="faint" style="margin:0">Sin solución definida. Pulsa "Editar" para escribirla.</p>`);
  const respCampo = auto ? (a.responsable || "") : (i.responsable || "");
  const fechaCampo = auto ? (a.fecha || "") : (i.fecha || "");
  const botones = auto ? "" : `<div class="no-print chips" style="margin-top:10px"><button class="btn ghost sm" data-act="editar" data-id="${esc(i.id)}">Editar</button><button class="btn ghost sm" data-act="eliminar" data-id="${esc(i.id)}">Eliminar</button></div>`;
  const vencida = fechaCampo && estSol !== "hecho" && fechaCampo < hoyIso() && i.estado !== "verde";
  return `<article class="card ind e-${i.estado}" data-card="${esc(i.id)}">
    <div class="ind-top"><span class="tag">${esc(i.tipo)} · ${auto ? "sugerido" : "propio"}</span>${pillSem(i.estado)}</div>
    <h3>${esc(i.nombre)}</h3>
    <div class="ind-val">${esc(fmtNum(i.valor))}<small>${esc(i.unidad || "")}</small></div>
    <p class="faint" style="margin:2px 0 0">${esc(textoMeta(i))}</p>
    ${barraInd(i)}
    ${i.como ? `<p class="muted" style="margin:6px 0 0;font-size:calc(12px * var(--font-scale))">${esc(i.como)}</p>` : ""}
    <div class="ind-sol"><p class="eyebrow">Solución</p>${sugeridas}${propia}
      <div class="ind-f">
        <label class="fld">Responsable<input class="field sm" data-src="${src}" data-id="${esc(i.id)}" data-f="responsable" value="${esc(respCampo)}" placeholder="Nombre o área"></label>
        <label class="fld">Fecha límite<input class="field sm" type="date" data-src="${src}" data-id="${esc(i.id)}" data-f="fecha" value="${esc(fechaCampo)}"></label>
        <label class="fld">Estado<select class="field sm" data-src="${src}" data-id="${esc(i.id)}" data-f="estado">${ESTADOS_SOL.map(([v, l]) => `<option value="${v}" ${estSol === v ? "selected" : ""}>${l}</option>`).join("")}</select></label>
      </div>
      ${vencida ? `<p class="venc">⚠ La fecha límite ya pasó y la solución no está hecha.</p>` : ""}
    </div>${botones}</article>`;
}

/* ---------- formulario para agregar / editar ---------- */
function formIndicador(f){
  const v = k => esc(f[k] ?? "");
  const esKri = (f.tipo || "KPI") === "KRI";
  return `<form class="card" id="frmInd" novalidate aria-label="${f.id ? "Editar" : "Nuevo"} indicador" style="margin-bottom:14px">
    <h2 style="margin:0 0 4px;font-size:calc(15px * var(--font-scale))">${f.id ? "Editar indicador" : "Nuevo indicador"}</h2>
    <p class="muted" style="margin:0 0 10px;font-size:calc(12px * var(--font-scale))">Completa lo básico. El semáforo se calcula solo con el valor, la meta y el límite.</p>
    <div class="frm-grid">
      <label class="fld">Tipo<select class="field sm" id="f-tipo"><option value="KPI" ${esKri ? "" : "selected"}>KPI — desempeño (más alto es mejor)</option><option value="KRI" ${esKri ? "selected" : ""}>KRI — riesgo (más bajo es mejor)</option></select></label>
      <label class="fld" style="grid-column:span 2">Nombre del indicador *<input class="field sm" id="f-nombre" value="${v("nombre")}" placeholder="Ej: Ventas versus presupuesto" maxlength="120" required></label>
      <label class="fld">Unidad<input class="field sm" id="f-unidad" value="${v("unidad")}" placeholder="% , $, días…" maxlength="12"></label>
      <label class="fld">Valor actual *<input class="field sm" id="f-valor" inputmode="decimal" value="${v("valor")}" placeholder="Ej: 92" required></label>
      <label class="fld">Meta *<input class="field sm" id="f-meta" inputmode="decimal" value="${v("meta")}" placeholder="${esKri ? "Máximo aceptable" : "Lo que queremos lograr"}" required></label>
      <label class="fld">Límite (pasa a rojo)<input class="field sm" id="f-limite" inputmode="decimal" value="${v("limite")}" placeholder="${esKri ? "Sobre este valor es rojo" : "Bajo este valor es rojo"}"></label>
      <label class="fld" style="grid-column:1/-1">Solución / acción a tomar<textarea class="field sm-ta" id="f-solucion" rows="2" placeholder="Qué se hará si el indicador no está en verde">${v("solucion")}</textarea></label>
      <label class="fld">Responsable<input class="field sm" id="f-resp" value="${v("responsable")}" placeholder="Nombre o área"></label>
      <label class="fld">Fecha límite<input class="field sm" type="date" id="f-fecha" value="${v("fecha")}"></label>
    </div>
    <p id="frmError" class="venc" role="alert" style="display:none"></p>
    <div class="chips" style="margin-top:12px"><button class="btn" type="submit">Guardar indicador</button><button class="btn ghost" type="button" data-act="ia-form" title="Propone unidad, meta, límite y solución a partir del nombre">Sugerir con IA</button><span class="faint" id="iaMsg" role="status" style="font-size:calc(12px * var(--font-scale))"></span><button class="btn ghost" type="button" data-act="cancelar">Cancelar</button></div>
  </form>`;
}
function guardarForm(ev){
  ev.preventDefault();
  const g = id => ($("#" + id)?.value ?? "").trim();
  const err = m => { const e = $("#frmError"); e.textContent = m; e.style.display = "block"; };
  const nombre = g("f-nombre");
  if(!nombre) return err("Escribe el nombre del indicador.");
  const dec = id => g(id).replace(",", ".");
  if(num(dec("f-valor")) === null) return err("El valor actual debe ser un número.");
  if(num(dec("f-meta")) === null) return err("La meta debe ser un número.");
  if(dec("f-limite") !== "" && num(dec("f-limite")) === null) return err("El límite debe ser un número (o déjalo vacío).");
  const tipo = g("f-tipo") === "KRI" ? "KRI" : "KPI";
  const previo = I.propios.find(p => p.id === I.form.id) || {};
  const nuevo = {
    ...previo, id: previo.id || ("p" + Date.now().toString(36) + Math.random().toString(36).slice(2, 6)),
    tipo, direccion: tipo === "KRI" ? "menor" : "mayor", nombre, unidad: g("f-unidad"),
    valor: num(dec("f-valor")), meta: num(dec("f-meta")), limite: dec("f-limite") === "" ? null : num(dec("f-limite")),
    solucion: g("f-solucion"), responsable: g("f-resp"), fecha: g("f-fecha"), estado_solucion: previo.estado_solucion || "pendiente",
  };
  const k = I.propios.findIndex(p => p.id === nuevo.id);
  if(k >= 0) I.propios[k] = nuevo; else I.propios.push(nuevo);
  saveProp(); I.form = null; pintar(); toast("Indicador guardado");
}

/* ---------- copia de respaldo ---------- */
function exportarCopia(){
  descargar(`Indicadores_Directa_${hoyIso()}.json`, JSON.stringify({version: 1, propios: I.propios, ajustes: I.ajustes}, null, 2), "application/json");
  toast("Copia guardada");
}
function importarCopia(ev){
  const f = ev.target.files && ev.target.files[0]; if(!f) return;
  const rd = new FileReader();
  rd.onload = () => {
    try{
      const j = JSON.parse(String(rd.result));
      const nuevos = arr(j.propios).filter(p => p && p.id && p.nombre);
      nuevos.forEach(p => { const k = I.propios.findIndex(x => x.id === p.id); if(k >= 0) I.propios[k] = p; else I.propios.push(p); });
      I.ajustes = {...I.ajustes, ...obj(j.ajustes)};
      saveProp(); saveAj(); pintar(); toast(`Copia cargada (${nuevos.length} indicadores propios)`);
    }catch(e){ toast("El archivo no es una copia válida", true); }
    ev.target.value = "";
  };
  rd.readAsText(f);
}
function exportarPdf(boton){
  const aj = {};
  Object.entries(I.ajustes).forEach(([k, v]) => {
    const [doc, ...resto] = k.split("|");
    if(doc === String(I.docId)) aj[resto.join("|")] = {responsable: v.responsable, fecha: v.fecha, estado_solucion: v.estado, solucion: v.solucion};
  });
  descargarPdf("/api/indicadores/pdf", {documento_id: I.docId, propios: I.propios, ajustes: aj}, `Indicadores_${hoyIso()}.pdf`, boton);
}


async function pedirIA(cuerpo){
  const r = await fetch(API + "/api/indicadores/sugerir", {method: "POST", headers: {"Content-Type": "application/json"}, body: JSON.stringify({documento_id: I.docId, ...cuerpo})}).then(x => x.json());
  if(!r.ok) throw new Error(r.error || "Sin respuesta");
  return r;
}
document.addEventListener("click", async ev => {
  const b = ev.target.closest("[data-act=ia-form],[data-act=ia-sol]"); if(!b) return;
  b.disabled = true;
  try{
    if(b.dataset.act === "ia-form"){
      const msg = $("#iaMsg"); msg.textContent = "Pensando…";
      const g = id => ($("#" + id)?.value ?? "").trim();
      const r = await pedirIA({modo: "form", tipo: g("f-tipo"), nombre: g("f-nombre")});
      const poner = (id, val) => { const el = $("#" + id); if(el && !el.value.trim() && val !== null && val !== undefined && val !== "") el.value = String(val).replace(".", ","); };
      poner("f-nombre", r.nombre); poner("f-unidad", r.unidad); poner("f-meta", r.meta); poner("f-limite", r.limite);
      poner("f-solucion", r.solucion); poner("f-resp", r.responsable);
      msg.textContent = "Listo: completé solo los campos vacíos. Ingresa el valor actual y revisa meta y límite.";
    }else{
      const it = arr(I.sug && I.sug.indicadores).find(x => String(x.id) === b.dataset.id) || {};
      const aj = ajusteDe(b.dataset.id);
      const r = await pedirIA({modo: "solucion", tipo: it.tipo, nombre: it.nombre, valor: it.valor, meta: it.meta, limite: it.limite, unidad: it.unidad, estado: it.estado});
      const k = claveAj(b.dataset.id), a = {...obj(I.ajustes[k])};
      a.solucion = ((a.solucion || "").trim() ? a.solucion.trim() + "\n" : "") + r.solucion;
      if(!a.responsable && r.responsable) a.responsable = r.responsable;
      I.ajustes[k] = a; saveAj(); pintar(); toast("Solución sugerida agregada. Revísala.");
    }
  }catch(e){ const m = $("#iaMsg"); if(m) m.textContent = "No se pudo: " + e.message; else toast("No se pudo sugerir: " + e.message, true); }
  finally{ b.disabled = false; }
});
/* ---------- eventos ---------- */
document.addEventListener("click", ev => {
  const b = ev.target.closest("[data-act]"); if(!b) return;
  const act = b.dataset.act;
  if(act === "nuevo"){ I.form = {tipo: "KPI"}; pintar(); $("#frmInd")?.scrollIntoView({behavior: "smooth", block: "center"}); $("#f-nombre")?.focus(); }
  else if(act === "editar"){ const p = I.propios.find(x => x.id === b.dataset.id); if(p){ I.form = {...p}; pintar(); $("#frmInd")?.scrollIntoView({behavior: "smooth", block: "center"}); $("#f-nombre")?.focus(); } }
  else if(act === "eliminar"){ const p = I.propios.find(x => x.id === b.dataset.id); if(p && confirm(`¿Eliminar el indicador "${p.nombre}"?`)){ I.propios = I.propios.filter(x => x.id !== p.id); saveProp(); pintar(); toast("Indicador eliminado"); } }
  else if(act === "cancelar"){ I.form = null; pintar(); }
  else if(act === "export"){ exportarCopia(); }
  else if(act === "import"){ $("#fileImp").click(); }
  else if(act === "pdf"){ exportarPdf(b); }
});
document.addEventListener("submit", ev => { if(ev.target.id === "frmInd") guardarForm(ev); });
document.addEventListener("change", ev => {
  const t = ev.target;
  if(t.id === "f-tipo" && I.form){
    const g = id => $("#" + id)?.value ?? "";
    I.form = {...I.form, tipo: t.value, nombre: g("f-nombre"), unidad: g("f-unidad"), valor: g("f-valor"), meta: g("f-meta"), limite: g("f-limite"),
      solucion: g("f-solucion"), responsable: g("f-resp"), fecha: g("f-fecha")};
    pintar(); return;
  }
  if(t.dataset && t.dataset.f) guardarCampo(t);
});
document.addEventListener("input", ev => { const t = ev.target; if(t.dataset && (t.dataset.f === "responsable" || t.dataset.f === "solucion")) guardarCampo(t); });
function guardarCampo(el){
  const id = el.dataset.id, f = el.dataset.f;
  if(el.dataset.src === "aj"){
    const k = claveAj(id), a = {...obj(I.ajustes[k])};
    a[f] = el.value; I.ajustes[k] = a; saveAj();
  }else{
    const p = I.propios.find(x => x.id === id); if(!p) return;
    if(f === "estado") p.estado_solucion = el.value; else p[f] = el.value;
    saveProp();
  }
  if(f === "estado" || f === "fecha"){ const c = el.closest(".ind"); if(c){ const w = c.querySelector(".venc:not(#frmError)"); if(w) w.remove(); } }
}
window.alCambiarDoc = id => {
  if(!id || id === I.docId) return;
  if(!I.docs.find(d => d.id === id)){ I.forzar = true; return cargarDocs(); }
  I.docId = id; pintarFiltros(); cargarSugeridos();
};
window.alRefrescar = () => { I.forzar = true; return cargarDocs(); };
document.addEventListener("DOMContentLoaded", iniciar);
