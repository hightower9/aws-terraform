# App configuration lives in SSM Parameter Store under
#   /<project>/<environment>/app/<NAME>
# and is loaded into the container as environment variables at boot
# (cloud-init writes them to an env file). Changing a value takes effect on
# the next instance replacement (or a container restart on the instance).
locals {
  path = "/${var.project}/${var.environment}/app"
}

# Plain settings, managed fully by Terraform.
resource "aws_ssm_parameter" "settings" {
  for_each = var.settings

  name  = "${local.path}/${each.key}"
  type  = "String"
  value = each.value

  tags = var.tags
}

# Secrets: Terraform only creates them with a placeholder so the app can
# boot. Set the real value out-of-band (never in git):
#   aws ssm put-parameter --name /<project>/<env>/app/APP_KEY \
#     --type SecureString --overwrite --value 'base64:...'
# ignore_changes keeps Terraform from reverting it afterwards.
resource "aws_ssm_parameter" "secrets" {
  # Names aren't secret; only the values are.
  for_each = nonsensitive(toset(keys(var.secret_placeholders)))

  name  = "${local.path}/${each.key}"
  type  = "SecureString"
  value = var.secret_placeholders[each.key]

  tags = var.tags

  lifecycle {
    ignore_changes = [value]
  }
}
