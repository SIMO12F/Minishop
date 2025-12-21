# MiniShop (Microservices + Gateway) — Master Thesis Demo

This repository contains a small **microservices-based** demo project called **MiniShop**.

It consists of:
- **product-service** (Products API)
- **order-service** (Orders API)
- **gateway-service** (Gateway / Aggregator API that calls the other services)

The system can run in two ways:
1) **Locally (non-Docker)** using Maven / IntelliJ
2) **With Docker Compose** (all services inside one Docker network)

---

## Architecture (High Level)

- `product-service` provides product data on port **8080**
- `order-service` provides order data on port **8082**
- `gateway-service` provides aggregated endpoints on port **8081** and calls the other two services

Gateway endpoints:
- `/api/products` → forwards to product-service `/products`
- `/api/orders` → forwards to order-service `/orders`
- `/api/summary` → combines both into one JSON response

---

## Requirements

### For running locally
- Java 21+
- Maven (or use `./mvnw` wrapper included in each service)

### For running with Docker
- Docker Desktop (with Docker Compose v2)

---

## Repository Structure

```text
minishop/
├─ product-service/
├─ order-service/
├─ gateway-service/
└─ docker-compose.yml


