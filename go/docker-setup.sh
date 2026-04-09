#!/usr/bin/env bash
# =============================================================================
# install_go.sh — Instalador de Go para contenedores Docker (agente IA)
# =============================================================================
# Uso:
#   ./install_go.sh                     # Instala la última versión de Go
#   ./install_go.sh -v 1.22.5           # Instala una versión específica
#   ./install_go.sh --version 1.21.0    # Versión larga
#   ./install_go.sh --help              # Muestra ayuda
#
# Opciones de entorno:
#   GO_INSTALL_DIR   Directorio de instalación  (default: /usr/local/go)
#   GOPATH           GOPATH personalizado        (default: /root/go)
#   GOCACHE          Cache de compilación        (default: /root/.cache/go-build)
#   GOMODCACHE       Cache de módulos            (default: /root/go/pkg/mod)
# =============================================================================

set -euo pipefail

# ─── Colores ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

log()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
ok()     { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()   { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()  { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
die()    { error "$*"; exit 1; }
title()  { echo -e "\n${BOLD}${CYAN}══ $* ══${RESET}"; }

# ─── Valores por defecto ───────────────────────────────────────────────────────
GO_VERSION=""
GO_INSTALL_DIR="${GO_INSTALL_DIR:-/usr/local/go}"
GOPATH="${GOPATH:-/root/go}"
GOCACHE="${GOCACHE:-/root/.cache/go-build}"
GOMODCACHE="${GOMODCACHE:-${GOPATH}/pkg/mod}"
GOTMPDIR="${GOTMPDIR:-/tmp/go-tmp}"
PROFILE_FILE="/etc/profile.d/golang.sh"
BIN_LINK_DIR="/usr/local/bin"   # cambia a /usr/sbin si lo prefieres

ARCH="$(uname -m)"
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"

# ─── Mapeo de arquitectura a nombre Go ────────────────────────────────────────
case "${ARCH}" in
  x86_64)            GO_ARCH="amd64" ;;
  aarch64|arm64)     GO_ARCH="arm64" ;;
  armv6l|armv7l)     GO_ARCH="armv6l" ;;
  i386|i686)         GO_ARCH="386" ;;
  s390x)             GO_ARCH="s390x" ;;
  ppc64le)           GO_ARCH="ppc64le" ;;
  *) die "Arquitectura no soportada: ${ARCH}" ;;
esac

# ─── Ayuda ────────────────────────────────────────────────────────────────────
usage() {
  cat <<EOF

${BOLD}install_go.sh${RESET} — Instalador de Go para contenedores Docker

${BOLD}USO:${RESET}
  $0 [opciones]

${BOLD}OPCIONES:${RESET}
  -v, --version <ver>   Versión de Go a instalar (ej: 1.22.5). Default: última estable.
  -d, --dir     <dir>   Directorio de instalación. Default: /usr/local/go
  -b, --bindir  <dir>   Directorio para enlaces simbólicos. Default: /usr/local/bin
  -h, --help            Muestra esta ayuda.

${BOLD}VARIABLES DE ENTORNO:${RESET}
  GO_INSTALL_DIR, GOPATH, GOCACHE, GOMODCACHE, GOTMPDIR

${BOLD}EJEMPLOS:${RESET}
  $0                        # Última versión
  $0 -v 1.22.5              # Versión específica
  $0 -v 1.21.0 -b /usr/sbin # Links en /usr/sbin

EOF
  exit 0
}

# ─── Parseo de argumentos ─────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--version)  GO_VERSION="$2"; shift 2 ;;
    -d|--dir)      GO_INSTALL_DIR="$2"; shift 2 ;;
    -b|--bindir)   BIN_LINK_DIR="$2"; shift 2 ;;
    -h|--help)     usage ;;
    *) die "Argumento desconocido: $1. Usa --help para ver la ayuda." ;;
  esac
done

# ─── Verificar root ───────────────────────────────────────────────────────────
[[ "${EUID}" -eq 0 ]] || die "Este script debe ejecutarse como root."

# ─── Obtener última versión si no se especificó ───────────────────────────────
fetch_latest_version() {
  log "Consultando la última versión estable de Go..."
  local ver=""

  # Intentar con curl
  if command -v curl &>/dev/null; then
    ver=$(curl -fsSL "https://go.dev/VERSION?m=text" 2>/dev/null | head -1 | sed 's/^go//')
  fi

  # Fallback con wget
  if [[ -z "${ver}" ]] && command -v wget &>/dev/null; then
    ver=$(wget -qO- "https://go.dev/VERSION?m=text" 2>/dev/null | head -1 | sed 's/^go//')
  fi

  [[ -n "${ver}" ]] || die "No se pudo obtener la última versión de Go. ¿Hay conexión a internet?"
  echo "${ver}"
}

if [[ -z "${GO_VERSION}" ]]; then
  GO_VERSION="$(fetch_latest_version)"
fi

ok "Versión objetivo: ${BOLD}go${GO_VERSION}${RESET}"

# ─── Variables derivadas ──────────────────────────────────────────────────────
GO_TARBALL="go${GO_VERSION}.${OS}-${GO_ARCH}.tar.gz"
GO_DOWNLOAD_URL="https://go.dev/dl/${GO_TARBALL}"
GO_CHECKSUM_URL="${GO_DOWNLOAD_URL}.sha256"
TMP_DIR="$(mktemp -d /tmp/go-install-XXXXXX)"
trap 'rm -rf "${TMP_DIR}"' EXIT

# ─── Instalar dependencias del sistema ────────────────────────────────────────
title "Dependencias del sistema"

install_system_deps() {
  local pkgs=(
    curl wget ca-certificates git
    gcc g++ make
    libc6-dev
    bash
  )

  if command -v apt-get &>/dev/null; then
    log "Actualizando listas de paquetes (apt)..."
    apt-get update -qq
    log "Instalando paquetes: ${pkgs[*]}"
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${pkgs[@]}" 2>/dev/null || \
      warn "Algunos paquetes no se instalaron (puede que ya estén presentes)."
    apt-get clean && rm -rf /var/lib/apt/lists/*

  elif command -v apk &>/dev/null; then
    log "Instalando paquetes (apk / Alpine)..."
    apk add --no-cache curl wget git gcc g++ make libc-dev bash ca-certificates

  elif command -v yum &>/dev/null; then
    log "Instalando paquetes (yum)..."
    yum install -y curl wget git gcc gcc-c++ make glibc-devel

  elif command -v dnf &>/dev/null; then
    log "Instalando paquetes (dnf)..."
    dnf install -y curl wget git gcc gcc-c++ make glibc-devel

  else
    warn "Gestor de paquetes no reconocido. Instala manualmente: gcc, git, curl, make."
  fi
  ok "Dependencias del sistema listas."
}

install_system_deps

# ─── Descargar Go ─────────────────────────────────────────────────────────────
title "Descarga de Go ${GO_VERSION}"

TARBALL_PATH="${TMP_DIR}/${GO_TARBALL}"

log "URL: ${GO_DOWNLOAD_URL}"
log "Descargando tarball..."

if command -v curl &>/dev/null; then
  curl -fsSL --progress-bar "${GO_DOWNLOAD_URL}" -o "${TARBALL_PATH}"
elif command -v wget &>/dev/null; then
  wget -q --show-progress "${GO_DOWNLOAD_URL}" -O "${TARBALL_PATH}"
else
  die "Se necesita curl o wget para descargar Go."
fi

ok "Descarga completa: ${TARBALL_PATH}"

# ─── Verificar checksum ───────────────────────────────────────────────────────
title "Verificación de integridad (sha256)"

EXPECTED_SHA=""
if command -v curl &>/dev/null; then
  EXPECTED_SHA="$(curl -fsSL "${GO_CHECKSUM_URL}" 2>/dev/null || true)"
elif command -v wget &>/dev/null; then
  EXPECTED_SHA="$(wget -qO- "${GO_CHECKSUM_URL}" 2>/dev/null || true)"
fi

if [[ -n "${EXPECTED_SHA}" ]]; then
  if command -v sha256sum &>/dev/null; then
    ACTUAL_SHA="$(sha256sum "${TARBALL_PATH}" | awk '{print $1}')"
  elif command -v shasum &>/dev/null; then
    ACTUAL_SHA="$(shasum -a 256 "${TARBALL_PATH}" | awk '{print $1}')"
  else
    warn "No se encontró sha256sum ni shasum. Omitiendo verificación."
    ACTUAL_SHA="${EXPECTED_SHA}"
  fi

  if [[ "${ACTUAL_SHA}" == "${EXPECTED_SHA}" ]]; then
    ok "Checksum verificado: ${ACTUAL_SHA:0:16}..."
  else
    die "¡Checksum inválido!\n  Esperado: ${EXPECTED_SHA}\n  Actual:   ${ACTUAL_SHA}"
  fi
else
  warn "No se pudo obtener el checksum oficial. Continuando sin verificación."
fi

# ─── Instalar Go ──────────────────────────────────────────────────────────────
title "Instalación"

if [[ -d "${GO_INSTALL_DIR}" ]]; then
  warn "Existe instalación previa en ${GO_INSTALL_DIR}. Eliminando..."
  rm -rf "${GO_INSTALL_DIR}"
fi

log "Extrayendo en /usr/local ..."
tar -C /usr/local -xzf "${TARBALL_PATH}"

# Mover si el directorio extraído no coincide con GO_INSTALL_DIR
if [[ "${GO_INSTALL_DIR}" != "/usr/local/go" ]]; then
  mv /usr/local/go "${GO_INSTALL_DIR}"
fi

ok "Go instalado en: ${GO_INSTALL_DIR}"

# ─── Crear directorios de trabajo de Go ───────────────────────────────────────
title "Directorios de trabajo"

for dir in "${GOPATH}" "${GOPATH}/bin" "${GOPATH}/src" "${GOPATH}/pkg" \
           "${GOCACHE}" "${GOMODCACHE}" "${GOTMPDIR}"; do
  mkdir -p "${dir}"
  ok "Directorio: ${dir}"
done

# ─── Variables de entorno persistentes ───────────────────────────────────────
title "Variables de entorno"

log "Escribiendo ${PROFILE_FILE} ..."
cat > "${PROFILE_FILE}" <<ENVEOF
# ─── Go — generado por install_go.sh ───────────────────────────────────────
export GOROOT="${GO_INSTALL_DIR}"
export GOPATH="${GOPATH}"
export GOCACHE="${GOCACHE}"
export GOMODCACHE="${GOMODCACHE}"
export GOTMPDIR="${GOTMPDIR}"
export GOFLAGS="-mod=mod"
export GONOSUMCHECK="*"
export GOTELEMETRY="off"
export CGO_ENABLED=1

# PATH
export PATH="\${GOROOT}/bin:\${GOPATH}/bin:\${PATH}"
ENVEOF

chmod 644 "${PROFILE_FILE}"
ok "Perfil escrito: ${PROFILE_FILE}"

# También exportar para la sesión actual
export GOROOT="${GO_INSTALL_DIR}"
export GOPATH="${GOPATH}"
export GOCACHE="${GOCACHE}"
export GOMODCACHE="${GOMODCACHE}"
export GOTMPDIR="${GOTMPDIR}"
export PATH="${GO_INSTALL_DIR}/bin:${GOPATH}/bin:${PATH}"

# Para bash interactivo / .bashrc
if [[ -f /root/.bashrc ]]; then
  if ! grep -q "golang.sh" /root/.bashrc 2>/dev/null; then
    echo 'source /etc/profile.d/golang.sh' >> /root/.bashrc
    ok ".bashrc actualizado."
  fi
fi

# Para shells que leen /etc/environment
if [[ -f /etc/environment ]]; then
  for var in GOROOT GOPATH GOCACHE GOMODCACHE GOTMPDIR; do
    val="${!var}"
    sed -i "/^${var}=/d" /etc/environment 2>/dev/null || true
    echo "${var}=${val}" >> /etc/environment
  done
fi

# ─── Enlaces simbólicos de binarios Go ───────────────────────────────────────
title "Enlaces simbólicos → ${BIN_LINK_DIR}"

mkdir -p "${BIN_LINK_DIR}"

GO_BINARIES=(go gofmt)

for bin in "${GO_BINARIES[@]}"; do
  src="${GO_INSTALL_DIR}/bin/${bin}"
  dst="${BIN_LINK_DIR}/${bin}"
  if [[ -f "${src}" ]]; then
    ln -sf "${src}" "${dst}"
    ok "Enlace: ${dst} → ${src}"
  else
    warn "Binario no encontrado, omitiendo: ${src}"
  fi
done

# ─── Herramientas esenciales del ecosistema Go ───────────────────────────────
title "Herramientas del ecosistema Go"

GO_BIN="${GO_INSTALL_DIR}/bin/go"

install_go_tool() {
  local pkg="$1"
  local name="$2"
  log "Instalando ${name} (${pkg})..."
  if "${GO_BIN}" install "${pkg}" 2>/dev/null; then
    ok "${name} instalado."
    # Enlace simbólico si el binario existe en GOPATH/bin
    local tool_bin="${GOPATH}/bin/${name}"
    if [[ -f "${tool_bin}" ]]; then
      ln -sf "${tool_bin}" "${BIN_LINK_DIR}/${name}"
      ok "Enlace: ${BIN_LINK_DIR}/${name}"
    fi
  else
    warn "No se pudo instalar ${name}. Continuando..."
  fi
}

# gopls — Language Server (fundamental para agente IA)
install_go_tool "golang.org/x/tools/gopls@latest"        "gopls"

# staticcheck — analizador estático
install_go_tool "honnef.co/go/tools/cmd/staticcheck@latest" "staticcheck"

# goimports — formateo + imports automáticos
install_go_tool "golang.org/x/tools/cmd/goimports@latest" "goimports"

# godoc — documentación local
install_go_tool "golang.org/x/tools/cmd/godoc@latest"     "godoc"

# dlv — debugger Delve
install_go_tool "github.com/go-delve/delve/cmd/dlv@latest" "dlv"

# golangci-lint — linter todo-en-uno
install_go_tool "github.com/golangci/golangci-lint/cmd/golangci-lint@latest" "golangci-lint"

# gotest — runner de tests con color
install_go_tool "github.com/rakyll/gotest@latest"          "gotest"

# air — live reload para desarrollo
install_go_tool "github.com/air-verse/air@latest"          "air"

# govulncheck — auditoría de vulnerabilidades
install_go_tool "golang.org/x/vuln/cmd/govulncheck@latest" "govulncheck"

# ─── Módulos estándar importantes (pre-descarga del cache) ───────────────────
title "Pre-calentamiento de módulos comunes"

WARMUP_PKGS=(
  "golang.org/x/sys"
  "golang.org/x/net"
  "golang.org/x/sync"
  "golang.org/x/text"
  "golang.org/x/crypto"
  "github.com/pkg/errors"
)

WARMUP_DIR="${TMP_DIR}/warmup"
mkdir -p "${WARMUP_DIR}"

(
  cd "${WARMUP_DIR}"
  "${GO_BIN}" mod init warmup 2>/dev/null || true
  for pkg in "${WARMUP_PKGS[@]}"; do
    log "Pre-descargando: ${pkg}..."
    "${GO_BIN}" get "${pkg}@latest" 2>/dev/null || warn "No se pudo pre-descargar ${pkg}."
  done
) || warn "Pre-calentamiento parcial. No crítico."

ok "Cache de módulos pre-calentado."

# ─── Permisos de los directorios Go ──────────────────────────────────────────
title "Ajuste de permisos"

chmod -R 755 "${GO_INSTALL_DIR}"
chmod -R 755 "${GOPATH}"
chmod -R 755 "${GOCACHE}" 2>/dev/null || true
ok "Permisos configurados."

# ─── Verificación final ───────────────────────────────────────────────────────
title "Verificación"

INSTALLED_VERSION="$("${GO_BIN}" version 2>/dev/null || echo 'ERROR')"
log "Versión instalada: ${INSTALLED_VERSION}"

if echo "${INSTALLED_VERSION}" | grep -q "go${GO_VERSION}"; then
  ok "Instalación verificada correctamente."
else
  warn "La versión instalada no coincide exactamente. Verifica manualmente."
fi

# Verificar binarios clave
for bin in go gofmt gopls goimports; do
  if command -v "${bin}" &>/dev/null || [[ -f "${BIN_LINK_DIR}/${bin}" ]]; then
    ok "Disponible: ${bin}"
  else
    warn "No encontrado en PATH: ${bin}"
  fi
done

# ─── Resumen final ───────────────────────────────────────────────────────────
title "Resumen de configuración"

cat <<SUMMARY
  ${BOLD}Go version:${RESET}      ${GO_VERSION}
  ${BOLD}GOROOT:${RESET}          ${GO_INSTALL_DIR}
  ${BOLD}GOPATH:${RESET}          ${GOPATH}
  ${BOLD}GOCACHE:${RESET}         ${GOCACHE}
  ${BOLD}GOMODCACHE:${RESET}      ${GOMODCACHE}
  ${BOLD}GOTMPDIR:${RESET}        ${GOTMPDIR}
  ${BOLD}Links en:${RESET}        ${BIN_LINK_DIR}
  ${BOLD}Perfil:${RESET}          ${PROFILE_FILE}

  ${YELLOW}Para aplicar en la sesión actual:${RESET}
    source ${PROFILE_FILE}
SUMMARY

echo ""
ok "¡Instalación de Go completa! 🚀"
echo ""
