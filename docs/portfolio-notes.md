# Portfolio notes and source provenance

| Phase | Source used to document the project |
| --- | --- |
| CS1 | Historical GitHub snapshot (March 2026) and the phase-one report. |
| CS2 | GitHub `main` commit `9e54a86` (23 May 2026); compared against the supplied CS2 archives and architecture, network and test reports. |
| CS3 | Final local archive `Last-One.zip`, Git commit `1cee59b` (23 June 2026), and the cost, validation and reflection reports. The tracked Terraform directory is present in the embedded Git history, but was not included in the ZIP's checked-out working files. |

The three phases are historical implementation snapshots. They are not intended to run as one simultaneous deployment. The separate CS3 source folder reflects the final archive, with the missing tracked Terraform files recovered from its embedded Git history.

## Publication adjustments

- The original CS1/CS2 Git history and CS2 application/Terraform source remain intact.
- The final CS3 source is in `case-study-03/`; local passwords, personal email and account-specific configuration are replaced with placeholders or inputs.
- The historical CS3 CI workflow is in `ci-reference/`, not an active workflow directory.
- The existing CS2 Terraform workflow excludes the CS3 folder, so publishing that snapshot does not trigger the CS2 cloud deployment.
- Original Word reports and screenshots are summarized in public-facing Markdown, avoiding personal information and environment-specific console identifiers.
- Terraform state, generated archives, caches, logs, private configuration and embedded Git history are not included in the new snapshot.
- Test results are historical results from the semester documentation. No new live tests against AWS or Kubernetes were run during this preparation.

## Before further source publication

Review repository visibility and historical source for credentials before publishing or restructuring. If any credentials were previously committed, rotate them; removing credentials in a later commit does not remove them from existing Git history. Account-specific values, local demo credentials, Terraform state, cached provider binaries, generated archives, logs, and any private environment configuration should not be published.

The original Terraform and CI/CD files may create paid cloud resources. Review workflows, plans, IAM permissions, secrets and costs before deploying them. The original diagrams depict proposed architectures in parts; the case-study documents distinguish those proposals from the implementation.
