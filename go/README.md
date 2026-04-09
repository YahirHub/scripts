# install_go.sh

Instalador de Go orientado a **contenedores Docker con agentes de IA**. Descarga Go directamente desde `go.dev`, verifica la integridad del tarball, instala las herramientas del ecosistema, configura todas las variables de entorno y crea enlaces simbólicos, dejando el entorno listo para compilar y ejecutar código Go sin configuración adicional.

---

## Características

- Detecta y descarga automáticamente la **última versión estable** de Go (o la que se especifique)
- **Verifica el checksum SHA-256** del tarball antes de instalar
- Soporta múltiples gestores de paquetes: `apt`, `apk` (Alpine), `yum`, `dnf`
- Detecta la arquitectura del sistema: `amd64`, `arm64`, `armv6l`, `386`, `s390x`, `ppc64le`
- Instala las **herramientas esenciales del ecosistema** Go (gopls, dlv, linters, etc.)
- Pre-calienta el **cache de módulos** con las dependencias más comunes
- Escribe un perfil persistente en `/etc/profile.d/golang.sh` y actualiza `/etc/environment`
- Crea **enlaces simbólicos** de todos los binarios en el directorio elegido
- Salida con colores y etiquetas claras (`[OK]`, `[INFO]`, `[WARN]`, `[ERROR]`)

---

## Requisitos

- Ejecutar como **root** (o con `sudo`)
- `curl` o `wget` disponible en la imagen base
- Acceso a internet durante el build

---

## Uso rápido

```bash
# Dar permisos de ejecución
chmod +x install_go.sh

# Instalar la última versión estable
./install_go.sh

# Instalar una versión específica
./install_go.sh -v 1.22.5

# Versión específica con links en /usr/sbin
./install_go.sh -v 1.22.5 -b /usr/sbin

# Directorio de instalación personalizado
./install_go.sh -v 1.23.0 -d /opt/go

# Ver ayuda
./install_go.sh --help
```

---

## Opciones

| Flag | Alias | Descripción | Default |
|------|-------|-------------|---------|
| `-v` | `--version` | Versión de Go a instalar (ej: `1.22.5`) | Última estable |
| `-d` | `--dir` | Directorio donde se instala Go (`GOROOT`) | `/usr/local/go` |
| `-b` | `--bindir` | Directorio para los enlaces simbólicos | `/usr/local/bin` |
| `-h` | `--help` | Muestra la ayuda | — |

---

## Variables de entorno

Se pueden sobreescribir antes de ejecutar el script:

| Variable | Default | Descripción |
|----------|---------|-------------|
| `GO_INSTALL_DIR` | `/usr/local/go` | Raíz de instalación de Go (`GOROOT`) |
| `GOPATH` | `/root/go` | Workspace de Go |
| `GOCACHE` | `/root/.cache/go-build` | Cache de compilación |
| `GOMODCACHE` | `/root/go/pkg/mod` | Cache de módulos descargados |
| `GOTMPDIR` | `/tmp/go-tmp` | Directorio temporal de Go |

**Ejemplo:**

```bash
GOPATH=/opt/gopath GOCACHE=/tmp/gocache ./install_go.sh -v 1.22.5
```

---

## Variables de entorno configuradas

El script escribe `/etc/profile.d/golang.sh` con el siguiente contenido:

```bash
export GOROOT="/usr/local/go"
export GOPATH="/root/go"
export GOCACHE="/root/.cache/go-build"
export GOMODCACHE="/root/go/pkg/mod"
export GOTMPDIR="/tmp/go-tmp"
export GOFLAGS="-mod=mod"
export GONOSUMCHECK="*"
export GOTELEMETRY="off"
export CGO_ENABLED=1
export PATH="${GOROOT}/bin:${GOPATH}/bin:${PATH}"
```

> `GOTELEMETRY=off` deshabilita la telemetría de Go, recomendado para entornos de contenedores.  
> `CGO_ENABLED=1` habilita la compilación con C, necesario para varios módulos de producción.

Para aplicar en la sesión actual sin reiniciar:

```bash
source /etc/profile.d/golang.sh
```

---

## Herramientas instaladas

| Herramienta | Paquete | Descripción |
|-------------|---------|-------------|
| `gopls` | `golang.org/x/tools/gopls` | Language Server (LSP) — esencial para el agente IA |
| `goimports` | `golang.org/x/tools/cmd/goimports` | Formateo + gestión automática de imports |
| `gofmt` | *(incluido en Go)* | Formateador oficial de código Go |
| `staticcheck` | `honnef.co/go/tools/cmd/staticcheck` | Analizador estático avanzado |
| `golangci-lint` | `github.com/golangci/golangci-lint` | Meta-linter todo-en-uno |
| `dlv` | `github.com/go-delve/delve/cmd/dlv` | Debugger Delve |
| `godoc` | `golang.org/x/tools/cmd/godoc` | Servidor de documentación local |
| `gotest` | `github.com/rakyll/gotest` | Runner de tests con salida en color |
| `air` | `github.com/air-verse/air` | Live reload para desarrollo |
| `govulncheck` | `golang.org/x/vuln/cmd/govulncheck` | Auditoría de vulnerabilidades en dependencias |

Todos los binarios instalados en `$GOPATH/bin` reciben un enlace simbólico en el directorio configurado con `-b` (por defecto `/usr/local/bin`), por lo que están disponibles directamente en el `PATH`.

---

## Módulos pre-cacheados

Para acelerar la primera compilación en el contenedor, el script pre-descarga los módulos más comunes:

- `golang.org/x/sys`
- `golang.org/x/net`
- `golang.org/x/sync`
- `golang.org/x/text`
- `golang.org/x/crypto`
- `github.com/pkg/errors`

---

## Uso en Dockerfile

### Imagen Debian/Ubuntu

```dockerfile
FROM debian:bookworm-slim

COPY install_go.sh /tmp/install_go.sh
RUN chmod +x /tmp/install_go.sh && /tmp/install_go.sh -v 1.22.5

# Cargar variables para capas posteriores
ENV PATH="/usr/local/go/bin:/root/go/bin:${PATH}" \
    GOROOT="/usr/local/go" \
    GOPATH="/root/go" \
    GOCACHE="/root/.cache/go-build" \
    CGO_ENABLED=1

WORKDIR /app
```

### Imagen Alpine

```dockerfile
FROM alpine:3.19

# Alpine necesita bash para el script
RUN apk add --no-cache bash

COPY install_go.sh /tmp/install_go.sh
RUN chmod +x /tmp/install_go.sh && /tmp/install_go.sh -v 1.22.5

ENV PATH="/usr/local/go/bin:/root/go/bin:${PATH}" \
    GOROOT="/usr/local/go" \
    GOPATH="/root/go" \
    GOCACHE="/root/.cache/go-build"

WORKDIR /app
```

### Siempre la última versión

```dockerfile
RUN chmod +x /tmp/install_go.sh && /tmp/install_go.sh
```

---

## Estructura de directorios creada

```
/usr/local/go/          ← GOROOT (binarios de Go)
│   └── bin/
│       ├── go          ← enlace simbólico en /usr/local/bin/go
│       └── gofmt       ← enlace simbólico en /usr/local/bin/gofmt

/root/go/               ← GOPATH
│   ├── bin/            ← herramientas instaladas (gopls, dlv, air…)
│   ├── src/
│   └── pkg/
│       └── mod/        ← GOMODCACHE

/root/.cache/go-build/  ← GOCACHE
/tmp/go-tmp/            ← GOTMPDIR
/etc/profile.d/golang.sh ← variables de entorno persistentes
```

---

## Solución de problemas

**El script falla con "Arquitectura no soportada"**
Verifica con `uname -m`. Las arquitecturas soportadas son: `x86_64`, `aarch64`, `arm64`, `armv6l`, `armv7l`, `i386`, `i686`, `s390x`, `ppc64le`.

**No se puede obtener la última versión**
El script necesita acceso a `https://go.dev`. Verifica la conectividad del contenedor durante el build.

**Checksum inválido**
Puede ocurrir si el tarball se descargó de forma incompleta. Vuelve a ejecutar el script; el directorio temporal se limpia automáticamente al salir.

**Las variables de entorno no están disponibles en la sesión**
Ejecuta `source /etc/profile.d/golang.sh` o reinicia la shell. En Dockerfile, declara las variables con `ENV` después de ejecutar el script.

**Una herramienta del ecosistema no se instaló**
El script continúa si alguna herramienta falla (muestra `[WARN]`). Puedes instalarla manualmente con:
```bash
source /etc/profile.d/golang.sh
go install <paquete>@latest
```

---

## Licencia

MIT — úsalo, modifícalo y distribúyelo libremente.
