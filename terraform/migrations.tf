# Old count-based resources are now the for_each resources
moved {
  from = proxmox_virtual_environment_vm.worker[0]
  to   = proxmox_virtual_environment_vm.worker["worker-1"]
}
moved {
  from = proxmox_virtual_environment_vm.worker[1]
  to   = proxmox_virtual_environment_vm.worker["worker-2"]
}
moved {
  from = proxmox_virtual_environment_vm.worker[2]
  to   = proxmox_virtual_environment_vm.worker["worker-3"]
}
moved {
  from = proxmox_virtual_environment_vm.worker[3]
  to   = proxmox_virtual_environment_vm.worker["worker-4"]
}

moved {
  from = data.talos_machine_configuration.worker[0]
  to   = data.talos_machine_configuration.worker["worker-1"]
}
moved {
  from = data.talos_machine_configuration.worker[1]
  to   = data.talos_machine_configuration.worker["worker-2"]
}
moved {
  from = data.talos_machine_configuration.worker[2]
  to   = data.talos_machine_configuration.worker["worker-3"]
}
moved {
  from = data.talos_machine_configuration.worker[3]
  to   = data.talos_machine_configuration.worker["worker-4"]
}

moved {
  from = talos_machine_configuration_apply.worker[0]
  to   = talos_machine_configuration_apply.worker["worker-1"]
}
moved {
  from = talos_machine_configuration_apply.worker[1]
  to   = talos_machine_configuration_apply.worker["worker-2"]
}
moved {
  from = talos_machine_configuration_apply.worker[2]
  to   = talos_machine_configuration_apply.worker["worker-3"]
}
moved {
  from = talos_machine_configuration_apply.worker[3]
  to   = talos_machine_configuration_apply.worker["worker-4"]
}