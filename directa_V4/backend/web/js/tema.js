// Aplica el tema guardado (claro u oscuro) antes de dibujar la página, para evitar parpadeos.
// Lo usan dashboard.html, memoria.html e indicadores.html.
try {
  var q = new URLSearchParams(location.search);
  var t = q.get("embed") === "1" ? q.get("theme") : null;
  if (t !== "dark" && t !== "light") t = localStorage.getItem("directa_theme");
  if (t !== "dark" && t !== "light") t = (window.matchMedia && matchMedia("(prefers-color-scheme: light)").matches) ? "light" : "dark";
  document.documentElement.setAttribute("data-theme", t);
} catch (e) {}
