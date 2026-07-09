#!/bin/bash

# 1. Prompt for your password once to cache credentials
if ! sudo -n true 2>/dev/null; then
  echo "Sudo password required for temporary sudoers entry"
  sudo -v
fi

# 2. Create a temporary sudoers file granting passwordless access
sudoers_tmp="/etc/sudoers.d/provision-tmp-$$"
sudo tee "$sudoers_tmp" > /dev/null <<< "$USER ALL=(ALL) NOPASSWD: ALL"
sudo chmod 0440 "$sudoers_tmp"

# 3. SET THE TRAP: Ensure the temp file is ALWAYS deleted upon exit
trap "sudo rm -f '$sudoers_tmp' 2>/dev/null" EXIT INT TERM

# 4. Run your playbook (no -K needed!)
ansible-playbook install_home.yml -c local

