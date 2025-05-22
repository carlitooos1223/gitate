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

-------------------------------------------------------------------------------------------------------------

check_exposed_commits() {
    echo "Escaneando historial de commits en busca de credenciales..."

    # Lista de patrones comunes de credenciales
    patterns=("password" "token" "secret" "apikey" "key" "access_key" "private_key")

    # Buscar en el historial de commits
    for pattern in "${patterns[@]}"; do
        git log -p | grep -i --color "$pattern" >> creds_in_commits.txt
    done

    # Mostrar resultados
    if [[ -s creds_in_commits.txt ]]; then
        echo "Se encontraron credenciales expuestas en commits anteriores:"
        cat creds_in_commits.txt
    else
        echo "No se detectaron credenciales en el historial de commits."
    fi
}

# Ejecutar la función si el usuario ejecuta `gitple security --commits`
check_exposed_commits

-------------------------------------------------------------------------------------------------------------

undo() {
    echo "Deshaciendo el último commit..."
    git reset --soft HEAD~1
    echo "Listo, el último commit ha sido eliminado pero los cambios siguen disponibles."
}

# Ejecutar la función si el usuario escribe `gitple undo`
undo

-------------------------------------------------------------------------------------------------------------

get_ai_prompt() {
    API_KEY="MI_API_KEY"
    PROMPT="Escribe un mensaje de commit para el siguiente cambio: Se actualizó el README para quitar un enlace"
    
    RESPUESTA=$(curl -s https://api.openai.com/v1/chat/completions \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $API_KEY" \
      -d '{
        "model": "gpt-4",
        "messages": [{"role": "user", "content": "'"$PROMPT"'"}],
        "temperature": 0.7
      }')
    
    echo "$RESPUESTA" | jq -r '.choices[0].message.content'
}

# Ejecutar la función si el usuario escribe `gitple commit`
get_ai_prompt
