#!/bin/bash

# ====== INPUT ======
read -p "Nombre del servicio (sin .service): " SERVICE_NAME
read -p "Comando o ejecutable (ej: /usr/bin/python3 app.py): " EXEC_CMD
read -p "Working directory (opcional, ENTER para omitir): " WORKDIR
read -p "Usuario para ejecutar el servicio (opcional, ENTER para omitir): " USER_NAME

SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# ====== VALIDACIÓN BÁSICA ======
if [ -z "$SERVICE_NAME" ] || [ -z "$EXEC_CMD" ]; then
    echo "❌ Nombre del servicio y comando son obligatorios"
    exit 1
fi

# Intentar validar el ejecutable (primer palabra del comando)
BIN=$(echo "$EXEC_CMD" | awk '{print $1}')

if ! command -v "$BIN" &> /dev/null && [ ! -f "$BIN" ]; then
    echo "⚠️ Advertencia: No se encontró el ejecutable '$BIN' en PATH o como ruta directa"
fi

echo "Creando servicio en: $SERVICE_FILE"

# ====== CREAR SERVICE ======
sudo bash -c "cat > $SERVICE_FILE" <<EOF
[Unit]
Description=Servicio ${SERVICE_NAME}
After=network.target

[Service]
Type=simple
ExecStart=${EXEC_CMD}
Restart=always
RestartSec=3
EOF

# ====== OPCIONALES ======
if [ -n "$WORKDIR" ]; then
    sudo bash -c "cat >> $SERVICE_FILE" <<EOF
WorkingDirectory=${WORKDIR}
EOF
fi

if [ -n "$USER_NAME" ]; then
    sudo bash -c "cat >> $SERVICE_FILE" <<EOF
User=${USER_NAME}
EOF
fi

# ====== FINAL ======
sudo bash -c "cat >> $SERVICE_FILE" <<EOF

[Install]
WantedBy=multi-user.target
EOF

# ====== PERMISOS (opcional pero recomendado) ======
sudo chmod 644 "$SERVICE_FILE"

# ====== SYSTEMD ======
echo "Recargando systemd..."
sudo systemctl daemon-reload

echo "Habilitando servicio..."
sudo systemctl enable ${SERVICE_NAME}.service

echo "Iniciando servicio..."
sudo systemctl start ${SERVICE_NAME}.service

# ====== VERIFICACIÓN ======
echo "Verificando estado..."
sleep 2

STATUS=$(systemctl is-active ${SERVICE_NAME}.service)

if [ "$STATUS" = "active" ]; then
    echo "✅ El servicio está corriendo correctamente."
else
    echo "❌ El servicio NO está activo."
    echo "Mostrando estado:"
    systemctl status ${SERVICE_NAME}.service --no-pager
fi
