# 🚀 Ultimate Auto-Provisioning Workspace (`install-home`)

Welcome to the central orchestrator of my automated development environment. This repository contains the entry-point script and Ansible playbooks required to turn a completely blank Ubuntu/WSL machine into a fully configured, cryptographically secure, C-compiled Neovim development environment in under 5 minutes.

## 🏗️ The Three-Repository Architecture

To maintain a strict separation of concerns, this infrastructure is split across three distinct repositories:

1. **`install-home` (The Orchestrator):** This repository. It contains the initial `bootstrap.sh` script and the master Ansible runner (`playbook/run.sh` and `playbook/install_home.yml`)[cite: 3].
2. **`.dotfiles` (The Configuration):** Contains all personal user configurations (`zsh`, `tmux`, `nvim`, `awesomewm`) managed seamlessly via GNU Stow.
3. **`ansible` (The Software):** Contains the modular Ansible roles (like `general_settings` and `pre-nvim`) that handle OS-level package management, Rust/Cargo toolchains, and compiling software from source.

---

## ⚡ The One-Liner Installation

To provision a brand new, Day-0 machine (Ubuntu Native or WSL), open a terminal and run:

```bash
curl -sL [https://raw.githubusercontent.com/talife/install-home/main/bootstrap.sh](https://raw.githubusercontent.com/talife/install-home/main/bootstrap.sh) | bash
