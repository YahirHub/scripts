#!/bin/bash

# ===================================================================================
# Script para construir y publicar imágenes Docker multi-arquitectura en GitHub Packages.
#
# FUNCIONALIDADES:
# - Cierra sesiones activas de otros registros (como Docker Hub).
# - Verifica e inicia sesión en GitHub Packages (ghcr.io).
# - Detecta el nombre de usuario de GitHub.
# - Solicita el nombre de la imagen y la versión.
# - Etiqueta la imagen con la versión y 'latest'.
# - Construye y publica para las arquitecturas amd64 y arm64.
# ===================================================================================

# --- Configuración de colores para los mensajes ---
COLOR_GREEN="\033[0;32m"
COLOR_YELLOW="\033[0;33m"
COLOR_RED="\033[0;31m"
COLOR_RESET="\033[0m"

# --- Variables Globales ---
GITHUB_USER=""
IMAGE_NAME=""
TAGS_INPUT=""

# --- Funciones de ayuda para mostrar mensajes ---
info() {
    echo -e "${COLOR_GREEN}[INFO]${COLOR_RESET} $1"
}

warn() {
    echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $1"
}

error() {
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $1" >&2
    exit 1
}

# --- NUEVA FUNCIÓN: Limpiar sesiones de Docker existentes ---
clean_existing_sessions() {
    info "Buscando otras sesiones de Docker activas..."
    if [ ! -f ~/.docker/config.json ]; then
        info "No se encontró el archivo de configuración de Docker. No hay sesiones que limpiar."
        return
    fi

    # Extraer los hosts de los que se ha iniciado sesión, excluyendo ghcr.io
    local LOGGED_IN_HOSTS=$(cat ~/.docker/config.json | grep -o '"[^"]*": {' | grep -v "ghcr.io" | awk -F'"' '{print $2}')

    # Si no hay otros hosts, no hacer nada
    if [ -z "$LOGGED_IN_HOSTS" ]; then
        info "No se encontraron otras sesiones activas."
        return
    fi

    # Renombrar docker.io para mayor claridad
    local DISPLAY_HOSTS=$(echo "$LOGGED_IN_HOSTS" | sed 's|https://index.docker.io/v1/|Docker Hub (docker.io)|')

    warn "Se han detectado las siguientes sesiones activas:"
    echo -e "${COLOR_YELLOW}$DISPLAY_HOSTS${COLOR_RESET}"
    read -p "¿Deseas cerrar estas sesiones antes de continuar? [s/N]: " CONFIRM_LOGOUT

    if [[ "$CONFIRM_LOGOUT" =~ ^[Ss]$ ]]; then
        info "Cerrando sesiones..."
        local HOSTS_TO_LOGOUT=$(echo "$DISPLAY_HOSTS" | sed 's|Docker Hub (docker.io)|docker.io|')

        for host in $HOSTS_TO_LOGOUT; do
            if docker logout "$host"; then
                info "Sesión cerrada en '$host'."
            else
                warn "No se pudo cerrar la sesión en '$host'. Puede que ya estuviera inválida."
            fi
        done
        info "Limpieza de sesiones completada."
    else
        info "Se mantendrán las sesiones existentes."
    fi
}


# --- 1. Verificación de dependencias e inicio de sesión ---
pre_run_checks_and_login() {
    info "Verificando que 'docker' y 'docker buildx' estén instalados..."
    if ! command -v docker &> /dev/null; then
        error "Docker no está instalado. Por favor, instálalo antes de continuar."
    fi
    if ! docker buildx version &> /dev/null; then
        error "Docker buildx no está disponible. Asegúrate de que tu versión de Docker es compatible."
    fi
    info "Dependencias encontradas."

    # --- PASO DE LIMPIEZA ---
    clean_existing_sessions

    # Verificar si el usuario ya ha iniciado sesión en ghcr.io
    if [ -f ~/.docker/config.json ] && grep -q "ghcr.io" ~/.docker/config.json; then
        info "Se ha detectado una sesión existente para ghcr.io."
        DETECTED_USER=$(grep "ghcr.io" -A2 ~/.docker/config.json | grep '"auth":' | cut -d'"' -f4 | base64 -d 2>/dev/null | cut -d':' -f1)
        if [ -n "$DETECTED_USER" ]; then
             read -p "Hemos detectado el usuario '${DETECTED_USER}'. ¿Es correcto? [S/n]: " CONFIRM_USER
             if [[ "$CONFIRM_USER" =~ ^[Ss]$ || -z "$CONFIRM_USER" ]]; then
                GITHUB_USER=$DETECTED_USER
             fi
        fi
    fi

    # Si no se pudo confirmar la sesión, realizar login
    if [ -z "$GITHUB_USER" ]; then
        read -p "Introduce tu nombre de usuario de GitHub: " GITHUB_USER
        if [ -z "$GITHUB_USER" ]; then
            error "El nombre de usuario no puede estar vacío."
        fi

        warn "Para continuar, necesitas iniciar sesión en GitHub Packages."
        info "Por favor, proporciona un Personal Access Token (PAT) con permisos 'write:packages'."
        read -sp "Introduce tu Personal Access Token (PAT): " GITHUB_PAT
        echo ""

        if [ -z "$GITHUB_PAT" ]; then
            error "El Personal Access Token no puede estar vacío."
        fi

        echo "$GITHUB_PAT" | docker login ghcr.io -u "$GITHUB_USER" --password-stdin
        if [ $? -ne 0 ]; then
            error "El inicio de sesión falló. Verifica tu usuario y PAT."
        fi
        info "Inicio de sesión en ghcr.io exitoso."
    fi
}

# --- 2. Solicitar datos de la imagen ---
get_image_details() {
    info "Usando el usuario de GitHub: ${GITHUB_USER}"

    read -p "Introduce el nombre de la imagen/repositorio (ej: mi-aplicacion): " IMAGE_REPO_NAME
    if [ -z "$IMAGE_REPO_NAME" ]; then
        error "El nombre de la imagen no puede estar vacío."
    fi

    read -p "Introduce la versión de la imagen (ej: 1.0.0): " IMAGE_VERSION
    if [ -z "$IMAGE_VERSION" ]; then
        error "La versión no puede estar vacía."
    fi

    IMAGE_NAME="ghcr.io/${GITHUB_USER}/${IMAGE_REPO_NAME}"
    TAGS_INPUT="${IMAGE_VERSION} latest"

    info "La imagen se publicará como: ${IMAGE_NAME}"
    info "Con las etiquetas: ${IMAGE_VERSION} y latest"
}

# --- 3. Crear y configurar el builder multi-arquitectura ---
setup_builder() {
    local BUILDER_NAME="multiarch_builder"
    info "Configurando el builder multi-arquitectura..."
    if ! docker buildx use "$BUILDER_NAME"; then
        info "Creando un nuevo builder llamado '$BUILDER_NAME'..."
        docker buildx create --name "$BUILDER_NAME" --use
        if [ $? -ne 0 ]; then
            error "No se pudo crear el builder multi-arquitectura."
        fi
    fi
    info "Inspeccionando y preparando el builder..."
    docker buildx inspect --bootstrap
    if [ $? -ne 0 ]; then
        error "El builder no pudo iniciarse correctamente."
    fi
    info "Builder listo."
}

# --- 4. Construir y subir la imagen ---
build_and_push_image() {
    info "Iniciando la construcción y subida de la imagen: '${IMAGE_NAME}'..."
    local BUILD_TAGS=()
    for tag in $TAGS_INPUT; do
        BUILD_TAGS+=("-t" "${IMAGE_NAME}:${tag}")
    done

    info "Plataformas a construir: linux/amd64, linux/arm64"
    info "Etiquetas a aplicar: ${TAGS_INPUT}"

    docker buildx build \
      --platform linux/amd64,linux/arm64 \
      "${BUILD_TAGS[@]}" \
      --push .

    if [ $? -ne 0 ]; then
        error "La construcción o subida de la imagen falló. Revisa los permisos de tu PAT."
    fi
    info "¡Imagen construida y publicada con éxito!"
}

# --- 5. Verificar la imagen en GitHub Packages ---
verify_image() {
    info "Verificando la imagen publicada en GitHub Packages..."
    local first_tag=$(echo "$TAGS_INPUT" | cut -d' ' -f1)
    sleep 3

    if ! docker buildx imagetools inspect "${IMAGE_NAME}:${first_tag}"; then
        warn "No se pudo verificar la imagen automáticamente. Por favor, revísala manualmente."
    else
        info "Verificación completada. La imagen multi-arquitectura está disponible."
    fi
}

# --- Función principal ---
main() {
    pre_run_checks_and_login
    get_image_details
    setup_builder
    build_and_push_image
    verify_image
    info "🚀 Proceso completado."
}

# --- Ejecutar el script ---
main
