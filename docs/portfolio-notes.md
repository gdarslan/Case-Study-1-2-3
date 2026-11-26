# Portfolio provenance and publication notes

| Phase | Source |
| --- | --- |
| CS1 | March 2026 historical GitHub snapshot and the phase-one report. |
| CS2 | May 2026 repository implementation and supplied archives; network, architecture and test reports. |
| CS3 | Final local archive and its tracked June 2026 Git commit; cost, test and reflection reports. The Terraform files were recovered from the embedded Git history. |

The phase folders preserve the progression of the semester. Reports summarize the historical evidence honestly, including incomplete and blocked tests. Original Word reports are not published; selected original screenshots have been cropped to omit unrelated identifiers and private browser/workstation details.

## Portfolio revision

- Restored CS1 as a separate source snapshot; moved CS2 out of the root directory and preserved CS3.
- Removed empty command artefacts, redundant generated archives and alert logs from the current working tree; Git history was not rewritten.
- Used input variables for credentials, private configuration, trusted ingress ranges and account-specific state settings.
- Moved original cloud deployment pipelines and the CS3 AWS deployment script into inactive reference folders; only offline regression checks run in GitHub Actions.
- Hardened SOAR bearer-token authentication, alert input validation, HTTPS listener configuration, least-scope Lambda invocation, safe email formatting and archive key uniqueness.
- Added demo HR administrator/read-only authorization, safe DOM rendering, input validation, database network policies and an idempotent local deployment helper.
- Added local regression checks for authentication and alert routing. These checks do not demonstrate a live AWS, Kubernetes or database deployment.

Keep the historical results separate from this later maintenance revision. The repository is an educational portfolio; cloud deployments need review of IAM policies, costs, credentials, TLS, monitoring and account restrictions. Do not use real employee data. Existing history may contain historical credentials; rotate any that were ever used and review history deliberately before further public distribution.
