# ==========================================
# ETAPA 1: Builder
# ==========================================
FROM --platform=linux/amd64 maven:3.9.6-eclipse-temurin-17-alpine AS builder

WORKDIR /build

# Argumento para inyectar el ID del estudiante en tiempo de build
ARG STUDENT_ID
ENV STUDENT_ID=${STUDENT_ID}

# Aislar descarga de dependencias para aprovechar la caché de Docker
COPY pom.xml .
RUN mvn dependency:go-offline -B

# Copiar el código fuente y empaquetar el .jar omitiendo tests
COPY src ./src
RUN mvn package -DskipTests

# ==========================================
# ETAPA 2: Runtime
# ==========================================
FROM --platform=linux/amd64 eclipse-temurin:17-jre-alpine

WORKDIR /app

# Crear grupo y usuario de sistema sin privilegios
RUN addgroup -S sensorgroup && adduser -S sensor_user -G sensorgroup -u 10001

# Copiar el ejecutable generado desde la etapa de compilación
COPY --from=builder /build/target/*.jar app.jar

# Asignar la titularidad del directorio al usuario no privilegiado
RUN chown -R sensor_user:sensorgroup /app

# Inyectar el ID de estudiante en la variable de entorno solicitada
ARG STUDENT_ID
ENV OPERATOR_ID=${STUDENT_ID}

# Opciones ergonómicas de la JVM para contenedores
ENV JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"

# Cambiar al usuario no privilegiado antes del ENTRYPOINT
USER sensor_user

EXPOSE 8080

ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar"]