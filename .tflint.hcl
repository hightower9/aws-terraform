# TFLint - catches provider-validated problems fmr/validate miss.
# Install: brew install tflint  (then run `tflint --init`)
plugin "aws" {
  enabled = true
  version = "0.33.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

rule "aws_instance_previous_type" {
  enabled = false
}

rule "terraform_standard_module_structure" {
  enabled = false
}

rule "terraform_unused_declarations" {
  enabled = true
}