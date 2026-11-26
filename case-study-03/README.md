# Case Study 03 — Employee Lifecycle & HR Platform

This folder contains the final CS3 source snapshot from June 2026, including the Terraform files recovered from the original tracked commit.

See [architecture, validation, cost management and limitations](../docs/case-study-03.md).

- `app/` — containerized FastAPI backend and web frontend
- `automation/` — employee onboarding/offboarding and database initialization
- `k8s/` — local Kubernetes deployment and logging manifests
- `terraform/` — AWS support infrastructure and inactive EKS/RDS reference definitions
- `ci-reference/` — historical GitHub Actions pipeline, not an active workflow

Configuration examples use placeholders instead of environment-specific values. Provide your own secret values privately. Review the deployment scripts before running them; `deploy.sh` describes the original managed EKS/RDS approach and is not compatible with the current active Terraform configuration as-is. The historical local demo uses Minikube and in-cluster PostgreSQL. Never use real employee data or deploy the demo publicly without hardening.
