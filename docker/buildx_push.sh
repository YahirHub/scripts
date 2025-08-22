#!/bin/bash

# ==============================================================================
# Script para construir y subir imágenes Docker multi-arquitectura (amd64, arm64).
#
# VERSIÓN MODIFICADA: Este script no gestiona el inicio de sesión.
# PRE-REQUISITO: Debes haber ejecutado 'docker login' exitosamente
# antes de lanzar este script.
#
# ==============================================================================

# --- Configuración de colores para los mensajes ---
COLOR_GREEN="\033[0;32m"
COLOR_YELLOW="\033[0;33m"
COLOR_RED="\033[0;31m"
COLOR_RESET="\033[0m"

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

# --- 1. Verificación de dependencias y estado de login ---
pre_run_check() {
    info "Verificando que 'docker' y 'docker buildx' estén instalados..."
    if ! command -v docker &> /dev/null; then
        error "Docker no está instalado. Por favor, instálalo antes de continuar."
    fi
    if ! docker buildx version &> /dev/null; then
        error "Docker buildx no está disponible. Asegúrate de que tu versión de Docker es compatible."
    fi
    info "Dependencias encontradas."
    
    # Aviso importante para el usuario
    warn "Este script asume que ya has iniciado sesión. Si falla por un error de autorización, ejecuta 'docker login' primero."
}

# --- 2. Solicitar datos de la imagen ---
get_image_details() {
    read -p "Introduce el nombre completo de la imagen (ej: pepito/mi-imagen): " IMAGE_NAME
    if [ -z "$IMAGE_NAME" ]; then
        error "El nombre de la imagen no puede estar vacío."
    fi

    read -p "Introduce las etiquetas (tags) separadas por espacios (ej: 1.0 latest): " TAGS_INPUT
    if [ -z "$TAGS_INPUT" ]; then
        warn "No se especificaron etiquetas. Se usará 'latest' por defecto."
        TAGS_INPUT="latest"
    fi
}

# --- 3. Crear y configurar el builder multi-arquitectura ---
setup_builder() {
    local BUILDER_NAME="multiarch_builder"
    info "Configurando el builder multi-arquitectura..."

    if docker buildx ls | grep -q "$BUILDER_NAME.*running"; then
        info "El builder '$BUILDER_NAME' ya existe y está en ejecución."
        docker buildx use "$BUILDER_NAME"
    else
        info "Creando un nuevo builder llamado '$BUILDER_NAME'..."
        if docker buildx ls | grep -q "$BUILDER_NAME"; then
            docker buildx rm "$BUILDER_NAME"
        fi
        
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
    info "Iniciando la construcción y subida de la imagen: '$IMAGE_NAME'..."
    
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
        error "La construcción o subida de la imagen falló. ¿Has iniciado sesión con 'docker login'?"
    fi
    info "¡Imagen construida y subida con éxito!"
}

# --- 5. Verificar la imagen en Docker Hub ---
verify_image() {
    info "Verificando la imagen subida en Docker Hub..."
    local first_tag=$(echo "$TAGS_INPUT" | cut -d' ' -f1)
    
    # Pequeña pausa para dar tiempo a la API de Docker Hub a actualizarse
    sleep 3
    
    docker buildx imagetools inspect "${IMAGE_NAME}:${first_tag}"
    if [ $? -ne 0 ]; then
        warn "No se pudo verificar la imagen automáticamente. Por favor, revísala manualmente en tu repositorio de Docker Hub."
    else
        info "Verificación completada. La imagen multi-arquitectura está disponible."
    fi
}

# --- Función principal ---
main() {
    pre_run_check
    get_image_details
    setup_builder
    build_and_push_image
    verify_image
    
    info "🚀 Proceso completado."
}

# --- Ejecutar el script ---
main
