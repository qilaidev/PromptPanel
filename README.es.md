<div align="center">

<img src="Sources/PromptPanel/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" alt="PromptPanel 项目快贴 — gestor de prompts y lanzador de snippets nativo para macOS" width="128" height="128" />

# PromptPanel | 项目快贴

### Gestor de prompts / lanzador de snippets nativo para macOS, pensado para ChatGPT, Claude, Cursor, Copilot, VS Code y Terminal
### Native macOS prompt manager and snippet launcher for ChatGPT, Claude, Cursor, Copilot, VS Code, and Terminal.

PromptPanel (项目快贴) es un **gestor de prompts para macOS** de tipo local-first, un **lanzador de prompts de IA** y un **lanzador de snippets de código**. Pulsa un atajo global, busca en tu **biblioteca local de prompts / snippets** y pega prompts, code snippets, plantillas e instrucciones reutilizables en **ChatGPT, Claude, Cursor, Copilot, VS Code, Terminal, el navegador o cualquier campo de texto**.

PromptPanel is a local-first **macOS prompt manager**, **AI prompt launcher**, and **snippet launcher**. It is built for developers and AI power users who reuse multiline prompts, coding templates, project context blocks, terminal commands, and reply snippets across apps.

[![Release: v1.1.2](https://img.shields.io/badge/Release-v1.1.2-blue.svg)](CHANGELOG.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform: macOS 14+](https://img.shields.io/badge/Platform-macOS%2014%2B-lightgrey.svg)](https://www.apple.com/macos)
[![Swift 5.10](https://img.shields.io/badge/Swift-5.10-orange.svg)](https://swift.org)
[![Apple Silicon & Intel](https://img.shields.io/badge/Arch-Apple%20Silicon%20%26%20Intel-blue.svg)](#instalación)
[![Local-first · No cloud](https://img.shields.io/badge/Local--first-No%20cloud-brightgreen.svg)](#privacidad-y-datos)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-success.svg)](.github/CONTRIBUTING.md)

[English](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [**Español**](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md)

[FAQ](docs/FAQ.md) · [Documentación](docs/README.md) · [LLM index](llms.txt) · [Changelog](CHANGELOG.md) · [Contribuir](.github/CONTRIBUTING.md)

</div>

---

## Resumen en 30 segundos / 30-Second Summary

| Dimensión / Field | Descripción / Answer |
| --- | --- |
| Qué es / What it is | Un prompt manager y snippet launcher de código abierto y local-first para macOS, que abre un panel nativo con un atajo global para buscar y pegar texto reutilizable. |
| Qué problema resuelve / Problem solved | Evita que los usuarios frecuentes de ChatGPT, Claude, Cursor, Copilot, VS Code y Terminal tengan que revolver sus notas una y otra vez para copiar el mismo system prompt, contexto de proyecto o plantilla de comandos. |
| Para quién es / Audience | Usuarios intensivos de IA, desarrolladores, prompt engineers, redactores técnicos, PM, consultores y desarrolladores independientes que necesitan aislar su biblioteca de prompts por proyecto. |
| Funciones clave / Core features | Atajo global, búsqueda instantánea, aislamiento por proyecto, `Universal / proyecto general`, filtrado por `#tag`, prioridad del portapapeles, pegado automático mediante Accessibility, registro de ejecución, importación/exportación en JSON/Markdown. |
| Pila técnica / Tech stack | Swift 5.10, AppKit `NSPanel`, SwiftUI, SQLite/GRDB, KeyboardShortcuts, Sparkle 2, Swift Package Manager. |
| Inicio rápido / Quick start | `git clone` -> `./scripts/build-app.sh` -> `open dist/PromptPanel.app`. En la primera ejecución, concede el permiso de Accessibility para el pegado automático; si no lo concedes, también puede copiar al portapapeles. |
| Casos de uso típicos / Use cases | Role prompt de ChatGPT/Claude, contexto de proyecto de Cursor, checklist de revisión de PR, snippet de comando de terminal, plantilla de notas de reunión, plantilla de respuesta específica por cliente. |
| Idioma de la interfaz / UI language | **La interfaz de la aplicación está actualmente solo en chino simplificado** (`CFBundleDevelopmentRegion = zh-Hans`; no hay recursos de localización ni selector de idioma dentro de la app). La documentación está disponible en 8 idiomas y `README.md` incluye una tabla de equivalencias chino→inglés de las etiquetas de la interfaz. El contenido de los prompts que guardes puede estar en cualquier idioma. |
| Limitaciones / Limits | Solo compatible con macOS 14+; interfaz solo en chino simplificado; la Release actual aún no incluye un binario notarizado; sin sincronización en la nube, sin colaboración en equipo, sin versión para Windows/Linux; sin plantillas con variables; el pegado automático depende del permiso de Accessibility de macOS. |

## ¿Qué es PromptPanel? / What is PromptPanel?

**PromptPanel (项目快贴)** es una **herramienta de gestión de prompts para macOS** y un **snippet launcher** de código abierto y nativos. Está diseñado en torno a un flujo de trabajo de IA muy corto: en cualquier aplicación en primer plano pulsas un atajo, buscas en tu biblioteca local de prompts, pulsas `Enter`, el contenido se escribe primero en el portapapeles del sistema y luego intenta pegarse automáticamente en el campo de texto activo. Sin cuentas, sin sincronización en la nube, sin telemetría: los datos principales permanecen en tu propio Mac.

In English: **PromptPanel is a native macOS prompt manager, AI prompt launcher, and local-first snippet manager** for people who reuse prompts and templates across ChatGPT, Claude, Cursor, Copilot, VS Code, Terminal, browsers, and other macOS text fields.

Si estás buscando **gestión de prompts de ChatGPT en macOS**, **biblioteca de prompts de Claude**, **gestor de snippets de código para Cursor**, **biblioteca de prompts local-first**, **macOS global hotkey paste tool**, **Raycast Snippets alternative for AI prompts** u **open-source TextExpander alternative for multiline prompts**, PromptPanel responde justo a esa necesidad: convertir las instrucciones de IA, los snippets de código y el contexto de proyecto que escribes repetidamente en un panel rápido local, buscable y auditable.

## ¿Te suena familiar?

PromptPanel existe porque los mismos cinco problemas aparecen a diario para cualquiera que trabaje con LLM:

- Reescribes el mismo **role / system prompt** ("eres un ingeniero senior de plantilla…") en un chat nuevo de ChatGPT o Claude diez veces al día.
- Mantienes una app de notas o un borrador lleno de **prompts de IA y checklists de revisión de código** y navegas por él a golpe de `⌘+F`.
- Por fin encuentras el prompt correcto y **el pegado falla en silencio** porque el foco cambió o la app bloqueó las pulsaciones de teclado sintéticas.
- Tu **bloque de contexto de proyecto de Cursor / Copilot** está en un archivo, el **snippet de comando de terminal** en otro y el **prompt de revisión de PR** en un tercero, y ninguno se puede buscar desde un único lugar.
- No vas a poner un brief real de cliente ni una arquitectura propietaria en un **gestor de prompts en la nube**, así que acabas sin ningún gestor de prompts.

PromptPanel reduce todo eso a un único ciclo de menos de un segundo, con un archivo SQLite local que te pertenece por completo.

## ¿Por qué PromptPanel?

La mayoría de los "gestores de prompts" son o bien extensiones de navegador (atadas a un solo sitio), o bien herramientas de snippets genéricas que no se diseñaron para el flujo de trabajo de IA. PromptPanel se ha construido específicamente en torno a un ciclo corto:

> **atajo → búsqueda → enter → el contenido aterriza en el campo de entrada activo**

Todo lo demás está al servicio de que ese ciclo sea rápido, predecible y nunca pierda datos.

| Lo que quieres… | Lo que te da PromptPanel |
|---|---|
| Una biblioteca de prompts que funcione **en todas las apps**, no solo en un sitio web | Atajo global, panel nativo de macOS, funciona en cualquier campo de texto |
| **Ciclo nativo de baja latencia** — objetivo de menos de un segundo desde la pulsación hasta la escritura | Objetivo de < 300 ms de atajo a foco, < 80 ms de refresco de búsqueda, < 250 ms de ejecución |
| **Aislamiento por proyecto** para que los prompts del cliente A no se filtren al cliente B | Proyectos de primer nivel + un proyecto `Universal` integrado para el contenido compartido |
| **Sin dependencia de la nube** para prompts sensibles | SQLite local. Cero llamadas de red para las funciones principales. Tus datos son un único archivo que te pertenece |
| **Pegado automático que no falla en silencio** | Pegado automático primero, respaldo del portapapeles siempre, y un aviso claro si el pegado fue bloqueado |
| **Operación solo con teclado** | Invocar → escribir → flechas → Enter. El ratón nunca es necesario |
| Código abierto que puedes auditar, bifurcar y en el que confiar | Licencia MIT, Swift puro, sin telemetría |

## ¿Para quién es?

- **Usuarios intensivos de ChatGPT / Claude / Gemini** que reutilizan las mismas definiciones de rol, restricciones de formato de salida y bloques de contexto
- **Usuarios de Cursor / Copilot / Aider** que pegan los mismos resúmenes de arquitectura y checklists de revisión
- **Desarrolladores** que escriben repetidamente esqueletos de mensajes de commit, plantillas de revisión de código, comandos de terminal y snippets de diagnóstico de errores
- **Indie hackers y consultores** que hacen malabares con varios proyectos de clientes, cada uno con sus guías de estilo y reglas de tono de voz
- **Redactores técnicos y PM** que mantienen respuestas reutilizables, actualizaciones de estado y esqueletos de especificaciones

Si "copio y pego el mismo prompt multilínea veinte veces al día" te describe, esta herramienta se escribió para ti.

## Funciones

### Núcleo (v1.0)

- 🔥 **Atajo global** — invoca el panel desde cualquier app en primer plano, con atajo configurable
- ⚡ **< 300 ms hasta la entrada** — basado en `NSPanel`, sin Electron, sin runtime web, sin arranque en frío
- 🔍 **Búsqueda instantánea** en título y cuerpo, sin paso de confirmación
- 🗂️ **Proyectos** — aísla los prompts por cliente, repositorio o contexto; el proyecto `Universal` siempre está visible
- 📋 **Pegado automático con respaldo del portapapeles** — usa `CGEvent` para enviar ⌘V, y degrada con elegancia si falta el permiso de Accessibility
- 🎯 **Prioridad al teclado** — flechas para navegar, Enter para ejecutar, Esc para descartar
- 📌 **Fijar y ordenar** — fija las entradas frecuentes, ordena manualmente, luego por recencia y luego por número de usos
- 🌗 Tema **claro / oscuro / del sistema**
- 🪶 **Residente en la barra de menús** — fuera del camino hasta que lo invocas
- 🚀 **Inicio al abrir sesión** mediante `SMAppService`
- 🔐 **Degradación consciente de permisos** — sin Accessibility, sigues teniendo copia con una tecla y una pista clara en la interfaz
- 📝 **Contenido multilínea** — cuerpos de plantilla completos, sin límite de longitud en el almacenamiento
- 📊 **Registro de ejecución** para diagnosticar fallos de pegado
- 🔄 **Actualización manual vía GitHub Releases** (la actualización automática de Sparkle está integrada pero se distribuye desactivada por defecto; el mantenedor la activará una vez que se aloje un feed appcast firmado)

### Lo que explícitamente *no* hace (límites del proyecto)

Por diseño, PromptPanel **nunca** añadirá sincronización en la nube, colaboración en equipo ni orquestación compleja de flujos de trabajo. No son cosas "para más adelante": están fuera de alcance para siempre. La herramienta es una utilidad de un solo usuario, solo local, y ese es precisamente su valor. Consulta [PRD §4.2](docs/项目快贴-PRD.md) para conocer el razonamiento.

## ¿Cómo funciona?

```
   ┌──────────────┐    hotkey     ┌──────────────┐    select    ┌──────────────┐
   │  any app     │  ──────────►  │ PromptPanel  │  ──────────► │  clipboard   │
   │ (ChatGPT,    │   (global)    │  NSPanel     │   (Enter)    │   (write)    │
   │  Claude,     │               │              │              └──────┬───────┘
   │  Cursor…)    │ ◄──────────── │              │                     │
   └──────────────┘  paste / focus└──────────────┘                     │
          ▲                         restored                            │
          └────────── CGEvent ⌘V (Accessibility permission) ◄───────────┘
                          fallback: clipboard only + toast
```

1. Pulsas el atajo configurado (la librería `KeyboardShortcuts` lo captura a nivel de todo el sistema).
2. PromptPanel coloca un `NSPanel` sobre la ventana activa, enfoca el campo de búsqueda y muestra las entradas del proyecto actual más las del proyecto `Universal`, ordenadas por fijado → manual → recencia → número de usos.
3. Escribes para filtrar (en vivo, sin confirmar), navegas con las flechas y pulsas `Enter`.
4. El contenido seleccionado **siempre** se escribe primero en el portapapeles del sistema (esta es la garantía: el portapapeles nunca falla en silencio).
5. El panel se oculta, la app anterior recupera el foco y PromptPanel sintetiza un `⌘V` mediante `CGEvent`. Si falta el permiso de Accessibility o la app de destino bloquea los eventos sintéticos, un aviso te indica "Copiado — pulsa ⌘V para pegar."
6. La ejecución se registra localmente para que puedas diagnosticar más tarde cualquier problema de pegado específico de una app.

Esta separación — **el portapapeles como garantía, el pegado automático como mejor esfuerzo** — es la decisión de diseño más importante del proyecto.

## Instalación

> **Requisito del sistema:** macOS 14 (Sonoma) o posterior. Se admiten tanto Apple Silicon como Intel.

### Opción A — Compilar desde el código fuente (vía actual mientras esté en pre-release)

```bash
# 1. Clonar
git clone https://github.com/tytsxai/PromptPanel.git
cd PromptPanel

# 2. Compilar el paquete .app (firmado ad-hoc por defecto)
./scripts/build-app.sh

# 3. Muévelo a Aplicaciones (o ejecútalo desde dist/)
open dist/PromptPanel.app
```

Requisitos para compilar:

- Xcode 15+ con el SDK de macOS 14
- Toolchain de Swift 5.10 (`xcrun swift --version`)

### Opción B — Release firmada y notarizada

Las GitHub Releases actualmente solo incluyen notas de versión de código/documentación; todavía no se adjunta ningún binario notarizado. Hasta que se complete la cadena de notarización de Developer ID, compila localmente con `./scripts/build-app.sh`.

### Configuración de la primera ejecución

1. **Concede el permiso de Accessibility** cuando se te solicite. macOS lo usa para permitir las pulsaciones de teclado sintéticas `⌘V`. Sin él, PromptPanel sigue copiando al portapapeles de forma fiable; simplemente pegas manualmente.
2. **Configura tu atajo** en `设置 → 偏好 → 快捷键 → 呼出面板`. El valor por defecto actual es `⌥2`; elige otro atajo si entra en conflicto con tu configuración.
3. **Crea un proyecto** o empieza a añadir entradas a `Universal`.

## Inicio rápido

Suponiendo que la app está compilada y en ejecución (icono visible en la barra de menús):

```text
1. Ventana principal → 内容库 (Biblioteca) → añade tu primera entrada:
   título "review", cuerpo = tu prompt de revisión de código, etiquetas opcionales
2. ⌥2              → aparece el panel, con el foco en el campo de búsqueda
3. escribe "review"→ filtra hasta tu prompt de revisión de código
4. ↵               → el contenido se copia y luego se pega en el campo activo
5. (el panel se oculta) → sigues trabajando
```

### Sintaxis de búsqueda en el panel / Search syntax

| Escribes | Qué ocurre |
|---|---|
| `review` | Coincidencia por **prefijo con FTS5 de SQLite** sobre el título y el contenido de la entrada |
| `code rev` | Cada token separado por espacios es un término de prefijo, combinados con AND |
| `#sql` | Filtra a las entradas con la etiqueta `sql`; el token `#tag` se elimina de la consulta de texto |
| `#sql migrate` | Filtro de etiqueta `sql` **y** coincidencia de texto `migrate` |
| *(vacío)* | Navega por el proyecto actual más `Universal`, ordenado por fijado → orden manual → recencia → número de usos |

Notas: solo se usa el primer token `#tag` como filtro de etiqueta, y coincide de forma exacta y sensible a mayúsculas (`#SQL` no coincidirá con una etiqueta `sql`); los resultados se limitan a 100 filas; la coincidencia de texto es por prefijo, así que un término tomado del interior de una palabra (o de una secuencia CJK sin espacios) no coincidirá.

Puedes cambiar el proyecto activo desde dentro del panel sin abrir la ventana principal — solo con el teclado, sin desvíos. `⌘1`–`⌘9` ejecutan directamente las nueve primeras filas; `⌘C` copia sin pegar; `⌘P` fija el panel; `Esc` lo cierra.

## Configuración

| Ajuste | Dónde | Notas |
|---|---|---|
| Atajo global | `设置 → 偏好 → 快捷键 → 呼出面板` | Un único atajo. Comportamiento de alternancia: la misma tecla lo descarta |
| Tema | `设置 → 偏好 → 外观 → 主题` | Claro / oscuro / seguir al sistema |
| Inicio al abrir sesión | `设置 → 偏好 → 权限与启动` | Usa `SMAppService` |
| Canal de actualización | GitHub Releases (manual) | Sparkle 2 está integrado pero desactivado hasta que se aloje un appcast firmado; suscríbete a las notificaciones de versiones y reemplaza el `.app` |
| Ubicación de la base de datos | `~/Library/Application Support/PromptPanel/promptpanel.db` | SQLite de un único archivo, fácil de respaldar |
| Registros | `~/Library/Logs/PromptPanel/` | Se inspeccionan mediante el "Runtime Health" de la ventana principal |

## Privacidad y datos

- **Local-first por definición.** Tus prompts viven en un único archivo SQLite en tu Mac. La app no envía tu contenido a ningún sitio.
- **Sin telemetría.** Sin SDK de analítica, sin endpoints de métricas, sin servicio de reporte de fallos.
- **El acceso a la red** es nulo en la versión actual. Sparkle viene incluido, pero el feed de actualización no está configurado, así que no ocurre ninguna llamada saliente en absoluto salvo que una compilación futura incluya un appcast.
- **Sin cuentas.** No hay nada donde iniciar sesión.
- **Código abierto.** Audita `Sources/PromptPanel/Core/` para verificar cualquiera de los puntos anteriores.

Si tus prompts contienen información propietaria — arquitectura interna, briefs de clientes, contexto bajo NDA — esta es justamente la propiedad que quieres.

## ¿Cómo se compara PromptPanel con las alternativas?

> Orientación rápida, no un ataque. Estas herramientas son buenas en lo suyo.

| | **PromptPanel** | TextExpander | Espanso | Raycast Snippets | Alfred Snippets | Extensiones de prompts para navegador |
|---|:---:|:---:|:---:|:---:|:---:|:---:|
| Código abierto | ✅ MIT | ❌ | ✅ GPLv3 | Parcial | ❌ | variable |
| Nativo de macOS (sin Electron / runtime web) | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| Funciona en cualquier app (no solo en el navegador) | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| Panel de búsqueda rápida (no solo cadenas de activación) | ✅ | parcial | ❌ | ✅ | ✅ | variable |
| Aislamiento por proyecto / contexto | ✅ de primer nivel | grupos | carpetas | carpetas | carpetas | poco frecuente |
| Flujo solo con teclado | ✅ | parcial | ✅ | ✅ | ✅ | variable |
| Opción solo local / sin nube | ✅ por defecto | opcional, los planes de pago empujan a la nube | ✅ | requiere cuenta | ✅ | normalmente en la nube |
| Gratis | ✅ | $$$ | ✅ | freemium | requiere Powerpack | variable |
| Construido específicamente en torno al flujo de trabajo de prompts de IA | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ pero solo en el navegador |

**En resumen:** si solo vives en el navegador, una extensión de navegador está bien. Si vives en Cursor/VS Code/Terminal/Slack/en todas partes, quieres algo nativo y basado en un panel. Entre las opciones nativas basadas en panel, PromptPanel es la de código abierto y con forma de prompt de IA.

## Ejemplos de flujo de trabajo

Formas concretas en que la gente usa PromptPanel en su día a día — estas también sirven como las preguntas de cola larga de tipo "¿cómo hago…?" que PromptPanel está diseñado para responder.

- **Arranca un chat nuevo de ChatGPT / Claude con tu role / system prompt estándar.** Atajo → escribe `role` → Enter. Se acabó reescribir "Eres un ingeniero senior de plantilla que…" por 200.ª vez.
- **Suelta un bloque de contexto de proyecto de Cursor / Copilot en un archivo nuevo.** Ten guardado una sola vez un bloque de varios párrafos "aquí están la arquitectura, las convenciones y las restricciones"; pégalo en cualquier sesión nueva de Cursor con una sola pulsación.
- **Pega un checklist de revisión de código en un borrador de PR.** El largo checklist con viñetas vive en PromptPanel; un atajo lo añade a la descripción de un PR de GitHub.
- **Lanza un comando de terminal recurrente con la combinación exacta de flags.** `kubectl get pods --context=prod --namespace=… -o jsonpath=…` — se escribe una vez, se guarda y se invoca con una cadena de búsqueda corta.
- **Inserta una plantilla de notas de reunión en Notion / Obsidian / Apple Notes.** La misma plantilla en cada standup del lunes → un atajo, cero copiar y pegar desde un borrador de una app de notas.
- **Envía una plantilla de respuesta de atención al cliente / ventas a Slack o al correo.** Un tono distinto por plantilla, elegido desde un panel de búsqueda rápida en lugar de una carpeta de notas.
- **Cambia entre proyectos con conjuntos de prompts aislados.** Cada grupo de proyecto conserva sus propios role prompts, snippets y plantillas, de modo que el contexto nunca se filtra entre clientes.

## Pila técnica

- **Lenguaje:** Swift 5.10
- **UI:** AppKit (`NSPanel`, `NSStatusItem`) + SwiftUI
- **Almacenamiento:** SQLite mediante [GRDB.swift](https://github.com/groue/GRDB.swift)
- **Atajo:** [sindresorhus/KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (Carbon Hot Key por debajo)
- **Pegado automático:** `CGEvent` sintetizando ⌘V tras restaurar el foco
- **Elemento de inicio de sesión:** `SMAppService`
- **Actualizador:** [Sparkle 2](https://sparkle-project.org/)
- **Distribución:** Developer ID + notarización de Apple (sin Mac App Store)
- **Compilación:** Swift Package Manager — no requiere proyecto de Xcode

Consulta [docs/技术选型.md](docs/技术选型.md) para el registro completo de decisiones.

## Estructura del proyecto

```
PromptPanel/
├── Sources/PromptPanel/
│   ├── App/              # AppDelegate, AppState, lifecycle
│   ├── Core/
│   │   ├── Database/     # SQLite open / migrate / recover
│   │   ├── Repositories/ # Project, Entry, Settings, Log
│   │   ├── Services/     # PanelService, ExecuteService, SearchService…
│   │   ├── Diagnostics/  # Hotkey-to-focus timing
│   │   └── Utils/
│   ├── Integrations/     # Clipboard, Paste (CGEvent), Tray, Hotkey, Updater
│   ├── Features/
│   │   ├── Panel/        # QuickPanelView + ViewModel — the hero feature
│   │   └── MainWindow/   # Library + Settings
│   └── Resources/        # Info.plist, entitlements, AppIcon, Assets
├── Tests/PromptPanelTests/
├── frontend-draft/       # UI source-of-truth (HTML/JSX mockups)
├── scripts/              # build-app.sh, notarize, release readiness, restore
├── docs/                 # public architecture, FAQ, PRD, release, ops, handoff docs
├── .github/              # contribution, security, conduct, issue/PR templates, CI
├── llms.txt              # short AI-search / LLM-readable project index
├── codemeta.json         # structured open-source software metadata
└── Package.swift         # SwiftPM package definition
```

## Documentación

El conjunto de documentación pública forma parte del repositorio:

- [Índice de documentación](docs/README.md)
- [FAQ](docs/FAQ.md)
- [PRD del producto](docs/项目快贴-PRD.md)
- [Presentación del proyecto](docs/项目介绍.md)
- [Arquitectura](docs/架构说明.md)
- [Módulos y lógica principales](docs/关键模块与核心逻辑.md)
- [Contrato de API y funciones](docs/API与功能说明.md)
- [Configuración](docs/配置说明.md)
- [Despliegue](docs/部署说明.md)
- [Estándares de desarrollo](docs/开发规范.md)
- [Ejemplos de uso](docs/使用示例.md)
- [Operaciones y resolución de problemas](docs/运维与排错指南.md)
- [Guía de traspaso para mantenedores](docs/接手维护指南.md)
- [Matriz de sincronización docs/código](docs/文档与代码同步矩阵.md)
- [Publicación y recuperación](docs/生产发布与恢复手册.md)
- [Hoja de ruta y guía de contribución](docs/路线图与贡献指南.md)
- [Búsqueda con IA y descubribilidad](docs/ai-search-discoverability.md)
- [Contexto completo para LLM](docs/ai-search/llms-full.txt)
- [Metadatos de búsqueda JSON-LD](docs/search-metadata.schema.jsonld)
- [Contribuir](.github/CONTRIBUTING.md)
- [Seguridad](.github/SECURITY.md)
- [Metadatos de software CodeMeta](codemeta.json)

Para motores de respuesta y herramientas de IA con conocimiento del repositorio, empieza por [llms.txt](llms.txt) o el ampliado [llms-full.txt](docs/ai-search/llms-full.txt).

## Búsqueda y descubribilidad con IA

PromptPanel mantiene dentro del repositorio las superficies clásicas de SEO y GEO para que tanto los usuarios como los motores de respuesta puedan identificar el proyecto con precisión:

- `README.md` y `README.zh-CN.md` ofrecen el resumen de página de aterrizaje para humanos y las capturas de pantalla actuales.
- [llms.txt](llms.txt) es el índice corto legible por IA para herramientas con conocimiento del repositorio.
- [docs/ai-search/llms-full.txt](docs/ai-search/llms-full.txt) es el contexto ampliado para motores de respuesta, con respuestas de tipo FAQ.
- [codemeta.json](codemeta.json) y [Schema.org JSON-LD](docs/search-metadata.schema.jsonld) describen la app para catálogos de software, rastreadores de búsqueda y la futura publicación de un sitio de documentación.
- [Búsqueda con IA y descubribilidad](docs/ai-search-discoverability.md) define la redacción canónica, el mapa de intención de búsqueda y el checklist de mantenimiento.

## Hoja de ruta

PromptPanel sigue una hoja de ruta **deliberadamente pequeña**. El PRD enumera los elementos que están explícitamente descartados para siempre (sincronización en la nube, equipos, orquestación de flujos de trabajo). Dentro del alcance:

- [x] v1.0 — enlace principal completo: atajo → búsqueda → ejecución, proyectos, respaldo del portapapeles, claro/oscuro, elemento de inicio de sesión, Sparkle, scripts de firma y notarización
- [x] Importación y exportación en JSON / Markdown, con copia de seguridad automática antes de importar
- [ ] "Repetir última entrada" con un solo toque
- [ ] Plantillas con variables (estilo `{{name}}`) — solo si se puede añadir sin ralentizar el enlace principal

Consulta [docs/路线图与贡献指南.md](docs/路线图与贡献指南.md) para las reglas de priorización, [CHANGELOG.md](CHANGELOG.md) para lo que ya se ha publicado y los [issues](https://github.com/tytsxai/PromptPanel/issues) para la planificación pública.

## Preguntas frecuentes

Para una FAQ más extensa, consulta [FAQ.md](docs/FAQ.md). Las más destacadas:

### ¿PromptPanel es gratis?

Sí. Licencia MIT. Sin plan de pago, sin límite de uso, sin cuenta.

### ¿Funciona con Apple Silicon (M1/M2/M3/M4)?

Sí — la versión se compila como binario universal (arm64 + x86_64), por lo que se ejecuta de forma nativa tanto en Macs con Apple Silicon como con Intel en macOS 14+.

### ¿Envía mis prompts a algún sitio?

No. La versión actual no hace ninguna llamada de red. Sparkle viene incluido, pero el feed de actualización no está configurado en esta compilación, así que no ocurre ningún tráfico saliente en absoluto. El contenido de tus prompts nunca sale de tu Mac.

### ¿Por qué pide el permiso de Accessibility?

Para sintetizar una pulsación `⌘V` después de que el panel se oculte y tu app anterior recupere el foco. Sin este permiso la app sigue funcionando — simplemente se detiene en el paso del portapapeles y te muestra un aviso "pulsa ⌘V para pegar".

### ¿Añadiréis sincronización en la nube / uso compartido en equipo / flujos de trabajo?

No, deliberadamente. Están listados como **no-objetivos permanentes** en el [PRD §4.2](docs/项目快贴-PRD.md). La identidad del producto es "un solo usuario, solo local, rápido". Añadir cualquiera de ellos cambiaría lo que es el producto.

### ¿Por qué no Electron / Tauri?

Los caminos más críticos de este producto (temporización del atajo global, restauración del foco, inyección de pulsaciones sintéticas, flujo de permisos de accessibility) son cuestiones de integración con el sistema de macOS. Una capa multiplataforma añade latencia e indirección sin aportar ninguna función que importe para este producto. Consulta [docs/技术选型.md](docs/技术选型.md) para el razonamiento completo.

### ¿Cómo reporto un error o solicito una función?

Abre un issue: <https://github.com/tytsxai/PromptPanel/issues>. Por favor, usa las plantillas — nos ahorrarán idas y venidas a ambos.

### ¿Cómo importo mis prompts existentes desde otra herramienta?

Usa `Settings → Maintenance → Import JSON` para transferencias completas de bibliotecas de PromptPanel, o `Import MD` para colecciones de prompts en Markdown. Las importaciones crean automáticamente antes una copia de seguridad local de la base de datos. `Export JSON` es lo mejor para una migración sin pérdidas; `Export MD` es lo mejor para compartir de forma revisable.

## Contribuir

Los PR son bienvenidos — por favor, lee primero [CONTRIBUTING.md](.github/CONTRIBUTING.md). Dos reglas no obvias:

1. **Los cambios de UI deben alinearse con `frontend-draft/`.** Ese directorio es la fuente de verdad para lo visual; no publiques una vista de Swift que contradiga el mockup de JSX.
2. **Mantente dentro del alcance del PRD.** Si una propuesta empujaría el producto hacia la nube / equipos / flujos de trabajo, es un "no" por muy bien implementada que esté. Esto no es control de acceso — es la razón por la que la herramienta es rápida y fiable.

## Agradecimientos

PromptPanel se apoya en:

- [GRDB.swift](https://github.com/groue/GRDB.swift) de Gwendal Roué
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) de Sindre Sorhus
- [Sparkle](https://github.com/sparkle-project/Sparkle) del equipo de Sparkle

…y la comunidad más amplia de Swift / AppKit, cuya documentación y respuestas en Stack Overflow hicieron posibles los caminos de integración con el sistema.

## Licencia

[MIT](LICENSE) © 2026 tytsxai y colaboradores de PromptPanel.

---

<sub>**Keywords** (para que puedas encontrar esto de verdad cuando busques): macOS prompt manager · AI prompt launcher · ChatGPT prompt manager macOS · Claude prompt library · Cursor snippet manager · Copilot prompt template launcher · open-source TextExpander alternative · Espanso alternative · Raycast snippets alternative · Alfred snippet replacement · global hotkey paste macOS · local-first prompt library · offline AI prompt storage · native Swift NSPanel app · AI workflow productivity tool · prompt template manager macOS · snippet launcher macOS · keyboard-first prompt picker · LLM prompt library Mac · prompt engineering toolkit macOS · Cursor prompt manager · fast local prompt launcher for AI · NDA-safe prompt storage · gestor de prompts macOS · lanzador de prompts de IA · biblioteca de prompts local · gestor de snippets para Cursor · alternativa a TextExpander de código abierto · almacenamiento de prompts sin conexión.</sub>

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=tytsxai/PromptPanel&type=Date)](https://www.star-history.com/#tytsxai/PromptPanel&Date)
