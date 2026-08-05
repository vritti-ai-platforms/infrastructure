# The reserved IP id comes from the network layer's state (READ-ONLY).
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "vritti-tfstate"
    key    = "network/terraform.tfstate"
    region = "auto"
    endpoints = {
      s3 = "https://45131bc1e1eb60fabc1b7991b762489f.r2.cloudflarestorage.com"
    }
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_s3_checksum            = true
    use_path_style              = true
  }
}
