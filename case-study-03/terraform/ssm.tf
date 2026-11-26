# AWS Systems Manager — device/node baseline (REQ-NCA-P3-02, REQ-NCA-P3-03)
# Applies a security baseline to all SSM-managed instances (EKS nodes + any enrolled endpoints)

resource "aws_ssm_document" "security_baseline" {
  name            = "${var.project_name}-security-baseline"
  document_type   = "Command"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Innovatech security baseline — applied to all managed nodes"
    mainSteps = [
      {
        action = "aws:runShellScript"
        name   = "EnableFirewall"
        inputs = {
          runCommand = [
            "#!/bin/bash",
            "# Ensure firewall is active",
            "if command -v ufw &>/dev/null; then ufw --force enable; fi",
            "if command -v firewalld &>/dev/null; then systemctl enable --now firewalld; fi"
          ]
        }
      },
      {
        action = "aws:runShellScript"
        name   = "DisableRootLogin"
        inputs = {
          runCommand = [
            "sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config",
            "systemctl reload sshd || true"
          ]
        }
      },
      {
        action = "aws:runShellScript"
        name   = "ApplyOSUpdates"
        inputs = {
          runCommand = [
            "#!/bin/bash",
            "if command -v apt-get &>/dev/null; then apt-get update -y && apt-get upgrade -y; fi",
            "if command -v yum &>/dev/null; then yum update -y; fi"
          ]
        }
      },
      {
        action = "aws:runShellScript"
        name   = "SetPasswordPolicy"
        inputs = {
          runCommand = [
            "# Enforce minimum password length and complexity",
            "if [ -f /etc/security/pwquality.conf ]; then",
            "  sed -i 's/# minlen.*/minlen = 12/' /etc/security/pwquality.conf",
            "  sed -i 's/# dcredit.*/dcredit = -1/' /etc/security/pwquality.conf",
            "fi"
          ]
        }
      }
    ]
  })

  tags = { Name = "${var.project_name}-security-baseline" }
}

# Run the baseline on all managed instances once at deploy time
resource "aws_ssm_association" "baseline" {
  name             = aws_ssm_document.security_baseline.name
  association_name = "${var.project_name}-baseline-association"

  targets {
    key    = "tag:ManagedBy"
    values = ["Terraform"]
  }

  # Re-apply the baseline every week to catch configuration drift
  schedule_expression = "rate(7 days)"

}

# Patch manager — auto-approve and install security patches (REQ-NCA-P3-03)
resource "aws_ssm_patch_baseline" "main" {
  name            = "${var.project_name}-patch-baseline"
  operating_system = "AMAZON_LINUX_2"
  description     = "Auto-approve critical and security patches within 7 days"

  approval_rule {
    approve_after_days = 7
    patch_filter {
      key    = "CLASSIFICATION"
      values = ["Security", "Bugfix", "Enhancement"]
    }
    patch_filter {
      key    = "SEVERITY"
      values = ["Critical", "Important", "Medium"]
    }
  }

  tags = { Name = "${var.project_name}-patch-baseline" }
}

resource "aws_ssm_patch_group" "main" {
  baseline_id = aws_ssm_patch_baseline.main.id
  patch_group = var.project_name
}
