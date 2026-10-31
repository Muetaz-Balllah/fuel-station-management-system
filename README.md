# ⛽ Fuel Station Management System

A robust, production-grade full-stack system designed to streamline operations, inventory control, and staff shift management for fuel stations.

---

## 🚀 Tech Stack

- **Backend:** [FastAPI](https://fastapi.tiangolo.com/) (Python) + PostgreSQL / SQLModel
- **Frontend:** [Flutter](https://flutter.dev/) (Cross-platform mobile/desktop application)
- **Database / Cache:** PostgreSQL, Redis
- **Architecture:** Clean Architecture & RESTful APIs

---

## 🌟 Core Features & Modules

### 👨‍💼 Manager Portal
- **Dashboard:** Real-time metrics on daily sales, total current inventory across tanks, and active staff.
- **Tanks & Pumps Management:** Live monitoring of tanks, pumps, individual nozzles (مسدسات), and consumption statistics.
- **Supply & Procurement:** Tracking supply orders, pending deliveries (e.g., Brega Oil Marketing Company), and active supplier logs.
- **Attendance & Shift Tracking:** Detailed tracking of employee assignments to specific pumps, check-in/check-out timestamps, and active status.
- **System Settings:** Station profile configuration, license expiration monitoring, and Role-Based Access Control (RBAC).

### 👷 Operator Portal
- **Shift Operations:** Secure login, opening and closing shifts with initial and final meter readings.
- **Automated Calculations:** System-calculated fuel dispensed, cash collected, and variance/discrepancy (عجوز/زيادة) tracking.
- **Shift History Log:** Personal historical records of past shifts and handovers.

---

## 📂 Project Structure

```text
├── backend/          # FastAPI application, database models, and API endpoints
├── frontend/         # Flutter cross-platform mobile/desktop app
├── docs/             # System documentation and specifications
└── ui-designs/       # UI/UX wireframes, screen flows, and mockups
