# Module provider requirement — pins the correct excloud source (excloud-dev/excloud, NOT the
# default hashicorp/ namespace). No backend here: the calling root owns the state.
terraform {
  required_providers {
    excloud = {
      source  = "excloud-dev/excloud"
      version = "~> 0.2"
    }
  }
}
