# -*- coding: utf-8 -*-
"""
Comprueba que TU llave de Gemini funciona, antes de usar la app.

    python probar_gemini.py              # prueba chat, JSON y embeddings
    python probar_gemini.py --modelos    # además lista los modelos que tu llave puede usar

Lee la llave desde el archivo .env (o desde las variables de entorno). Nunca la imprime.
"""
import sys

from dotenv import load_dotenv

load_dotenv()

import ia_config as ia  # noqa: E402


def linea(ok, texto):
    print(("  [OK]    " if ok else "  [FALLA] ") + texto)
    return ok


def main():
    print("DIRECTA — prueba de Gemini")
    est = ia.estado_ia()
    print(f"  llaves configuradas: {est['llaves_configuradas']} | modelo: {est['modelo']} | "
          f"respaldos: {', '.join(est['modelos_respaldo']) or '—'} | embeddings: {est['modelo_embedding']} ({est['dimension_embedding']} dim)")
    if not est["llaves_configuradas"]:
        print("\nNo hay llave. Copia .env.example como .env y pega tu GEMINI_API_KEY (https://aistudio.google.com/apikey).")
        return 2

    if "--modelos" in sys.argv:
        try:
            for m in ia.listar_modelos_disponibles():
                if "generateContent" in m["metodos"] or "embedContent" in m["metodos"] or "batchEmbedContents" in m["metodos"]:
                    print("   -", m["nombre"], "|", ", ".join(m["metodos"]))
        except Exception as e:
            linea(False, f"No se pudo listar modelos: {str(e)[:200]}")

    todo = True
    try:
        t = ia.llamar_llm_chat("Eres un asistente. Responde en español, una sola frase.", "Di que estás listo para ayudar al Gerente General.",
                               temperatura=0.0, max_tokens=80)
        todo &= linea(bool((t or "").strip()), f"chat: «{(t or '').strip()[:90]}»")
    except Exception as e:
        todo &= linea(False, f"chat: {str(e)[:300]}")

    try:
        j = ia.llamar_llm_json("Responde SOLO un JSON.", 'Devuelve {"ok": true, "suma": 2+2 calculada}.', max_tokens=80)
        todo &= linea(isinstance(j, dict) and bool(j), f"JSON: {j}")
    except Exception as e:
        todo &= linea(False, f"JSON: {str(e)[:300]}")

    try:
        v = ia.generar_embedding_pregunta("ingresos operacionales del ejercicio")
        todo &= linea(len(v) == ia.EMBEDDING_DIM, f"embeddings: {len(v)} dimensiones (la base espera {ia.EMBEDDING_DIM})")
    except Exception as e:
        todo &= linea(False, f"embeddings: {str(e)[:300]}")

    print("\n" + ("Todo bien: ya puedes usar la app." if todo else
                  "Hay fallas. Revisa la llave, el nombre del modelo (python probar_gemini.py --modelos) y tu cuota en AI Studio."))
    return 0 if todo else 1


if __name__ == "__main__":
    sys.exit(main())
