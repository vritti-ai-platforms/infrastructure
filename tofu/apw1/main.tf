# apw1 — an agent-managed core deployment VM. Thin root: all instance/SG logic lives in the shared
# ../modules/excloud-core-vm module; this root only owns apw1's state (key apw1/) and wires its
# reserved IP. Adding another VM = copy these ~6 lines into apw2/ with name = "apw2".
module "vm" {
  source            = "../modules/excloud-core-vm"
  name              = "apw1"
  ip_reservation_id = data.terraform_remote_state.network.outputs.apw1_ip_id
  sg_id             = data.terraform_remote_state.network.outputs.core_sg_id
  ssh_pubkey        = var.SSH_PUBLIC_KEY
}
