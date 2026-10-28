# Reporte Forense y Auditoría de Seguridad - Eco-Air Backend

## 1. Tabla de Identidad de la Imagen
* **Hash SHA-256 de la Imagen (`docker inspect --format='{{.Id}}' eco-air-backend:1.0.0`):**
  `sha256:cc88427d74141de2973fc03d1863e24cae28a5b0cb4f15e91a95fbc3f89d13be`
* **Variable de Entorno Inyectada (`docker exec eco_air_active env | grep OPERATOR_ID`):**
  `OPERATOR_ID=123456`
* **Consumo Final Calibrado (`docker stats --no-stream eco_air_active`):**
  ```text
  CONTAINER ID   NAME             CPU %     MEM USAGE / LIMIT     MEM %     NET I/O         BLOCK I/O       PIDS
  0714b71cdac2   eco_air_active   0.26%     399.2MiB / 7.748GiB   5.03%     2.41kB / 809B   107MB / 877kB   44
  ```

---

## 2. Reto 2: Auditoría Forense y Comprobación de Vulnerabilidades

### 2.1 Verificación del Desacoplamiento de Capas
**Comando ejecutado:**
```bash
docker history --human --format "table {{.Size}}\t{{.CreatedBy}}" eco-air-backend:1.0.0
```
**Salida de consola:**
```text
SIZE      CREATED BY
0B        ENTRYPOINT ["sh" "-c" "java $JAVA_OPTS -jar …
0B        EXPOSE [8080/tcp]
0B        USER sensor_user
0B        ENV JAVA_OPTS=-XX:+UseContainerSupport -XX:M…
0B        ENV OPERATOR_ID=123456
0B        ARG STUDENT_ID=123456
19.6MB    RUN /bin/sh -c chown -R sensor_user:sensorgr…
19.6MB    COPY /build/target/*.jar app.jar # buildkit
53.2kB    RUN /bin/sh -c addgroup -S sensorgroup && ad…
8.19kB    WORKDIR /app
0B        ENTRYPOINT ["/__cacert_entrypoint.sh"]
12.3kB    COPY --chmod=755 entrypoint.sh /__cacert_ent…
12.3kB    RUN /bin/sh -c set -eux;     echo "Verifying…
141MB     RUN /bin/sh -c set -eux;     ARCH="$(apk --p…
0B        ENV JAVA_VERSION=jdk-17.0.20.1+1
44MB      RUN /bin/sh -c set -eux;     apk add --no-ca…
0B        ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_AL…
0B        ENV PATH=/opt/java/openjdk/bin:/usr/local/sb…
0B        ENV JAVA_HOME=/opt/java/openjdk
0B        CMD ["/bin/sh"]
9.08MB    ADD alpine-minirootfs-3.24.2-x86_64.tar.gz /…
```
**Análisis y Justificación:**
La imagen final de runtime construida con base en `eclipse-temurin:17-jre-alpine` desacopla completamente el SDK de Maven y el compilador. Solo transfiere el artefacto compilado (`app.jar` de 19.6 MB), reduciendo significativamente la superficie de ataque y el peso final del contenedor.

---

### 2.2 Inspección del Proceso del Host (Aislamiento de Privilegios)
**Comando ejecutado:**
```bash
docker top eco_air_active -o pid,user,comm
```
**Salida de consola:**
```text
PID                 USER                COMMAND
661                 10001               java
```
**Evidencia y Análisis:**
El proceso `java` dentro del contenedor se ejecuta bajo el UID **10001** (`sensor_user`), perteneciente al grupo `sensorgroup`. Se demuestra que **no** se ejecuta con privilegios de `root` (UID 0), previniendo ataques de escalada de privilegios o escapes hacia el kernel del host.

---

### 2.3 Test de Penetración: Comprobación de Inmutabilidad de Runtime
**Comando ejecutado:**
```bash
docker exec eco_air_active touch /etc/crontab_fake
```
**Salida de consola:**
```text
touch: cannot touch '/etc/crontab_fake': Permission denied
```
**Evidencia y Análisis:**
Al intentar escribir un archivo dentro de directorios del sistema operativo (`/etc`), el kernel de Linux rechaza la acción con `Permission denied` gracias al principio de mínimo privilegio impuesto por el usuario `sensor_user` (UID 10001) y la inmutabilidad de las capas base.

---

### 2.4 Auditoría de Artefactos de Desarrollo
**Comandos ejecutados:**
```bash
docker exec eco_air_active which mvn
docker exec eco_air_active find / -name "*.java" 2>/dev/null
```
**Salidas de consola:**
```text
mvn: not found
(Salida vacía: sin archivos .java en el contenedor de producción)
```
**Evidencia y Análisis:**
Se verifica la ausencia de la herramienta Maven (`mvn`) y de archivos de código fuente (`*.java`). Esto certifica que el entorno de producción no expone propiedad intelectual ni herramientas de compilación que faciliten explotación in-situ por parte de atacantes.

---

## 3. Reto 3: Calibración de cgroups y Captura del Asesino OOM

### 3.1 Inducción del Colapso por Memoria (OOMKilled)
Se arrancó un contenedor con cuota insuficiente de memoria (48 MB):
```bash
docker run -d --name eco_air_crash -m 48m eco-air-backend:1.0.0
sleep 10
docker inspect eco_air_crash --format='Status: {{.State.Status}} | ExitCode: {{.State.ExitCode}} | OOMKilled: {{.State.OOMKilled}}'
```
**Salida de consola:**
```text
Status: exited | ExitCode: 137 | OOMKilled: true
```
**Análisis:**
El subsistema de cgroups de memoria del kernel interceptó la ejecución cuando la JVM intentó superar los 48 MB requeridos para la carga de clases y memoria nativa de Spring Boot. El proceso fue eliminado de forma fulminante por el OOM Killer con señal `SIGKILL` (ExitCode 137 = 128 + 9), protegiendo la estabilidad del nodo anfitrión.

---

### 3.2 Calibración Iterativa del Límite Operativo Mínimo

Se sometió el artefacto a pruebas iterativas variando la cuota `-m` para encontrar el umbral óptimo:

| Cuota `-m` | Estado | Tiempo de Inicio | Consumo de Memoria (`stats`) | Comportamiento |
| :--- | :--- | :--- | :--- | :--- |
| **48m** | `exited (137)` | N/A | Excedido | Colapso fulminante por OOM Killer. |
| **128m** | `running` | 7.33 s | 127.1 MiB / 128 MiB (**99.32%**) | Crítico y riesgoso. Al borde del colapso bajo tráfico. |
| **256m** | `running` | 3.75 s | 217.8 MiB / 256 MiB (**85.07%**) | Mínimo viable. Inicia en < 15 s, pero con poco margen para GC. |
| **384m** | `running` | 3.62 s | 213.9 MiB / 384 MiB (**55.69%**) | **Umbral Óptimo Calibrado**. Rápido, estable y con 45% de margen. |
| **512m** | `running` | 3.99 s | 236.2 MiB / 512 MiB (**46.13%**) | Holgado para producción con picos intensivos de tráfico. |

#### Comprobación de Arranque (< 15 segundos):
**Comando:**
```bash
docker logs --timestamps eco_air_active | grep "Started EcoAirApplication"
```
**Salida:**
```text
2026-10-22T21:23:06.247588595Z 2026-10-22T21:23:06.247Z  INFO 1 --- [           main] com.ecoair.EcoAirApplication             : Started EcoAirApplication in 5.049 seconds (process running for 6.759)
```

#### Profiling Calibrado Estable (Umbral Óptimo 384 MB):
```bash
docker stats --no-stream eco_test_384m
```
```text
CONTAINER ID   NAME            CPU %     MEM USAGE / LIMIT   MEM %     NET I/O       BLOCK I/O   PIDS
16e11339b54c   eco_test_384m   0.35%     213.9MiB / 384MiB   55.69%    872B / 126B   0B / 0B     30
```