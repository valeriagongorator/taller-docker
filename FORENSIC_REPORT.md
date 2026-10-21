# Reporte Forense y Auditoría de Seguridad - Eco-Air Backend

## 1. Tabla de Identidad de la Imagen
* **Hash SHA-256 de la Imagen (`docker inspect --format='{{.Id}}' eco-air-backend:1.0.0`):**
  `sha256:cc88427d74141de2973fc03d1863e24cae28a5b0cb4f15e91a95fbc3f89d13be`
* **Variable de Entorno Inyectada (`docker exec eco_air_active env | grep OPERATOR_ID`):**
  `OPERATOR_ID=123456`
* **Consumo Final Calibrado (`docker stats --no-stream eco_air_active`):**
  ```text
  CONTAINER ID   NAME             CPU %     MEM USAGE / LIMIT     MEM %     NET I/O        BLOCK I/O    PIDS
  0714b71cdac2   eco_air_active   0.16%     318.6MiB / 7.748GiB   4.02%     1.3kB / 126B   0B / 274kB   44