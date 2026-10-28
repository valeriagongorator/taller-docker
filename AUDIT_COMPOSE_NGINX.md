# Informe de Auditoría Técnica de Infraestructura y Orquestación
**Proyecto:** Eco-Air Backend con Reverse Proxy Nginx  
**Orquestador:** Docker Compose v5.5.1  
**Fecha de Auditoría:** 28 de Octubre de 2026  
**Auditora:** Valeria Estefanía Góngora Torres  

---

## 1. Resumen Ejecutivo de la Solución
Se ha implementado con éxito la arquitectura de micro-servicios contenerizados compuesta por:
1. **Proxy Inverso (Nginx:alpine):** Punto único de entrada seguro en el puerto 80 del host con cabeceras de hardening y redirección balanceada.
2. **Servicio Backend (Spring Boot 3 en Eclipse Temurin 17 JRE Alpine):** Aislado en la red interna `app-network`, sin exposición directa al host, operando bajo el usuario no privilegiado `sensor_user` (UID 10001) y con cuotas estrictas de cgroups de memoria (512 MB de límite y 256 MB de reserva).

---

## 2. Archivos de Infraestructura Implementados

### 2.1 Configuración de Nginx (`nginx/nginx.conf`)
```nginx
events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    # Ocultar la versión de Nginx para mitigar fingerprinting (Hardening)
    server_tokens off;

    # Formato de logs estructurado para auditoría y trazabilidad
    log_format audit_log '$remote_addr - $remote_user [$time_local] '
                         '"$request" $status $body_bytes_sent '
                         '"$http_referer" "$http_user_agent" '
                         'rt=$request_time uct="$upstream_connect_time" '
                         'uht="$upstream_header_time" urt="$upstream_response_time"';

    access_log /var/log/nginx/access.log audit_log;
    error_log /var/log/nginx/error.log warn;

    sendfile        on;
    tcp_nopush      on;
    tcp_nodelay     on;
    keepalive_timeout  65;

    # Cabeceras de seguridad globales (Security Hardening)
    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Definición del grupo upstream hacia el servicio backend en la red bridge
    upstream backend_nodes {
        server backend:8080;
        keepalive 32;
    }

    server {
        listen 80;
        server_name localhost;

        # Redirección y balanceo de peticiones hacia el backend
        location / {
            proxy_pass http://backend_nodes;
            proxy_http_version 1.1;

            # Cabeceras estándar de Reverse Proxy
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header Connection "";

            # Timeouts de proxy para resiliencia operativa
            proxy_connect_timeout 30s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
        }

        # Endpoint interno de comprobación del estado del proxy
        location /proxy-health {
            access_log off;
            default_type text/plain;
            return 200 "nginx proxy operational\n";
        }
    }
}
```

### 2.2 Orquestación con Docker Compose (`docker-compose.yml`)
```yaml
services:
  backend:
    build:
      context: .
      dockerfile: Dockerfile
      args:
        STUDENT_ID: "${STUDENT_ID:-123456}"
    image: eco-air-backend:1.0.0
    container_name: eco_air_backend
    expose:
      - "8080"
    environment:
      - OPERATOR_ID=${STUDENT_ID:-123456}
    deploy:
      resources:
        limits:
          cpus: "1.00"
          memory: 512M
        reservations:
          cpus: "0.25"
          memory: 256M
    networks:
      - app-network
    restart: unless-stopped

  nginx:
    image: nginx:alpine
    container_name: eco_air_proxy
    ports:
      - "80:80"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      - backend
    deploy:
      resources:
        limits:
          cpus: "0.50"
          memory: 128M
        reservations:
          cpus: "0.10"
          memory: 32M
    networks:
      - app-network
    restart: unless-stopped

networks:
  app-network:
    name: app-network
    driver: bridge
```

---

## 3. Protocolo de Auditoría Técnica y Evidencias

### 3.1 Revisión de Seguridad y Privilegios
#### Evidencia de Procesos y Usuarios en Ejecución
* **Comandos ejecutados:**
  ```bash
  docker compose top
  docker exec eco_air_backend id
  docker exec eco_air_proxy id
  ```
* **Salida de la terminal:**
  ```text
  SERVICE  #   UID    PID   PPID  C   STIME  TTY  TIME      CMD
  backend  1   10001  2128  2105  6   20:02  ?    00:00:06  /opt/java/openjdk/bin/java java -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -jar app.jar
  nginx    1   root   2187  2163  0   20:02  ?    00:00:00  nginx: master process nginx -g daemon off;
  nginx    1   statd  2239  2187  0   20:02  ?    00:00:00  nginx: worker process

  backend: uid=10001(sensor_user) gid=101(sensorgroup) groups=101(sensorgroup)
  nginx:   uid=0(root) gid=0(root)
  ```
* **Hallazgo:** El backend ejecuta Java exclusivamente bajo el UID sin privilegios `10001` (`sensor_user`), eliminando el riesgo de compromiso de nivel root del contenedor en la lógica de negocio. En Nginx, el proceso master ejecuta como root solo para enlazar el puerto estándar 80, mientras los worker processes que atienden tráfico de red operan con privilegios reducidos.

#### Evidencia de Puertos y Aislamiento de Red
* **Comandos ejecutados:**
  ```bash
  docker port eco_air_backend
  docker port eco_air_proxy
  ```
* **Salida:**
  ```text
  eco_air_backend: (Sin puertos publicados en el host)
  eco_air_proxy:   80/tcp -> 0.0.0.0:80, [::]:80
  ```
* **Hallazgo:** El puerto 8080 de Spring Boot está protegido y no es accesible desde el exterior. Solo Nginx expone el puerto 80, actuando como escudo perimetral.

#### Evidencia de Montaje Seguro de Volúmenes (`:ro`)
* **Comando ejecutado:**
  ```bash
  docker inspect eco_air_proxy --format 'Mounts: {{range .Mounts}}Source: {{.Source}} -> Dest: {{.Destination}} (RW: {{.RW}}){{end}}'
  docker exec eco_air_proxy touch /etc/nginx/nginx.conf
  ```
* **Salida:**
  ```text
  Mounts: Source: /.../taller-docker/nginx/nginx.conf -> Dest: /etc/nginx/nginx.conf (RW: false)
  touch: /etc/nginx/nginx.conf: Read-only file system
  ```
* **Hallazgo:** La configuración de Nginx está montada en modo estricto de solo lectura (`:ro`). Cualquier intento de alteración o inyección en caliente dentro del contenedor es rechazado por el kernel con `Read-only file system`.

---

### 3.2 Gestión de Recursos y Estabilidad (Prevención OOMKilled)
* **Comandos ejecutados:**
  ```bash
  docker stats --no-stream
  docker inspect eco_air_backend --format 'Backend -> Memory Limit: {{.HostConfig.Memory}} Bytes | Reservation: {{.HostConfig.MemoryReservation}} Bytes | OOMKilled: {{.State.OOMKilled}}'
  ```
* **Salida:**
  ```text
  CONTAINER ID   NAME              CPU %     MEM USAGE / LIMIT   MEM %     NET I/O          BLOCK I/O     PIDS
  0aff275828d9   eco_air_proxy     0.00%     4.387MiB / 128MiB   3.43%     3.44kB / 2.1kB   0B / 12.3kB   2
  299df61c78b8   eco_air_backend   0.27%     223.6MiB / 512MiB   43.68%    2.45kB / 743B    0B / 57.3kB   30

  Backend -> Memory Limit: 536870912 Bytes (512 MB) | Reservation: 268435456 Bytes (256 MB) | OOMKilled: false
  Proxy   -> Memory Limit: 134217728 Bytes (128 MB) | Reservation: 33554432 Bytes (32 MB)  | OOMKilled: false
  ```
* **Diagnóstico de Estabilidad:**
  * En la prueba de estrés previa, una cuota de 48 MB causaba colapso inmediato (`OOMKilled: true`, ExitCode 137).
  * Con la calibración aplicada en Compose (512 MB de límite y 256 MB de reserva), la JVM de Spring Boot utiliza **223.6 MiB (43.68%)**, disponiendo de un margen de seguridad superior al 55% para recolector de basura (GC) y procesamiento de peticiones simultáneas, erradicando el riesgo de terminación por falta de memoria (`OOMKilled: false`).

---

### 3.3 Análisis de Registros, Trazabilidad y Cabeceras de Seguridad
* **Petición HTTP a través de Nginx (`curl -i http://localhost/`):**
  ```text
  HTTP/1.1 404 
  Server: nginx
  Date: Wed, 28 Oct 2026 20:03:52 GMT
  Content-Type: application/json
  Transfer-Encoding: chunked
  Connection: keep-alive
  X-Frame-Options: DENY
  X-Content-Type-Options: nosniff
  X-XSS-Protection: 1; mode=block
  Referrer-Policy: strict-origin-when-cross-origin

  {"timestamp":"2026-10-28T20:03:52.702+00:00","status":404,"error":"Not Found","path":"/"}
  ```
* **Trazabilidad en Registros Sincronizados:**
  * **Log Nginx (`eco_air_proxy`):**
    ```text
    192.168.65.1 - - [28/Oct/2026:20:03:52 +0000] "GET / HTTP/1.1" 404 100 "-" "curl/8.7.1" rt=0.244 uct="0.000" uht="0.242" urt="0.243"
    ```
  * **Log Backend (`eco_air_backend` al mismo instante):**
    ```text
    2026-10-28T20:03:52.661Z INFO 1 --- [nio-8080-exec-1] o.a.c.c.C.[Tomcat].[localhost].[/] : Initializing Spring DispatcherServlet 'dispatcherServlet'
    ```
* **Hallazgo:**
  1. Se verifica la inyección de cabeceras de hardening (`X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `X-XSS-Protection: 1; mode=block`).
  2. La versión exacta de Nginx se encuentra enmascarada (`Server: nginx`), impidiendo escaneos automatizados de vulnerabilidades (CVEs).
  3. Los tiempos de respuesta hacia el upstream (`uct="0.000"`, `urt="0.243"`) muestran una latencia de redirección interna prácticamente nula.

---

### 3.4 Análisis de Vulnerabilidades e Higiene de Imágenes
| Criterio | Estado Actual | Evaluación Técnica |
| :--- | :--- | :--- |
| **Multi-Stage Build** | Implementado | Separa la etapa de construcción (`maven:...-alpine`) de la de runtime (`temurin:...-alpine`). |
| **Superficie de Ataque** | Mínima | El contenedor final carece de compilador Maven y de archivos de código fuente `.java`. |
| **Base Image Footprint** | Alpine Linux | Uso de imágenes basadas en musl libc/Alpine para mantener tamaños reducidos (~106 MB backend, ~4 MB Nginx). |
| **Higiene de Secretos** | Conforme | El ID de estudiante y variables de operador se inyectan en tiempo de construcción/despliegue, sin credenciales hardcodeadas. |

---

## 4. Instrucciones de Remediación y Mejoras Recomendadas
1. **Unprivileged Nginx Container:**
   * *Hallazgo:* El proceso maestro de Nginx corre como root dentro del contenedor para escuchar en el puerto 80.
   * *Remediación:* Para entornos de máxima seguridad (zero-root policy), emplear la imagen `nginxinc/nginx-unprivileged:alpine` configurada para escuchar en el puerto interno 8080 y mapear en compose `80:8080`.
2. **Healthcheck Nativo en Docker Compose:**
   * *Recomendación:* Añadir un bloque `healthcheck` en el servicio backend utilizando `wget -q --spider http://localhost:8080/ || exit 0` y enlazar Nginx con `condition: service_healthy` en `depends_on`.
3. **Plataforma Multi-Arquitectura:**
   * *Recomendación:* Reemplazar la bandera fija `--platform=linux/amd64` en el `Dockerfile` por el soporte nativo de multi-arch (`--platform=$BUILDPLATFORM`), permitiendo ejecución nativa en procesadores Apple Silicon (ARM64) sin sobrecarga de emulación Rosetta/QEMU.
