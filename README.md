# Eco-Air Backend - Contenerización Segura, Auditoría Forense y Orquestación

![Docker](https://img.shields.io/badge/Docker-24.0+-2496ED?style=for-the-badge&logo=docker&logoColor=white)
![Docker Compose](https://img.shields.io/badge/Docker_Compose-v2+-2496ED?style=for-the-badge&logo=docker&logoColor=white)
![Nginx](https://img.shields.io/badge/Nginx-Alpine-009639?style=for-the-badge&logo=nginx&logoColor=white)
![Java](https://img.shields.io/badge/Java-17-ED8B00?style=for-the-badge&logo=openjdk&logoColor=white)
![Spring Boot](https://img.shields.io/badge/Spring_Boot-3.2.0-6DB33F?style=for-the-badge&logo=spring-boot&logoColor=white)
![Security](https://img.shields.io/badge/Security-Hardened-green?style=for-the-badge&logo=shield)

Este repositorio contiene la arquitectura de contenerización, seguridad de runtime, pruebas de estrés de cgroups y orquestación multicapa para el sistema ambiental crítico **Eco-Air Backend**.

El proyecto implementa una estrategia de **Defensa en Profundidad**: compilación multietapa (*Multi-Stage Build*), ejecución bajo usuario no privilegiado (*Zero-Root*), control estricto de recursos de hardware (*cgroups*), y un servidor proxy inverso **Nginx** como escudo perimetral con cabeceras de *hardening* y volumen inmutable de solo lectura.

---

## 🏛️ Arquitectura del Sistema

```text
                    [ Tráfico Exterior / Cliente ]
                                  │ (Puerto 80)
                                  ▼
┌────────────────────────────────────────────────────────────────────────┐
│ Red Bridge Privada: app-network                                        │
│                                                                        │
│  ┌───────────────────────────────┐     (proxy_pass: 8080)              │
│  │ eco_air_proxy (Nginx Alpine)  │ ────────────────────────────┐       │
│  │ • Expone puerto 80 al host    │                             │       │
│  │ • Hardening HTTP Headers      │                             ▼       │
│  │ • Configuración :ro (inmutable│                 ┌──────────────────┐│
│  │ • server_tokens off           │                 │ eco_air_backend  ││
│  └───────────────────────────────┘                 │ (Spring Boot 3)  ││
│                                                    │ • Puerto 8080    ││
│                                                    │   (Solo interno) ││
│                                                    │ • UID: 10001     ││
│                                                    │ • RAM: 512M/256M ││
│                                                    └──────────────────┘│
└────────────────────────────────────────────────────────────────────────┘
```

---

## 📂 Estructura del Repositorio

```plaintext
taller-docker/
├── .dockerignore              # Exclusión de archivos innecesarios del contexto de build
├── Dockerfile                 # Construcción multietapa (Builder + Runtime Alpine)
├── docker-compose.yml         # Orquestación de backend y proxy con cuotas cgroups
├── pom.xml                    # Configuración del proyecto Maven y dependencias
├── audit_session.log          # Registro crudo de terminal con marcas de tiempo (script)
├── FORENSIC_REPORT.md         # Reporte de evidencias forenses, penetración y cgroups
├── AUDIT_COMPOSE_NGINX.md     # Auditoría técnica de Compose, Nginx y trazabilidad
├── nginx/
│   └── nginx.conf             # Configuración de Nginx (Reverse Proxy y Hardening)
└── src/                       # Código fuente Java de la aplicación Spring Boot
```

---

## 🛠️ Retos Técnicos Implementados

### 1. Reto 1: Construcción Multietapa y Reducción de Huella
* **Etapa 1 (Builder):** `maven:3.9.6-eclipse-temurin-17-alpine`.
  * Optimización de caché: se copia `pom.xml` y se ejecuta `mvn dependency:go-offline -B` antes de transferir `src/`, asegurando que cambios de código no re-descarguen librerías.
  * Inyección de identidad en tiempo de compilación: `ARG STUDENT_ID="123456"`.
* **Etapa 2 (Runtime):** `eclipse-temurin:17-jre-alpine`.
  * Creación del usuario no privilegiado: `sensor_user` con UID `10001` y grupo `sensorgroup`.
  * Asignación de permisos al directorio `/app` y cambio al usuario antes del `ENTRYPOINT`.
  * Opciones ergonómicas de JVM para contenedores:
    ```bash
    ENV JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"
    ```
  * Desacoplamiento total: la imagen final pesa solo **106 MB**, excluyendo el compilador Maven y el código fuente.

---

### 2. Reto 2: Auditoría Forense y Comprobación de Vulnerabilidades
* **Aislamiento de Privilegios (`docker top`):**
  Se verifica que el proceso `java` corre bajo el UID **10001** y no como `root` (UID 0), bloqueando ataques de escalada hacia el host.
  ```text
  PID                 USER                COMMAND
  661                 10001               java
  ```
* **Test de Penetración / Inmutabilidad de Runtime:**
  Al intentar crear una tarea maliciosa en `/etc/crontab_fake`:
  ```bash
  docker exec eco_air_active touch /etc/crontab_fake
  # Salida: touch: cannot touch '/etc/crontab_fake': Permission denied
  ```
* **Higiene de Artefactos de Desarrollo:**
  * `which mvn` $\rightarrow$ No encontrado.
  * `find / -name "*.java"` $\rightarrow$ 0 archivos encontrados.

---

### 3. Reto 3: Calibración de cgroups y Captura del OOM Killer
* **Captura del Asesino OOM (48 MB):**
  Al limitar el contenedor a 48 MB, el kernel de Linux intercepta el desbordamiento de la JVM y elimina el proceso con señal `SIGKILL`:
  ```text
  Status: exited | ExitCode: 137 | OOMKilled: true
  ```
* **Calibración Iterativa de Memoria:**

| Cuota `-m` | Estado | Tiempo de Arranque | Consumo (`stats`) | Diagnóstico |
| :---: | :---: | :---: | :---: | :--- |
| **48 MB** | Exited (137) | N/A | Excedido | Colapso inmediato por OOM Killer. |
| **128 MB** | Running | 7.33 s | 127.1 MiB (**99.32%**) | Crítico y vulnerable bajo tráfico. |
| **256 MB** | Running | 3.75 s | 217.8 MiB (**85.07%**) | Mínimo viable ($< 15$ s), poco margen de GC. |
| **384 MB** | Running | 3.62 s | 213.9 MiB (**55.69%**) | **Umbral Óptimo Calibrado** (45% de margen libre). |
| **512 MB** | Running | 3.99 s | 236.2 MiB (**46.13%**) | Holgado para producción con picos intensivos. |

---

### 4. Orquestación con Nginx y Docker Compose
* **Proxy Inverso Seguro:** Nginx redirige el tráfico exterior al backend mediante `proxy_pass http://backend_nodes;`.
* **Hardening Perimetral:**
  * Ocultamiento de versión: `server_tokens off;`
  * Cabeceras inyectadas: `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `X-XSS-Protection: 1; mode=block`.
* **Inmutabilidad de Configuración:** Montaje del volumen en modo solo lectura (`:ro`), impidiendo escritura en caliente:
  ```bash
  docker exec eco_air_proxy touch /etc/nginx/nginx.conf
  # Salida: touch: /etc/nginx/nginx.conf: Read-only file system
  ```
* **Aislamiento de Red:** El backend usa `expose: "8080"` (sin mapeo en el host), garantizando que nadie pueda evadir el proxy Nginx.
* **Trazabilidad:** Logs sincronizados al mismo milisegundo entre Nginx y el `DispatcherServlet` de Spring Boot con tiempos de upstream de $0.000$ ms.

---

## 🚀 Despliegue Rápido Paso a Paso

### Prerrequisitos
* Docker Engine 24+ y Docker Compose v2+ activos.

### 1. Clonar el Repositorio
```bash
git clone https://github.com/valeriagongorator/taller-docker.git
cd taller-docker
```

### 2. Construir e Iniciar los Servicios
```bash
docker compose up --build -d
```

### 3. Verificar el Estado de los Contenedores
```bash
docker compose ps
```

### 4. Comprobar la Conectividad a través del Proxy
```bash
# Healthcheck directo de Nginx
curl -i http://localhost/proxy-health

# Petición redirigida al backend Spring Boot
curl -i http://localhost/
```

### 5. Monitorear Consumo de Recursos en Vivo
```bash
docker stats --no-stream
```

### 6. Detener los Servicios
```bash
docker compose down
```

---

## 📋 Informes Forenses Disponibles
* [FORENSIC_REPORT.md](FORENSIC_REPORT.md): Reporte con firmas SHA-256, inspección forense de privilegios y pruebas cgroups.
* [AUDIT_COMPOSE_NGINX.md](AUDIT_COMPOSE_NGINX.md): Auditoría completa de seguridad perimetral, volúmenes `:ro`, cuotas y trazabilidad de logs.

---

## 👤 Autora
* **Valeria Estefanía Góngora Torres**
* Repositorio: [valeriagongorator/taller-docker](https://github.com/valeriagongorator/taller-docker)
