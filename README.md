# MiniShop (Microservices + Gateway) — Master Thesis Demo

MiniShop is a small **microservices-based** demo project built with **Spring Boot**.
It is designed as a **minimal but complete** microservices system for a **Master Thesis**.

The project contains **three independent services**:

- **product-service** — Products API
- **order-service** — Orders API
- **gateway-service** — Gateway / Aggregator API that calls the other services

The system can run in **two modes**:

1) **Locally (non-Docker)** using Maven / IntelliJ
2) **With Docker Compose** (all services inside one Docker network)

---

## Architecture (High Level)

- `product-service` runs on **port 8080**
- `order-service` runs on **port 8082**
- `gateway-service` runs on **port 8081**

The **gateway-service** aggregates data from the other two services.

### Gateway Endpoints

- `GET /api/products` → forwards to `product-service` → `/products`
- `GET /api/orders` → forwards to `order-service` → `/orders`
- `GET /api/summary` → calls both services and returns one combined JSON response

---

## Requirements

### Run locally (non-Docker)
- Java **21+**
- Maven **or** Maven Wrapper (`./mvnw`)
- IntelliJ IDEA (optional)

### Run with Docker
- Docker Desktop
- Docker Compose v2

---

## Repository Structure

```text
minishop/
├─ product-service/
├─ order-service/
├─ gateway-service/
└─ docker-compose.yml
```

---

## Run Locally (non-Docker)

⚠️ **Important:**  
When running locally, you need **3 terminals** because the gateway depends on the other two services.

### 1) Start product-service (Terminal 1)

```bash
cd product-service
./mvnw spring-boot:run
```

Test:
- http://localhost:8080/products

### 2) Start order-service (Terminal 2)

```bash
cd order-service
./mvnw spring-boot:run
```

Test:
- http://localhost:8082/orders

### 3) Start gateway-service (Terminal 3)

```bash
cd gateway-service
./mvnw spring-boot:run
```

Test gateway:
- http://localhost:8081/api/products
- http://localhost:8081/api/orders
- http://localhost:8081/api/summary

---

## Run With Docker Compose (Recommended)

### Build JARs

```bash
cd product-service && ./mvnw clean package -DskipTests
cd ../order-service && ./mvnw clean package -DskipTests
cd ../gateway-service && ./mvnw clean package -DskipTests
cd ..
```

### Start services

```bash
docker compose up --build
```

### Test endpoints

- http://localhost:8080/products
- http://localhost:8082/orders
- http://localhost:8081/api/products
- http://localhost:8081/api/orders
- http://localhost:8081/api/summary

### Stop containers

```bash
docker compose down
```

---

## Docker vs Localhost

Inside Docker:
- `http://product-service:8080`
- `http://order-service:8082`

Locally:
- `http://localhost:8080`
- `http://localhost:8082`

---

## Thesis Scope

This project intentionally excludes:
- Databases
- CI/CD
- Kubernetes

Focus:
- Microservices
- Gateway pattern
- Docker & Compose
- Service communication
