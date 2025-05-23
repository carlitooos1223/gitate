#!/bin/bash

security() {
    echo "Ejecutando análisis de seguridad en el repositorio..."

    # Verificar credenciales expuestas
    check_exposed_credentials

    # Verificar archivos con permisos inseguros (ejemplo: .env con permisos abiertos)
    echo "Revisando permisos de archivos sensibles..."
    find . -type f \( -name "*.env" -o -name "*.config" -o -name "*.json" \) -exec ls -l {} \; | awk '$1 ~ /^-rw-rw-rw/ {print "Archivo inseguro:", $9}'

    # Escaneo de dependencias (ejemplo con npm)
    if [ -f "package.json" ]; then
        echo "Revisando dependencias..."
        npm outdated
    fi

    echo "Análisis de seguridad completado."
}

# Llamada a la función si el usuario ejecuta `gitple security`
security
