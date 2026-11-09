# DIRECTA V2 — Capstone 005D

### Plataforma de Inteligencia Directiva mediante Inteligencia Artificial

**Duoc UC | Ingeniería en Informática | Capstone 2026**

## Descripción del proyecto

**DIRECTA V2** es un proyecto desarrollado en el contexto de la asignatura Capstone de Duoc UC, cuyo objetivo es diseñar e implementar una plataforma inteligente que facilite el análisis de información corporativa y apoye la toma de decisiones estratégicas.

El proyecto se centra en el desarrollo del **Módulo Gerente General**, una solución que utiliza inteligencia artificial para procesar documentos empresariales, identificar riesgos, generar informes y apoyar la preparación de reuniones de directorio.

La plataforma busca reducir el trabajo manual asociado a la revisión de grandes volúmenes de información, permitiendo que el usuario acceda a resultados relevantes de manera más rápida, organizada y respaldada por sus fuentes.

Actualmente, el proyecto se encuentra en desarrollo y evolución tecnológica, avanzando desde un MVP con interfaz web hacia una nueva implementación utilizando **Flutter**, con el propósito de mejorar la experiencia de usuario y consolidar la solución final.

---

## Objetivo general

Desarrollar una plataforma de apoyo a la gestión directiva que permita analizar información corporativa mediante inteligencia artificial, facilitando la identificación de hallazgos, riesgos e indicadores relevantes para la toma de decisiones.

### Objetivos específicos

- Automatizar el análisis de documentos empresariales.
- Implementar agentes de inteligencia artificial especializados en distintas áreas de gestión.
- Permitir consultas sobre documentos mediante un chat inteligente.
- Generar informes ejecutivos que faciliten la preparación de reuniones de directorio.
- Presentar indicadores y alertas relevantes mediante un dashboard.
- Incorporar criterios de seguridad, privacidad y trazabilidad de la información.
- Mejorar progresivamente la experiencia de usuario y la integración de los componentes del sistema.

---

## 📂 Organización del repositorio

El repositorio se encuentra organizado de acuerdo con las fases de desarrollo del proyecto Capstone.

```text
Capstone005D-Grupo-5/
│
├── Fase 1/
│   └── Investigación, análisis y planificación
│
├── Fase 2/
│   └── Diseño, diagramas, arquitectura y MVP
│
├── Fase 3/
│   └── Implementación, validación y entrega final
│
└── README.md
```

Cada fase contiene los documentos y entregables correspondientes al avance del proyecto.

## Fases del proyecto

### 🔹 Fase 1 — Investigación y planificación

Durante la primera fase se desarrollaron las bases teóricas y metodológicas necesarias para definir la solución.

El trabajo estuvo enfocado en comprender la problemática, establecer el alcance del proyecto y determinar cómo se organizaría su desarrollo.

**Principales actividades:**

- Identificación de la problemática y necesidades del usuario.
- Investigación de tecnologías y alternativas de solución.
- Definición de objetivos generales y específicos.
- Levantamiento y análisis de requerimientos.
- Estudio de factibilidad técnica y operativa.
- Definición de la metodología de trabajo Scrum.
- Planificación inicial del proyecto.
- Identificación de riesgos y definición del alcance del MVP.

**Resultado:** definición de las bases del proyecto, sus requerimientos y la planificación necesaria para comenzar el diseño y desarrollo.

### 🔹 Fase 2 — Diseño y desarrollo del MVP

En esta fase se avanzó desde la planificación hacia el diseño técnico y la construcción de un primer producto mínimo viable (MVP).

Se elaboraron los modelos y diagramas necesarios para representar el funcionamiento del sistema, junto con la implementación inicial de sus principales funcionalidades.

**Principales actividades:**

- Diseño de la arquitectura general del sistema.
- Elaboración de diagramas UML.
- Desarrollo de diagramas de casos de uso, actividades, secuencia y clases.
- Diseño del flujo de navegación del usuario.
- Creación de prototipos y pantallas.
- Organización del Product Backlog e historias de usuario.
- Desarrollo del backend con Python y FastAPI.
- Integración de Supabase como sistema de almacenamiento.
- Implementación de consultas inteligentes mediante RAG.
- Desarrollo e integración de 14 agentes especializados de IA.
- Construcción de un MVP web funcional.
- Ejecución de pruebas y revisión de funcionalidades.

**Funcionalidades consideradas en el MVP:**

- Carga y procesamiento de documentos PDF, Word y Excel.
- Análisis documental mediante agentes de inteligencia artificial.
- Chat inteligente con respuestas basadas en documentos.
- Visualización de indicadores y hallazgos.
- Dashboard ejecutivo.
- Apoyo a la elaboración de memorias anuales.
- Generación y exportación de informes.

**Resultado:** un MVP inicial que permite validar las funcionalidades principales del Módulo Gerente General e identificar mejoras para la siguiente etapa.

### 🔹 Fase 3 — Evolución, integración y entrega final

La tercera fase está orientada al perfeccionamiento de la solución, la integración de sus componentes y la preparación del producto final.

Como parte de esta evolución, se está trabajando en la **migración de la interfaz web del MVP hacia Flutter**, manteniendo el enfoque en las funcionalidades del sistema y buscando mejorar la experiencia de usuario.

**Actividades en desarrollo y planificadas:**

- Migración y adaptación de interfaces a Flutter.
- Integración de la nueva interfaz con los servicios del backend.
- Mejoras en navegación, diseño y experiencia de usuario.
- Ajustes en el procesamiento y análisis de documentos.
- Fortalecimiento de mecanismos de autenticación y seguridad.
- Mejoras en los informes ejecutivos y visualización de indicadores.
- Integración y validación de funcionalidades.
- Ejecución de pruebas funcionales y corrección de errores.
- Elaboración de documentación técnica y manuales.
- Preparación de la presentación y defensa final del proyecto.

**Resultado esperado:** una versión integrada y validada de DIRECTA V2, acompañada de su documentación y evidencias de desarrollo.

---

## 🛠️ Tecnologías utilizadas

Las tecnologías consideradas durante el desarrollo del proyecto incluyen:

| Área | Tecnología |
|---|---|
| Interfaz del MVP inicial | HTML, CSS y JavaScript |
| Nueva interfaz | Flutter / Dart |
| Backend | Python 3.12 y FastAPI |
| Base de datos | Supabase / PostgreSQL |
| Búsqueda vectorial | pgvector |
| Inteligencia artificial | Groq y NVIDIA |
| Procesamiento documental | PyPDF, LangChain, python-docx |
| Generación de archivos | xhtml2pdf y openpyxl |
| Control de versiones | Git y GitHub |
| Metodología de desarrollo | Scrum |

> **Nota:** El stack tecnológico continúa evolucionando durante la implementación final. La interfaz original del MVP está siendo reemplazada progresivamente por una solución desarrollada en Flutter.

---

##  Funcionamiento general de DIRECTA V2

El sistema contempla un flujo de procesamiento y consulta de información corporativa:

1. **Carga documental:** el usuario incorpora documentos empresariales.
2. **Procesamiento:** el backend extrae, fragmenta e indexa el contenido.
3. **Análisis inteligente:** los 14 agentes especializados analizan la información.
4. **Consulta:** el usuario realiza preguntas mediante un chat basado en RAG.
5. **Visualización:** los resultados se presentan mediante indicadores, alertas y hallazgos.
6. **Generación de informes:** la información relevante puede organizarse y exportarse para apoyar las reuniones de directorio.

La arquitectura busca mantener una separación entre la interfaz, los servicios de procesamiento, la base de datos y los proveedores de inteligencia artificial.

---

## 📊 Metodología de trabajo

El proyecto utiliza la metodología ágil **Scrum**, organizada en sprints de dos semanas.

Durante cada sprint se realizan actividades de planificación, desarrollo, seguimiento y validación, permitiendo incorporar mejoras de forma progresiva.

La gestión del proyecto considera historias de usuario, prioridades del Product Backlog, revisión de avances y pruebas de las funcionalidades implementadas.

---

## Estado actual del proyecto

**Estado: En desarrollo — Fase de integración y evolución del MVP.**

Se cuenta con una versión inicial del MVP web que permitió validar el funcionamiento de los principales módulos de DIRECTA V2.

Actualmente, el equipo trabaja en la evolución de la interfaz hacia Flutter, la integración de funcionalidades, la mejora de la seguridad y las pruebas necesarias para la entrega final.

Algunas funcionalidades pueden encontrarse en proceso de implementación, ajuste o validación.

---

## 👥 Equipo de desarrollo

**Capstone 005D — Grupo 5 | Duoc UC**

| Integrante | Rol |
|---|---|
| Rodrigo Bello | Scrum Master |
| Ignacio González | Product Owner |
| Benjamín Gutiérrez | Desarrollador Backend |
| Javiera Villalobos | Desarrolladora Frontend |

---

## Contexto académico

Este repositorio reúne los avances, entregables y evidencias del proyecto DIRECTA V2, desarrollado como parte de la asignatura Capstone de Duoc UC durante el año 2026.

Su propósito es documentar el proceso completo de desarrollo, desde la investigación y planificación inicial hasta el diseño, implementación, validación y presentación de la solución final.

**DIRECTA V2 — Capstone 005D | 2026**
