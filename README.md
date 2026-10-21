# Eco-Air Backend - Contenerización Segura y Auditoría Forense

![Docker](https://img.shields.io/badge/Docker-24.0+-2496ED?style=for-the-badge&logo=docker&logoColor=white)
![Java](https://img.shields.io/badge/Java-17-ED8B00?style=for-the-badge&logo=openjdk&logoColor=white)
![Spring Boot](https://img.shields.io/badge/Spring_Boot-3.2.0-6DB33F?style=for-the-badge&logo=spring-boot&logoColor=white)
![Security](https://img.shields.io/badge/Security-Hardened-green?style=for-the-badge&logo=shield)

Este repositorio contiene la configuración e infraestructura de contenerización para el backend de **Eco-Air**, una aplicación crítica orientada al procesamiento de métricas y alertas ambientales. 

El proyecto fue diseñado bajo estrictos estándares de **hardening**, arquitectura multietapa (*Multi-Stage Build*), aislamiento de privilegios en *runtime* y calibración de recursos de hardware (*cgroups*).

---

## Estructura del Repositorio

```plaintext
taller-docker/
├── .dockerignore          # Exclusión de artefactos no deseados en el contexto
├── Dockerfile             # Construcción multietapa (Builder + Runtime)
├── FORENSIC_REPORT.md     # Reporte detallado de evidencias y pruebas de penetración
├── audit_session.log      # Registro crudo de terminal con marcas de tiempo (script)
├── pom.xml                # Configuración del proyecto Maven y dependencias
└── src/                   # Código fuente Java (Spring Boot)
